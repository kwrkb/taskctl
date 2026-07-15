#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# データ資産の整合性テスト。
# 原則: カタログ (ja/en) のキー集合 = レジストリのキー集合。空文字は絶対に出さない。

Describe 'データ資産の coverage' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        & (Join-Path $repoRoot 'build\Convert-DataToJson.ps1') | Out-Null

        $dataDir = Join-Path $repoRoot 'src\Taskctl\data'
        $script:registry = Get-Content (Join-Path $dataDir 'registry.json') -Raw -Encoding utf8 | ConvertFrom-Json
        $script:catalogs = @{}
        foreach ($f in Get-ChildItem $dataDir -Filter 'messages.*.json') {
            $locale = $f.BaseName -replace '^messages\.', ''
            $script:catalogs[$locale] = Get-Content $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json
        }

        $script:registryKeys = @($registry.codes.key)
    }

    Context 'レジストリ (registry.yaml)' {
        It 'ja と en のカタログが存在する' {
            $catalogs.Keys | Should -Contain 'ja'
            $catalogs.Keys | Should -Contain 'en'
        }

        It 'コードの key に重複がない' {
            ($registryKeys | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
        }

        It 'key は 0x + 大文字16進8桁に正規化されている' {
            foreach ($k in $registryKeys) {
                $k | Should -Match '^0x[0-9A-F]{8}$'
            }
        }

        It 'kind / severity / next_rank が meta の定義域に収まる' {
            foreach ($c in $registry.codes) {
                $registry.meta.kinds | Should -Contain $c.kind
                $registry.meta.severities | Should -Contain $c.severity
                $registry.meta.ranks | Should -Contain $c.next_rank
            }
        }
    }

    Context 'カタログのキー集合 = レジストリのキー集合 (<_>)' -ForEach @('ja', 'en') {
        BeforeAll { $script:cat = $catalogs[$_] }

        It 'codes のキー集合が registry と一致する' {
            $catKeys = @($cat.codes.PSObject.Properties.Name)
            Compare-Object $registryKeys $catKeys | Should -BeNullOrEmpty
        }

        It '全コードに meaning と next があり、空文字が無い' {
            foreach ($k in $registryKeys) {
                $entry = $cat.codes.$k
                $entry.meaning | Should -Not -BeNullOrEmpty -Because "$k の meaning"
                $entry.next | Should -Not -BeNullOrEmpty -Because "$k の next"
            }
        }

        It '失敗コード (is_failure) には cause がある' {
            foreach ($c in ($registry.codes | Where-Object is_failure)) {
                $cat.codes.($c.key).cause | Should -Not -BeNullOrEmpty -Because "$($c.key) は失敗コード"
            }
        }

        It '3点セットの見出し (meaning / cause / next) がある' {
            foreach ($h in 'meaning', 'cause', 'next') {
                $cat.headings.$h | Should -Not -BeNullOrEmpty -Because "heading $h"
            }
        }

        It '全 rank にラベルと説明がある' {
            foreach ($r in $registry.meta.ranks) {
                $cat.ranks.$r.label | Should -Not -BeNullOrEmpty -Because "rank $r"
                $cat.ranks.$r.description | Should -Not -BeNullOrEmpty -Because "rank $r"
            }
        }

        It '全 kind にラベルと説明がある' {
            foreach ($k in $registry.meta.kinds) {
                $cat.kinds.$k.label | Should -Not -BeNullOrEmpty -Because "kind $k"
                $cat.kinds.$k.description | Should -Not -BeNullOrEmpty -Because "kind $k"
            }
        }

        It 'fallback のキー集合が registry と一致し、meaning/cause/next が揃う' {
            $regFallback = @($registry.fallback.PSObject.Properties.Name)
            $catFallback = @($cat.fallback.PSObject.Properties.Name)
            Compare-Object $regFallback $catFallback | Should -BeNullOrEmpty
            foreach ($f in $regFallback) {
                foreach ($field in 'meaning', 'cause', 'next') {
                    $cat.fallback.$f.$field | Should -Not -BeNullOrEmpty -Because "fallback $f の $field"
                }
            }
        }

        It 'メッセージ中のプレースホルダがすべて解決できる' {
            # snippets.<name> はカタログの定型文、それ以外は resolver が値を注入する既知の名前。
            $snippetKeys = @($cat.snippets.PSObject.Properties.Name)
            # resolver が値を注入する既知の名前（未指定なら <TASKNAME> 等の既定で埋まる）
            $valueKeys = @('win32', 'task', 'task_args', 'task_regex', 'command', 'workdir', 'days', 'limit_seconds')
            $texts = foreach ($k in $registryKeys) {
                "$($cat.codes.$k.meaning)`n$($cat.codes.$k.cause)`n$($cat.codes.$k.next)"
            }
            $texts += foreach ($f in $cat.fallback.PSObject.Properties.Name) {
                "$($cat.fallback.$f.meaning)`n$($cat.fallback.$f.cause)`n$($cat.fallback.$f.next)"
            }
            $texts += foreach ($r in $cat.rules.PSObject.Properties.Name) {
                "$($cat.rules.$r.meaning)`n$($cat.rules.$r.cause)`n$($cat.rules.$r.next)"
            }
            $texts += foreach ($s in $snippetKeys) { $cat.snippets.$s }
            foreach ($text in $texts) {
                foreach ($m in [regex]::Matches($text, '\{\{([^}]+)\}\}')) {
                    $ref = $m.Groups[1].Value
                    if ($ref -match '^snippets\.(\w+)$') {
                        $snippetKeys | Should -Contain $Matches[1]
                    }
                    else {
                        $valueKeys | Should -Contain $ref
                    }
                }
            }
        }
    }

    Context 'ロケール間の整合' {
        It 'snippets のキー集合が ja / en で一致する' {
            $ja = @($catalogs['ja'].snippets.PSObject.Properties.Name)
            $en = @($catalogs['en'].snippets.PSObject.Properties.Name)
            Compare-Object $ja $en | Should -BeNullOrEmpty
        }

        It 'snippets のコマンド行（# 以外の行）が ja / en で同一である' {
            foreach ($name in $catalogs['ja'].snippets.PSObject.Properties.Name) {
                $jaCmd = @(($catalogs['ja'].snippets.$name -split "`n") | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
                $enCmd = @(($catalogs['en'].snippets.$name -split "`n") | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
                ($jaCmd -join "`n") | Should -Be ($enCmd -join "`n") -Because "snippet $name のコマンドは非翻訳"
            }
        }
    }
}
