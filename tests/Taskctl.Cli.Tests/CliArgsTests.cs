using Taskctl.Cli;

namespace Taskctl.Cli.Tests;

public class CliArgsTests
{
    [Fact]
    public void 引数なしは空コマンド()
    {
        Assert.Equal("", CliArgs.Parse(Array.Empty<string>()).Command);
    }

    [Theory]
    [InlineData("--help")]
    [InlineData("-h")]
    [InlineData("help")]
    public void ヘルプ指定はhelpコマンドになる(string arg)
    {
        Assert.Equal("help", CliArgs.Parse(new[] { arg }).Command);
    }

    [Fact]
    public void コマンド後のヘルプフラグもhelpになる()
    {
        Assert.Equal("help", CliArgs.Parse(new[] { "doctor", "--help" }).Command);
    }

    [Fact]
    public void 位置引数とフラグを混在してパースできる()
    {
        var args = CliArgs.Parse(new[] { "explain", "0x41303", "--lang", "en", "--json" });
        Assert.Equal("explain", args.Command);
        Assert.Equal("0x41303", args.Positional);
        Assert.Equal("en", args.Lang);
        Assert.True(args.Json);
        Assert.False(args.Verbose);
    }

    [Fact]
    public void イコール形式のlangもパースできる()
    {
        Assert.Equal("ja", CliArgs.Parse(new[] { "doctor", "--lang=ja" }).Lang);
    }

    [Fact]
    public void langの値が無ければ例外()
    {
        Assert.Throws<ArgumentException>(() => CliArgs.Parse(new[] { "explain", "2", "--lang" }));
    }

    [Fact]
    public void 不明なフラグは例外()
    {
        Assert.Throws<ArgumentException>(() => CliArgs.Parse(new[] { "doctor", "--unknown" }));
    }

    [Fact]
    public void 位置引数が多すぎれば例外()
    {
        Assert.Throws<ArgumentException>(() => CliArgs.Parse(new[] { "explain", "2", "3" }));
    }
}
