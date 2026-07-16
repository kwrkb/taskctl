using System.Globalization;
using System.Security.Principal;
using Taskctl.Model;

namespace Taskctl.Facts;

// 正規化モデルから、検出ルール (data/rules.json) が参照するファクトを算出する。
// 判定は1箇所、プロースはカタログ。値が算出できない場合は null（評価器は null の条件を
// 不成立として扱う＝発火しない側に倒す）。
internal static class TaskFacts
{
    public static Dictionary<string, object?> Compute(
        TaskModel model,
        TaskInfoModel? info,
        DateTime now,
        string? currentSid = null,
        string? currentName = null)
    {
        var facts = new Dictionary<string, object?>(StringComparer.Ordinal);

        // ---- task.* ----
        facts["task.enabled"] = model.Enabled;
        var triggers = model.Triggers;
        var enabledTriggers = triggers.Where(t => t.Enabled).ToList();
        facts["task.has_triggers"] = triggers.Count > 0;
        facts["task.has_enabled_trigger"] = enabledTriggers.Count > 0;
        // 時刻ベースのトリガー（次回実行時刻を持つのが正常なもの）。
        // ログオン/ブート/イベントトリガーのタスクは NextRunTime が無くて正常なので区別する。
        facts["task.has_enabled_time_trigger"] = enabledTriggers.Any(t => t.Type is "TimeTrigger" or "CalendarTrigger");

        // ---- trigger.* ----
        // all_past_end_boundary: 全トリガーが終了境界を持ち、かつ全て過去。1つでも境界なし/未来なら false。
        bool allPast = false;
        if (triggers.Count > 0)
        {
            allPast = true;
            foreach (var t in triggers)
            {
                if (string.IsNullOrWhiteSpace(t.EndBoundary)) { allPast = false; break; }
                var end = ParseDateTime(t.EndBoundary);
                if (end is null || end > now) { allPast = false; break; }
            }
        }
        facts["trigger.all_past_end_boundary"] = allPast;

        // ---- info.*（実行情報が取れないタスクでは null のまま＝関連ルールは発火しない） ----
        facts["info.next_run_set"] = null;
        facts["info.never_run"] = null;
        facts["info.days_since_last_run"] = null;
        if (info is not null)
        {
            // 未実行/未予定のとき LastRunTime / NextRunTime は null か 1999-11-30 のセンチネルで返る
            facts["info.next_run_set"] = info.NextRunTime is { Year: >= 2000 };
            bool neverRun = info.LastRunTime is not { Year: >= 2000 };
            facts["info.never_run"] = neverRun;
            if (!neverRun)
            {
                facts["info.days_since_last_run"] = (double)(int)Math.Floor((now - info.LastRunTime!.Value).TotalDays);
            }
        }

        // ---- principal.* ----
        facts["principal.is_service_account"] = false;
        facts["principal.logon_type_interactive"] = false;
        facts["principal.is_current_user"] = false;
        if (model.Principal is not null)
        {
            var userId = model.Principal.UserId ?? "";
            facts["principal.is_service_account"] =
                userId is "S-1-5-18" or "S-1-5-19" or "S-1-5-20" ||
                System.Text.RegularExpressions.Regex.IsMatch(userId, @"^(NT AUTHORITY\\)?(SYSTEM|LOCAL SERVICE|NETWORK SERVICE)$",
                    System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            facts["principal.logon_type_interactive"] = model.Principal.LogonType == "InteractiveToken";
            // taskctl を動かしている本人のタスクか。本人のタスクに限れば、taskctl の文脈での
            // パス存在チェックは「タスクが走る文脈」とほぼ一致し、Test-Path の結果を信頼できる。
            facts["principal.is_current_user"] = IsCurrentUser(userId, currentSid, currentName);
        }

        // ---- settings.* ----
        var s = model.Settings;
        facts["settings.disallow_start_if_on_batteries"] = s is not null ? s.DisallowStartIfOnBatteries : null;
        facts["settings.run_only_if_idle"] = s is not null ? s.RunOnlyIfIdle : null;
        facts["settings.run_only_if_network_available"] = s is not null ? s.RunOnlyIfNetworkAvailable : null;
        facts["settings.multiple_instances_parallel"] = s is not null ? s.MultipleInstancesPolicy == "Parallel" : null;

        // ExecutionTimeLimit: ISO 8601 期間。PT0S は「制限なし」を意味する。
        facts["settings.execution_time_limit_set"] = false;
        facts["settings.execution_time_limit_seconds"] = null;
        if (s is not null && !string.IsNullOrWhiteSpace(s.ExecutionTimeLimit))
        {
            try
            {
                var span = System.Xml.XmlConvert.ToTimeSpan(s.ExecutionTimeLimit);
                if (span.TotalSeconds > 0)
                {
                    facts["settings.execution_time_limit_set"] = true;
                    facts["settings.execution_time_limit_seconds"] = (double)(int)span.TotalSeconds;
                }
            }
            catch (FormatException) { /* 解釈できない期間表記は無視する */ }
        }

        return facts;
    }

    // UserId は SID（S-1-5-21-...）でもアカウント名（DOMAIN\user）でも入りうるため両方見る。
    // 判定できない場合は false（＝存在チェックを走らせない側に倒す）。
    public static bool IsCurrentUser(string? userId, string? currentSid, string? currentName)
    {
        if (string.IsNullOrWhiteSpace(userId)) return false;

        if (currentSid is null || currentName is null)
        {
            try
            {
                using var identity = WindowsIdentity.GetCurrent();
                currentSid = identity.User?.Value;
                currentName = identity.Name;
            }
            catch
            {
                return false;
            }
        }
        if (currentSid is null || currentName is null) return false;

        var id = userId.Trim();
        if (id == currentSid) return true;
        if (string.Equals(id, currentName, StringComparison.OrdinalIgnoreCase)) return true;

        // ドメイン修飾なしのアカウント名（"user" と "HOST\user"）
        if (!id.StartsWith("S-1-", StringComparison.Ordinal))
        {
            var leaf = currentName.Contains('\\') ? currentName[(currentName.LastIndexOf('\\') + 1)..] : currentName;
            return string.Equals(id, leaf, StringComparison.OrdinalIgnoreCase);
        }
        return false;
    }

    private static DateTime? ParseDateTime(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        if (DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dto))
        {
            return dto.LocalDateTime;
        }
        return null;
    }
}
