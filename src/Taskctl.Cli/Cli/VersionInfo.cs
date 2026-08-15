using System.Reflection;

namespace Taskctl.Cli;

// 導入されている版の自己申告。Scoop 経由で配られた exe でも、バグ報告に版を添えられるようにする。
internal static class VersionInfo
{
    // AssemblyInformationalVersion は SourceLink により "2.0.1+<commit sha>" になる。
    // 版の識別に sha は要らず、読み手には雑音なので落とす。
    public static string Value
    {
        get
        {
            var informational = typeof(VersionInfo).Assembly
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;

            if (string.IsNullOrWhiteSpace(informational))
            {
                // 属性が取れない環境でも空文字を出さない（i18n と同じく空表示を作らない）。
                return typeof(VersionInfo).Assembly.GetName().Version?.ToString() ?? "unknown";
            }

            int plus = informational.IndexOf('+');
            return plus < 0 ? informational : informational.Substring(0, plus);
        }
    }

    public static string Text => $"taskctl {Value}";
}
