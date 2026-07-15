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
        [string] $Locale,

        # プロースのプレースホルダへ渡す実値（doctor は task / command を知っている）。
        # explain 単体では分からないため、既定のプレースホルダ表記で埋める。
        [hashtable] $Values = @{}
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
            Severity    = $registry.fallback.hresult_from_win32.severity
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
        # 未知のコード。意味は断定しないが、失敗を隠さない。
        # 非ゼロ = 失敗として扱い、severity/rank も失敗に整合させる（調査を促す）。
        # ここで notice/info にすると、doctor の詳細にも出ず終了コードも 0 になり、
        # 「未知の失敗を緑で返す」ことになってツールの存在意義を損なう。
        $isFailure = ($normalized.Unsigned -ne 0)
        $prose = $catalog.fallback.unknown
        $finding = [PSCustomObject]@{
            Code        = $normalized.Key
            Decimal     = [int64] $normalized.Unsigned
            Signed      = $normalized.Signed
            Constant    = $null
            Kind        = 'app'      # 未知のコードはアプリ独自の終了コードの可能性が高い
            Severity    = if ($isFailure) { $registry.fallback.unknown.severity } else { 'info' }
            IsFailure   = $isFailure
            Rank        = if ($isFailure) { $registry.fallback.unknown.rank } else { 'info' }
            MessageKey  = 'fallback.unknown'
            Meaning     = $prose.meaning
            Cause       = $prose.cause
            Next        = $prose.next
            IsKnown     = $false
        }
    }

    # プレースホルダを展開（プロース層のみ。コマンドは非翻訳のままカタログから来る）
    $expandValues = @{} + $Values
    if ($null -ne $finding.PSObject.Properties['Win32']) { $expandValues['win32'] = $finding.Win32 }
    # 呼び出し側が実値を知らない場合の既定。<...> 表記は非翻訳（<TASKNAME> と同じ慣習）で、
    # 「ここに自分の値を入れる」ことが日英どちらでも分かる。空文字は絶対に出さない。
    foreach ($p in @{ task = '<TASKNAME>'; command = '<COMMAND>' }.GetEnumerator()) {
        if (-not $expandValues.ContainsKey($p.Key) -or [string]::IsNullOrWhiteSpace([string] $expandValues[$p.Key])) {
            $expandValues[$p.Key] = $p.Value
        }
    }
    foreach ($field in 'Meaning', 'Cause', 'Next') {
        if ($finding.$field) {
            $finding.$field = Expand-TaskctlPlaceholder -Text $finding.$field -Catalog $catalog -Values $expandValues
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
    snippet の中身がさらにプレースホルダを含む（例: operational_log の {{task}}）ため、
    変化が無くなるまで繰り返す。循環参照に備えて回数を上限で打ち切る。
    複数行の値を差し込むときは、継続行をプレースホルダの桁へ揃える
    （揃えないとコマンドが左端に落ちて、コピペ範囲が読み取れなくなる）。
#>
function Expand-TaskctlPlaceholder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [object] $Catalog,

        [hashtable] $Values = @{},

        [int] $MaxPass = 5
    )

    $current = $Text
    for ($i = 0; $i -lt $MaxPass; $i++) {
        # 行頭からプレースホルダまでの空白を捉え、複数行の値をその桁へ揃える
        $next = [regex]::Replace($current, '(?m)^([ \t]*)(.*?)\{\{(\w+(?:\.\w+)?)\}\}', {
                param($m)
                $indent = $m.Groups[1].Value
                $before = $m.Groups[2].Value
                $ref = $m.Groups[3].Value

                $value = if ($ref -match '^snippets\.(\w+)$') {
                    $snippet = $Catalog.snippets.($Matches[1])
                    if ($null -eq $snippet) { $null } else { $snippet.TrimEnd() }
                }
                elseif ($Values.ContainsKey($ref)) { [string] $Values[$ref] }
                else { $null }

                if ($null -eq $value) { return $m.Value }   # 未定義は原文のまま

                # 2行目以降を、プレースホルダのある行のインデントへ揃える
                $lines = $value -split "`r?`n"
                if ($lines.Count -gt 1) {
                    $value = ($lines[0], ($lines[1..($lines.Count - 1)] | ForEach-Object { $indent + $_ })) -join "`n"
                }
                $indent + $before + $value
            })
        if ($next -eq $current) { return $next }
        $current = $next
    }
    Write-Verbose "プレースホルダの展開が $MaxPass 回で収束しませんでした（循環参照の可能性）"
    $current
}
