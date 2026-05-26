# Web App pixels on Tizen emulator — verdict

Date: 2026-05-27.

## Question

Can a Tizen web app (HTML/CSS/JS in a `.wgt` package) render visible
pixels on the headless Tizen TV emulator on a Linux host (Pop!_OS,
Xvfb display), avoiding the EGL/Mesa wayland wall that blocked Flutter
and NUI?

## Answer

**No.** Tizen web app hits the **same EGL/Mesa wayland wall** as Flutter
and NUI. The Chromium-EFL runtime (`wrt-loader`) used by Tizen WRT
internally calls `eglGetDisplay()` through EFL's `evas-wayland_egl`
backend to create its rendering surface, and that call fails with the
exact same error pattern.

## What was tried

1. Minimal hand-written `config.xml` + `index.html` Tizen 2.4 web app.
2. Built `.wgt` (24 KB) signed with `tizen-default` profile.
3. Installed cleanly via `pkgcmd -i -t wgt`. WAS-side: OK.
4. Launched via `app_launcher --start`. AMD-side: clean.
5. Chromium-EFL initialized through to `browser-window-created`
   and `window created : #1`.

## What failed

```
W/LAUNCHPAD( 2799): loader_context.cc: Deploy(312) > Request to the loader process.
                    pid(1825387), path(/opt/usr/globalapps/.../9aBcDeFgHi.TizenWebSmoke)

I/CHROMIUM(1825387): wrt_native_window.cc: EnsurePlatformWindow(235) >
                     Use offscreen rendering mode

E/EFL(1825387): evas-wayland_egl: evas_wl_main.c:175 eng_window_new() 
                eglGetDisplay() fail. code=0
E/EFL(1825387): ecore_evas: ecore_evas_wayland_common.c:4684 
                _ecore_evas_wl_common_new_internal()
                Failed to set Evas Engine Info for 'wayland_egl'

E/AMD: app_status_manager.cc: OnSigchldEvent(1134) >
       pid(1825387) is crashed by signal(5)
```

Signal 5 (`SIGTRAP`) = Chromium's internal check failed and aborted.

## Why this confirms the wall is global

The same `eglGetDisplay() fail. code=0` pattern has now been observed
across three independent app runtimes on this emulator:

| Runtime | App type | Result |
|---|---|---|
| Flutter engine (libflutter_tizen.so) | `.tpk` | `flutter_tizen_engine.cc: RunEngine > The display was not valid` |
| Samsung NUI/DALi (Tizen.NET.Sdk) | `.tpk` | `egl-graphics-controller.cpp: InitializeGLES` segfault libcoreclr |
| Chromium-EFL WRT | `.wgt` | `evas-wayland_egl: eglGetDisplay() fail. code=0` |
| Pre-installed Samsung apps (homescreen, taskbar, volume) | `.tpk` | constant crashes, libcoreclr segfaults, `display was not valid` |

The Mesa/YAGL EGL layer in the guest's `/usr/lib64/libEGL.so.1.4`
cannot obtain a display handle on this image, on this host stack. It
affects every app that goes through EFL's GL path, which is every Tizen
TV UI runtime.

## Mitigations tried

| Mitigation | Result |
|---|---|
| `ELM_ENGINE=wayland_shm ECORE_EVAS_ENGINE=wayland_shm EVAS_ENGINE=wayland_shm` direct binary launch | bypasses launchpad, app cannot acquire wayland resources, dies |
| Write `~/.cache/dali_common_caches/gpu-environment.conf` with `RENDERER=Software` | no effect on WRT (DALi-specific config) |
| `vconftool set memory/setting/force_software_gl 1` | accepted, no observable effect |
| `LIBGL_ALWAYS_SOFTWARE=1 EGL_PLATFORM=surfaceless MESA_LOADER_DRIVER_OVERRIDE=swrast` | env vars don't survive Tizen launchpad's privilege drop |
| `--hwacc=NONE` via `app_launcher` extra | option not supported by `app_launcher` |
| `aul_test launch_app` direct call | same lifecycle, same EGL failure |

## What renders on this emulator

| What | Renders? | Notes |
|---|---|---|
| Generic Tizen 10 emulator default wallpaper / E20 compositor base | ✓ | drawn by enlightenment (E20) via TDM, no EGL needed |
| Boot animation (`/usr/bin/boot-animation-dali`) | crashes early on EGL | DALi-based |
| `org.tizen.homescreen` (pre-installed Flutter) | ✗ | crashes on EGL |
| `org.tizen.taskbar`, `org.tizen.volume` (pre-installed NUI) | ✗ | crashes on EGL |
| Our installed `.tpk` Flutter app | ✗ | reaches lifecycle, no UI |
| Our installed `.wgt` web app (Chromium WRT) | ✗ | crashes signal 5 on EGL fail |

Conclusion: the **only** visible content on the emulator is what E20
compositor itself renders. Any app that needs a GL context to draw is
blocked at `eglGetDisplay()`.

## Alternative paths

### 1. Real Samsung TV — most reliable

A 2021+ Samsung Smart TV (Tizen 6.0+, RM/UN model line) has a real
GPU with working EGL. The same `.wgt` deployed via Samsung Developer
mode on a real device will render. This is what Samsung's documentation
recommends for any UI verification. Cost: a device.

### 2. Web rendering on a host browser (no emulator)

For pure UI iteration that doesn't need Tizen-specific APIs, run the
`index.html` directly in Chrome / Firefox / a local server with the TV
dimensions:

```bash
cd /tmp/tizen-web-smoke
python3 -m http.server 8080
# open http://localhost:8080 in browser, set window to 1920x1080
```

Tizen-specific JS APIs (`tizen.systeminfo.*`, `tizen.tvchannel.*`,
`tizen.tvinputdevice.*`) won't be available, but layout, animations,
and most app logic can be iterated this way much faster than any
emulator.

### 3. Try a different emulator image

Some Tizen Studio emulator images have historically worked better with
software fallback on Linux hosts. Specifically the **`tizen-4.0` /
`tizen-5.5`** older images had simpler GL pipelines. Possible to try if
you specifically need an emulator and not a real TV, but you give up
modern Tizen TV APIs.

### 4. Patch host Mesa / VIGS

The `eglGetDisplay() fail. code=0` traces back to the guest's
YAGL/VIGS GL passthrough not negotiating with the host. Earlier work
in this project (see `project-tizen-emulator-linux-wall.md` in
`memory/`) established that this is a deep issue across kernel + Mesa.
Possible to patch but high effort and reversed-engineering-heavy.

### 5. Headless test target only

Use the emulator for what works:

- build / sign / package validation
- install/uninstall flow
- AUL/AMD lifecycle dispatch (OnCreate, OnResume, OnTerminate)
- platform API calls that don't require UI (systeminfo, network, storage)
- automated integration tests that don't assert on rendered output

UI verification stays on a real TV.

## Practical verdict

**Visible pixels of a sideloaded user app on the Tizen TV emulator
on Linux host are not achievable** with currently available emulator
images and tooling. Either:

- accept emulator for non-UI tasks and use a real Samsung TV for UI, **or**
- iterate UI in a host browser (option 2) and only finalize on TV.

There is no software-fallback knob in the current Tizen WRT / EFL /
DALi stacks that bypasses the missing EGL display on this host.

## Provenance

Diagnostic session 2026-05-27 on Pop!_OS 24.04 host with VS Code
Tizen Extension–managed SDK at `~/.tizen-extension-platform/`,
T-10.0-x86_64 emulator on Xvfb :99. Web app and full dlog snapshots
preserved at `/tmp/tizen-web-smoke/` on popos. Pre-existing observations
about the same EGL wall affecting Flutter and Samsung TV image
documented in `docs/TIZEN_TV_FLUTTER_FINDINGS.md` and
`docs/TIZEN_EXTENSION_SDK_MIGRATION_REPORT.md`.
