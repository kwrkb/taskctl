using System.Text.Json.Serialization;

namespace Taskctl.Data;

// メッセージカタログ（ja / en）。翻訳される「プロース層」のみを持つ。
// コード値・定数名・コマンドなどの機械識別子はレジストリ側に置く。
internal sealed class Catalog
{
    [JsonPropertyName("codes")]
    public Dictionary<string, CatalogProse> Codes { get; set; } = new();

    // 検出ルールごとの meaning / cause / next。Phase 2 で使う。
    [JsonPropertyName("rules")]
    public Dictionary<string, CatalogProse> Rules { get; set; } = new();

    [JsonPropertyName("fallback")]
    public CatalogFallback Fallback { get; set; } = new();

    [JsonPropertyName("snippets")]
    public Dictionary<string, string> Snippets { get; set; } = new();

    [JsonPropertyName("headings")]
    public CatalogHeadings Headings { get; set; } = new();

    [JsonPropertyName("kinds")]
    public Dictionary<string, CatalogLabel> Kinds { get; set; } = new();

    [JsonPropertyName("ranks")]
    public Dictionary<string, CatalogLabel> Ranks { get; set; } = new();

    [JsonPropertyName("locale")]
    public string Locale { get; set; } = "";
}

internal sealed class CatalogProse
{
    [JsonPropertyName("meaning")]
    public string? Meaning { get; set; }

    [JsonPropertyName("cause")]
    public string? Cause { get; set; }

    [JsonPropertyName("next")]
    public string? Next { get; set; }
}

internal sealed class CatalogFallback
{
    [JsonPropertyName("unknown")]
    public CatalogProse Unknown { get; set; } = new();

    [JsonPropertyName("hresult_from_win32")]
    public CatalogProse HresultFromWin32 { get; set; } = new();
}

internal sealed class CatalogHeadings
{
    [JsonPropertyName("meaning")]
    public string Meaning { get; set; } = "";

    [JsonPropertyName("cause")]
    public string Cause { get; set; } = "";

    [JsonPropertyName("next")]
    public string Next { get; set; } = "";
}

internal sealed class CatalogLabel
{
    [JsonPropertyName("label")]
    public string Label { get; set; } = "";
}
