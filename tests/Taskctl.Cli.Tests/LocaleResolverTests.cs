using Taskctl.I18n;

namespace Taskctl.Cli.Tests;

// ロケール決定の優先順位（--lang > TASKCTL_LANG > OS UI カルチャ > en）。
// env / uiCulture はパラメータで注入し、実行環境に依存しない。
public class LocaleResolverTests
{
    [Fact]
    public void 明示フラグが最優先()
    {
        Assert.Equal("en", LocaleResolver.Resolve("en", envLang: "ja", uiCulture: "ja-JP"));
    }

    [Fact]
    public void フラグが無ければ環境変数()
    {
        Assert.Equal("ja", LocaleResolver.Resolve(null, envLang: "ja", uiCulture: "en-US"));
    }

    [Fact]
    public void 環境変数も無ければUIカルチャ()
    {
        Assert.Equal("ja", LocaleResolver.Resolve(null, envLang: "", uiCulture: "ja-JP"));
    }

    [Fact]
    public void どれも未対応ならenへフォールバック()
    {
        Assert.Equal("en", LocaleResolver.Resolve("fr", envLang: "de", uiCulture: "ko-KR"));
    }

    [Theory]
    [InlineData("ja-JP", "ja")]
    [InlineData("JA", "ja")]
    [InlineData("en_US", "en")]
    [InlineData(" ja ", "ja")]
    public void 先頭サブタグと大文字小文字と空白を正規化する(string input, string expected)
    {
        Assert.Equal(expected, LocaleResolver.Resolve(input, envLang: "", uiCulture: ""));
    }

    [Fact]
    public void 未対応のフラグは次の段へ倒れる()
    {
        Assert.Equal("ja", LocaleResolver.Resolve("fr", envLang: "ja-JP", uiCulture: "en-US"));
    }
}
