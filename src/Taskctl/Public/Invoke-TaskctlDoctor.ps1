<#
.SYNOPSIS
    タスクの健康診断（taskctl doctor）。read-only で、設定は一切変更しない。
.DESCRIPTION
    - 引数なし: 全ユーザータスクを走査し、状態一覧と、問題のあるタスクの診断を表示
    - タスク名指定: 1本を深掘り（成功していても最終結果の翻訳を表示）
    所見は「これは何 / 考えられる原因 / 次の一手 [ランク]」の3点セット。
    コマンドは提示のみで、実行はユーザーに委ねる。
.PARAMETER TaskName
    深掘りするタスク名（省略時は全タスク走査）。
.PARAMETER Lang
    表示言語（ja / en）。既定は TASKCTL_LANG > OS の UI カルチャ > en。
.PARAMETER Json
    構造化出力（常に UTF-8）。exit_code フィールドを含む。
.PARAMETER IncludeMicrosoft
    \Microsoft\* 配下の OS 標準タスクも走査に含める。
.PARAMETER Raw
    生の設定（操作 / プリンシパル / トリガー / 主な設定）も表示する。
    `taskctl doctor --verbose` から渡される。
.NOTES
    終了コード（Get-TaskctlExitCode / JSON の exit_code）:
      0 問題なし / 2 警告あり / 3 重大な問題あり
    notice（判断＝仕様かもしれない）は 0 に数える。自動化を仕様通知で騒がせない。
#>
function Invoke-TaskctlDoctor {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [string] $TaskName,

        [ValidateNotNullOrEmpty()]
        [string] $Lang,

        [switch] $Json,

        [switch] $IncludeMicrosoft,

        [switch] $Raw
    )

    $locale = Resolve-TaskctlLocale -Lang $Lang
    $deepDive = -not [string]::IsNullOrWhiteSpace($TaskName)

    $acquired = @(
        if ($deepDive) { Get-TaskctlTask -TaskName $TaskName }
        else { Get-TaskctlTask -IncludeMicrosoft:$IncludeMicrosoft }
    )

    $results = foreach ($t in $acquired) {
        Get-TaskctlDiagnosis -Acquired $t -Locale $locale -IncludeNonFailureResult:$deepDive
    }
    $results = @($results)

    # 終了コード: error -> 3, warning -> 2, それ以外 -> 0
    $severities = @($results | ForEach-Object { $_.Findings } | ForEach-Object { $_.Severity })
    # 取得できなかったタスクは「問題なし」と言えない（診断できていないだけ）。
    # 重大とも断定できないので warning 扱い（＝レポートが不完全である、という警告）。
    $acquireErrors = @($results | Where-Object AcquireError).Count
    $exitCode = if ($severities -contains 'error') { 3 }
    elseif ($severities -contains 'warning' -or $acquireErrors -gt 0) { 2 }
    else { 0 }
    $script:TaskctlLastExitCode = $exitCode

    if ($Json) {
        $model = [ordered]@{
            locale    = $locale
            scanned   = $results.Count
            exit_code = $exitCode
            summary   = [ordered]@{
                errors         = @($severities | Where-Object { $_ -eq 'error' }).Count
                warnings       = @($severities | Where-Object { $_ -eq 'warning' }).Count
                notices        = @($severities | Where-Object { $_ -eq 'notice' }).Count
                acquire_errors = $acquireErrors
            }
            tasks     = @($results | ForEach-Object { ConvertTo-TaskctlDoctorJsonModel -Result $_ -Locale $locale })
        }
        return ConvertTo-TaskctlJson $model
    }

    Initialize-TaskctlConsole -Confirm:$false
    $text = Format-TaskctlDoctorReport -Results $results -Locale $locale -DeepDive:$deepDive -Raw:$Raw
    $hint = Get-TaskctlEncodingHint -Locale $locale
    if ($hint) { $text = "$text`n`n$hint" }
    $text
}

<#
.SYNOPSIS
    doctor の終了コード（直近の実行結果）。0 問題なし / 2 警告 / 3 重大。
.DESCRIPTION
    PowerShell の関数はプロセス終了コードを設定できないため、自動化では
    これを参照して exit する（例は README）。--json の exit_code と同じ値。
#>
function Get-TaskctlExitCode {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    if ($null -eq $script:TaskctlLastExitCode) { 0 } else { $script:TaskctlLastExitCode }
}
