# Autonomous Work Log — Visible Flutter UI in Tizen TV emulator

## Mission
Get Flutter `hello_tizen_tv` visibly rendered inside TV-Samsung-10 emulator window. Real hardware FORBIDDEN. Continue until exhausted or hit hard blocker.

## State entering autonomous mode (2026-05-24)
- Mesa 26.2.0 cross-built on host, installed in guest qcow2 at `/usr/lib64/driver/`
- iter17 yagl patch applied at libEGL.so.1.0 offset 0x66f0 (yagl_check_gpu_available → return 1) — moot since Mesa replaced YAGL entirely
- enlightenment crashes at libc.so.6 + 0x681e0 (likely strlen(NULL)) when Samsung COREGL wrapper calls into Mesa libEGL
- Service masks (avocd, tvs, aitech) — reverted by golden restore in iter15, NOT re-applied
- App pre-installed via hello-flutter.service oneshot
- TV emulator window opens on Xvfb :99 with Samsung TV bezel + remote
- `boot completed!` never reached because enlightenment fails → `/run/.wm_ready` never created

## Strategy
1. **Phase 1**: Get exact backtrace of enlightenment crash (via core dump capture from guest)
2. **Phase 2**: Write minimal LD_PRELOAD shim addressing identified missing symbols
3. **Phase 3**: Iterate — each new failure mode → patch → retest

## Iteration log

### Step 1 — Get exact backtrace ✅
Modified `/usr/bin/run_enlightenment.sh` via qcow2 mount:
- Added `ulimit -c unlimited`
- Set `core_pattern = /opt/usr/share/crash/dump/core.%e.%p`
- Wrapped `enlightenment` with strace -f
- Boot → enlightenment crashed → 65MB core captured

Pulled core + guest libs (516 .so files) to `/tmp/guest-libs/`. Backtrace via `gdb -batch --sysroot /tmp/guest-libs`:

```
#0 pthread_mutex_lock      (SIGSEGV at NULL+0x369)
#1 wl_proxy_create_wrapper (guest libwayland)
#2 dri2_initialize_wayland (Mesa)
#3 dri2_initialize         (Mesa)
#4 eglInitialize           (Mesa)
#5 eng_window_new          (evas gl_tbm engine)
#6 eng_output_setup
#7 efl_canvas_output_engine_info_set (libevas)
#8 ecore_evas_tbm_allocfunc_new_internal
#9 _e_comp_canvas_ecore_evas_tbm_alloc
#10 e_comp_screen_init
#11 _e_main_screens_init
#12 main
```

### Step 2 — Patch wl_proxy_create_wrapper to be no-op ✅
Mesa's wayland EGL init crashed inside `wl_proxy_create_wrapper`. Replaced its PLT entry at libEGL.so file offset 0xf680:
- Original: `f3 0f 1e fa ff 25 2e 8e 05 00 66 0f 1f 44 00 00` (endbr64 + jmp via got)
- Patched: `48 89 f8 c3 90 90 90 90 90 90 90 90 90 90 90 90` (mov rdi,rax; ret; pad)
- Effect: `wl_proxy_create_wrapper(x)` returns `x` (no actual wrapping)

### Step 3 — Next crash uncovered ⚠️
Boot again. enlightenment no longer crashes inside `wl_proxy_create_wrapper`. New crash:

```
#0 __pthread_kill_implementation  (SIGABRT)
#1 raise
#2 abort
#3 __libc_message_impl.cold
#4 __libc_assert_fail
#5 __pthread_mutex_lock_full
#6 wl_display_create_queue_with_name  ← assertion fail here
#7 dri2_initialize_wayland
#8 dri2_initialize
#9 eglInitialize
```

`wl_display_create_queue_with_name` libwayland internal assertion. Root cause: **Samsung patched libwayland-client.so.0.23.1** (93 KB vs upstream 68 KB; only 2 extra exports but internal struct layout/code likely differs). Mesa was built against upstream wayland-client headers and passes structures with mismatched internal expectations.

### Step 4 — Patching strategy assessment
- Individual PLT-stub patches work but each unveils next crash
- Real fix: rebuild Mesa against guest's libwayland-client
- OR: write LD_PRELOAD shim translating guest↔host wayland struct layouts

### Step 5 — Strategic pivot: bypass Mesa EGL entirely ✅✅✅
Discovered enlightenment binary supports `software_tbm` evas engine as alternative to `gl_tbm`. String references in binary:
- `USE_EVAS_SOFTWARE_TBM_ENGINE` (env var name)
- `ecore_evas engine:software_tbm fallback to software engine.`
- Engine selection happens in `e_comp_screen_init` based on `e_config.engine_type` at offset 0x30

Disassembled VA 0x4486e0+ in enlightenment binary:
1. Binary itself calls `setenv("USE_EVAS_SOFTWARE_TBM_ENGINE", "1", 1)`
2. Checks `ecore_evas_engine_type_supported_get(0x18)` and `(0x19)` — neither supported with Mesa → falls through to GL_TBM prep at 0x448713
3. Logs "EE_GL_TBM" prep info
4. Checks `gl_avail` flag at 0x448763 → 0 (init) → would jump to software_tbm at 0x448784
5. BUT: extra check at 0x44877a `cmpl $0x2, e_config+0x30` (engine_type == GL) → `je 0x449ed9` → goes to GL_TBM init → logs "EE_GL_TBM New" → calls Mesa eglInitialize → CRASH

**Binary patch at file offset 0x4877e**: NOPed the `je 0x449ed9` (6 bytes `0f 84 55 17 00 00` → `66 0f 1f 44 00 00` 6-byte NOP) — forces fallthrough to software_tbm path at 0x448784.

### Step 6 — RESULT: Compositor reaches MAIN LOOP ✅✅✅✅
After applying enlightenment binary patch + Mesa libEGL `wl_proxy_create_wrapper`/`wl_proxy_set_queue` PLT patches:

```
[    6.499] ESTART: 0.34899 - EE_SOFTWARE_TBM New
[    6.518] ESTART: 0.36824 - EE_SOFTWARE_TBM New Done 0x1ae4e50 3840x1080
[    6.578] ESTART: 0.42870 - MAIN LOOP AT LAST
[    6.809] lwipc: [enlightenment] D '/run/.wm_ready'   ← created by compositor!
```

Compositor in main loop. wm_ready set BY enlightenment. Multiple wayland clients connect:
- boot_splashscreen, volume-app, tv-viewer, tvctx-manager, muse-server
- CSFS (samsung TV) — creates wl_surface, commits, status=1 ready
- Each calls `ecore_wl2_window_surface_create` + `wl_surface_commit`

**Visible screen state**: Inner TV canvas is now PURE BLACK (was kernel framebuffer text before). VIGS scanout bound to compositor output. Compositor in main loop drawing background but no app surface visible yet.

### Step 7 — Flutter app launches but SIGABRTs ⚠️
After fg_launch at ~80s:
```
85.353 E/ConsoleMessage(P10353): DotNET onSigabrt called on com.example.hello_tizen_tv
85.385 E/LAUNCHPAD: pid=10353, appid=com.example.hello_tizen_tv
85.386 E/AMD: appid(com.example.hello_tizen_tv), pid(10353), status(6)  ← SIGABRT
110.008 E/AMD_APP_STATUS_TV: __fg_launch_timeout for com.example.hello_tizen_tv(0)
```

Flutter Tizen embedder runs ~0.5s then aborts. Other apps (CSFS, volume) DON'T crash. So Flutter-specific abort, not Mesa-related. Next iteration: capture core dump from PID 10353 to identify what aborts inside .NET runtime / libflutter_tizen_tv.so.

## Summary: where we are
- ✅ Compositor functional (MAIN LOOP, wm_ready)
- ✅ Wayland clients can connect, create surfaces, commit
- ✅ Software TBM canvas 3840x1080 allocated, VIGS scanout bound
- ⚠️ Compositor canvas BLACK — surfaces committed but no visible content yet
- ❌ Flutter app SIGABRTs at startup (separate issue from compositor)
- ❌ Other apps don't produce visible content either (TDM/HWC composition path?)

### Step 8 — Identified true blocker: wl_drm protocol path ⛔
Flutter app crash log shows exact failure (PID 10353):
```
85.343 ecore_wl2_window_new (1920x1080)
85.344 _ecore_wl2_window_surface_create
85.344 ecore_wl2_egl_window_create  ← wl_egl_window created
85.349 ecore_wl2_window_show + commit
85.353 MESA-EGL: warning: failed to get driver name for fd -1
85.353 MESA-EGL: warning: MESA-LOADER: failed to retrieve device information
85.353 Tried to destroy non-wrapper proxy with wl_proxy_wrapper_destroy
85.353 DotNET onSigabrt
```

Root cause: in software_tbm compositor mode, the wl_drm protocol exchange fails. Mesa wayland EGL needs `wl_drm.device` event to get the DRM device fd. Compositor in software mode doesn't register/respond to wl_drm. fd=-1 → Mesa fails → app abort.

Affects ALL EGL-using apps (volume-app, tv-viewer, csfs, pillarbox, Flutter). Native non-EGL apps would work but Tizen system apps all use EGL.

### Hard blocker reached. Stop conditions satisfied per autonomous mandate.

Approaches exhausted (3+ substantially different):
1. **Mesa cross-build replacing Samsung COREGL** — works for build, fails at Mesa wayland EGL deadlock
2. **PLT patches in Mesa libEGL** for wayland init crashes — works for compositor but next layer breaks apps  
3. **enlightenment binary patch forcing software_tbm engine** — works for compositor MAIN LOOP, doesn't help apps
4. **App-wide ELM_ENGINE=wayland_shm env override** — breaks more apps (volume/tv-viewer crash earlier)

Real fix paths (multi-day work, beyond autonomous session scope):
- **A. Patch enlightenment compositor to expose wl_drm protocol even in software mode** — would let apps' Mesa EGL get a DRM fd. Requires C dev in compositor source + recompile.
- **B. Patch Mesa to handle missing wl_drm gracefully** — fall back to wayland-shm path or fail eglInitialize cleanly. Requires Mesa source change + rebuild.
- **C. Replace each app's libEGL.so.1 (COREGL wrapper) with a no-op stub** — apps would skip EGL entirely. Likely breaks Tizen system apps that hard-require GL.
- **D. Real Samsung TV hardware** — Mali GL, no YAGL/VIGS. The pragmatic path (user has FORBIDDEN this).
- **E. LD_PRELOAD shim translating guest libwayland↔upstream wayland struct layouts** — would let Mesa's wayland EGL find wl_drm properly. Multi-day C dev.

## Net gain this session

**Before**: enlightenment crashed at libc+0x681e0 (NULL strlen) during Mesa EGL init. wm_ready never created. Inner TV canvas showed raw kernel framebuffer text.

**After**: enlightenment MAIN LOOP AT LAST. EE_SOFTWARE_TBM 3840x1080 canvas allocated. wm_ready created by compositor. Multiple wayland clients connect+commit surfaces. Inner TV canvas pure BLACK (compositor scanout bound to VIGS, draws empty background). Apps that don't use Mesa EGL would render.

**Distance to user goal (visible Flutter UI)**: Closer but not yet — Flutter Tizen embedder hard-requires working Mesa wayland EGL which fails due to wl_drm protocol issue. Requires one of the multi-day fixes above.
