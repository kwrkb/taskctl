# LESSONS.md

ユーザーからの修正・開発で得た教訓の記録。

## PowerShell: `Input` は Pester の `-ForEach` キーに使えない

`$input` は PowerShell の自動変数。`-ForEach @(@{ Input = '0x2'; ... })` と書くと `$Input` は
常に空になり、**「不正な入力は throw する」系のテストが空振りでパスする**（偽の合格）。

- **ルール**: テストデータのキー名に `Input` / `Args` / `Host` / `Error` など自動変数と衝突する名前を使わない。`Raw` / `Text` / `Given` などにする。
- **兆候**: `-ForEach` のテスト名に値が展開されず `@()` と表示されたら、キー名の衝突を疑う。

## PowerShell: uint32 → int32 のキャストは折り返さずオーバーフローする

`[int32] [uint32] 2147942405` は C 系のようにラップせず `OverflowException` を投げる。
符号付き32bit へ折り返すには自前で計算する:

```powershell
[int64] $signed = if ($unsigned -gt 2147483647L) { $unsigned - 4294967296L } else { $unsigned }
```

- **背景**: `LastTaskResult` は符号付き int32 で返るため、`0x80070005` 等の変換は必ず通る経路。
- **関連**: `[int]` は `0x80000000` 以上のパースでもオーバーフローする。パースは `[int64]` で行う。
