# implementation-notes.md

作業中の判断・選択・妥協の記録。

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
