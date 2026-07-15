#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# 注意: -ForEach のキーに Input は使えない（PowerShell の自動変数 $input と衝突して空になる）。

BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\Taskctl\Private\ConvertTo-TaskctlCode.ps1')
}

Describe 'ConvertTo-TaskctlCode' {
    Context '16進表記' {
        It '<Raw> -> <Expected>' -ForEach @(
            @{ Raw = '0x41303'; Expected = '0x00041303' }      # VISION の explain 例。8桁ゼロ埋め
            @{ Raw = '0x00041303'; Expected = '0x00041303' }
            @{ Raw = '0x2'; Expected = '0x00000002' }
            @{ Raw = '0x8004130a'; Expected = '0x8004130A' }   # 小文字 -> 大文字
            @{ Raw = '0X8004130A'; Expected = '0x8004130A' }   # 0X 接頭辞
            @{ Raw = '0x80070005'; Expected = '0x80070005' }   # int オーバーフロー域
            @{ Raw = '0xFFFFFFFF'; Expected = '0xFFFFFFFF' }
            @{ Raw = '0x0'; Expected = '0x00000000' }
        ) {
            (ConvertTo-TaskctlCode $Raw).Key | Should -Be $Expected
        }
    }

    Context '10進表記（数字のみは10進。16進と推測しない）' {
        It '<Raw> -> <Expected>' -ForEach @(
            @{ Raw = '2'; Expected = '0x00000002' }
            @{ Raw = '267011'; Expected = '0x00041303' }
            @{ Raw = '0'; Expected = '0x00000000' }
            @{ Raw = '1'; Expected = '0x00000001' }
            @{ Raw = '4294967295'; Expected = '0xFFFFFFFF' }
            @{ Raw = '41303'; Expected = '0x0000A157' }        # 0x41303 と解釈しない
        ) {
            (ConvertTo-TaskctlCode $Raw).Key | Should -Be $Expected
        }
    }

    Context '符号付き int32（LastTaskResult の実際の返り値）' {
        It '<Raw> -> <Expected>' -ForEach @(
            @{ Raw = '-2147024891'; Expected = '0x80070005' }  # E_ACCESSDENIED
            @{ Raw = '-2147216615'; Expected = '0x80041319' }  # SCHED_E_MISSINGNODE
            @{ Raw = '-1'; Expected = '0xFFFFFFFF' }
            @{ Raw = '-2147483648'; Expected = '0x80000000' }  # int32 の下限
        ) {
            (ConvertTo-TaskctlCode $Raw).Key | Should -Be $Expected
        }

        It '符号付き / 符号なしの両表現を返す' {
            $r = ConvertTo-TaskctlCode '0x80070005'
            $r.Unsigned | Should -Be ([uint32] 2147942405)
            $r.Signed | Should -Be ([int32] -2147024891)
        }

        It '正の範囲では Signed と Unsigned が一致する' {
            $r = ConvertTo-TaskctlCode '0x41303'
            $r.Unsigned | Should -Be ([uint32] 267011)
            $r.Signed | Should -Be ([int32] 267011)
        }

        It '負の10進と対応する hex が同じ Key になる' {
            (ConvertTo-TaskctlCode '-2147024891').Key |
                Should -Be (ConvertTo-TaskctlCode '0x80070005').Key
        }
    }

    Context '前後の空白' {
        It '空白を許容する' {
            (ConvertTo-TaskctlCode '  0x41303  ').Key | Should -Be '0x00041303'
        }
    }

    Context '不正な入力は例外（推測しない）' {
        It '<Raw> は throw する' -ForEach @(
            @{ Raw = '' }
            @{ Raw = '   ' }
            @{ Raw = 'abc' }
            @{ Raw = '0xZZ' }
            @{ Raw = '12.5' }
            @{ Raw = '0x123456789' }    # 32bit 超過
            @{ Raw = '4294967296' }     # 32bit 超過
            @{ Raw = '-2147483649' }    # int32 下限未満
            @{ Raw = '0x' }
        ) {
            { ConvertTo-TaskctlCode $Raw } | Should -Throw
        }
    }
}
