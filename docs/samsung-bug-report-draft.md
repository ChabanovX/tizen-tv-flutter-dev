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

Same Pop!_OS host, same KVM, same Qt5 platform, all binaries probed in sequence:

| Emulator package | Branch | Version | Build date | Stripped? | Window? | `vigs_offscreen_server_create`? |
|---|---|---|---|---|---|---|
| `MOBILE-6.0-Emulator` | Samsung-fork | **2.8.0.33** | 2020-09-23 | debug_info | ✅ | ✅ |
| `WEARABLE-6.5-Emulator` | Samsung-fork | **2.8.0.36** | **2021-09-09** | debug_info | **✅** (renders full watch face) | ✅ |
| `WEARABLE-7.0-Emulator` | upstream | 5.0.2.2 | 2022-09-28 | ? | (not visually verified) | ? |
| `TIZEN-8.0-Emulator` | upstream | 5.0.3.2 | 2023-06-07 | ? | ✅ | ✅ |
| `TIZEN-9.0-Emulator` | upstream | 5.0.3.3 | 2024-02-01 | ? | (not visually verified) | ? |
| `TIZEN-10.0-Emulator` | upstream | 5.0.3.6 | 2025-09-11 | ? | ✅ | ✅ |
| **`TV-SAMSUNG-Public-Emulator 10.0.0`** | **Samsung-fork** | **2.8.0.38** | **2025-11-20** | **stripped** | **❌** | **❌** |

The regression is bracketed inside Samsung's own fork (`2.8.0.x`) **between 2.8.0.36 and 2.8.0.38** — at most one or two intermediate builds. The 2.8.0.36 binary from `WEARABLE-6.5-Emulator` renders the full watch face GUI (including animated dial and bezel artwork) on the identical Pop!_OS host. The 2.8.0.38 binary from `TV-SAMSUNG-Public-Emulator 10.0.0` does not create a window at all.

Additionally, Samsung's parallel **upstream Tizen branch** (`5.0.3.x`, maintained by the same team — see Maintainer field — and building two months earlier in September 2025) works fine on the exact same machine. The bug is **not** in the host environment.

Note also that **the broken binary is stripped while the working older binaries (2.8.0.33 and 2.8.0.36) ship with `debug_info` intact**. This is unusual for a regression: stripping is the only build-process change visible externally between working .36 and broken .38. We did not investigate whether the stripping itself triggers the regression (e.g. through linker option side effects), but it is worth Samsung verifying.

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
