using System.Text.Json.Serialization;

namespace Taskctl.Data;

internal sealed class Registry
{
    [JsonPropertyName("codes")]
    public List<RegistryCode> Codes { get; set; } = new();

    [JsonPropertyName("fallback")]
    public RegistryFallback Fallback { get; set; } = new();

    [JsonPropertyName("meta")]
    public RegistryMeta Meta { get; set; } = new();
}

internal sealed class RegistryMeta
{
    [JsonPropertyName("severities")]
    public List<string> Severities { get; set; } = new();

    [JsonPropertyName("ranks")]
    public List<string> Ranks { get; set; } = new();

    [JsonPropertyName("kinds")]
    public List<string> Kinds { get; set; } = new();
}

internal sealed class RegistryCode
{
    [JsonPropertyName("key")]
    public string Key { get; set; } = "";

    [JsonPropertyName("constant")]
    public string Constant { get; set; } = "";

    [JsonPropertyName("kind")]
    public string Kind { get; set; } = "";

    [JsonPropertyName("severity")]
    public string Severity { get; set; } = "";

    [JsonPropertyName("next_rank")]
    public string NextRank { get; set; } = "";

    [JsonPropertyName("is_failure")]
    public bool IsFailure { get; set; }

    // 0x8004xxxx 系は符号付き/符号なしの二義性があるため省略される。
    [JsonPropertyName("dec")]
    public long? Dec { get; set; }
}

internal sealed class RegistryFallback
{
    [JsonPropertyName("unknown")]
    public RegistryFallbackEntry Unknown { get; set; } = new();

    [JsonPropertyName("hresult_from_win32")]
    public RegistryFallbackEntry HresultFromWin32 { get; set; } = new();
}

internal sealed class RegistryFallbackEntry
{
    [JsonPropertyName("severity")]
    public string Severity { get; set; } = "";

    [JsonPropertyName("rank")]
    public string Rank { get; set; } = "";
}
