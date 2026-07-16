using System.Text.RegularExpressions;
using Taskctl.Data;

namespace Taskctl.Cli.Tests;

// データ資産の整合性テスト。
// 原則: カタログ (ja/en) のキー集合 = レジストリのキー集合。空文字は絶対に出さない。
public partial class DataCoverageTests
{
    private static readonly string[] Locales = { "ja", "en" };

    [GeneratedRegex(@"^0x[0-9A-F]{8}$")]
    private static partial Regex KeyFormat();

    [GeneratedRegex(@"^https://learn\.microsoft\.com/")]
    private static partial Regex MsLearnUrl();

    [GeneratedRegex(@"\{\{([^}]+)\}\}")]
    private static partial Regex PlaceholderRef();

    [Fact]
    public void jaとenのカタログが存在する()
    {
        foreach (var l in Locales) DataStore.GetCatalog(l);
    }

    [Fact]
    public void コードのkeyに重複がない()
    {
        var keys = DataStore.GetRegistry().Codes.Select(c => c.Key).ToList();
        Assert.Equal(keys.Count, keys.Distinct().Count());
    }

    [Fact]
    public void keyは0xと大文字十六進八桁に正規化されている()
    {
        foreach (var c in DataStore.GetRegistry().Codes)
        {
            Assert.Matches(KeyFormat(), c.Key);
        }
    }

    [Fact]
    public void kind_severity_next_rankがmetaの定義域に収まる()
    {
        var meta = DataStore.GetRegistry().Meta;
        foreach (var c in DataStore.GetRegistry().Codes)
        {
            Assert.Contains(c.Kind, meta.Kinds);
            Assert.Contains(c.Severity, meta.Severities);
            Assert.Contains(c.NextRank, meta.Ranks);
        }
    }

    [Theory]
    [InlineData("ja")]
    [InlineData("en")]
    public void codesのキー集合がregistryと一致する(string locale)
    {
        var registryKeys = DataStore.GetRegistry().Codes.Select(c => c.Key).ToHashSet();
        var catKeys = DataStore.GetCatalog(locale).Codes.Keys.ToHashSet();
        Assert.True(registryKeys.SetEquals(catKeys),
            $"差分: registry-only={string.Join(",", registryKeys.Except(catKeys))} / catalog-only={string.Join(",", catKeys.Except(registryKeys))}");
    }

    [Theory]
    [InlineData("ja")]
    [InlineData("en")]
    public void 全コードにmeaningとnextがあり空文字が無い(string locale)
    {
        var cat = DataStore.GetCatalog(locale);
        foreach (var c in DataStore.GetRegistry().Codes)
        {
            var entry = cat.Codes[c.Key];
            Assert.False(string.IsNullOrWhiteSpace(entry.Meaning), $"{c.Key} の meaning");
            Assert.False(string.IsNullOrWhiteSpace(entry.Next), $"{c.Key} の next");
        }
    }

    [Theory]
    [InlineData("ja")]
    [InlineData("en")]
    public void 失敗コードにはcauseがある(string locale)
    {
        var cat = DataStore.GetCatalog(locale);
        foreach (var c in DataStore.GetRegistry().Codes.Where(c => c.IsFailure))
        {
            Assert.False(string.IsNullOrWhiteSpace(cat.Codes[c.Key].Cause), $"{c.Key} は失敗コード");
        }
    }

    [Theory]
    [InlineData("ja")]
    [InlineData("en")]
    public void fallbackのキー集合が一致しmeaning_cause_nextが揃う(string locale)
    {
        var cat = DataStore.GetCatalog(locale);
        foreach (var (name, prose) in new (string, CatalogProse)[]
                 {
                     ("unknown", cat.Fallback.Unknown),
                     ("hresult_from_win32", cat.Fallback.HresultFromWin32),
                 })
        {
            Assert.False(string.IsNullOrWhiteSpace(prose.Meaning), $"fallback {name} の meaning");
            Assert.False(string.IsNullOrWhiteSpace(prose.Cause), $"fallback {name} の cause");
            Assert.False(string.IsNullOrWhiteSpace(prose.Next), $"fallback {name} の next");
        }
    }

    [Theory]
    [InlineData("ja")]
    [InlineData("en")]
    public void メッセージ中のプレースホルダがすべて解決できる(string locale)
    {
        var cat = DataStore.GetCatalog(locale);
        var snippetKeys = cat.Snippets.Keys.ToHashSet();
        var valueKeys = new HashSet<string> { "win32", "task", "task_args", "task_regex", "command", "workdir", "days", "limit_seconds" };

        var texts = new List<string>();
        foreach (var kv in cat.Codes) texts.Add($"{kv.Value.Meaning}\n{kv.Value.Cause}\n{kv.Value.Next}");
        texts.Add($"{cat.Fallback.Unknown.Meaning}\n{cat.Fallback.Unknown.Cause}\n{cat.Fallback.Unknown.Next}");
        texts.Add($"{cat.Fallback.HresultFromWin32.Meaning}\n{cat.Fallback.HresultFromWin32.Cause}\n{cat.Fallback.HresultFromWin32.Next}");
        foreach (var kv in cat.Rules) texts.Add($"{kv.Value.Meaning}\n{kv.Value.Cause}\n{kv.Value.Next}");
        foreach (var kv in cat.Snippets) texts.Add(kv.Value);

        foreach (var text in texts)
        {
            foreach (Match m in PlaceholderRef().Matches(text))
            {
                var reference = m.Groups[1].Value;
                if (reference.StartsWith("snippets.", StringComparison.Ordinal))
                {
                    Assert.Contains(reference["snippets.".Length..], snippetKeys);
                }
                else
                {
                    Assert.Contains(reference, valueKeys);
                }
            }
        }
    }

    [Fact]
    public void snippetsのキー集合がjaとenで一致する()
    {
        var ja = DataStore.GetCatalog("ja").Snippets.Keys.ToHashSet();
        var en = DataStore.GetCatalog("en").Snippets.Keys.ToHashSet();
        Assert.True(ja.SetEquals(en));
    }

    [Fact]
    public void snippetsのコマンド行がjaとenで同一である()
    {
        var ja = DataStore.GetCatalog("ja").Snippets;
        var en = DataStore.GetCatalog("en").Snippets;
        foreach (var name in ja.Keys)
        {
            string CommandLines(string text) => string.Join('\n', text.Split('\n')
                .Where(l => !string.IsNullOrWhiteSpace(l) && !l.Trim().StartsWith('#')));
            Assert.Equal(CommandLines(ja[name]), CommandLines(en[name]));
        }
    }

    [Fact]
    public void sourceがあるエントリはMicrosoftの一次資料を指す()
    {
        // v1.1 以降に追加するエントリは検証した一次資料の URL を必ず持つ（ブログや二次情報は根拠にしない）。
        // C# 側の Registry モデルは source を保持していないため、ここでは埋込 JSON を直接読んで確認する。
        var asm = typeof(DataStore).Assembly;
        using var stream = asm.GetManifestResourceStream("registry.json")!;
        using var doc = System.Text.Json.JsonDocument.Parse(stream);
        foreach (var code in doc.RootElement.GetProperty("codes").EnumerateArray())
        {
            if (code.TryGetProperty("source", out var source))
            {
                Assert.Matches(MsLearnUrl(), source.GetString());
            }
        }
    }
}
