using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using Taskctl.Data;
using Taskctl.Model;

namespace Taskctl.Acquisition;

// COM interop は NativeAOT で非対応（IL3052）なため、取得は PowerShell へのシェルアウトに徹する。
// VISION の「取得層はインターフェースで隔離」を、C# 版ではこの一点に集約する。
internal sealed class PowerShellTaskAcquirer : ITaskAcquirer
{
    // 全タスク走査（数百件）でも余裕を持って終わる長さ。ハング時の無限待ちだけを防ぐ。
    private const int TimeoutMs = 120_000;

    public List<AcquiredTask> Acquire(string? taskName, bool includeMicrosoft)
    {
        var scriptPath = ExtractScript();
        var outFile = Path.Combine(Path.GetTempPath(), $"taskctl-acquire-{Guid.NewGuid():N}.json");

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = ResolveShell(),
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-NonInteractive");
            psi.ArgumentList.Add("-ExecutionPolicy");
            psi.ArgumentList.Add("Bypass");
            psi.ArgumentList.Add("-File");
            psi.ArgumentList.Add(scriptPath);
            if (!string.IsNullOrWhiteSpace(taskName))
            {
                psi.ArgumentList.Add("-TaskNameArg");
                psi.ArgumentList.Add(taskName);
            }
            if (includeMicrosoft)
            {
                psi.ArgumentList.Add("-IncludeMicrosoft");
            }
            psi.ArgumentList.Add("-OutFile");
            psi.ArgumentList.Add(outFile);

            Process? process;
            try
            {
                process = Process.Start(psi);
            }
            catch (System.ComponentModel.Win32Exception ex)
            {
                throw new InvalidOperationException($"PowerShell を起動できませんでした ({psi.FileName}): {ex.Message}");
            }
            if (process is null) throw new InvalidOperationException("PowerShell を起動できませんでした。");

            string stderr;
            using (process)
            {
                // stdout / stderr の両方をドレインしないと、想定外の出力がパイプバッファを
                // 埋めた際に双方が待ち合うデッドロックになりうる
                var stdoutTask = process.StandardOutput.ReadToEndAsync();
                var stderrTask = process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(TimeoutMs))
                {
                    try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
                    throw new InvalidOperationException($"タスクの取得がタイムアウトしました（{TimeoutMs / 1000} 秒）。");
                }
                stderr = stderrTask.GetAwaiter().GetResult();
                stdoutTask.GetAwaiter().GetResult();
            }

            if (!File.Exists(outFile))
            {
                var detail = string.IsNullOrWhiteSpace(stderr) ? "" : $"\n{stderr.Trim()}";
                throw new InvalidOperationException($"タスクの取得に失敗しました（PowerShell の出力がありません）。{detail}");
            }

            var json = File.ReadAllText(outFile);
            var raw = JsonSerializer.Deserialize(json, DataJsonContext.Default.RawAcquireOutput)
                ?? throw new InvalidOperationException("取得結果の解析に失敗しました。");

            if (raw.Error is not null)
            {
                throw new InvalidOperationException(raw.Error);
            }

            return raw.Tasks.Select(ToAcquiredTask).ToList();
        }
        finally
        {
            try { File.Delete(outFile); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    private static AcquiredTask ToAcquiredTask(RawAcquiredTask raw)
    {
        TaskModel? model = null;
        string? acquireError = raw.AcquireError;

        if (raw.Xml is not null)
        {
            try
            {
                model = TaskXmlParser.Parse(raw.Xml, raw.TaskName, raw.TaskPath);
            }
            catch (FormatException ex)
            {
                acquireError ??= ex.Message;
            }
        }

        TaskInfoModel? info = raw.Info is null ? null : new TaskInfoModel
        {
            LastRunTime = raw.Info.LastRunTime?.LocalDateTime,
            LastTaskResult = raw.Info.LastTaskResult,
            NextRunTime = raw.Info.NextRunTime?.LocalDateTime,
            NumberOfMissedRuns = raw.Info.NumberOfMissedRuns,
        };

        return new AcquiredTask
        {
            TaskName = raw.TaskName,
            TaskPath = raw.TaskPath,
            FullName = raw.TaskPath + raw.TaskName,
            State = raw.State,
            Model = model,
            Info = info,
            AcquireError = acquireError,
        };
    }

    // pwsh (PowerShell 7+) があれば優先し、無ければ Windows PowerShell 5.1 にフォールバックする。
    private static string ResolveShell()
    {
        if (IsOnPath("pwsh.exe") || IsOnPath("pwsh")) return "pwsh";
        return "powershell";
    }

    private static bool IsOnPath(string exeName)
    {
        var pathEnv = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in pathEnv.Split(Path.PathSeparator))
        {
            try
            {
                if (dir.Length > 0 && File.Exists(Path.Combine(dir, exeName))) return true;
            }
            catch (ArgumentException) { /* 不正なパス断片は無視 */ }
        }
        return false;
    }

    // 埋込スクリプトを一時ファイルへ展開する（プロセス起動には実ファイルパスが要る）。
    // プロセス単位でキャッシュし、複数回の Acquire 呼び出しでも再展開しない。
    private static string? _cachedScriptPath;

    private static string ExtractScript()
    {
        if (_cachedScriptPath is not null && File.Exists(_cachedScriptPath)) return _cachedScriptPath;

        var asm = typeof(PowerShellTaskAcquirer).Assembly;
        using var stream = asm.GetManifestResourceStream("acquire.ps1")
            ?? throw new InvalidOperationException("埋込リソースが見つかりません: acquire.ps1");
        using var reader = new StreamReader(stream, System.Text.Encoding.UTF8);
        var content = reader.ReadToEnd();

        var path = Path.Combine(Path.GetTempPath(), "taskctl-acquire.ps1");
        File.WriteAllText(path, content, new System.Text.UTF8Encoding(false));
        _cachedScriptPath = path;
        return path;
    }
}
