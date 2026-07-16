using System.Text.Json.Serialization;

namespace Taskctl.Acquisition;

// acquire.ps1 が書き出す JSON の形。C# 側のパース用（生データ、まだ正規化していない）。
internal sealed class RawAcquireOutput
{
    [JsonPropertyName("tasks")]
    public List<RawAcquiredTask> Tasks { get; set; } = new();

    [JsonPropertyName("error")]
    public string? Error { get; set; }
}

internal sealed class RawAcquiredTask
{
    [JsonPropertyName("task_name")]
    public string TaskName { get; set; } = "";

    [JsonPropertyName("task_path")]
    public string TaskPath { get; set; } = "";

    [JsonPropertyName("state")]
    public string State { get; set; } = "";

    [JsonPropertyName("xml")]
    public string? Xml { get; set; }

    [JsonPropertyName("info")]
    public RawTaskInfo? Info { get; set; }

    [JsonPropertyName("acquire_error")]
    public string? AcquireError { get; set; }
}

internal sealed class RawTaskInfo
{
    [JsonPropertyName("last_run_time")]
    public DateTimeOffset? LastRunTime { get; set; }

    [JsonPropertyName("last_task_result")]
    public long? LastTaskResult { get; set; }

    [JsonPropertyName("next_run_time")]
    public DateTimeOffset? NextRunTime { get; set; }

    [JsonPropertyName("number_of_missed_runs")]
    public int? NumberOfMissedRuns { get; set; }
}
