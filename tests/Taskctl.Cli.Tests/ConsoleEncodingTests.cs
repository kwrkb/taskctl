using Taskctl.I18n;

namespace Taskctl.Cli.Tests;

// 文字化けヒントの文言。環境（コンソールのコードページ）に依存しない部分だけを検証する。
public class ConsoleEncodingTests
{
    [Theory]
    [InlineData("doctor", "taskctl doctor --lang en")]
    [InlineData("explain <code>", "taskctl explain <code> --lang en")]
    public void ヒントは実行中のコマンドを案内する(string commandExample, string expected)
    {
        var hint = ConsoleEncoding.BuildHint("ja", commandExample);
        Assert.NotNull(hint);
        Assert.Contains(expected, hint, StringComparison.Ordinal);
        Assert.Contains("chcp 65001", hint, StringComparison.Ordinal);
    }

    [Fact]
    public void doctorのヒントにexplainは出さない()
    {
        var hint = ConsoleEncoding.BuildHint("ja", "doctor");
        Assert.DoesNotContain("explain", hint, StringComparison.Ordinal);
    }

    [Fact]
    public void 対処法のコメントは同じ桁に揃える()
    {
        var hint = ConsoleEncoding.BuildHint("ja", "doctor")!;
        var columns = hint.Split('\n').Skip(1).Select(l => l.IndexOf('#', StringComparison.Ordinal)).ToList();
        Assert.Equal(2, columns.Count);
        Assert.All(columns, c => Assert.True(c > 0));
        Assert.Single(columns.Distinct());
    }

    [Theory]
    [InlineData("en")]
    [InlineData("de")]
    public void 日本語以外はヒントを出さない(string locale)
    {
        Assert.Null(ConsoleEncoding.BuildHint(locale, "doctor"));
        // en は環境に関わらず（コードページを見る前に）null
        Assert.Null(ConsoleEncoding.GetEncodingHint("en", "doctor"));
    }
}
