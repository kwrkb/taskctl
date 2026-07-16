using Taskctl.Findings;
using Taskctl.Model;
using Taskctl.Rules;

namespace Taskctl.Doctor;

// 取得済みタスク1件の診断結果。
internal sealed class DiagnosisResult
{
    public required string TaskName { get; init; }
    public required string TaskPath { get; init; }
    public required string FullName { get; init; }
    public required string State { get; init; }
    public TaskModel? Model { get; init; } // --verbose（生の設定）で使う
    public TaskInfoModel? Info { get; init; }
    public string? AcquireError { get; init; }
    public Finding? CodeFinding { get; init; }
    public List<RuleFinding> RuleFindings { get; init; } = new();

    public IEnumerable<ISeverityFinding> AllFindings()
    {
        if (CodeFinding is not null) yield return CodeFinding;
        foreach (var r in RuleFindings) yield return r;
    }
}
