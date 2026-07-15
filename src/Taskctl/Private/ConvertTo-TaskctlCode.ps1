<#
.SYNOPSIS
    結果コード文字列を uint32 hex（0x + 大文字8桁）へ正規化する。
.DESCRIPTION
    LastTaskResult は符号付き 32bit int で返るため、lookup 前に必ず正規化する。
      - "0x" 接頭辞あり  16進として解釈
      - 数字のみ         10進として解釈（16進と推測しない）
      - 負値             uint32 へ折り返す（例: -2147024891 -> 0x80070005）
    [int] は 0x80000000 以上でオーバーフローするため int64 で扱う。
.OUTPUTS
    PSCustomObject: Key (0xXXXXXXXX), Unsigned (uint32), Signed (int32)
#>
function ConvertTo-TaskctlCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Code
    )

    $text = $Code.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "結果コードが空です。16進 (0x41303) か10進 (267011) で指定してください。"
    }

    $negative = $false
    if ($text -match '^[+-]') {
        $negative = $text[0] -eq '-'
        $text = $text.Substring(1)
    }

    [int64] $value = 0
    if ($text -match '^0[xX][0-9a-fA-F]+$') {
        $hex = $text.Substring(2)
        if ($hex.Length -gt 8) {
            throw "結果コードが 32bit の範囲を超えています: $Code"
        }
        $value = [Convert]::ToInt64($hex, 16)
    }
    elseif ($text -match '^[0-9]+$') {
        try {
            $value = [Convert]::ToInt64($text, 10)
        }
        catch {
            throw "結果コードが 32bit の範囲を超えています: $Code"
        }
    }
    else {
        throw "結果コードとして解釈できません: $Code (例: 0x41303, 267011, -2147024891)"
    }

    if ($negative) { $value = -$value }

    if ($value -gt 4294967295L -or $value -lt -2147483648L) {
        throw "結果コードが 32bit の範囲を超えています: $Code"
    }

    # uint32 へ折り返す（負値は 2^32 を足すのと同じ）
    [int64] $unsigned = $value -band 0xFFFFFFFFL
    # [int32] へのキャストは PowerShell では折り返さずオーバーフローするため、自前で折り返す
    [int64] $signedValue = if ($unsigned -gt 2147483647L) { $unsigned - 4294967296L } else { $unsigned }
    [int32] $signed = [int32] $signedValue

    [PSCustomObject]@{
        Key      = '0x{0:X8}' -f $unsigned
        Unsigned = [uint32] $unsigned
        Signed   = $signed
    }
}
