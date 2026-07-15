# taskctl

Windows タスクスケジューラで **タスクが失敗した / 失敗しそうな理由を特定し、「次に何をやればいいか」を具体的に示す** 診断ツール。

設定は自分では変更しません（read-only）。出力は**日本語・英語**に対応します。

> English speakers: everything below works with `--lang en`. See [Usage](#使い方).

## 何をするツールか

タスクスケジューラで「何が悪いか」を出す手段は既にあります。ですが **「だから次にこれをやれ」まで言ってくれるものがありません。**

- 最終結果は `0x41303` のような生コードで表示され、意味は自分で調べることになる
- しかもそのコードが「プログラムの終了コード」なのか「タスクスケジューラの状態コード」なのか区別されない
- 相対パス・作業ディレクトリ未設定・プロファイル依存といった「失敗しやすい設定」を事前に指摘してくれない

taskctl はこの **翻訳と次アクションの提示** だけをやります。

```console
$ taskctl explain 0x41303
0x00041303 (267011)  [SCHED_S_TASK_HAS_NOT_RUN]
  (状態コード)

これは何:
  まだ一度も実行されていない、という状態コード。失敗ではない。

次の一手 [判断]:
  登録直後なら正常。実行されるはずなのに残るなら、トリガーと有効/無効を確認。
```

### やらないこと

一覧・登録・有効化・手動実行・履歴取得は、標準の `Get-ScheduledTask` / `Register-ScheduledTask` /
`Enable-ScheduledTask` / `Get-WinEvent` で足ります。車輪を再発明しません。

`apply` / `plan` / `write` 全般、COM 実装、GUI、config-as-code デプロイ、複数 PC 集中管理も対象外です。

## インストール

```powershell
git clone https://github.com/kwrkb/taskctl.git
cd taskctl

# データ (YAML) を実行時形式 (JSON) へ変換してモジュールへ同梱する
.\build\Convert-DataToJson.ps1

Import-Module .\src\Taskctl\Taskctl.psd1
```

**動作要件**: Windows / PowerShell 7 を推奨（5.1 でも動きますが、日本語表示が化ける場合は
`chcp 65001` するか `pwsh` を使ってください）。ビルド時のみ `powershell-yaml` が必要で、
未導入なら `Convert-DataToJson.ps1` が自動で入れます。実行時に外部依存はありません。

## 使い方

```
taskctl doctor              # 全ユーザータスクを走査。状態一覧＋問題のあるものに診断
taskctl doctor <task>       # 1本を深掘り
taskctl explain <code>      # 結果コード単体を翻訳（例: taskctl explain 0x41303）

共通フラグ:
  --lang ja|en   表示言語（既定は環境/OSから決定、最終フォールバックは en）
  --json         構造化出力（常に UTF-8）
  --verbose      生の設定も表示
```

`explain` は 16進 (`0x41303`) / 10進 (`267011`) / 符号付き10進 (`-2147024891`) のいずれも受け付けます。
`LastTaskResult` は符号付き 32bit で返るため、そのまま貼り付けて構いません。

PowerShell 流に呼びたい場合は `Invoke-TaskctlDoctor` / `Invoke-TaskctlExplain` を直接使えます
（`taskctl doctor --lang en` ≡ `Invoke-TaskctlDoctor -Lang en`）。

### doctor の出力例

```console
$ taskctl doctor
走査 47 タスク: error 0 / warning 6 / notice 72

=== \OmenInstallMonitor  (Ready) ===
  0x00000002 (2)  [ERROR_FILE_NOT_FOUND]
    (システムエラー)

  これは何:
    実行しようとしたファイルが見つからない。プログラムの終了コードではない。

  考えられる原因:
    操作のパスが存在しない、またはタスク実行時の文脈（別ユーザー
    マップドライブ）から解決できない。

  次の一手 [調査]:
    パスがタスクの実行ユーザー文脈で解決できるか確認する。
    ...
```

走査時は **warning 以上のタスクだけ** 詳細を出します（notice だけのタスクは一覧にのみ表示）。
1本を深掘りすると notice も含めてすべて出ます。`--json` には常に全所見が載ります。

### 自動化に乗せる

終了コードは `0` 問題なし / `2` 警告あり / `3` 重大な問題あり です。

```powershell
Import-Module .\src\Taskctl\Taskctl.psd1
Invoke-TaskctlDoctor -Lang en
exit (Get-TaskctlExitCode)
```

`--json` の `exit_code` フィールドにも同じ値が入ります。

```powershell
$report = taskctl doctor --json | ConvertFrom-Json
$report.tasks | Where-Object { $_.last_result.is_failure } |
    ForEach-Object { "$($_.task): $($_.last_result.constant)" }
```

`notice`（＝「仕様かもしれない」もの）は終了コード 0 に数えます。仕様通知で CI を赤くしないためです。

## 設計の考え方

### 次の一手は、確信度でランク分けする

外れた次アクションは、何も言わないより有害です。断定できる時だけ断定します。

| ランク | 意味 | 出すもの |
|---|---|---|
| **修正** (fix) | 原因がほぼ確定 | コピペできる標準コマンド |
| **調査** (investigate) | 断定できない | 真因を掴むための情報収集コマンド |
| **判断** (decide) | 仕様かもしれない | 「これは意図通りか？」という問い |
| **情報** (info) | 失敗ではない | 対応不要 |

そして **自動では直しません。** doctor はコマンドを *見せる* だけで、実行するのはあなたです。

### 誤検知への規律

- **文脈差を前提にする。** taskctl が動く文脈と、タスクが実際に走る文脈（別ユーザー・マップドライブ・別プロファイル）は違います。ファイル存在チェックはこの差で誤爆しうるため、`error` にせず「調査」として提示します。
- 相対パス検出などのヒューリスティックは `warning` 止まり。「修正」コマンドは出しません。
- 実際、**v1 の検出ルールに `rank: fix` は1つもありません**（テストで担保しています）。

### データ資産と i18n

ツールの本体は「翻訳表＋検出ルール＋メッセージカタログ」という言語非依存の資産です。

| ファイル | 中身 |
|---|---|
| `data/registry.yaml` | コードについての**事実**（`code → constant / kind / severity / is_failure / next_rank`） |
| `data/rules.yaml` | 検出ルール（宣言的。`when` は AND 条件） |
| `data/messages/ja.yaml`, `en.yaml` | **その言い方**（`meaning` / `cause` / `next`） |

**翻訳されるのはプロース層だけ** です。コマンド・定数名（`SCHED_S_TASK_READY`）・コード値・
`kind` / `severity` などの機械識別子は翻訳しません。翻訳すると、コマンドは動かなくなり、
ログは grep できなくなるためです。

この境界はテストで機械的に守っています（キー集合の一致、snippets のコマンド行が日英で同一、など）。

提示するコマンドは `{{task}}` / `{{command}}` のプレースホルダを持ち、`doctor` が実際の
タスク名とコマンドを埋めます。そのままコピペして動きます。

```console
$ taskctl doctor MyBackup
...
次の一手 [調査]:
  操作のコマンドをタスクを介さず直接実行して、アプリ側のエラーを確認:
    # 操作(Action)のコマンドを、タスクを介さず手元で直接実行して切り分ける
    powershell.exe -File Z:\scripts\backup.ps1     <- 実際のコマンドが入る
```

`explain <code>` 単体はタスクを知らないため、`<COMMAND>` / `<TASKNAME>` と表示します
（空欄にはしません）。

### 翻訳表の正確性

コードの意味は記憶で埋めず、**Microsoft の一次資料で検証済みのものだけ**を載せています
（出典は `data/registry.yaml` の冒頭に記載）。表に無いコードは推測せず、`0x8007xxxx` なら
`net helpmsg` を案内し、それ以外は「不明」と明示して16進・10進を併記します。

## 開発

```powershell
.\build\Convert-DataToJson.ps1   # data/*.yaml -> src/Taskctl/data/*.json
Invoke-Pester -Path tests        # Pester 5+ が必要
```

診断ルールは正規化モデル上の純粋関数なので、`tests/fixtures/*.xml` を使えば
**Windows 実機のタスク登録なしに**テストできます。

- 翻訳表にコードを足す: `data/registry.yaml`（事実）と `data/messages/*.yaml`（プロース）の両方。一次資料での検証は必須。coverage テストがキーの欠落を検出します。
- 検出ルールを足す: `data/rules.yaml` にルール、`Get-TaskctlFact` にファクト、カタログにプロース。判定ロジックはコードに散らさず、ファクト算出へ集約してください。

## ライセンス

未定。
