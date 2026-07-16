# PLAN.md — taskctl v1 (PowerShell モジュール)

VISION.md に基づく v1 実装計画。**「結果コードの翻訳」「設定ミスの検出」「次アクションの提示」の3点のみ**を作る。read-only を貫き、自動修正はしない。

---

## 現状の把握（2026-07-15 時点）

- 存在するもの: `VISION.md` / `result-codes.yaml`（38 コード。meta / ranks / kinds / snippets / codes 構造。Microsoft Learn 検証済み）
- 存在しないもの: コード一式、テスト、git リポジトリ、ja/en カタログ分離
- `result-codes.yaml` は現状「事実」と「日本語プロース」が同居 → **最初のリファクタ対象**（VISION 記載どおり）

---

## 設計上の決定事項

| 項目 | 決定 | 理由 |
|---|---|---|
| 実装言語 | PowerShell モジュール（v1） | VISION どおり。価値の本体に最短で触れる |
| データ形式 | YAML を正本とし、ビルド時に JSON へ変換してモジュールに同梱 | 実行時に `powershell-yaml` 依存を持ち込まない。JSON なら `ConvertFrom-Json` 標準で読め、将来の C# 版もそのまま読める |
| PowerShell バージョン | PowerShell 7 を第一対象。5.1 は「動けば良い」レベル（文字化け時は chcp 65001 / PS7 を案内） | UTF-8 既定・エンコーディングの罠を最小化 |
| テスト | Pester v5。診断ルールは正規化モデル上の純粋関数にし、実タスク XML を fixture 化 | Windows 実機のタスク登録なしでテスト可能 |
| リポジトリ | `gh repo create kwrkb/taskctl --private` | グローバル設定どおり |

---

## ディレクトリ構成（目標）

```
taskctl/
├── data/                      # 言語非依存の資産（C# 版へそのまま移植可能）
│   ├── registry.yaml          # code → constant / kind / severity / is_failure（事実のみ）
│   ├── rules.yaml             # 宣言的な検出ルール
│   └── messages/
│       ├── ja.yaml            # code/rule → meaning, cause, next.text
│       └── en.yaml
├── src/Taskctl/               # PowerShell モジュール本体
│   ├── Taskctl.psd1
│   ├── Taskctl.psm1
│   ├── Public/                # Invoke-TaskctlDoctor, Invoke-TaskctlExplain（+ taskctl エントリ）
│   └── Private/               # 取得層 / 正規化 / lookup / i18n / レンダリング
├── tests/
│   ├── fixtures/              # Export-ScheduledTask の実 XML サンプル
│   └── *.Tests.ps1
├── build/                     # YAML → JSON 変換スクリプト
├── VISION.md
└── PLAN.md
```

---

## フェーズ計画

### Phase 0: 足場づくり ✅ (2026-07-15)

- [x] `git init` + `.gitignore` + 初回コミット（VISION.md / result-codes.yaml / PLAN.md）
- [x] `gh repo create kwrkb/taskctl --private` + push → https://github.com/kwrkb/taskctl
- [x] ディレクトリ骨格と空モジュール（`Import-Module` が通るだけの状態）
- [x] Pester 実行環境の確認（Pester **6.0.0** を CurrentUser にインストール。v5 系互換構文で記述）

### Phase 1: データ資産の分離（i18n 最初のリファクタ）✅ (2026-07-15)

- [x] `result-codes.yaml` → `data/registry.yaml`（言語非依存の事実）+ `data/messages/ja.yaml` に分割（分割後、元ファイルは削除）
- [x] `data/messages/en.yaml` を作成（38 コード分を英訳。コマンド・定数名・コード値は翻訳しない）
- [x] `build/Convert-DataToJson.ps1`: YAML → JSON 変換（powershell-yaml はビルド時のみの依存）
- [x] coverage テスト: **レジストリのキー集合 = ja のキー集合 = en のキー集合** を担保（+ 定義域チェック、snippets コマンド行の日英同一性、空文字禁止）
- [ ] fallback テスト: 未対応ロケール → en → **Phase 2 のロケール解決の実装と合わせて行う**（データ側の空文字禁止は担保済み）

### Phase 2: `taskctl explain <code>` — 最小の縦切り ✅ (2026-07-15)

翻訳表を最初にエンドツーエンドで通す。doctor より先にここで i18n・正規化・JSON 出力の骨格を固める。

- [x] コード正規化: 符号付き int32 / 10進 / `0x` 表記 → uint32 hex 8桁 key（単体テスト 31 件）
- [x] lookup + 不明コード処理（3段: 完全一致 → `0x8007xxxx` → 不明。断定しない）
- [x] ロケール決定: `--lang` > `TASKCTL_LANG` > `$PSUICulture` > `en`
- [x] 出力レンダリング: 「これは何 / 考えられる原因 / 次の一手 [ランク]」の3点セット
- [x] `--json`: 常に UTF-8。言語非依存フィールド + 現在ロケールの message / action
- [x] 出力エンコーディング対処（PS5.1 で化ける場合の案内文）

### Phase 3: 取得層と正規化モデル ✅ (2026-07-15)

- [x] 取得層インターフェース: `Export-ScheduledTask`（XML）+ `Get-ScheduledTaskInfo` の相関取得
- [x] XML → 正規化モデル（Action / Trigger / Settings / Principal）。既定名前空間を名前空間マネージャで解決
- [x] fixture を **手書き**で用意（実タスクを登録せず済む。normal / relative-path / network-drive / logon-only / no-trigger-disabled）
- [x] fixture ベースのパーステスト 19 件（実機タスク登録なしで動く）

### Phase 4: `taskctl doctor` — 結果コード翻訳の統合 ✅ (2026-07-15)

- [x] `taskctl doctor <task>`: 1タスク深掘り。LastTaskResult を翻訳し3点セットで表示
- [x] `taskctl doctor`: 全タスク走査。状態一覧 + warning 以上のみ診断表示（notice は一覧のみ。`--json` には全載せ）
- [x] 終了コード: `0` 問題なし / `2` 警告あり / `3` 重大な問題あり（`Get-TaskctlExitCode` / JSON の `exit_code`）
- [x] `--verbose`（生の設定）/ `--json` 対応
- [ ] Operational ログが無効な場合の案内 → **v1 では見送り**。ログ取得は v1 の入力に含めなかったため（下記「スコープの変更」参照）

### Phase 5: 検出ルール（設定ミスの検出）✅ (2026-07-15)

`data/rules.yaml`（宣言的ルール 20 件）+ 小さな評価器。判定は `Get-TaskctlFact` の1箇所、プロースはカタログ。

- [x] ルール評価器: 正規化モデル → 所見リストの純粋関数（when は AND、演算子は eq/gte/lte のみ）
- [x] 初期ルール（すべて ja/en メッセージと確信度ランク付き）:
  - [x] 実行ファイル / 作業ディレクトリの不在（**文脈差があるため Error にしない → 調査**）
  - [x] 作業ディレクトリ未設定 + 相対パス（Warning / 調査）
  - [x] ネットワークドライブ・UNC・プロファイル依存パス（Warning / 調査）
  - [x] PowerShell の起動指定不備 / スクリプト直接指定（Warning / 調査）
  - [x] ログオン中のみ / AC 電源時のみ / アイドル時のみ / ネットワーク時のみ（Notice / 判断）
  - [x] 実行時間制限が短い / 多重起動許可 / タスク無効 / トリガー無し / 次回実行なし / 長期間未実行 / 期限切れ
- [x] 誤検知規律のテスト: **v1 のルールに `rank: fix` が1つも無い**ことを機械的に担保

### Phase 6: 仕上げ ✅ (2026-07-15)

- [x] `--verbose`（生の設定表示）を実装
- [x] README（インストール・使い方・設計の考え方）。クリーンな clone で手順を実証
- [x] モジュールマニフェスト整備とバージョニング（v1.0.0）
- [x] LESSONS.md / implementation-notes.md の整理
- [ ] （任意）PSGallery 公開 → **v1 では見送り**。ライセンス未定のため。git clone で使える

---

## スコープ外（やらないことの再確認）

apply / write 全般、COM 実装、GUI、常駐、config-as-code、複数 PC 管理、Windows 以外。
`Get-/Register-/Enable-/Start-ScheduledTask` で足りる操作は再発明しない。

## v1.1: 翻訳表の拡充（完了 / PR）

ブランチ `feature/v1.1-result-codes` → PR。

実機 241 タスク（Microsoft 標準含む）の走査で、翻訳表に無いまま出現した結果コード 12 件を
洗い出し、**Microsoft Learn の一次資料で検証**した。

判断基準:
- 一次資料で定数名と意味を確認できる
- かつ、タスクスケジューラの文脈で意味のある「次の一手」を書ける
- かつ、kind の定義域（status / sched_error / system / app）に無理なく収まる
- どれか欠ければ**載せない**（fallback に任せる＝それが正しい扱い）

**結果: 6 件を追加、6 件は fallback に残した。**

### 追加した 6 件（`source:` に検証した URL を持つ）

| コード | 定数 | 出現したタスク |
|---|---|---|
| `0x800710E0` | `HRESULT_FROM_WIN32(ERROR_REQUEST_REFUSED)` | DiskCleanup\SilentCleanup, MemoryDiagnostic\ProcessMemoryDiagnosticEvents |
| `0x80070002` | `HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND)` | SystemOptimizerTemp, Location\Notifications |
| `0x80070032` | `HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED)` | Setup\PITRTask |
| `0x800700B7` | `HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)` | Shell\ThemesSyncedImageDownload |
| `0x80040111` | `CLASS_E_CLASSNOTAVAILABLE` | MemoryDiagnostic\AutomaticOfflineMemoryDiagnostic |
| `0x80040154` | `REGDB_E_CLASSNOTREG` | DiskFootprint\StorageSense |

COM 系（`0x8004xxxx`）は fallback の `0x8007----` に当たらず**完全な「未知」**だったため、
追加の効果が最も大きい。`0x8007xxxx` 系は fallback でも `net helpmsg <N>` に誘導できていたので、
意味をその場で出せるようになった分の改善（severity / rank は fallback と同じまま＝断定を増やさない）。

### 載せなかった 7 件と理由

| コード | 理由 |
|---|---|
| `0x40010004` (`DBG_TERMINATE_PROCESS`) | 一次資料で確認できたが **NTSTATUS** で kind の定義域に収まらない。`0x40` は情報severity で is_failure / severity が曖昧。「デバッガが終了させた」から有用な次の一手も書けない。よく言われる「シャットダウンで終了」は一次資料に無い |
| `0x00000420` (`ERROR_SERVICE_ALREADY_RUNNING`) | デコードは確定だが 1056 は小さい整数で、アプリ独自の `exit(1056)` と区別できない |
| `0x00002EE7` (`ERROR_INTERNET_NAME_NOT_RESOLVED`) | WinINet 帯だが、返しているのがサードパーティ製 updater でアプリ終了コードの可能性が同程度に残る |
| `0x10000000` | 一次資料で確認できず |
| `0x8004EE04` | 一次資料で確認できず（facility=4 は FACILITY_ITF＝アプリ定義領域。OneDrive 独自の可能性が高い） |
| `0xFFFFFFF8` | 一次資料で確認できず（HRESULT として解釈しても facility が未定義） |

「一次資料で確認できなかった」「確認できても意味のある案内にならない」ものを載せないのは
**取りこぼしではなく設計判断**。fallback が「未知 / warning / 調査」として正しく扱う
（＝失敗は失敗として報告し、意味だけを断定しない）。

### 担保

- `source:` を持つエントリは `^https://learn\.microsoft\.com/` を指すことをテストで機械検査
- 出典 URL 3 本を実際に開き、6 件すべての定数名と説明文が一字一句一致することを確認
  （テストは URL の形しか見ないため、内容の一致は人が確かめる必要がある）
- 185 テストパス（失敗 0）
- 実機で end-to-end 確認（SilentCleanup / PITRTask / ThemesSyncedImageDownload が実際に翻訳される）
- 載せなかったコードが fallback で「失敗 / 調査」のまま維持されることも確認（隠していない）

### v1 で見送った項目（VISION には挙がっていたもの）

- **Operational ログの参照**: VISION の「入力とデータ源」では *任意* とされていた。v1 では
  設定 XML と実行情報だけで診断が成立したため、取得層に足さなかった。ログは「次の一手 [調査]」
  としてコマンドを提示する形で扱っている（実行はユーザー）。v2 の候補。
- **バッチ / WSL の起動指定不備**: PowerShell とスクリプト直接指定は実装したが、
  バッチ・WSL 固有の不備は具体的な失敗パターンを一次資料で確認できていないため見送り。
  推測でルールを足すと誤検知の元になる（VISION の「確信度に正直」より）。
- **PSGallery 公開**: ライセンス未定のため。

---

## リスクと先回り

- **翻訳表の正確性が信頼の根幹**: 新コード追加は必ず Microsoft 一次資料で検証してから registry に入れる（既存 38 件は検証済み）
- **PS5.1 のエンコーディング**: 深追いしない。検出できたら案内を出すに留め、PS7 を推奨
- **fixture 収集**: 失敗パターンの実 XML が必要。手元でわざと壊したタスクを作って `Export-ScheduledTask` で採取する
- **en カタログの品質**: 機械的な直訳にせず、コマンド非翻訳の境界を coverage テストで機械的に守る

---

## 進捗ログ

- 2026-07-15: PLAN.md 作成。既存資産は VISION.md / result-codes.yaml（38 コード）のみ
- 2026-07-15: Phase 0 完了。git 初期化・GitHub private リポジトリ作成・モジュール骨格・Pester 6 導入（テスト2件パス）。コミット author は `yugosasaki <dev@kwrkb.com>`（開発用の名前。GitHub アカウント名 `kwrkb` とは別で、これが正しい）
- 2026-07-15: `result-codes.yaml` と `VISION.md` の累積インデント破損を発見し、行間差分から機械的に復元（内容行は不変）
- 2026-07-15: Phase 1 完了。registry + ja/en カタログに分割、ビルドスクリプトと coverage テスト 18 件を追加（計 20 テストパス）。ランク ID を言語非依存化（情報/判断/調査/修正 → info/decide/investigate/fix）
- 2026-07-15: Phase 2 完了。explain をエンドツーエンドで実装（83 テストパス）。カタログに `cause` を追加し VISION の3点セットへ揃えた
- 2026-07-15: Phase 3 完了。取得層と正規化モデル、手書き fixture 5 種（102 テストパス）
- 2026-07-15: Phase 4/5 完了。doctor と宣言的ルール 20 件（150 テストパス）。実機 47 タスクで動作確認
- 2026-07-15: **Phase 6 完了 = v1 完成**（155 テストパス）。`--verbose`、README、v1.0.0。クリーンな clone でインストール手順を実証
- 2026-07-15: **v1.0.1** — レビューで見つかった2点を修正（164 テストパス）。未知の非ゼロコードを緑で返していた矛盾（`is_failure=true` なのに notice/info）と、他ユーザーのタスクでの存在チェック誤爆
- 2026-07-16: **v2 実装言語を Go から C#（.NET 10 / NativeAOT）へ変更**。決め手は Windows 専用という前提と、v1 PowerShell が .NET 基盤である継続性。COM interop（`Microsoft.Win32.TaskScheduler` 含む）は NativeAOT 非対応（IL3052）と確認し不採用、取得は PowerShell シェルアウトに統一する方針で VISION.md を更新
- 2026-07-16: **v2 Phase 1 完了**（`src/Taskctl.Cli`）。explain をエンドツーエンドで実装。データ資産（registry/rules/ja/en カタログ）を単一 exe に埋込。AOT publish で 3.1MB の単一 exe を生成し実機で動作確認
- 2026-07-16: **v2 Phase 2 完了**。doctor をエンドツーエンドで実装（取得層・XML 正規化・fact・宣言的ルールエンジン・診断・レポート整形）。実機 69 タスクの走査で PowerShell v1 と完全一致（scanned/errors/warnings/notices/exit_code）を確認
- 2026-07-16: **v2 Phase 3 完了**（`tests/Taskctl.Cli.Tests`）。xUnit 122 テストパス。`ITaskAcquirer` を注入可能にし、実機・PowerShell 起動なしで doctor の統合テストが走る。AOT publish（8.7MB 単一 exe）でも動作確認

## v1 の到達点

VISION の成功条件に対する自己評価:

| 成功条件 | 状態 |
|---|---|
| 失敗コードの意味を数秒で理解できる（状態コードか終了コードかも分かる） | ✅ `explain` / `doctor` が kind を区別して表示 |
| 失敗しやすい設定を、失敗する前に指摘できる | ✅ 20 ルール |
| 提示される「次の一手」が具体的で、外れが少ない | ✅ ランク分け + `fix` ゼロの規律をテストで担保 |
| 日本語でも英語でも自然に読め、コマンドは非翻訳で正しく動く | ✅ coverage テストで境界を機械的に担保 |
| 自動変更しないため、ツールを使ってタスクを壊すことがない | ✅ read-only。書き込み API を一切呼ばない |
| Windows 標準機能と共存し、モジュールを置くだけで使える | ✅ 実行時の外部依存なし |
