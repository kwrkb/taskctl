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
| データ形式 | YAML を正本とし、ビルド時に JSON へ変換してモジュールに同梱 | 実行時に `powershell-yaml` 依存を持ち込まない。JSON なら `ConvertFrom-Json` 標準で読め、将来の Go 版もそのまま読める |
| PowerShell バージョン | PowerShell 7 を第一対象。5.1 は「動けば良い」レベル（文字化け時は chcp 65001 / PS7 を案内） | UTF-8 既定・エンコーディングの罠を最小化 |
| テスト | Pester v5。診断ルールは正規化モデル上の純粋関数にし、実タスク XML を fixture 化 | Windows 実機のタスク登録なしでテスト可能 |
| リポジトリ | `gh repo create kwrkb/taskctl --private` | グローバル設定どおり |

---

## ディレクトリ構成（目標）

```
taskctl/
├── data/                      # 言語非依存の資産（Go 版へそのまま移植可能）
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

### Phase 1: データ資産の分離（i18n 最初のリファクタ）

- [ ] `result-codes.yaml` → `data/registry.yaml`（言語非依存の事実）+ `data/messages/ja.yaml` に分割
- [ ] `data/messages/en.yaml` を作成（38 コード分を英訳。コマンド・定数名・コード値は翻訳しない）
- [ ] `build/` に YAML → JSON 変換スクリプト（モジュール同梱用）
- [ ] coverage テスト: **レジストリのキー集合 = ja のキー集合 = en のキー集合** を担保
- [ ] fallback テスト: 未対応ロケール → en、空文字を絶対に出さない

### Phase 2: `taskctl explain <code>` — 最小の縦切り

翻訳表を最初にエンドツーエンドで通す。doctor より先にここで i18n・正規化・JSON 出力の骨格を固める。

- [ ] コード正規化: 符号付き int32 / 10進 / `0x` 表記 → uint32 hex 8桁 key（単体テスト必須）
- [ ] lookup + 不明コード処理（「不明」と明示、16進・10進併記、断定しない）
- [ ] ロケール決定: `--lang` > `TASKCTL_LANG` > `$PSUICulture` > `en`
- [ ] 出力レンダリング: 「これは何 / 考えられる原因 / 次の一手 [ランク]」の3点セット
- [ ] `--json`: 常に UTF-8。言語非依存フィールド（code / constant / kind / severity / is_failure / message_key）+ 現在ロケールの message / action
- [ ] 出力エンコーディング対処（PS5.1 で化ける場合の案内文）

### Phase 3: 取得層と正規化モデル

- [ ] 取得層インターフェース: `Export-ScheduledTask`（XML）+ `Get-ScheduledTaskInfo` の相関取得
- [ ] XML → 正規化モデル（Action / Trigger / Settings / Principal / LastTaskResult 等）
- [ ] 代表的なタスクの実 XML を `tests/fixtures/` に収集（正常系・ネットワークドライブ・相対パス・条件付き等）
- [ ] fixture ベースのパーステスト（実機タスク登録なしで動く）

### Phase 4: `taskctl doctor` — 結果コード翻訳の統合

- [ ] `taskctl doctor <task>`: 1タスク深掘り。LastTaskResult を翻訳し3点セットで表示
- [ ] `taskctl doctor`: 全タスク走査。状態一覧 + 問題のあるものだけ診断（デフォルト出力は短く、問題と次の一手を先頭に）
- [ ] Operational ログが無効な場合の案内（有効化コマンドの提示のみ、実行しない）
- [ ] 終了コード: `0` 問題なし / `2` 警告あり / `3` 重大な問題あり
- [ ] `--verbose` / `--json` 対応

### Phase 5: 検出ルール（設定ミスの検出）

`data/rules.yaml`（宣言的ルール）+ 小さな評価器。判定は1箇所、プロースはカタログ。

- [ ] ルール評価器: 正規化モデル → 所見リストの純粋関数
- [ ] 初期ルール（VISION の候補から。各ルールに ja/en メッセージと確信度ランクを付与）:
  - [ ] 実行ファイル／スクリプト／作業ディレクトリの不在（**文脈差があるため Error にしない → 調査**）
  - [ ] 作業ディレクトリ未設定 + 相対パス（Warning / 調査）
  - [ ] ネットワークドライブ・プロファイル依存パス（Warning / 調査）
  - [ ] PowerShell / バッチ / WSL の起動指定不備
  - [ ] ログオン中のみ / AC 電源時のみ / アイドル時のみ（Notice / 判断 — 「意図通りか？」を問う）
  - [ ] 実行時間制限が短い / 多重起動許可 / タスク無効 / 次回実行なし / 長期間未実行
- [ ] 誤検知規律のテスト: ヒューリスティックが「修正」を出さないことを検証

### Phase 6: 仕上げ

- [ ] README（インストール・使い方・日英）
- [ ] モジュールマニフェスト整備とバージョニング
- [ ] LESSONS.md / implementation-notes.md の整理
- [ ] （任意）PSGallery 公開の検討

---

## スコープ外（やらないことの再確認）

apply / write 全般、COM 実装、GUI、常駐、config-as-code、複数 PC 管理、Windows 以外。
`Get-/Register-/Enable-/Start-ScheduledTask` で足りる操作は再発明しない。

---

## リスクと先回り

- **翻訳表の正確性が信頼の根幹**: 新コード追加は必ず Microsoft 一次資料で検証してから registry に入れる（既存 38 件は検証済み）
- **PS5.1 のエンコーディング**: 深追いしない。検出できたら案内を出すに留め、PS7 を推奨
- **fixture 収集**: 失敗パターンの実 XML が必要。手元でわざと壊したタスクを作って `Export-ScheduledTask` で採取する
- **en カタログの品質**: 機械的な直訳にせず、コマンド非翻訳の境界を coverage テストで機械的に守る

---

## 進捗ログ

- 2026-07-15: PLAN.md 作成。既存資産は VISION.md / result-codes.yaml（38 コード）のみ
- 2026-07-15: Phase 0 完了。git 初期化・GitHub private リポジトリ作成・モジュール骨格・Pester 6 導入（テスト2件パス）。コミット author はリポジトリローカル設定で `kwrkb` に統一（実名の混入防止）
