using System.Globalization;
using Taskctl.Data;

namespace Taskctl.I18n;

// 表示ロケールを決定する。VISION の優先順位:
//   1. --lang（明示フラグ）
//   2. 環境変数 TASKCTL_LANG
//   3. OS の UI カルチャ（CultureInfo.CurrentUICulture）
//   4. 既定 = en
// どの段も先頭のサブタグ（ja-JP -> ja）で判定し、未対応なら次の段へ。空文字は返さない。
internal static class LocaleResolver
{
    public static string Resolve(string? explicitLang, string? envLang = null, string? uiCulture = null)
    {
        var supported = DataStore.GetSupportedLocales();
        if (supported.Count == 0)
        {
            throw new InvalidOperationException("メッセージカタログが1つも埋め込まれていません。");
        }

        string fallback = supported.Contains("en") ? "en" : supported[0];

        envLang ??= Environment.GetEnvironmentVariable("TASKCTL_LANG");
        uiCulture ??= CultureInfo.CurrentUICulture.Name;

        foreach (var candidate in new[] { explicitLang, envLang, uiCulture })
        {
            if (string.IsNullOrWhiteSpace(candidate)) continue;
            var head = candidate.Trim().Split(new[] { '-', '_' }, 2)[0].ToLowerInvariant();
            if (supported.Contains(head)) return head;
        }

        return fallback;
    }
}
