namespace Taskctl.Findings;

// 1件の所見。VISION の3点セット（Meaning / Cause / Next）と、
// JSON 出力に必要な機械識別子（Kind / Severity / Rank / IsFailure / MessageKey / Constant）を持つ。
internal sealed class Finding : ISeverityFinding
{
    public required string Code { get; init; }
    public required long Decimal { get; init; }
    public required int Signed { get; init; }
    public string? Constant { get; init; }
    public required string Kind { get; init; }
    public required string Severity { get; init; }
    public required string Rank { get; init; }
    public required bool IsFailure { get; init; }
    public required string MessageKey { get; init; }
    public required bool IsKnown { get; init; }
    public string? Meaning { get; set; }
    public string? Cause { get; set; }
    public string? Next { get; set; }
    // HRESULT_FROM_WIN32 fallback で下位16bit の Win32 コードを保持する（プレースホルダ展開用）。
    public long? Win32 { get; init; }
    // Windows の FormatMessage が返す OS ローカライズ文言（未知コードの補助表示用。任意）。
    public string? OsMessage { get; set; }
}
