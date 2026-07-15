<#
.SYNOPSIS
    コンソール出力のエンコーディングを整える。
.DESCRIPTION
    VISION: 出力は UTF-8 を既定とする。ただし Windows コンソールは既定コードページ
    （日本語環境で CP932）や PowerShell 5.1 の出力エンコーディングで化けうる。
    ここでは「化けない側へ寄せる」だけを行い、直せない場合は Get-TaskctlEncodingHint が案内を返す。
    副作用を持つのでモジュール読み込み時ではなく、コマンド実行時に呼ぶ。
#>
function Initialize-TaskctlConsole {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not $PSCmdlet.ShouldProcess('console', 'set output encoding to UTF-8')) { return }

    try {
        if ([Console]::OutputEncoding.CodePage -ne 65001) {
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        }
    }
    catch {
        # リダイレクト中などで設定できないことがある。致命的ではないので握りつぶす。
        Write-Verbose "コンソールのエンコーディングを設定できませんでした: $_"
    }
}

<#
.SYNOPSIS
    文字化けのおそれがある環境なら、対処法の案内文を返す。無ければ $null。
#>
function Get-TaskctlEncodingHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Locale
    )

    # 非 ASCII を出さない言語なら関係ない
    if ($Locale -eq 'en') { return $null }

    # PowerShell 7 かつ UTF-8 コンソールなら問題は起きない
    $isUtf8 = $false
    try { $isUtf8 = [Console]::OutputEncoding.CodePage -eq 65001 } catch { $isUtf8 = $false }
    if ($isUtf8 -and $PSVersionTable.PSVersion.Major -ge 6) { return $null }

    $hint = if ($Locale -eq 'ja') {
        @'
文字化けする場合は、次のいずれかをお試しください:
  chcp 65001            # コンソールを UTF-8 にする
  pwsh                  # PowerShell 7 を使う（推奨）
  taskctl explain <code> --lang en   # 英語で表示する
'@
    }
    else {
        @'
If the text is garbled, try one of the following:
  chcp 65001            # switch the console to UTF-8
  pwsh                  # use PowerShell 7 (recommended)
'@
    }
    $hint
}
