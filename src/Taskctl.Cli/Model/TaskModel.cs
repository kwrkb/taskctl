namespace Taskctl.Model;

// Export-ScheduledTask の XML を正規化したモデル。診断ルールはこの上の純粋関数として書く。
internal sealed class TaskModel
{
    public string? TaskName { get; init; }
    public string? TaskPath { get; init; }
    public string? Uri { get; init; }
    public bool Enabled { get; init; } = true;
    public PrincipalModel? Principal { get; init; }
    public List<ActionModel> Actions { get; init; } = new();
    public List<TriggerModel> Triggers { get; init; } = new();
    public SettingsModel? Settings { get; init; }
    public string Xml { get; init; } = "";
}

internal sealed class PrincipalModel
{
    public string? UserId { get; init; }
    public string? GroupId { get; init; }
    public string? LogonType { get; init; }
    public string? RunLevel { get; init; }
}

internal sealed class ActionModel
{
    public required string Type { get; init; }
    public string? Command { get; init; }
    public string? Arguments { get; init; }
    public string? WorkingDirectory { get; init; }
}

internal sealed class TriggerModel
{
    public required string Type { get; init; }
    public bool Enabled { get; init; } = true;
    public string? StartBoundary { get; init; }
    public string? EndBoundary { get; init; }
}

internal sealed class SettingsModel
{
    public bool Enabled { get; init; } = true;
    public string? ExecutionTimeLimit { get; init; }
    public string? MultipleInstancesPolicy { get; init; }
    public bool DisallowStartIfOnBatteries { get; init; } = true;
    public bool StopIfGoingOnBatteries { get; init; } = true;
    public bool RunOnlyIfIdle { get; init; }
    public bool RunOnlyIfNetworkAvailable { get; init; }
    public bool StartWhenAvailable { get; init; }
    public bool WakeToRun { get; init; }
}

// Get-ScheduledTaskInfo の結果（設定とは別取得。相関が必要）。
// タスクオブジェクトが持つ実行結果は直近1回分のみ。
internal sealed class TaskInfoModel
{
    public DateTime? LastRunTime { get; init; }
    public long? LastTaskResult { get; init; }
    public DateTime? NextRunTime { get; init; }
    public int? NumberOfMissedRuns { get; init; }
}
