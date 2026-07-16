using System.Text.Json;
using System.Text.Json.Serialization;

namespace Taskctl.Data;

// System.Text.Json のソースジェネレータ。NativeAOT でリフレクションを避けるため、
// 逆・順シリアライズする全ルート型をここで宣言する。
[JsonSerializable(typeof(Registry))]
[JsonSerializable(typeof(Catalog))]
[JsonSerializable(typeof(RulesFile))]
[JsonSerializable(typeof(Findings.FindingJsonModel))]
[JsonSerializable(typeof(Rules.RuleFindingJsonModel))]
[JsonSerializable(typeof(Acquisition.RawAcquireOutput))]
[JsonSerializable(typeof(Doctor.DoctorJsonModel))]
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower,
    ReadCommentHandling = JsonCommentHandling.Skip,
    AllowTrailingCommas = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    WriteIndented = true)]
internal partial class DataJsonContext : JsonSerializerContext
{
}
