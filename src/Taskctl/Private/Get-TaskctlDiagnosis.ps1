<#
.SYNOPSIS
    取得済みタスク1件を診断する（結果コード翻訳 + 検出ルール）。
.DESCRIPTION
    doctor の中核。取得層の結果（正規化モデル + 実行情報）を受け取り、
    所見のリストを返す純粋関数。実機アクセスはしない。
.PARAMETER IncludeNonFailureResult
    失敗でない結果コード（S_OK や状態コード）も所見に含める（深掘り時）。
#>
function Get-TaskctlDiagnosis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Acquired,

        [Parameter(Mandatory)]
        [string] $Locale,

        [switch] $IncludeNonFailureResult,

        [datetime] $Now = (Get-Date),

        [string[]] $FixedDrives = (Get-TaskctlFixedDrive)
    )

    $findings = [System.Collections.Generic.List[object]]::new()

    # 1) 直近の結果コードの翻訳（実行情報が取れている場合のみ）
    $codeFinding = $null
    if ($Acquired.Info -and $null -ne $Acquired.Info.LastTaskResult) {
        $neverRun = -not ($Acquired.Info.LastRunTime -and $Acquired.Info.LastRunTime.Year -ge 2000)
        # 一度も実行されていないタスクの LastTaskResult (SCHED_S_TASK_HAS_NOT_RUN 等) は
        # 走査時のノイズになるため、深掘り時のみ表示する
        if (-not $neverRun -or $IncludeNonFailureResult) {
            $codeFinding = Resolve-TaskctlResultCode -Code ([string] $Acquired.Info.LastTaskResult) -Locale $Locale
            $codeFinding | Add-Member -NotePropertyName Type -NotePropertyValue 'result_code' -Force
            if ($codeFinding.IsFailure -or $IncludeNonFailureResult) {
                $findings.Add($codeFinding)
            }
        }
    }

    # 2) 設定ミスの検出（宣言的ルール）。取得に失敗したタスクはスキップ。
    if ($Acquired.Model) {
        $ruleFindings = @(Invoke-TaskctlRuleEngine -Model $Acquired.Model -Info $Acquired.Info -Now $Now -FixedDrives $FixedDrives |
                Resolve-TaskctlRuleProse -Locale $Locale)
        foreach ($f in $ruleFindings) { $findings.Add($f) }
    }

    [PSCustomObject]@{
        TaskName     = $Acquired.TaskName
        TaskPath     = $Acquired.TaskPath
        FullName     = $Acquired.FullName
        State        = $Acquired.State
        Model        = $Acquired.Model      # --verbose（生の設定）で使う
        Info         = $Acquired.Info
        AcquireError = $Acquired.AcquireError
        CodeFinding  = $codeFinding
        Findings     = @($findings)
    }
}

<#
.SYNOPSIS
    診断結果1件を --json 用オブジェクトへ射影する。
#>
function ConvertTo-TaskctlDoctorJsonModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Result,

        [Parameter(Mandatory)]
        [string] $Locale
    )

    $codeModel = $null
    if ($Result.CodeFinding) {
        $codeModel = ConvertTo-TaskctlJsonModel -Finding $Result.CodeFinding -Locale $Locale
    }

    $ruleModels = @($Result.Findings | Where-Object Type -eq 'rule' |
            ForEach-Object { ConvertTo-TaskctlRuleJsonModel -Finding $_ -Locale $Locale })

    [ordered]@{
        task          = $Result.FullName
        state         = $Result.State
        last_run      = if ($Result.Info -and $Result.Info.LastRunTime -and $Result.Info.LastRunTime.Year -ge 2000) { $Result.Info.LastRunTime.ToString('o') } else { $null }
        next_run      = if ($Result.Info -and $Result.Info.NextRunTime -and $Result.Info.NextRunTime.Year -ge 2000) { $Result.Info.NextRunTime.ToString('o') } else { $null }
        last_result   = $codeModel
        findings      = $ruleModels
        acquire_error = $Result.AcquireError
    }
}

<#
.SYNOPSIS
    doctor のテキストレポートを組み立てる。問題と次の一手を先頭に、一覧は最後。
#>
function Format-TaskctlDoctorReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Results,

        [Parameter(Mandatory)]
        [string] $Locale,

        [switch] $DeepDive,

        [switch] $Raw
    )

    $catalog = Get-TaskctlCatalog -Locale $Locale
    $lines = [System.Collections.Generic.List[string]]::new()

    # 走査時は warning 以上（または取得失敗）のタスクだけ詳細を出す。
    # notice（判断＝仕様かもしれない）だけのタスクまで並べると本当の問題が埋もれる。
    # 深掘り時はすべて出す。notice も JSON には常に全部載る。
    $problem = if ($DeepDive) {
        @($Results | Where-Object { $_.Findings.Count -gt 0 -or $_.AcquireError })
    }
    else {
        @($Results | Where-Object {
                $_.AcquireError -or
                @($_.Findings | Where-Object { $_.Severity -in 'warning', 'error' }).Count -gt 0
            })
    }
    $severities = @($Results | ForEach-Object { $_.Findings } | ForEach-Object { $_.Severity })
    $summaryLine = if ($Locale -eq 'ja') {
        '走査 {0} タスク: error {1} / warning {2} / notice {3}' -f $Results.Count,
        @($severities | Where-Object { $_ -eq 'error' }).Count,
        @($severities | Where-Object { $_ -eq 'warning' }).Count,
        @($severities | Where-Object { $_ -eq 'notice' }).Count
    }
    else {
        'Scanned {0} task(s): error {1} / warning {2} / notice {3}' -f $Results.Count,
        @($severities | Where-Object { $_ -eq 'error' }).Count,
        @($severities | Where-Object { $_ -eq 'warning' }).Count,
        @($severities | Where-Object { $_ -eq 'notice' }).Count
    }
    $lines.Add($summaryLine)
    $lines.Add('')

    # ---- 問題のあるタスクの診断（先頭に） ----
    foreach ($r in $problem) {
        $lines.Add(('=== {0}  ({1}) ===' -f $r.FullName, $r.State))
        if ($r.AcquireError) {
            $lines.Add(('  ! {0}' -f $r.AcquireError))
        }
        if ($Raw -and $r.Model) {
            $lines.Add((Format-TaskctlRawSetting -Model $r.Model -Info $r.Info -Locale $Locale))
            $lines.Add('')
        }
        foreach ($f in $r.Findings) {
            $text = if ($f.Type -eq 'result_code') {
                Format-TaskctlFinding -Finding $f -Locale $Locale
            }
            else {
                Format-TaskctlRuleFinding -Finding $f -Locale $Locale
            }
            # タスク見出しの下に字下げして載せる
            $lines.Add((($text -split "`r?`n" | ForEach-Object { '  ' + $_ }) -join "`n"))
            $lines.Add('')
        }
    }

    # ---- 一覧（深掘り時は冗長なので出さない） ----
    if (-not $DeepDive -and $Results.Count -gt 0) {
        $lines.Add(('--- {0} ---' -f ($(if ($Locale -eq 'ja') { '一覧' } else { 'Tasks' })))
        )
        $header = '{0,-10} {1,-12} {2,-20} {3}' -f 'State', 'LastResult', 'NextRun', 'Task'
        $lines.Add($header)
        foreach ($r in ($Results | Sort-Object FullName)) {
            $lastResult = if ($r.CodeFinding) { $r.CodeFinding.Code }
            elseif ($r.Info -and $null -ne $r.Info.LastTaskResult) { '0x{0:X8}' -f ([int64]($r.Info.LastTaskResult) -band 0xFFFFFFFFL) }
            else { '-' }
            $nextRun = if ($r.Info -and $r.Info.NextRunTime -and $r.Info.NextRunTime.Year -ge 2000) {
                $r.Info.NextRunTime.ToString('yyyy-MM-dd HH:mm')
            }
            else { '-' }
            $lines.Add(('{0,-10} {1,-12} {2,-20} {3}' -f $r.State, $lastResult, $nextRun, $r.FullName))
        }
    }

    ($lines -join "`n").TrimEnd()
}

<#
.SYNOPSIS
    生の設定を表示する（--verbose）。値は加工せずそのまま見せる。
.DESCRIPTION
    環境変数や相対パスは展開しない。taskctl の文脈で展開すると、
    タスクが実際に走る文脈での値と食い違い、かえって誤解を生むため。
#>
function Format-TaskctlRawSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Model,
        [object] $Info,
        [Parameter(Mandatory)] [string] $Locale
    )

    $isJa = $Locale -eq 'ja'
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(('  --- {0} ---' -f $(if ($isJa) { '生の設定' } else { 'Raw settings' })))

    foreach ($a in @($Model.Actions)) {
        $lines.Add(('    {0}: {1} {2}' -f $(if ($isJa) { '操作' } else { 'Action' }), $a.Command, $a.Arguments).TrimEnd())
        if ($a.WorkingDirectory) {
            $lines.Add(('      {0}: {1}' -f $(if ($isJa) { '作業ディレクトリ' } else { 'Working dir' }), $a.WorkingDirectory))
        }
    }
    if ($Model.Principal) {
        $lines.Add(('    {0}: {1} / LogonType={2} / RunLevel={3}' -f
                $(if ($isJa) { '実行ユーザー' } else { 'Principal' }),
                $Model.Principal.UserId, $Model.Principal.LogonType, $Model.Principal.RunLevel))
    }
    foreach ($t in @($Model.Triggers)) {
        $lines.Add(('    {0}: {1} / Enabled={2} / Start={3} / End={4}' -f
                $(if ($isJa) { 'トリガー' } else { 'Trigger' }),
                $t.Type, $t.Enabled, $t.StartBoundary, $t.EndBoundary))
    }
    if ($Model.Settings) {
        $s = $Model.Settings
        $lines.Add(('    {0}: Enabled={1} / ExecutionTimeLimit={2} / MultipleInstancesPolicy={3}' -f
                $(if ($isJa) { '設定' } else { 'Settings' }),
                $s.Enabled, $s.ExecutionTimeLimit, $s.MultipleInstancesPolicy))
        $lines.Add(('      DisallowStartIfOnBatteries={0} / RunOnlyIfIdle={1} / RunOnlyIfNetworkAvailable={2}' -f
                $s.DisallowStartIfOnBatteries, $s.RunOnlyIfIdle, $s.RunOnlyIfNetworkAvailable))
    }
    if ($Info) {
        $lines.Add(('    {0}: LastRunTime={1} / LastTaskResult={2} / NextRunTime={3}' -f
                $(if ($isJa) { '実行情報' } else { 'Run info' }),
                $Info.LastRunTime, $Info.LastTaskResult, $Info.NextRunTime))
    }

    $lines -join "`n"
}
