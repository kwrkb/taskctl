<#
.SYNOPSIS
    taskctl (C#) の取得層が呼び出す PowerShell スクリプト。
.DESCRIPTION
    VISION: すべて read-only。Export-ScheduledTask の XML（設定）と Get-ScheduledTaskInfo
    （実行情報。設定とは別取得）を、UTF-8 のファイルへ書き出す。
    stdout のリダイレクトはコンソールの既定コードページ（PS 5.1 の CP932 等）に左右され
    化けうるため使わず、ファイル書き出しに固定して呼び出し側とのエンコーディング問題を避ける。
#>
[CmdletBinding()]
param(
    [string] $TaskNameArg,
    [switch] $IncludeMicrosoft,
    [Parameter(Mandatory)]
    [string] $OutFile
)

$ErrorActionPreference = 'Stop'

function ConvertFrom-InfoObj {
    param($Info)
    if (-not $Info) { return $null }
    [ordered]@{
        last_run_time         = if ($Info.LastRunTime) { $Info.LastRunTime.ToString('o') } else { $null }
        last_task_result      = if ($null -ne $Info.LastTaskResult) { [int64] $Info.LastTaskResult } else { $null }
        next_run_time         = if ($Info.NextRunTime) { $Info.NextRunTime.ToString('o') } else { $null }
        number_of_missed_runs = $Info.NumberOfMissedRuns
    }
}

function Write-TaskctlAcquireOutput {
    param($Payload)
    $json = $Payload | ConvertTo-Json -Depth 10 -Compress
    [System.IO.File]::WriteAllText($OutFile, $json, [System.Text.UTF8Encoding]::new($false))
}

try {
    $tasks = if ($TaskNameArg) {
        # ユーザーは "\Foo\Bar" でも "Bar" でも指定しうる
        $leaf = Split-Path $TaskNameArg -Leaf
        # Get-ScheduledTask -TaskName はワイルドカードとして解釈する。タスク名に使える
        # "[" などが入ると「不正なパターン」で throw するため、その場合はリテラル名として探す。
        $found = @()
        try {
            $found = @(Get-ScheduledTask -TaskName $leaf -ErrorAction SilentlyContinue)
        }
        catch {
            $found = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -eq $leaf })
        }
        if ($TaskNameArg -match '[\\/]') {
            $wanted = '\' + $TaskNameArg.Trim('\', '/')
            $found = @($found | Where-Object { ($_.TaskPath + $_.TaskName).TrimEnd('\') -eq $wanted })
        }
        if (-not $found) {
            throw "タスクが見つかりません: $TaskNameArg"
        }
        $found
    }
    else {
        $all = @(Get-ScheduledTask -ErrorAction Stop)
        if (-not $IncludeMicrosoft) {
            $all = @($all | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })
        }
        $all
    }

    $results = foreach ($t in $tasks) {
        $xml = $null
        $acquireError = $null
        try {
            $xml = Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop
        }
        catch {
            $acquireError = $_.Exception.Message
        }

        $info = $null
        try {
            $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop
        }
        catch {
            if (-not $acquireError) { $acquireError = $_.Exception.Message }
        }

        [ordered]@{
            task_name     = $t.TaskName
            task_path     = $t.TaskPath
            state         = [string] $t.State
            xml           = $xml
            info          = ConvertFrom-InfoObj $info
            acquire_error = $acquireError
        }
    }

    Write-TaskctlAcquireOutput ([ordered]@{ tasks = @($results); error = $null })
}
catch {
    Write-TaskctlAcquireOutput ([ordered]@{ tasks = @(); error = $_.Exception.Message })
    exit 1
}
