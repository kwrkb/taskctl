using System.Text.Json;
using Taskctl.Cli;

namespace Taskctl.Cli.Tests;

// explain の統合テスト（in-process で Run を呼び、出力契約を検証する）。
// Console.SetOut はプロセス全域のため、コンソールを差し替えるテストは同一コレクションで直列化する。
[Collection("console-redirection")]
public class ExplainCommandTests
{
    private static (string stdout, string stderr, int exitCode) Run(CliArgs args)
    {
        var swOut = new StringWriter();
        var swErr = new StringWriter();
        var (origOut, origErr) = (Console.Out, Console.Error);
        Console.SetOut(swOut);
        Console.SetError(swErr);
        try
        {
            var exit = ExplainCommand.Run(args);
            return (swOut.ToString(), swErr.ToString(), exit);
        }
        finally
        {
            Console.SetOut(origOut);
            Console.SetError(origErr);
        }
    }

    [Fact]
    public void 引数が無ければ終了コード1()
    {
        var (_, stderr, exit) = Run(new CliArgs { Command = "explain", Lang = "ja" });
        Assert.Equal(1, exit);
        Assert.Contains("結果コードを指定", stderr);
    }

    [Fact]
    public void JSON出力は契約フィールドを持ち日本語を生のUTF8で出す()
    {
        var (stdout, _, exit) = Run(new CliArgs { Command = "explain", Positional = "0x00000002", Lang = "ja", Json = true });
        Assert.Equal(0, exit);

        // 生の UTF-8（\uXXXX にエスケープしない）で出す契約（VISION: PowerShell 版の ConvertTo-Json と同じ）
        Assert.DoesNotContain("\\u", stdout);

        var json = JsonDocument.Parse(stdout);
        var root = json.RootElement;
        Assert.Equal("0x00000002", root.GetProperty("code").GetString());
        Assert.Equal("ERROR_FILE_NOT_FOUND", root.GetProperty("constant").GetString());
        Assert.True(root.GetProperty("is_failure").GetBoolean());
        Assert.Equal("ja", root.GetProperty("locale").GetString());
        Assert.Contains("ファイル", root.GetProperty("message").GetString());
    }

    [Fact]
    public void テキスト出力は三点セットを日本語で出す()
    {
        var (stdout, _, exit) = Run(new CliArgs { Command = "explain", Positional = "2", Lang = "ja" });
        Assert.Equal(0, exit);
        Assert.Contains("これは何", stdout);
        Assert.Contains("次の一手", stdout);
        Assert.Contains("ERROR_FILE_NOT_FOUND", stdout);
    }

    [Fact]
    public void 解釈できないコードでも落ちずに終了コード0()
    {
        // explain は辞書的コマンド。未知コードも「翻訳表に無い」という答えを返す
        var (stdout, _, exit) = Run(new CliArgs { Command = "explain", Positional = "0x00002EE7", Lang = "ja" });
        Assert.Equal(0, exit);
        Assert.Contains("翻訳表に無い", stdout);
    }
}
