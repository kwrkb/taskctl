using Taskctl.Acquisition;

namespace Taskctl.Cli.Tests;

// 取得層のうち、実機（タスクスケジューラ）に触れない部分だけを検証する。
public class PowerShellTaskAcquirerTests
{
    [Fact]
    public void 一時スクリプトは呼び出しごとに別のパスへ展開する()
    {
        // 固定名だと共有 TEMP で並行プロセス・別ユーザーと衝突する（#7）。
        var a = PowerShellTaskAcquirer.ExtractScript();
        var b = PowerShellTaskAcquirer.ExtractScript();
        try
        {
            Assert.NotEqual(a, b);
            Assert.True(File.Exists(a));
            Assert.True(File.Exists(b));

            var prefix = $"taskctl-acquire-{Environment.ProcessId}-";
            Assert.StartsWith(prefix, Path.GetFileName(a), StringComparison.Ordinal);
            Assert.StartsWith(prefix, Path.GetFileName(b), StringComparison.Ordinal);
            Assert.EndsWith(".ps1", a, StringComparison.Ordinal);
        }
        finally
        {
            File.Delete(a);
            File.Delete(b);
        }
    }

    [Fact]
    public void 一時スクリプトには埋込の取得スクリプトを書き出す()
    {
        var path = PowerShellTaskAcquirer.ExtractScript();
        try
        {
            var content = File.ReadAllText(path);
            Assert.Contains("Get-ScheduledTask", content, StringComparison.Ordinal);
            Assert.Contains("$OutFile", content, StringComparison.Ordinal);
        }
        finally { File.Delete(path); }
    }
}
