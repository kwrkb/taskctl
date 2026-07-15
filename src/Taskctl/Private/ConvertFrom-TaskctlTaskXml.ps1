<#
.SYNOPSIS
    Export-ScheduledTask の XML を、診断ルールが評価する正規化モデルへ変換する。
.DESCRIPTION
    純粋関数（XML 文字列 -> オブジェクト）。実機のタスク登録なしに fixture でテストできる。
    タスク XML は既定名前空間 http://schemas.microsoft.com/windows/2004/02/mit/task を持つため、
    XPath には必ず名前空間マネージャを渡す（渡さないと何も返らず、無言で空になる）。
#>

$script:TaskctlTaskNamespace = 'http://schemas.microsoft.com/windows/2004/02/mit/task'

function ConvertFrom-TaskctlTaskXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Xml,

        [string] $TaskName,
        [string] $TaskPath
    )

    $doc = [xml] $Xml
    $ns = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
    $ns.AddNamespace('t', $script:TaskctlTaskNamespace)

    $task = $doc.SelectSingleNode('/t:Task', $ns)
    if (-not $task) {
        throw 'タスク XML として解釈できません（ルート要素 Task が見つかりません）。'
    }

    [PSCustomObject]@{
        TaskName  = $TaskName
        TaskPath  = $TaskPath
        Uri       = Get-TaskctlXmlText $task 't:RegistrationInfo/t:URI' $ns
        Enabled   = Get-TaskctlXmlBool $task 't:Settings/t:Enabled' $ns -Default $true
        Principal = ConvertFrom-TaskctlPrincipalXml $task $ns
        Actions   = @(ConvertFrom-TaskctlActionXml $task $ns)
        Triggers  = @(ConvertFrom-TaskctlTriggerXml $task $ns)
        Settings  = ConvertFrom-TaskctlSettingsXml $task $ns
        Xml       = $Xml
    }
}

function ConvertFrom-TaskctlPrincipalXml {
    [CmdletBinding()]
    param($Task, $Ns)

    $p = $Task.SelectSingleNode('t:Principals/t:Principal', $Ns)
    if (-not $p) { return $null }

    [PSCustomObject]@{
        UserId    = Get-TaskctlXmlText $p 't:UserId' $Ns
        GroupId   = Get-TaskctlXmlText $p 't:GroupId' $Ns
        LogonType = Get-TaskctlXmlText $p 't:LogonType' $Ns
        RunLevel  = Get-TaskctlXmlText $p 't:RunLevel' $Ns
    }
}

function ConvertFrom-TaskctlActionXml {
    [CmdletBinding()]
    param($Task, $Ns)

    foreach ($exec in $Task.SelectNodes('t:Actions/t:Exec', $Ns)) {
        [PSCustomObject]@{
            Type             = 'Exec'
            Command          = Get-TaskctlXmlText $exec 't:Command' $Ns
            Arguments        = Get-TaskctlXmlText $exec 't:Arguments' $Ns
            WorkingDirectory = Get-TaskctlXmlText $exec 't:WorkingDirectory' $Ns
        }
    }
    # Exec 以外（ComHandler / SendEmail / ShowMessage）は v1 の診断対象外だが、存在は拾う
    foreach ($other in $Task.SelectNodes('t:Actions/*[not(self::t:Exec)]', $Ns)) {
        [PSCustomObject]@{
            Type             = $other.LocalName
            Command          = $null
            Arguments        = $null
            WorkingDirectory = $null
        }
    }
}

function ConvertFrom-TaskctlTriggerXml {
    [CmdletBinding()]
    param($Task, $Ns)

    foreach ($trigger in $Task.SelectNodes('t:Triggers/*', $Ns)) {
        [PSCustomObject]@{
            Type          = $trigger.LocalName
            Enabled       = Get-TaskctlXmlBool $trigger 't:Enabled' $Ns -Default $true
            StartBoundary = Get-TaskctlXmlText $trigger 't:StartBoundary' $Ns
            EndBoundary   = Get-TaskctlXmlText $trigger 't:EndBoundary' $Ns
        }
    }
}

function ConvertFrom-TaskctlSettingsXml {
    [CmdletBinding()]
    param($Task, $Ns)

    $s = $Task.SelectSingleNode('t:Settings', $Ns)
    if (-not $s) { return $null }

    [PSCustomObject]@{
        Enabled                    = Get-TaskctlXmlBool $s 't:Enabled' $Ns -Default $true
        ExecutionTimeLimit         = Get-TaskctlXmlText $s 't:ExecutionTimeLimit' $Ns
        MultipleInstancesPolicy    = Get-TaskctlXmlText $s 't:MultipleInstancesPolicy' $Ns
        DisallowStartIfOnBatteries = Get-TaskctlXmlBool $s 't:DisallowStartIfOnBatteries' $Ns -Default $true
        StopIfGoingOnBatteries     = Get-TaskctlXmlBool $s 't:StopIfGoingOnBatteries' $Ns -Default $true
        RunOnlyIfIdle              = Get-TaskctlXmlBool $s 't:RunOnlyIfIdle' $Ns -Default $false
        RunOnlyIfNetworkAvailable  = Get-TaskctlXmlBool $s 't:RunOnlyIfNetworkAvailable' $Ns -Default $false
        StartWhenAvailable         = Get-TaskctlXmlBool $s 't:StartWhenAvailable' $Ns -Default $false
        WakeToRun                  = Get-TaskctlXmlBool $s 't:WakeToRun' $Ns -Default $false
    }
}

<#
.SYNOPSIS
    XPath で要素のテキストを取る。無ければ $null（空文字と区別する）。
#>
function Get-TaskctlXmlText {
    [CmdletBinding()]
    param($Node, [string] $XPath, $Ns)

    $found = $Node.SelectSingleNode($XPath, $Ns)
    if ($null -eq $found) { return $null }
    $found.InnerText
}

<#
.SYNOPSIS
    XPath で bool を取る。要素が無ければ Default（タスクスケジューラの既定値）を返す。
#>
function Get-TaskctlXmlBool {
    [CmdletBinding()]
    param($Node, [string] $XPath, $Ns, [bool] $Default)

    $text = Get-TaskctlXmlText $Node $XPath $Ns
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
    $text.Trim() -eq 'true'
}
