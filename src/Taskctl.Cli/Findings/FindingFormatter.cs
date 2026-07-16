using System.Globalization;
using System.Text;
using Taskctl.Data;

namespace Taskctl.Findings;

// 所見を人間向けテキストへ整形する。VISION の型:
//   <Code> (10進 <dec>)  [<CONSTANT>]
//   (kind ラベル)
//
//   これは何:       ...
//   考えられる原因: ...
//   次の一手 [ランク]: ...
// 見出しとランクのラベルはカタログ（プロース層）から。コード値・定数名・コマンドは非翻訳。
internal static class FindingFormatter
{
    public static string Format(Finding finding, string locale, string? title = null)
    {
        var catalog = DataStore.GetCatalog(locale);
        var sb = new StringBuilder();

        // ヘッダ
        sb.Append(finding.Code).Append(" (").Append(finding.Decimal.ToString(CultureInfo.InvariantCulture)).Append(')');
        if (finding.Signed < 0)
        {
            sb.Append(" / ").Append(finding.Signed.ToString(CultureInfo.InvariantCulture));
        }
        if (!string.IsNullOrEmpty(finding.Constant))
        {
            sb.Append("  [").Append(finding.Constant).Append(']');
        }
        if (!string.IsNullOrEmpty(title))
        {
            sb.Insert(0, title + "  ");
        }
        sb.Append('\n');

        if (catalog.Kinds.TryGetValue(finding.Kind, out var kindLabel) && !string.IsNullOrEmpty(kindLabel.Label))
        {
            sb.Append("  (").Append(kindLabel.Label).Append(")\n");
        }
        sb.Append('\n');

        AppendSection(sb, catalog.Headings.Meaning, finding.Meaning ?? "");
        if (!string.IsNullOrEmpty(finding.Cause))
        {
            AppendSection(sb, catalog.Headings.Cause, finding.Cause);
        }

        var rankLabel = catalog.Ranks.TryGetValue(finding.Rank, out var rl) ? rl.Label : finding.Rank;
        var nextHeading = $"{catalog.Headings.Next} [{rankLabel}]";
        AppendSection(sb, nextHeading, finding.Next ?? "");

        // 未知コードのみ、OS の FormatMessage 訳文を末尾に「参考」として付ける。
        // カタログの文言と区別するため見出しを別立てにし、翻訳の正本と混ざらないようにする。
        if (!finding.IsKnown && !string.IsNullOrEmpty(finding.OsMessage))
        {
            var refHeading = locale == "ja" ? "参考 (OS)" : "Reference (OS)";
            AppendSection(sb, refHeading, finding.OsMessage);
        }

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
