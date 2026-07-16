using System.Text.Json.Serialization;

namespace Taskctl.Data;

// Phase 2 (doctor) で使う。Phase 1 では読み込むだけ。
internal sealed class RulesFile
{
    [JsonPropertyName("rules")]
    public List<Rule> Rules { get; set; } = new();
}

internal sealed class Rule
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("scope")]
    public string Scope { get; set; } = "";

    [JsonPropertyName("severity")]
    public string Severity { get; set; } = "";

    [JsonPropertyName("rank")]
    public string Rank { get; set; } = "";

    [JsonPropertyName("when")]
    public List<RuleClause> When { get; set; } = new();
}

// {fact, eq|gte|lte} のいずれか一つの比較演算子を持つ節。
// eq は bool / string / number いずれもありうるため、object? にしておき
// 評価器側で fact 値の型に合わせて比較する。
internal sealed class RuleClause
{
    [JsonPropertyName("fact")]
    public string Fact { get; set; } = "";

    [JsonPropertyName("eq")]
    public object? Eq { get; set; }

    [JsonPropertyName("gte")]
    public double? Gte { get; set; }

    [JsonPropertyName("lte")]
    public double? Lte { get; set; }
}
