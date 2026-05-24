# Phase 3 — Next Steps (handoff)

## Stop reason for this session
- Path A (NUIApplication + NUIFlutterView): EXHAUSTED. MinimalNUIApp (no Flutter at all) blocks at the same OnCreate-never-fires wall.
- Path B (libecore_wl2 `_ecore_wl2_display_wait` patch): EXHAUSTED for the `access()`/SMACK hypothesis. Patch deployed, reverted — did not unblock.
- Time-budget pressure (context filling). Other Path B sub-paths remain unexecuted.

## Current proven blocker
Tizen .NET appcore main loop enters successfully but `CREATE` lifecycle event is NEVER delivered to our app's .NET layer. Same behavior across `FlutterApplication`, `NUIApplication`, and minimal `NUIApplication`-with-only-OnCreate-logging. Pre-installed Samsung apps (CSFS etc.) DO receive CREATE in the same boot.

## Hypotheses prioritized for next attempt

### H11 (highest information gain): AMD doesn't dispatch CREATE to user-installed apps
Approach:
1. Instrument `/usr/share/amd/mod/libamd-mod-app-status-tv.so` and `/usr/share/amd/mod/libamd-mod-ui-core.so` to log every cmd dispatched and to which appid/pid.
2. Compare what AMD sends to CSFS PID 1497 vs our PID 3614/3597 at launch time.
3. If AMD never sends a CREATE/RESUME message to our app, patch AMD to ALWAYS send CREATE after `__on_app_fg_launch start timer` fires.

Files to patch:
- `/usr/lib64/libamd.so.1.78.2`
- `/usr/share/amd/mod/libamd-mod-app-status-tv.so`

Hint: existing patch in this image at `libamd-mod-app-status-tv.so` (Phase 1 era) changed `__fg_launch_timeout` from 25s to 1000s via byte patch. Find that offset for context.

### H12: enlightenment lwipc subscription
- Late-spawned apps (boot+120s) missed the `/run/.wm_ready` lwipc signal published at boot+6.6s.
- Pre-fork worker pool subscribed at boot, persisted subscription across exec into target app.
- Approach: patch enlightenment's lwipc module to re-broadcast `/run/.wm_ready` periodically OR patch libecore_wl2 to use `inotify_wait_for_create_or_just_check_existence` instead of the buggy access+inotify race.

The Phase 3 iter18 binary patch at libecore_wl2 offset 0x31b51 was an ATTEMPT at this but didn't help — proves the wait isn't actually called for our app's NUI path.

### H13: Window create wait
- Tizen.NUI's DALI adaptor calls `Dali::Application::OnInit` which creates a wayland window. The window create issues `wl_compositor.create_surface` and `tizen_policy.activate_surface` requests. If enlightenment never responds with required acks (which would be the case if our app isn't on the compositor's "allowed apps" list), the DALI init hangs.
- Approach: dump the wayland traffic with `WAYLAND_DEBUG=1` (env var) and compare CSFS vs our app.

### H14 (smallest blast radius if it works): Replace appid context
- Uninstall a non-critical Samsung app (e.g. `com.samsung.tv.AOTManagerDashboard`).
- Re-install our app under that appid + signed with the platform certs that came with the image.
- If CREATE fires under hijacked system appid, the issue is confirmed to be appid-based whitelist in AMD.

### H15 (smallest binary patch): Patch dotnet-launcher-inhouse
- The launcher binary itself may have a "first-launch handshake" with AMD that our app misses.
- Compare `dotnet-launcher-inhouse` strace at launch time:
  - System app (CSFS) - what messages does it exchange in the first 500ms?
  - Our app - same window?

## Resumable state on `popos`

- Emulator image at `~/tizen-studio-data/emulator/vms/hello_tv/emulimg-hello_tv.x86_64`
- VM config in `~/tizen-studio-data/emulator/vms/hello_tv/vm_launch.conf` (modified — `maru-virtual-tuner` device REMOVED so emulator boots under Xvfb)
- All native libraries copied to `/tmp/lib*.so` for offline disassembly
- Core-filter at `/usr/local/bin/core-filter.sh` ONLY retains DN_llo*/hello_tizen*/Runner cores to prevent disk fill
- `flutter-probe.service` enabled at boot via `multi-user.target.wants/flutter-probe.service`
- Current probe script is iter17 (early-attach strace)

## Launch command (popos)
```
cd ~/tizen-studio/tools/emulator/bin
DISPLAY=:99 ./em-cli launch --name hello_tv
```
NOT `DISPLAY=:0` — the X server :0 isn't available from ssh. The `vigs_wsi` requires Xvfb :99.

## Build command (mac, this repo root)
```
EMB_PROJ=~/dev/flutter-tizen/embedding/csharp/Tizen.Flutter.Embedding/Tizen.Flutter.Embedding.csproj
dotnet build -c Release -p:FlutterEmbeddingPath=$EMB_PROJ tizen/Runner.csproj
# Output: tizen/bin/Release/tizen90/com.example.hello_tizen_tv-1.0.0.tpk
```
Then on popos, edit manifest to `dotnet-inhouse`, re-sign with `vld` profile (cert at `~/SamsungCertificate/hello-tizen-tv/`), deploy to qcow2 `/home/owner/share/tmp/sdk_tools/h.tpk`.

## Reference: ALL bytes patched so far

```
# Phase 1 (pre-Phase-3, in effect):
/usr/bin/enlightenment        @ 0x4877e   6-byte NOP -> compositor MAIN LOOP

# Phase 2 (Mesa source patches, in effect):
~/mesa-src/src/egl/drivers/dri2/platform_wayland.c   force ForceSoftware=true, route to dri2_initialize_wayland_swrast
~/mesa-src/src/egl/main/eglconfig.c                  relax SAMPLES/SAMPLE_BUFFERS criteria

# Phase 3 (in effect):
/usr/lib64/libdotnet_plugin.so   @ 0x1a574   75 4a -> eb 4a  (checkAppHasPlatformPrivilege no-op)
/usr/share/dotnet/.../libcoreclr.so   @ 0x3c73d3   74 03 -> 90 90  (TwoWayPipe::CreateServer returns 0, no DebugPipe worker)

# Reverted:
/usr/lib64/libecore_wl2.so.1.25.1   @ 0x31b51   reverted to orig (patch ineffective)
```
