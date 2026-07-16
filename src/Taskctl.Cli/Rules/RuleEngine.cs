using System.Text.Json;
using Taskctl.Data;
using Taskctl.Facts;
using Taskctl.Model;

namespace Taskctl.Rules;

// 宣言的ルール (data/rules.json) を正規化モデルに適用し、言語非依存の所見を返す。
// when は AND 条件の配列で、各条件は { fact, eq|gte|lte } のみ。
// ファクトが null（算出不能）の条件は不成立として扱う＝誤検知しない側に倒す。
// プロースは一切持たない。表示時にカタログの rules.<id> から引く。
internal static class RuleEngine
{
    public static List<RuleFinding> Evaluate(
        TaskModel model,
        TaskInfoModel? info,
        DateTime now,
        IReadOnlyCollection<string> fixedDrives,
        IReadOnlyCollection<string> networkDrives,
        IReadOnlyCollection<string> localDrives,
        string? currentSid = null,
        string? currentName = null)
    {
        var rulesFile = DataStore.GetRules();
        var taskFacts = TaskFacts.Compute(model, info, now, currentSid, currentName);

        var actionFactSets = model.Actions
            .Select(a => ActionFacts.Compute(a, fixedDrives, networkDrives, localDrives))
            .ToList();

        var findings = new List<RuleFinding>();

        foreach (var rule in rulesFile.Rules)
        {
            if (rule.Scope == "task")
            {
                if (Matches(rule.When, taskFacts))
                {
                    findings.Add(BuildFinding(rule, model, taskFacts, null, -1));
                }
            }
            else if (rule.Scope == "action")
            {
                for (int i = 0; i < model.Actions.Count; i++)
                {
                    var merged = new Dictionary<string, object?>(taskFacts, StringComparer.Ordinal);
                    foreach (var kv in actionFactSets[i]) merged[kv.Key] = kv.Value;

                    if (Matches(rule.When, merged))
                    {
                        findings.Add(BuildFinding(rule, model, merged, model.Actions[i], i));
                    }
                }
            }
        }

        return findings;
    }

    private static bool Matches(List<RuleClause> conditions, Dictionary<string, object?> facts)
    {
        foreach (var cond in conditions)
        {
            if (!facts.TryGetValue(cond.Fact, out var value))
            {
                return false; // 未知のファクト（ルール側の誤記の可能性）
            }
            if (value is null) return false; // 算出不能 -> 発火させない

            bool ok;
            if (cond.Eq is not null)
            {
                ok = MatchesEq(value, cond.Eq);
            }
            else if (cond.Gte is not null)
            {
                ok = Convert.ToDouble(value) >= cond.Gte.Value;
            }
            else if (cond.Lte is not null)
            {
                ok = Convert.ToDouble(value) <= cond.Lte.Value;
            }
            else
            {
                ok = false; // 未知の演算子
            }
            if (!ok) return false;
        }
        return true;
    }

    private static bool MatchesEq(object factValue, object eqValue)
    {
        // JSON ソースジェネレータは object 型プロパティを JsonElement として保持する。
        if (eqValue is JsonElement je)
        {
            return je.ValueKind switch
            {
                JsonValueKind.True => factValue is true,
                JsonValueKind.False => factValue is false,
                JsonValueKind.String => Equals(factValue as string, je.GetString()),
                JsonValueKind.Number => factValue is double d && Math.Abs(d - je.GetDouble()) < 1e-9,
                _ => false,
            };
        }
        return Equals(factValue, eqValue);
    }

    private static RuleFinding BuildFinding(Rule rule, TaskModel model, Dictionary<string, object?> facts, ActionModel? action, int actionIndex)
    {
        var name = model.TaskName ?? model.Uri ?? "";
        var values = TaskValueBuilder.Build(name, model.TaskPath);
        if (action is not null)
        {
            values["command"] = $"{action.Command} {action.Arguments}".Trim();
            values["workdir"] = action.WorkingDirectory ?? "";
        }
        if (facts.TryGetValue("info.days_since_last_run", out var days) && days is not null)
        {
            values["days"] = Convert.ToInt64(days).ToString();
        }
        if (facts.TryGetValue("settings.execution_time_limit_seconds", out var limit) && limit is not null)
        {
            values["limit_seconds"] = Convert.ToInt64(limit).ToString();
        }

        return new RuleFinding
        {
            RuleId = rule.Id,
            Scope = rule.Scope,
            Severity = rule.Severity,
            Rank = rule.Rank,
            ActionIndex = action is not null ? actionIndex : null,
            MessageKey = $"rules.{rule.Id}",
            Values = values,
        };
    }
}
