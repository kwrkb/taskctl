#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

Describe 'Taskctl モジュール' {
    BeforeAll {
        $script:manifestPath = Join-Path $PSScriptRoot '..\src\Taskctl\Taskctl.psd1'
    }

    It 'マニフェストが妥当である' {
        { Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Import-Module が成功する' {
        { Import-Module $script:manifestPath -Force -ErrorAction Stop } | Should -Not -Throw
    }
}
