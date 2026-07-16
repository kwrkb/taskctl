using Taskctl.Acquisition;
using Taskctl.Codes;
using Taskctl.Facts;
using Taskctl.Rules;

namespace Taskctl.Doctor;

// 取得層の結果（正規化モデル + 実行情報）を受け取り、所見のリストを返す純粋関数。
// 実機アクセスはしない。doctor の中核。
internal static class DiagnosisEngine
{
    public static DiagnosisResult Diagnose(
        AcquiredTask acquired,
        string locale,
        bool includeNonFailureResult,
        DateTime now,
        IReadOnlyCollection<string> fixedDrives)
    {
        Findings.Finding? codeFinding = null;

        // 1) 直近の結果コードの翻訳（実行情報が取れている場合のみ）
        if (acquired.Info?.LastTaskResult is { } lastResult)
        {
            bool neverRun = acquired.Info.LastRunTime is not { Year: >= 2000 };
            // 一度も実行されていないタスクの LastTaskResult (SCHED_S_TASK_HAS_NOT_RUN 等) は
            // 走査時のノイズになるため、深掘り時のみ表示する
            if (!neverRun || includeNonFailureResult)
            {
                // doctor はタスク名と操作を知っているので、プロースのプレースホルダへ実値を渡す
                // （提示されるコマンドがそのままコピペできるようにする）。
                var values = TaskValueBuilder.Build(acquired.TaskName, acquired.TaskPath);
                var execs = acquired.Model?.Actions.Where(a => a.Type == "Exec").ToList() ?? new();
                if (execs.Count >= 1)
                {
                    // 操作が複数あるタスク（最大32個を順に実行）では、どれが失敗したかを
                    // 結果コードから特定できない。1つ目だけ見せて断定せず、全部を並べる。
                    values["command"] = string.Join("\n", execs.Select(e => $"{e.Command} {e.Arguments}".Trim()));
                }
                codeFinding = ResultCodeResolver.Resolve(lastResult.ToString(), locale, values);
            }
        }

        // 2) 設定ミスの検出（宣言的ルール）。取得に失敗したタスクはスキップ。
        var ruleFindings = new List<RuleFinding>();
        if (acquired.Model is not null)
        {
            var networkDrives = DriveLetters.Network();
            var localDrives = DriveLetters.Local();
            ruleFindings = RuleEngine.Evaluate(acquired.Model, acquired.Info, now, fixedDrives, networkDrives, localDrives);
            foreach (var f in ruleFindings) RuleProseResolver.Resolve(f, locale);
        }

        return new DiagnosisResult
        {
            TaskName = acquired.TaskName,
            TaskPath = acquired.TaskPath,
            FullName = acquired.FullName,
            State = acquired.State,
            Model = acquired.Model,
            Info = acquired.Info,
            AcquireError = acquired.AcquireError,
            CodeFinding = codeFinding,
            RuleFindings = ruleFindings,
        };
    }
}
