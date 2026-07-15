<#
.SYNOPSIS
    結果コードを所見（finding）へ解決する。explain と doctor が共有する中核の純粋関数。
.DESCRIPTION
    3段で解決する:
      1. レジストリに完全一致       -> 翻訳表の事実 + カタログのプロース
      2. 0x8007xxxx (HRESULT_FROM_WIN32) -> 下位16bit を Win32 エラーとして案内（net helpmsg）
      3. それ以外                   -> 「不明」。16進/10進を併記し、断定しない
    返す finding は言語非依存フィールドと現在ロケールのプロースを両方持つ。
.OUTPUTS
    PSCustomObject (finding)
#>
function Resolve-TaskctlResultCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Code,

        [Parameter(Mandatory)]
        [string] $Locale
    )

    $normalized = ConvertTo-TaskctlCode $Code
    $registry = Get-TaskctlRegistry
    $catalog = Get-TaskctlCatalog -Locale $Locale

    $entry = $registry.codes | Where-Object key -eq $normalized.Key | Select-Object -First 1

    if ($entry) {
        $prose = $catalog.codes.($normalized.Key)
        $finding = [PSCustomObject]@{
            Code        = $normalized.Key
            Decimal     = [int64] $normalized.Unsigned
            Signed      = $normalized.Signed
            Constant    = $entry.constant
            Kind        = $entry.kind
            Severity    = $entry.severity
            IsFailure   = [bool] $entry.is_failure
            Rank        = $entry.next_rank
            MessageKey  = $normalized.Key
            Meaning     = $prose.meaning
            Cause       = $prose.cause
            Next        = $prose.next
            IsKnown     = $true
        }
    }
    elseif ($normalized.Key -match '^0x8007([0-9A-F]{4})$') {
        # HRESULT_FROM_WIN32: 下位16bit が Win32 エラーコード
        $win32 = [Convert]::ToInt64($Matches[1], 16)
        $prose = $catalog.fallback.hresult_from_win32
        $finding = [PSCustomObject]@{
            Code        = $normalized.Key
            Decimal     = [int64] $normalized.Unsigned
            Signed      = $normalized.Signed
            Constant    = "HRESULT_FROM_WIN32($win32)"
            Kind        = 'system'
            Severity    = 'warning'
            IsFailure   = $true
            Rank        = $registry.fallback.hresult_from_win32.rank
            MessageKey  = 'fallback.hresult_from_win32'
            Meaning     = $prose.meaning
            Cause       = $prose.cause
            Next        = $prose.next
            IsKnown     = $false
            Win32       = $win32
        }
    }
    else {
        $prose = $catalog.fallback.unknown
        $finding = [PSCustomObject]@{
            Code        = $normalized.Key
            Decimal     = [int64] $normalized.Unsigned
            Signed      = $normalized.Signed
            Constant    = $null
            Kind        = 'app'      # 未知のコードはアプリ独自の終了コードの可能性が高い
            Severity    = 'notice'
            IsFailure   = ($normalized.Unsigned -ne 0)
            Rank        = $registry.fallback.unknown.rank
            MessageKey  = 'fallback.unknown'
            Meaning     = $prose.meaning
            Cause       = $prose.cause
            Next        = $prose.next
            IsKnown     = $false
        }
    }

    # プレースホルダを展開（プロース層のみ。コマンドは非翻訳のままカタログから来る）
    $values = @{}
    if ($null -ne $finding.PSObject.Properties['Win32']) { $values['win32'] = $finding.Win32 }
    foreach ($field in 'Meaning', 'Cause', 'Next') {
        if ($finding.$field) {
            $finding.$field = Expand-TaskctlPlaceholder -Text $finding.$field -Catalog $catalog -Values $values
        }
    }

    $finding
}

<#
.SYNOPSIS
    テキスト中の {{snippets.<name>}} と {{<value>}} を展開する。
.DESCRIPTION
    snippets はカタログの定型文へ、それ以外は Values で渡された値へ置換する。
    未定義の参照は原文のまま残す（空文字を出さないため。coverage テストで検出する）。
#>
function Expand-TaskctlPlaceholder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [object] $Catalog,

        [hashtable] $Values = @{}
    )

    [regex]::Replace($Text, '\{\{(\w+(?:\.\w+)?)\}\}', {
            param($m)
            $ref = $m.Groups[1].Value
            if ($ref -match '^snippets\.(\w+)$') {
                $snippet = $Catalog.snippets.($Matches[1])
                if ($null -eq $snippet) { return $m.Value }
                return $snippet.TrimEnd()
            }
            if ($Values.ContainsKey($ref)) { return [string] $Values[$ref] }
            $m.Value
        })
}
