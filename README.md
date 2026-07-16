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

## 実装は2つある

taskctl には PowerShell モジュール版（v1、安定）と、C# 単一 exe 版（v2、プレビュー）があります。
どちらも同じデータ資産（翻訳表・検出ルール・日英カタログ）を共有し、`explain` / `doctor` の
挙動は同一です（実機での突き合わせ済み）。使い方は共通、違いは配布形態と実行環境だけです。

| | v1 (PowerShell) | v2 (C# / .NET) |
|---|---|---|
| 状態 | 安定（v1.1） | プレビュー（2.0.0-alpha1） |
| 配布形態 | モジュール（`.ps1` 一式） | 単一 exe（NativeAOT） |
| 実行環境 | PowerShell 5.1 / 7 | 単体で動作。取得層のみ内部で `powershell`/`pwsh` を呼ぶ |
| ビルド | データ変換のみ（`Convert-DataToJson.ps1`） | .NET SDK でコンパイル要 |

迷ったら v1 を使ってください。v2 は配布のしやすさ（単一 exe）を検証中の段階です。

## インストール（v1・PowerShell）

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

## インストール（v2・C#）

```powershell
git clone https://github.com/kwrkb/taskctl.git
cd taskctl\src\Taskctl.Cli

dotnet publish -c Release
# -> bin\Release\net10.0-windows10.0.17763.0\win-x64\publish\taskctl.exe
```

生成された `taskctl.exe` を `PATH` の通った場所に置くだけで使えます（単一 exe、外部依存なし）。

**動作要件**: .NET 10 SDK（ビルド時のみ）、NativeAOT のリンクに MSVC ビルドツール
（Visual Studio Build Tools の「C++ によるデスクトップ開発」ワークロード）が必要です。
実行時の要件は PowerShell（5.1 or 7、`Export-ScheduledTask` / `Get-ScheduledTaskInfo` の
取得に内部で使用）のみで、.NET ランタイムのインストールは不要です（AOT 単一バイナリのため）。

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

`doctor <task>` のタスク指定は、名前 (`MyBackup`)、フォルダ付き (`\Foo\MyBackup`)、
ワイルドカード (`Omen*` — 一致した全部を深掘り) が使えます。

PowerShell 流に呼びたい場合は `Invoke-TaskctlDoctor` / `Invoke-TaskctlExplain` を直接使えます
（`taskctl doctor --lang en` ≡ `Invoke-TaskctlDoctor -Lang en`）。v1 の `taskctl` 関数と v2 の
`taskctl.exe` はコマンド形が同一です（`taskctl doctor --lang en --json` はどちらでも同じ出力）。

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
一方、**設定を読めなかったタスクがあると終了コード 2** になります（`summary.acquire_errors`）。
診断できなかったことを「問題なし」とは報告しません。

#### JSON をファイルに保存する場合

`--json` が返すのは文字列で、ファイルのエンコーディングは受け取り側が決めます。
PowerShell 7 は既定が UTF-8 なので `taskctl doctor --json > report.json` で UTF-8 になりますが、
**Windows PowerShell 5.1 の `>` / `Out-File` は既定が UTF-16LE** です。5.1 で UTF-8 にするには:

```powershell
taskctl doctor --json | Out-File report.json -Encoding utf8   # 5.1 では BOM 付き UTF-8
# BOM なしにするなら:
[IO.File]::WriteAllText('report.json', (taskctl doctor --json), [Text.UTF8Encoding]::new($false))
```

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

### v1 (PowerShell)

```powershell
.\build\Convert-DataToJson.ps1   # data/*.yaml -> src/Taskctl/data/*.json
Invoke-Pester -Path tests        # Pester 5+ が必要
```

診断ルールは正規化モデル上の純粋関数なので、`tests/fixtures/*.xml` を使えば
**Windows 実機のタスク登録なしに**テストできます。

- 翻訳表にコードを足す: `data/registry.yaml`（事実）と `data/messages/*.yaml`（プロース）の両方。一次資料での検証は必須。coverage テストがキーの欠落を検出します。
- 検出ルールを足す: `data/rules.yaml` にルール、`Get-TaskctlFact` にファクト、カタログにプロース。判定ロジックはコードに散らさず、ファクト算出へ集約してください。

### v2 (C#)

```powershell
.\build\Convert-DataToJson.ps1                       # v1 と同じ JSON を v2 も埋め込んで使う
dotnet test .\tests\Taskctl.Cli.Tests\                # xUnit（実機不要、1秒未満）
dotnet build .\src\Taskctl.Cli\ -p:PublishAot=false   # 開発時は AOT を切って高速ビルド
```

`ITaskAcquirer` を差し替えれば取得層をモックでき、`tests/fixtures/*.xml` を v1 と共有します
（翻訳表・検出ルールを足す手順は v1 と同じ。データ資産は両実装で共通）。

コード構成は `src/Taskctl.Cli/{Codes,Findings,Model,Rules,Facts,Doctor,Acquisition,Cli,I18n,Data}/`
で、取得層（`Acquisition/`）だけが実機依存です。それ以外は正規化モデル上の純粋関数です。

## ライセンス

未定。
