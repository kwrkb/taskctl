namespace Taskctl.Cli;

internal static class Usage
{
    public const string Text = """
taskctl - Windows タスクスケジューラの失敗を診断し、次の一手を示す（設定は変更しません）

使い方:
  taskctl doctor              全タスクを走査し、状態一覧と問題のあるタスクの診断を表示
  taskctl doctor <task>       タスクを深掘りして診断（名前 / "\フォルダ\名前" / ワイルドカード可）
  taskctl explain <code>      結果コード単体を翻訳（例: taskctl explain 0x41303）

共通フラグ:
  --lang ja|en                表示言語（既定: TASKCTL_LANG > OS の UI カルチャ > en）
  --json                      構造化出力（常に UTF-8）
  --verbose                   生の設定も表示

終了コード:
  0  問題なし   2  警告あり   3  重大な問題あり   1  実行エラー
""";
}
