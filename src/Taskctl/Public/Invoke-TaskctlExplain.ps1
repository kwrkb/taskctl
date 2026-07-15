<#
.SYNOPSIS
    結果コード単体を翻訳する（taskctl explain <code>）。
.DESCRIPTION
    タスクスケジューラの結果コードを、状態コード / スケジューラエラー / システムエラー /
    アプリの終了コードを区別して説明し、次の一手を確信度つきで示す。
    設定は一切変更しない（read-only）。
.PARAMETER Code
    結果コード。16進 (0x41303) / 10進 (267011) / 符号付き10進 (-2147024891) のいずれも可。
.PARAMETER Lang
    表示言語（ja / en）。既定は TASKCTL_LANG > OS の UI カルチャ > en の順で決定。
.PARAMETER Json
    構造化出力（常に UTF-8。言語非依存フィールド + 現在ロケールの文言）。
.EXAMPLE
    Invoke-TaskctlExplain 0x41303
.EXAMPLE
    taskctl explain -2147024891 --lang en --json
#>
function Invoke-TaskctlExplain {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Code,

        [ValidateNotNullOrEmpty()]
        [string] $Lang,

        [switch] $Json
    )

    $locale = Resolve-TaskctlLocale -Lang $Lang
    $finding = Resolve-TaskctlResultCode -Code $Code -Locale $locale

    if ($Json) {
        # --json は表示ロケールに関わらず常に UTF-8。エンコーディング調整もしない。
        return ConvertTo-TaskctlJson (ConvertTo-TaskctlJsonModel -Finding $finding -Locale $locale)
    }

    Initialize-TaskctlConsole -Confirm:$false
    $text = Format-TaskctlFinding -Finding $finding -Locale $locale

    $hint = Get-TaskctlEncodingHint -Locale $locale
    if ($hint) {
        $text = "$text`n`n$hint"
    }
    $text
}
