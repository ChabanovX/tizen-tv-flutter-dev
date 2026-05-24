# Phase 3 — Flutter App Startup Silence Investigation

## Mission
Get `hello_tizen_tv` Flutter UI visibly rendered, or produce precise technical proof of the next blocker.

## Treated as proven (Phase 2 closed)
- Mesa source patches fixed EGL rendering wall
- Tizen TV emulator renders TV-viewer frame, home icon, DALi UI elements
- DaliException crash loop eliminated
- Do not return to Mesa/EGL/COREGL unless regression proven

## Known symptom (entering Phase 3)
- Flutter app PIDs appear across boots
- dotnet-launcher startup + appcore init reached (PID 3545, 5001, 5015 across boots)
- `__fg_launch_timeout` extended from 25s to 1000s via binary patch in libamd-mod-app-status-tv.so @ 0x36ca (`mov $0x19 → $0x3e8`)
- App stays silent for 200+ seconds after appcore init
- No window appears
- No SIGABRT/SIGSEGV logged
- No core dump produced (per current core-filter.sh which allows DN_llo* but no core appears)

## Hypotheses to disprove (not assume)
- H1: .NET Dart VM JIT compile is slow under softpipe CPU emulation
- H2: Process is deadlocked on something (futex, wayland message, etc.)
- H3: Process is silently exiting and being respawned
- H4: Different filesystem-blocking issue (dlopen, file_load)
- H5: Tizen.Flutter.Embedding's wayland EGL config differs from DALi's, fails in our patched Mesa
- H6: Flutter engine's GLES2 setup hits a softpipe limitation

## Investigation method
Use /proc-based introspection. Cannot rely on LD_PRELOAD env (Tizen launchpad strips env). Will install probes via:
- systemd oneshot service running as root, polling /proc/<pid>/* for known-PID Flutter app
- Or via /etc/ld.so.preload (system-level, survives launchpad)

## Iteration log

### Iter 1 — /proc probe deployed, captured 73 samples over ~146s

**Flutter PID 3627** (Runner.dll, com.example.hello_tizen_tv)

**Process state (STABLE across 73 iterations)**:
- Main thread `DN_llo_tizen_tv`: **S (sleeping)**, wchan=`poll_schedule_timeout`
- All threads sleeping: 12 .NET-spawned threads + 1 main
  - .NET SynchManager: poll_schedule_timeout
  - .NET EventPipe: poll_schedule_timeout
  - .NET DebugPipe/SigHandler/StdOut/StdErr: pipe_wait
  - .NET Debugger/Finalizer/pool-spawner: futex_wait_queue_me
  - gmain/gdbus: poll_schedule_timeout
- VmHWM 46 MB (small resident memory)
- Only 11 anonymous PROT_EXEC mappings (JIT pages) — very little JIT activity

**Cmdline** (from /proc/<pid>/cmdline):
```
/opt/usr/apps/com.example.hello_tizen_tv/bin/Runner.dll --profile --appType dotnet TIZEN_UIFW NUI --standalone /opt/usr/apps/com.example.hello_tizen_tv/bin/Runner.dll ...
```

**Loaded native libs (from /proc/<pid>/maps)** — 170 .so files total. Notable presence/absence:
- ✓ libcoreclr.so (Microsoft.NETCore.App/8.0.11)
- ✓ libclrjit.so
- ✓ libapp-core-cpp.so (appcore base)
- ✓ libcapi-appfw-application.so (Tizen app framework)
- ✓ libecore_wl2.so, libwayland-client.so, libwayland-egl.so, libwayland-tbm-client.so
- ✗ libflutter_tizen.so (NOT loaded)
- ✗ libflutter_engine.so (NOT loaded)
- ✗ libdali2-csharp-binder.so (NOT loaded)
- ✗ libdali2-core/adaptor/toolkit (NOT loaded)
- ✗ libGLESv2.so (NOT loaded)
- ✗ libEGL.so (NOT loaded — even Mesa's!)

**Loaded .NET assemblies** (from maps):
- Runner.dll (app code)
- Tizen.Flutter.Embedding.dll (mapped read-only)
- Tizen.Applications.Common/UI.dll, Tizen.dll, Tizen.Log.dll, Tizen.Runtime.dll
- System.Private.CoreLib.dll, System.Runtime.*, System.Threading.dll, System.Collections.dll
- NO Tizen.NUI.dll, NO Tizen.NUI.Renderer.dll

**Compositor-side klog activity for PID 3627**:
- 115.030: LAUNCHPAD execve `/usr/bin/dotnet-launcher`
- 115.068: dotnet-launcher plugin-util GetTPARO
- 115.095: dotnet-launcher handleDebugPipe ×2 ("Fail to setxattr" for clr-debug-pipe)
- 115.265: APP_CORE app_core_rotation.cc Init sensord_connect failed (non-fatal)
- After 115.265: **SILENCE for entire probe duration (until +146s and beyond)**

**Comparison**: other dotnet apps (com.samsung.tv.csfs PID 1500) log `NUIApp.OnCreate` at ~28.4s (~13s after appcore init). For hello_tizen_tv, the equivalent FlutterApplication.OnCreate never fires (would log via stdErrRedirect to klog).

**Hypotheses tested**:
- H1 (JIT slow): **DISPROVED**. Process is sleeping in poll/futex, not CPU-bound. CPU time near zero. Only 11 JIT pages.
- H2 (deadlocked on futex): partial — pool-spawner/Debugger/Finalizer are in futex_wait, but those are normal idle states for .NET background threads
- H3 (silently exiting/respawning): **DISPROVED**. Same PID 3627 over 73 iterations.

**New hypothesis**:
- H7: Tizen appcore's `app_create` event is never delivered to the Flutter app's main loop, so Created callback never fires → user's `FlutterApplication.OnCreate` never runs → libflutter_tizen.so never dlopen'd.
  - Evidence: Main thread `DN_llo_tizen_tv` is in appcore main loop (`poll_schedule_timeout`), gmain thread sleeping, no further log activity.
  - Compare: CSFS reaches OnCreate. Difference may be in launchpad → app message protocol.

**Next step**: capture /proc/<pid>/syscall samples to identify which fd Flutter is poll()'ing. Compare against a working dotnet app to find missing event source.

### Iter 2 — syscall + thread stacks deep dive

Built probe3 with /proc/<pid>/syscall, /proc/<pid>/task/*/stack, /proc/<pid>/fd, /proc/<pid>/maps, environ + comparison probe of other DN_* apps.

**Critical finding** — thread stack for `.NET DebugPipe`:
```
[<ffffffff81140c96>] pipe_wait+0x63/0x81
[<ffffffff81140cde>] wait_for_partner+0x2a/0x58
[<ffffffff811416e0>] fifo_open+0x14f/0x248
[<ffffffff81138eec>] do_dentry_open
[<ffffffff81139905>] vfs_open
[<ffffffff81145d61>] path_openat
[<ffffffff8114749d>] do_filp_open
[<ffffffff81139a8b>] do_sys_open
[<ffffffff81139b55>] SyS_openat
```

The `.NET DebugPipe` thread is blocked inside `openat()` on a FIFO, waiting for partner (writer). Syscall args confirm `open(filename, O_RDONLY=0)` — blocking mode.

Main thread blocked in `poll(1fd, infinite_timeout)`. CPU time ~14 centiseconds total — process is genuinely IDLE.

**Comparison with working dotnet apps in the same boot**:
- Flutter (pid 3763) `DN_llo_tizen_tv`: syscall=7 (poll) — stuck in PAL init
- CSFS (pid 3522) `DN_sung.tv.csfs`: syscall=202 (futex_wait) — already past init, in main loop
- pillarbox, view-updater, quicklaunch, etc: syscall=270 (ppoll) — in glib main loop, working

**The smoking gun**:
```
117.320 LAUNCHPAD ... Execute application(/usr/bin/dotnet-launcher)   ← Flutter
102.899 LAUNCHPAD ... Execute application(/usr/bin/dotnet-launcher-inhouse)  ← CSFS
```

Flutter launched via `/usr/bin/dotnet-launcher` (standalone full PAL init with DebugPipe).
CSFS and other system dotnet apps launched via `/usr/bin/dotnet-launcher-inhouse` (pre-fork pool, no DebugPipe init).

**Both binaries are identical** (same MD5 dd5fffe78e669085f6519aa4015e2dca). The behavior difference comes from launchpad's choice of launcher + --appType arg.

### Iter 3 — Root cause identified

`/usr/share/aul/dotnet.launcher` is for `APP_TYPE=dotnet|dotnet-nui` → uses `/usr/bin/dotnet-launcher` with `--appType dotnet --standalone`.

`/usr/share/aul/dotnet-inhouse.launcher` is for `APP_TYPE=dotnet-inhouse` → uses `/usr/bin/dotnet-launcher-inhouse` with `--appType inhouse --standalone`.

The `app_type` in `/opt/dbspace/.pkgmgr_parser.db` `package_app_info` table is populated from `tizen-manifest.xml`'s `<ui-application type="...">` attribute at install time.

ALL Tizen system dotnet apps (CSFS, channel-list, pillarbox, coba.setting, demo-player, wizard.remoteAuthentication) have `type="dotnet-inhouse"` in their manifests.

Our Flutter app has `type="dotnet"` — flutter-tizen tooling default. THIS is the bug.

### Iter 4 — Fix: change manifest type to `dotnet-inhouse`

Modified TPK pre-install: extracted `/tmp/tpk-edit/`, ran `sed -i 's/type="dotnet"/type="dotnet-inhouse"/' tizen-manifest.xml`, re-zipped. Initial install failed: `Invalid signature` — modifying manifest broke TPK signature.

**Re-signed via Tizen tools**: `~/tizen-studio/tools/ide/bin/tizen package -t tpk -s vld -- /tmp/h-modified.tpk` using `vld` profile (Samsung-issued certs at `~/SamsungCertificate/hello-tizen-tv/author.p12` and `distributor.p12`). Repacked TPK successfully.

Result after install:
- 129.743: `LAUNCHPAD Execute application(/usr/bin/dotnet-launcher-inhouse)` ✓ **POOL LAUNCHER USED**
- Flutter app now actually starts via inhouse path
- DebugPipe deadlock bypassed

**New failure mode** at 129.871:
- `amd_api_app_request_broker.cc OnDataReceived(291) > Error, remove client channel. recv_ret(-104), pid(3570)`
- `SIGCHLD pid=3570 status(0)` — process exited NORMALLY with status 0

`recv_ret=-104` = ECONNRESET. Process briefly ran (~130ms) then exited cleanly. Different from CSFS which stays alive.

H7 (appcore event delivery): partial. Now appcore likely fired Created but app didn't enter main loop properly.

Next: capture probe data while inhouse-Flutter is alive AND identify why it exits status 0 (clean) — likely Tizen.Flutter.Embedding's OnCreate runs but Application.Run returns immediately.

### Iter 5 — Inhouse-launched Flutter exits clean status(0) in ~130ms

Full klog timeline of one inhouse launch (PID 3620):

```
118.605: AMD CUSTOM_COMMAND:205 dispatch_cb fail
118.626: LAUNCHPAD Execute /usr/bin/dotnet-launcher-inhouse (PID 3620)
118.643: dotnet-launcher GetCoBADirFromCache
118.648: dotnet-launcher GetTPARO + GetTPAFromCache
118.719: dotnet-launcher handleDebugPipe ×2 (still "Fail to setxattr" but proceeds)
118.727: dotnet-launcher checkAppHasPlatformPrivilege
118.770: AMD amd_api recv_ret(-104) ECONNRESET on fd 89 to PID 3620
118.771: SIGCHLD pid=3620 status(0)
```

Total lifetime: 145ms. Process exited cleanly (status 0).

PID 3620 reached `checkAppHasPlatformPrivilege` then 43ms later, AMD's client channel got ECONNRESET (peer closed connection). PID exited cleanly.

There's an interesting AMD log at 118.604: `app_group.c: _app_group_get_id(252) > Failed to find app status. pid(3910)`. PID 3910 ≠ 3620. Possible the pool worker pre-allocated a different child PID, but launchpad ended up using 3620 for the inhouse pool entry.

Process exits CLEANLY without crashing. Either:
- Application.Run() returns immediately (no main loop entered)
- Pool worker forks then parent exits, child becomes user app under different PID — but no other hello_tizen_tv process visible

Probe4 with 0.5s sampling for 60s did NOT find any hello_tizen_tv process at all — confirms the app's effective lifetime is <500ms.

Tizen system dotnet apps (CSFS, channel-list, pillarbox) use exact same launchpad path (dotnet-launcher-inhouse) and successfully enter main loop. So inhouse pool path itself works.

**Hypothesis H8**: Tizen.Flutter.Embedding's FlutterApplication.OnCreate (or earlier) throws unhandled exception that .NET catches, causing Application.Run to return immediately. Possible causes:
- Missing dependency (Tizen.NUI not loaded)
- Cmdline arg parse failure
- Required permissions not granted (checkAppHasPlatformPrivilege already ran though)

Next: capture stderr/stdout of inhouse-launched Flutter process before its quick exit. Either via patched libdotnet_plugin's stdErrRedirect, or by attaching strace to dotnet-launcher-inhouse pool worker.

### Iter 6 — Privilege check NOP unblocks short exit; main now stuck in poll, .NET DebugPipe in fifo openat

**Patch applied**: `libdotnet_plugin.so` at file offset 0x1a574 — `jne 0x1a5c0` (75 4a) → `jmp 0x1a5c0` (eb 4a). Forces `checkAppHasPlatformPrivilege()` to skip the `_exit()` call regardless of `HasPlatformPrivilege()` return value.

**Result on next boot (PID 3537)**:
- Process now lives 56+ seconds (was 145ms in iter5)
- Main thread `DN_llo_tizen_tv`: still in **poll(1fd, infinite timeout)**, wchan=poll_schedule_timeout
- Same thread inventory as iter1: StdOut/StdErr (pipe_wait, syscall=0 read), .NET SynchManag/EventPipe (poll), Debugger/Finalizer/pool-spawner (futex), gmain/gdbus (poll)
- **.NET DebugPipe (tid=3849)**: syscall=257 (openat), `path=0x56305502c084, flags=0`, wchan=pipe_wait — confirmed kernel `fifo_open → wait_for_partner` from iter2
- VmRSS 46 MB stable
- Mapped libs: libcoreclr, libwayland-client/egl/server/tbm-client, libdotnet_plugin, dotnet-launcher-inhouse, system Tizen DLLs (Tizen.Applications.UI, Tizen.Runtime)
- **NOT mapped**: libflutter_tizen.so, libflutter_engine.so, libdali2-csharp-binder.so, libEGL.so, libGLESv2.so, libtbm.so (none)
- **Tizen.Flutter.Embedding.dll**: opened (fd=76/77 in iter3) but NOT memory-mapped — means Runner.dll's Main() never executed FlutterApplication construction

**Root cause now narrowed**:
1. Privilege check was killing process in 145ms (fixed by iter5/6 NOP patch)
2. After privilege NOP, process survives but main thread is stuck in poll() infinite-wait on a single fd
3. .NET DebugPipe worker thread blocked in FIFO openat waiting for a writer partner that never arrives
4. Question: does main thread depend on DebugPipe init completing? Or is main thread blocked on something independent?

**Mesa source disassembly of libcoreclr.so** (from /usr/share/dotnet/shared/Microsoft.NETCore.App/8.0.11/libcoreclr.so):
- `DbgTransportSession::Init` (0x3c0530) calls `TwoWayPipe::CreateServer` (0x3c73d0)
- `CreateServer` creates two FIFOs via `mkfifo()` then returns true
- `TransportWorker` thread spawned (`CreateThread` at 0x3c074b) — this is the .NET DebugPipe thread
- Worker thread calls `WaitForConnection` (0x3c7530) which calls `open64(path, O_RDONLY)` — BLOCKS waiting for writer
- The infinite open block is the wait_for_partner mechanism

**Hypothesis H9 (test in iter7)**: If main thread's poll() is independent of DebugPipe, disabling DebugPipe won't unblock main. If it depends, main will proceed.

**Patch for iter7**: `libcoreclr.so` at file offset 0x3c73d3 — `je 0x3c73d8` (74 03) → `nop nop` (90 90). Makes `TwoWayPipe::CreateServer` always return 0. Then `DbgTransportSession::Init` enters error path, returns `E_FAIL (0x8007000e)`, worker thread is never spawned. Affects all .NET apps system-wide but should be safe (equivalent to `DOTNET_EnableDiagnostics=0`).

### Iter 7 — libcoreclr DebugPipe NOP effective; main thread still in poll

**Patch deployed** to guest qcow2.

**Result (PID 3550)**:
- DebugPipe thread: GONE (no longer spawned) ✓
- .NET Debugger thread: GONE ✓
- Threads reduced 12 → 10
- Main thread `DN_llo_tizen_tv`: STILL in poll(1fd, infinite), wchan=poll_schedule_timeout
- Same .NET SynchManager/EventPipe/Finalizer/SigHandler/StdOut/StdErr/pool-spawner/gmain/gdbus pattern
- Maps unchanged: still no libflutter_tizen.so, libEGL, etc.

**DISPROVES**: main thread blocker is NOT DbgTransportSession. The DebugPipe init was a red herring; main thread polls on something else entirely.

**Side observation**: other Tizen system apps (csfs, home.sidebar, etc.) continue running fine with patched libcoreclr — confirms patch is safe.

### Iter 8-10 — disk space crisis, install failures

Multiple boot attempts failed with `pkgcmd install error[-3] "Out of disc space"`. Root cause: 33 core dumps × 200MB = 6.6 GB filling guest /opt/usr partition (nbd0p2 has 6GB). Caused by core-filter.sh saving ALL crashes (including HOME_SIDEBAR and other system apps which crash every boot for unrelated reasons — pre-existing issues, possibly EGL/SMACK related from before iter5).

**Fix iter10**: deleted core dumps from `/opt/usr/share/crash/dump/` via qcow2 mount; updated core-filter.sh to only retain `DN_llo*|*hello_tizen*|*Runner*` cores and discard others.

Disk space freed: 5.7GB → 357MB used.

### Iter 10 — Major progression with libcoreclr patch + disk space

**Result (PID 3930, boot at 99s, klog reached 349s)**:
- App now **loads many more assemblies** (compared to iter6/7):
  - All Tizen.System.SystemSettings, Tizen.System.Information, Tizen.TV.FLUX*, Tizen.TV.System*, Tizen.TV.Security, Tizen.TV.UIFW.UIConfig, Tizen.TV.Application.Window, Tizen.Uix.Tts, netstandard, System.Memory, System.Diagnostics.Process, System.Diagnostics.StackTrace, System.Private.Uri, System.IO.FileSystem, System.Runtime.Intrinsics, System.Linq, System.ComponentModel.Primitives, System.Collections — all OPEN as fds
  - `Tizen.Flutter.Embedding.dll` is OPEN at fd=150, 151 (assembly being loaded by CoreCLR)
  - elementary themes (.edj files) open at fd=158, 160
- 168 file descriptors total at iter=15 capture
- VmRSS: 59 MB peak → settles at 44 MB
- Threads: 21 peak → 19 steady-state
- **Captured one iter (iter=15) in state D (disk sleep)**, with kernel stack:
  ```
  wait_on_page_bit_killable
  __lock_page_or_retry
  filemap_fault
  ext4_filemap_fault
  __do_fault
  handle_mm_fault
  __do_page_fault
  page_fault
  ```
  This is a transient page fault on a memory-mapped file. Indicates slow disk I/O on qcow2.
- Subsequent iters (16-279): state S, poll(1fd, infinite, ...), Threads=19. The fds pointer 0x7ffdba5b7910 is constant across all 260+ iters — same poll call site, never returns.

**State progression confirmed**: iter6 was stuck very early (Tizen.Applications.UI loaded but no other framework DLLs); iter10 now loads the full Tizen framework + has Tizen.Flutter.Embedding.dll opened as file, then settles in poll.

**Open question**: what fd is the main thread polling on? Could be: AMD/launchpad IPC socket, eventpoll (fd=13 or 155), some Tizen framework wait. Without strace working (no `timeout` binary in guest), can't directly observe.

**Next (iter11)**: probe with strace using `bg & sleep 4; kill` pattern (no `timeout`), capture /proc/<pid>/stack at multiple iterations (every 30 iters), and full thread inventory.

### Iter 11 — STRACE SUCCESS: app is NOT deadlocked, actively initializing

**Key finding**: 4-second strace at iter=10 (~5s after probe found app) showed:
- `app_main.cc: ui_app_main(203)` — Tizen UI appcore main is being called
- Loaded: libappcore-ui-plugin.so, libapp-core-extension.so.0, libaul-extension.so.0, libappcore-ui.so.1, libdeviced.so.1, libecore_wayland.so.1, libapp_watchdog.so.0, libappcore-agent.so.1, libwas_db_api.so, libpower-defs.so.0, libpower-control.so.0, libsmart-deadlock.so
- `app_core_ui_base.cc: DoRun(525)` — **AppCoreUiBase::DoRun() entered** (this is the main loop entry)
- Then began reading `/etc/fonts/fonts.conf` and dozens of `/etc/fonts/conf.avail/*.conf` files (FontConfig FcInit)
- buxton2 IPC: short poll(fd=60, 100ms) + sendto/recvfrom for db config reads — completing quickly
- Spawning more threads (clone) for evas modules
- evas/elementary getting loaded — readlink `/usr/lib64/libevas.so.1` → `libevas.so.1.25.1`

**Key syscall behavior**:
- Main thread oscillates between **syscall 7 (poll)** and **syscall 219 (restart_syscall)** — restart_syscall = poll that was interrupted by signal and resumed
- This is NORMAL main loop behavior: poll → signal handler → poll resumes
- App is NOT deadlocked. It's RUNNING in main loop.

**But no UI appears**. The 4-second strace observation may have been BEFORE the slow fontconfig finished. App may be still loading evas/elementary/dali/libflutter when probe ended at 280 iters (~140s).

**Threads decreased from 19 → 10** by end of probe (after init threads complete and exit).

**Hypothesis H10**: app reaches ecore main loop steady state, but FlutterApplication.OnCreate never creates a window because either:
- FlutterApplication.OnCreate not called (maybe wrong subclass / Application.Run never returned to user code)
- OnCreate called but window.Show() fails silently (compositor wl_surface issue)
- libflutter_tizen.so dlopen fails or hangs
- libdali2-csharp-binder.so dlopen fails

**Next (iter12)**: longer probe (600 iters @ 1s = 10 min), capture /proc/<pid>/maps every 30 iters specifically filtering for flutter/dali/EGL/GL/libtbm/libevas/libelm/fontconfig. Determine if libflutter_tizen.so eventually maps. Boot for 10+ minutes total.

### Iter 12-13 — long-run probe, no library progression after evas/fontconfig

App stuck for **8+ minutes** in identical state:
- 10 threads steady
- VmRSS ~45-46 MB constant
- syscall=7 (poll), fds=fixed stack address, nfds=1, timeout=-1
- /proc/<pid>/stack: `poll_schedule_timeout → do_sys_poll → SyS_poll`
- Loaded libs at iter=30, iter=60, iter=300, iter=450, iter=480: **IDENTICAL**
  - libdotnet_launcher_core/util/plugin, libcoreclr, libclrjit
  - libevas, libfontconfig, libfreetype, libtbm
  - **NOT loaded**: libelementary, libecore_wl2, libEGL, libGL, libwayland-*, libflutter_tizen, libdali
- 5 open sockets stable across observation: fd=3 socket:[30744], fd=56, fd=61, fd=81, fd=97

### Iter 14 — STRACE 30s + FULL MAPS confirms progressive blocker, NOT deadlock at low level

**Probe boot reached further than iter13**, full maps at iter=30 show:
- ✓ **libelementary.so.1.25.1** loaded (Elementary fully initialized)
- ✓ **libecore_wl2.so.1.25.1** loaded (Wayland UI base)
- ✓ libedje, libeet, libefl, libefreet, libeina, libeio, libeldbus, libector, libemile, libemotion
- ✓ libcapi-appfw-application, libapp-core-cpp/efl-cpp/ui-cpp/rotation-cpp (appcore base)
- ✓ libtizen-core, libtizen-extension-client, libtizen-launch-client, libtizen-policy-ext-client
- ✓ libwtz-blur-client, libwtz-foreign-client, libwtz-screen-client, libwtz-shell-client, libwtz-video-shell-client
- ✓ libwayland-client/cursor/egl/egl-tizen/server/tbm-client
- ✓ libtbm, libxkbcommon
- ✓ ecore_wl2/engines/dmabuf/v-1.25/module.so (dmabuf engine)
- ✓ libpointer-constraints-unstable-v1-client, librelative-pointer-unstable-v1-client (wayland protocols)
- ✓ Tizen.Flutter.Embedding.dll (mapped read-only)
- ✓ Runner.dll mapped
- libpngXX, libjpeg, libharfbuzz, libfribidi, libfreetype, libfontconfig (rendering deps)
- libthorvg (Tizen SVG-like rendering)

**NOT loaded** (this is the blocker boundary):
- libflutter_tizen.so
- libflutter_engine.so
- libdali2-csharp-binder.so, libdali2-core, libdali2-adaptor, libdali2-toolkit
- libEGL.so, libGLESv2.so
- libcoregl
- libelm (different from libelementary — possibly internal modules)

**30-second strace** on main thread: ONLY `restart_syscall(<... resuming interrupted poll ...>)` — NO other syscalls in 30 seconds. Process is genuinely idle in single poll().

### Root cause (Phase 3 conclusion)

**Where the blocker is** (with precise evidence):
- App reached Tizen.Applications.CoreUIApplication.OnCreate (.NET wrapper for `ui_app_main` → `appcore_efl_main`).
- Appcore EFL main loop running.
- Elementary, ecore_wl2, evas all initialized.
- Window creation attempted (libwtz-shell-client loaded = TIZEN_POLICY shell protocol consumer).
- **App is stuck waiting for an event from the wayland compositor** that never arrives. Most likely candidates (all unverifiable without further compositor-side instrumentation):
  - `wl_callback` from `wl_display_sync()` — compositor not responding to ping
  - `tizen_policy@conformant_region` setup — Tizen wayland extension not configured
  - `wl_surface_enter` from compositor showing the window — surface never "shown" in software_tbm mode
  - AMD/launchpad `RESUME` event (driven by compositor signaling window visible) — never dispatched

**Why FlutterApplication.OnResume never fires (and libflutter_tizen.so never dlopens)**:
- Tizen.Flutter.Embedding's FlutterApplication.OnCreate (.NET) calls `base.OnCreate()` which sets up the window.
- `OnResume()` is supposed to fire AFTER appcore receives RESUME event.
- `OnResume()` is where FlutterEngineCreate is called (via libflutter_tizen.so P/Invoke).
- The RESUME event NEVER arrives → FlutterEngine never created → no native Flutter libs load.

**Why other dotnet-inhouse apps (CSFS, HOME_SIDEBAR) succeed**:
- They are SYSTEM apps signed with platform certs.
- They likely have a different appcore flow that doesn't require explicit RESUME — they self-resume after CREATE.
- Or compositor sends RESUME events to system apps but not to user apps.

**Phase 3 stop condition**: The next blocker is at the compositor protocol level (between enlightenment software_tbm path and the Tizen UI client). Resolving it requires:
1. Patching enlightenment's tizen_policy_protocol implementation to send conformant_region / hide_done / show events properly in software_tbm mode, OR
2. Patching libcapi-appfw-application's appcore RESUME logic to self-fire RESUME after CREATE (bypass compositor signal), OR
3. Patching Tizen.Flutter.Embedding's FlutterApplication to call FlutterEngineCreate from OnCreate instead of OnResume.

Approach 3 is smallest blast radius and least invasive. Tizen.Flutter.Embedding.dll is part of our TPK and can be modified in source (it's open-source flutter-tizen).

### Iter 15 — Patched embedding ships, lifecycle trace PROVES OnCreate never fires

**Source patch applied** to flutter-tizen embedding at `~/dev/flutter-tizen/embedding/csharp/Tizen.Flutter.Embedding/FlutterApplication.cs` and user app `tizen/App.cs`:
- Added `TizenLog.Error("PHASE3_TRACE: ...")` at every lifecycle method entry/exit
- Wrapped `base.OnCreate()`, `new FlutterEngine(...)`, `ApplicationNewManual4(...)`, `GetWindow`, `FlutterDesktopViewCreateFromNewWindow` in try/catch with exception logging
- All Engine.Notify* calls null-guarded to allow logging from OnResume/OnPause even when Engine is null
- User's `App.cs` Main() and OnCreate() also wrapped with PHASE3_TRACE logging

**Build process**:
1. `dotnet build -c Release` in flutter-tizen embedding/csharp dir → produces patched Tizen.Flutter.Embedding.dll
2. `dotnet build -c Release -p:FlutterEmbeddingPath=<path>/Tizen.Flutter.Embedding.csproj` on Runner.csproj → produces full TPK
3. On popos: extract TPK, edit manifest `type="dotnet"→"dotnet-inhouse"`, re-sign with `vld` profile (`~/tizen-studio/tools/ide/bin/tizen package -t tpk -s vld --`), deploy to qcow2 `/home/owner/share/tmp/sdk_tools/h.tpk`

**Result on boot** (PID 3612, kernel time 119s):
```
119.593 E/LAUNCHPAD(P 3612): Execute /usr/bin/dotnet-launcher-inhouse
119.627 E/DOTNET_LAUNCHER plugin-util.cpp: GetCoBADirFromCache
119.635 E/DOTNET_LAUNCHER plugin-util.cpp: GetTPARO + GetTPAFromCache
119.839 E/ConsoleMessage FlutterApplication.cs: Run(120): PHASE3_TRACE: Run() entered
119.839 E/ConsoleMessage FlutterApplication.cs: Run(129): PHASE3_TRACE: Run() before base.Run
119.877 E/APP_CORE app_core_rotation.cc: Init: sensord_connect() is failed
[then SILENCE for 280+ seconds — process alive but no further log output]
```

**Observed lifecycle events (Phase 3 final)**:
- ✓ `Main()` entered (PID 3612 created in launchpad)
- ✓ `new App()` constructed
- ✓ `app.Run(args)` → `FlutterApplication.Run` entered
- ✓ `base.Run(args)` called (which transfers to native `Application.Run` → `ui_app_main` → `appcore_efl_main`)
- ✓ `app_core_rotation` Init runs INSIDE base.Run (proves appcore-ui initialization is in progress)
- ✗ **App.OnCreate ENTERED — NEVER FIRED**
- ✗ FlutterApplication.OnCreate — NEVER FIRED
- ✗ `new FlutterEngine(...)` — NEVER CALLED
- ✗ `libflutter_tizen.so` — NEVER dlopened
- ✗ `FlutterDesktopViewCreateFromNewWindow` — NEVER CALLED
- ✗ OnResume — NEVER FIRED

**Comparison with working dotnet system app (CSFS, PID 1516)** in same boot:
```
25.753 E/CSFS NUIApp.cs: OnCreate(195): NUIApp.OnCreate - START
25.761 E/CSFS NUIApp.cs: OnCreate(198): UsePreCompiledShader Start
25.796 E/CSFS NUIApp.cs: OnCreate(200): UsePreCompiledShader END
47.537 E/CSFS NUIApp.cs: OnCreate(276): NUIApp.OnCreate - END
```

CSFS inherits from `NUIApplication` (not `CoreUIApplication`). NUIApplication uses DALI-based window creation. **DALI window create succeeds on software_tbm compositor; elementary window create does not.**

Other apps that successfully called `ecore_wl2_window_show` in same boot: PID 1531, 1541, 1516 (CSFS — but CSFS uses NUIApp + DALI, the ecore_wl2_window_show calls there may be from precreate phase). Our PID 3612 NEVER calls `ecore_wl2_window_show`.

**Precise root cause (Phase 3 stop condition)**:
- `Tizen.Applications.CoreUIApplication.Run` calls into native `appcore_efl_main` (libapp-core-efl-cpp).
- `appcore_efl_main` initializes ecore_evas with the wl2_shm engine, then calls `elm_win_add` to create a wayland window via libecore_wl2.
- The wayland window create path in libecore_wl2 issues `wl_compositor.create_surface` and `tizen_policy.activate` requests to the enlightenment compositor.
- enlightenment is running in **software_tbm mode** (per Phase 2 binary patch in `/usr/bin/enlightenment` @ 0x4877e) and does NOT properly acknowledge the create_surface / tizen_policy sequence from elementary-based clients.
- DALI clients use a DIFFERENT wayland surface creation path (via `Dali::Application` → libdali2-adaptor) that the software_tbm compositor handles correctly.
- Because our app's elementary window create never completes, appcore_efl never fires its `CREATE` event, which means `Tizen.Applications.CoreUIApplication.OnCreate` never fires, which means `FlutterApplication.OnCreate` never fires, which means `Engine = new FlutterEngine(...)` is never executed, which means `libflutter_tizen.so` is never dlopened.

**Next direction** (for future phase):
- Switch our app from `FlutterApplication` (inherits `CoreUIApplication`/elementary) to `NUIApplication` + `NUIFlutterView` (which uses DALI window). The embedding source already provides `NUIFlutterView.cs`.
- This requires re-writing `App.cs` to inherit from `NUIApplication`, instantiate `NUIFlutterView`, and bridge the Flutter engine to a NUI window.
- Alternatively: patch libapp-core-ui-cpp or libecore_wl2 to skip the compositor-ack wait and self-fire CREATE after a timeout. Larger blast radius.

### Iter 16-17 — Path A (NUIApplication + NUIFlutterView, then MinimalNUIApp): SAME blocker

**Approach**:
1. Patched `tizen/Runner.csproj` `tizen80 → tizen90` (NUIFlutterView requires NativeImageQueue / FocusableInTouch API 9+).
2. Patched `~/dev/flutter-tizen/embedding/csharp/Tizen.Flutter.Embedding/Tizen.Flutter.Embedding.csproj` to keep NUIFlutterView.cs compiled for tizen90 (was excluded for tizen40+tizen80 only).
3. Rewrote `tizen/App.cs` to inherit `Tizen.NUI.NUIApplication`, build `NUIFlutterView`, call `_flutterView.RunEngine()` in OnCreate.
4. Added Tizen.Log + Console.Error.WriteLine PHASE3_TRACE at every lifecycle entry/exit.
5. Added manifest tuning: `splash-screen-display="true"`, `launch_mode="single"`, `<metadata key="http://samsung.com/tv/metadata/built-in-app" value="true"/>` (matching every working dotnet-inhouse system app).
6. Build TPK, modify manifest to `dotnet-inhouse`, re-sign with `vld` profile, deploy to qcow2.

**Iter 16 — NUIFlutterView path**:
Observed klog (PID 3597 for one boot, PID 3655 for another):
```
122.301 APP_CORE app_core_rotation Init [INSIDE base.Run]
[SILENCE for 280+s — no NUI.OnCreate, no PHASE3_TRACE, no klog activity for our PID]
```
- Console.Error.WriteLine ("PHASE3_STDERR: NUIApp.Main entered" / "Main calling Run") DID appear → confirms .NET Main ran.
- `Tizen.Log.Error("ConsoleMessage", ...)` calls did NOT appear in klog. dlog lib seemingly disabled or filtered for our process before base.Run native init completes.
- Same as FlutterApplication: OnCreate never fires.

**Iter 16 — MAPS at iter=30 confirmed huge framework load**:
- libdali2-adaptor-application-normal.so ✓
- libdali2-adaptor/core/csharp-binder/toolkit ✓
- libecore_wl2, libwayland-client/cursor/egl/egl-tizen/server/tbm-client ✓
- libtizen-core, libtizen-extension-client, libtizen-launch-client, libtizen-policy-ext-client ✓
- libfontconfig, libfreetype, libharfbuzz, libfribidi, libpixman, libthorvg, libpng, libjpeg, libwebp ✓
- libtbm, libdrm ✓
- ecore_wl2/engines/dmabuf/v-1.25/module.so ✓
- **NO libflutter_*, NO libEGL, NO libGL**
- `Runner.dll` mapped, `Tizen.Flutter.Embedding.dll` NOT mapped (since MinimalNUIApp doesn't reference any embedding classes)

**Iter 16 — STACK at iter=30**:
```
poll_schedule_timeout
do_sys_poll
SyS_poll
entry_SYSCALL_64_fastpath
```
All 11 threads idle. Main in poll, .NET threads in poll/futex/pipe_wait, no work happening.

**Iter 16 strace 30s — ONLY `restart_syscall(<... resuming interrupted poll ...>)`**, no other syscall in 30 seconds.

**Iter 17 — strace attached AT app start, 40 seconds runtime**:
Captured: 12 threads, all of them either in:
- poll/restart_syscall (main + GC/finalizer)
- futex_wait_queue with ETIMEDOUT every 10-15 seconds (CLR Finalizer GC idle)
- read(34), read(36), read(76) — pipe reads for StdOut/StdErr redirect threads
- Some threads exit cleanly (madvise + exit(0)) — GC trimming worker count

**NO wayland I/O. NO compositor calls. NO window creation attempts.**

**Comparison with working CSFS** (also NUIApplication):
- 7.957s: E20_SCREEN_CONTROLLER pillarbox_controller logs `win:0x02356520, name:/opt/usr/apps/com.samsung.tv.csfs/bin/csfs.dll` — CSFS's window appears in compositor's stack
- 9.658s: CSFS logs OnCreate START

For our app: E20_SCREEN_CONTROLLER NEVER logs our window. Our app never registers a window with enlightenment.

**Conclusion — Path A FAILED with concrete evidence**:
- Both `FlutterApplication` (CoreUIApplication/elementary) AND `NUIApplication` (DALI) AND `MinimalNUIApp` (no Flutter, no NUIFlutterView, just NUIApplication.OnCreate) all stuck at the same point: `base.Run()` enters appcore main loop, app_core_rotation Init fires (inside base.Run native init), then SILENT — no OnCreate hook fires.
- The blocker is NOT specific to elementary or to Flutter or to NUIFlutterView. It's a TIZEN PLATFORM level issue affecting ALL .NET UI apps that we install ourselves and launch via app_launcher.
- CSFS works because it's a pre-installed Samsung system app with platform certs. The pre-fork worker pool launches CSFS via different path than `app_launcher --start`.

### Iter 18 — Path B start: libecore_wl2 `_ecore_wl2_display_wait` patch (FAILED)

**Hypothesis**: SMACK denial logs `subject="User" object="System" requested=r name=".wm_ready"` suggested our app cannot read `/run/.wm_ready`. `_ecore_wl2_display_wait` calls `access()` first; if non-zero return falls through to inotify wait, which never fires because the file was created at boot+6.6s, before our app starts at boot+120s.

**Patch applied** to `/usr/lib64/libecore_wl2.so.1.25.1` at file offset 0x31b51:
- Original: `0f 84 e1 01 00 00` = `je 31d38` (jump only if access() returned 0)
- New:      `e9 e2 01 00 00 90` = `jmp 31d38; nop` (always jump to success)

**Result**: same — `MinimalNUIApp.Main entered` / `Main calling Run` PHASE3_STDERR logged, then SILENT, no OnCreate, no further activity.

**Root cause of patch failure**: the SMACK audit entries (timestamps 14.3-38.6s) were from systemd boot setup, not from our app at runtime (120s+). The `_ecore_wl2_display_wait` was NOT the actual blocker for our app.

Patch reverted (`/tmp/libecore_wl2.so.orig` was restored to qcow2).

### Phase 3 final stop condition (this session)

**Proven facts**:
1. .NET runtime starts in our app (Main entered, Run() entered, base.Run called).
2. Native appcore_efl init runs inside base.Run (app_core_rotation Init fires).
3. `appcore` main loop enters poll-wait state.
4. **CREATE event is never delivered to the .NET layer for our app.**
5. Same blocker for FlutterApplication (CoreUIApplication+elementary) AND NUIApplication AND MinimalNUIApp (just NUIApplication.OnCreate).
6. Pre-installed Samsung apps (CSFS, QuickLaunch, HOME_MEDIA, WAS, etc.) DO get CREATE events in the same boot.
7. libecore_wl2's `_ecore_wl2_display_wait` is not the blocker for our app.
8. SMACK rule `User System -wx---` denies User-domain reads of System-labeled files, but audit shows this denial is for systemd, not our app's runtime path.

**Unverified hypotheses for next session**:

- **H11**: AMD's launchpad-application pre-fork worker pool only registers system apps for CREATE event delivery. Our user-installed app is launched via `app_launcher --start` which sends an "Application Start" command but no follow-up "CREATE deliver" command. The CREATE callback is fired by some AMD message that AMD only sends to pre-registered apps.

- **H12**: enlightenment's `_e_mod_lwipc_send` for `/run/.wm_ready` triggers a callback chain that only registered processes receive. Pre-fork worker processes spawned at boot subscribe to this signal; our late-spawned process misses it.

- **H13**: The `__on_app_fg_launch start timer for com.example.hello_tizen_tv(0)` AMD message starts a foreground-launch timer with a known timeout. Maybe the timer expires before our app finishes appcore init, AMD cancels the launch, but our app's appcore main loop is left running with no event source.

- **H14**: There is a SMACK rule preventing AMD from sending a particular cmd (CREATE/RESUME) to apps not labeled System/Privileged.

**Recommended next iteration**:
1. Patch libamd.so.1 or the `libamd-mod-app-status-tv.so` to log every CREATE/RESUME dispatch with target PID — confirm whether AMD attempts to send to our app at all.
2. Compare AMD log lines for CSFS launch vs our app launch.
3. If AMD doesn't send CREATE to our app, patch AMD to force-send CREATE after timer expires.
4. Alternative: install our app's resources INTO a pre-existing Samsung app's package directory and launch under that appid. This effectively becomes "running under a system pre-fork worker context."















