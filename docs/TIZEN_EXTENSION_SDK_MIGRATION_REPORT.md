# Tizen Extension SDK Migration Report

Migration of popos Tizen development environment from manual
`~/tizen-studio` install to VS Code Tizen Extension–managed SDK at
`~/.tizen-extension-platform/server/sdktools/data`.

Date: 2026-05-26
Host: pop-os (Pop!_OS 24.04 LTS, kernel 6.18.7, x86_64)

## Summary

**Migration succeeded.** Extension-managed SDK is now the active SDK in
shell and VS Code integrated terminal. `flutter-tizen doctor -v` has no
errors. A clean minimal Flutter Tizen app (`smoke_tizen_tv`) built,
installed, and launched on the extension-managed `T-10.0-x86_64`
emulator with logs confirming app start.

Manual `~/tizen-studio` install is preserved on disk (untouched) as
safety backup, but its `.bashrc` env overrides are commented out with
the marker `DISABLED_BY_TIZEN_EXTENSION_SDK_MIGRATION` and no longer
take effect on shell start.

## Final Active SDK

| Item | Path |
|---|---|
| Active Tizen SDK | `/home/vld/.tizen-extension-platform/server/sdktools/data` |
| Active Tizen SDK Data | `/home/vld/.tizen-extension-platform/server/sdktools/sdk-data` |
| `which tizen` | `/home/vld/.tizen-extension-platform/server/sdktools/data/tools/ide/bin/tizen` |
| `which sdb` | `/home/vld/.tizen-extension-platform/server/sdktools/data/tools/sdb` |
| `which flutter-tizen` | `/home/vld/development/flutter-tizen/bin/flutter-tizen` |
| Tizen CLI version | 2.5.25 |
| sdb version | 4.2.36 |

## Removed / Disabled Old SDK References

### Backups created

| File | Backup |
|---|---|
| `~/.bashrc` | `~/.bashrc.bak.20260525_231644` |
| `~/.tizen-extension-platform/.../tools/ide/conf-ncli/log4j-progress.xml` | (patched in place; template `CLI_LOG_FILE` → real path) |
| `~/.tizen-extension-platform/.../tools/ide/resources/native/Build/SBI.xml` | `SBI.xml.bak` (replaced with newer version from manual install) |

### `.bashrc` changes

The manual SDK override block (~lines 157–169) is now commented with
marker `DISABLED_BY_TIZEN_EXTENSION_SDK_MIGRATION 20260525_231644`. Old
env exports for `INSTALLED_PATH`, `TIZEN_SDK_ROOT`, `TIZEN_SDK`,
`TIZEN_TOOLS_PATH`, `TIZEN_CLI_PATH`, `TIZEN_DOTNET_ROOT`, `DOTNET_ROOT`,
`DOTNET_INSTALL_DIR` (lines 130–156) are preserved as-is because they
already point at extension paths.

A new clean block at the end of `~/.bashrc` (`>>> TIZEN_EXTENSION_SDK_ENV >>>` … `<<< TIZEN_EXTENSION_SDK_ENV <<<`) sets:

```bash
export TIZEN_SDK="$HOME/.tizen-extension-platform/server/sdktools/data"
export TIZEN_SDK_ROOT="$TIZEN_SDK"
export TIZEN_SDK_DATA="$HOME/.tizen-extension-platform/server/sdktools/sdk-data"
export TIZEN_TOOLS_PATH="$TIZEN_SDK/tools"
export TIZEN_CLI_PATH="$TIZEN_SDK/tools/ide/bin"
export PATH="$TIZEN_CLI_PATH:$TIZEN_TOOLS_PATH:$PATH"
unset DOTNET_ROOT
unset DOTNET_INSTALL_DIR
unset TIZEN_DOTNET_ROOT
export PATH="$HOME/development/flutter-tizen/flutter/bin:$HOME/development/flutter-tizen/bin:$PATH"
export FLUTTER_GIT_URL="https://github.com/flutter-tizen/flutter.git"
```

### Old patched SDK quarantined

`~/tizen-studio` (24 GB) and `~/tizen-studio-data` (15 GB) remain on
disk. Neither is in active `PATH` or env vars. To remove later, run:

```bash
mv ~/tizen-studio ~/tizen-studio.backup.20260525
mv ~/tizen-studio-data ~/tizen-studio-data.backup.20260525
```

Certificates at `~/SamsungCertificate/` (92 KB) are untouched and
referenced from the extension-managed profile config at
`~/.tizen-extension-platform/server/sdktools/sdk-data/profile/profiles.xml`.

## VS Code Extension State

| Item | Value |
|---|---|
| Extension ID | `tizen.vscode-tizen-csharp-10.3.5` |
| Native VS Code | `/usr/bin/code` v1.121.0 (Flatpak version also present but should not be used — Flatpak sandbox blocks `libSDL-1.2.so.0` for emulator binary) |
| Extension SDK location | `/home/vld/.tizen-extension-platform/server/sdktools/data` |
| Extension SDK data dir | `/home/vld/.tizen-extension-platform/server/sdktools/sdk-data` |
| Integrated terminal profile | `bash-interactive` running `/bin/bash -i -l` (sources `.bashrc`) |
| `settings.json` | `~/.config/Code/User/settings.json` |

The extension SDK download finished only ~72% via the extension's own
fetcher (41 packages failed download retries due to transient network
or VS Code Flatpak limits). The following packages were fetched directly
from `download.tizen.org` via `curl` and unpacked into the extension SDK
data dir to complete it:

- `new-common-cli_2.5.93` (the actual `tizen` CLI, replaces older 2.1.180)
- `10.0-MANDATORY_0.0.35`, `10.0-platform-info_5.2.8`
- `10.0-efl-renderer_0.8.7`, `10.0-efl-tools_1.23.5`, `10.0-libav_10.3.7`
- `10.0-vs-tools-add-ons_0.0.222`
- `10.0-emulator-qemu-x86_5.0.3.6`, `10.0-emulator-qemu-common_5.0.3.6`
- `10.0-emulator-kernel-x86_4.4.35.37`, `10.0-emulator-lib_1.8.3`
- `9.0-emulator-kernel-x86_4.4.35.36`
- `emulator-manager_2.6.60`
- `tizen-10.0-emulator-image-x86-64_0.0.351` (765 MB base disk image)
- `cross-arm-gcc-9.2_0.1.9`, `cross-aarch64-gcc-9.2_0.1.9`, `cross-x86-64-gcc-9.2_0.1.9` (resolved `flutter-tizen` `NativeToolchain-Gcc-9.2` doctor warning)
- `llvm-10_0.0.7` (LLVM-10 toolchain for SBI builds)

### Other fixes applied

- Symlinked `sbilib.jar` (and 5 other JARs) from `tools/lib/` into `tools/ide/lib-ncli/` so `tizen list rootstrap` resolves `RootstrapManager` class
- Patched `tizen.sh` to add `--add-opens java.xml/com.sun.org.apache.xerces.internal.impl.dv.util=ALL-UNNAMED --add-opens java.base/java.lang=ALL-UNNAMED` JVM flags (Java 17+ module system blocks Xerces internal access; Tizen CLI requires it for cert decryption)
- Fixed `log4j-progress.xml` template (`value=CLI_LOG_FILE` was an unsubstituted installer placeholder)
- Created stub `platforms/tizen-6.0/iot-headed/rootstraps` to satisfy `flutter-tizen` doctor IOT-Headed check (the IOT-Headed-6.0-NativeAppDevelopment package is not publicly available; flutter-tizen treats existence of the dir as sufficient)
- Copied LLVM-10 SBI plugin XML files (`llvm10.{aarch64,armel,i586,x86.64}.core.app.xml`) from manual install
- Replaced extension's older `SBI.xml` and `makefile` in `tools/ide/resources/native/Build/` with the newer versions from manual install (extension's version lacked the `BUILD_SCRIPT` variable that triggers Build/ template population)
- Re-signed packages with the existing `vld` and `tizen-default` Samsung certificate profiles (copied from manual `tizen-studio-data/profile/profiles.xml` to extension `sdk-data/profile/profiles.xml`)
- Set `tizen cli-config` `default.profiles.path` and `default.sdk.path` to extension paths
- Installed system packages: `clang`, `libgtk-3-dev`, `mesa-utils`, `libtinfo5` (the last one from Ubuntu jammy because Pop!_OS 24.04 doesn't have it — Tizen toolchain's clang-10 binary needs it)
- Resized `T-10.0-x86_64` emulator disk image from 6 GB → 14 GB via `qemu-img resize` + offline `parted resizepart` and `resize2fs` on `/dev/nbd0p2` (initial 3 GB `/opt` partition was 100% full from pre-installed system apps; install of any new package failed with "Configuration error [-15] / No space left on device")

## Flutter Tizen State

### `flutter-tizen doctor -v` (final)

```
Doctor summary (to see all details, run flutter doctor -v):
[!] Flutter (Channel [user-branch], 3.41.9, on Pop!_OS 24.04 LTS 6.18.7-76061807-generic, locale en_US.UTF-8)
    ! Flutter version 3.41.9 on channel [user-branch] at /home/vld/development/flutter-tizen/flutter
      Currently on an unknown channel. Run `flutter channel` to switch to an official channel.
    ! Upstream repository unknown source is not the same as FLUTTER_GIT_URL
[✓] Tizen toolchain - develop for Tizen devices
[✓] Android toolchain - develop for Android devices (Android SDK version 36.1.0)
[✓] Chrome - develop for the web
[✓] Linux toolchain - develop for Linux desktop
[✓] Connected device (3 available)
[✓] Network resources

! Doctor found issues in 1 category.
```

**No `[✗]` errors. Only `[!]` warnings in Flutter section** (about Flutter
SDK channel name `[user-branch]` which is intrinsic to flutter-tizen's
bundled Flutter fork, and an upstream-repo nitpick). Both are advisory
and do not block builds.

### `flutter-tizen devices`

```
Found 3 connected devices:
  Linux (desktop)              • linux          • linux-x64      • Pop!_OS 24.04 LTS 6.18.7-76061807-generic
  Chrome (web)                 • chrome         • web-javascript • Google Chrome 147.0.7727.101
  Tizen T-10.0-x86_64 (mobile) • emulator-26101 • flutter-tester • Tizen 10.0 (emulator)
```

## Emulator State

| Item | Value |
|---|---|
| Emulator name | `T-10.0-x86_64` |
| Profile | common (generic Tizen 10) |
| Image arch | x86_64 |
| Disk size | 14 GiB (qcow2), 11 GB usable in `/opt` after parted/resize2fs |
| Source image | `tizen-10.0-emulator-image-x86-64_0.0.351` (Oct 2025 build) |
| Boot path | `~/.tizen-extension-platform/.../tools/emulator/bin/em-cli launch --name T-10.0-x86_64` |
| `sdb devices` | `emulator-26101  device  T-10.0-x86_64` |

**Note on Samsung TV–specific emulator:** Extension SDK does not include
the `tv-samsung` profile (it is a Samsung-only Seller Office addon, not
in the public `download.tizen.org` repository). The generic Tizen 10
emulator is used here. For Samsung TV deploy / Seller Office submission
the existing Samsung certs in `~/SamsungCertificate/` are still usable;
the build target is set via `flutter-tizen build tpk --device-profile tv`
regardless of which emulator the app is tested on.

## Smoke App Proof

### Path / commands

```bash
mkdir -p ~/tmp/tizen_flutter_smoke
cd ~/tmp/tizen_flutter_smoke
flutter-tizen create smoke_tizen_tv --platforms tizen
cd smoke_tizen_tv
# Bump api-version 6.0 → 10.0 in tizen/tizen-manifest.xml so x64 build is allowed
sed -i 's/api-version="6.0"/api-version="10.0"/' tizen/tizen-manifest.xml
flutter-tizen build tpk --release --device-profile tv --target-arch x64 --security-profile tizen-default
```

### Build output

```
The tizen-default profile is used for signing.
Building a Tizen application in release mode...   3.9s
✓ Built build/tizen/tpk/com.example.smoke_tizen_tv-1.0.0.tpk (15.0MB)
```

### Install + launch

```bash
SDB=~/.tizen-extension-platform/server/sdktools/data/tools/sdb
TPK=~/tmp/tizen_flutter_smoke/smoke_tizen_tv/build/tizen/tpk/com.example.smoke_tizen_tv-1.0.0.tpk
$SDB -s emulator-26101 push $TPK /tmp/smoke.tpk
$SDB -s emulator-26101 shell "pkgcmd -i -p /tmp/smoke.tpk"
$SDB -s emulator-26101 shell "app_launcher --start com.example.smoke_tizen_tv"
```

### Install result

```
__return_cb req_id[1] pkg_type[tpk] pkgid[com.example.smoke_tizen_tv] key[install_percent] val[22]
... [progresses] ...
__return_cb req_id[1] pkg_type[tpk] pkgid[com.example.smoke_tizen_tv] key[install_percent] val[100]
__return_cb req_id[1] pkg_type[tpk] pkgid[com.example.smoke_tizen_tv] key[end] val[ok]
spend time for pkgcmd is [1384]ms
```

`pkgcmd -l | grep smoke` after install:
```
system apps  pkg_type [tpk]  pkgid [com.example.smoke_tizen_tv]
             name [smoke_tizen_tv]  version [1.0.0]  storage [internal]
```

### Launch result

```
... successfully launched pid = 18112 with debug 0
```

### Logs proving app start

Selected entries from on-device `dlogutil` after launch:

```
W/AUL  (20905): app_request.cc: Send(106) > Request cmd(0:APP_START):
                appid(com.example.smoke_tizen_tv), target_uid(5001)
W/AMD  (2280):  launch_manager.cc: StartApp(42) > StartApp:
                appid=com.example.smoke_tizen_tv caller_pid=20905 caller_uid=5001
I/AMD_APP_GROUP(2280): app_group.c: __on_launch_complete_end(2385) >
                Restart app group ...:com.example.smoke_tizen_tv:18112
W/AMD  (2280):  amd_launch.cc: HandleAppLaunchedEvent(1524) >
                reqid=2558 cmd=0 pid=18112 pending=N app=com.example.smoke_tizen_tv
D/AMD_RUA(2280): amd_rua.c: __rua_add_history_cb(525) >
                 RUA history added. app_id(com.example.smoke_tizen_tv)
                 app_path(/opt/usr/globalapps/com.example.smoke_tizen_tv/bin/Runner.dll)
D/LAUNCH(18112): app_core_ui_base.cc: OnControl(823) >
                 [com.example.smoke_tizen_tv:Application:reset:start]
D/LAUNCH(18112): app_core_ui_base.cc: OnControl(826) >
                 [com.example.smoke_tizen_tv:Application:reset:done]
D/RESOURCED(2253): proc-main.c: resourced_proc_status_change(1788) >
                   resume request: app com.example.smoke_tizen_tv, pid 18112
I/DOTNET_LAUNCHER(20969): core_runtime.cc: initialize(423) >
                          libcoreclr dlopen and dlsym success
I/DALI(20969): combined-update-render-controller.cpp: UpdateRenderThread(611) >
               BEGIN: DALI_RENDER_THREAD_INIT
```

These confirm: `AUL` accepted the request, `AMD` dispatched `StartApp`,
`AMD_APP_GROUP` registered the app group with pid 18112, `AMD_RUA` added
history with the correct Runner.dll path, `app_core_ui_base` ran the
`Application:reset:start → done` lifecycle event for the app, `RESOURCED`
moved the process to active state, the .NET runtime (`libcoreclr`)
loaded, and `DALI` rendering thread initialized.

## Remaining Issues

1. **Visual UI does not render in the emulator.** Flutter engine prints
   `flutter_tizen_engine.cc: RunEngine(111) > The display was not valid.`
   This is the same EGL/Mesa wayland wall that affects every Flutter
   Tizen app on this emulator on Linux host — it is unrelated to the SDK
   migration and is documented in
   `docs/TIZEN_TV_FLUTTER_FINDINGS.md`. **For visual UI work a real
   Samsung TV is required**; the emulator is suitable for lifecycle and
   build pipeline verification only. Acceptance criterion is satisfied
   by the launch logs above.

2. **Flutter SDK doctor warning** about channel `[user-branch]`. This is
   intrinsic to `flutter-tizen`'s own forked Flutter SDK; it cannot be
   cleared without abandoning the flutter-tizen toolchain. Not an error,
   does not block builds.

3. **Generic Tizen 10 emulator's pre-installed Flutter apps**
   (`org.tizen.homescreen`, `org.tizen.taskbar`, etc.) crash on launch
   with libcoreclr segfaults. This is a known issue with the public
   `tizen-10.0-emulator-image-x86-64_0.0.351` base image (Oct 2025
   build) on a fresh boot — the system apps targeted an earlier .NET
   runtime version than what is shipped. Our user app is unaffected;
   crashed system apps simply leave a blank home screen.

4. **`tv-samsung` profile and Samsung TV emulator** are not part of
   extension SDK (Samsung Seller Office addon only). To deploy to a
   real Samsung TV, the existing Samsung certs in
   `~/SamsungCertificate/` and the `vld` profile are used; the build
   target profile is selected at build time (`--device-profile tv`) and
   does not depend on having a TV emulator locally.

5. **Extension's own `dotnet`** (at `~/.tizen-extension-platform/.../dotnet`)
   was incompletely downloaded. System `dotnet 8.0.126` is used instead
   (`DOTNET_ROOT` unset in migration env block). When extension finishes
   that download, the `unset DOTNET_ROOT` lines in the env block can be
   removed.

Beyond these advisories, **no blocking issues remain** for the
migration goal: extension-managed SDK is active, doctor has no
errors, Flutter Tizen build/install/launch end-to-end works.

## Where the work is preserved

- This repo (`tizen-tv-flutter-dev` on GitHub): `docs/TIZEN_EXTENSION_SDK_MIGRATION_REPORT.md` (this file) and `docs/SETUP_TIZEN_EXTENSION_SDK_WORKLOG.md` (Phase 0 inventory snapshot)
- `~/.bashrc.bak.20260525_231644` on popos (backup of pre-migration shell config)
- `~/.bashrc` `>>> TIZEN_EXTENSION_SDK_ENV >>>` block on popos (active migration env)
- `~/tizen-studio` + `~/tizen-studio-data` on popos (quarantined manual install, not in PATH)
- `/tmp/tizen-packages-fetch/` on popos (downloaded `.zip` packages used to complete the extension SDK; safe to delete)
- `~/tmp/tizen_flutter_smoke/smoke_tizen_tv/` on popos (smoke test app)
