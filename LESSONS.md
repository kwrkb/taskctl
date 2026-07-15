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

## PowerShell: `switch -regex` は `break` が無いと該当する全ブロックを実行する

`--lang` は `'^--lang$'` にも `'^--'` にも一致するため、両方のブロックが走って
「不明なフラグです」が誤発火した。C 系のような fall-through ではなく、**全マッチ実行**が既定。

- **ルール**: `switch -regex` の各 case には原則 `break` を書く。特に「包括的なパターン」
  （`'^--'` のようなフォールバック）を併記する場合は必須。

## PowerShell: `@($null)` は要素1個の配列（空ではない）

`param([string[]] $Arguments)` に何も渡されないと `$Arguments` は `$null` になり、
`@($Arguments).Count` は **0 ではなく 1** になる。引数なしの分岐がすり抜けた。

- **ルール**: `@($x | Where-Object { $null -ne $_ })` のように空要素を落としてから数える。

## タスクスケジューラの XML は既定名前空間を持つ

`http://schemas.microsoft.com/windows/2004/02/mit/task` が既定名前空間として付く。
`[xml]` に対する XPath は、名前空間マネージャを渡さないと **例外ではなく無言で空** を返す。

```powershell
$ns = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
$ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
$doc.SelectSingleNode('/t:Task/t:Settings/t:Enabled', $ns)
```

- **兆候**: パースは通るのに全フィールドが空。

## データ変換の失敗は、その場で止める

`ConvertFrom-Yaml` が壊れた YAML で失敗しても、そのまま null の JSON を書き出していたため、
実行時に「カタログが null」という原因の分かりにくいエラーになった（Phase 4 で実際に踏んだ）。

- **ルール**: ビルド/変換スクリプトは、出力が空・null なら例外で止める。
  下流で分かりにくく壊れるより、変換時点で失敗させる方が早く直せる。

## テストが「通った」ことと「検証できている」ことは違う

Pester の `-ForEach` で `Input` というキーを使ったところ、自動変数 `$input` と衝突して
値が空になり、**「不正な入力は throw する」テストが空振りでパスしていた**。

- **ルール**: 「throw するはず」のテストを書いたら、**期待した理由で throw しているか**を確認する
  （テスト名に値が展開されているか、失敗メッセージが想定通りか）。
- **関連**: 自動変数と衝突する名前（`Input` / `Args` / `Host` / `Error` / `Matches`）を
  テストデータのキーに使わない。
