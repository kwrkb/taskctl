<#
.SYNOPSIS
    取得層。実機（タスクスケジューラ）へのアクセスをここへ隔離する。
.DESCRIPTION
    VISION: すべて read-only。設定は Export-ScheduledTask の XML（忠実ロケール非依存）、
    実行情報は Get-ScheduledTaskInfo（設定とは別取得。相関が必要）。
    診断ルールはこの層が返す正規化モデル上の純粋関数にするため、
    ここだけをテスト時に差し替えられるようにしておく。
#>
function Get-TaskctlTask {
    [CmdletBinding()]
    param(
        [string] $TaskName,

        # Microsoft\* 配下の OS 標準タスクを含めるか（既定は除外。VISION の「全ユーザータスク」）
        [switch] $IncludeMicrosoft
    )

    $tasks = if ($TaskName) {
        # ユーザーは "\Foo\Bar" でも "Bar" でも指定しうる
        $leaf = Split-Path $TaskName -Leaf
        $found = @(Get-ScheduledTask -TaskName $leaf -ErrorAction SilentlyContinue)
        if ($TaskName -match '[\\/]') {
            $wanted = '\' + $TaskName.Trim('\', '/')
            $found = @($found | Where-Object { ($_.TaskPath + $_.TaskName).TrimEnd('\') -eq $wanted })
        }
        if (-not $found) {
            throw "タスクが見つかりません: $TaskName"
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

    foreach ($t in $tasks) {
        $model = $null
        $acquireError = $null
        try {
            $xml = Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop
            $model = ConvertFrom-TaskctlTaskXml -Xml $xml -TaskName $t.TaskName -TaskPath $t.TaskPath
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

        [PSCustomObject]@{
            TaskName     = $t.TaskName
            TaskPath     = $t.TaskPath
            FullName     = ($t.TaskPath + $t.TaskName)
            State        = [string] $t.State
            Model        = $model
            Info         = if ($info) { ConvertFrom-TaskctlTaskInfo $info } else { $null }
            AcquireError = $acquireError
        }
    }
}

<#
.SYNOPSIS
    Get-ScheduledTaskInfo の結果を正規化する（実行情報。設定とは別取得）。
.DESCRIPTION
    留意: タスクオブジェクトが持つ実行結果は直近1回分のみ。
    LastTaskResult は符号付き 32bit で返るため、コードの正規化は lookup 側で行う。
#>
function ConvertFrom-TaskctlTaskInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Info
    )

    [PSCustomObject]@{
        LastRunTime        = $Info.LastRunTime
        LastTaskResult     = $Info.LastTaskResult
        NextRunTime        = $Info.NextRunTime
        NumberOfMissedRuns = $Info.NumberOfMissedRuns
    }
}
