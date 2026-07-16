# CLAUDE.md — taskctl

Windows タスクスケジューラ診断ツール。実装は 2 系統: v2 (C# / NativeAOT 単一 exe / 安定) と v1 (PowerShell モジュール / 安定)。データ資産（翻訳表・検出ルール・日英カタログ）は両者で共通。

## Commands

```powershell
# データ変換（v1/v2 とも先にこれ。tests もこれに依存）
.\build\Convert-DataToJson.ps1

# v2 (C#)
dotnet test tests/Taskctl.Cli.Tests           # xUnit 157件、実機不要
dotnet publish src/Taskctl.Cli -c Release     # NativeAOT 単一 exe

# v1 (PowerShell)
Invoke-Pester -Path tests                     # Pester 5+ 必要、185件
```

CI (`.github/workflows/test.yml`) が push/PR ごとに両方走らせる。

## Immutable rules（触ると壊れる）

- **翻訳表 (`data/registry.yaml`) にコードを追加する時は必ず Microsoft 一次資料で検証**。推測で埋めない。`source:` フィールドに URL 必須。テストで `learn.microsoft.com` を機械検査している。
- **検出ルール (`data/rules.yaml`) に `rank: fix` を入れない**。文脈差で誤爆する。誤検知規律テスト (`Rules.Tests.ps1` / `RulesTests.cs`) が機械的に禁止している。

## Where to look

- `VISION.md` — 何を作るか / 作らないか
- `PLAN.md` — 進捗ログ（v1 / v2 の Phase 単位）
- `LESSONS.md` — 過去にハマった罠（読むだけで数時間節約できる）
- `implementation-notes.md` — 判断ログ

## Gotchas

- `data/messages/*.yaml` のプロース以外（コマンド・定数名・kind/severity 等）は絶対に翻訳しない。テストで日英同一を機械検査している。
- 取得層 (`Acquisition/`) だけが実機依存。それ以外は正規化モデル上の純粋関数として書く。
- 静的な遅延キャッシュは xUnit 並列で race する（`DataStore` で実際に発生済み。ConcurrentDictionary を使う）。
