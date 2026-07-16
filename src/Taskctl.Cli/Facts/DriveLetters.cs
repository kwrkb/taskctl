namespace Taskctl.Facts;

// ローカルのドライブ文字を種類別に列挙する。DriveInfo は列挙時に例外を投げうる
// （切断された共有など）ため、失敗しても空で返す。
internal static class DriveLetters
{
    public static string[] Get(params DriveType[] types)
    {
        try
        {
            return DriveInfo.GetDrives()
                .Where(d => types.Contains(d.DriveType))
                .Select(d => d.Name.Substring(0, 1).ToUpperInvariant())
                .ToArray();
        }
        catch (Exception)
        {
            // IOException のほか UnauthorizedAccessException 等もありうる。
            // ドライブ一覧が取れなくても診断自体は続行できる（v1 も全例外を握って空を返す）。
            return Array.Empty<string>();
        }
    }

    public static string[] Fixed() => Get(DriveType.Fixed);
    public static string[] Network() => Get(DriveType.Network);
    public static string[] Local() => Get(DriveType.Removable, DriveType.CDRom, DriveType.Ram);
}
