# Hello Tizen TV — Onboarding

## What this project is

`hello_tizen_tv` is a Flutter (`.NET dotnet TFM tizen80`) Material counter app targeting Samsung Smart TV (Tizen 10 platform, TV-Samsung extension). The app itself is trivially small — it's a discovery/proving-ground for the Flutter Tizen toolchain.

## Current status (2026-05-23, after ~3 days of investigation)

**Headless dev pipeline works fully**:

| Stage | Status | Notes |
|---|---|---|
| `flutter-tizen build tpk --release --target-arch=x64 --device-profile=common` | ✅ | Always pass `--target-arch` and `--device-profile`; without them flutter-tizen ships a 32-bit ARM library to a 64-bit x86 target |
| Sign with Samsung-issued certs | ✅ | Profile `vld` in tizen Studio. Password `TizenAuthorPass1!`. For Tizen-distributor-signed builds use profile `tizen-default` (generated 2026-05-23) |
| `sdb push` + `pkgcmd -i -t tpk -p ...` | ✅ | Install succeeds on TV-Samsung-10 emulator |
| `app_launcher --start com.example.hello_tizen_tv` | ✅ | AUL launches, dotnet-launcher activates, CoreCLR initializes |
| Dart VM Service inside guest | ✅ | `libflutter_tizen_tv.so` patched at file offset 0x49703 (6x NOP) to bypass "display was not valid" abort; otherwise the embedder aborts before VM service starts |
| `flutter-tizen attach` for hot reload | Should work | Verified Dart VM Service starts; full attach flow not end-to-end tested today |

**What is blocked**: visible UI in *any* emulator on this Linux box. Several emulators tested today, each fails at a different layer:

| Emulator | Window opens? | App installs? | App launches? | Visible UI? |
|---|---|---|---|---|
| TV-Samsung 10 (Samsung-branch 2.8.0.38, 2025-11) | ❌ binary regression | n/a | n/a | n/a |
| Mobile 6.0 (Samsung-branch 2.8.0.33, 2020) | ✅ | ❌ API mismatch (.NET 10 vs Mobile 6 max .NET 8) | n/a | n/a |
| Tizen 8.0 public (upstream 5.0.3.2, 2023) | ✅ | ❌ disk full + system services crash | n/a | n/a |
| Tizen 10.0 public (upstream 5.0.3.6, 2025-09) | ✅ | ✅ (after `/opt/usr/share/crash` cleanup) | ✅ | ❌ DALi/EGL broken — even Samsung's pre-installed apps crash with `Could not get EGL display` |

## The Samsung regression (already proven, don't re-investigate)

Side-by-side cross-version A/B on the same Pop!_OS host proves the regression is in Samsung's binary branch:

| Binary path | Samsung version | Build date | Visible window? |
|---|---|---|---|
| `tizen-6.0/common/emulator/bin/emulator-x86_64` | 2.8.0.33 | 2020-09-23 | ✅ |
| `tizen-8.0/common/emulator/bin/emulator-x86_64` | 5.0.3.2 (upstream Tizen) | 2023-06-07 | ✅ |
| `tizen-10.0/common/emulator/bin/emulator-x86_64` | 5.0.3.6 (upstream Tizen) | 2025-09-11 | ✅ |
| `tizen-10.0/tv-samsung/emulator/bin/emulator-x86_64` | **2.8.0.38** | **2025-11-20** | ❌ |

The TV-Samsung binary logs `mainwindow.cpp:350 show main window`, the Qt5 process stays alive holding X11 sockets, but Qt main window is never `XMapWindow`'d. VIGS never logs `vigs_offscreen_server_create` or `vigs_onscreen_server_create`. Older binaries DO log this and DO create visible windows.

**Don't re-test these environments**, they all behave identically on TV-Samsung-10:
- Cosmic Wayland (host), Xephyr nested X11, Xvfb headless, Docker Ubuntu 22.04 jammy
- `QT_QPA_PLATFORM=xcb`, `LIBGL_ALWAYS_SOFTWARE=1`, `LIBGL_ALWAYS_INDIRECT=0`
- iter9 binary patches (qt5_early_prepare, qt5_gui_init, vigs_qt5_onscreen_enabled) — restored to .orig because they don't help
- vm_launch.conf `rendering=offscreen` vs `rendering=onscreen`
- vm_launch.conf `backend=sw` vs `backend=gl`

## Where to actually invest

In order of payoff:

1. **File Samsung SDK bug** at https://developer.samsung.com/forum or via their developer portal. Reference the cross-version A/B above. Include `Build Date: 2025-11-20 12:33:06 IST` and `Package Version: 2.8.0.38`.

2. **Buy a used Samsung TV with developer mode** (Tizen 4+ — any 2018+ Smart TV model). Enable Smart Hub → Apps → enter `12345` → toggle Developer Mode → set host IP. Then `sdb connect <tv_ip>:26101` and the existing pipeline deploys directly.

3. **Continue Flutter dev "blind" against TV-Samsung-10 emulator** while waiting. Use `flutter-tizen attach` + Dart Observatory for state inspection, hot reload, breakpoints. Only visible-UI verification is blocked.

4. **GDB binary diff** of Mobile-6.0 (NOT stripped, has debug_info) vs TV-Samsung-10 (stripped). Find where VIGS-to-MainWindow wiring diverges. Weeks of work.

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
| Patched libflutter_tizen_tv.so | `~/development/flutter-tizen/flutter/bin/cache/artifacts/engine/tizen-x64/8.0/libflutter_tizen_tv.so` (orig at `.orig`) |
| flutter-tizen `tizen_sdk.dart` patch | `defaultNativeCompiler='gcc'` (Tizen Studio 6.1 ships gcc, not llvm-10) |
| Patched emulator-x86_64 (preserved but not active) | `tv-samsung/emulator/bin/emulator-x86_64.patched` — current `emulator-x86_64` matches `.orig` |
| Golden TV VM snapshot | `~/tizen-studio-data/emulator/vms/hello_tv/emulimg-hello_tv.x86_64.golden` |

## Setup details (don't re-derive)

- SSH bridge Mac ↔ Pop!_OS via Tailscale CGNAT 100.x. Mac side: Hiddify VPN configured to bypass 100.64.0.0/10. SSH alias `popos`.
- Headless display: `Xvfb :99 -screen 0 4096x1200x24 -ac` running on Pop!_OS for emulator screenshot capture. Use `DISPLAY=:99 import -window root /tmp/X.png` to capture. `wmctrl -l` won't list windows (no WM); use `DISPLAY=:99 xwininfo -root -tree`.
- The `setsid sh -c "kill -15 $PID" &` pattern is required for killing KVM emulator processes — direct `pkill` drops the SSH session.
- buxton service in Tizen 10 is `buxton2.service` (not `buxton.service`). Earlier dlog errors saying "Can't connect to buxton" were misleading — service is fine when `/opt` has free space; clear `/opt/usr/share/crash` if disk fills up.

## flutter-tizen build invocation (the working incantation)

```bash
cd ~/development/hello_tizen_tv
~/development/flutter-tizen/bin/flutter-tizen build tpk \
    --release \
    --target-arch=x64 \
    --device-profile=common
```

The manifest in `tizen/tizen-manifest.xml` should have `api-version="10.0"` and `<profile name="tv"/>` for real TV deployment. Restore it from `tizen-manifest.xml.bak.20260428_run_api10` if needed — today's testing temporarily swapped to `common` profile for the (unsuccessful) public Tizen 10 emulator attempt.

## Confluence research record

The full Mac-side research history (iter1-7) is at https://fitstars.atlassian.net/wiki/spaces/SmartTV/pages/625934347. The Linux-side iterations (iter8-12) are in `docs/FINDINGS.md` of this repo.
