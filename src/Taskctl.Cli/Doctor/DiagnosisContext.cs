using Taskctl.Facts;

namespace Taskctl.Doctor;

// 診断が参照する環境のスナップショット（現在時刻・ドライブ構成・実行ユーザー）。
// テストでは固定値を注入し、実行時刻やホスト構成に依存しないヘルメティックな検証を可能にする。
// CurrentSid / CurrentName が null の場合はファクト算出側でライブ照会される（実行時の既定動作）。
internal sealed class DiagnosisContext
{
    public required DateTime Now { get; init; }
    public required IReadOnlyCollection<string> FixedDrives { get; init; }
    public required IReadOnlyCollection<string> NetworkDrives { get; init; }
    public required IReadOnlyCollection<string> LocalDrives { get; init; }
    public string? CurrentSid { get; init; }
    public string? CurrentName { get; init; }

    public static DiagnosisContext Live() => new()
    {
        Now = DateTime.Now,
        FixedDrives = DriveLetters.Fixed(),
        NetworkDrives = DriveLetters.Network(),
        LocalDrives = DriveLetters.Local(),
    };
}
