using Taskctl.Facts;
using Taskctl.Model;

namespace Taskctl.Cli.Tests;

// ファクト計算の大文字小文字非依存性（v1 の PowerShell 比較演算子は既定で case-insensitive）
public class TaskFactsTests
{
    private static readonly DateTime FixedNow = new(2026, 7, 15, 12, 0, 0);
    private static readonly string[] NoDrives = Array.Empty<string>();

    [Theory]
    [InlineData("NT AUTHORITY\\SYSTEM")]
    [InlineData("NT AUTHORITY\\System")]
    [InlineData("system")]
    [InlineData("Network Service")]
    [InlineData("S-1-5-18")]
    public void サービスアカウント判定は大文字小文字を区別しない(string userId)
    {
        var model = new TaskModel { Principal = new PrincipalModel { UserId = userId } };
        var facts = TaskFacts.Compute(model, null, FixedNow, "S-1-5-21-1-2-3-1001", "HOST\\user");
        Assert.Equal(true, facts["principal.is_service_account"]);
    }

    [Fact]
    public void 一般ユーザーはサービスアカウントではない()
    {
        var model = new TaskModel { Principal = new PrincipalModel { UserId = "HOST\\user2" } };
        var facts = TaskFacts.Compute(model, null, FixedNow, "S-1-5-21-1-2-3-1001", "HOST\\user");
        Assert.Equal(false, facts["principal.is_service_account"]);
    }

    [Theory]
    [InlineData("%USERPROFILE%\\app.exe")]
    [InlineData("%userprofile%\\app.exe")]
    [InlineData("%AppData%\\tool\\run.exe")]
    public void プロファイル変数の検出は大文字小文字を区別しない(string command)
    {
        var action = new ActionModel { Type = "Exec", Command = command };
        var facts = ActionFacts.Compute(action, NoDrives, NoDrives, NoDrives);
        Assert.Equal(true, facts["action.uses_profile_variable"]);
    }

    [Fact]
    public void プロファイル変数を使わないコマンドは検出しない()
    {
        var action = new ActionModel { Type = "Exec", Command = "C:\\tools\\app.exe" };
        var facts = ActionFacts.Compute(action, NoDrives, NoDrives, NoDrives);
        Assert.Equal(false, facts["action.uses_profile_variable"]);
    }

    [Theory]
    [InlineData("C:\\tools\\run.ps1")]
    [InlineData("C:\\tools\\run.PS1")]
    [InlineData("C:\\tools\\run.Ps1")]
    [InlineData("C:\\tools\\mod.PSM1")]
    [InlineData("C:\\tools\\run.SH")]
    public void 直接起動できないスクリプト拡張子の判定は大文字小文字を区別しない(string command)
    {
        var action = new ActionModel { Type = "Exec", Command = command };
        var facts = ActionFacts.Compute(action, NoDrives, NoDrives, NoDrives);
        Assert.Equal(true, facts["action.command_is_unlaunchable_script"]);
    }

    [Theory]
    [InlineData("C:\\tools\\app.exe")]
    [InlineData("C:\\tools\\run.CMD")]
    public void 直接起動できるコマンドはスクリプト扱いしない(string command)
    {
        var action = new ActionModel { Type = "Exec", Command = command };
        var facts = ActionFacts.Compute(action, NoDrives, NoDrives, NoDrives);
        Assert.Equal(false, facts["action.command_is_unlaunchable_script"]);
    }
}
