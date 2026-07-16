using Taskctl.Codes;

namespace Taskctl.Cli.Tests;

public class ResultCodeTests
{
    [Theory]
    [InlineData("0x41303", "0x00041303")]      // VISION の explain 例。8桁ゼロ埋め
    [InlineData("0x00041303", "0x00041303")]
    [InlineData("0x2", "0x00000002")]
    [InlineData("0x8004130a", "0x8004130A")]    // 小文字 -> 大文字
    [InlineData("0X8004130A", "0x8004130A")]    // 0X 接頭辞
    [InlineData("0x80070005", "0x80070005")]    // int オーバーフロー域
    [InlineData("0xFFFFFFFF", "0xFFFFFFFF")]
    [InlineData("0x0", "0x00000000")]
    public void 十六進表記を正規化する(string raw, string expected)
    {
        Assert.Equal(expected, ResultCode.Parse(raw).Key);
    }

    [Theory]
    [InlineData("2", "0x00000002")]
    [InlineData("267011", "0x00041303")]
    [InlineData("0", "0x00000000")]
    [InlineData("1", "0x00000001")]
    [InlineData("4294967295", "0xFFFFFFFF")]
    [InlineData("41303", "0x0000A157")]         // 0x41303 と解釈しない
    public void 数字のみは十進として解釈する(string raw, string expected)
    {
        Assert.Equal(expected, ResultCode.Parse(raw).Key);
    }

    [Theory]
    [InlineData("-2147024891", "0x80070005")]   // E_ACCESSDENIED
    [InlineData("-2147216615", "0x80041319")]   // SCHED_E_MISSINGNODE
    [InlineData("-1", "0xFFFFFFFF")]
    [InlineData("-2147483648", "0x80000000")]   // int32 の下限
    public void 符号付きint32を正規化する(string raw, string expected)
    {
        Assert.Equal(expected, ResultCode.Parse(raw).Key);
    }

    [Fact]
    public void 符号付き符号なしの両方を返す()
    {
        var r = ResultCode.Parse("0x80070005");
        Assert.Equal(2147942405u, r.Unsigned);
        Assert.Equal(-2147024891, r.Signed);
    }

    [Fact]
    public void 正の範囲ではSignedとUnsignedが一致する()
    {
        var r = ResultCode.Parse("0x41303");
        Assert.Equal(267011u, r.Unsigned);
        Assert.Equal(267011, r.Signed);
    }

    [Fact]
    public void 負の十進と対応する十六進が同じKeyになる()
    {
        Assert.Equal(ResultCode.Parse("0x80070005").Key, ResultCode.Parse("-2147024891").Key);
    }

    [Fact]
    public void 前後の空白を許容する()
    {
        Assert.Equal("0x00041303", ResultCode.Parse("  0x41303  ").Key);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("abc")]
    [InlineData("0xZZ")]
    [InlineData("12.5")]
    [InlineData("0x123456789")]  // 32bit 超過
    [InlineData("4294967296")]   // 32bit 超過
    [InlineData("-2147483649")]  // int32 下限未満
    [InlineData("0x")]
    public void 不正な入力は例外を投げる(string raw)
    {
        Assert.ThrowsAny<FormatException>(() => ResultCode.Parse(raw));
    }
}
