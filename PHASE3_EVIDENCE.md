# Phase 3 Evidence Index

Concrete artifacts that prove what's been observed.

## Source patches (in-tree, this repo)

| Iter | File | What changed |
|---|---|---|
| 15 | `tizen/App.cs` | PHASE3_TRACE lifecycle logging (Console.Error + Tizen.Log) |
| 17 | `tizen/App.cs` | Switched FlutterApplication → NUIApplication, then to MinimalNUIApp (no NUIFlutterView) |
| 17 | `tizen/Runner.csproj` | `tizen80 → tizen90` (NUIFlutterView requires API 9) |
| 17 | `tizen/tizen-manifest.xml` | Added `splash-screen-display="true"`, `launch_mode="single"`, `built-in-app=true` metadata |

## Source patches (companion repo `~/dev/flutter-tizen`)

| Iter | File | What changed |
|---|---|---|
| 15 | `embedding/csharp/Tizen.Flutter.Embedding/FlutterApplication.cs` | PHASE3_TRACE lifecycle logging at every override |
| 17 | `embedding/csharp/Tizen.Flutter.Embedding/Tizen.Flutter.Embedding.csproj` | Removed `tizen80` from `<Compile Remove="NUIFlutterView.cs">` condition (kept `tizen40`) |

## Binary patches deployed to qcow2 emulator image (`~/tizen-studio-data/emulator/vms/hello_tv/emulimg-hello_tv.x86_64`)

| Iter | Library | Offset | Bytes (orig → new) | Effect |
|---|---|---|---|---|
| 5 | `/usr/lib64/libdotnet_plugin.so` | 0x1a574 | `75 4a → eb 4a` | `jne → jmp`: `checkAppHasPlatformPrivilege` always success path, no `_exit()` |
| 7 | `/usr/share/dotnet/shared/Microsoft.NETCore.App/8.0.11/libcoreclr.so` | 0x3c73d3 | `74 03 → 90 90` | `je → nop nop`: `TwoWayPipe::CreateServer` always returns 0, no DebugPipe worker spawned |
| 18 | `/usr/lib64/libecore_wl2.so.1.25.1` | 0x31b51 | `0f 84 e1 01 00 00 → e9 e2 01 00 00 90` | `je → jmp`: `_ecore_wl2_display_wait` skips access() check. **REVERTED** — didn't help. |
| 19 | `/usr/share/appcore/plugins/libappcore-ui-plugin.so` | 0x6db6 | `e8 e5 d2 ff ff → 90 90 90 90 90` | NOP out `call LwipcWaitEvent@plt` in `__init_wayland`. **REVERTED** — didn't help. |

Pre-Phase-3 (Phase 2) binary patches still in effect:
- `/usr/bin/enlightenment` @ 0x4877e: 6-byte NOP forces software_tbm path → compositor reaches MAIN LOOP.
- Multiple Mesa libEGL.so patches (forced ForceSoftware, swrast path, relaxed multisample criteria).

## Native libraries pulled from guest for analysis

In `/tmp/` on `popos`:
- `libdotnet_plugin.so` (+ `.bak`, `.orig`)
- `libdotnet_launcher_core.so`, `libdotnet_launcher_util.so`
- `libcoreclr.so` (+ `.iter5` backup)
- `dotnet-launcher-inhouse`
- `libapp-core-cpp.so`, `libapp-core-ui-cpp.so`, `libappcore-common.so`, `libappcore-plugin.so`, `libappcore-ui-plugin.so`
- `libcapi-appfw-application.so`
- `libdali2-adaptor.so`
- `libecore_wl2.so` (+ `.orig`)
- `amd`, `libamd.so`

## Probe scripts deployed to `/usr/local/bin/flutter-probe.sh` (systemd `flutter-probe.service`)

| Iter | Variant | What it captures |
|---|---|---|
| 3-4 | full /proc dump every 0.5s | status, syscall, wchan, fd list, maps |
| 6 | + Thread name + stack | per-thread state |
| 7 | smaller, focused | post-libcoreclr DebugPipe NOP |
| 11 | + 4s strace at iter=10 | confirmed ui_app_main DoRun + fontconfig |
| 14 | + ALL MAPS at iter=30, 30s strace | confirmed full elementary stack loaded, no syscall activity |
| 16 | iter14 + filter `pgrep -x DN_llo_tizen_tv` | reliable PID identification |
| 17 | early strace immediately when PID appears | confirmed no wayland I/O |

Probe logs stored in qcow2 `/opt/usr/home/owner/share/tmp/sdk_tools/flutter_probe_iter*.log`.

## Critical klog excerpts (proof artifacts)

### Iter 15 — FlutterApplication (CoreUIApplication+elementary) trace

```
121.999 E/LAUNCHPAD(P 3614): app_executor.cc: OnExecution: Execute application(/usr/bin/dotnet-launcher-inhouse)
122.030 E/DOTNET_LAUNCHER(P 3614): plugin-util.cpp: GetCoBADirFromCache
122.036 E/DOTNET_LAUNCHER(P 3614): plugin-util.cpp: GetTPARO + GetTPAFromCache
122.314 E/DOTNET_LAUNCHER(P 3614, T 3893): log.cc: stdErrRedirect: PHASE3_STDERR: NUIApp.Main entered
122.332 E/DOTNET_LAUNCHER(P 3614, T 3893): log.cc: stdErrRedirect: PHASE3_STDERR: NUIApp.Main calling Run
122.363 E/APP_CORE(P 3614): app_core_rotation.cc: Init: sensord_connect() is failed
[NO further log for PID 3614 over 280+ seconds. OnCreate, OnResume, OnPause, OnTerminate all never fire.]
```

### Iter 16-17 — NUIApplication / MinimalNUIApp same pattern

Identical klog timeline. `MinimalNUIApp` (just inherits `Tizen.NUI.NUIApplication`, no Flutter, no `NUIFlutterView`, only logs `OnCreate entered`) **STILL** does not fire OnCreate.

### Working comparison — CSFS (NUIApplication, same boot)

```
7.957 E/E20_SCREEN_CONTROLLER(P 1767): e_mod_pillarbox_controller.cpp: PrintStack:
       win:0x02356520, name:/opt/usr/apps/com.samsung.tv.csfs/bin/csfs.dll
       [compositor enlistens CSFS's window]
9.658 E/CSFS(P 1497): NUIApp.cs: OnCreate(195): NUIApp.OnCreate - START
44.939 E/CSFS(P 1497): NUIApp.cs: OnCreate(276): NUIApp.OnCreate - END
```

For our app: E20_SCREEN_CONTROLLER never lists `com.example.hello_tizen_tv` in its window stack. Compositor never sees our window.

### Iter 17 — 40-second strace of our app at runtime ~5s onwards

12 threads. All threads either in:
- `restart_syscall(<... resuming interrupted poll ...>)` (main thread + .NET poll threads)
- `futex(FUTEX_WAIT_PRIVATE, ...)` cycling with 15-second timeouts (CLR Finalizer GC idle)
- `read(34, ...)`, `read(36, ...)`, `read(76, ...)` (StdOut/StdErr pipe redirect threads)
- Some threads cleanly `exit(0)` (GC trimming worker pool)

**ZERO wayland I/O, ZERO compositor calls, ZERO window-create activity. ZERO file opens or reads (beyond pipe waits).**

## Commits

| Hash | Subject |
|---|---|
| c0b4afe | phase3: Path A NUIApplication exhausted — same OnCreate-never-fires blocker |
| ab63aee | fix(phase3): iter15 lifecycle trace patch proves OnCreate never fires |
| 736b13b | docs(phase3): iter6-14 — Flutter native libs never load; blocker at compositor RESUME event |
| 6dfc66f | docs(phase3): iter5 — inhouse-launched Flutter exits clean status(0) in 145ms |
| ba1f68c | docs(phase3): iter1-4 root cause — manifest type=dotnet sends app through standalone PAL init |
| 5c46212 | docs(phase3): iter1 — /proc probe disproves JIT-slow hypothesis |
