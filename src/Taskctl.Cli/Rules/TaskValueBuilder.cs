using System.Text.RegularExpressions;

namespace Taskctl.Rules;

// プロースのプレースホルダへ渡す、タスク識別子の各表現を作る。
// 提示するコマンドがそのままコピペで動くことが VISION の成功条件。そのために:
//   task       : 表示用のフルパス（\Folder\Name）
//   task_args  : cmdlet の引数（-TaskName '...' -TaskPath '...'）。
//                -TaskName にフルパスは渡せない（cmdlet が受け付けない）ため、
//                必ず -TaskPath と組にする。
//   task_regex : -match に埋める正規表現（メタ文字をエスケープ）
// 値は PowerShell の単一引用符文字列として埋める前提でエスケープする
// （' を '' にする）。単一引用符なら $ や ` が展開されず、名前に何が入っても壊れない。
internal static class TaskValueBuilder
{
    public static Dictionary<string, string> Build(string? taskName, string? taskPath)
    {
        var path = string.IsNullOrWhiteSpace(taskPath) ? "\\" : taskPath;
        if (!path.EndsWith('\\')) path += "\\";
        var full = path + taskName;

        return new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["task"] = full,
            ["task_args"] = $"-TaskName {ToPsLiteral(taskName)} -TaskPath {ToPsLiteral(path)}",
            ["task_regex"] = ToPsLiteralBody(Regex.Escape(full)),
        };
    }

    private static string ToPsLiteral(string? text) => "'" + ToPsLiteralBody(text) + "'";

    private static string ToPsLiteralBody(string? text) => text?.Replace("'", "''") ?? "";
}
