# taskctl

> English / **[日本語](README.ja.md)**

[![test](https://github.com/kwrkb/taskctl/actions/workflows/test.yml/badge.svg)](https://github.com/kwrkb/taskctl/actions/workflows/test.yml)

A diagnostic tool for Windows Task Scheduler that **pinpoints why a task failed (or is likely to fail) and tells you what to do next**.

It never changes any settings (read-only). Output is available in **English and Japanese**.

## What it does

Windows already tells you *what* went wrong with a scheduled task. What it doesn't tell you is **"…so here's what you do next."**

- The last result is shown as a raw code like `0x41303`, and you're on your own to look it up
- It doesn't distinguish whether that code is a *program exit code* or a *Task Scheduler status code*
- It won't flag failure-prone settings (relative paths, missing working directory, profile-dependent paths) before they bite

taskctl focuses on exactly this: **translating codes and pointing at the next action**.

```console
$ taskctl explain 0x41303 --lang en
0x00041303 (267011)  [SCHED_S_TASK_HAS_NOT_RUN]
  (status code)

What this is:
  A status code meaning "has not run yet". Not a failure.

Next step [decide]:
  Normal right after registration. If it persists when the task should be running,
  check the trigger and whether the task is enabled.
```

### What it doesn't do

Listing, registering, enabling, running on demand, fetching history — the built-in
`Get-ScheduledTask` / `Register-ScheduledTask` / `Enable-ScheduledTask` / `Get-WinEvent`
already cover these. taskctl doesn't reinvent them.

Anything under `apply` / `plan` / `write`, COM implementations, GUIs, config-as-code
deployment, and multi-PC central management are all out of scope.

## Two implementations

taskctl ships as a C# single-exe (v2, stable) and a PowerShell module (v1, stable).
Both share the same data assets (code table, detection rules, ja/en catalogs) and
behave identically for `explain` / `doctor` (verified against real machines).
The CLI is identical; only the distribution format and runtime environment differ.

| | v2 (C# / .NET) | v1 (PowerShell) |
|---|---|---|
| Status | Stable (v2.0) | Stable (v1.1) |
| Distribution | Single exe (NativeAOT) | Module (`.ps1` files) |
| Runtime | Standalone. Only the acquisition layer shells out to `powershell` / `pwsh` | PowerShell 5.1 / 7 |
| Build | Requires .NET SDK to compile (binary also available on Releases) | Data conversion only (`Convert-DataToJson.ps1`) |

**Default to v2** (shortest install path, no external dependencies). Pick v1 if you
want to fold it into an existing PowerShell-module workflow.

## Install (binary, v2 single exe)

No .NET SDK needed. Just download the zip from GitHub Releases and extract.

1. Download `taskctl-vX.Y.Z-win-x64.zip` from the
   [Releases page](https://github.com/kwrkb/taskctl/releases/latest)
2. Extract anywhere (`taskctl.exe`, single file)
3. Run `taskctl.exe doctor`

Drop it somewhere in `PATH` and you can invoke it as `taskctl doctor`.
Since it's a NativeAOT single exe, **no .NET runtime is required** (the acquisition
layer invokes `powershell` internally at runtime).

## Install (v1, PowerShell)

```powershell
git clone https://github.com/kwrkb/taskctl.git
cd taskctl

# Convert data (YAML) into the runtime format (JSON) and embed it in the module
.\build\Convert-DataToJson.ps1

Import-Module .\src\Taskctl\Taskctl.psd1
```

**Requirements**: Windows / PowerShell 7 recommended (5.1 works too; if Japanese output
looks garbled, run `chcp 65001` or use `pwsh`). `powershell-yaml` is needed only at
build time — if it's not installed, `Convert-DataToJson.ps1` installs it for you.
No runtime dependencies.

## Install (v2, C#)

```powershell
git clone https://github.com/kwrkb/taskctl.git
cd taskctl\src\Taskctl.Cli

dotnet publish -c Release
# -> bin\Release\net10.0-windows10.0.17763.0\win-x64\publish\taskctl.exe
```

Drop the resulting `taskctl.exe` in `PATH` and you're set (single exe, no external
dependencies).

**Requirements**: .NET 10 SDK (build-time only), plus the MSVC build tools that
NativeAOT links against (the "Desktop development with C++" workload from Visual
Studio Build Tools). At runtime, only PowerShell is required (5.1 or 7, used
internally to invoke `Export-ScheduledTask` / `Get-ScheduledTaskInfo`); no .NET
runtime is required (AOT single binary).

## Usage

```
taskctl doctor              # Scan all user tasks. Status list plus diagnosis for problems
taskctl doctor <task>       # Deep-dive a single task
taskctl explain <code>      # Translate a single result code (e.g. taskctl explain 0x41303)

Common flags:
  --lang ja|en   Display language (default is inferred from env/OS, final fallback is en)
  --json         Structured output (always UTF-8)
  --verbose      Also show raw settings
```

`explain` accepts hex (`0x41303`), decimal (`267011`), or signed decimal
(`-2147024891`). `LastTaskResult` is returned as signed 32-bit, so you can paste it
in as-is.

For `doctor <task>`, the argument can be a name (`MyBackup`), a full path
(`\Foo\MyBackup`), or a wildcard (`Omen*` — deep-dives everything that matches).

For a PowerShell-native call, `Invoke-TaskctlDoctor` / `Invoke-TaskctlExplain` are
available (`taskctl doctor --lang en` ≡ `Invoke-TaskctlDoctor -Lang en`). The v1
`taskctl` function and the v2 `taskctl.exe` share the same command shape (`taskctl
doctor --lang en --json` produces the same output on either).

### doctor output example

```console
$ taskctl doctor --lang en
Scanned 47 tasks: error 0 / warning 6 / notice 72

=== \OmenInstallMonitor  (Ready) ===
  0x00000002 (2)  [ERROR_FILE_NOT_FOUND]
    (system error)

  What this is:
    The file to be executed could not be found. Not a program exit code.

  Likely cause:
    The action's path does not exist, or it cannot be resolved in the task's
    runtime context (different user, mapped drive).

  Next step [investigate]:
    Verify that the path resolves in the task's runtime user context.
    ...
```

On a scan, **only tasks at warning or higher get a detailed diagnosis** (notice-only
tasks appear in the list without details). A single-task deep-dive shows notices too.
`--json` always includes every finding.

### Wire it into automation

Exit code is `0` (all clear) / `2` (warnings) / `3` (errors).

```powershell
Import-Module .\src\Taskctl\Taskctl.psd1
Invoke-TaskctlDoctor -Lang en
exit (Get-TaskctlExitCode)
```

The `--json` output carries the same value in its `exit_code` field.

```powershell
$report = taskctl doctor --json | ConvertFrom-Json
$report.tasks | Where-Object { $_.last_result.is_failure } |
    ForEach-Object { "$($_.task): $($_.last_result.constant)" }
```

`notice` (things that *might* be intentional) counts toward exit code 0 — we don't
want spec notices to turn CI red. On the other hand, **any task whose settings we
couldn't read pushes the exit code to 2** (`summary.acquire_errors`). We never
report "all clear" when we couldn't actually diagnose.

#### Saving JSON to a file

`--json` returns a string; the file encoding is up to whoever receives it.
PowerShell 7 defaults to UTF-8, so `taskctl doctor --json > report.json` gives you
UTF-8. **Windows PowerShell 5.1's `>` / `Out-File` default is UTF-16LE**, though.
To get UTF-8 on 5.1:

```powershell
taskctl doctor --json | Out-File report.json -Encoding utf8   # UTF-8 with BOM on 5.1
# For BOM-less UTF-8:
[IO.File]::WriteAllText('report.json', (taskctl doctor --json), [Text.UTF8Encoding]::new($false))
```

## Design

### Rank next steps by confidence

A wrong "next step" is worse than none at all. We only assert when we can.

| Rank | Meaning | What we emit |
|---|---|---|
| **fix** | Cause essentially confirmed | A copy-pasteable canonical command |
| **investigate** | Can't assert | An information-gathering command to find the real cause |
| **decide** | Might be intentional | The question "is this on purpose?" |
| **info** | Not a failure | No action needed |

And we **don't fix things automatically.** doctor only *shows* commands; you decide
whether to run them.

### Discipline against false positives

- **Assume context differences.** The context taskctl runs in and the context the
  task actually runs in (different user, mapped drives, different profile) are
  different. File-existence checks can misfire on this gap, so we report them as
  "investigate", not "error".
- Heuristics like relative-path detection top out at `warning`. We never emit a
  "fix" command from a heuristic.
- In fact, **not a single v1 detection rule has `rank: fix`** (a test enforces this).

### Data assets and i18n

The core of the tool is a set of language-independent assets: the code table, the
detection rules, and message catalogs.

| File | Contents |
|---|---|
| `data/registry.yaml` | **Facts** about codes (`code → constant / kind / severity / is_failure / next_rank`) |
| `data/rules.yaml` | Detection rules (declarative; `when` is AND) |
| `data/messages/ja.yaml`, `en.yaml` | **How to say it** (`meaning` / `cause` / `next`) |

**Only the prose layer is translated.** Commands, constant names
(`SCHED_S_TASK_READY`), code values, and machine identifiers like `kind` /
`severity` are not translated. Translating them would break the commands and make
logs ungreppable.

This boundary is enforced by tests (key-set equality, snippets' command lines being
identical between languages, etc.).

Commands we emit have `{{task}}` / `{{command}}` placeholders that `doctor` fills
with the actual task name and command. Copy-paste, and they run.

```console
$ taskctl doctor MyBackup --lang en
...
Next step [investigate]:
  Run the action's command directly, bypassing the scheduler, to see the app-side error:
    # Run the Action's command directly, bypassing the task, to isolate the problem
    powershell.exe -File Z:\scripts\backup.ps1     <- actual command goes here
```

`explain <code>` on its own doesn't know a task, so it displays `<COMMAND>` /
`<TASKNAME>` (we never emit blanks).

### Accuracy of the translation table

We don't fill code meanings from memory; **we only include codes verified against
Microsoft primary sources** (citations at the top of `data/registry.yaml`). Codes
not in the table are not guessed — for `0x8007xxxx` we point at `net helpmsg`;
otherwise we say "unknown" and print both hex and decimal.

## Development

### v1 (PowerShell)

```powershell
.\build\Convert-DataToJson.ps1   # data/*.yaml -> src/Taskctl/data/*.json
Invoke-Pester -Path tests        # Requires Pester 5+
```

Detection rules are pure functions over the normalized model, so `tests/fixtures/*.xml`
lets you test **without registering real tasks on a Windows machine**.

- Adding a code to the translation table: update both `data/registry.yaml` (facts)
  and `data/messages/*.yaml` (prose). Primary-source verification is required.
  Coverage tests catch missing keys.
- Adding a detection rule: add the rule to `data/rules.yaml`, the fact to
  `Get-TaskctlFact`, and the prose to the catalogs. Keep the judgement logic in
  fact computation, not scattered through the code.

### v2 (C#)

```powershell
.\build\Convert-DataToJson.ps1                        # Same JSON as v1; v2 embeds it too
dotnet test .\tests\Taskctl.Cli.Tests\                # xUnit (no real machine needed, sub-second)
dotnet build .\src\Taskctl.Cli\ -p:PublishAot=false   # Turn AOT off for fast dev builds
```

Swap `ITaskAcquirer` to mock the acquisition layer; `tests/fixtures/*.xml` are shared
with v1 (the process for adding codes and detection rules is the same as v1 — data
assets are common to both implementations).

Code layout: `src/Taskctl.Cli/{Codes,Findings,Model,Rules,Facts,Doctor,Acquisition,Cli,I18n,Data}/`.
Only the acquisition layer (`Acquisition/`) touches the real machine; everything
else is pure functions over the normalized model.

## License

MIT License. See [LICENSE](LICENSE).
