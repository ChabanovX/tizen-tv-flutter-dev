# Samsung Tizen TV Flutter — what actually works

Findings from running Flutter Tizen TV in the Samsung TV 10 emulator on
Pop!_OS 24.04 (2026-05-25 session). Two manifest metadata lines were the
root cause of the entire AMD/OnCreate wall. Sideload works via the
documented supported path. UI rendering still does NOT work in the
emulator (separate EGL/Mesa wayland wall).

## TL;DR

Strip two lines from `tizen/tizen-manifest.xml`:

```diff
-<metadata key="http://tizen.org/metadata/prefer_nuget_cache" value="true"/>
-<metadata key="http://samsung.com/tv/metadata/built-in-app" value="true"/>
```

Install via supported `sdb install` (not `pkgcmd`). Launch via supported
`sdb shell 0 execute <APP_ID>` (not `app_launcher --start`). After this,
AMD's `__on_app_fg_launch` enters the line-639 valid-flow branch and the
app proceeds through APP_CORE init.

## The three walls

| # | Wall | Cause | Fix |
|---|---|---|---|
| 1 | `sdb install` rejected with `[0, -138]` | `built-in-app=true` metadata routes the package onto Samsung's factory-app install path that rejects sideloads | Strip the metadata line |
| 2 | AMD prints `__on_app_fg_launch(633) > invalid flow` on launch | `prefer_nuget_cache=true` metadata flips AMD's launch-flow classification onto an invalid branch | Strip the metadata line |
| 3 | `OnCreate` never fires; `app.Run()` blocks; `Main Run returned` never logged | Unknown — process spawns, .NET `Main()` runs, `APP_CORE init` runs, then nothing. EGL/Mesa wayland wall (`wl_drm fd=-1`) prevents NUI/Flutter rendering, possibly blocking lifecycle dispatch as well | Not fixed — needs real Samsung TV |

Walls 1 and 2 are app-side and dev-side problems — fixable in any project.
Wall 3 is the emulator's hard limit. Visual UI work requires a real TV.

## Red herrings that wasted time in prior iterations

These appear in klog on every launch via `sdb shell 0 execute`, including
successful runs of a control blank ElmSharp app — they are **benign**
side effects of the launch helper, NOT bugs:

- `AMD_APP_GROUP: _app_group_get_id(252) > Failed to find app status. pid(N)` — `N` is the sdbu helper pid, not the launched app
- `AMD: DispatchRequest(314) > dispatch_cb fail|cmd=CUSTOM_COMMAND:205` — same root: cmd 205 lookup uses the helper pid
- `AOT_MANAGER_SERVER: aot(396) > AOT failed to create ni under pkg root` — non-fatal, app runs JIT
- `APP_CORE: app_core_rotation.cc: Init(37) > sensord_connect() is failed` — non-fatal, emulator has no rotation sensor
- `DOTNET_LAUNCHER: GetTPARO(378) > access TPA RO file errno: No such file or directory` — non-fatal warning

## A/B comparison: how walls 1 and 2 were identified

| Probe | Manifest | `sdb install` | AMD klog |
|---|---|---|---|
| Original Flutter `.tpk` | `built-in-app + prefer_nuget_cache + ...` | `install failed[0, -138]` (Wall 1) | n/a |
| After strip `built-in-app` | `prefer_nuget_cache + splash-screen-display + ...` | OK | `__on_app_fg_launch(633) > invalid flow` (Wall 2) |
| After strip `splash-screen-display` too | `prefer_nuget_cache + ...` | OK | line 633 invalid (still) |
| After strip `prefer_nuget_cache` | minimal | OK | `__on_app_fg_launch(639) > start timer for <appid>(0)` ✓ |
| Control: blank ElmSharp `.NET` TV app | minimal from start | OK | line 639 valid ✓ |

The `splash-screen-display` strip is a no-op — `prefer_nuget_cache` was
the only metadata flipping AMD's launch flow on this image.

## The supported launch path Samsung documents (vs the one prior iterations used)

| Operation | Unsupported (what was used) | Supported (per Samsung Mac .NET TV blog) |
|---|---|---|
| Install | `pkgcmd -i -p <tpk>` (forces install through low-level package manager) | `sdb install <tpk>` (goes through WAS — Web Application Service) |
| Launch | `app_launcher --start <appid>` | `sdb shell 0 execute <appid>` |

The unsupported install path is what `built-in-app=true` forces you onto.
The unsupported launch path is what you fall back to when `sdb install`
rejects your package. Removing the metadata removes the need for the
fallback.

## Local environment notes

Build verified on Pop!_OS 24.04 with:

- Tizen Studio manual install at `~/tizen-studio` (NOT the VS Code extension's bundled SDK — that one lacks `tv-samsung` profile and has frequent incomplete-download issues)
- `flutter-tizen` at `~/development/flutter-tizen`
- System `dotnet` 8.0.126 at `/usr/bin/dotnet`
- Samsung certificate at `~/SamsungCertificate/hello-tizen-tv/`, security profile `vld` in `~/tizen-studio-data/profile/profiles.xml`
- libtinfo5 from Ubuntu jammy installed for Tizen toolchain clang 10
- VS Code as native `.deb` (NOT Flatpak — Flatpak's sandbox blocks `libSDL-1.2.so.0` for the emulator binary)
- Critical env override: `DOTNET_ROOT` must be unset (or pointed at system dotnet) — the VS Code Tizen extension sets it to its own incomplete dotnet install, which breaks Tizen.NET.Sdk task loading

See `scripts/setup-popos-env.sh` for the `~/.bashrc` override block and
`scripts/run-tizen.sh` for a one-command build/install/launch wrapper.

## Build command that works

```bash
flutter-tizen build tpk --release --device-profile tv --target-arch x64
# → build/tizen/tpk/com.example.hello_tizen_tv-1.0.0.tpk (14.5 MB)
# Auto-signs with active 'vld' Samsung profile.
```

For real TV deploy use `--target-arch arm` instead. `--target-arch x64`
is for the emulator only (Tizen TV emulator is x86_64, real TV is armel
typically arm32).

## Launch + log inspection

```bash
sdb install build/tizen/tpk/com.example.hello_tizen_tv-1.0.0.tpk
sdb -s emulator-26101 shell 0 execute com.example.hello_tizen_tv

# klog filter — expect line 639 + PHASE3_STDERR Main entered + APP_CORE Init
tail -100 ~/tizen-studio-data/emulator/vms/hello_tv/logs/emulator.klog \
  | grep -E "(__on_app_fg_launch|PHASE3|APP_CORE)" \
  | grep -v -E "(GMainLoopHandler|smart_deadlock)"
```

## Out of scope / not fixed here

- **OnCreate dispatch** in the emulator after lifecycle init runs — root cause unknown, likely tied to the emulator's enlightenment/wayland compositor not delivering surface-create events to the app. Real TV deploys are the documented path for UI work.
- **Flutter engine EGL init** inside the emulator — `eglGetDisplay()` returns NULL in YAGL for sideloaded apps. Samsung's pre-installed apps render via TDM+VIGS without going through EGL, which is why home screen is visible but Flutter is not.
- **Hot reload via flutter-tizen run** — depends on the engine initializing and the VM service starting, both of which fail with the EGL wall. Use real TV for hot reload.

## Provenance

This document and the accompanying scripts come from a single 2026-05-25
debugging session that compared a control blank `.NET` TV app to the
Flutter `.tpk` via the documented supported launch path on the Samsung TV
10 emulator. The control isolated the manifest metadata as the cause and
the launch path mismatch as the trigger. Prior iterations (logged in
`PHASE3_WORKLOG.md` etc.) treated AMD klog noise as the wall itself and
ran reverse-engineering loops against it; that was misdirected effort.
