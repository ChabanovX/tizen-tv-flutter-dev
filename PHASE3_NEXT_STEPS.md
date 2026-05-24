# Phase 3 — Next Steps (handoff)

## Stop reason for this session
- Path A (NUIApplication + NUIFlutterView): EXHAUSTED. MinimalNUIApp (no Flutter at all) blocks at the same OnCreate-never-fires wall.
- Path B (libecore_wl2 `_ecore_wl2_display_wait` patch): EXHAUSTED for the `access()`/SMACK hypothesis. Patch deployed, reverted — did not unblock.
- Time-budget pressure (context filling). Other Path B sub-paths remain unexecuted.

## Current proven blocker
Tizen .NET appcore main loop enters successfully but `CREATE` lifecycle event is NEVER delivered to our app's .NET layer. Same behavior across `FlutterApplication`, `NUIApplication`, and minimal `NUIApplication`-with-only-OnCreate-logging. Pre-installed Samsung apps (CSFS etc.) DO receive CREATE in the same boot.

## Hypotheses prioritized for next attempt

### H11 (highest information gain) — CONFIRMED smoking gun in iter20

**Evidence in klog right after our app's `__on_app_fg_launch start timer`**:
```
124.916 AMD_APP_GROUP: app_group.c: _app_group_get_id(252) > Failed to find app status. pid(3869)
124.922 AMD: request_manager.cc: DispatchRequest(314) > dispatch_cb fail|cmd=CUSTOM_COMMAND:205
```

**Analysis**:
- AMD's `_app_group_get_id` (in `libamd-mod-ui-core.so` @ 0x86c0) is queried with PID 3869.
- PID 3869 is a STALE pre-fork pool worker reference; the actual launched-app PID is different (matches iter5 observation pid(3910) ≠ pid(3620)).
- The lookup fails → AMD aborts dispatching `CUSTOM_COMMAND:205`.
- `dispatch_cb fail` means the cmd 205 callback chain never executes for our app.
- CUSTOM_COMMAND:205 is very likely the cmd that completes the launch handshake and lets appcore fire CREATE.

**Recommended approach**:
1. Disassemble `_app_group_get_id` in `libamd-mod-ui-core.so` at 0x86c0:
   ```
   ssh popos 'objdump -d /tmp/libamd-mod-ui-core.so | sed -n "/^00000000000086c0/,/^0000/p" | head -60'
   ```
2. Find the early-return that fires `Failed to find app status. pid(...)` log.
3. Patch the early-return to fall through to a successful lookup path. Either:
   - Always return success (return some valid app_status pointer instead of NULL)
   - OR fall back to lookup by appid using the bundle (look at `__get_caller_id`/`__app_group_can_be_leader` paths)
4. Equivalent in `libamd.so.1.78.2`'s `amd_app_status_find_by_effective_pid` — may need patching too.
5. Boot, observe whether CUSTOM_COMMAND:205 dispatches successfully and OnCreate fires.

This is the highest-information-gain step. Confirmed by direct klog evidence in the same boot that fails to fire OnCreate.

Files to patch:
- `/usr/share/amd/mod/libamd-mod-ui-core.so` (contains `_app_group_get_id` at 0x86c0)
- Possibly `/usr/lib64/libamd.so.1.78.2`
- Possibly `/usr/share/amd/mod/libamd-mod-app-status-tv.so`

Hint: existing Phase-1-era patch in `libamd-mod-app-status-tv.so` changed `__fg_launch_timeout` from 25s to 1000s via byte patch. That patch logic doesn't help OnCreate dispatch but shows the file is patchable.

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
