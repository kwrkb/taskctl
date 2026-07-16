using System.Xml.Linq;

namespace Taskctl.Model;

// Export-ScheduledTask の XML を正規化モデルへ変換する。純粋関数（XML文字列 -> オブジェクト）。
// 実機のタスク登録なしに fixture でテストできる。既定名前空間を持つため、
// 要素アクセスには必ず XNamespace を通す（通さないと何も取れず、無言で空になる）。
internal static class TaskXmlParser
{
    private static readonly XNamespace Ns = "http://schemas.microsoft.com/windows/2004/02/mit/task";

    public static TaskModel Parse(string xml, string? taskName = null, string? taskPath = null)
    {
        var doc = XDocument.Parse(xml);
        var task = doc.Root;
        if (task is null || task.Name != Ns + "Task")
        {
            throw new FormatException("タスク XML として解釈できません（ルート要素 Task が見つかりません）。");
        }

        return new TaskModel
        {
            TaskName = taskName,
            TaskPath = taskPath,
            Uri = GetText(task, "RegistrationInfo", "URI"),
            Enabled = GetBool(task, true, "Settings", "Enabled"),
            Principal = ParsePrincipal(task),
            Actions = ParseActions(task),
            Triggers = ParseTriggers(task),
            Settings = ParseSettings(task),
            Xml = xml,
        };
    }

    private static PrincipalModel? ParsePrincipal(XElement task)
    {
        var p = task.Element(Ns + "Principals")?.Element(Ns + "Principal");
        if (p is null) return null;
        return new PrincipalModel
        {
            UserId = p.Element(Ns + "UserId")?.Value,
            GroupId = p.Element(Ns + "GroupId")?.Value,
            LogonType = p.Element(Ns + "LogonType")?.Value,
            RunLevel = p.Element(Ns + "RunLevel")?.Value,
        };
    }

    private static List<ActionModel> ParseActions(XElement task)
    {
        var result = new List<ActionModel>();
        var actions = task.Element(Ns + "Actions");
        if (actions is null) return result;

        foreach (var child in actions.Elements())
        {
            if (child.Name == Ns + "Exec")
            {
                result.Add(new ActionModel
                {
                    Type = "Exec",
                    Command = child.Element(Ns + "Command")?.Value,
                    Arguments = child.Element(Ns + "Arguments")?.Value,
                    WorkingDirectory = child.Element(Ns + "WorkingDirectory")?.Value,
                });
            }
            else
            {
                // Exec 以外（ComHandler / SendEmail / ShowMessage）は診断対象外だが、存在は拾う
                result.Add(new ActionModel { Type = child.Name.LocalName });
            }
        }
        return result;
    }

    private static List<TriggerModel> ParseTriggers(XElement task)
    {
        var result = new List<TriggerModel>();
        var triggers = task.Element(Ns + "Triggers");
        if (triggers is null) return result;

        foreach (var t in triggers.Elements())
        {
            result.Add(new TriggerModel
            {
                Type = t.Name.LocalName,
                Enabled = GetBool(t, true, "Enabled"),
                StartBoundary = t.Element(Ns + "StartBoundary")?.Value,
                EndBoundary = t.Element(Ns + "EndBoundary")?.Value,
            });
        }
        return result;
    }

    private static SettingsModel? ParseSettings(XElement task)
    {
        var s = task.Element(Ns + "Settings");
        if (s is null) return null;

        return new SettingsModel
        {
            Enabled = GetBool(s, true, "Enabled"),
            ExecutionTimeLimit = s.Element(Ns + "ExecutionTimeLimit")?.Value,
            MultipleInstancesPolicy = s.Element(Ns + "MultipleInstancesPolicy")?.Value,
            DisallowStartIfOnBatteries = GetBool(s, true, "DisallowStartIfOnBatteries"),
            StopIfGoingOnBatteries = GetBool(s, true, "StopIfGoingOnBatteries"),
            RunOnlyIfIdle = GetBool(s, false, "RunOnlyIfIdle"),
            RunOnlyIfNetworkAvailable = GetBool(s, false, "RunOnlyIfNetworkAvailable"),
            StartWhenAvailable = GetBool(s, false, "StartWhenAvailable"),
            WakeToRun = GetBool(s, false, "WakeToRun"),
        };
    }

    private static string? GetText(XElement root, params string[] path)
    {
        XElement? cur = root;
        foreach (var p in path)
        {
            cur = cur?.Element(Ns + p);
            if (cur is null) return null;
        }
        return cur?.Value;
    }

    private static bool GetBool(XElement root, bool @default, params string[] path)
    {
        var text = GetText(root, path);
        if (string.IsNullOrWhiteSpace(text)) return @default;
        return text.Trim() == "true";
    }
}
