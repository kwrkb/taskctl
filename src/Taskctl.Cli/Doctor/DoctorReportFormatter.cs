using System.Text;
using Taskctl.Data;
using Taskctl.Findings;
using Taskctl.Model;
using Taskctl.Rules;

namespace Taskctl.Doctor;

// doctor のテキストレポートを組み立てる。問題と次の一手を先頭に、一覧は最後。
internal static class DoctorReportFormatter
{
    public static string Format(List<DiagnosisResult> results, string locale, bool deepDive, bool raw)
    {
        var sb = new StringBuilder();

        // 表示は severity で絞る（集計・JSON は全所見を見る）。
        // 走査時: warning 以上の所見だけ。notice（判断＝仕様かもしれない）や info（S_OK 等）まで
        //         並べると本当の問題が埋もれる。
        // 深掘り時: すべて出す（ok = S_OK も含む）。
        var shown = deepDive
            ? DataStore.GetRegistry().Meta.Severities.ToHashSet()
            : new HashSet<string> { "warning", "error" };

        var problem = results.Where(r => r.AcquireError is not null || r.AllFindings().Any(f => shown.Contains(f.Severity))).ToList();
        var severities = results.SelectMany(r => r.AllFindings()).Select(f => f.Severity).ToList();
        int total = results.Count;
        int errors = severities.Count(s => s == "error");
        int warnings = severities.Count(s => s == "warning");
        int notices = severities.Count(s => s == "notice");

        var summaryLine = locale == "ja"
            ? $"走査 {total} タスク: error {errors} / warning {warnings} / notice {notices}"
            : $"Scanned {total} task(s): error {errors} / warning {warnings} / notice {notices}";
        sb.Append(summaryLine).Append('\n');

        // 診断できなかったタスクは黙って落とさない（「問題なし」に見えてしまう）
        int acquireErrors = results.Count(r => r.AcquireError is not null);
        if (acquireErrors > 0)
        {
            var line = locale == "ja"
                ? $"! {acquireErrors} タスクは設定/実行情報を取得できず、診断できていません（下記 ! 行）"
                : $"! {acquireErrors} task(s) could not be read, so they were not diagnosed (see ! lines below)";
            sb.Append(line).Append('\n');
        }
        sb.Append('\n');

        // ---- 問題のあるタスクの診断（先頭に） ----
        foreach (var r in problem)
        {
            sb.Append($"=== {r.FullName}  ({r.State}) ===\n");
            if (r.AcquireError is not null)
            {
                sb.Append($"  ! {r.AcquireError}\n");
            }
            if (raw && r.Model is not null)
            {
                sb.Append(Indent(FormatRawSetting(r.Model, r.Info, locale), 0)).Append('\n');
            }

            foreach (ISeverityFinding f in r.AllFindings().Where(f => shown.Contains(f.Severity)))
            {
                var text = f is Finding finding
                    ? FindingFormatter.Format(finding, locale)
                    : RuleFindingFormatter.Format((RuleFinding)f, locale);
                sb.Append(Indent(text, 2)).Append('\n');
                sb.Append('\n');
            }
        }

        // ---- 一覧（深掘り時は冗長なので出さない） ----
        if (!deepDive && results.Count > 0)
        {
            sb.Append($"--- {(locale == "ja" ? "一覧" : "Tasks")} ---\n");
            sb.Append($"{"State",-10} {"LastResult",-12} {"NextRun",-20} Task\n");
            foreach (var r in results.OrderBy(r => r.FullName, StringComparer.Ordinal))
            {
                string lastResult = r.CodeFinding?.Code
                    ?? (r.Info?.LastTaskResult is { } lr ? $"0x{unchecked((uint)lr):X8}" : "-");
                string nextRun = r.Info?.NextRunTime is { Year: >= 2000 } nr
                    ? nr.ToString("yyyy-MM-dd HH:mm")
                    : "-";
                sb.Append($"{r.State,-10} {lastResult,-12} {nextRun,-20} {r.FullName}\n");
            }
        }

        return sb.ToString().TrimEnd();
    }

    private static string Indent(string text, int width)
    {
        var pad = new string(' ', width);
        return string.Join('\n', text.Split('\n').Select(l => pad + l));
    }

    // 生の設定を表示する（--verbose）。値は加工せずそのまま見せる。
    // 環境変数や相対パスは展開しない。taskctl の文脈で展開すると、
    // タスクが実際に走る文脈での値と食い違い、かえって誤解を生むため。
    private static string FormatRawSetting(TaskModel model, TaskInfoModel? info, string locale)
    {
        bool isJa = locale == "ja";
        var sb = new StringBuilder();
        sb.Append($"  --- {(isJa ? "生の設定" : "Raw settings")} ---\n");

        foreach (var a in model.Actions)
        {
            sb.Append($"    {(isJa ? "操作" : "Action")}: {a.Command} {a.Arguments}".TrimEnd()).Append('\n');
            if (!string.IsNullOrEmpty(a.WorkingDirectory))
            {
                sb.Append($"      {(isJa ? "作業ディレクトリ" : "Working dir")}: {a.WorkingDirectory}\n");
            }
        }
        if (model.Principal is not null)
        {
            sb.Append($"    {(isJa ? "実行ユーザー" : "Principal")}: {model.Principal.UserId} / LogonType={model.Principal.LogonType} / RunLevel={model.Principal.RunLevel}\n");
        }
        foreach (var t in model.Triggers)
        {
            sb.Append($"    {(isJa ? "トリガー" : "Trigger")}: {t.Type} / Enabled={t.Enabled} / Start={t.StartBoundary} / End={t.EndBoundary}\n");
        }
        if (model.Settings is not null)
        {
            var s = model.Settings;
            sb.Append($"    {(isJa ? "設定" : "Settings")}: Enabled={s.Enabled} / ExecutionTimeLimit={s.ExecutionTimeLimit} / MultipleInstancesPolicy={s.MultipleInstancesPolicy}\n");
            sb.Append($"      DisallowStartIfOnBatteries={s.DisallowStartIfOnBatteries} / RunOnlyIfIdle={s.RunOnlyIfIdle} / RunOnlyIfNetworkAvailable={s.RunOnlyIfNetworkAvailable}\n");
        }
        if (info is not null)
        {
            sb.Append($"    {(isJa ? "実行情報" : "Run info")}: LastRunTime={info.LastRunTime} / LastTaskResult={info.LastTaskResult} / NextRunTime={info.NextRunTime}\n");
        }

        return sb.ToString().TrimEnd('\n');
    }
}
