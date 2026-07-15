<#
.SYNOPSIS
    同梱データ（registry / メッセージカタログ）を読み込む。
.DESCRIPTION
    正本は data/*.yaml。ここで読むのは build/Convert-DataToJson.ps1 が生成した JSON で、
    実行時に powershell-yaml 依存を持ち込まないための設計。
    プロセス内でキャッシュする。
#>

$script:TaskctlDataCache = @{}

function Get-TaskctlDataPath {
    [CmdletBinding()]
    param()
    # 配置形態: src/Taskctl/Private/*.ps1 に対し src/Taskctl/data/*.json
    Join-Path (Split-Path $PSScriptRoot -Parent) 'data'
}

function Get-TaskctlRegistry {
    [CmdletBinding()]
    param()

    if (-not $script:TaskctlDataCache.ContainsKey('registry')) {
        $path = Join-Path (Get-TaskctlDataPath) 'registry.json'
        if (-not (Test-Path $path)) {
            throw "レジストリが見つかりません: $path`nbuild\Convert-DataToJson.ps1 を実行してください。"
        }
        $script:TaskctlDataCache['registry'] = Get-Content $path -Raw -Encoding utf8 | ConvertFrom-Json
    }
    $script:TaskctlDataCache['registry']
}

function Get-TaskctlRules {
    [CmdletBinding()]
    param()

    if (-not $script:TaskctlDataCache.ContainsKey('rules')) {
        $path = Join-Path (Get-TaskctlDataPath) 'rules.json'
        if (-not (Test-Path $path)) {
            throw "検出ルールが見つかりません: $path`nbuild\Convert-DataToJson.ps1 を実行してください。"
        }
        $script:TaskctlDataCache['rules'] = Get-Content $path -Raw -Encoding utf8 | ConvertFrom-Json
    }
    $script:TaskctlDataCache['rules']
}

function Get-TaskctlCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Locale
    )

    $cacheKey = "catalog:$Locale"
    if (-not $script:TaskctlDataCache.ContainsKey($cacheKey)) {
        $path = Join-Path (Get-TaskctlDataPath) "messages.$Locale.json"
        if (-not (Test-Path $path)) {
            throw "メッセージカタログが見つかりません: $path"
        }
        $script:TaskctlDataCache[$cacheKey] = Get-Content $path -Raw -Encoding utf8 | ConvertFrom-Json
    }
    $script:TaskctlDataCache[$cacheKey]
}

function Get-TaskctlSupportedLocale {
    [CmdletBinding()]
    param()

    Get-ChildItem (Get-TaskctlDataPath) -Filter 'messages.*.json' |
        ForEach-Object { $_.BaseName -replace '^messages\.', '' } |
        Sort-Object
}
