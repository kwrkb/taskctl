using System.Text.Json.Serialization;
using Taskctl.Findings;
using Taskctl.Rules;

namespace Taskctl.Doctor;

internal sealed class DoctorJsonModel
{
    [JsonPropertyName("locale")]
    public string Locale { get; set; } = "";

    [JsonPropertyName("scanned")]
    public int Scanned { get; set; }

    [JsonPropertyName("exit_code")]
    public int ExitCode { get; set; }

    [JsonPropertyName("summary")]
    public DoctorSummary Summary { get; set; } = new();

    [JsonPropertyName("tasks")]
    public List<DoctorTaskJsonModel> Tasks { get; set; } = new();
}

internal sealed class DoctorSummary
{
    [JsonPropertyName("errors")]
    public int Errors { get; set; }

    [JsonPropertyName("warnings")]
    public int Warnings { get; set; }

    [JsonPropertyName("notices")]
    public int Notices { get; set; }

    [JsonPropertyName("acquire_errors")]
    public int AcquireErrors { get; set; }
}

internal sealed class DoctorTaskJsonModel
{
    [JsonPropertyName("task")]
    public string Task { get; set; } = "";

    [JsonPropertyName("state")]
    public string State { get; set; } = "";

    [JsonPropertyName("last_run")]
    public string? LastRun { get; set; }

    [JsonPropertyName("next_run")]
    public string? NextRun { get; set; }

    [JsonPropertyName("last_result")]
    public FindingJsonModel? LastResult { get; set; }

    [JsonPropertyName("findings")]
    public List<RuleFindingJsonModel> Findings { get; set; } = new();

    [JsonPropertyName("acquire_error")]
    public string? AcquireError { get; set; }

    public static DoctorTaskJsonModel From(DiagnosisResult r, string locale) => new()
    {
        Task = r.FullName,
        State = r.State,
        LastRun = r.Info?.LastRunTime is { Year: >= 2000 } lr ? lr.ToString("o") : null,
        NextRun = r.Info?.NextRunTime is { Year: >= 2000 } nr ? nr.ToString("o") : null,
        LastResult = r.CodeFinding is not null ? FindingJsonModel.From(r.CodeFinding, locale) : null,
        Findings = r.RuleFindings.Select(f => RuleFindingJsonModel.From(f, locale)).ToList(),
        AcquireError = r.AcquireError,
    };
}
