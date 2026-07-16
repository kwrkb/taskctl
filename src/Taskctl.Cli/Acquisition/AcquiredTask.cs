using Taskctl.Model;

namespace Taskctl.Acquisition;

// 取得層の結果。設定（Model）と実行情報（Info）は別取得のため、
// 一方だけ失敗することがある（AcquireError に理由を残す）。
internal sealed class AcquiredTask
{
    public required string TaskName { get; init; }
    public required string TaskPath { get; init; }
    public required string FullName { get; init; }
    public required string State { get; init; }
    public TaskModel? Model { get; init; }
    public TaskInfoModel? Info { get; init; }
    public string? AcquireError { get; init; }
}
