using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using Taskctl.Codes;
using Taskctl.Data;
using Taskctl.Findings;
using Taskctl.I18n;

namespace Taskctl.Cli;

internal static class ExplainCommand
{
    // 出力用オプション。ソースジェネレータの TypeInfoResolver をそのまま流用しつつ、
    // Encoder を UnsafeRelaxedJsonEscaping にして日本語を \uXXXX に逃さない
    // （VISION: --json は常に UTF-8）。JsonTypeInfo を options 越しに取得することで AOT 安全。
    private static readonly JsonSerializerOptions JsonOutput = new()
    {
        TypeInfoResolver = DataJsonContext.Default,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = true,
    };

    public static int Run(CliArgs args)
    {
        if (args.Positional is null)
        {
            Console.Error.WriteLine("explain には結果コードを指定してください（例: taskctl explain 0x41303）");
            return 1;
        }

        var locale = LocaleResolver.Resolve(args.Lang);
        var finding = ResultCodeResolver.Resolve(args.Positional, locale);

        if (args.Json)
        {
            var model = FindingJsonModel.From(finding, locale);
            var typeInfo = (JsonTypeInfo<FindingJsonModel>)JsonOutput.GetTypeInfo(typeof(FindingJsonModel));
            var json = JsonSerializer.Serialize(model, typeInfo);
            Console.Out.WriteLine(json);
            return 0;
        }

        ConsoleEncoding.EnsureUtf8();
        var text = FindingFormatter.Format(finding, locale);
        Console.Out.WriteLine(text);

        var hint = ConsoleEncoding.GetEncodingHint(locale);
        if (hint is not null)
        {
            Console.Out.WriteLine();
            Console.Out.WriteLine(hint);
        }
        return 0;
    }
}
