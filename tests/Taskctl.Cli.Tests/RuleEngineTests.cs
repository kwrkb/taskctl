using Taskctl.Data;
using Taskctl.Model;
using Taskctl.Rules;

namespace Taskctl.Cli.Tests;

public class RuleEngineTests
{
    private static readonly DateTime FixedNow = new(2026, 7, 15, 12, 0, 0);
    private static readonly string[] Drives = { "C" };
    private const string FixtureSid = "S-1-5-21-1111111111-2222222222-3333333333-1001";
    private const string OtherSid = "S-1-5-21-9999999999-8888888888-7777777777-1002";

    private static string FixturePath(string name) => Path.Combine(AppContext.BaseDirectory, "fixtures", name);

    private static List<string> GetIds(string fixture, TaskInfoModel? info, string? currentSid = null)
    {
        var xml = File.ReadAllText(FixturePath(fixture));
        var model = TaskXmlParser.Parse(xml, "Fixture", "\\");
        return RuleEngine.Evaluate(model, info, FixedNow, Drives, Array.Empty<string>(), Array.Empty<string>(),
                currentSid ?? FixtureSid, "TESTHOST\\fixture")
            .Select(f => f.RuleId)
            .ToList();
    }

    [Fact]
    public void normal_所見を出さない()
    {
        var info = new TaskInfoModel { LastRunTime = new DateTime(2026, 7, 15, 2, 0, 0), NextRunTime = new DateTime(2026, 7, 16, 2, 0, 0) };
        Assert.Empty(GetIds("normal.xml", info));
    }

    [Fact]
    public void notriggerdisabled_タスク無効を検出する()
    {
        var ids = GetIds("no-trigger-disabled.xml", new TaskInfoModel());
        Assert.Contains("task_disabled", ids);
        Assert.Contains("command_not_found", ids);
        Assert.Contains("multiple_instances_parallel", ids);
        Assert.DoesNotContain("no_triggers", ids);
        Assert.DoesNotContain("never_run", ids);
        Assert.DoesNotContain("no_next_run", ids);
    }

    [Fact]
    public void relativepath_作業ディレクトリ未設定と相対パス()
    {
        var info = new TaskInfoModel { LastRunTime = new DateTime(2026, 7, 15, 9, 0, 0), NextRunTime = new DateTime(2026, 7, 16, 9, 0, 0) };
        var ids = GetIds("relative-path.xml", info);
        Assert.Contains("relative_command_without_workdir", ids);
        Assert.DoesNotContain("command_not_found", ids);
        Assert.Contains("run_only_if_logged_on", ids);
    }

    [Fact]
    public void networkdrive_マップドライブとプロファイル依存と短い実行時間制限()
    {
        var info = new TaskInfoModel { LastRunTime = new DateTime(2026, 7, 15, 3, 0, 0), NextRunTime = new DateTime(2026, 7, 16, 3, 0, 0) };
        var ids = GetIds("network-drive.xml", info);
        Assert.Contains("mapped_drive_dependency", ids);
        Assert.Contains("profile_dependency_as_service", ids);
        Assert.Contains("short_execution_time_limit", ids);
        Assert.DoesNotContain("working_directory_not_found", ids);
    }

    [Fact]
    public void logononly_条件付き実行と期限切れを検出する()
    {
        var info = new TaskInfoModel { LastRunTime = new DateTime(2020, 12, 31, 12, 0, 0) };
        var ids = GetIds("logon-only.xml", info);
        Assert.Contains("run_only_if_logged_on", ids);
        Assert.Contains("ac_power_only", ids);
        Assert.Contains("idle_only", ids);
        Assert.Contains("network_only", ids);
        Assert.Contains("past_end_boundary", ids);
        Assert.DoesNotContain("no_next_run", ids);
    }

    [Fact]
    public void v1のルールにfixは一つも無い()
    {
        var ranks = DataStore.GetRules().Rules.Select(r => r.Rank).ToList();
        Assert.DoesNotContain("fix", ranks);
    }

    [Theory]
    [InlineData("command_not_found")]
    [InlineData("working_directory_not_found")]
    public void 存在チェックはerrorにしない(string id)
    {
        var rule = DataStore.GetRules().Rules.Single(r => r.Id == id);
        Assert.NotEqual("error", rule.Severity);
        Assert.Equal("investigate", rule.Rank);
    }

    [Fact]
    public void ファクトが算出不能なら発火しない()
    {
        var ids = GetIds("normal.xml", null);
        Assert.DoesNotContain("never_run", ids);
        Assert.DoesNotContain("no_next_run", ids);
        Assert.DoesNotContain("stale_last_run", ids);
    }

    [Fact]
    public void 他ユーザーのタスクでは存在チェックしない()
    {
        var ids = GetIds("no-trigger-disabled.xml", new TaskInfoModel(), OtherSid);
        Assert.DoesNotContain("command_not_found", ids);
    }

    [Fact]
    public void 本人のタスクなら存在チェックする()
    {
        var ids = GetIds("no-trigger-disabled.xml", new TaskInfoModel(), FixtureSid);
        Assert.Contains("command_not_found", ids);
    }

    [Fact]
    public void SYSTEM実行のタスクでは存在チェックしない()
    {
        var info = new TaskInfoModel { LastRunTime = new DateTime(2026, 7, 15, 3, 0, 0), NextRunTime = new DateTime(2026, 7, 16, 3, 0, 0) };
        var ids = GetIds("network-drive.xml", info);
        Assert.DoesNotContain("command_not_found", ids);
        Assert.DoesNotContain("working_directory_not_found", ids);
    }

    [Fact]
    public void 長期未実行_90日以上前なら検出する()
    {
        var info = new TaskInfoModel { LastRunTime = new DateTime(2026, 1, 1, 2, 0, 0), NextRunTime = new DateTime(2026, 7, 16, 2, 0, 0) };
        Assert.Contains("stale_last_run", GetIds("normal.xml", info));
    }

    [Fact]
    public void 長期未実行_90日未満なら検出しない()
    {
        var info = new TaskInfoModel { LastRunTime = new DateTime(2026, 7, 1, 2, 0, 0), NextRunTime = new DateTime(2026, 7, 16, 2, 0, 0) };
        Assert.DoesNotContain("stale_last_run", GetIds("normal.xml", info));
    }

    [Fact]
    public void 全ルールIDにjaとenのプロースがある()
    {
        var ids = DataStore.GetRules().Rules.Select(r => r.Id).ToList();
        foreach (var locale in new[] { "ja", "en" })
        {
            var cat = DataStore.GetCatalog(locale);
            foreach (var id in ids)
            {
                Assert.True(cat.Rules.TryGetValue(id, out var prose), $"{locale} に {id} が無い");
                Assert.False(string.IsNullOrWhiteSpace(prose!.Meaning), $"{locale} の {id}.meaning");
                Assert.False(string.IsNullOrWhiteSpace(prose.Next), $"{locale} の {id}.next");
            }
        }
    }

    [Fact]
    public void カタログに存在しないルールIDのプロースが残っていない()
    {
        var ids = DataStore.GetRules().Rules.Select(r => r.Id).ToHashSet();
        foreach (var locale in new[] { "ja", "en" })
        {
            var cat = DataStore.GetCatalog(locale);
            foreach (var key in cat.Rules.Keys)
            {
                Assert.Contains(key, ids);
            }
        }
    }

    [Fact]
    public void プロースのプレースホルダが展開され残らない()
    {
        var info = new TaskInfoModel { LastRunTime = new DateTime(2026, 1, 1, 2, 0, 0) };
        foreach (var locale in new[] { "ja", "en" })
        {
            var xml = File.ReadAllText(FixturePath("network-drive.xml"));
            var model = TaskXmlParser.Parse(xml, "Fixture");
            var findings = RuleEngine.Evaluate(model, info, FixedNow, Drives, Array.Empty<string>(), Array.Empty<string>());
            foreach (var f in findings)
            {
                RuleProseResolver.Resolve(f, locale);
                var text = $"{f.Meaning}\n{f.Cause}\n{f.Next}";
                Assert.DoesNotContain("{{", text);
            }
        }
    }
}
