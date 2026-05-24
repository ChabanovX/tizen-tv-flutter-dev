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

