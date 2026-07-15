<#
.SYNOPSIS
    正規化モデルから、検出ルール (data/rules.yaml) が参照するファクトを算出する。
.DESCRIPTION
    VISION: 判定は1箇所、プロースはカタログ。ルールの when が参照するファクト名は
    すべてここで算出する。ルール側に新しいファクトが増えたら、まずここに足す。
    値が算出できない場合は $null（評価器は $null の条件を不成立として扱う＝発火しない側に倒す）。
    Now / FixedDrives を注入できるようにし、実機や現在時刻に依存せずテストする。
#>
function Get-TaskctlTaskFact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Model,

        [object] $Info,

        [datetime] $Now = (Get-Date),

        # taskctl を動かしている本人の識別子（テストで注入）
        [string] $CurrentSid,
        [string] $CurrentName
    )

    $facts = @{}

    # ---- task.* ----
    $facts['task.enabled'] = [bool] $Model.Enabled
    $triggers = @($Model.Triggers)
    $enabledTriggers = @($triggers | Where-Object Enabled)
    $facts['task.has_triggers'] = $triggers.Count -gt 0
    $facts['task.has_enabled_trigger'] = $enabledTriggers.Count -gt 0
    # 時刻ベースのトリガー（次回実行時刻を持つのが正常なもの）。
    # ログオン/ブート/イベントトリガーのタスクは NextRunTime が無くて正常なので区別する。
    $facts['task.has_enabled_time_trigger'] = [bool] @($enabledTriggers |
            Where-Object { $_.Type -in 'TimeTrigger', 'CalendarTrigger' }).Count

    # ---- trigger.* ----
    # all_past_end_boundary: 全トリガーが終了境界を持ち、かつ全て過去。1つでも境界なし/未来なら false。
    $facts['trigger.all_past_end_boundary'] = $false
    if ($triggers.Count -gt 0) {
        $allPast = $true
        foreach ($t in $triggers) {
            if ([string]::IsNullOrWhiteSpace($t.EndBoundary)) { $allPast = $false; break }
            $end = ConvertTo-TaskctlDateTime $t.EndBoundary
            if ($null -eq $end -or $end -gt $Now) { $allPast = $false; break }
        }
        $facts['trigger.all_past_end_boundary'] = $allPast
    }

    # ---- info.*（実行情報が取れないタスクでは $null のまま＝関連ルールは発火しない） ----
    $facts['info.next_run_set'] = $null
    $facts['info.never_run'] = $null
    $facts['info.days_since_last_run'] = $null
    if ($Info) {
        # 未実行/未予定のとき LastRunTime / NextRunTime は $null か 1999-11-30 のセンチネルで返る
        $facts['info.next_run_set'] = [bool] ($Info.NextRunTime -and $Info.NextRunTime.Year -ge 2000)
        $neverRun = -not ($Info.LastRunTime -and $Info.LastRunTime.Year -ge 2000)
        $facts['info.never_run'] = $neverRun
        if (-not $neverRun) {
            $facts['info.days_since_last_run'] = [int] [math]::Floor(($Now - $Info.LastRunTime).TotalDays)
        }
    }

    # ---- principal.* ----
    $facts['principal.is_service_account'] = $false
    $facts['principal.logon_type_interactive'] = $false
    $facts['principal.is_current_user'] = $false
    if ($Model.Principal) {
        $userId = [string] $Model.Principal.UserId
        $facts['principal.is_service_account'] =
            $userId -in 'S-1-5-18', 'S-1-5-19', 'S-1-5-20' -or
            $userId -match '^(NT AUTHORITY\\)?(SYSTEM|LOCAL SERVICE|NETWORK SERVICE)$'
        $facts['principal.logon_type_interactive'] = $Model.Principal.LogonType -eq 'InteractiveToken'
        # taskctl を動かしている本人のタスクか。本人のタスクに限れば、taskctl の文脈での
        # パス存在チェックは「タスクが走る文脈」とほぼ一致し、Test-Path の結果を信頼できる。
        $currentUserArgs = @{ UserId = $userId }
        if ($CurrentSid) { $currentUserArgs['CurrentSid'] = $CurrentSid }
        if ($CurrentName) { $currentUserArgs['CurrentName'] = $CurrentName }
        $facts['principal.is_current_user'] = Test-TaskctlCurrentUser @currentUserArgs
    }

    # ---- settings.* ----
    $s = $Model.Settings
    $facts['settings.disallow_start_if_on_batteries'] = if ($s) { [bool] $s.DisallowStartIfOnBatteries } else { $null }
    $facts['settings.run_only_if_idle'] = if ($s) { [bool] $s.RunOnlyIfIdle } else { $null }
    $facts['settings.run_only_if_network_available'] = if ($s) { [bool] $s.RunOnlyIfNetworkAvailable } else { $null }
    $facts['settings.multiple_instances_parallel'] = if ($s) { $s.MultipleInstancesPolicy -eq 'Parallel' } else { $null }

    # ExecutionTimeLimit: ISO 8601 期間。PT0S は「制限なし」を意味する。
    $facts['settings.execution_time_limit_set'] = $false
    $facts['settings.execution_time_limit_seconds'] = $null
    if ($s -and -not [string]::IsNullOrWhiteSpace($s.ExecutionTimeLimit)) {
        try {
            $span = [System.Xml.XmlConvert]::ToTimeSpan($s.ExecutionTimeLimit)
            if ($span.TotalSeconds -gt 0) {
                $facts['settings.execution_time_limit_set'] = $true
                $facts['settings.execution_time_limit_seconds'] = [int] $span.TotalSeconds
            }
        }
        catch {
            Write-Verbose "ExecutionTimeLimit を解釈できません: $($s.ExecutionTimeLimit)"
        }
    }

    $facts
}

<#
.SYNOPSIS
    1つの操作 (Exec) についてのファクトを算出する。
#>
function Get-TaskctlActionFact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Action,

        [object] $Principal,

        # ローカルの固定ドライブ文字（テストで注入。既定は実機から取得）
        [string[]] $FixedDrives = (Get-TaskctlFixedDrive)
    )

    $facts = @{}
    if ($Action.Type -ne 'Exec') { return $facts }

    $command = Remove-TaskctlQuote ([string] $Action.Command)
    $arguments = [string] $Action.Arguments
    $workdir = Remove-TaskctlQuote ([string] $Action.WorkingDirectory)
    $allText = "$command $arguments $workdir"

    # ---- パスの形 ----
    $isRooted = $command -match '^[A-Za-z]:[\\/]' -or $command -match '^\\' -or $command -match '^%'
    $hasSeparator = $command -match '[\\/]'
    # 「区切りを含むのに絶対でない」だけを相対と見なす。素の exe 名は検索パスで解決されるため flag しない。
    $facts['action.command_relative'] = ($hasSeparator -and -not $isRooted)

    $facts['action.working_directory_set'] = -not [string]::IsNullOrWhiteSpace($workdir)

    # ---- 存在チェック（文脈差で誤爆しうるため、確実に検査できる時だけ） ----
    $facts['action.command_checkable'] = $false
    $facts['action.command_exists'] = $null
    if ($command -match '^([A-Za-z]):[\\/]' -and $command -notmatch '%') {
        if ($Matches[1].ToUpperInvariant() -in $FixedDrives) {
            $facts['action.command_checkable'] = $true
            $facts['action.command_exists'] = Test-Path -LiteralPath $command -PathType Leaf
        }
    }

    $facts['action.working_directory_checkable'] = $false
    $facts['action.working_directory_exists'] = $null
    if ($workdir -match '^([A-Za-z]):[\\/]' -and $workdir -notmatch '%') {
        if ($Matches[1].ToUpperInvariant() -in $FixedDrives) {
            $facts['action.working_directory_checkable'] = $true
            $facts['action.working_directory_exists'] = Test-Path -LiteralPath $workdir -PathType Container
        }
    }

    # ---- ネットワーク/プロファイル依存 ----
    $referenced = [regex]::Matches($allText, '(?<![A-Za-z0-9])([A-Za-z]):[\\/]') |
        ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } | Sort-Object -Unique
    $facts['action.uses_mapped_drive'] = [bool] ($referenced | Where-Object { $_ -notin $FixedDrives })

    $facts['action.uses_unc_path'] = $allText -match '(^|[\s"''=])\\\\[^\\\s]'

    $profileVars = '%USERPROFILE%', '%APPDATA%', '%LOCALAPPDATA%', '%TEMP%', '%TMP%', '%HOMEDRIVE%', '%HOMEPATH%', '%ONEDRIVE%'
    $facts['action.uses_profile_variable'] = [bool] ($profileVars | Where-Object { $allText -match [regex]::Escape($_) })

    # ---- 起動指定 ----
    $leaf = [System.IO.Path]::GetFileName($command)
    $facts['action.is_powershell'] = $leaf -match '^(powershell|pwsh)(\.exe)?$'
    $facts['action.powershell_has_file_or_command'] = $null
    if ($facts['action.is_powershell']) {
        $facts['action.powershell_has_file_or_command'] =
            $arguments -match '(?i)(^|\s)-(File|Command|EncodedCommand)\b' -or
            $arguments -match '(?i)\.ps1\b'
    }

    $ext = [System.IO.Path]::GetExtension($command)
    $facts['action.command_is_unlaunchable_script'] = $ext -in '.ps1', '.psm1', '.sh'

    $facts
}

<#
.SYNOPSIS
    タスクの実行ユーザーが、taskctl を動かしている本人かを判定する。
.DESCRIPTION
    UserId は SID（S-1-5-21-...）でもアカウント名（DOMAIN\user）でも入りうるため両方見る。
    判定できない場合は $false（＝存在チェックを走らせない側に倒す）。
#>
function Test-TaskctlCurrentUser {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $UserId,

        [string] $CurrentSid = $script:TaskctlCurrentSid,
        [string] $CurrentName = $script:TaskctlCurrentName
    )

    if ([string]::IsNullOrWhiteSpace($UserId)) { return $false }

    if (-not $CurrentSid -or -not $CurrentName) {
        try {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $script:TaskctlCurrentSid = $identity.User.Value
            $script:TaskctlCurrentName = $identity.Name
            $CurrentSid = $script:TaskctlCurrentSid
            $CurrentName = $script:TaskctlCurrentName
        }
        catch {
            Write-Verbose "現在のユーザーを判定できません: $_"
            return $false
        }
    }

    $id = $UserId.Trim()
    if ($id -eq $CurrentSid) { return $true }
    if ($id -eq $CurrentName) { return $true }
    # ドメイン修飾なしのアカウント名（"kiwar" と "HOST\user"）
    ($id -notmatch '^S-1-' -and $id -eq (Split-Path $CurrentName -Leaf))
}

function Get-TaskctlFixedDrive {
    [CmdletBinding()]
    param()

    @([System.IO.DriveInfo]::GetDrives() |
            Where-Object { $_.DriveType -eq 'Fixed' } |
            ForEach-Object { $_.Name.Substring(0, 1).ToUpperInvariant() })
}

function Remove-TaskctlQuote {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string] $Text)

    if ($null -eq $Text) { return '' }
    $Text.Trim().Trim('"').Trim("'")
}

<#
.SYNOPSIS
    タスク XML の日時文字列を DateTime へ。解釈できなければ $null。
#>
function ConvertTo-TaskctlDateTime {
    [CmdletBinding()]
    param([string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        ([datetimeoffset]::Parse($Text, [cultureinfo]::InvariantCulture)).LocalDateTime
    }
    catch {
        $null
    }
}
