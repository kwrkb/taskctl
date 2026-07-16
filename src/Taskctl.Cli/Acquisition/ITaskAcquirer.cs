namespace Taskctl.Acquisition;

// 取得層。実機（タスクスケジューラ）へのアクセスをここへ隔離する。
// VISION: すべて read-only。診断ルールはこの層が返す正規化モデル上の純粋関数にするため、
// ここだけをテスト時に差し替えられるようにしておく。
internal interface ITaskAcquirer
{
    List<AcquiredTask> Acquire(string? taskName, bool includeMicrosoft);
}
