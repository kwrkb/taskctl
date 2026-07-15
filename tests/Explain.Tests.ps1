#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    & (Join-Path $repoRoot 'build\Convert-DataToJson.ps1') | Out-Null
    Import-Module (Join-Path $repoRoot 'src\Taskctl\Taskctl.psd1') -Force
}

Describe 'Resolve-TaskctlLocale' {
    BeforeAll {
        $supported = @('en', 'ja')
        # Private 関数はモジュールスコープで呼ぶ
        function locale {
            param($Lang, $EnvLang, $UICulture)
            InModuleScope Taskctl -Parameters @{ l = $Lang; e = $EnvLang; u = $UICulture } {
                Resolve-TaskctlLocale -Lang $l -EnvLang $e -UICulture $u -Supported @('en', 'ja')
            }
        }
    }

    It '優先順位: --lang > TASKCTL_LANG > UI カルチャ > en' {
        locale -Lang 'ja' -EnvLang 'en' -UICulture 'en-US' | Should -Be 'ja'
        locale -Lang $null -EnvLang 'ja' -UICulture 'en-US' | Should -Be 'ja'
        locale -Lang $null -EnvLang $null -UICulture 'ja-JP' | Should -Be 'ja'
        locale -Lang $null -EnvLang $null -UICulture $null | Should -Be 'en'
    }

    It 'ja-JP / en_US のようなカルチャ名を先頭サブタグで解決する' {
        locale -Lang 'ja-JP' -EnvLang $null -UICulture $null | Should -Be 'ja'
        locale -Lang 'en_US' -EnvLang $null -UICulture $null | Should -Be 'en'
        locale -Lang 'JA' -EnvLang $null -UICulture $null | Should -Be 'ja'
    }

    It '未対応ロケールは次の段へ落ち、最終的に en へフォールバックする' {
        # VISION: 未対応の所は英語へフォールバックし、空文字は絶対に出さない
        locale -Lang 'fr' -EnvLang $null -UICulture $null | Should -Be 'en'
        locale -Lang 'de-DE' -EnvLang $null -UICulture 'ja-JP' | Should -Be 'ja'  # --lang が未対応なら次段
        locale -Lang $null -EnvLang 'fr' -UICulture 'zh-CN' | Should -Be 'en'
    }

    It '空文字や空白は無視して次の段へ落ちる' {
        locale -Lang '' -EnvLang 'ja' -UICulture $null | Should -Be 'ja'
        locale -Lang '  ' -EnvLang $null -UICulture 'ja-JP' | Should -Be 'ja'
    }
}

Describe 'Invoke-TaskctlExplain' {
    Context '既知のコード（レジストリに完全一致）' {
        It 'VISION の例 0x41303 を状態コードとして説明する' {
            $out = Invoke-TaskctlExplain '0x41303' -Lang ja
            $out | Should -Match 'SCHED_S_TASK_HAS_NOT_RUN'
            $out | Should -Match '0x00041303'
            $out | Should -Match '267011'          # 10進併記
            $out | Should -Match '状態コード'
            $out | Should -Match 'これは何'
            $out | Should -Match '次の一手'
        }

        It '日英で同じ事実（コード/定数）を示し、プロースだけが変わる' {
            $ja = Invoke-TaskctlExplain '0x2' -Lang ja
            $en = Invoke-TaskctlExplain '0x2' -Lang en
            foreach ($out in $ja, $en) {
                $out | Should -Match 'ERROR_FILE_NOT_FOUND'   # 定数名は非翻訳
                $out | Should -Match '0x00000002'
            }
            $ja | Should -Match 'これは何'
            $en | Should -Match 'What this is'
        }

        It 'コマンドは翻訳されない（日英どちらでもそのままコピペできる）' {
            # VISION: 日英いずれの表示でも、コマンドはそのままコピペして動く
            foreach ($lang in 'ja', 'en') {
                $out = Invoke-TaskctlExplain '0x41302' -Lang $lang
                $out | Should -Match 'Enable-ScheduledTask -TaskName'
            }
        }

        It '{{snippets.*}} が展開され、プレースホルダが残らない' {
            foreach ($lang in 'ja', 'en') {
                $out = Invoke-TaskctlExplain '0x1' -Lang $lang
                $out | Should -Not -Match '\{\{'
                $out | Should -Not -Match '\}\}'
            }
        }

        It 'snippet の中のプレースホルダも展開される（多段展開）' {
            # {{snippets.operational_log}} の中身に {{task}} が入っている。
            # 1パスだと snippet を差し込んだだけで {{task}} が残る。
            $out = Invoke-TaskctlExplain '0x41306' -Lang ja
            $out | Should -Match 'Get-WinEvent'
            $out | Should -Not -Match '\{\{'
        }

        It '実値を渡せばコマンドに埋め込まれる（doctor 用の経路）' {
            $finding = InModuleScope Taskctl {
                Resolve-TaskctlResultCode -Code '0x1' -Locale 'ja' -Values @{ command = 'C:\app\run.exe --daily' }
            }
            $finding.Next | Should -Match 'C:\\app\\run\.exe --daily'
            $finding.Next | Should -Not -Match '<COMMAND>'
        }

        It '実値が無ければ <COMMAND> / <TASKNAME> で埋める（空文字を出さない）' {
            # explain 単体はタスクを知らない。空にせず、入れるべき場所を示す。
            $out = Invoke-TaskctlExplain '0x1' -Lang ja
            $out | Should -Match '<COMMAND>'
            (Invoke-TaskctlExplain '0x41302' -Lang ja) | Should -Match "Enable-ScheduledTask -TaskName '<TASKNAME>'"
        }

        It 'コマンドの値は単一引用符で囲む（名前に $ や ` が入っても壊れない）' {
            # 二重引用符だと "$(...)" がコピペ実行時に評価される。
            $out = Invoke-TaskctlExplain '0x41302' -Lang ja
            $out | Should -Not -Match 'Enable-ScheduledTask -TaskName "'
        }

        It '1行に複数のプレースホルダがあっても全部展開する' {
            # 以前は正規表現を行頭アンカーにしていたため、1パスで行あたり1個しか
            # 置換できず、多段展開の回数（既定5）を超えると残った。
            $r = InModuleScope Taskctl {
                $cat = Get-TaskctlCatalog -Locale ja
                Expand-TaskctlPlaceholder -Text '{{a}} {{b}} {{c}} {{d}} {{e}} {{f}} {{g}}' `
                    -Catalog $cat -Values @{ a = 1; b = 2; c = 3; d = 4; e = 5; f = 6; g = 7 }
            }
            $r | Should -Be '1 2 3 4 5 6 7'
        }

        It '未定義のプレースホルダは原文のまま残す（空文字にしない）' {
            $r = InModuleScope Taskctl {
                $cat = Get-TaskctlCatalog -Locale ja
                Expand-TaskctlPlaceholder -Text 'x {{nope}} y' -Catalog $cat -Values @{}
            }
            $r | Should -Be 'x {{nope}} y'
        }

        It '複数行の値は差し込み先のインデントへ揃える' {
            # 揃えないとコマンドが左端に落ち、コピペ範囲が読み取れなくなる
            $out = Invoke-TaskctlExplain '0x41306' -Lang ja
            $lines = @($out -split "`n" | Where-Object { $_ -match 'Get-WinEvent|Where-Object' })
            $lines.Count | Should -Be 2
            foreach ($l in $lines) { $l | Should -Match '^\s{4,}\S' }
        }

        It '失敗しないコードには cause セクションを出さない' {
            $out = Invoke-TaskctlExplain '0x0' -Lang ja
            $out | Should -Not -Match '考えられる原因'
        }
    }

    Context '符号付き int32（LastTaskResult の実際の返り値）' {
        It '-2147024891 を 0x80070005 として解決する' {
            $out = Invoke-TaskctlExplain '-2147024891' -Lang en
            $out | Should -Match '0x80070005'
            $out | Should -Match 'E_ACCESSDENIED'
        }

        It '負値のとき符号付き10進も併記する' {
            $out = Invoke-TaskctlExplain '0x80070005' -Lang en
            $out | Should -Match '2147942405'      # 符号なし
            $out | Should -Match '-2147024891'     # 符号付き
        }
    }

    Context 'フォールバック（表に無いコード。断定しない）' {
        It '0x8007xxxx は Win32 エラーとして net helpmsg を案内する' {
            $out = Invoke-TaskctlExplain '0x80070002' -Lang ja
            $out | Should -Match 'net helpmsg 2'       # 下位16bit を10進で注入
            $out | Should -Match 'HRESULT_FROM_WIN32\(2\)'
        }

        It '未知のコードは「不明」とし、16進と10進を示す' {
            $out = Invoke-TaskctlExplain '0x63' -Lang ja
            $out | Should -Match '0x00000063'
            $out | Should -Match '99'
            $out | Should -Match '翻訳表に無い'
        }

        It '未知のコードでも空文字を出さない（全セクションが埋まる）' {
            foreach ($lang in 'ja', 'en') {
                $j = Invoke-TaskctlExplain '0x63' -Lang $lang -Json | ConvertFrom-Json
                $j.message | Should -Not -BeNullOrEmpty
                $j.cause | Should -Not -BeNullOrEmpty
                $j.action | Should -Not -BeNullOrEmpty
            }
        }

        It '未知の非ゼロコードは失敗として扱い、severity / rank も失敗に整合させる' {
            # 意味を断定しないことと、失敗を隠すことは別。
            # notice/info にすると doctor の詳細に出ず終了コードも 0 になり、
            # 「未知の失敗を緑で返す」ことになる。
            foreach ($code in '0x63', '0x00002EE7', '0x8004EE04', '0x40010004') {
                $j = Invoke-TaskctlExplain $code -Lang ja -Json | ConvertFrom-Json
                $j.is_failure | Should -BeTrue -Because "$code は非ゼロ"
                $j.severity | Should -Be 'warning' -Because "$code は未知の失敗"
                $j.rank | Should -Be 'investigate' -Because "$code は断定できないので調査"
                $j.known | Should -BeFalse
            }
        }

        It '未知コードの表示ランクが「調査」になる（本文と見出しが矛盾しない）' {
            $out = Invoke-TaskctlExplain '0x63' -Lang ja
            $out | Should -Match '次の一手 \[調査\]'
            $out | Should -Not -Match '次の一手 \[情報\]'
        }

        It '0x8007xxxx フォールバックも warning / investigate' {
            $j = Invoke-TaskctlExplain '0x80070002' -Lang ja -Json | ConvertFrom-Json
            $j.is_failure | Should -BeTrue
            $j.severity | Should -Be 'warning'
            $j.rank | Should -Be 'investigate'
        }
    }

    Context '--json（機械可読の契約）' {
        BeforeAll { $script:j = Invoke-TaskctlExplain '0x2' -Lang ja -Json | ConvertFrom-Json }

        It 'VISION §5 の言語非依存フィールドをすべて含む' {
            foreach ($f in 'code', 'constant', 'kind', 'severity', 'is_failure', 'message_key') {
                $j.PSObject.Properties.Name | Should -Contain $f
            }
        }

        It '現在ロケールの message / action を含む' {
            $j.locale | Should -Be 'ja'
            $j.message | Should -Not -BeNullOrEmpty
            $j.action | Should -Not -BeNullOrEmpty
        }

        It '言語非依存フィールドはロケールを変えても不変' {
            $en = Invoke-TaskctlExplain '0x2' -Lang en -Json | ConvertFrom-Json
            foreach ($f in 'code', 'constant', 'kind', 'severity', 'is_failure', 'rank', 'message_key') {
                $en.$f | Should -Be $j.$f -Because "$f は言語非依存"
            }
            $en.message | Should -Not -Be $j.message
        }

        It '妥当な JSON であり、日本語が壊れていない' {
            $j.message | Should -Match '見つからない'
        }

        It 'message_key で自前ローカライズできる（キーはコード値）' {
            $j.message_key | Should -Be '0x00000002'
        }
    }

    Context '不正な入力' {
        It '解釈できないコードは分かりやすく throw する' {
            { Invoke-TaskctlExplain 'あいうえお' -Lang ja } | Should -Throw '*結果コードとして解釈できません*'
        }
    }
}

Describe 'taskctl ディスパッチャ' {
    It 'explain サブコマンドを --lang 付きで解釈する' {
        $out = taskctl explain 0x41303 --lang en
        $out | Should -Match 'SCHED_S_TASK_HAS_NOT_RUN'
        $out | Should -Match 'What this is'
    }

    It '--lang=ja 形式も解釈する' {
        taskctl explain 0x41303 --lang=ja | Should -Match 'これは何'
    }

    It '--json を解釈する' {
        $out = taskctl explain 0x41303 --lang en --json
        { $out | ConvertFrom-Json } | Should -Not -Throw
    }

    It '負値のコードをフラグと誤認しない' {
        taskctl explain -2147024891 --lang en | Should -Match '0x80070005'
    }

    It '引数なし / --help で使い方を表示する' {
        taskctl | Should -Match 'taskctl doctor'
        taskctl --help | Should -Match 'taskctl explain'
    }

    It '不明なコマンド / フラグは使い方を添えて throw する' {
        { taskctl bogus } | Should -Throw '*不明なコマンド*'
        { taskctl explain 0x2 --bogus } | Should -Throw '*不明なフラグ*'
    }

    It '--lang に値が無ければ throw する' {
        { taskctl explain 0x2 --lang } | Should -Throw '*--lang には言語*'
    }

    It 'explain にコードが無ければ throw する' {
        { taskctl explain } | Should -Throw '*結果コードを指定*'
    }
}
