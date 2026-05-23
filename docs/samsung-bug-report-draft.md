# Bug report draft — Samsung TV-Samsung emulator v2.8.0.38 regression

**Target submission**: https://developer.samsung.com/forum (TV / Tizen Studio category) or the Tizen SDK issue tracker. Confluence record at https://fitstars.atlassian.net/wiki/spaces/SmartTV/pages/625934347.

---

## Title

TV-Samsung emulator v2.8.0.38 fails to create main window on Linux x86_64 — regression from older 2.8.0.x builds

## Environment

- Host: Pop!_OS 24.04 (Ubuntu 24.04 noble base), x86_64 + Intel/AMD CPU + KVM enabled
- Tizen Studio 6.1 (latest, fresh install)
- Tizen Studio package manager → `TV-SAMSUNG-Public-Emulator 10.0.0` (latest available)
- Package Version: `2.8.0.38`, Build Date: `2025-11-20 12:33:06 IST`
- Maintainer: `Jingjing geng <jingjin.geng@samsung.com>`
- Tested with both NVIDIA + Mesa hosts, with KVM and TCG, with backend=sw and backend=gl, with X11 (Xorg/Xephyr/Xvfb) and XWayland, with and without Docker (Ubuntu 22.04 jammy and 24.04 noble)

## Steps to reproduce

1. Install Tizen Studio 6.1 on Linux x86_64.
2. Install `TV-SAMSUNG-Public-Emulator 10.0.0` via package-manager-cli.
3. Create a TV emulator VM (e.g. `hello_tv`, default resolution 3840x1080).
4. Launch via `emulator.sh --conf .../vm_launch.conf -j .../jdk/bin/java`.

## Expected behavior

Emulator skin window opens; `vigs_offscreen_server_create` is logged; guest reaches boot completion; UI is visible.

## Actual behavior

- Process starts and stays alive (sleeping in `poll_schedule_timeout`).
- `mainwindow.cpp:350 show main window` is logged.
- Qt5 process holds X11 sockets (`/proc/PID/fd` shows them); `wmctrl` from inside the emulator's network namespace can list host windows, so the X11 connection itself is fine.
- **But the emulator's Qt main window never appears** — `xwininfo -root -tree` shows only Qt5 internal helper windows (1x1, 3x3), no skin/canvas.
- VIGS never logs either `vigs_offscreen_server_create` or `vigs_onscreen_server_create`.

The guest VM is still reachable via `sdb`; install, AUL launch, Dart VM Service all work — only the *visible* emulator window is broken.

## Cross-version A/B (key evidence)

Same Pop!_OS host, same KVM, same Qt5 platform, all binaries running concurrently or in sequence:

| Emulator package | Branch | Version | Build date | Window opens? | `vigs_offscreen_server_create`? |
|---|---|---|---|---|---|
| `MOBILE-6.0-Emulator` | Samsung TV ext | **2.8.0.33** | 2020-09-23 | ✅ | ✅ |
| `TIZEN-8.0-Emulator` | upstream Tizen | 5.0.3.2 | 2023-06-07 | ✅ | ✅ |
| `TIZEN-10.0-Emulator` | upstream Tizen | 5.0.3.6 | 2025-09-11 | ✅ | ✅ |
| `TV-SAMSUNG-Public-Emulator 10.0.0` | Samsung TV ext | **2.8.0.38** | 2025-11-20 | **❌** | **❌** |

The regression is bracketed to **Samsung TV-extension branch between 2.8.0.33 and 2.8.0.38**. The parallel upstream Tizen 5.0.3.x branch (built only two months earlier in September 2025) works fine on the exact same machine. We are unable to test intermediate 2.8.0.34–37 builds because package-manager-cli only ships the latest revision.

## Secondary observation (worth investigating but not the primary report)

On `TIZEN-10.0-Emulator` (the upstream-branch emulator that *does* create a window), every pre-installed dotnet app (`org.tizen.homescreen`, `boot-animation-dali`, `org.tizen.volume`, `TaskBar.dll`) crashes on launch with:

```
tizen_renderer_egl.cc: PrintEGLError() > Unknown EGL error: 0
tizen_renderer_egl.cc: CreateSurface() > Could not get EGL display.
window-impl.cpp: SetScreen() > input Screen name is empty
Exception: OpenGL ES is not supported
terminate called after throwing an instance of 'Dali::DaliException'
```

COREGL initializes correctly (`coregl_initialize ... -> Completed`), reports `Driver GL version 3.0`, and selects the "Default API path" (Fastpath disabled). But subsequent GLES surface creation fails. This appears to be an image-level issue with the `tizen-unified_20251027.095554` build, not specific to any third-party app.

## Workaround applied (so we are not blocked)

Headless development is preserved on the broken TV-Samsung-10 emulator: `pkgcmd` install, `app_launcher --start`, Dart VM Service all function. The development cycle works without visible UI, with a single byte-patch to bypass the embedder's "display was not valid" abort:

- `libflutter_tizen_tv.so` at file offset `0x49703`, replace 6 bytes (originally `je 0x497cb`) with `90 90 90 90 90 90` (NOPs).

This is obviously not appropriate for production, but it lets us iterate on Dart-level code via `flutter-tizen attach` while the underlying display issue is open.

## Impact

Flutter Tizen TV development on Linux x86_64 is fully blocked from visible UI inspection until either this regression is fixed or developers can obtain physical Samsung TV hardware in dev mode.

## Asks

1. Confirm the regression in v2.8.0.38 vs prior 2.8.0.x builds.
2. Ship an interim hotfix (or expose a prior 2.8.0.x revision via the package manager) so visible UI testing on Linux is possible again.
3. Independently, look at `tizen-unified_20251027.095554` image GLES initialization — multiple pre-installed apps are unable to obtain an EGL display.
