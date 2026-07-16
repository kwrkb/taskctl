using System.Text.RegularExpressions;
using Taskctl.Model;

namespace Taskctl.Facts;

// 1つの操作 (Exec) についてのファクトを算出する。
internal static partial class ActionFacts
{
    private static readonly string[] ProfileVars =
        { "%USERPROFILE%", "%APPDATA%", "%LOCALAPPDATA%", "%TEMP%", "%TMP%", "%HOMEDRIVE%", "%HOMEPATH%", "%ONEDRIVE%" };

    [GeneratedRegex(@"^[A-Za-z]:[\\/]")]
    private static partial Regex RootedDriveRegex();

    [GeneratedRegex(@"[\\/]")]
    private static partial Regex SeparatorRegex();

    [GeneratedRegex(@"^([A-Za-z]):[\\/]")]
    private static partial Regex DriveLetterRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9])([A-Za-z]):[\\/]")]
    private static partial Regex ReferencedDriveRegex();

    [GeneratedRegex(@"(^|[\s""'=])\\\\[^\\\s]")]
    private static partial Regex UncPathRegex();

    [GeneratedRegex(@"^(powershell|pwsh)(\.exe)?$", RegexOptions.IgnoreCase)]
    private static partial Regex PowerShellExeRegex();

    [GeneratedRegex(@"(?i)(^|\s)-(File|Command|EncodedCommand)\b")]
    private static partial Regex PowerShellArgRegex();

    [GeneratedRegex(@"(?i)\.ps1\b")]
    private static partial Regex Ps1Regex();

    public static Dictionary<string, object?> Compute(
        ActionModel action,
        IReadOnlyCollection<string> fixedDrives,
        IReadOnlyCollection<string> networkDrives,
        IReadOnlyCollection<string> localDrives)
    {
        var facts = new Dictionary<string, object?>(StringComparer.Ordinal);
        if (action.Type != "Exec") return facts;

        var command = RemoveQuote(action.Command);
        var arguments = action.Arguments ?? "";
        var workdir = RemoveQuote(action.WorkingDirectory);
        var allText = $"{command} {arguments} {workdir}";

        // ---- パスの形 ----
        bool isRooted = RootedDriveRegex().IsMatch(command) || command.StartsWith('\\') || command.StartsWith('%');
        bool hasSeparator = SeparatorRegex().IsMatch(command);
        // 「区切りを含むのに絶対でない」だけを相対と見なす。素の exe 名は検索パスで解決されるため flag しない。
        facts["action.command_relative"] = hasSeparator && !isRooted;

        facts["action.working_directory_set"] = !string.IsNullOrWhiteSpace(workdir);

        // ---- 存在チェック（文脈差で誤爆しうるため、確実に検査できる時だけ） ----
        facts["action.command_checkable"] = false;
        facts["action.command_exists"] = null;
        var driveMatch = DriveLetterRegex().Match(command);
        if (driveMatch.Success && !command.Contains('%'))
        {
            var drive = driveMatch.Groups[1].Value.ToUpperInvariant();
            if (fixedDrives.Contains(drive))
            {
                facts["action.command_checkable"] = true;
                facts["action.command_exists"] = File.Exists(command);
            }
        }

        facts["action.working_directory_checkable"] = false;
        facts["action.working_directory_exists"] = null;
        var workdirMatch = DriveLetterRegex().Match(workdir);
        if (workdirMatch.Success && !workdir.Contains('%'))
        {
            var drive = workdirMatch.Groups[1].Value.ToUpperInvariant();
            if (fixedDrives.Contains(drive))
            {
                facts["action.working_directory_checkable"] = true;
                facts["action.working_directory_exists"] = Directory.Exists(workdir);
            }
        }

        // ---- ネットワーク/プロファイル依存 ----
        // ネットワークドライブは「実際に DriveType=Network のもの」と「そもそも存在しないドライブ文字」
        // の両方がありうる（タスク実行時にのみマウントされる想定の Z: など）。
        // USB / 光学ドライブを「ネットワークドライブ」と誤報しないため、固定ドライブ以外を
        // 一律にマップドライブ扱いはしない。
        var referenced = ReferencedDriveRegex().Matches(allText)
            .Select(m => m.Groups[1].Value.ToUpperInvariant())
            .Distinct()
            .ToList();
        facts["action.uses_mapped_drive"] = referenced.Any(d => networkDrives.Contains(d) || (!fixedDrives.Contains(d) && !localDrives.Contains(d)));

        facts["action.uses_unc_path"] = UncPathRegex().IsMatch(allText);

        // 環境変数参照は大文字小文字を区別しない（%userprofile% も有効）
        facts["action.uses_profile_variable"] = ProfileVars.Any(v => allText.Contains(v, StringComparison.OrdinalIgnoreCase));

        // ---- 起動指定 ----
        var leaf = Path.GetFileName(command);
        bool isPowerShell = PowerShellExeRegex().IsMatch(leaf);
        facts["action.is_powershell"] = isPowerShell;
        facts["action.powershell_has_file_or_command"] = null;
        if (isPowerShell)
        {
            facts["action.powershell_has_file_or_command"] =
                PowerShellArgRegex().IsMatch(arguments) || Ps1Regex().IsMatch(arguments);
        }

        var ext = Path.GetExtension(command);
        facts["action.command_is_unlaunchable_script"] = ext is ".ps1" or ".psm1" or ".sh";

        return facts;
    }

    private static string RemoveQuote(string? text)
    {
        if (text is null) return "";
        return text.Trim().Trim('"').Trim('\'');
    }
}
