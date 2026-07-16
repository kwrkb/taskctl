using System.Globalization;
using System.Text.RegularExpressions;
using Taskctl.Data;

namespace Taskctl.I18n;

// テキスト中の {{snippets.<name>}} と {{<value>}} を展開する。
//   - snippet の中身がさらにプレースホルダを含みうるため、変化が無くなるまで繰り返す
//     （循環参照に備えて回数を上限で打ち切る）
//   - 複数行の値を差し込む場合、2行目以降をプレースホルダ位置のインデントへ揃える
//     （揃えないとコマンドが左端に落ち、コピペ範囲が読み取れなくなる）
//   - 未定義の参照は原文のまま残す（空文字を出さないため。coverage テストで検出する）
internal static partial class PlaceholderExpander
{
    private const int MaxPass = 5;

    // {{name}} または {{namespace.name}} を拾う。名前は英数と _ のみ。
    [GeneratedRegex(@"\{\{(\w+(?:\.\w+)?)\}\}")]
    private static partial Regex PlaceholderPattern();

    public static string Expand(string text, Catalog catalog, IReadOnlyDictionary<string, string> values)
    {
        var current = text;
        for (int i = 0; i < MaxPass; i++)
        {
            var source = current;
            var next = PlaceholderPattern().Replace(source, m =>
            {
                var reference = m.Groups[1].Value;

                string? value;
                if (reference.StartsWith("snippets.", StringComparison.Ordinal))
                {
                    var name = reference.Substring("snippets.".Length);
                    value = catalog.Snippets.TryGetValue(name, out var snippet) ? snippet.TrimEnd() : null;
                }
                else if (values.TryGetValue(reference, out var v))
                {
                    value = v;
                }
                else
                {
                    value = null;
                }

                if (value is null) return m.Value; // 未定義は原文のまま

                var lines = value.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None);
                if (lines.Length <= 1) return value;

                // プレースホルダが載っている行の先頭空白幅を、2行目以降に付ける。
                var lineStart = source.LastIndexOf('\n', Math.Max(0, m.Index - 1)) + 1;
                var lineHead = source.Substring(lineStart, m.Index - lineStart);
                var indent = MeasureLeadingWhitespace(lineHead);
                var sb = new System.Text.StringBuilder();
                sb.Append(lines[0]);
                for (int li = 1; li < lines.Length; li++)
                {
                    sb.Append('\n').Append(indent).Append(lines[li]);
                }
                return sb.ToString();
            });

            if (next == current) return next;
            current = next;
        }
        return current;
    }

    private static string MeasureLeadingWhitespace(string s)
    {
        int i = 0;
        while (i < s.Length && (s[i] == ' ' || s[i] == '\t')) i++;
        return s.Substring(0, i);
    }
}
