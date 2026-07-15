<#
.SYNOPSIS
    ルール所見（言語非依存）へ、カタログのプロースを付ける / 表示用テキストへ整形する。
#>
function Resolve-TaskctlRuleProse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Finding,

        [Parameter(Mandatory)]
        [string] $Locale
    )

    process {
        $catalog = Get-TaskctlCatalog -Locale $Locale
        $prose = $catalog.rules.($Finding.RuleId)
        if (-not $prose) {
            # coverage テストで防いでいるが、万一欠けても空文字は出さない（rule id を出す）
            $prose = [PSCustomObject]@{ meaning = $Finding.RuleId; cause = $null; next = $Finding.RuleId }
        }

        $values = if ($Finding.Values) { $Finding.Values } else { @{} }
        $meaning = if ($prose.meaning) { Expand-TaskctlPlaceholder -Text $prose.meaning -Catalog $catalog -Values $values } else { $null }
        $cause = if ($prose.cause) { Expand-TaskctlPlaceholder -Text $prose.cause -Catalog $catalog -Values $values } else { $null }
        $next = if ($prose.next) { Expand-TaskctlPlaceholder -Text $prose.next -Catalog $catalog -Values $values } else { $null }

        $Finding | Add-Member -NotePropertyName Meaning -NotePropertyValue $meaning -Force
        $Finding | Add-Member -NotePropertyName Cause -NotePropertyValue $cause -Force
        $Finding | Add-Member -NotePropertyName Next -NotePropertyValue $next -Force
        $Finding
    }
}

<#
.SYNOPSIS
    ルール所見を人間向けテキストへ。ヘッダはルール ID（grep 可能な安定キー。非翻訳）。
#>
function Format-TaskctlRuleFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Finding,

        [Parameter(Mandatory)]
        [string] $Locale
    )

    process {
        $catalog = Get-TaskctlCatalog -Locale $Locale
        $lines = [System.Collections.Generic.List[string]]::new()

        $lines.Add(('[{0}] {1}' -f $Finding.Severity, $Finding.RuleId))
        $lines.Add('')
        $lines.Add((Format-TaskctlSection -Heading $catalog.headings.meaning -Body $Finding.Meaning))
        if ($Finding.Cause) {
            $lines.Add((Format-TaskctlSection -Heading $catalog.headings.cause -Body $Finding.Cause))
        }
        $rankLabel = $catalog.ranks.($Finding.Rank).label
        $lines.Add((Format-TaskctlSection -Heading ('{0} [{1}]' -f $catalog.headings.next, $rankLabel) -Body $Finding.Next))

        ($lines -join "`n").TrimEnd()
    }
}

<#
.SYNOPSIS
    ルール所見を --json 用オブジェクトへ射影する。
#>
function ConvertTo-TaskctlRuleJsonModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Finding,

        [Parameter(Mandatory)]
        [string] $Locale
    )

    process {
        [ordered]@{
            rule        = $Finding.RuleId
            severity    = $Finding.Severity
            rank        = $Finding.Rank
            message_key = $Finding.MessageKey
            locale      = $Locale
            message     = $Finding.Meaning
            cause       = $Finding.Cause
            action      = $Finding.Next
            target      = if ($Finding.Values -and $Finding.Values.ContainsKey('command')) { $Finding.Values['command'] } else { $null }
        }
    }
}
