# DiskClutterSim

Test-fixture generator for a disk-cleanup automation script that targets
`cleanmgr.exe` categories: previous Windows installations, update
artifacts, error dumps, and upgrade logs.

These scripts don't call `cleanmgr.exe` or touch real system data — they
build a realistic fake folder layout in a sandbox so you can point your
cleanup script at it and verify it detects, removes, and correctly reports
GB reclaimed.

## Files

- `Common.ps1` — shared helpers (junk-file generator, path safety checks). Dot-sourced by the others; not run directly.
- `Simulate-PreviousWindowsInstallation.ps1` — fake `Windows.old` tree.
- `Simulate-UpdateArtifacts.ps1` — fake `SoftwareDistribution\Download` + WinSxS backup bloat.
- `Simulate-ErrorDumps.ps1` — fake `MEMORY.DMP`, kernel minidumps, WER crash dumps.
- `Simulate-UpgradeLogs.ps1` — fake `$WINDOWS.~BT`, `$WINDOWS.~WS`, Panther setup logs.
- `Invoke-AllSimulations.ps1` — runs all four against one shared root, prints a combined GB summary.
- `Remove-AllSimulations.ps1` — teardown; deletes the sandbox and reports GB freed.

## Usage

```powershell
cd DiskClutterSim
.\Invoke-AllSimulations.ps1
```

By default everything is built under `%TEMP%\DiskCleanupSim` (e.g.
`C:\Users\<you>\AppData\Local\Temp\DiskCleanupSim`). Point your cleanup
script's category checks at that folder (or its subfolders) instead of the
real system paths for the test run.

When done:

```powershell
.\Remove-AllSimulations.ps1
```

## Safety notes

- **Sandbox by default.** No script writes outside `-Root`, and `-Root`
  defaults to a temp folder — never a real Windows system path.
- **Guarded override.** If you deliberately point `-Root` at a real
  sensitive path (`C:\Windows`, `C:\Windows.old`, `$WINDOWS.~BT`,
  `$WINDOWS.~WS`, `Program Files`), every script refuses to run unless you
  pass `-Force` *and* type `YES` at an interactive prompt. This is not
  recommended — real cleanup tools may treat these as live system state.
- **No auto-exec.** Nothing here invokes your cleanup script or
  `cleanmgr.exe` automatically. You run each step yourself.
- **Disk usage.** Files are real (not sparse), so a full run with default
  sizes writes roughly 1.5 GB to disk. Adjust `-SizeMB` per script if you
  need more or less.
- Run PowerShell as Administrator only if your cleanup script itself
  requires elevation to read the sandbox paths you chose; elevation is not
  required for the default `%TEMP%` sandbox.

## Testing your real cleanup script (Add-UnwantedTempFiles + Invoke-DiskCleanup.SafeTest)

Your cleanup script hardcodes absolute paths (`C:\Windows.old`,
`C:\Windows\SoftwareDistribution\Download`, `C:\Windows\Panther`,
`C:\Windows\MEMORY.DMP`, `C:\ProgramData\Microsoft\Windows\WER\...`, etc.).
Junk placed only at `%TEMP%\DiskCleanupSim` is invisible to it. Use this
pair instead:

1. **`Add-UnwantedTempFiles.ps1`** — recreates the same 11 target paths
   your script checks, but relative to a sandbox `-BasePath`
   (default `%TEMP%\DiskCleanupSim`).
2. **`Invoke-DiskCleanup.SafeTest.ps1`** — your script's exact
   detect/remove/report logic, but every target is resolved under
   `-BasePath` too, plus a `-DryRun` switch.

```powershell
.\Add-UnwantedTempFiles.ps1
.\Invoke-DiskCleanup.SafeTest.ps1
```

That runs entirely inside the sandbox — nothing under real `C:\Windows`
or `C:\ProgramData` is touched, and no services are stopped.

**Before running the real thing against `C:\`:**

```powershell
.\Invoke-DiskCleanup.SafeTest.ps1 -BasePath 'C:\' -DryRun
```

This reports what would be deleted and how many GB would be reclaimed,
with zero deletions — review the list. Only then run for real:

```powershell
.\Invoke-DiskCleanup.SafeTest.ps1 -BasePath 'C:\' -TouchServices
```

This requires typing `YES` at a prompt, because it deletes real, live
Windows Update cache, WER crash-report queues, Panther setup logs, and
minidumps, and stops/restarts `wuauserv`, `bits`, `dosvc` around the run.
**Recommendation:** validate on a disposable VM or non-production machine
first — this is a real system change, not a test, once pointed at `C:\`.
