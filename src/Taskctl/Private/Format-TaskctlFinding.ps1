<#
.SYNOPSIS
    所見（finding）を人間向けテキストへ整形する。VISION の3点セットの型。
.DESCRIPTION
    出力の型:
        <Code> (10進 <dec>)  [<CONSTANT>]
        これは何:       ...
        考えられる原因: ...
        次の一手 [ランク]: ...
    見出しとランクのラベルはカタログから引く（プロース層のみ翻訳）。
    コード値定数名コマンドは非翻訳。
#>
function Format-TaskctlFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Finding,

        [Parameter(Mandatory)]
        [string] $Locale,

        [string] $Title
    )

    process {
        $catalog = Get-TaskctlCatalog -Locale $Locale
        $lines = [System.Collections.Generic.List[string]]::new()

        # ヘッダ: コード値と定数名（いずれも非翻訳）
        $header = '{0} ({1})' -f $Finding.Code, $Finding.Decimal
        if ($Finding.Signed -lt 0) {
            $header += ' / {0}' -f $Finding.Signed
        }
        if ($Finding.Constant) {
            $header += '  [{0}]' -f $Finding.Constant
        }
        if ($Title) {
            $header = '{0}  {1}' -f $Title, $header
        }
        $lines.Add($header)

        $kindLabel = $catalog.kinds.($Finding.Kind).label
        if ($kindLabel) {
            $lines.Add('  ({0})' -f $kindLabel)
        }
        $lines.Add('')

        $lines.Add((Format-TaskctlSection -Heading $catalog.headings.meaning -Body $Finding.Meaning))
        if ($Finding.Cause) {
            $lines.Add((Format-TaskctlSection -Heading $catalog.headings.cause -Body $Finding.Cause))
        }

        $rankLabel = $catalog.ranks.($Finding.Rank).label
        $nextHeading = '{0} [{1}]' -f $catalog.headings.next, $rankLabel
        $lines.Add((Format-TaskctlSection -Heading $nextHeading -Body $Finding.Next))

        ($lines -join "`n").TrimEnd()
    }
}

<#
.SYNOPSIS
    1セクション（見出し + 字下げした本文）を整形する。
#>
function Format-TaskctlSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Heading,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Body
    )

    $indented = ($Body.TrimEnd() -split "`r?`n" | ForEach-Object { '  ' + $_ }) -join "`n"
    "{0}:`n{1}`n" -f $Heading, $indented
}

<#
.SYNOPSIS
    所見を --json 用のオブジェクトへ射影する。
.DESCRIPTION
    VISION §5: 言語非依存フィールド（code / constant / kind / severity / is_failure / message_key）を
    必ず含め、加えて現在ロケールの message / action を載せる。
    消費側は message_key で自前ローカライズも、提供テキストの利用も選べる。
#>
function ConvertTo-TaskctlJsonModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Finding,

        [Parameter(Mandatory)]
        [string] $Locale
    )

    process {
        [ordered]@{
            code        = $Finding.Code
            code_dec    = $Finding.Decimal
            code_signed = $Finding.Signed
            constant    = $Finding.Constant
            kind        = $Finding.Kind
            severity    = $Finding.Severity
            is_failure  = $Finding.IsFailure
            rank        = $Finding.Rank
            known       = $Finding.IsKnown
            message_key = $Finding.MessageKey
            locale      = $Locale
            message     = $Finding.Meaning
            cause       = $Finding.Cause
            action      = $Finding.Next
        }
    }
}

<#
.SYNOPSIS
    オブジェクトを JSON 文字列にする。
.DESCRIPTION
    VISION は「--json は常に UTF-8」を求めるが、返すのは .NET 文字列であり、
    バイト列のエンコーディングは受け取り側が決める。
      - PowerShell 7: 既定が UTF-8 なので `taskctl doctor --json > a.json` で UTF-8 になる
      - Windows PowerShell 5.1: `>` / Out-File の既定が UTF-16LE のため UTF-8 にならない
    ここでエンコーディングを制御することはできない（文字列を返すだけなので）。
    ファイルへ UTF-8 で保存する方法は README に記載する。
#>
function ConvertTo-TaskctlJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $InputObject
    )

    ConvertTo-Json $InputObject -Depth 10
}
