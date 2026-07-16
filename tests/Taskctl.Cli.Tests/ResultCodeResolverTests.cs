using Taskctl.Codes;
using Taskctl.Data;
using Taskctl.Findings;

namespace Taskctl.Cli.Tests;

public class ResultCodeResolverTests
{
    [Fact]
    public void VISIONの例0x41303を状態コードとして説明する()
    {
        var f = ResultCodeResolver.Resolve("0x41303", "ja");
        var text = FindingFormatter.Format(f, "ja");
        Assert.Contains("SCHED_S_TASK_HAS_NOT_RUN", text);
        Assert.Contains("0x00041303", text);
        Assert.Contains("267011", text);
        Assert.Contains("状態コード", text);
        Assert.Contains("これは何", text);
        Assert.Contains("次の一手", text);
    }

    [Fact]
    public void 日英で同じ事実を示しプロースだけが変わる()
    {
        var ja = FindingFormatter.Format(ResultCodeResolver.Resolve("0x2", "ja"), "ja");
        var en = FindingFormatter.Format(ResultCodeResolver.Resolve("0x2", "en"), "en");
        foreach (var text in new[] { ja, en })
        {
            Assert.Contains("ERROR_FILE_NOT_FOUND", text);
            Assert.Contains("0x00000002", text);
        }
        Assert.Contains("これは何", ja);
        Assert.Contains("What this is", en);
    }

    [Theory]
    [InlineData("ja")]
    [InlineData("en")]
    public void コマンドは翻訳されない(string lang)
    {
        var text = FindingFormatter.Format(ResultCodeResolver.Resolve("0x41302", lang), lang);
        Assert.Contains("Enable-ScheduledTask -TaskName", text);
    }

    [Theory]
    [InlineData("ja")]
    [InlineData("en")]
    public void プレースホルダが残らない(string lang)
    {
        var text = FindingFormatter.Format(ResultCodeResolver.Resolve("0x1", lang), lang);
        Assert.DoesNotContain("{{", text);
        Assert.DoesNotContain("}}", text);
    }

    [Fact]
    public void snippet内のプレースホルダも展開される()
    {
        var text = FindingFormatter.Format(ResultCodeResolver.Resolve("0x41306", "ja"), "ja");
        Assert.Contains("Get-WinEvent", text);
        Assert.DoesNotContain("{{", text);
    }

    [Fact]
    public void 実値を渡せばコマンドに埋め込まれる()
    {
        var f = ResultCodeResolver.Resolve("0x1", "ja", new Dictionary<string, string> { ["command"] = @"C:\app\run.exe --daily" });
        Assert.Contains(@"C:\app\run.exe --daily", f.Next);
        Assert.DoesNotContain("<COMMAND>", f.Next);
    }

    [Fact]
    public void 実値が無ければプレースホルダ表記で埋める()
    {
        var f1 = ResultCodeResolver.Resolve("0x1", "ja");
        Assert.Contains("<COMMAND>", f1.Next);

        var f2 = ResultCodeResolver.Resolve("0x41302", "ja");
        Assert.Contains("Enable-ScheduledTask -TaskName '<TASKNAME>'", f2.Next);
    }

    [Fact]
    public void コマンドの値は単一引用符で囲む()
    {
        var f = ResultCodeResolver.Resolve("0x41302", "ja");
        Assert.DoesNotContain("Enable-ScheduledTask -TaskName \"", f.Next);
    }

    [Fact]
    public void 失敗しないコードにはCauseセクションを出さない()
    {
        var text = FindingFormatter.Format(ResultCodeResolver.Resolve("0x0", "ja"), "ja");
        Assert.DoesNotContain("考えられる原因", text);
    }

    [Fact]
    public void 符号付き値を正しく解決する()
    {
        var f = ResultCodeResolver.Resolve("-2147024891", "en");
        Assert.Equal("0x80070005", f.Code);
        Assert.Equal("E_ACCESSDENIED (HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED))", f.Constant);
    }

    [Fact]
    public void 負値のとき符号付き十進も併記する()
    {
        var text = FindingFormatter.Format(ResultCodeResolver.Resolve("0x80070005", "en"), "en");
        Assert.Contains("2147942405", text);
        Assert.Contains("-2147024891", text);
    }

    [Fact]
    public void フォールバック検証用のコードがレジストリに無いことを確かめる()
    {
        var keys = DataStore.GetRegistry().Codes.Select(c => c.Key).ToHashSet();
        Assert.DoesNotContain("0x80070057", keys);
    }

    [Fact]
    public void HRESULTからWin32エラーとしてnethelpmsgを案内する()
    {
        var text = FindingFormatter.Format(ResultCodeResolver.Resolve("0x80070057", "ja"), "ja");
        Assert.Contains("net helpmsg 87", text);
        Assert.Contains("HRESULT_FROM_WIN32(87)", text);
    }

    [Fact]
    public void 未知のコードは不明とし十六進と十進を示す()
    {
        var text = FindingFormatter.Format(ResultCodeResolver.Resolve("0x63", "ja"), "ja");
        Assert.Contains("0x00000063", text);
        Assert.Contains("99", text);
        Assert.Contains("翻訳表に無い", text);
    }

    [Theory]
    [InlineData("0x63")]
    [InlineData("0x00002EE7")]
    [InlineData("0x8004EE04")]
    [InlineData("0x40010004")]
    public void 未知の非ゼロコードは失敗として扱いseverityとrankが整合する(string code)
    {
        var f = ResultCodeResolver.Resolve(code, "ja");
        Assert.True(f.IsFailure);
        Assert.Equal("warning", f.Severity);
        Assert.Equal("investigate", f.Rank);
        Assert.False(f.IsKnown);
    }

    [Fact]
    public void 未知コードの表示ランクが調査になる()
    {
        var text = FindingFormatter.Format(ResultCodeResolver.Resolve("0x63", "ja"), "ja");
        Assert.Contains("次の一手 [調査]", text);
        Assert.DoesNotContain("次の一手 [情報]", text);
    }

    [Fact]
    public void HRESULTフォールバックもwarningInvestigate()
    {
        var f = ResultCodeResolver.Resolve("0x80070057", "ja");
        Assert.True(f.IsFailure);
        Assert.Equal("warning", f.Severity);
        Assert.Equal("investigate", f.Rank);
    }

    [Fact]
    public void JSONモデルは言語非依存フィールドが不変()
    {
        var ja = FindingJsonModel.From(ResultCodeResolver.Resolve("0x2", "ja"), "ja");
        var en = FindingJsonModel.From(ResultCodeResolver.Resolve("0x2", "en"), "en");
        Assert.Equal(ja.Code, en.Code);
        Assert.Equal(ja.Constant, en.Constant);
        Assert.Equal(ja.Kind, en.Kind);
        Assert.Equal(ja.Severity, en.Severity);
        Assert.Equal(ja.IsFailure, en.IsFailure);
        Assert.Equal(ja.Rank, en.Rank);
        Assert.Equal(ja.MessageKey, en.MessageKey);
        Assert.NotEqual(ja.Message, en.Message);
    }

    [Fact]
    public void messageKeyはコード値()
    {
        var f = FindingJsonModel.From(ResultCodeResolver.Resolve("0x2", "ja"), "ja");
        Assert.Equal("0x00000002", f.MessageKey);
    }
}
