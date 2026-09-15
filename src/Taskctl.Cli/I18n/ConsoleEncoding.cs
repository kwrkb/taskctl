using System.Text;

namespace Taskctl.I18n;

// VISION: 出力は UTF-8 を既定。ただし Windows コンソールの既定コードページ (CP932) で
// 化けうる。ここでは「化けない側へ寄せる」ことだけ行い、リダイレクト中に失敗しても握りつぶす。
// C# の Console.OutputEncoding は UTF-8 に変えられる（chcp と等価。プロセス限定）。
internal static class ConsoleEncoding
{
    public static void EnsureUtf8()
    {
        try
        {
            if (Console.OutputEncoding.CodePage != 65001)
            {
                Console.OutputEncoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
            }
        }
        catch
        {
            // 何かに失敗しても致命的ではない（例: リダイレクト中）
        }
    }

    // 文字化けの恐れがある環境（非 UTF-8 コンソール & 非 ASCII を出す言語）で対処法を返す。
    // .NET 10 のコンソール既定は UTF-8 のためほぼ発火しないが、CP932 な cmd 経由の起動などで有効。
    // commandExample には呼び出し元のコマンド形（"doctor" / "explain <code>" 等）を渡す。
    // 実行中のコマンドと違う例を出すと、そのまま貼っても目的の出力が出ず不親切なため。
    public static string? GetEncodingHint(string locale, string commandExample)
    {
        if (locale == "en") return null;

        bool isUtf8 = false;
        try { isUtf8 = Console.OutputEncoding.CodePage == 65001; } catch { }
        if (isUtf8) return null;

        return BuildHint(locale, commandExample);
    }

    // 環境判定と文言生成を分ける（文言だけは UTF-8 コンソール上のテストからも検証できる）。
    internal static string? BuildHint(string locale, string commandExample)
    {
        if (locale != "ja") return null;

        const string chcp = "chcp 65001";
        var rerun = $"taskctl {commandExample} --lang en";
        int col = Math.Max(chcp.Length, rerun.Length) + 2;

        return "文字化けする場合は、次のいずれかをお試しください:\n"
            + $"  {chcp.PadRight(col)}# コンソールを UTF-8 にする\n"
            + $"  {rerun.PadRight(col)}# 英語で表示する";
    }
}
