# Taskctl.psm1 — モジュールローダー
# Public/ と Private/ の .ps1 を読み込み、Public のみエクスポートする。

$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in ($public + $private)) {
    . $file.FullName
}

Export-ModuleMember -Function $public.BaseName
