using System.ComponentModel;
using System.Globalization;
using System.Text.RegularExpressions;
using Taskctl.Data;
using Taskctl.Findings;
using Taskctl.I18n;

namespace Taskctl.Codes;

// 結果コードを所見（Finding）へ解決する。explain と doctor が共有する中核の純粋関数。
// 3段の解決:
//   1. レジストリに完全一致       -> 事実（レジストリ）+ プロース（カタログ）
//   2. 0x8007xxxx (HRESULT_FROM_WIN32) -> 下位16bit を Win32 エラーとして案内
//   3. それ以外                   -> 「不明」。断定せず、非ゼロなら失敗扱いにして調査を促す
internal static partial class ResultCodeResolver
{
    [GeneratedRegex(@"^0x8007([0-9A-F]{4})$")]
    private static partial Regex HresultFromWin32Pattern();

    public static Finding Resolve(string code, string locale, IReadOnlyDictionary<string, string>? values = null)
    {
        var normalized = ResultCode.Parse(code);
        var registry = DataStore.GetRegistry();
        var catalog = DataStore.GetCatalog(locale);

        // 完全一致
        var entry = registry.Codes.FirstOrDefault(c => string.Equals(c.Key, normalized.Key, StringComparison.OrdinalIgnoreCase));
        Finding finding;
        if (entry is not null)
        {
            catalog.Codes.TryGetValue(normalized.Key, out var prose);
            finding = new Finding
            {
                Code = normalized.Key,
                Decimal = normalized.Unsigned,
                Signed = normalized.Signed,
                Constant = entry.Constant,
                Kind = entry.Kind,
                Severity = entry.Severity,
                Rank = entry.NextRank,
                IsFailure = entry.IsFailure,
                MessageKey = normalized.Key,
                IsKnown = true,
                Meaning = prose?.Meaning,
                Cause = prose?.Cause,
                Next = prose?.Next,
            };
        }
        else if (HresultFromWin32Pattern().Match(normalized.Key) is { Success: true } m)
        {
            long win32 = long.Parse(m.Groups[1].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
            var prose = catalog.Fallback.HresultFromWin32;
            finding = new Finding
            {
                Code = normalized.Key,
                Decimal = normalized.Unsigned,
                Signed = normalized.Signed,
                Constant = $"HRESULT_FROM_WIN32({win32})",
                Kind = "system",
                Severity = registry.Fallback.HresultFromWin32.Severity,
                Rank = registry.Fallback.HresultFromWin32.Rank,
                IsFailure = true,
                MessageKey = "fallback.hresult_from_win32",
                IsKnown = false,
                Meaning = prose.Meaning,
                Cause = prose.Cause,
                Next = prose.Next,
                Win32 = win32,
            };
        }
        else
        {
            // 未知のコード。断定しないが、非ゼロなら失敗として扱う（severity/rank も失敗に整合させる）。
            bool isFailure = normalized.Unsigned != 0;
            var prose = catalog.Fallback.Unknown;
            finding = new Finding
            {
                Code = normalized.Key,
                Decimal = normalized.Unsigned,
                Signed = normalized.Signed,
                Constant = null,
                Kind = "app",
                Severity = isFailure ? registry.Fallback.Unknown.Severity : "info",
                Rank = isFailure ? registry.Fallback.Unknown.Rank : "info",
                IsFailure = isFailure,
                MessageKey = "fallback.unknown",
                IsKnown = false,
                Meaning = prose.Meaning,
                Cause = prose.Cause,
                Next = prose.Next,
            };
        }

        // 未知コードには OS の FormatMessage 訳文を補助として添える（AOT でも動く）。
        // カタログを迂回しないため、Meaning に混ぜず OsMessage として分離保持する。
        if (!finding.IsKnown)
        {
            try
            {
                var osMsg = new Win32Exception(finding.Signed).Message;
                if (!string.IsNullOrWhiteSpace(osMsg) &&
                    !osMsg.StartsWith("Unknown error", StringComparison.OrdinalIgnoreCase))
                {
                    finding.OsMessage = osMsg.Trim();
                }
            }
            catch { /* 取れなければ黙って諦める */ }
        }

        // プレースホルダ展開（プロース層のみ。コマンドは非翻訳のままカタログから来る）
        var expandValues = new Dictionary<string, string>(StringComparer.Ordinal);
        if (values is not null) foreach (var kv in values) expandValues[kv.Key] = kv.Value;
        if (finding.Win32.HasValue) expandValues["win32"] = finding.Win32.Value.ToString(CultureInfo.InvariantCulture);

        // 呼び出し側が実値を知らない場合の既定値。<...> 表記は非翻訳で
        // 「ここに自分の値を入れる」ことが日英どちらでも分かる。空文字は絶対に返さない。
        AddDefault(expandValues, "task", "<TASKNAME>");
        AddDefault(expandValues, "task_args", "-TaskName '<TASKNAME>'");
        AddDefault(expandValues, "task_regex", "<TASKNAME>");
        AddDefault(expandValues, "command", "<COMMAND>");

        if (finding.Meaning is not null) finding.Meaning = PlaceholderExpander.Expand(finding.Meaning, catalog, expandValues);
        if (finding.Cause is not null) finding.Cause = PlaceholderExpander.Expand(finding.Cause, catalog, expandValues);
        if (finding.Next is not null) finding.Next = PlaceholderExpander.Expand(finding.Next, catalog, expandValues);

        return finding;
    }

    private static void AddDefault(Dictionary<string, string> map, string key, string defaultValue)
    {
        if (!map.TryGetValue(key, out var existing) || string.IsNullOrWhiteSpace(existing))
        {
            map[key] = defaultValue;
        }
    }
}
