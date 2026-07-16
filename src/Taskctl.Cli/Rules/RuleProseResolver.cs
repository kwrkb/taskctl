using Taskctl.Data;
using Taskctl.I18n;

namespace Taskctl.Rules;

// ルール所見（言語非依存）へ、カタログのプロースを付ける。
internal static class RuleProseResolver
{
    public static void Resolve(RuleFinding finding, string locale)
    {
        var catalog = DataStore.GetCatalog(locale);
        if (!catalog.Rules.TryGetValue(finding.RuleId, out var prose))
        {
            // coverage テストで防ぐが、万一欠けても空文字は出さない（rule id を出す）
            prose = new CatalogProse { Meaning = finding.RuleId, Cause = null, Next = finding.RuleId };
        }

        // 実値が無い場合の既定。<...> 表記は非翻訳で、「ここに自分の値を入れる」ことが
        // 日英どちらでも分かる。空文字は絶対に出さない。
        var values = new Dictionary<string, string>(finding.Values, StringComparer.Ordinal);
        AddDefault(values, "task", "<TASKNAME>");
        AddDefault(values, "task_args", "-TaskName '<TASKNAME>'");
        AddDefault(values, "task_regex", "<TASKNAME>");
        AddDefault(values, "command", "<COMMAND>");
        AddDefault(values, "workdir", "<WORKDIR>");

        finding.Meaning = prose.Meaning is not null ? PlaceholderExpander.Expand(prose.Meaning, catalog, values) : null;
        finding.Cause = prose.Cause is not null ? PlaceholderExpander.Expand(prose.Cause, catalog, values) : null;
        finding.Next = prose.Next is not null ? PlaceholderExpander.Expand(prose.Next, catalog, values) : null;
    }

    private static void AddDefault(Dictionary<string, string> map, string key, string defaultValue)
    {
        if (!map.TryGetValue(key, out var existing) || string.IsNullOrWhiteSpace(existing))
        {
            map[key] = defaultValue;
        }
    }
}
