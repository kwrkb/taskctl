# implementation-notes.md

作業中の判断・選択・妥協の記録。

## 2026-07-15 (Phase 0)

- **Pester 6.0.0 を採用**（計画では v5）: `Install-Module -MinimumVersion 5.0` で最新の 6.0.0 が入った。v5 系構文と互換であり、ダウングレードして固定するメリットがないためそのまま採用。テストの `#Requires` は `ModuleVersion 5.0` のままにし、v5/v6 どちらでも動く構文で書く。
- **git author は `yugosasaki <dev@kwrkb.com>` のまま**: 一度リポジトリローカルで `kwrkb` に変更したが、`yugosasaki` は開発用の名前であり元のままが正しいとユーザーから指摘。ローカル上書きを削除し、既存コミットも rebase で author を戻して force push 済み。
- **データの runtime 形式は JSON**（正本は YAML）: 実行時に `powershell-yaml` 依存を持ち込まないため、`build/` で YAML→JSON 変換して同梱する方式。将来の Go 版も同じ JSON を読める。
