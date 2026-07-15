#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# doctor の統合テスト。取得層 (Get-TaskctlTask) をモックし、実機に依存せず検証する。

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    & (Join-Path $repoRoot 'build\Convert-DataToJson.ps1') | Out-Null
    Import-Module (Join-Path $repoRoot 'src\Taskctl\Taskctl.psd1') -Force
    $script:fixtureDir = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'Invoke-TaskctlDoctor' {
    BeforeAll {
        # fixture から取得層の戻り値を組み立てる
        function New-Acquired {
            param(
                [string] $Fixture,
                [string] $Name,
                [string] $State = 'Ready',
                $LastTaskResult = 0,
                $LastRunTime = ([datetime]'2026-07-15T02:00:00'),
                $NextRunTime = ([datetime]'2026-07-16T02:00:00'),
                [string] $AcquireError
            )
            $xml = Get-Content (Join-Path $script:fixtureDir $Fixture) -Raw
            InModuleScope Taskctl -Parameters @{
                x = $xml; n = $Name; s = $State; r = $LastTaskResult
                lr = $LastRunTime; nr = $NextRunTime; e = $AcquireError
            } {
                [PSCustomObject]@{
                    TaskName     = $n
                    TaskPath     = '\'
                    FullName     = "\$n"
                    State        = $s
                    Model        = ConvertFrom-TaskctlTaskXml -Xml $x -TaskName $n -TaskPath '\'
                    Info         = [PSCustomObject]@{
                        LastRunTime        = $lr
                        LastTaskResult     = $r
                        NextRunTime        = $nr
                        NumberOfMissedRuns = 0
                    }
                    AcquireError = $e
                }
            }
        }
    }

    Context '失敗タスクの診断（結果コード翻訳の統合）' {
        BeforeAll {
            $acq = New-Acquired -Fixture 'normal.xml' -Name 'FailingTask' -LastTaskResult 2
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It '最終結果を翻訳して3点セットで示す' {
            $out = Invoke-TaskctlDoctor -Lang ja
            $out | Should -Match 'ERROR_FILE_NOT_FOUND'
            $out | Should -Match '0x00000002'
            $out | Should -Match 'これは何'
            $out | Should -Match '次の一手'
        }

        It '終了コード 2（警告あり）を返す' {
            Invoke-TaskctlDoctor -Lang ja | Out-Null
            Get-TaskctlExitCode | Should -Be 2
        }

        It '--json に exit_code と言語非依存フィールドを載せる' {
            $j = Invoke-TaskctlDoctor -Lang ja -Json | ConvertFrom-Json
            $j.exit_code | Should -Be 2
            $j.scanned | Should -Be 1
            $j.tasks[0].last_result.code | Should -Be '0x00000002'
            $j.tasks[0].last_result.constant | Should -Be 'ERROR_FILE_NOT_FOUND'
            $j.tasks[0].last_result.is_failure | Should -BeTrue
        }
    }

    Context '未知の非ゼロ結果コード（失敗を緑で返さない）' {
        BeforeAll {
            # 0x00002EE7 は翻訳表に無い。実機で ViGEmBus_Updater が返していた実際の値。
            $acq = New-Acquired -Fixture 'normal.xml' -Name 'UnknownFail' -LastTaskResult 12007
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It '終了コード 2 を返す（未知でも失敗は失敗）' {
            Invoke-TaskctlDoctor -Lang ja | Out-Null
            Get-TaskctlExitCode | Should -Be 2
        }

        It '走査時の詳細に出る（一覧に埋もれさせない）' {
            $out = Invoke-TaskctlDoctor -Lang ja
            $out | Should -Match 'UnknownFail'
            $out | Should -Match '0x00002EE7'
            $out | Should -Match '翻訳表に無い'
            $out | Should -Match '次の一手 \[調査\]'
        }

        It '--json で is_failure と severity が整合する' {
            $j = Invoke-TaskctlDoctor -Lang ja -Json | ConvertFrom-Json
            $j.exit_code | Should -Be 2
            $j.tasks[0].last_result.is_failure | Should -BeTrue
            $j.tasks[0].last_result.severity | Should -Be 'warning'
            $j.tasks[0].last_result.known | Should -BeFalse
        }
    }

    Context '終了コード 3（重大な問題）' {
        BeforeAll {
            # SCHED_E_SERVICE_NOT_RUNNING (0x80041315) は registry で severity: error
            $acq = New-Acquired -Fixture 'normal.xml' -Name 'ErrorTask' -LastTaskResult -2147216619
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It 'error の結果コードで終了コード 3 を返す' {
            $out = Invoke-TaskctlDoctor -Lang ja
            $out | Should -Match 'SCHED_E_SERVICE_NOT_RUNNING'
            Get-TaskctlExitCode | Should -Be 3
        }

        It '--json の exit_code も 3' {
            $j = Invoke-TaskctlDoctor -Lang ja -Json | ConvertFrom-Json
            $j.exit_code | Should -Be 3
            $j.summary.errors | Should -Be 1
        }
    }

    Context '成功タスク（問題なし）' {
        BeforeAll {
            $acq = New-Acquired -Fixture 'normal.xml' -Name 'HealthyTask' -LastTaskResult 0
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It '終了コード 0 を返す' {
            Invoke-TaskctlDoctor -Lang ja | Out-Null
            Get-TaskctlExitCode | Should -Be 0
        }

        It '走査時は成功タスクの結果コードを載せない（出力を短く保つ）' {
            $out = Invoke-TaskctlDoctor -Lang ja
            $out | Should -Not -Match 'S_OK'
        }

        It '深掘り時は成功でも結果コードを翻訳して示す' {
            $out = Invoke-TaskctlDoctor -TaskName 'HealthyTask' -Lang ja
            $out | Should -Match 'S_OK'
            $out | Should -Match '正常終了'
        }

        It '一覧に状態と次回実行を載せる' {
            $out = Invoke-TaskctlDoctor -Lang ja
            $out | Should -Match '一覧'
            $out | Should -Match 'HealthyTask'
            $out | Should -Match '2026-07-16'
        }
    }

    Context 'notice だけのタスク（仕様かもしれない）' {
        BeforeAll {
            $acq = New-Acquired -Fixture 'logon-only.xml' -Name 'NoticeOnly' -LastTaskResult 0 -NextRunTime $null
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It '終了コードは 0（notice で自動化を騒がせない）' {
            Invoke-TaskctlDoctor -Lang ja | Out-Null
            Get-TaskctlExitCode | Should -Be 0
        }

        It '走査時は詳細を出さず、一覧にだけ載せる' {
            $out = Invoke-TaskctlDoctor -Lang ja
            $out | Should -Not -Match 'run_only_if_logged_on'
            $out | Should -Match 'NoticeOnly'
        }

        It '深掘りすれば notice の所見も出す' {
            $out = Invoke-TaskctlDoctor -TaskName 'NoticeOnly' -Lang ja
            $out | Should -Match 'run_only_if_logged_on'
        }

        It '--json には notice も常に載せる（機械可読を削らない）' {
            $j = Invoke-TaskctlDoctor -Lang ja -Json | ConvertFrom-Json
            $j.summary.notices | Should -BeGreaterThan 0
            @($j.tasks[0].findings.rule) | Should -Contain 'run_only_if_logged_on'
        }
    }

    Context '複数タスクの集計' {
        BeforeAll {
            $acq = @(
                New-Acquired -Fixture 'normal.xml' -Name 'Ok' -LastTaskResult 0
                New-Acquired -Fixture 'relative-path.xml' -Name 'Warn' -LastTaskResult 0
                New-Acquired -Fixture 'logon-only.xml' -Name 'Notice' -LastTaskResult 0 -NextRunTime $null
            )
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It '最も重い深刻度で終了コードを決める' {
            Invoke-TaskctlDoctor -Lang ja | Out-Null
            Get-TaskctlExitCode | Should -Be 2      # warning あり
        }

        It '走査数と内訳を先頭に出す' {
            $out = Invoke-TaskctlDoctor -Lang ja
            $out | Should -Match '走査 3 タスク'
        }

        It '--json は全タスクを載せる' {
            $j = Invoke-TaskctlDoctor -Lang ja -Json | ConvertFrom-Json
            $j.scanned | Should -Be 3
            @($j.tasks.task) | Should -Contain '\Ok'
            @($j.tasks.task) | Should -Contain '\Warn'
        }
    }

    Context '取得に失敗したタスク' {
        BeforeAll {
            $acq = InModuleScope Taskctl {
                [PSCustomObject]@{
                    TaskName     = 'Broken'
                    TaskPath     = '\'
                    FullName     = '\Broken'
                    State        = 'Unknown'
                    Model        = $null
                    Info         = $null
                    AcquireError = 'アクセスが拒否されました'
                }
            }
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It '取得エラーを報告し、他を落とさない' {
            $out = Invoke-TaskctlDoctor -Lang ja
            $out | Should -Match 'Broken'
            $out | Should -Match 'アクセスが拒否されました'
        }

        It 'モデルが無くても throw しない' {
            { Invoke-TaskctlDoctor -Lang ja } | Should -Not -Throw
        }

        It '--json に acquire_error を載せる' {
            $j = Invoke-TaskctlDoctor -Lang ja -Json | ConvertFrom-Json
            $j.tasks[0].acquire_error | Should -Be 'アクセスが拒否されました'
        }
    }

    Context 'i18n' {
        BeforeAll {
            $acq = New-Acquired -Fixture 'relative-path.xml' -Name 'I18nTask' -LastTaskResult 2
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It '日英でプロースが切り替わる' {
            (Invoke-TaskctlDoctor -Lang ja) | Should -Match 'これは何'
            (Invoke-TaskctlDoctor -Lang en) | Should -Match 'What this is'
        }

        It 'ルール ID と定数名は非翻訳（grep の安定キー）' {
            foreach ($lang in 'ja', 'en') {
                $out = Invoke-TaskctlDoctor -Lang $lang
                $out | Should -Match 'relative_command_without_workdir'
                $out | Should -Match 'ERROR_FILE_NOT_FOUND'
            }
        }

        It '日英で所見の件数（事実）は変わらない' {
            $ja = Invoke-TaskctlDoctor -Lang ja -Json | ConvertFrom-Json
            $en = Invoke-TaskctlDoctor -Lang en -Json | ConvertFrom-Json
            $en.exit_code | Should -Be $ja.exit_code
            @($en.tasks[0].findings.rule) | Should -Be @($ja.tasks[0].findings.rule)
        }
    }

    Context 'コマンドがそのままコピペできる（VISION の成功条件）' {
        BeforeAll {
            $acq = New-Acquired -Fixture 'network-drive.xml' -Name 'CopyPasteTask' -LastTaskResult 1
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It '結果コードの所見に実際のコマンドが埋まる（<COMMAND> のままにしない）' {
            $out = Invoke-TaskctlDoctor -TaskName 'CopyPasteTask' -Lang ja
            $out | Should -Match 'powershell\.exe -File Z:\\scripts\\backup\.ps1'
            $out | Should -Not -Match '<COMMAND>'
        }

        It '実際のタスク名が埋まる（<TASKNAME> のままにしない）' {
            $out = Invoke-TaskctlDoctor -TaskName 'CopyPasteTask' -Lang ja
            $out | Should -Not -Match '<TASKNAME>'
        }

        It '日英どちらでも同じコマンドが出る（コマンドは非翻訳）' {
            foreach ($lang in 'ja', 'en') {
                Invoke-TaskctlDoctor -TaskName 'CopyPasteTask' -Lang $lang |
                    Should -Match 'powershell\.exe -File Z:\\scripts\\backup\.ps1'
            }
        }
    }

    Context 'コマンドが実際に対象へ届く（TaskPath とエスケープ）' {
        It 'フォルダ配下のタスクには -TaskPath を付ける' {
            # -TaskName にフルパスは渡せない（cmdlet が受け付けない）。-TaskPath を省くと
            # ルートが対象になり、失敗するか別タスクを操作してしまう。
            $v = InModuleScope Taskctl { Get-TaskctlTaskValue -TaskName 'MyTask' -TaskPath '\Foo\Bar\' }
            $v.task_args | Should -Be "-TaskName 'MyTask' -TaskPath '\Foo\Bar\'"
            $v.task | Should -Be '\Foo\Bar\MyTask'
        }

        It 'TaskPath が無い / 末尾の \ が無い場合を補正する' {
            (InModuleScope Taskctl { Get-TaskctlTaskValue -TaskName 'T' -TaskPath $null }).task_args |
                Should -Be "-TaskName 'T' -TaskPath '\'"
            (InModuleScope Taskctl { Get-TaskctlTaskValue -TaskName 'T' -TaskPath '\Foo' }).task_args |
                Should -Be "-TaskName 'T' -TaskPath '\Foo\'"
        }

        It "単一引用符を含む名前をエスケープする" {
            $v = InModuleScope Taskctl { Get-TaskctlTaskValue -TaskName "It's" -TaskPath '\' }
            $v.task_args | Should -Be "-TaskName 'It''s' -TaskPath '\'"
        }

        It '正規表現メタ文字を含む名前をエスケープする' {
            # -match に生の名前を埋めると a[b で正規表現エラーになる
            $v = InModuleScope Taskctl { Get-TaskctlTaskValue -TaskName 'a[b' -TaskPath '\' }
            $v.task_regex | Should -Be '\\a\[b'
            { [regex]::Match('x', $v.task_regex) } | Should -Not -Throw
        }

        It '生成した引数が実際の cmdlet で解釈できる' {
            # 文字列としてではなく、PowerShell のパーサが引数として解釈できることを確認する
            $v = InModuleScope Taskctl { Get-TaskctlTaskValue -TaskName "It's a Task" -TaskPath '\Foo\' }
            $parsed = [System.Management.Automation.Language.Parser]::ParseInput(
                "Get-ScheduledTask $($v.task_args)", [ref]$null, [ref]$null)
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseInput(
                "Get-ScheduledTask $($v.task_args)", [ref]$null, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
            # 名前が引数として正しく復元されること
            $cmd = $parsed.EndBlock.Statements[0].PipelineElements[0]
            $cmd.CommandElements[2].Value | Should -Be "It's a Task"
        }
    }

    Context '--verbose（生の設定）' {
        BeforeAll {
            $acq = New-Acquired -Fixture 'network-drive.xml' -Name 'RawTask' -LastTaskResult 2
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It '既定では生の設定を出さない' {
            Invoke-TaskctlDoctor -Lang ja | Should -Not -Match '生の設定'
        }

        It '操作 / プリンシパル / トリガー / 設定を出す' {
            $out = Invoke-TaskctlDoctor -Lang ja -Raw
            $out | Should -Match '生の設定'
            $out | Should -Match 'powershell\.exe'
            $out | Should -Match 'S-1-5-18'
            $out | Should -Match 'TimeTrigger'
            $out | Should -Match 'MultipleInstancesPolicy=Parallel'
        }

        It '環境変数を展開せずそのまま見せる（別文脈の値と食い違わせない）' {
            Invoke-TaskctlDoctor -Lang ja -Raw | Should -Match '%USERPROFILE%\\work'
        }

        It 'taskctl doctor --verbose から渡る' {
            taskctl doctor --verbose --lang ja | Should -Match '生の設定'
        }

        It 'explain の --verbose は無視される（生の設定は doctor 用）' {
            { taskctl explain 0x2 --verbose --lang ja } | Should -Not -Throw
        }
    }

    Context 'タスク名の解決（取得層）' {
        BeforeAll {
            # Get-ScheduledTask を差し替え、-TaskName がワイルドカードとして解釈される挙動を再現する
            Mock -ModuleName Taskctl Get-ScheduledTask {
                $all = @(
                    [PSCustomObject]@{ TaskName = 'a[b'; TaskPath = '\'; State = 'Ready' }
                    [PSCustomObject]@{ TaskName = 'Plain'; TaskPath = '\'; State = 'Ready' }
                )
                if ($TaskName) {
                    # 実物と同じく、不正なワイルドカードパターンなら throw する
                    if ($TaskName -match '\[') { throw 'The specified wildcard character pattern is not valid: ' + $TaskName }
                    return @($all | Where-Object { $_.TaskName -like $TaskName })
                }
                $all
            }
            Mock -ModuleName Taskctl Export-ScheduledTask { Get-Content (Join-Path $script:fixtureDir 'normal.xml') -Raw }
            Mock -ModuleName Taskctl Get-ScheduledTaskInfo {
                [PSCustomObject]@{ LastRunTime = [datetime]'2026-07-15T02:00:00'; LastTaskResult = 0
                    NextRunTime = [datetime]'2026-07-16T02:00:00'; NumberOfMissedRuns = 0 }
            }
        }

        It '"[" を含むタスク名でも解決できる（ワイルドカード不正で落ちない）' {
            # タスク名に "[" は使える。-TaskName はワイルドカードとして解釈するため、
            # そのまま渡すと .NET の内部例外が漏れていた。
            $r = @(InModuleScope Taskctl { Get-TaskctlTask -TaskName 'a[b' })
            $r.Count | Should -Be 1
            $r[0].TaskName | Should -Be 'a[b'
        }

        It '存在しないタスクは分かりやすく throw する' {
            { InModuleScope Taskctl { Get-TaskctlTask -TaskName 'NoSuchTask' } } |
                Should -Throw '*タスクが見つかりません*'
        }
    }

    Context 'taskctl ディスパッチャ経由' {
        BeforeAll {
            $acq = New-Acquired -Fixture 'normal.xml' -Name 'DispatchTask' -LastTaskResult 0
            Mock -ModuleName Taskctl Get-TaskctlTask { $acq }.GetNewClosure()
        }

        It 'taskctl doctor が動く' {
            taskctl doctor --lang ja | Should -Match '走査 1 タスク'
        }

        It 'taskctl doctor <task> が深掘りになる' {
            taskctl doctor DispatchTask --lang ja | Should -Match 'S_OK'
        }

        It 'taskctl doctor --json が妥当な JSON を返す' {
            { taskctl doctor --json | ConvertFrom-Json } | Should -Not -Throw
        }
    }
}
