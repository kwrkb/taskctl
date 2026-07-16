using System.Text.Json.Serialization;

namespace Taskctl.Findings;

// VISION §5: --json は言語非依存フィールド + 現在ロケールの message/action を持つ。
// 消費側は message_key で自前ローカライズも、提供テキストの利用も選べる。
internal sealed class FindingJsonModel
{
    [JsonPropertyName("code")]
    public string Code { get; set; } = "";

    [JsonPropertyName("code_dec")]
    public long CodeDec { get; set; }

    [JsonPropertyName("code_signed")]
    public int CodeSigned { get; set; }

    [JsonPropertyName("constant")]
    public string? Constant { get; set; }

    [JsonPropertyName("kind")]
    public string Kind { get; set; } = "";

    [JsonPropertyName("severity")]
    public string Severity { get; set; } = "";

    [JsonPropertyName("is_failure")]
    public bool IsFailure { get; set; }

    [JsonPropertyName("rank")]
    public string Rank { get; set; } = "";

    [JsonPropertyName("known")]
    public bool Known { get; set; }

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

    // 未知コードのみ、OS の FormatMessage 訳文（あれば）。カタログの文言と混ざらないよう別フィールド。
    [JsonPropertyName("os_message")]
    public string? OsMessage { get; set; }

    public static FindingJsonModel From(Finding f, string locale) => new()
    {
        Code = f.Code,
        CodeDec = f.Decimal,
        CodeSigned = f.Signed,
        Constant = f.Constant,
        Kind = f.Kind,
        Severity = f.Severity,
        IsFailure = f.IsFailure,
        Rank = f.Rank,
        Known = f.IsKnown,
        MessageKey = f.MessageKey,
        Locale = locale,
        Message = f.Meaning,
        Cause = f.Cause,
        Action = f.Next,
        OsMessage = f.OsMessage,
    };
}
