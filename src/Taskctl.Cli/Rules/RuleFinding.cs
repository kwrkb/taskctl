using Taskctl.Findings;

namespace Taskctl.Rules;

// ルール所見（言語非依存）。プロースは持たない（表示時にカタログの rules.<id> から引く）。
internal sealed class RuleFinding : ISeverityFinding
{
    public required string RuleId { get; init; }
    public required string Scope { get; init; }
    public required string Severity { get; init; }
    public required string Rank { get; init; }
    public int? ActionIndex { get; init; }
    public required string MessageKey { get; init; }
    public Dictionary<string, string> Values { get; init; } = new();
    public string? Meaning { get; set; }
    public string? Cause { get; set; }
    public string? Next { get; set; }
}
