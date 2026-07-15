#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# 取得層を介さず、fixture の XML から正規化モデルへの変換だけを検証する（実機不要）。

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\Taskctl\Private\ConvertFrom-TaskctlTaskXml.ps1')
    $script:fixtureDir = Join-Path $PSScriptRoot 'fixtures'
    function Read-Fixture {
        param([string] $Name)
        ConvertFrom-TaskctlTaskXml -Xml (Get-Content (Join-Path $script:fixtureDir $Name) -Raw) -TaskName ($Name -replace '\.xml$', '')
    }
}

Describe 'ConvertFrom-TaskctlTaskXml' {
    Context '既定名前空間の扱い' {
        It '名前空間付きの XML から値を取り出せる（無言で空にならない）' {
            # タスク XML は既定名前空間を持つ。名前空間マネージャなしの XPath は何も返さない。
            $m = Read-Fixture 'normal.xml'
            $m.Uri | Should -Be '\NormalBackup'
            $m.Actions | Should -Not -BeNullOrEmpty
            $m.Triggers | Should -Not -BeNullOrEmpty
            $m.Settings | Should -Not -BeNullOrEmpty
            $m.Principal | Should -Not -BeNullOrEmpty
        }

        It 'タスク XML でなければ throw する' {
            { ConvertFrom-TaskctlTaskXml -Xml '<foo/>' } | Should -Throw '*タスク XML として解釈できません*'
        }
    }

    Context 'normal.xml（健全なタスク）' {
        BeforeAll { $script:m = Read-Fixture 'normal.xml' }

        It '操作 (Exec) を取り出す' {
            $m.Actions.Count | Should -Be 1
            $m.Actions[0].Type | Should -Be 'Exec'
            $m.Actions[0].Command | Should -Be 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
            $m.Actions[0].Arguments | Should -Match 'backup\.ps1'
            $m.Actions[0].WorkingDirectory | Should -Be 'C:\Windows\System32'
        }

        It 'プリンシパルを取り出す' {
            $m.Principal.UserId | Should -Match '^S-1-5-21-'
            $m.Principal.LogonType | Should -Be 'Password'
            $m.Principal.RunLevel | Should -Be 'LeastPrivilege'
        }

        It 'トリガーを取り出す' {
            $m.Triggers.Count | Should -Be 1
            $m.Triggers[0].Type | Should -Be 'CalendarTrigger'
            $m.Triggers[0].Enabled | Should -BeTrue
            $m.Triggers[0].StartBoundary | Should -Be '2026-01-01T02:00:00+09:00'
            $m.Triggers[0].EndBoundary | Should -BeNullOrEmpty
        }

        It '設定を取り出す' {
            $m.Enabled | Should -BeTrue
            $m.Settings.ExecutionTimeLimit | Should -Be 'PT1H'
            $m.Settings.MultipleInstancesPolicy | Should -Be 'IgnoreNew'
            $m.Settings.DisallowStartIfOnBatteries | Should -BeFalse
            $m.Settings.RunOnlyIfIdle | Should -BeFalse
            $m.Settings.StartWhenAvailable | Should -BeTrue
        }
    }

    Context 'relative-path.xml（作業ディレクトリ未設定 + 相対パス）' {
        BeforeAll { $script:m = Read-Fixture 'relative-path.xml' }

        It '相対パスの Command をそのまま保持する' {
            $m.Actions[0].Command | Should -Be 'scripts\run.bat'
        }

        It '未設定の WorkingDirectory は $null（空文字と区別する）' {
            $m.Actions[0].WorkingDirectory | Should -BeNullOrEmpty
        }
    }

    Context 'network-drive.xml（マップドライブ依存）' {
        BeforeAll { $script:m = Read-Fixture 'network-drive.xml' }

        It '引数にドライブレターを保持する' {
            $m.Actions[0].Arguments | Should -Match 'Z:\\scripts\\backup\.ps1'
        }

        It '環境変数を含む作業ディレクトリを展開せずに保持する' {
            # taskctl が動く文脈と、タスクが走る文脈は異なる。ここで展開してはいけない。
            $m.Actions[0].WorkingDirectory | Should -Be '%USERPROFILE%\work'
        }

        It 'SYSTEM プリンシパルと RunLevel を取り出す' {
            $m.Principal.UserId | Should -Be 'S-1-5-18'
            $m.Principal.RunLevel | Should -Be 'HighestAvailable'
        }
    }

    Context 'logon-only.xml（条件付き実行 / 期限切れトリガー）' {
        BeforeAll { $script:m = Read-Fixture 'logon-only.xml' }

        It '条件（電源/アイドル/ネットワーク）を取り出す' {
            $m.Settings.DisallowStartIfOnBatteries | Should -BeTrue
            $m.Settings.StopIfGoingOnBatteries | Should -BeTrue
            $m.Settings.RunOnlyIfIdle | Should -BeTrue
            $m.Settings.RunOnlyIfNetworkAvailable | Should -BeTrue
        }

        It 'ログオン中のみ実行（InteractiveToken）を取り出す' {
            $m.Principal.LogonType | Should -Be 'InteractiveToken'
        }

        It '終了境界を取り出す' {
            $m.Triggers[0].EndBoundary | Should -Be '2021-01-01T12:00:00+09:00'
        }
    }

    Context 'no-trigger-disabled.xml（無効 / トリガー無し / 既定値の省略）' {
        BeforeAll { $script:m = Read-Fixture 'no-trigger-disabled.xml' }

        It '無効なタスクを検出できる' {
            $m.Enabled | Should -BeFalse
            $m.Settings.Enabled | Should -BeFalse
        }

        It 'トリガー無しは空配列（$null ではない）' {
            $m.Triggers | Should -BeNullOrEmpty
            , $m.Triggers | Should -BeOfType [System.Object[]]
        }

        It '省略された設定はタスクスケジューラの既定値になる' {
            # XML に要素が無い場合、実際のタスクスケジューラの既定に合わせる
            $m.Settings.DisallowStartIfOnBatteries | Should -BeTrue   # 既定 true
            $m.Settings.RunOnlyIfIdle | Should -BeFalse               # 既定 false
            $m.Settings.StartWhenAvailable | Should -BeFalse          # 既定 false
        }

        It '未設定の ExecutionTimeLimit は $null' {
            $m.Settings.ExecutionTimeLimit | Should -BeNullOrEmpty
        }

        It '多重起動ポリシーを取り出す' {
            $m.Settings.MultipleInstancesPolicy | Should -Be 'Parallel'
        }
    }
}
