using Taskctl.Cli;

namespace Taskctl.Cli.Tests;

public class VersionInfoTests
{
    [Fact]
    public void バージョンは空にならない()
    {
        Assert.False(string.IsNullOrWhiteSpace(VersionInfo.Value));
    }

    [Fact]
    public void バージョンにcommit_shaを混ぜない()
    {
        // AssemblyInformationalVersion は "2.0.1+<sha>" 形式になりうる。
        Assert.DoesNotContain('+', VersionInfo.Value);
    }

    [Fact]
    public void 表示はツール名とバージョンの1行()
    {
        Assert.Equal($"taskctl {VersionInfo.Value}", VersionInfo.Text);
        Assert.DoesNotContain('\n', VersionInfo.Text);
    }
}
