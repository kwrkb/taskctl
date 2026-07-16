using Taskctl.Cli;
using Taskctl.I18n;

// AOT の起動直後にコンソールを UTF-8 へ寄せる（エラーメッセージも文字化けさせない）
ConsoleEncoding.EnsureUtf8();

try
{
    var parsed = CliArgs.Parse(args);

    switch (parsed.Command)
    {
        case "":
        case "help":
            Console.Out.WriteLine(Usage.Text);
            return 0;
        case "explain":
            return ExplainCommand.Run(parsed);
        case "doctor":
            return DoctorCommand.Run(parsed);
        default:
            Console.Error.WriteLine($"不明なコマンドです: {parsed.Command}");
            Console.Error.WriteLine();
            Console.Error.WriteLine(Usage.Text);
            return 1;
    }
}
catch (ArgumentException ex)
{
    Console.Error.WriteLine(ex.Message);
    Console.Error.WriteLine();
    Console.Error.WriteLine(Usage.Text);
    return 1;
}
catch (FormatException ex)
{
    Console.Error.WriteLine(ex.Message);
    return 1;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"エラー: {ex.Message}");
    return 1;
}
