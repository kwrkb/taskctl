<#
.SYNOPSIS
    宣言的ルール (data/rules.yaml) を正規化モデルに適用し、言語非依存の所見を返す。
.DESCRIPTION
    小さな評価器。when は AND 条件の配列で、各条件は { fact, eq|gte|lte } のみ。
    ファクトが $null（算出不能）の条件は不成立として扱う＝誤検知しない側に倒す。
    プロースは一切持たない。表示時にカタログの rules.<id> から引く。
#>
function Invoke-TaskctlRuleEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Model,

        [object] $Info,

        [object] $Rules = (Get-TaskctlRules),

        [datetime] $Now = (Get-Date),

        [string[]] $FixedDrives = (Get-TaskctlFixedDrive),

        [string[]] $NetworkDrives = (Get-TaskctlDriveLetter -DriveType Network),

        [string[]] $LocalDrives = (Get-TaskctlDriveLetter -DriveType Removable, CDRom, Ram),

        # taskctl を動かしている本人の識別子（テストで注入）
        [string] $CurrentSid,
        [string] $CurrentName
    )

    $taskFactArgs = @{ Model = $Model; Info = $Info; Now = $Now }
    if ($CurrentSid) { $taskFactArgs['CurrentSid'] = $CurrentSid }
    if ($CurrentName) { $taskFactArgs['CurrentName'] = $CurrentName }
    $taskFacts = Get-TaskctlTaskFact @taskFactArgs

    $actionFactSets = @()
    foreach ($action in @($Model.Actions)) {
        $actionFactSets += , @{
            Action = $action
            Facts  = (Get-TaskctlActionFact -Action $action -Principal $Model.Principal `
                    -FixedDrives $FixedDrives -NetworkDrives $NetworkDrives -LocalDrives $LocalDrives)
        }
    }

    foreach ($rule in $Rules.rules) {
        if ($rule.scope -eq 'task') {
            if (Test-TaskctlRuleCondition -Conditions $rule.when -Facts $taskFacts) {
                New-TaskctlRuleFinding -Rule $rule -Model $Model -Facts $taskFacts
            }
        }
        elseif ($rule.scope -eq 'action') {
            for ($i = 0; $i -lt $actionFactSets.Count; $i++) {
                $set = $actionFactSets[$i]
                # action ルールは task ファクトも参照できる（合成して評価）
                $merged = @{} + $taskFacts
                foreach ($k in $set.Facts.Keys) { $merged[$k] = $set.Facts[$k] }
                if (Test-TaskctlRuleCondition -Conditions $rule.when -Facts $merged) {
                    New-TaskctlRuleFinding -Rule $rule -Model $Model -Facts $merged -Action $set.Action -ActionIndex $i
                }
            }
        }
    }
}

function Test-TaskctlRuleCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Conditions,

        [Parameter(Mandatory)]
        [hashtable] $Facts
    )

    foreach ($cond in $Conditions) {
        $name = [string] $cond.fact
        if (-not $Facts.ContainsKey($name)) {
            Write-Verbose "未知のファクトです（ルール側の誤記の可能性）: $name"
            return $false
        }
        $value = $Facts[$name]
        if ($null -eq $value) { return $false }   # 算出不能 -> 発火させない

        $ok = if ($null -ne $cond.PSObject.Properties['eq'])   { $value -eq $cond.eq }
        elseif ($null -ne $cond.PSObject.Properties['gte'])    { $value -ge $cond.gte }
        elseif ($null -ne $cond.PSObject.Properties['lte'])    { $value -le $cond.lte }
        else {
            Write-Verbose "未知の演算子です: $($cond | ConvertTo-Json -Compress)"
            $false
        }
        if (-not $ok) { return $false }
    }
    $true
}

function New-TaskctlRuleFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Rule,
        [Parameter(Mandatory)] [object] $Model,
        [Parameter(Mandatory)] [hashtable] $Facts,
        [object] $Action,
        [int] $ActionIndex = -1
    )

    # プロース側のプレースホルダへ渡す値（言語非依存の実値のみ）
    $name = if ($Model.TaskName) { $Model.TaskName } else { $Model.Uri }
    $values = Get-TaskctlTaskValue -TaskName $name -TaskPath $Model.TaskPath
    if ($Action) {
        $values['command'] = ('{0} {1}' -f $Action.Command, $Action.Arguments).Trim()
        $values['workdir'] = [string] $Action.WorkingDirectory
    }
    if ($null -ne $Facts['info.days_since_last_run']) {
        $values['days'] = $Facts['info.days_since_last_run']
    }
    if ($null -ne $Facts['settings.execution_time_limit_seconds']) {
        $values['limit_seconds'] = $Facts['settings.execution_time_limit_seconds']
    }

    [PSCustomObject]@{
        Type        = 'rule'
        RuleId      = $Rule.id
        Scope       = $Rule.scope
        Severity    = $Rule.severity
        Rank        = $Rule.rank
        ActionIndex = if ($Action) { $ActionIndex } else { $null }
        MessageKey  = "rules.$($Rule.id)"
        Values      = $values
    }
}
