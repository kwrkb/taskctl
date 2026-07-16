using System.Text;
using Taskctl.Data;

namespace Taskctl.Rules;

// ルール所見を人間向けテキストへ。ヘッダはルール ID（grep 可能な安定キー。非翻訳）。
internal static class RuleFindingFormatter
{
    public static string Format(RuleFinding finding, string locale)
    {
        var catalog = DataStore.GetCatalog(locale);
        var sb = new StringBuilder();

        sb.Append('[').Append(finding.Severity).Append("] ").Append(finding.RuleId).Append('\n');
        sb.Append('\n');

        AppendSection(sb, catalog.Headings.Meaning, finding.Meaning ?? "");
        if (!string.IsNullOrEmpty(finding.Cause))
        {
            AppendSection(sb, catalog.Headings.Cause, finding.Cause);
        }
        var rankLabel = catalog.Ranks.TryGetValue(finding.Rank, out var rl) ? rl.Label : finding.Rank;
        AppendSection(sb, $"{catalog.Headings.Next} [{rankLabel}]", finding.Next ?? "");

        return sb.ToString().TrimEnd();
    }

    private static void AppendSection(StringBuilder sb, string heading, string body)
    {
        sb.Append(heading).Append(":\n");
        var trimmed = body.TrimEnd();
        foreach (var line in trimmed.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
        {
            sb.Append("  ").Append(line).Append('\n');
        }
        sb.Append('\n');
    }
}
