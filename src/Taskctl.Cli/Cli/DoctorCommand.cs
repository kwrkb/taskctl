using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using Taskctl.Acquisition;
using Taskctl.Data;
using Taskctl.Doctor;
using Taskctl.I18n;

namespace Taskctl.Cli;

internal static class DoctorCommand
{
    private static readonly JsonSerializerOptions JsonOutput = new()
    {
        TypeInfoResolver = DataJsonContext.Default,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = true,
    };

    public static int Run(CliArgs args, ITaskAcquirer? acquirer = null, DiagnosisContext? context = null)
    {
        var locale = LocaleResolver.Resolve(args.Lang);
        bool deepDive = !string.IsNullOrWhiteSpace(args.Positional);

        acquirer ??= new PowerShellTaskAcquirer();

        List<AcquiredTask> acquired;
        try
        {
            acquired = acquirer.Acquire(args.Positional, includeMicrosoft: false);
        }
        catch (InvalidOperationException ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }

        context ??= DiagnosisContext.Live();
        var results = acquired
            .Select(a => DiagnosisEngine.Diagnose(a, locale, deepDive, context))
            .ToList();

        // 終了コード: error -> 3, warning -> 2, それ以外 -> 0
        var severities = results.SelectMany(r => r.AllFindings()).Select(f => f.Severity).ToList();
        // 取得できなかったタスクは「問題なし」と言えない（診断できていないだけ）。
        // 重大とも断定できないので warning 扱い（＝レポートが不完全である、という警告）。
        int acquireErrors = results.Count(r => r.AcquireError is not null);
        int exitCode = severities.Contains("error") ? 3
            : (severities.Contains("warning") || acquireErrors > 0) ? 2
            : 0;

        if (args.Json)
        {
            var model = new DoctorJsonModel
            {
                Locale = locale,
                Scanned = results.Count,
                ExitCode = exitCode,
                Summary = new DoctorSummary
                {
                    Errors = severities.Count(s => s == "error"),
                    Warnings = severities.Count(s => s == "warning"),
                    Notices = severities.Count(s => s == "notice"),
                    AcquireErrors = acquireErrors,
                },
                Tasks = results.Select(r => DoctorTaskJsonModel.From(r, locale)).ToList(),
            };
            var typeInfo = (JsonTypeInfo<DoctorJsonModel>)JsonOutput.GetTypeInfo(typeof(DoctorJsonModel));
            Console.Out.WriteLine(JsonSerializer.Serialize(model, typeInfo));
            return exitCode;
        }

        ConsoleEncoding.EnsureUtf8();
        var text = DoctorReportFormatter.Format(results, locale, deepDive, args.Verbose);
        Console.Out.WriteLine(text);

        var hint = ConsoleEncoding.GetEncodingHint(locale);
        if (hint is not null)
        {
            Console.Out.WriteLine();
            Console.Out.WriteLine(hint);
        }
        return exitCode;
    }
}
