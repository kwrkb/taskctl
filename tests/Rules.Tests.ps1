#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# 検出ルールは正規化モデル上の純粋関数。fixture の XML だけで、実機・現在時刻に依存せず検証する。

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    & (Join-Path $repoRoot 'build\Convert-DataToJson.ps1') | Out-Null
    Import-Module (Join-Path $repoRoot 'src\Taskctl\Taskctl.psd1') -Force

    $script:fixtureDir = Join-Path $PSScriptRoot 'fixtures'

    # 時刻・固定ドライブ・実行ユーザーを固定して評価する（実機差で結果が揺れないように）
    $script:FixedNow = [datetime]'2026-07-15T12:00:00'
    $script:Drives = @('C')
    # fixture の Principal に合わせた「本人」の SID（存在チェック系ルールの前提）
    $script:FixtureSid = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
    $script:OtherSid = 'S-1-5-21-9999999999-8888888888-7777777777-1002'

    function Get-RuleId {
        param(
            [string] $Fixture,
            [object] $Info,
            [datetime] $Now = $script:FixedNow,
            [string[]] $FixedDrives = $script:Drives,
            [string] $CurrentSid = $script:FixtureSid
        )
        $xml = Get-Content (Join-Path $script:fixtureDir $Fixture) -Raw
        InModuleScope Taskctl -Parameters @{ x = $xml; i = $Info; n = $Now; d = $FixedDrives; s = $CurrentSid } {
            $model = ConvertFrom-TaskctlTaskXml -Xml $x -TaskName 'Fixture'
            @(Invoke-TaskctlRuleEngine -Model $model -Info $i -Now $n -FixedDrives $d `
                    -CurrentSid $s -CurrentName 'TESTHOST\fixture' |
                    ForEach-Object { $_.RuleId })
        }
    }

    function New-Info {
        param($LastRunTime, $LastTaskResult = 0, $NextRunTime, $NumberOfMissedRuns = 0)
        [PSCustomObject]@{
            LastRunTime        = $LastRunTime
            LastTaskResult     = $LastTaskResult
            NextRunTime        = $NextRunTime
            NumberOfMissedRuns = $NumberOfMissedRuns
        }
    }
}

Describe '検出ルール' {
    Context 'normal.xml（健全なタスク）' {
        It '所見を出さない（誤検知しない）' {
            $info = New-Info -LastRunTime ([datetime]'2026-07-15T02:00:00') -NextRunTime ([datetime]'2026-07-16T02:00:00')
            Get-RuleId 'normal.xml' -Info $info | Should -BeNullOrEmpty
        }
    }

    Context 'no-trigger-disabled.xml' {
        BeforeAll {
            $script:ids = Get-RuleId 'no-trigger-disabled.xml' -Info (New-Info -LastRunTime $null -NextRunTime $null)
        }

        It 'タスク無効を検出する' { $ids | Should -Contain 'task_disabled' }
        It '存在しない実行ファイルを検出する' { $ids | Should -Contain 'command_not_found' }
        It '多重起動許可を検出する' { $ids | Should -Contain 'multiple_instances_parallel' }

        It '無効なタスクにはトリガー系のルールを出さない（ノイズを増やさない）' {
            # 無効化が原因と分かっているのに、派生する所見まで並べない
            $ids | Should -Not -Contain 'no_triggers'
            $ids | Should -Not -Contain 'never_run'
            $ids | Should -Not -Contain 'no_next_run'
        }
    }

    Context 'relative-path.xml' {
        BeforeAll {
            $script:ids = Get-RuleId 'relative-path.xml' -Info (New-Info -LastRunTime ([datetime]'2026-07-15T09:00:00') -NextRunTime ([datetime]'2026-07-16T09:00:00'))
        }

        It '作業ディレクトリ未設定 + 相対パスを検出する' {
            $ids | Should -Contain 'relative_command_without_workdir'
        }

        It '相対パスは存在チェックの対象にしない（検査できないものを断定しない）' {
            $ids | Should -Not -Contain 'command_not_found'
        }

        It 'ログオン中のみ実行（InteractiveToken）を検出する' {
            $ids | Should -Contain 'run_only_if_logged_on'
        }
    }

    Context 'network-drive.xml' {
        BeforeAll {
            $script:ids = Get-RuleId 'network-drive.xml' -Info (New-Info -LastRunTime ([datetime]'2026-07-15T03:00:00') -NextRunTime ([datetime]'2026-07-16T03:00:00'))
        }

        It 'マップドライブ依存 (Z:) を検出する' {
            $ids | Should -Contain 'mapped_drive_dependency'
        }

        It 'SYSTEM 実行 + プロファイル依存変数を検出する' {
            $ids | Should -Contain 'profile_dependency_as_service'
        }

        It '短い実行時間制限 (PT30S) を検出する' {
            $ids | Should -Contain 'short_execution_time_limit'
        }

        It '環境変数を含むパスは存在チェックしない（別文脈で解決されうる）' {
            $ids | Should -Not -Contain 'working_directory_not_found'
        }
    }

    Context 'logon-only.xml（条件付き / 期限切れ）' {
        BeforeAll {
            $script:ids = Get-RuleId 'logon-only.xml' -Info (New-Info -LastRunTime ([datetime]'2020-12-31T12:00:00') -NextRunTime $null)
        }

        It '条件（ログオン / AC電源 / アイドル / ネットワーク）をすべて検出する' {
            $ids | Should -Contain 'run_only_if_logged_on'
            $ids | Should -Contain 'ac_power_only'
            $ids | Should -Contain 'idle_only'
            $ids | Should -Contain 'network_only'
        }

        It '終了境界切れを検出する' {
            $ids | Should -Contain 'past_end_boundary'
        }

        It '終了境界切れのタスクに no_next_run を重ねて出さない' {
            # 次回実行が無い理由は期限切れで説明済み。二重に言わない。
            $ids | Should -Not -Contain 'no_next_run'
        }
    }

    Context '誤検知への規律（VISION の中核）' {
        It 'v1 のルールに rank: fix は1つも無い（ヒューリスティックで断定しない）' {
            $ranks = InModuleScope Taskctl { @((Get-TaskctlRules).rules | ForEach-Object { $_.rank }) }
            $ranks | Should -Not -Contain 'fix'
        }

        It 'ファイル存在チェックは error にしない（文脈差で誤爆しうる）' {
            $rules = InModuleScope Taskctl { (Get-TaskctlRules).rules }
            foreach ($id in 'command_not_found', 'working_directory_not_found') {
                $rule = $rules | Where-Object id -eq $id
                $rule.severity | Should -Not -Be 'error' -Because "$id は文脈差で誤爆しうる"
                $rule.rank | Should -Be 'investigate' -Because "$id は調査に留める"
            }
        }

        It 'ヒューリスティック系のルールは Warning 止まりで、rank は investigate' {
            $rules = InModuleScope Taskctl { (Get-TaskctlRules).rules }
            foreach ($id in 'relative_command_without_workdir', 'mapped_drive_dependency') {
                $rule = $rules | Where-Object id -eq $id
                $rule.severity | Should -Be 'warning'
                $rule.rank | Should -Be 'investigate'
            }
        }

        It '仕様かもしれない条件は notice / decide にする' {
            $rules = InModuleScope Taskctl { (Get-TaskctlRules).rules }
            foreach ($id in 'run_only_if_logged_on', 'ac_power_only', 'idle_only', 'network_only') {
                $rule = $rules | Where-Object id -eq $id
                $rule.severity | Should -Be 'notice'
                $rule.rank | Should -Be 'decide'
            }
        }

        It 'ファクトが算出不能なら発火しない' {
            # 実行情報が取れないタスク（Info なし）で、info.* を見るルールが出ないこと
            $ids = Get-RuleId 'normal.xml' -Info $null
            $ids | Should -Not -Contain 'never_run'
            $ids | Should -Not -Contain 'no_next_run'
            $ids | Should -Not -Contain 'stale_last_run'
        }

        It '他ユーザーのタスクでは存在チェックをしない（読めないだけを「無い」と誤検知しない）' {
            # taskctl の Test-Path は本人の権限で走る。別ユーザーのタスクのパスは
            # 「本人に読めないだけで、実行時には見える」ことがある。
            $info = New-Info -LastRunTime $null -NextRunTime $null
            $ids = Get-RuleId 'no-trigger-disabled.xml' -Info $info -CurrentSid $script:OtherSid
            $ids | Should -Not -Contain 'command_not_found'
        }

        It '本人のタスクなら存在チェックする（検査できる時はする）' {
            $info = New-Info -LastRunTime $null -NextRunTime $null
            $ids = Get-RuleId 'no-trigger-disabled.xml' -Info $info -CurrentSid $script:FixtureSid
            $ids | Should -Contain 'command_not_found'
        }

        It 'SYSTEM 実行のタスクでは存在チェックをしない' {
            # network-drive.xml は S-1-5-18 (SYSTEM)
            $info = New-Info -LastRunTime ([datetime]'2026-07-15T03:00:00') -NextRunTime ([datetime]'2026-07-16T03:00:00')
            $ids = Get-RuleId 'network-drive.xml' -Info $info
            $ids | Should -Not -Contain 'command_not_found'
            $ids | Should -Not -Contain 'working_directory_not_found'
        }
    }

    Context '長期間未実行' {
        It '90日以上前なら検出する' {
            $info = New-Info -LastRunTime ([datetime]'2026-01-01T02:00:00') -NextRunTime ([datetime]'2026-07-16T02:00:00')
            Get-RuleId 'normal.xml' -Info $info | Should -Contain 'stale_last_run'
        }

        It '90日未満なら検出しない' {
            $info = New-Info -LastRunTime ([datetime]'2026-07-01T02:00:00') -NextRunTime ([datetime]'2026-07-16T02:00:00')
            Get-RuleId 'normal.xml' -Info $info | Should -Not -Contain 'stale_last_run'
        }
    }

    Context 'ルール ID とカタログの対応' {
        It 'すべてのルール ID に ja / en のプロースがある' {
            $ids = InModuleScope Taskctl { @((Get-TaskctlRules).rules | ForEach-Object { $_.id }) }
            foreach ($locale in 'ja', 'en') {
                $cat = InModuleScope Taskctl -Parameters @{ l = $locale } { Get-TaskctlCatalog -Locale $l }
                foreach ($id in $ids) {
                    $cat.rules.$id.meaning | Should -Not -BeNullOrEmpty -Because "$locale の $id"
                    $cat.rules.$id.next | Should -Not -BeNullOrEmpty -Because "$locale の $id"
                }
            }
        }

        It 'カタログに、存在しないルール ID のプロースが残っていない' {
            $ids = InModuleScope Taskctl { @((Get-TaskctlRules).rules | ForEach-Object { $_.id }) }
            foreach ($locale in 'ja', 'en') {
                $cat = InModuleScope Taskctl -Parameters @{ l = $locale } { Get-TaskctlCatalog -Locale $l }
                $catIds = @($cat.rules.PSObject.Properties.Name)
                Compare-Object $ids $catIds | Should -BeNullOrEmpty -Because "$locale のルールキー集合"
            }
        }

        It 'プロースのプレースホルダが展開され、残らない' {
            $info = New-Info -LastRunTime ([datetime]'2026-01-01T02:00:00') -NextRunTime $null
            foreach ($locale in 'ja', 'en') {
                $xml = Get-Content (Join-Path $script:fixtureDir 'network-drive.xml') -Raw
                $texts = InModuleScope Taskctl -Parameters @{ x = $xml; i = $info; l = $locale; n = $script:FixedNow; d = $script:Drives } {
                    $model = ConvertFrom-TaskctlTaskXml -Xml $x -TaskName 'Fixture'
                    Invoke-TaskctlRuleEngine -Model $model -Info $i -Now $n -FixedDrives $d |
                        Resolve-TaskctlRuleProse -Locale $l |
                        ForEach-Object { "$($_.Meaning)`n$($_.Cause)`n$($_.Next)" }
                }
                foreach ($t in $texts) {
                    $t | Should -Not -Match '\{\{' -Because "$locale で未展開のプレースホルダ"
                }
            }
        }
    }
}
