using System.Text.Json.Serialization;

namespace Taskctl.Rules;

internal sealed class RuleFindingJsonModel
{
    [JsonPropertyName("rule")]
    public string Rule { get; set; } = "";

    [JsonPropertyName("severity")]
    public string Severity { get; set; } = "";

    [JsonPropertyName("rank")]
    public string Rank { get; set; } = "";

    [JsonPropertyName("message_key")]
    public string MessageKey { get; set; } = "";

    [JsonPropertyName("locale")]
    public string Locale { get; set; } = "";

    [JsonPropertyName("message")]
    public string? Message { get; set; }

    [JsonPropertyName("cause")]
    public string? Cause { get; set; }

    [JsonPropertyName("action")]
    public string? Action { get; set; }

    [JsonPropertyName("target")]
    public string? Target { get; set; }

    public static RuleFindingJsonModel From(RuleFinding f, string locale) => new()
    {
        Rule = f.RuleId,
        Severity = f.Severity,
        Rank = f.Rank,
        MessageKey = f.MessageKey,
        Locale = locale,
        Message = f.Meaning,
        Cause = f.Cause,
        Action = f.Next,
        Target = f.Values.TryGetValue("command", out var cmd) ? cmd : null,
    };
}
