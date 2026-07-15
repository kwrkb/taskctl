<#
.SYNOPSIS
    表示ロケールを決定する。
.DESCRIPTION
    VISION の優先順位（ブラウザの Accept-Language は無いので決め打ち）:
      1. --lang（明示フラグ）
      2. 環境変数 TASKCTL_LANG
      3. OS の UI カルチャ（$PSUICulture）
      4. 既定 = en
    どの段でも「ja-JP」のような形は先頭のサブタグで判定し、
    未対応なら次の段へ落ちる（最終的に en）。空文字は絶対に返さない。
#>
function Resolve-TaskctlLocale {
    [CmdletBinding()]
    param(
        [string] $Lang,
        [string] $EnvLang = $env:TASKCTL_LANG,
        [string] $UICulture = $PSUICulture,
        [string[]] $Supported = (Get-TaskctlSupportedLocale)
    )

    if (-not $Supported -or $Supported.Count -eq 0) {
        throw 'メッセージカタログが1つも見つかりません。build\Convert-DataToJson.ps1 を実行してください。'
    }

    $fallback = if ($Supported -contains 'en') { 'en' } else { $Supported[0] }

    foreach ($candidate in @($Lang, $EnvLang, $UICulture)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        # ja-JP -> ja、en_US -> en
        $subtag = ($candidate.Trim() -split '[-_]')[0].ToLowerInvariant()
        if ($Supported -contains $subtag) { return $subtag }
    }

    $fallback
}
