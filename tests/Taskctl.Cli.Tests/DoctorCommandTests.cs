using System.Text.Json;
using Taskctl.Acquisition;
using Taskctl.Cli;
using Taskctl.Model;

namespace Taskctl.Cli.Tests;

// doctor の統合テスト。取得層 (ITaskAcquirer) を差し替え、実機に依存せず検証する。
public class DoctorCommandTests
{
    private static string FixturePath(string name) => Path.Combine(AppContext.BaseDirectory, "fixtures", name);

    private sealed class FakeAcquirer : ITaskAcquirer
    {
        private readonly List<AcquiredTask> _tasks;
        public FakeAcquirer(params AcquiredTask[] tasks) => _tasks = tasks.ToList();

        public List<AcquiredTask> Acquire(string? taskName, bool includeMicrosoft)
        {
            if (string.IsNullOrWhiteSpace(taskName)) return _tasks;
            return _tasks.Where(t => t.TaskName == taskName).ToList();
        }
    }

    private static AcquiredTask NewAcquired(
        string fixture, string name, string state = "Ready",
        long lastTaskResult = 0,
        DateTime? lastRunTime = null, DateTime? nextRunTime = null,
        string? acquireError = null)
    {
        var xml = File.ReadAllText(FixturePath(fixture));
        var model = TaskXmlParser.Parse(xml, name, "\\");
        return new AcquiredTask
        {
            TaskName = name,
            TaskPath = "\\",
            FullName = "\\" + name,
            State = state,
            Model = model,
            Info = new TaskInfoModel
            {
                LastRunTime = lastRunTime ?? new DateTime(2026, 7, 15, 2, 0, 0),
                LastTaskResult = lastTaskResult,
                NextRunTime = nextRunTime ?? new DateTime(2026, 7, 16, 2, 0, 0),
                NumberOfMissedRuns = 0,
            },
            AcquireError = acquireError,
        };
    }

    private static (string stdout, int exitCode) RunText(CliArgs args, ITaskAcquirer acquirer)
    {
        var sw = new StringWriter();
        var original = Console.Out;
        Console.SetOut(sw);
        try
        {
            var exit = DoctorCommand.Run(args, acquirer);
            return (sw.ToString(), exit);
        }
        finally { Console.SetOut(original); }
    }

    private static (JsonDocument json, int exitCode) RunJson(CliArgs args, ITaskAcquirer acquirer)
    {
        var (text, exit) = RunText(args, acquirer);
        return (JsonDocument.Parse(text), exit);
    }

    [Fact]
    public void 失敗タスクの最終結果を三点セットで示す()
    {
        var acq = NewAcquired("normal.xml", "FailingTask", lastTaskResult: 2);
        var (text, exit) = RunText(new CliArgs { Command = "doctor", Lang = "ja" }, new FakeAcquirer(acq));
        Assert.Contains("ERROR_FILE_NOT_FOUND", text);
        Assert.Contains("0x00000002", text);
        Assert.Contains("これは何", text);
        Assert.Contains("次の一手", text);
        Assert.Equal(2, exit);
    }

    [Fact]
    public void JSONにexit_codeと言語非依存フィールドを載せる()
    {
        var acq = NewAcquired("normal.xml", "FailingTask", lastTaskResult: 2);
        var (json, exit) = RunJson(new CliArgs { Command = "doctor", Lang = "ja", Json = true }, new FakeAcquirer(acq));
        Assert.Equal(2, exit);
        Assert.Equal(2, json.RootElement.GetProperty("exit_code").GetInt32());
        Assert.Equal(1, json.RootElement.GetProperty("scanned").GetInt32());
        var t0 = json.RootElement.GetProperty("tasks")[0];
        Assert.Equal("0x00000002", t0.GetProperty("last_result").GetProperty("code").GetString());
        Assert.Equal("ERROR_FILE_NOT_FOUND", t0.GetProperty("last_result").GetProperty("constant").GetString());
        Assert.True(t0.GetProperty("last_result").GetProperty("is_failure").GetBoolean());
    }

    [Fact]
    public void 未知の非ゼロ結果コードでも失敗として扱う()
    {
        // 0x00002EE7 (12007) は翻訳表に無い。実機で観測された実際の値。
        var acq = NewAcquired("normal.xml", "UnknownFail", lastTaskResult: 12007);
        var (text, exit) = RunText(new CliArgs { Command = "doctor", Lang = "ja" }, new FakeAcquirer(acq));
        Assert.Equal(2, exit);
        Assert.Contains("UnknownFail", text);
        Assert.Contains("0x00002EE7", text);
        Assert.Contains("翻訳表に無い", text);
        Assert.Contains("次の一手 [調査]", text);
    }

    [Fact]
    public void error重大度の結果コードで終了コード3()
    {
        // SCHED_E_SERVICE_NOT_RUNNING (0x80041315) は registry で severity: error
        var acq = NewAcquired("normal.xml", "ErrorTask", lastTaskResult: -2147216619);
        var (text, exit) = RunText(new CliArgs { Command = "doctor", Lang = "ja" }, new FakeAcquirer(acq));
        Assert.Contains("SCHED_E_SERVICE_NOT_RUNNING", text);
        Assert.Equal(3, exit);
    }

    [Fact]
    public void 成功タスクは終了コード0で走査時は結果コードを載せない()
    {
        var acq = NewAcquired("normal.xml", "HealthyTask", lastTaskResult: 0);
        var (text, exit) = RunText(new CliArgs { Command = "doctor", Lang = "ja" }, new FakeAcquirer(acq));
        Assert.Equal(0, exit);
        Assert.DoesNotContain("S_OK", text);
    }

    [Fact]
    public void 深掘り時は成功でも結果コードを翻訳して示す()
    {
        var acq = NewAcquired("normal.xml", "HealthyTask", lastTaskResult: 0);
        var (text, _) = RunText(new CliArgs { Command = "doctor", Lang = "ja", Positional = "HealthyTask" }, new FakeAcquirer(acq));
        Assert.Contains("S_OK", text);
        Assert.Contains("正常終了", text);
    }

    [Fact]
    public void noticeだけのタスクは走査時に隠れ深掘りで出る()
    {
        var acq = NewAcquired("logon-only.xml", "NoticeOnly", lastTaskResult: 0, nextRunTime: DateTime.MinValue);
        var (scanText, scanExit) = RunText(new CliArgs { Command = "doctor", Lang = "ja" }, new FakeAcquirer(acq));
        Assert.Equal(0, scanExit);
        Assert.DoesNotContain("run_only_if_logged_on", scanText);
        Assert.Contains("NoticeOnly", scanText);

        var (deepText, _) = RunText(new CliArgs { Command = "doctor", Lang = "ja", Positional = "NoticeOnly" }, new FakeAcquirer(acq));
        Assert.Contains("run_only_if_logged_on", deepText);
    }

    [Fact]
    public void JSONにはnoticeも常に載せる()
    {
        var acq = NewAcquired("logon-only.xml", "NoticeOnly", lastTaskResult: 0, nextRunTime: DateTime.MinValue);
        var (json, _) = RunJson(new CliArgs { Command = "doctor", Lang = "ja", Json = true }, new FakeAcquirer(acq));
        Assert.True(json.RootElement.GetProperty("summary").GetProperty("notices").GetInt32() > 0);
        var rules = json.RootElement.GetProperty("tasks")[0].GetProperty("findings").EnumerateArray()
            .Select(f => f.GetProperty("rule").GetString()).ToList();
        Assert.Contains("run_only_if_logged_on", rules);
    }

    [Fact]
    public void 複数タスクの集計は最も重い深刻度で終了コードを決める()
    {
        var acq = new[]
        {
            NewAcquired("normal.xml", "Ok", lastTaskResult: 0),
            NewAcquired("relative-path.xml", "Warn", lastTaskResult: 0),
            NewAcquired("logon-only.xml", "Notice", lastTaskResult: 0, nextRunTime: DateTime.MinValue),
        };
        var (text, exit) = RunText(new CliArgs { Command = "doctor", Lang = "ja" }, new FakeAcquirer(acq));
        Assert.Equal(2, exit);
        Assert.Contains("走査 3 タスク", text);
    }

    [Fact]
    public void 取得に失敗したタスクは報告し他を落とさない()
    {
        var acq = new AcquiredTask
        {
            TaskName = "Broken",
            TaskPath = "\\",
            FullName = "\\Broken",
            State = "Unknown",
            Model = null,
            Info = null,
            AcquireError = "アクセスが拒否されました",
        };
        var (text, exit) = RunText(new CliArgs { Command = "doctor", Lang = "ja" }, new FakeAcquirer(acq));
        Assert.Contains("Broken", text);
        Assert.Contains("アクセスが拒否されました", text);
        Assert.Equal(2, exit); // 取得エラーは warning 扱い
    }

    [Fact]
    public void JSONにacquire_errorを載せる()
    {
        var acq = new AcquiredTask
        {
            TaskName = "Broken",
            TaskPath = "\\",
            FullName = "\\Broken",
            State = "Unknown",
            AcquireError = "アクセスが拒否されました",
        };
        var (json, _) = RunJson(new CliArgs { Command = "doctor", Lang = "ja", Json = true }, new FakeAcquirer(acq));
        Assert.Equal("アクセスが拒否されました", json.RootElement.GetProperty("tasks")[0].GetProperty("acquire_error").GetString());
    }

    [Fact]
    public void 日英でプロースが切り替わりルールIDと定数名は非翻訳()
    {
        var acq = NewAcquired("relative-path.xml", "I18nTask", lastTaskResult: 2);
        var ja = RunText(new CliArgs { Command = "doctor", Lang = "ja" }, new FakeAcquirer(acq)).stdout;
        var en = RunText(new CliArgs { Command = "doctor", Lang = "en" }, new FakeAcquirer(acq)).stdout;
        Assert.Contains("これは何", ja);
        Assert.Contains("What this is", en);
        foreach (var text in new[] { ja, en })
        {
            Assert.Contains("relative_command_without_workdir", text);
            Assert.Contains("ERROR_FILE_NOT_FOUND", text);
        }
    }

    [Fact]
    public void コマンドが実際に埋まりTASKNAMEのままにならない()
    {
        var acq = NewAcquired("network-drive.xml", "CopyPasteTask", lastTaskResult: 1);
        var (text, _) = RunText(new CliArgs { Command = "doctor", Lang = "ja", Positional = "CopyPasteTask" }, new FakeAcquirer(acq));
        Assert.Contains(@"powershell.exe -File Z:\scripts\backup.ps1", text);
        Assert.DoesNotContain("<COMMAND>", text);
        Assert.DoesNotContain("<TASKNAME>", text);
    }

    [Fact]
    public void verboseで生の設定を出す()
    {
        var acq = NewAcquired("network-drive.xml", "RawTask", lastTaskResult: 2);
        var (withoutRaw, _) = RunText(new CliArgs { Command = "doctor", Lang = "ja" }, new FakeAcquirer(acq));
        Assert.DoesNotContain("生の設定", withoutRaw);

        var (withRaw, _) = RunText(new CliArgs { Command = "doctor", Lang = "ja", Verbose = true }, new FakeAcquirer(acq));
        Assert.Contains("生の設定", withRaw);
        Assert.Contains("powershell.exe", withRaw);
        Assert.Contains("S-1-5-18", withRaw);
        Assert.Contains("TimeTrigger", withRaw);
        Assert.Contains("MultipleInstancesPolicy=Parallel", withRaw);
        Assert.Contains("%USERPROFILE%\\work", withRaw);
    }
}
