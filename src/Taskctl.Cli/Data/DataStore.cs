using System.Reflection;
using System.Text.Json;

namespace Taskctl.Data;

// アセンブリに埋め込んだ JSON を読み込んでキャッシュする。
// PowerShell 版と正本を共有（build/Convert-DataToJson.ps1 が生成した JSON を埋込）。
internal static class DataStore
{
    private static Registry? _registry;
    private static RulesFile? _rules;
    private static readonly Dictionary<string, Catalog> _catalogs = new(StringComparer.OrdinalIgnoreCase);
    private static string[]? _supportedLocales;

    public static Registry GetRegistry()
        => _registry ??= Load("registry.json", DataJsonContext.Default.Registry);

    public static RulesFile GetRules()
        => _rules ??= Load("rules.json", DataJsonContext.Default.RulesFile);

    public static Catalog GetCatalog(string locale)
    {
        if (_catalogs.TryGetValue(locale, out var cached)) return cached;
        var cat = Load($"messages.{locale}.json", DataJsonContext.Default.Catalog);
        _catalogs[locale] = cat;
        return cat;
    }

    public static IReadOnlyList<string> GetSupportedLocales()
    {
        if (_supportedLocales is not null) return _supportedLocales;
        var asm = typeof(DataStore).Assembly;
        var locales = new List<string>();
        foreach (var name in asm.GetManifestResourceNames())
        {
            if (name.StartsWith("messages.", StringComparison.Ordinal) &&
                name.EndsWith(".json", StringComparison.Ordinal))
            {
                var locale = name.Substring("messages.".Length, name.Length - "messages.".Length - ".json".Length);
                if (!string.IsNullOrWhiteSpace(locale)) locales.Add(locale);
            }
        }
        locales.Sort(StringComparer.Ordinal);
        _supportedLocales = locales.ToArray();
        return _supportedLocales;
    }

    private static T Load<T>(string resourceName, System.Text.Json.Serialization.Metadata.JsonTypeInfo<T> typeInfo)
    {
        var asm = typeof(DataStore).Assembly;
        using var stream = asm.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"埋込リソースが見つかりません: {resourceName}");
        var obj = JsonSerializer.Deserialize(stream, typeInfo)
            ?? throw new InvalidOperationException($"埋込リソースの解析に失敗しました: {resourceName}");
        return obj;
    }
}
