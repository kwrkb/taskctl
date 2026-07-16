using Taskctl.Model;

namespace Taskctl.Cli.Tests;

public class TaskXmlParserTests
{
    private static string FixturePath(string name) => Path.Combine(AppContext.BaseDirectory, "fixtures", name);

    private static TaskModel Read(string name) =>
        TaskXmlParser.Parse(File.ReadAllText(FixturePath(name)), name.Replace(".xml", ""));

    [Fact]
    public void 名前空間付きXMLから値を取り出せる()
    {
        var m = Read("normal.xml");
        Assert.Equal("\\NormalBackup", m.Uri);
        Assert.NotEmpty(m.Actions);
        Assert.NotEmpty(m.Triggers);
        Assert.NotNull(m.Settings);
        Assert.NotNull(m.Principal);
    }

    [Fact]
    public void タスクXMLでなければ例外()
    {
        Assert.Throws<FormatException>(() => TaskXmlParser.Parse("<foo/>"));
    }

    [Fact]
    public void 不正なXMLでもFormatExceptionに揃える()
    {
        // 呼び出し元は FormatException を「このタスクだけ解析失敗」として継続する。
        // XmlException が素通りするとプロセス全体が落ちる。
        Assert.Throws<FormatException>(() => TaskXmlParser.Parse("not xml at all <<"));
    }

    [Fact]
    public void normal_操作を取り出す()
    {
        var m = Read("normal.xml");
        var a = Assert.Single(m.Actions);
        Assert.Equal("Exec", a.Type);
        Assert.Equal(@"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe", a.Command);
        Assert.Contains("backup.ps1", a.Arguments);
        Assert.Equal(@"C:\Windows\System32", a.WorkingDirectory);
    }

    [Fact]
    public void normal_プリンシパルを取り出す()
    {
        var m = Read("normal.xml");
        Assert.StartsWith("S-1-5-21-", m.Principal!.UserId);
        Assert.Equal("Password", m.Principal.LogonType);
        Assert.Equal("LeastPrivilege", m.Principal.RunLevel);
    }

    [Fact]
    public void normal_トリガーを取り出す()
    {
        var m = Read("normal.xml");
        var t = Assert.Single(m.Triggers);
        Assert.Equal("CalendarTrigger", t.Type);
        Assert.True(t.Enabled);
        Assert.Equal("2026-01-01T02:00:00+09:00", t.StartBoundary);
        Assert.Null(t.EndBoundary);
    }

    [Fact]
    public void normal_設定を取り出す()
    {
        var m = Read("normal.xml");
        Assert.True(m.Enabled);
        Assert.Equal("PT1H", m.Settings!.ExecutionTimeLimit);
        Assert.Equal("IgnoreNew", m.Settings.MultipleInstancesPolicy);
        Assert.False(m.Settings.DisallowStartIfOnBatteries);
        Assert.False(m.Settings.RunOnlyIfIdle);
        Assert.True(m.Settings.StartWhenAvailable);
    }

    [Fact]
    public void relativepath_相対パスをそのまま保持する()
    {
        var m = Read("relative-path.xml");
        Assert.Equal(@"scripts\run.bat", m.Actions[0].Command);
    }

    [Fact]
    public void relativepath_未設定のWorkingDirectoryはnull()
    {
        var m = Read("relative-path.xml");
        Assert.True(string.IsNullOrEmpty(m.Actions[0].WorkingDirectory));
    }

    [Fact]
    public void networkdrive_引数にドライブレターを保持する()
    {
        var m = Read("network-drive.xml");
        Assert.Contains(@"Z:\scripts\backup.ps1", m.Actions[0].Arguments);
    }

    [Fact]
    public void networkdrive_環境変数を展開せずに保持する()
    {
        var m = Read("network-drive.xml");
        Assert.Equal("%USERPROFILE%\\work", m.Actions[0].WorkingDirectory);
    }

    [Fact]
    public void networkdrive_SYSTEMプリンシパルとRunLevel()
    {
        var m = Read("network-drive.xml");
        Assert.Equal("S-1-5-18", m.Principal!.UserId);
        Assert.Equal("HighestAvailable", m.Principal.RunLevel);
    }

    [Fact]
    public void logononly_条件を取り出す()
    {
        var m = Read("logon-only.xml");
        Assert.True(m.Settings!.DisallowStartIfOnBatteries);
        Assert.True(m.Settings.StopIfGoingOnBatteries);
        Assert.True(m.Settings.RunOnlyIfIdle);
        Assert.True(m.Settings.RunOnlyIfNetworkAvailable);
    }

    [Fact]
    public void logononly_ログオン中のみ実行()
    {
        var m = Read("logon-only.xml");
        Assert.Equal("InteractiveToken", m.Principal!.LogonType);
    }

    [Fact]
    public void logononly_終了境界を取り出す()
    {
        var m = Read("logon-only.xml");
        Assert.Equal("2021-01-01T12:00:00+09:00", m.Triggers[0].EndBoundary);
    }

    [Fact]
    public void notriggerdisabled_無効なタスクを検出できる()
    {
        var m = Read("no-trigger-disabled.xml");
        Assert.False(m.Enabled);
        Assert.False(m.Settings!.Enabled);
    }

    [Fact]
    public void notriggerdisabled_トリガー無しは空リスト()
    {
        var m = Read("no-trigger-disabled.xml");
        Assert.Empty(m.Triggers);
    }

    [Fact]
    public void notriggerdisabled_省略された設定は既定値になる()
    {
        var m = Read("no-trigger-disabled.xml");
        Assert.True(m.Settings!.DisallowStartIfOnBatteries);
        Assert.False(m.Settings.RunOnlyIfIdle);
        Assert.False(m.Settings.StartWhenAvailable);
    }

    [Fact]
    public void notriggerdisabled_未設定のExecutionTimeLimitはnull()
    {
        var m = Read("no-trigger-disabled.xml");
        Assert.True(string.IsNullOrEmpty(m.Settings!.ExecutionTimeLimit));
    }

    [Fact]
    public void notriggerdisabled_多重起動ポリシーを取り出す()
    {
        var m = Read("no-trigger-disabled.xml");
        Assert.Equal("Parallel", m.Settings!.MultipleInstancesPolicy);
    }
}
