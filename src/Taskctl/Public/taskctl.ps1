<#
.SYNOPSIS
    taskctl エントリポイント。VISION の想定コマンド形（POSIX 風フラグ）を受ける。
.DESCRIPTION
    使い方:
      taskctl doctor              # 全ユーザータスクを走査。状態一覧＋問題のあるものに診断
      taskctl doctor <task>       # 1本を深掘り
      taskctl explain <code>      # 結果コード単体を翻訳（例: taskctl explain 0x41303）

    共通フラグ:
      --lang ja|en   表示言語（既定は環境/OSから決定、最終フォールバックは en）
      --json         構造化出力（常に UTF-8）
      --verbose      生の設定も表示

    PowerShell のパラメータバインダは `--lang` 形式を扱えないため、ここで解釈して
    各コマンドの PowerShell 引数へ橋渡しする。-Lang / -Json のような PowerShell 流の
    指定は、各 Invoke-Taskctl* を直接呼べばよい。
.EXAMPLE
    taskctl explain 0x41303 --lang en
#>
function taskctl {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]] $Arguments
    )

    # 引数なしのとき $Arguments は $null。@($null) は要素1個の配列になるため空要素を落とす。
    $argv = @($Arguments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($argv.Count -eq 0 -or $argv[0] -in '--help', '-h', 'help') {
        return Get-TaskctlUsage
    }

    $command = $argv[0]
    $rest = @($argv | Select-Object -Skip 1)

    # 共通フラグを抜き出す。
    # 注意: switch -regex は break が無いと該当する全ブロックを実行する（--lang は ^-- にも一致する）。
    $params = @{}
    $positional = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $rest.Count; $i++) {
        switch -regex ($rest[$i]) {
            '^--lang$' {
                $i++
                if ($i -ge $rest.Count) { throw '--lang には言語を指定してください（例: --lang ja）' }
                $params['Lang'] = $rest[$i]
                break
            }
            '^--lang=(.+)$' { $params['Lang'] = $Matches[1]; break }
            '^--json$' { $params['Json'] = $true; break }
            '^--verbose$' { $params['Verbose'] = $true; break }
            '^(--help|-h)$' { return Get-TaskctlUsage }
            '^--' { throw "不明なフラグです: $($rest[$i])`n`n$(Get-TaskctlUsage)" }
            default { $positional.Add($rest[$i]); break }
        }
    }

    switch ($command) {
        'explain' {
            if ($positional.Count -lt 1) {
                throw "explain には結果コードを指定してください（例: taskctl explain 0x41303）"
            }
            Invoke-TaskctlExplain -Code $positional[0] @params
        }
        'doctor' {
            if ($positional.Count -ge 1) { $params['TaskName'] = $positional[0] }
            Invoke-TaskctlDoctor @params
        }
        default {
            throw "不明なコマンドです: $command`n`n$(Get-TaskctlUsage)"
        }
    }
}

function Get-TaskctlUsage {
    [CmdletBinding()]
    param()

    @'
taskctl - Windows タスクスケジューラの失敗を診断し、次の一手を示す（設定は変更しません）

使い方:
  taskctl doctor              全タスクを走査し、状態一覧と問題のあるタスクの診断を表示
  taskctl doctor <task>       1つのタスクを深掘りして診断
  taskctl explain <code>      結果コード単体を翻訳（例: taskctl explain 0x41303）

共通フラグ:
  --lang ja|en                表示言語（既定: TASKCTL_LANG > OS の UI カルチャ > en）
  --json                      構造化出力（常に UTF-8）
  --verbose                   生の設定も表示

終了コード:
  0  問題なし   2  警告あり   3  重大な問題あり   1  実行エラー
'@
}
