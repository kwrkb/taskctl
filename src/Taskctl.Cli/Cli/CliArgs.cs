namespace Taskctl.Cli;

// パース済みの引数。VISION の想定コマンド形（POSIX 風フラグ）に沿う。
internal sealed class CliArgs
{
    public string Command { get; init; } = "";
    public string? Positional { get; init; }
    public string? Lang { get; init; }
    public bool Json { get; init; }
    public bool Verbose { get; init; }

    public static CliArgs Parse(string[] argv)
    {
        if (argv.Length == 0)
        {
            return new CliArgs { Command = "" };
        }

        string first = argv[0];
        if (first is "--help" or "-h" or "help")
        {
            return new CliArgs { Command = "help" };
        }

        string command = first;
        string? positional = null;
        string? lang = null;
        bool json = false;
        bool verbose = false;

        for (int i = 1; i < argv.Length; i++)
        {
            var a = argv[i];
            if (a == "--lang")
            {
                if (i + 1 >= argv.Length)
                    throw new ArgumentException("--lang には言語を指定してください（例: --lang ja）");
                lang = argv[++i];
            }
            else if (a.StartsWith("--lang=", StringComparison.Ordinal))
            {
                lang = a.Substring("--lang=".Length);
            }
            else if (a == "--json")
            {
                json = true;
            }
            else if (a == "--verbose")
            {
                verbose = true;
            }
            else if (a is "--help" or "-h")
            {
                return new CliArgs { Command = "help" };
            }
            else if (a.StartsWith("--", StringComparison.Ordinal))
            {
                throw new ArgumentException($"不明なフラグです: {a}");
            }
            else
            {
                if (positional is not null)
                    throw new ArgumentException($"位置引数が多すぎます: {a}");
                positional = a;
            }
        }

        return new CliArgs
        {
            Command = command,
            Positional = positional,
            Lang = lang,
            Json = json,
            Verbose = verbose,
        };
    }
}
