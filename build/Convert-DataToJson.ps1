<#
.SYNOPSIS
    data/ 配下の YAML（正本）を JSON へ変換し、モジュール同梱用に src/Taskctl/data/ へ出力する。
.NOTES
    powershell-yaml はビルド時のみの依存。実行時（モジュール本体）は ConvertFrom-Json だけで済ませる。
    出力 JSON は UTF-8 (BOM なし)。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable powershell-yaml)) {
    Write-Host 'powershell-yaml が見つからないためインストールします (CurrentUser)...'
    Install-Module powershell-yaml -Scope CurrentUser -Force
}
Import-Module powershell-yaml

$repoRoot = Split-Path $PSScriptRoot -Parent
$dataDir = Join-Path $repoRoot 'data'
$outDir = Join-Path $repoRoot 'src\Taskctl\data'
$null = New-Item -ItemType Directory -Force $outDir

$targets = @(
    @{ In = Join-Path $dataDir 'registry.yaml'; Out = Join-Path $outDir 'registry.json' }
)
foreach ($catalog in Get-ChildItem (Join-Path $dataDir 'messages') -Filter '*.yaml') {
    $targets += @{ In = $catalog.FullName; Out = Join-Path $outDir "messages.$($catalog.BaseName).json" }
}

foreach ($t in $targets) {
    $yaml = Get-Content $t.In -Raw -Encoding utf8
    $obj = ConvertFrom-Yaml $yaml
    $json = ConvertTo-Json $obj -Depth 10
    [System.IO.File]::WriteAllText($t.Out, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "converted: $($t.In) -> $($t.Out)"
}
