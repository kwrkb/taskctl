#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# v2 の取得スクリプト (src/Taskctl.Cli/Acquisition/acquire.ps1) のタスク選択ロジックを、
# 実機のタスクスケジューラ無しで検証する。スケジューラ系コマンドは同名の関数で覆う
# （関数はコマンドレットより優先して解決される）。

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:acquirePath = Join-Path $repoRoot 'src\Taskctl.Cli\Acquisition\acquire.ps1'

    # 実機のタスク一覧の代わり。TaskPath は実機と同じく末尾 "\" 付き。
    $global:taskctlFakeTasks = @(
        [PSCustomObject]@{ TaskName = 'Backup'; TaskPath = '\Custom\'; State = 'Ready' }
        [PSCustomObject]@{ TaskName = 'BackupWeekly'; TaskPath = '\Custom\'; State = 'Ready' }
        [PSCustomObject]@{ TaskName = 'Backup'; TaskPath = '\Other\'; State = 'Ready' }
        [PSCustomObject]@{ TaskName = 'Scan'; TaskPath = '\Microsoft\Windows\Defender\'; State = 'Ready' }
        # 実機に存在しうる、ワイルドカードとしては不正な名前（"[" が閉じていない）
        [PSCustomObject]@{ TaskName = 'Log[1'; TaskPath = '\Custom\'; State = 'Ready' }
    )

    function Get-ScheduledTask {
        param([string] $TaskName, [string] $ErrorAction)
        # 実機と同じく -TaskName はワイルドカードとして解釈し、不正なパターンでは throw する
        if ($TaskName) {
            $pattern = [System.Management.Automation.WildcardPattern]::new($TaskName)
            return @($global:taskctlFakeTasks | Where-Object { $pattern.IsMatch($_.TaskName) })
        }
        return @($global:taskctlFakeTasks)
    }

    function Export-ScheduledTask {
        param([string] $TaskName, [string] $TaskPath, [string] $ErrorAction)
        "<Task><RegistrationInfo><URI>$TaskPath$TaskName</URI></RegistrationInfo></Task>"
    }

    function Get-ScheduledTaskInfo {
        param([string] $TaskName, [string] $TaskPath, [string] $ErrorAction)
        [PSCustomObject]@{
            LastRunTime = [datetime]'2026-07-15T02:00:00'
            LastTaskResult = 0
            NextRunTime = [datetime]'2026-07-16T02:00:00'
            NumberOfMissedRuns = 0
        }
    }

    # acquire.ps1 を走らせ、書き出された JSON を返す
    function Invoke-Acquire {
        param([string] $TaskNameArg)
        $outFile = Join-Path ([System.IO.Path]::GetTempPath()) "taskctl-acquire-test-$([guid]::NewGuid().ToString('N')).json"
        try {
            & $script:acquirePath -TaskNameArg $TaskNameArg -OutFile $outFile
            return Get-Content $outFile -Raw | ConvertFrom-Json
        }
        finally { Remove-Item $outFile -ErrorAction SilentlyContinue }
    }

    # 取得結果を "\Path\Name" の一覧にする
    function Get-FullName {
        param($Result)
        @($Result.tasks | ForEach-Object { $_.task_path + $_.task_name })
    }
}

Describe 'acquire.ps1 のタスク選択' {
    It 'フォルダパス付きの完全一致は1件だけ返す' {
        $r = Invoke-Acquire -TaskNameArg '\Custom\Backup'
        Get-FullName $r | Should -Be @('\Custom\Backup')
    }

    It 'フォルダパス付きのワイルドカードが一致する' {
        $r = Invoke-Acquire -TaskNameArg '\Custom\Backup*'
        Get-FullName $r | Should -Be @('\Custom\Backup', '\Custom\BackupWeekly')
    }

    It 'フォルダ配下すべてをワイルドカードで指定できる' {
        $r = Invoke-Acquire -TaskNameArg '\Microsoft\*'
        Get-FullName $r | Should -Be @('\Microsoft\Windows\Defender\Scan')
    }

    It 'スラッシュ区切りのパス指定も受け付ける' {
        $r = Invoke-Acquire -TaskNameArg '/Custom/Backup'
        Get-FullName $r | Should -Be @('\Custom\Backup')
    }

    It 'ワイルドカードとして不正な名前はリテラルとして完全一致する' {
        # "[" を含む名前でパス側も -like にすると、文字クラス扱いになり一致しなくなる
        $r = Invoke-Acquire -TaskNameArg '\Custom\Log[1'
        Get-FullName $r | Should -Be @('\Custom\Log[1')
    }

    It '一致しないパス指定はエラーを返す' {
        $r = Invoke-Acquire -TaskNameArg '\NoSuchFolder\Backup'
        $r.tasks | Should -BeNullOrEmpty
        $r.error | Should -Match 'タスクが見つかりません'
    }
}
