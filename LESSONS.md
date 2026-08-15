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

## PowerShell: `-replace` の置換文字列で `$_` は「入力文字列全体」に展開される

`.NET Regex.Replace` の置換パターンでは `$_` が特殊変数（入力文字列全体）。
`$c -replace 'x', "y `$_.Message z"` のつもりで書くと、**ファイル全体がそこに挿入される**（実際に踏んだ）。

- **特殊なもの**: `$&`（マッチ全体）、`$1`（グループ）、`` $` ``（前方）、`$'`（後方）、`$_`（入力全体）、`$$`（リテラルの $）
- **ルール**: 置換文字列に `$` を含めるなら `$$` でエスケープする。
  そもそも**設定ファイルの一括置換に `-replace` を使わない** — Edit ツールで明示的に置換する方が安全。
- **兆候**: 置換後のファイルが不自然に肥大する。

## 二重の基準を作らない（同じ事実を2つのフィールドで判定しない）

`is_failure`（コードが失敗の範囲か）と `severity`（どれだけ気にすべきか）を別々の判定に使っていた:
- 所見を**集める**条件 → `is_failure`
- 集計・表示・終了コード → `severity`

結果、`is_failure:false` かつ `severity:warning` のコード（`SCHED_S_TASK_TERMINATED` =
実行時間超過で強制終了）が集計にも詳細にも出ず、**exit 0 で緑になった**。

- **ルール**: 一連の判断は**単一の基準**で行う。別の軸が必要なら、役割を明確に分ける
  （例: 収集は常に行い、**表示だけ**を severity で絞る）。
- **兆候**: 「A で絞ったものを B で数える」構造。境界で必ず取りこぼす。

## 「調べられなかった」を「問題なし」と報告しない

取得に失敗したタスクを終了コードの集計に含めていなかったため、アクセス拒否で
1件も診断できなくても `exit 0`（問題なし）を返していた。

- **ルール**: 診断ツールの「問題なし」は「調べた上で問題が無かった」を意味する。
  調べられなかったものは、専用のカウントを持たせて非ゼロで返す。

## 「断定しない」と「隠す」を混同しない

未知の結果コードを「断定しないから」と `severity: notice` / `rank: info`（対応不要）に
していたところ、`is_failure = true` なのに doctor の詳細に出ず、終了コードも 0 になっていた。
**未知の失敗を緑で返す**という、診断ツールとして最悪の挙動。

- **ルール**: 確信度が低いことは、**重大度を下げる理由にならない**。
  「何が起きたか（失敗した）」と「なぜ起きたか（不明）」は別の軸。
  分からないなら「分からないので調査せよ」と warning で言う。黙るのではない。
- **兆候**: `is_failure = true` なのに `severity` が notice、のような**内部で矛盾するフラグ**。
  同じ事実を表す複数のフィールドは、どこかで必ず食い違う。1箇所から導出する。

## 自分の権限で調べた結果を、他人の文脈の事実として報告しない

`Test-Path` は taskctl を動かす本人の権限で走る。別ユーザー / SYSTEM のタスクのパスを
チェックすると、「本人に読めないだけ」を「存在しない」と誤検知する。

- **ルール**: 環境を調べるチェックは、**調べている文脈と対象の文脈が一致する時だけ**行う。
  一致しないなら、チェックしない（＝黙る）か、文脈差そのものを所見として提示する。

## フォールバックのテストに「いつか表に載る値」を使わない

fallback 経路（`0x8007xxxx` → `net helpmsg`）の検証に `0x80070002` を使っていた。
v1.1 でこのコードを翻訳表に追加したところ、**完全一致が先に当たって fallback を素通り**し、
テストは fallback を検証しなくなった。今回はアサーションが落ちて気付けたが、
アサーションが緩ければ**黙って検証が消えていた**。

- **ルール**: 「デフォルト経路 / フォールバック」のテストには、**その経路にしか行かない値**を使う。
  値が表側へ移りうるなら、「この値が表に無いこと」を明示的にテストして固定する。
- **同型の罠**: ドキュメントやメッセージ中の例示も同じ。fallback の説明文に
  「例: 0x80070002 なら…」と書いていたため、表に載せた瞬間に嘘になった（例示自体を削除）。
- **兆候**: テストデータが「たまたま今は未対応な値」であること。対応が進むと壊れる／黙る。

## テストが「通った」ことと「検証できている」ことは違う

Pester の `-ForEach` で `Input` というキーを使ったところ、自動変数 `$input` と衝突して
値が空になり、**「不正な入力は throw する」テストが空振りでパスしていた**。

- **ルール**: 「throw するはず」のテストを書いたら、**期待した理由で throw しているか**を確認する
  （テスト名に値が展開されているか、失敗メッセージが想定通りか）。
- **関連**: 自動変数と衝突する名前（`Input` / `Args` / `Host` / `Error` / `Matches`）を
  テストデータのキーに使わない。

## v2 C# 移植のレビュー対応 (2026-07-16)

### PowerShell → C# 移植では比較の case-insensitivity が黙って失われる
- PowerShell の `-eq` / `-match` / `-contains` は**既定で大文字小文字を無視**するが、C# の
  `==` / `Ordinal` / `Regex.IsMatch`（オプションなし）は区別する。機械的に移植すると
  `NT AUTHORITY\System` や `%userprofile%` を見逃す挙動差が入る（実際に2件入った）。
- **ルール**: PowerShell の比較を C# へ移植する時は、**1つずつ「大小の区別が意味を持つか」を問う**。
  迷ったら `OrdinalIgnoreCase` / `RegexOptions.IgnoreCase`（= v1 と同じ挙動）に倒す。
  case-sensitive にして良いのは、値が XML スキーマの正準値など大小が固定と証明できる場合のみ。

### Process のリダイレクトは「読まないパイプ」がデッドロックを生む
- `RedirectStandardOutput = true` にして一度も読まないと、子プロセスが約 4KB の
  パイプバッファを埋めた時点で双方が待ち合う古典的デッドロックになる。
  stderr だけ同期 `ReadToEnd()` → `WaitForExit()` の順も同じ穴。
- **ルール**: リダイレクトしたストリームは**必ず全部ドレイン**する（`ReadToEndAsync()` を
  両方起動してから `WaitForExit(timeout)`）。読まないなら最初からリダイレクトしない。
  `WaitForExit` は必ずタイムアウト付きにし、`Process.Start` の `Win32Exception`
  （実行ファイル不在）も捕捉して分かるメッセージに変換する。

### gitignore された生成物を EmbeddedResource にすると、手元では気付けない
- 埋め込みリソースが `.gitignore` 対象の生成物（YAML→JSON）を指していたため、手元では
  常にビルドが通るのに**クリーンチェックアウトではビルド不能**だった（bot レビューで発覚）。
- **ルール**: ビルド入力に生成物を使うなら、**ビルド自体が生成できる**ようにする
  （MSBuild ターゲット + Inputs/Outputs でインクリメンタル化）。検証は「生成物を退避して
  ビルドが通るか」で行う。クリーン環境の再現は clone し直さなくてもこれで足りる。

### テストは「実行環境のスナップショット」を注入しないとフレーキーになる
- doctor のテストが `DateTime.Now`・実機のドライブ列挙・`WindowsIdentity.GetCurrent()` に
  依存しており、fixture の日付から日数が経つと `stale_last_run` が発火する時限爆弾だった
  （レビューエージェントが実際に 1 回の FAIL を観測）。
- **ルール**: 現在時刻・ドライブ構成・実行ユーザーなど環境由来の入力は、**1つのコンテキスト型に
  束ねて注入可能**にする（実行時は `Live()` ファクトリ）。fixture の日時と整合する固定 Now を使う。
- **関連**: `Console.SetOut` はプロセス全域なので、コンソールを差し替えるテストクラスが
  複数あると xUnit の並列実行で出力を奪い合う。同一 `[Collection]` に入れて直列化する。

### 静的な遅延キャッシュは xUnit 並列実行でレースする
- `DataStore.GetCatalog` は `if (dict.TryGet) return; dict[key] = Load();` パターンで
  ロケール別 Catalog をキャッシュしていた。ローカル 8 コアでは低確率で通っていたが、
  GitHub Actions runner の並列実行で確実に踏み、`InvalidOperationException:
  Operations that change non-concurrent collections must have exclusive access`
  で xUnit が fail した。
- **ルール**: 静的な遅延キャッシュ（`static Dictionary` + null-coalescing 初期化）は
  デフォルトで**スレッドセーフではない**。テストが並列実行される前提なら
  `ConcurrentDictionary.GetOrAdd(key, Loader)` に置き換える。
  reference-type 単体の `??=` は代入がアトミックなので、Load が純粋関数なら
  「多重呼び出しで同じ結果」で許容する。
- **関連**: CI 環境（並列度・コア数・タイミング）は手元と別。手元で通るのは
  「並列に走らせても壊れないこと」の証拠にならない。「並列度が違う場所で必ず走らせる」
  を成立させるために CI を早期に入れておく。

---

# 設計判断ログ

旧 `implementation-notes.md` から統合（2026-07-26）。作業中の判断・選択・妥協の記録。

## 2026-07-15 (Phase 0)

- **Pester 6.0.0 を採用**（計画では v5）: `Install-Module -MinimumVersion 5.0` で最新の 6.0.0 が入った。v5 系構文と互換であり、ダウングレードして固定するメリットがないためそのまま採用。テストの `#Requires` は `ModuleVersion 5.0` のままにし、v5/v6 どちらでも動く構文で書く。
- **データの runtime 形式は JSON**（正本は YAML）: 実行時に `powershell-yaml` 依存を持ち込まないため、`build/` で YAML→JSON 変換して同梱する方式。将来の C# 版も同じ JSON を読める。

## 2026-07-15 (Phase 1)

- **破損復元の方式**: `result-codes.yaml` / `VISION.md` は行頭空白が「前行の空白＋本来のインデント」で累積する破損だった。`本来のインデント = 現在の行頭空白 − 前行の行頭空白` で機械復元（空白のみ操作、内容行は不変）。復元後に YAML パース・38 コード・全構造を検証。
- **rank を言語非依存 ID に変更**: 元データは `情報/判断/調査/修正` という日本語がそのまま識別子だった。機械識別子は非翻訳という VISION の原則に合わせ `info/decide/investigate/fix` に改め、表示ラベル（情報/Info 等）はカタログ側に移した。
- **snippets はカタログ側に配置**: snippets はコメント行（プロース）を含むため registry ではなく ja/en 両カタログに置いた。「コマンド行は非翻訳で日英同一」はテストで機械的に担保（`#` 以外の行の一致検査）。
- **`dec` 欄は 0x8004xxxx 系で元から省略**: 符号付き/符号なしの二義性があるため。復元漏れではない。
- **元の `result-codes.yaml` は削除**: 正本が data/ に移ったため。破損版含め履歴は git に残る。

## 2026-07-15 (Phase 2)

- **カタログに `cause` を追加**（当初は `meaning` / `next` の2つだけだった）: VISION の表示型は
  「これは何 / 考えられる原因 / 次の一手」の3セクションなのに、カタログのプロースが2つしか
  無く、原因が `next` に混ざっていた。38×2 エントリの移行は後ほど高くつくため、カタログが
  新しいうちに分離した。`is_failure` のコードにのみ必須（成功コードに原因は無い）。
- **explain を doctor より先に実装**: i18n の3つの罠（翻訳境界・ロケール決定・エンコーディング）を
  小さい面積で先に潰すため。doctor は同じ `Resolve-TaskctlResultCode` / `Format-TaskctlFinding` を
  呼ぶだけになり、Phase 4 が薄くなった。
- **プレースホルダを `{{win32}}` に統一**: 当初は fallback のテキストを `-replace '<win32を10進にした値>'` で
  置換していたが、日本語の文言に依存して壊れやすい。カタログ側をプレースホルダにし、
  展開器（`Expand-TaskctlPlaceholder`）へ一本化した。
- **`--verbose` は `-Raw` へマップ**: PowerShell の共通パラメータ `-Verbose`（詳細ログ）とは
  別物のため。VISION の `--verbose`（生の設定を表示）はユーザー向けの意味であり、衝突させない。

## 2026-07-15 (Phase 3)

- **fixture は実タスクを登録せず手書き**: 壊れたタスクを実機に登録して `Export-ScheduledTask` で
  採る案もあったが、テストのために実機の状態を変えるのは read-only の方針と相性が悪く、
  再現性も落ちる。XML スキーマは実機の出力で確認済み。
- **環境変数・相対パスは正規化時に展開しない**: taskctl の文脈で展開すると、タスクが実際に
  走る文脈（別ユーザー・別プロファイル）での値と食い違い、かえって誤解を生む。文脈差そのものを
  「調査」として提示する VISION の方針に従い、生の値を保持する。

## 2026-07-15 (Phase 4-5)

- **notice は終了コード 0 に数える**: VISION は「0 問題なし / 2 警告 / 3 重大」とだけ定めていた。
  notice（＝判断：仕様かもしれない）を 2 に含めると、実機 47 タスクで 72 件の notice が出て
  常に CI が赤くなり、自動化に使えない。「仕様通知で騒がせない」と判断した。
- **走査時は warning 以上だけ詳細表示**: 同上の理由。notice だけのタスクまで詳細を並べると
  本当の問題が埋もれる（実測で出力 226 行 → 必要な所見が見つけにくい）。深掘り時と
  `--json` では全所見を出すので、情報は失われない。
- **実行予定系ルールは「時刻ベースのトリガーがある」場合に限定**: 当初 `no_next_run` /
  `never_run` を全タスクに適用したところ、ログオン・イベントトリガーのタスク（`NextRunTime` を
  持たないのが正常）で大量に誤検知した。`task.has_enabled_time_trigger` を足して絞った。
- **無効なタスクにトリガー系ルールを出さない**: 無効化が原因と分かっているのに派生の所見を
  並べてもノイズにしかならない。ルールの `when` に `task.enabled == true` を入れて抑止。
- **ビルドで YAML 解析失敗を検出して停止**: `ConvertFrom-Yaml` が失敗しても null の JSON が
  書き出され、実行時に「カタログが null」という原因の分かりにくい形で壊れた（実際に踏んだ）。
  ビルドを止める方が早く直せる。
- **`Export-ModuleMember -Function *` + マニフェストで絞る**: 当初は psm1 側で `$public.BaseName` を
  エクスポートしていたが、1ファイルに複数の公開関数（`Invoke-TaskctlDoctor` と
  `Get-TaskctlExitCode`）を置くと漏れる。公開面の制御はマニフェストの `FunctionsToExport` に一本化した。

## 2026-07-15 (Phase 6 / v1)

- **PSGallery 公開は見送り**: ライセンスが未定のため。`git clone` + `Import-Module` で使える。
- **Operational ログ参照は v2 送り**: VISION でも *任意* 扱い。設定 XML と実行情報だけで
  診断が成立したため、取得層を増やさなかった。ログは「次の一手 [調査]」としてコマンドを
  提示する形（実行はユーザー）で扱っている。
- **バッチ / WSL の起動指定ルールは見送り**: 具体的な失敗パターンを一次資料で確認できず、
  推測でルールを足すと誤検知の元になるため。VISION の「確信度に正直」を優先した。

## 2026-07-15 (v1 レビュー後の修正)

- **未知の非ゼロコードを warning / investigate へ**（以前は notice / info）: `is_failure = true` なのに
  `severity = notice` / `rank = info`（＝対応不要）という矛盾があり、結果として
  (1) doctor の詳細に出ない（フィルタが warning 以上）、(2) 終了コードが 0 になる、
  (3) 見出しが「[情報] 対応不要」なのに本文は調査を促す、という状態だった。
  実機でも `0x00002EE7` / `0x8004EE04` / `0x40010004` の3件が「未知の失敗」として緑で埋もれていた。
  **「意味を断定しない」ことと「失敗を隠す」ことは別**と整理し、非ゼロなら失敗として扱う。
  VISION の「不明なコードは断定しない」は意味の話であり、失敗の隠蔽を求めてはいない。
- **存在チェックを「本人のタスク」に限定**: `Test-Path` は taskctl を動かしている本人の権限で
  走るため、別ユーザー / SYSTEM のタスクでは「本人に読めないだけ」のパスを「無い」と誤検知する。
  `principal.is_current_user` を足して `command_not_found` / `working_directory_not_found` を
  本人のタスクに絞った。本人のタスクでも文脈は完全一致しないので rank は「調査」のまま。
- **fallback の severity をレジストリへ**: 以前はコード側にハードコードしていた。
  「事実はレジストリ、プロースはカタログ」の原則に合わせ、`registry.yaml` の fallback に移した。

## 2026-07-16 (Codex レビュー後の修正 / v1.0.4)

- **所見の収集と表示を分離**（指摘2）: 所見を「集める」条件が `is_failure`、集計・表示・終了コードが
  `severity` という二重基準になっていた。`is_failure:false` かつ `severity:warning` の
  `SCHED_S_TASK_TERMINATED`（実行時間超過で強制終了）が集計にも詳細にも出ず exit 0 だった。
  **収集は常に行い、表示だけを severity で絞る**形に変更。単一の基準にした。
- **取得失敗を終了コードへ反映**（指摘1）: 取得できなかったタスクを集計に含めておらず、
  アクセス拒否で1件も診断できなくても exit 0（問題なし）だった。warning 扱い（exit 2）とし、
  `summary.acquire_errors` とサマリー行の `!` 表示を追加。重大とは断定できないので 3 にはしない。
- **`{{task_args}}` / `{{task_regex}}` を導入**（指摘4）: `-TaskName "{{task}}"` はフォルダ配下の
  タスクに届かない（`-TaskName` にフルパスは渡せず、`-TaskPath` が必須。実機で確認）。
  また名前を二重引用符に埋めると `$(...)` がコピペ実行時に評価され、`-match` に埋めると
  `a[b` で正規表現エラーになる。値は単一引用符リテラル（`'` を `''`）＋ `[regex]::Escape` で
  エスケープし、`-TaskName 'X' -TaskPath '\Foo\'` を生成する。実機の cmdlet で動作確認済み。
- **マップドライブ判定を DriveType ベースへ**（指摘6）: 「固定ドライブ以外はすべてネットワーク」
  としていたため、USB / 光学ドライブを誤報しうる。実際の `DriveType=Network` か、
  **存在しないドライブ文字**（タスク実行時にのみマウントされる想定の Z: 等）のみを対象にした。
- **`0x2` の断定を緩めた**（指摘3）: 「プログラムの終了コードではない」と書いていたが、
  `LastTaskResult` はプログラムの終了コードもそのまま返すため、数値だけでは区別できない。
  「多くの場合 ERROR_FILE_NOT_FOUND だが、プログラムが 2 を返した可能性も残る」に改め、
  次の一手にも直接実行での切り分けを足した。VISION の「確信度に正直」に合わせた訂正。
- **複数操作のタスクでは全 Exec を並べる**（指摘3後半）: タスクは最大32個の操作を順に実行でき、
  結果コードからはどれが失敗したか特定できない。1つ目だけ見せると誤った案内になるため、
  全部を並べて断定しない。
- **`--json` の UTF-8 は PS7 前提と明記**（指摘5）: 返すのは文字列で、バイト列の
  エンコーディングは受け取り側（`>` / `Out-File`）が決める。5.1 の既定は UTF-16LE なので
  実装では保証できない。README に 5.1 での保存方法を記載した。

## 2026-07-16 (v1.1 / 翻訳表の拡充)

- **12 コード中 6 件だけを追加**: 実機で「未知」として出たコードを一次資料（Microsoft Learn）で
  検証したところ、11 件は定数を特定できた。しかし**「一次資料で意味が確認できる」ことと
  「翻訳表に載せてよい」ことは別**だと整理し、3 条件（意味の確認 / 有用な次の一手 / kind の
  定義域に収まる）を全て満たす 6 件に絞った。
- **`0x80070002` は `0x00000002` があっても別途載せる**: 当初「既に裸の 2 が表にあるから不要」と
  判断しかけたが、両者は別キーで扱いが全く違った。裸の `0x00000002` には共有(UNC)の回避策など
  厚い案内が付くのに、HRESULT 版は fallback の `net helpmsg 2` だけ ——
  **同じ原因なのに得られる情報が少ない**という非対称があった。しかも `0x8007----` は
  構造的に Win32 由来と分かるぶん、裸の 2 より**断定できる**（「プログラムが 2 を返した
  可能性」のヘッジが要らない）。載せない理由が無い。
- **`source:` フィールドを追加**: 翻訳表の正確性が信頼の根幹（VISION）なのに、v1 の出典は
  ファイル冒頭のコメントに 5 URL がまとまっているだけで、どのコードがどれ由来か辿れなかった。
  v1.1 以降はエントリ単位で URL を持ち、`learn.microsoft.com` 以外を機械的に弾く。
- **`0x40010004` (DBG_TERMINATE_PROCESS) を見送り**: 一次資料（[MS-ERREF] NTSTATUS Values）で
  確認できたが **NTSTATUS** であり、`kinds`（status / sched_error / system / app）に収まらない。
  `system` は「Windows システム/HRESULT」と定義済みで、そこへ押し込むと嘘になる。
  さらに severity が informational (`0x4`) のため `is_failure` / `severity` の判断が割れる
  ＝過去に2度踏んだ「二重基準」の再発経路。「デバッガがプロセスを終了させた」から
  タスクスケジューラ文脈で有用な案内も書けない。**分類できないものは載せない**。
- **`0x00000420` / `0x00002EE7` を見送り**: デコード自体は一次資料で確定するが、
  `LastTaskResult` はプログラムの終了コードもそのまま返すため、`1056` / `12007` が
  Win32 / WinINet 由来なのかアプリ独自の終了コードなのかを値だけでは区別できない。
  `0x2` は「多くの場合 ERROR_FILE_NOT_FOUND」とヘッジして載せているが、あれは頻度と
  トラブルシューティング上の重要性が桁違いで、しかも公式文書が Task Scheduler の文脈で
  言及している。同じヘッジをこの2つに適用するのは、根拠なく「たぶん Win32 由来」と
  示唆することになる。
- **fallback のテストに「表に載りうる値」を使っていた**: `0x80070002` を追加したら、
  それを fallback 経路の代表として使っていたテストが**完全一致に吸われて fallback を
  検証しなくなった**（アサーションが落ちて発覚）。表に載らない `0x80070057` へ差し替え、
  さらに「この値が表に無いこと」自体をテストで固定した。fallback の説明文にあった
  「例: 0x80070002 なら…」も、載せた瞬間に嘘になるため例示ごと削除した。
- **出典 URL は実際に開いて内容を確認した**: coverage テストは URL の**形**
  （`^https://learn\.microsoft\.com/`）しか見ない。URL が実在し、そこに主張どおりの
  定数と説明文があることは機械では担保できないため、3 本すべてを開いて照合した。
  検証を委譲したエージェントは `0x800710E0` の10進を 2147943136 と誤っていた（正しくは
  2147946720）。`dec` は 0x8004/0x8007 系では元から省略する規約だったためデータには
  入らなかったが、**委譲した検証をそのまま信じない**根拠になった。
- **追加分の severity / rank は fallback と同じ (warning / investigate)**: 意味が分かったことは
  重大度を上げる理由にも下げる理由にもならない。実際 `ERROR_ALREADY_EXISTS` や
  `ERROR_REQUEST_REFUSED` は、システム標準タスクでは正常でも出うる。プロースは `0x2` に倣って
  「これだけでは異常とは言えない」とヘッジし、**断定を増やさずに情報だけを増やした**。

## 2026-07-16 (VISION: v2 の実装言語を Go → C# へ変更)

- **v2 を Go から C#（.NET）へ変更した**: 決め手は 2 点で、いずれも一般論ではなく本ツール固有の
  前提から来る。(1) **Windows 専用と VISION で宣言済み**のため、Go を選ぶ最大の理由である
  クロスプラットフォームな静的バイナリが不要になる。逆に読む情報源は Windows 固有
  （CIM 経由の `Get-ScheduledTask`、Operational ログ）で、Go だと PowerShell へのシェルアウトか
  syscall 自作が要る一方、.NET は標準ライブラリで届く。(2) **v1 の PowerShell は .NET そのもの**
  であり、C# 行きは実行基盤の継続、Go 行きは異なる言語での書き直し＋グルーコードになる。
  個人保守ではここが最も効く。
- **「単一バイナリ配布」は判断材料から外した**: Go 版を望んだ当初の動機だが、C# も NativeAOT で
  自己完結バイナリを作れるため差にならない。差にならないものを根拠に据えると判断を誤る。
- **受け入れた代償**: .NET SDK 未インストール（Go 1.26.5 は導入済み）、NativeAOT には MSVC
  ビルドツールが要る、グローバル設定も Go 前提（module パス規約等）。隠さず VISION に明記した。
- **AOT リスクを設計制約に変換した**: NativeAOT はリフレクション多用の Windows API（CIM/MI、
  一部 EventLog 経路）をトリミングで壊しうる。VISION に元々あった「取得層はインターフェースで
  隔離」を、C# 版では**設計の都合ではなく前提条件**に格上げした（取得をシェルアウトに留める限り
  AOT は通る）。ネイティブ interop に進むなら先に AOT 実証、と条件を先に書いた。
- **`Win32Exception(code).Message` は採らなかった**: OS からエラー文言が只で取れるのは C# の利点だが、
  核心の半分である `SCHED_S_*` / `SCHED_E_*` の HRESULT は確実に引けず、OS 生成訳文は
  「カタログが文言を所有する」という i18n 設計を迂回する。補助・照合用に留める旨を VISION に補足した。
- **ドキュメントの Go 前提記述も同時に揃えた**: VISION.md の 3 箇所（i18n の実装言語非依存、技術方針、
  将来像）に加え、PLAN.md 2 箇所と本ファイル 1 箇所。片方だけ直すと後で矛盾が事実として読まれる。
- **`Microsoft.Win32.TaskScheduler`（dahall/TaskScheduler）を検討し、見送った**: .NET で Task Scheduler を
  扱う定番ライブラリだが、3 点で本ツールと噛み合わない。(1) **NativeAOT と両立しない**：
  実装は `Type.GetTypeFromCLSID` + `Activator.CreateInstance` で COM を実行時に活性化しており、
  Microsoft は IL3052「COM interop is not supported with full ahead of time compilation」として
  明記、到達時に実行時例外になる。C# を選んだ前提の一つ（単一バイナリ）が壊れる。
  (2) **VISION が COM を明示的に対象外にしている**。(3) **write 可能**なため、read-only が
  「構造的な保証」から「規律」に落ちる。現状は `Export-ScheduledTask` / `Get-ScheduledTaskInfo`
  しか呼ばず壊しようがないが、`RegisterTaskDefinition` が 1 コール先にあるのは別物。
  なお名前に反し **Microsoft 製ではない**（NuGet 名 `TaskScheduler` / 作者 dahall / MIT）。
  加えて売りの一つが localization であり、「カタログが文言を所有する」i18n 境界とも競合する。
  **採用が正解になる条件**：apply/write に踏み込む、AOT を諦めて framework-dependent 配布にする、
  XML から取れない情報が必要と判明する。現時点ではどれも該当しない。

## 2026-07-16 (C# 版 v2 実装 / Phase 1-3)

- **取得層は PowerShell シェルアウトに徹した**: COM (`Microsoft.Win32.TaskScheduler` 含む) は
  NativeAOT で非対応（IL3052）と VISION で結論済みのため、`Export-ScheduledTask` /
  `Get-ScheduledTaskInfo` を埋込 `acquire.ps1` 経由で呼ぶ設計にした。stdout はコンソールの
  既定コードページ（PS 5.1 の CP932 等）に化けうるため使わず、UTF-8 ファイル書き出し
  （`[System.IO.File]::WriteAllText(..., UTF8Encoding(false))`）→ C# 側がファイルを読む方式にした。
- **`messages.ja.json` はサテライトアセンブリに分離されかけた**: MSBuild は `.ja.` を IETF
  言語タグと解釈し、`EmbeddedResource` を既定でサテライトアセンブリへ分ける。
  `GetManifestResourceStream` が本体アセンブリで見つからなくなり実行時エラーになった。
  `WithCulture="false"` を全埋込リソースに明示して回避。
- **TFM を `net10.0-windows10.0.17763.0` に固定**: `WindowsIdentity` 等 Windows 専用 API で
  CA1416（プラットフォーム限定 API 検査）がビルドエラーになった。VISION で「Windows 専用」と
  明記済みなので、警告を握りつぶすのではなく TFM を正しく宣言する形で解決した。
  `SupportedOSPlatformVersion` を別指定すると TargetPlatformVersion との不整合で失敗したため、
  TFM 文字列に直接バージョンを埋め込む形にした。
- **`--json` の日本語エスケープを `UnsafeRelaxedJsonEscaping` で解除**: 既定の
  `JsonSerializerOptions` は非 ASCII を `\uXXXX` にエスケープする。PowerShell 版
  （`ConvertTo-Json` は生の UTF-8 を返す）と挙動を合わせるため、出力用の `JsonSerializerOptions`
  を分離して encoder を緩めた（データ読み込み用の `DataJsonContext` 既定設定はそのまま）。
- **未知コードに OS の `Win32Exception` 訳文を補助表示として追加した**（PowerShell 版には無い）。
  AOT PoC で「`SCHED_S_*` の HRESULT も含め、OS の FormatMessage が日本語文言を返す」ことを実測で
  確認済み（前回の想定は誤りだった）。ただしカタログを翻訳の正本とする設計は変えず、
  `os_message` / `参考 (OS)` として分離表示に留めた（本文の `Meaning` には混ぜない）。
- **`RuleClause.Eq` は `object?` のまま JSON ソースジェネレータで通った**: 逆シリアライズ時は
  `JsonElement` として保持される。評価器 (`RuleEngine.MatchesEq`) は `JsonElement.ValueKind` で
  bool/string/number を判定する形にした（rules.json の `eq` は現状すべて bool）。
  `object` 型プロパティは AOT のリフレクションフリー原則と衝突しそうに見えたが、
  `JsonSerializable` 経由で問題なく動いた。
- **実機 69 タスクで PowerShell v1 と完全一致を確認**: `scanned=69 / errors=0 / warnings=13 /
  notices=107 / exit_code=2` が両実装で一致。取得層・XML 正規化・ルールエンジン・結果コード解決の
  移植が対症療法ではなく本当に等価であることを、単体テストだけでなく実データで裏取りした。
- **xUnit は internal 型を直接テストする方針にした**（PowerShell 版の `InModuleScope` 相当）。
  `InternalsVisibleTo` で `Taskctl.Cli.Tests` にだけ公開。fixture XML は `tests/fixtures/` を
  そのまま参照し複製しない（`CopyToOutputDirectory`）。122件、実行時間1秒未満。
- **doctor の取得層はテスト時に差し替え可能にした**: `DoctorCommand.Run(args, acquirer: null)` の
  第2引数に `ITaskAcquirer` を注入できるようにし、PowerShell 版の `Mock -ModuleName Taskctl
  Get-TaskctlTask` に相当する差し替えを実現。実機・PowerShell 起動なしで doctor の統合テストが走る。

## 2026-07-16 (レビュー対応: 自己レビュー + PR bot レビュー)

- **サービスアカウント判定とプロファイル変数検出を case-insensitive 化**: PowerShell の
  `-match`/`-eq` は既定で大文字小文字を無視するが、C# 移植で ordinal 比較にしてしまい
  `NT AUTHORITY\System` や `%userprofile%` を見逃す v1 との挙動差が出ていた（自己レビューで検出）。
  他の ordinal 比較（LogonType 等）は XML の正準値のみが入るため据え置き。
- **埋め込み JSON をビルド前に MSBuild ターゲットで生成**（Codex bot P1）: `src/Taskctl/data/*.json`
  は .gitignore 対象の生成物で、クリーンチェックアウトでは v2 のビルドが失敗していた。
  csproj の `GenerateDataJson` ターゲット（Inputs/Outputs でインクリメンタル）から
  `build/Convert-DataToJson.ps1` を呼ぶ。シェルは常在する `powershell.exe`（5.1）を使用
  — pwsh は .NET SDK だけの環境に無い可能性があるため。5.1 の ConvertTo-Json は
  キー順・インデント・非 ASCII の \uXXXX エスケープが pwsh と異なるが、v1 (Pester 185件) /
  v2 (xUnit 133件) 両方でどちらの形式でも全テスト成功を確認済み。JSON 契約は形式差を許容する。
- **取得層のプロセス処理を堅牢化**（自己レビュー + Gemini bot）: (1) pwsh/powershell 不在時の
  `Win32Exception` を `InvalidOperationException` へ変換（スタックトレースの素通り防止）、
  (2) `WaitForExit` に 120 秒タイムアウト（超過時はプロセスツリーごと Kill）、(3) stdout/stderr を
  非同期で両方ドレイン。Gemini は `RedirectStandardOutput` の削除を提案したが、想定外出力の
  取りこぼしよりドレインの方が安全側なのでドレインを採用。
- **不正 XML は `FormatException` に揃える**（Gemini bot）: `XDocument.Parse` の `XmlException` を
  素通しするとタスク1件の破損 XML でプロセス全体が落ちる。呼び出し元の「このタスクだけ
  解析失敗として継続」という契約（FormatException）に変換して揃えた。
- **見送った指摘**: stderr の `StandardErrorEncoding=UTF8` 明示（PS 5.1 はコンソールに CP932 で
  書くため UTF-8 指定は逆に文字化けする）、展開先 acquire.ps1 の GUID 名化（ユーザー専有
  Temp の ACL 前提で攻撃面が限定的、固定名はプロセス間キャッシュとして機能）。

## 2026-07-16 (レビュー対応 第2弾: テストのヘルメティック化)

- **DiagnosisContext を導入**（自己レビュー指摘: doctor テストが実時刻・実機ドライブ・実行ユーザーに
  依存しフレーキー。実測で 1 回 FAIL を観測）: 現在時刻・ドライブ構成・実行ユーザーのスナップショットを
  1つの型に束ね、`DoctorCommand.Run(args, acquirer, context)` で注入可能にした。実行時は
  `DiagnosisContext.Live()`。fixture の日時 (2026-07-15) と整合する固定 Now を使うことで、
  日数経過による stale_last_run 等の誤発火を排除。
- **コンソール差し替えテストは同一コレクションで直列化**: `Console.SetOut` はプロセス全域のため、
  xUnit がテストクラスを並列実行すると Doctor/Explain のテストが互いの出力を奪い合う
  （実際に並列衝突で失敗を観測）。`[Collection("console-redirection")]` で直列化した。
- **explain --json / CliArgs / LocaleResolver / 取得層全体失敗 (exit 1) のテストを追加**
  （自己レビュー指摘のテスト欠落。LocaleResolver は既に env/uiCulture が注入可能な設計だった）。

## 2026-08-15: リリース成果物のバージョンはタグから渡す

- 却下した案: 従来どおり csproj の `<Version>` をリリースのたびに手で上げる。
- 決め手: v2.0.1 として配布した exe の中身が `2.0.0-alpha1` のままだった（更新漏れが実際に起きていた）。
  `dotnet build -p:Version=9.9.9` した dll の FileVersion が `9.9.9.0` になることを確認したので、
  publish 時にタグから渡せば二重管理そのものが消える。csproj の値はローカルビルドの既定値に降格。
- 覆す条件: タグ名と成果物バージョンを意図的にずらす必要が出た場合（例: 同一コードを別版として再配布）。

## 2026-08-15: `--version` はアセンブリ属性のリフレクション取得で足りる

- 却下した案: MSBuild ターゲットで `BuildVersion.g.cs` を生成し `const string` として焼き込む案。
  NativeAOT はリフレクションを壊しうるため、確実側に倒す発想（既存の `GenerateDataJson` と同じ手口）。
- 決め手: `AssemblyInformationalVersionAttribute` をリフレクションで読む実装のまま
  `dotnet publish -c Release -p:Version=2.0.1`（NativeAOT）した実 exe が、`--version` /
  `version` / `doctor --version` のいずれでも `taskctl 2.0.1` を出力した。`TreatWarningsAsErrors=true`
  のままトリミング警告（IL2026 / IL3050 等）も出ず、生成ターゲットを足す理由が観測できなかった。
- 覆す条件: publish 済み exe でバージョンが空や `unknown` になる（＝属性がトリムされる）ことを
  観測したら、生成した const へ切り替える。テストは `VersionInfo.Value` が空にならないことを見ている。
