# Hello Tizen TV — Onboarding

## What this project is

`hello_tizen_tv` is a Flutter (.NET, TFM `tizen80`) Material counter app targeting Samsung Smart TV (Tizen 10 platform, TV-Samsung extension). Trivially small — it's a proving-ground for the Flutter Tizen toolchain.

## Current status (2026-05-23, after ~4 days of investigation)

### What works end-to-end

| Stage | Status | Notes |
|---|---|---|
| `flutter-tizen build tpk --release --target-arch=x64 --device-profile=tv` | ✅ | Always pass `--target-arch=x64` and `--device-profile`; without them flutter-tizen ships a 32-bit ARM library to a 64-bit x86 target |
| Sign with Samsung-issued certs | ✅ | Profile `vld` in tizen Studio. Password `TizenAuthorPass1!`. |
| TV-Samsung-10 emulator window opens on Xvfb :99 (Samsung TV bezel + Samsung TV remote visible) | ✅ | Iter14 discovery. Earlier iter9–12 conclusion ("binary regression") was wrong — they tested under Cosmic Wayland's XWayland connector which is the actual incompatibility |
| Guest VM boots to `boot completed!` (~80s on Xvfb) | ✅ |
| Install TPK via qcow2 mount + systemd oneshot service | ✅ | Iter16. sdb shell is unreliable but offline install via mount works |
| AUL launch — process spawned, dotnet-launcher activates, AMD foreground timer starts | ✅ |
| `flutter-tizen attach` for Dart hot reload | Theoretically | Dart VM Service starts (after libflutter_tizen_tv.so patch at 0x49703) |

### What is blocked — **the actual wall**

**Visible Flutter UI inside the emulator's inner canvas — gated by guest YAGL/EGL initialization failure.**

Inside the Tizen guest, `eglGetDisplay(EGL_DEFAULT_DISPLAY)` returns NULL from `/usr/lib64/driver/libEGL.so.1.0` (Samsung's YAGL implementation that talks to the VIGS DRM device). Affects ALL apps that go through `ecore_wl2 + wayland_egl`:

- Samsung's pre-installed `org.tizen.homescreen` — fails
- `boot-animation-dali` — fails
- `org.tizen.volume`, `TaskBar.dll` — fail
- `wrt-loader` (web runtime) — fails
- `com.samsung.tv.csfs` — fails
- **Our Flutter app — fails the same way**

AMD logs `__fg_launch_timeout` after 108s wait for foreground window. App process runs, AOT failed (Flutter runs JIT instead, fine), Dart VM is up, but no visible Wayland surface.

The guest's wayland_egl crash error is the same EGL fail observed across all Tizen 10 emulators (both Samsung TV-extension and upstream Tizen 10 public — `TIZEN-10.0-Emulator 5.0.3.6`).

## Critical paths and lessons

**Do not re-investigate these (already exhausted)**:

| Approach | Why it doesn't help |
|---|---|
| "Binary regression in TV-Samsung 2.8.0.38" | Iter14 disproved this. The binary actually works on Xvfb — Cosmic XWayland was the wrong test environment |
| Cosmic Wayland, Xephyr nested in Cosmic, Docker (any flavor) for emulator display | Cosmic's XWayland refuses to map Qt5 windows from emulator-x86_64. Use Xvfb :99 instead — pure-X11 headless framebuffer in RAM |
| `QT_QPA_PLATFORM=xcb`, `LIBGL_ALWAYS_SOFTWARE=1`, `LIBGL_ALWAYS_INDIRECT=0` | Doesn't bypass guest YAGL |
| iter9 binary patches on emulator-x86_64 (qt5_early_prepare, qt5_gui_init, vigs_qt5_onscreen_enabled) | Don't help. Binary already restored to .orig |
| `vm_launch.conf` `rendering=offscreen` vs `onscreen`, `backend=sw` vs `gl` | `backend=gl` with Mesa llvmpipe is what works on host. `backend=sw` on host doesn't expose GLES. Either way, guest YAGL still fails |
| Trying alternate emulators (Tizen 8, 9, 10 public; Mobile 6, 6.5; Wearable 6.0–7.0) | Old ones work but use different .NET API (TFM mismatch). Tizen 10 public has the SAME guest EGL fail as TV-Samsung. Wearable 6.5 (2.8.0.36) renders the watch face fully — but it's a different platform (Tizen Wearable, not TV) |
| Service masking (avocd, tvs_lite, tvs_deamon, aitech_daemon, csfs auto-restart) via qcow2 mount | Reduces klog spam, doesn't fix EGL |

## Remaining paths (in order of payoff per effort)

1. **Real Samsung TV ($150–500, 1 week shipping)** — Tizen 4+ device, any 2018+ Smart TV model. Enable Smart Hub → Apps → enter `12345` → toggle Developer Mode → set host IP. Then `sdb connect <tv_ip>:26101` and the full pipeline deploys. Real hardware uses Mali GL, no YAGL — Layer 2 wall disappears entirely.

2. **Fix guest YAGL/EGL (days of RE)** — investigate why `eglGetDisplay()` returns NULL. Need either LD_PRELOAD strace inside guest or kernel tracepoints on `/dev/dri/card0`. May involve cross-compiling Mesa with virgl support and switching emulator config from VIGS to `virtio-gpu`.

3. **Patch libflutter_tizen.so for software rendering (binary RE, days)** — current binary directly calls `ecore_wl2` and uses dmabuf. Would need to intercept the EGL path or replace with software Skia + Wayland-SHM. Complex.

4. **Wait for Samsung emulator fix** — file SDK bug at developer.samsung.com forum. Months-long timescale, uncertain.

## Key paths (on remote Pop!_OS box `popos` via Tailscale SSH)

| Resource | Path |
|---|---|
| Tizen Studio | `~/tizen-studio/` |
| Tizen data dir | `~/tizen-studio-data/` |
| flutter-tizen | `~/development/flutter-tizen/` |
| Project | `~/development/hello_tizen_tv/` |
| Samsung certs | `~/SamsungCertificate/hello-tizen-tv/` (password `TizenAuthorPass1!`) |
| Tizen-default cert | `~/SamsungCertificate/tizen-default/tizen-test.p12` (password `TestPass1!`) |
| Cert profiles config | `~/tizen-studio-data/profile/profiles.xml` |
| Patched `libflutter_tizen_tv.so` | `~/development/flutter-tizen/flutter/bin/cache/artifacts/engine/tizen-x64/8.0/libflutter_tizen_tv.so` (orig at `.orig`, patched at file offset 0x49703 with 6× NOP) |
| flutter-tizen `tizen_sdk.dart` patch | `defaultNativeCompiler='gcc'` |
| TV-Samsung-10 emulator binary | `~/tizen-studio/platforms/tizen-10.0/tv-samsung/emulator/bin/emulator-x86_64` (unpatched, matches `.orig`) |
| Wearable 6.5 binary (working reference, debug_info intact, 2.8.0.36) | `~/tizen-studio/platforms/tizen-6.5/common/emulator/bin/emulator-x86_64` |
| Hello TV VM image | `~/tizen-studio-data/emulator/vms/hello_tv/emulimg-hello_tv.x86_64` — contains pre-installed hello_tizen_tv app + hello-flutter.service oneshot |
| Golden snapshot | `~/tizen-studio-data/emulator/vms/hello_tv/emulimg-hello_tv.x86_64.golden` — clean state to restore if needed |

## Setup details

- SSH bridge Mac ↔ Pop!_OS via Tailscale CGNAT 100.x. Mac-side: Hiddify VPN configured to bypass 100.64.0.0/10. SSH alias `popos`.
- Xvfb running headless at :99: `Xvfb :99 -screen 0 4096x1200x24 -ac`. Screenshot via `DISPLAY=:99 import -window root /tmp/x.png`. Window listing via `DISPLAY=:99 xwininfo -root -tree` (no WM, so `wmctrl -l` won't show much).
- Killing the emulator process can drop SSH. Use `setsid bash -c "kill -15 $PID; sleep 3; kill -9 $PID 2>/dev/null" >/dev/null 2>&1 &` then `disown`. Avoid `pkill -f` patterns broader than necessary (broad patterns can match SSH itself).
- buxton service is named `buxton2.service` in Tizen 10 (not `buxton.service`).

## Working incantation (still works headless)

```bash
# On host:
ssh popos
setsid nohup /tmp/run_tv10_xvfb.sh > /tmp/tv10_xvfb.log 2>&1 < /dev/null &
sleep 90  # boot

# Where /tmp/run_tv10_xvfb.sh contains:
# unset WAYLAND_DISPLAY
# export DISPLAY=:99
# export QT_QPA_PLATFORM=xcb
# exec /home/vld/tizen-studio/platforms/tizen-10.0/tv-samsung/emulator/bin/emulator.sh \
#   --conf /tmp/hello_tv_no_tuner.conf \
#   -j /home/vld/tizen-studio/jdk/bin/java

# Build app:
cd ~/development/hello_tizen_tv
~/development/flutter-tizen/bin/flutter-tizen build tpk --release \
    --target-arch=x64 --device-profile=tv

# Install via sdb push (works to specific path) — but sdb shell may hang:
~/tizen-studio/tools/sdb -s emulator-26101 push \
    build/tizen/tpk/com.example.hello_tizen_tv-1.0.0.tpk \
    /home/owner/share/tmp/sdk_tools/

# If sdb shell hangs, use offline-install via qemu-nbd qcow2 mount
# (see iter16 in docs/FINDINGS.md for full sequence)
```

## Confluence research record

Full Mac-side iter1–7 + early Linux iter8–12 history: https://fitstars.atlassian.net/wiki/spaces/SmartTV/pages/625934347. Linux iter8–16 detail: `docs/FINDINGS.md` (this repo). Samsung SDK bug report draft (needs rewrite — the original "regression" claim is wrong): `docs/samsung-bug-report-draft.md`.
