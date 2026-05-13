---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 14:00 Europe/Moscow

### Bootstrap script for re-installing TV emulator packages

**Status:** verified

**Finding:** When `~/.tizen-extension-platform/server/sdktools/data/` gets wiped (it does — between sessions, on extension updates), the TV emulator packages can be re-downloaded straight from `https://download.tizen.org/sdk/extensions/tv_extensions/binary/` instead of going through the VS Code Tizen extension UI. The package list (with SHA256s) is preserved at `~/.tizen-extension-platform/server/sdktools/snapshots/tv-samsung/pkg_list_macos-64`.

**Evidence:**
Two scripts are now committed in `docs/`:

- `docs/bootstrap-tizen-tv-emulator.sh` — downloads 13 TV emulator zips (~910 MB), checks SHA256 against the snapshot list, unzips into `$SDK_BASE` (each zip has a top-level `data/` prefix, so unzip target must be the parent of `$DATA`).
- `docs/start-tizen-emulator.sh` — boots the image with stock QEMU 11 (`brew install qemu`) using the cmdline from the prior finding.

Quick check after bootstrap:
```bash
ls ~/.tizen-extension-platform/server/sdktools/data/platforms/tizen-10.0/tv-samsung/emulator/data/kernel/bzImage.x86_64
ls ~/.tizen-extension-platform/server/sdktools/data/platforms/tizen-10.0/tv-samsung/emulator-images/tv-samsung-10.0-x86_64/emulimg-10.0.x86_64
```

**Why it matters:** Avoids the manual VS Code Tizen extension UI flow when artifacts disappear. Repeatable from a fresh machine in ~3 minutes.

**Next action:** None. Both scripts are ready to run.

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 14:00 Europe/Moscow

### `sdb` is not in TV emulator packages — comes from `tizen-studio/tools/sdb`

**Status:** verified

**Finding:** The TV-SAMSUNG emulator zips do not include `sdb`. It belongs to Tizen Studio's common tools at `~/tizen-studio/tools/sdb`. `start-tizen-emulator.sh` falls back to it when `$TIZEN_SDK/tools/sdb` is missing. flutter-tizen, however, still expects `sdb` at `$TIZEN_SDK/tools/sdb` (from `$TIZEN_SDK = ~/.tizen-extension-platform/server/sdktools/data`); a symlink fixes that:

```bash
ln -sf ~/tizen-studio/tools/sdb ~/.tizen-extension-platform/server/sdktools/data/tools/sdb
```

**Evidence:**
```bash
flutter-tizen devices
# Before symlink: ProcessException: Failed to find ".../sdktools/data/tools/sdb"
# After symlink:   Tizen Tizen_TV_HD1080 (tv) • emulator-26101 • tizen-x64 • Tizen 10.0 (emulator)
```

**Why it matters:** flutter-tizen sees `$TIZEN_SDK` from the env that VS Code Tizen extension sets, not `~/tizen-studio`. Without this symlink, every `flutter-tizen devices`/`run` fails before even checking the emulator.

**Next action:** Bake this symlink into `bootstrap-tizen-tv-emulator.sh` (already done).

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 14:00 Europe/Moscow

### `tizen-core/tz` and `tizen` CLI also missing from the slim SDK; symlink from `~/tizen-studio`

**Status:** verified

**Finding:** flutter-tizen's build pipeline calls `tz build` from `$TIZEN_SDK/tools/tizen-core/tz` and `tizen` from `$TIZEN_SDK/tools/ide/bin/tizen`. The TV emulator zips don't ship them either — they live in `~/tizen-studio/tools/tizen-core/` and `~/tizen-studio/tools/ide/bin/`. Symlink both:

```bash
ln -sf ~/tizen-studio/tools/tizen-core ~/.tizen-extension-platform/server/sdktools/data/tools/tizen-core
mkdir -p ~/.tizen-extension-platform/server/sdktools/data/tools/ide/bin
ln -sf ~/tizen-studio/tools/ide/bin/tizen ~/.tizen-extension-platform/server/sdktools/data/tools/ide/bin/tizen
```

**Evidence:**
Without the symlinks, `flutter-tizen run` fails at `DotnetTpk.build` with:
```
ProcessException: Failed to find ".../sdktools/data/tools/tizen-core/tz" in the search path.
```

After symlinking, `tz --version` reports `Tizen cli v10.0.2`, and the build moves to the next stage.

**Why it matters:** Without these, no Tizen build target works, regardless of certs/emulator.

**Next action:** Consider extending `bootstrap-tizen-tv-emulator.sh` to add these two symlinks at the end.

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 14:00 Europe/Moscow

### flutter-tizen reads signing profile from `$TIZEN_SDK_DATA/profile/profiles.xml`, NOT `~/tizen-studio-data/profile/profiles.xml`

**Status:** verified

**Finding:** `tizen security-profiles add` and `tizen security-profiles list` write/read `~/tizen-studio-data/profile/profiles.xml`. But flutter-tizen via the extension SDK reads from `~/.tizen-extension-platform/server/sdktools/sdk-data/profile/profiles.xml` (TIZEN_SDK_DATA_PATH). They are two separate files. A leftover `test123` profile lived in the second one.

Fix: copy our profile over after each `security-profiles add`:
```bash
cp ~/tizen-studio-data/profile/profiles.xml ~/.tizen-extension-platform/server/sdktools/sdk-data/profile/profiles.xml
```

**Evidence:** Build output before fix: `The test123 profile is used for signing.` After fix: `The hello_tizen_tv profile is used for signing.`

**Why it matters:** A correctly-active profile in tizen-studio is invisible to flutter-tizen until copied. This silently kills cert work.

**Next action:** Always sync after `security-profiles add`. Could be automated in a small wrapper.

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 14:00 Europe/Moscow

### Tizen .NET SDK 9.0.304 bundled with VS Code Tizen extension is broken; reinstall from Microsoft

**Status:** verified

**Finding:** `~/.tizen-extension-platform/server/sdktools/dotnet/sdk/9.0.304/` ships incomplete — missing `dotnet.runtimeconfig.json`, `Microsoft.DotNet.Cli.Utils.dll`, and many MSBuild dlls. `tz build` calls into it and fails with:

```
A fatal error was encountered. The library 'libhostpolicy.dylib' required to execute the application
was not found in '$TIZEN_DOTNET_ROOT/sdk/9.0.304/'.
Failed to run as a self-contained app.
  - dotnet.runtimeconfig.json was not found.

# After fixing the runtimeconfig:
Could not load file or assembly 'Microsoft.DotNet.Cli.Utils, Version=9.0.304.0, ...'.
```

Fix: replace with Microsoft's official 9.0.304 SDK in-place:
```bash
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && chmod +x /tmp/dotnet-install.sh
mv ~/.tizen-extension-platform/server/sdktools/dotnet/sdk/9.0.304 ~/.tizen-extension-platform/server/sdktools/dotnet/sdk/9.0.304.bak
/tmp/dotnet-install.sh --version 9.0.304 --install-dir ~/.tizen-extension-platform/server/sdktools/dotnet --architecture arm64
```

Keep `sdk-manifests/` and `packs/` from the original Tizen install (these are Tizen-specific workloads).

**Evidence:** After reinstall, `tz build` of the dotnet project succeeds:
```
Runner -> /Users/chabanovz/work/hello_tizen_tv/tizen/bin/Debug/tizen80/com.example.hello_tizen_tv-1.0.0.tpk
Build succeeded.
```

**Why it matters:** Without this, no .NET-based Tizen TPK can be built locally, period.

**Next action:** Add the dotnet reinstall step to `bootstrap-tizen-tv-emulator.sh` as an optional repair flag, since this is wipeable in the same way as the TV packages.

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 14:00 Europe/Moscow

### `install failed[118, -12]: Check certificate error` is NOT solvable with bundled Tizen distributors; requires Samsung-issued cert

**Status:** verified (negative)

**Finding:** Samsung Tizen TV emulator (image `10.0.6`, distribution `tv-samsung`) rejects all three Tizen public distributor certificates bundled with Tizen Studio:

- `certificates/distributor/tizen-distributor-signer.p12` (public)
- `certificates/distributor/sdk-partner/tizen-distributor-signer-new.p12` (partner)
- `certificates/distributor/sdk-platform/tizen-distributor-signer-new.p12` (platform)

All three cause the same error during `pkgcmd` install:
```
app_id[com.example.hello_tizen_tv] install failed[118, -12], reason: Check certificate error
```

The author cert (locally generated via `tizen certificate -a ...`) is fine — the rejection is the distributor side. The emulator has its own trust chain that only accepts a Samsung-issued distributor cert (produced by Samsung Certificate Extension via the Samsung Developer account flow).

Tried: regenerated profile with each of the three distributors; reinstalled with each; all fail the same way at `installing[20]` step.

`sdbd_rootperm` is `disabled` and `sdb root on` returns `Permission denied`, so the trust store inside the guest cannot be patched from the host side.

**Evidence:**
```bash
$ tizen security-profiles list
[Profile Name]      [Active]
hello_tizen_tv      O

$ flutter-tizen run -d emulator-26101
The hello_tizen_tv profile is used for signing.
Installing TPK failed:
...
app_id[com.example.hello_tizen_tv] install failed[118, -12], reason: Check certificate error
```

**Why it matters:** This is the hard wall the prior note in `AGENTS.md` and `docs/codex_validate_claude_work.md` flagged. Multiple distributors do not help. Bypass requires either:
1. **Samsung Developer Account + Samsung Certificate Extension** in Tizen Studio (interactive UI flow; cannot be done via CLI alone — needs Samsung XDC enrollment and the device DUID).
2. Or developing on a **real Samsung Tizen TV in Dev Mode**, registering the TV's DUID with Samsung, and signing for that device.

**Next action:** User decision needed. Install Samsung Certificate Extension via VS Code Tizen extension UI (or Tizen Studio Package Manager → "Samsung Certificate Extension"), sign in with a Samsung account, generate a Samsung TV author + distributor cert there, then re-sign with that profile and retry. Without the Samsung account, this emulator path is blocked.

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 21:15 Europe/Moscow

### Samsung Certificate Extension's webview is broken on macOS arm64 — bypass via direct curl to `/api/v1/generateSamsungCert`

**Status:** verified

**Finding:** The VS Code Tizen extension's "Create Certificate" webview (`tizen-certificate-manager-v2`) hangs silently when the Create button is clicked. No request reaches the backend server (`~/.tizen-extension-platform/server/dist/index.js`), and the Webview Developer Tools console shows no error — pure frontend dead code path. DUID auto-detection works, form validation passes visibly, but the submit handler does nothing.

The backend server, however, is fully functional. The route `POST /api/v1/generateSamsungCert` works directly and triggers the full Samsung OAuth → CSR → `svdca.samsungqbe.com/apis/v{1,3}/{authors,distributors}` → p12 pipeline.

**Bypass — use curl directly:**

Get server port + token from `~/.tizen-extension-platform/server/conn.json`:

```bash
PORT=$(python3 -c 'import json;print(json.load(open("/Users/chabanovz/.tizen-extension-platform/server/conn.json"))["port"])')
TOKEN=$(python3 -c 'import json;print(json.load(open("/Users/chabanovz/.tizen-extension-platform/server/conn.json"))["token"])')

# Author cert. Server opens browser to Samsung OAuth on localhost:4794. User logs in once.
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{
  "profileName": "hello-tizen-tv",
  "password": "TizenAuthorPass1!",
  "certificateType": "author",
  "identity": "ivan",
  "country": "KZ"
}' "http://127.0.0.1:$PORT/api/v1/generateSamsungCert"

# Distributor cert. Needs DUID. Re-authenticates (deletes saved auth file).
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{
  "profileName": "hello-tizen-tv",
  "password": "TizenAuthorPass1!",
  "certificateType": "distributor",
  "duidList": ["XTCJYJZXZBZVK"],
  "privilege": "Public"
}' "http://127.0.0.1:$PORT/api/v1/generateSamsungCert"
```

OAuth URL (if browser doesn't open automatically):
```
https://account.samsung.com/mobile/account/check.do?serviceID=v285zxnl3h&actionID=StartOAuth2&accessToken=Y&redirect_uri=http://localhost:4794/signin/callback
```

DUID is obtained via VS Code Tizen extension's Device Manager (sdb shell on this emulator is broken — `intershell_support: disabled`).

**Evidence:**

```
$ cat /tmp/samsung_author_response.json
{"status":"success","profileName":"hello-tizen-tv","certificateType":"author",
 "certificateLocation":"/Users/chabanovz/SamsungCertificate/hello-tizen-tv/author.p12",
 "pwdLocation":"/Users/chabanovz/SamsungCertificate/hello-tizen-tv/author.pwd",
 "message":"Certificate generated successfully"}

$ ls /Users/chabanovz/SamsungCertificate/hello-tizen-tv/
author.crt    author.p12    distributor.crt    distributor.p12    samsung-auth-data.json
author.csr    author.pri    distributor.csr    distributor.pri
device-profile.xml
```

Server log of the run:
```
[Process] Generate samsung certificate: hello-tizen-tv (SUCCESS) in 6546ms
distributor.p12 file created!
```

**Why it matters:** Unblocks the entire cert workflow when the GUI is unusable. The bug in the webview is in production-shipping VS Code extension version 10.3.2; expect future agents/users to hit it too. The curl path is fully replicable.

**Next action:** None for cert generation itself — done. Document the curl flow alongside `start-tizen-emulator.sh` so it's runnable from scratch.

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 21:15 Europe/Moscow

### Samsung-issued Public TV distributor cert + emulator DUID → TPK install succeeds; cert wall broken

**Status:** verified

**Finding:** With a Samsung-issued author + distributor cert (privilege=Public, duidList=[emulator's DUID]) bound into a `tizen security-profiles` profile and synced to the slim SDK profile path, `pkgcmd` on the emulator accepts the TPK without complaint. The `install failed[118, -12], reason: Check certificate error` from the prior finding is gone.

**Evidence:**
```
$ flutter-tizen run -d emulator-26101
Launching tizen/flutter/generated_main.dart on Tizen Tizen_TV_HD1080 in debug mode...
Building a Tizen application in debug mode...
The hello_tizen_tv profile is used for signing.
Building a Tizen application in debug mode...                       4.9s
✓ Built build/tizen/tpk/com.example.hello_tizen_tv-1.0.0.tpk (48.2MB)
Installing build/tizen/tpk/com.example.hello_tizen_tv-1.0.0.tpk...        14.4s
Connecting to the device logger is taking longer than expected...
```

No install error. The remaining "Connecting to the device logger" stall is a separate issue (see next finding).

Profile that worked:
```bash
$ tizen security-profiles list
hello_tizen_tv      O

# profiles.xml content:
<profile name="hello_tizen_tv">
  <profileitem distributor="0"
      key="/Users/chabanovz/SamsungCertificate/hello-tizen-tv/author.p12" ... />
  <profileitem distributor="1"
      key="/Users/chabanovz/SamsungCertificate/hello-tizen-tv/distributor.p12" ... />
</profile>
```

Must be synced to both paths:
```bash
~/tizen-studio-data/profile/profiles.xml         # tizen CLI writes here
~/.tizen-extension-platform/server/sdktools/sdk-data/profile/profiles.xml  # flutter-tizen reads here
```

**Why it matters:** This is the hard wall that blocked the project for weeks per `AGENTS.md`. Closed.

**Next action:** None for install. Next blocker is device logger / display rendering — separate finding.

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 21:15 Europe/Moscow

### `intershell_support: disabled` on this Tizen TV emulator — `sdb shell` returns empty; dlog unreachable

**Status:** verified

**Finding:** `sdb capability` for `emulator-26101` reports:
```
intershell_support: disabled
appcmd_support: disabled
log_enable: disabled
sdbd_rootperm: disabled
```

`sdb -s emulator-26101 shell <cmd>` returns empty bytes for every command (echo, vconftool, cat, etc.). `sdb dlog` returns empty. `sdb root on` returns `Permission denied`. Only pkgcmd-style operations (install / uninstall / push / pull) work, because `pkgcmd_debugmode: enabled`.

This blocks flutter-tizen's hot-reload mechanism, which depends on tailing `dlog` to find the Dart VM Observatory URL printed by the running Flutter engine. So even after a successful `pkgcmd -i ...`, flutter-tizen hangs at `Connecting to the device logger is taking longer than expected`.

**Evidence:**
```bash
$ ~/tizen-studio/tools/sdb -s emulator-26101 capability | head
secure_protocol:enabled
intershell_support:disabled
filesync_support:pushpull
usbproto_support:disabled
sockproto_support:enabled
...
log_enable:disabled
log_path:/tmp
appcmd_support:disabled
appid2pid_support:enabled
pkgcmd_debugmode:enabled

$ ~/tizen-studio/tools/sdb -s emulator-26101 shell "echo hi" </dev/null
# (empty, immediate return)
```

**Why it matters:** Even with cert wall broken and install succeeding, flutter-tizen hot-reload can't function on this emulator config. Static install works; dynamic Dart-side tooling does not.

**Next action:** Two workarounds to try:
1. Add `hostfwd=tcp::*observatory*-:8888-8899` rule on QEMU monitor to forward Observatory ports, then attach Dart DevTools directly to `127.0.0.1:<port>` instead of waiting on dlog.
2. Check whether starting Tizen with `sdbd-env-generator` arguments adjusted (e.g., `--with-debug`) enables intershell. Both probably need digging into sdbd binary further.

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 21:30 Europe/Moscow

### Display rendering is structurally blocked on Apple Silicon — both QEMU paths fail at a different layer

**Status:** verified (negative, both branches)

**Finding:** Tried both QEMU paths to see if either renders the Tizen TV UI:

**Path A — stock QEMU 11 with virtio-vga or `-vga std` + `-display cocoa`:**
- QEMU window opens, kernel sees the PCI VGA device (`vgaarb: setting as boot device: PCI:0000:00:02.0` or `:00:03.0`), DRM core initializes (`[drm] Initialized drm 1.1.0`).
- But: **no DRM driver attaches.** Samsung's custom kernel 4.4.35 has no `bochs-drm`, `virtio-gpu`, `qxl`, or `cirrus` driver compiled in — it's built specifically for the Samsung `vigs` graphics device, which is a custom QEMU device not in stock QEMU.
- Tizen userspace (enlightenment + libevas + EFL) can never get a working EGL surface. Flutter engine binds to the libflutter_engine.so → libevas → vigs chain, fails to create a renderer, and the app crashes early. `sdb forward --list` shows Dart Observatory ports forwarded but the underlying processes never bind.

**Path B — Samsung's bundled QEMU 2.8.0 with vigs:**
- Re-applied the NOP patch at file offset `0x1d708b` (lost when bootstrap-tizen-tv-emulator.sh reinstalled the `TV-SAMSUNG-Public-Emulator` package).
- vigs device present (logs show `vigs_device_reset: VIGS reset`).
- But: **the same TCG bugs from the original session resurface** — and `Haswell-noTSX` only patches a subset. Within 80s of boot, `enlightenment` always crashes with `general protection ip:...5d2 in libevas.so.1.25.1[+0x7e5d2]` — same fixed offset every time. cynara/fconfigd/launchpad-proce also crash at their known fixed offsets. With WM dead before it ever paints, no UI is shown.

**Evidence:**
```bash
# Path A klog
[    0.524435] vgaarb: setting as boot device: PCI:0000:00:03.0
[    0.771412] [drm] Initialized drm 1.1.0
# no virtio_gpu / bochs_drm / etc. afterwards

# Path B klog
[   24.249693] traps: cynara[1277] general protection ip:7fb396ded28000 ... (+0x28000)
[   63.635897] traps: enlightenment[1335] general protection ip:7ff9c37945d2 sp:7ffc26971d40 error:0 in libevas.so.1.25.1[7ff9c3716000+1a0000]
```

**Why it matters:** Display is gated by a hard structural problem, not config. Either:
- Stock QEMU has no vigs → kernel has no display driver
- Samsung QEMU has vigs but its TCG miscompiles libevas → WM dies

Both layers are out of reach of a config tweak. Working around them means either patching QEMU 2.8's TCG (multi-week reverse-engineering of x86 instruction emulation), porting vigs to stock QEMU (Samsung-specific source needed), or rebuilding the Tizen TV kernel with virtio-gpu support (kernel build setup + Samsung patches).

**Why this is OK:** The original project goal — `flutter-tizen run -d emulator-26101` successfully **installing** the app — is achieved (`pkgcmd` returns success, no `Check certificate error`). What's not achieved is interactive UI testing. That's a separate problem space.

**Next action (recommended):** Stop pursuing display. For actual UI/UX validation, the realistic paths are:
1. Real Samsung Tizen TV in Developer Mode (sdb connect over network; full vigs+WM+UI; standard cert flow with our existing Samsung-issued profile but DUID re-bound to the TV).
2. Develop UI on Flutter desktop/web targets, validate logic, deploy to real TV only at release.
3. CI runs `flutter test` / `flutter test integration_test --headless` against the emulator for non-UI logic (install passes, Dart code runs, app lifecycle hooks fire), accepting that pixel rendering is uncovered.

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-12 22:20 Europe/Moscow

### libevas crash at `+0x7e5d2` is a QEMU 2.8 TCG bug, not a real instruction fault — RIP reporting is broken

**Status:** verified

**Finding:** Investigated whether the deterministic crash `traps: enlightenment[pid] general protection ip:...5d2 in libevas.so.1.25.1[base+1a0000]` could be defused by patching libevas. Tried two patches in the backing qcow2:

1. **Replace function entry of `_op_blend_rel_mas_c_dp` (offset 0x7e360) with `0xc3` (ret immediately).** Function should return at byte 0, never reaching anything inside.
2. **NOP out the bytes at 0x7e5cf-0x7e5d6** (the `shrl $0x18, %r14d; imull %r14d, %eax` pair that the kernel-reported IP `+0x7e5d2` falls inside).

Both patches verified intact in the qcow2 chain via `qemu-img convert -f qcow2 -O raw overlay verify.raw` + byte read at expected offsets. Both boot Samsung's QEMU 2.8 fresh. **Both produce exactly the same crash:** `general protection ip:...5d2 in libevas.so.1.25.1[base+1a0000]`. The IP offset `+0x7e5d2` is identical across runs and identical between original and patched libevas.

The only consistent explanation: Samsung's QEMU 2.8 TCG generates a **bogus saved RIP value** at exception time. The Linux kernel reports that bogus IP, and because the IP happens to fall inside the libevas VMA, the kernel attributes it to libevas. The actual faulting code is somewhere else entirely — likely in TCG-emitted x86 host code translated from some other guest x86 instruction.

**Evidence:**
```
# Patch verified in qcow2:
$ qemu-img convert -f qcow2 -O raw $OVERLAY /tmp/verify.raw
$ python3 -c "open('/tmp/verify.raw','rb').seek(0x100000+0x28191000+0x7e360); ..."
Bytes at func entry: c389c0554989cb83   # c3 = ret (patched)
Bytes at 0x7e5cf:    9090909090909090   # nops (patched)

# But guest still crashes at byte +0x272 INSIDE the function:
[   58.700840] traps: enlightenment[1336] general protection ip:7f8ca4e9a5d2 ... in libevas.so.1.25.1[7f8ca4e1c000+1a0000]
```

Confirmed deterministic across runs:
- `ip:7f18fca525d2` ... 4 separate runs, all `+0x7e5d2`
- `ip:7f5895f0a5d2`
- `ip:7fbc064335d2`
- `ip:7ff9c37945d2`
- `ip:7f288967a5d2` (with `-smp 1 noxsave nopti nokaslr`)
- `ip:7f8ca4e9a5d2` (with library byte-NOP patches)

Tried CPU and machine config variants — `-smp 1`, kernel `noxsave nopti nokaslr` — none move the crash offset. Confirms the deterministic IP is independent of CPU count, XSAVE, KASLR, or library contents.

**Why it matters:** Local-level patching of libevas/EFL cannot fix this. The bug is structural in Samsung's QEMU 2.8 TCG translator, not in any Tizen userspace binary. Therefore — Path B (libevas patching) is closed.

**Next action:** To go further, the only real path is:
1. **Rebuild Samsung's QEMU 2.8 from source** (Tizen gerrit) with TCG fixes or logging that prints the real faulting RIP. ~3-4h of build setup, then unknown reverse-engineering effort.
2. **Port the `vigs` device + `maru-x86-machine` to stock QEMU 11+**. ~Days. Requires Samsung patches.
3. **Rebuild the Tizen TV kernel** with virtio-gpu compiled in, so stock QEMU 11 can give it a display. Requires kernel source + Samsung patches + cross-build toolchain.

All three are weeks of expert work. **Recommendation: stop pursuing display on this Apple Silicon setup.** Use a real Samsung Tizen TV in Dev Mode for UI validation; keep stock QEMU 11 for non-UI work (build/install verification, CI integration, unit/integration tests that don't touch GL).

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-13 00:05 Europe/Moscow

### Custom kernel with virtio-gpu boots Tizen TV image; libevas TCG crash disappears; only Samsung-specific powerdown blocks UI

**Status:** verified (major progress, one Samsung-specific blocker remains)

**Finding:** Built a custom Tizen TV emulator kernel from public source with `CONFIG_DRM_VIRTIO_GPU=y` added. Stock QEMU 11 + this custom kernel boots successfully, virtio-gpu attaches to the virtio-vga device, framebuffer is exposed. The libevas TCG crash at `+0x7e5d2` (the show-stopper on Samsung's QEMU 2.8) **does NOT happen** with stock QEMU 11. Enlightenment starts and reaches `lwipc: c#0 '/tmp/fms_ready', status=1`.

**Steps that worked:**
1. Found kernel source at `https://git.tizen.org/cgit/sdk/emulator/emulator-kernel/`, branch `accepted/tizen_10.0_unified` (commit `39b6687fdb8e0493d9cc61423b272638ae0e9de2`). Version matches: Linux 4.4.35.
2. Downloaded snapshot via `https://git.tizen.org/cgit/sdk/emulator/emulator-kernel/snapshot/<commit>.tar.gz` (~131 MB).
3. Used Docker (Ubuntu 24.04 + `gcc-x86-64-linux-gnu` cross compiler) to build on arm64 Mac. Source MUST extract on case-sensitive FS — macOS HFS+ drops one of `xt_TCPMSS.c`/`xt_tcpmss.c`. Solution: extract inside a Docker volume.
4. Followed Samsung's own `build-x86_64.sh` recipe:
   ```bash
   ARCH=x86_64 make tizen_emul_defconfig
   sed -i "s/^EXTRAVERSION.*/EXTRAVERSION = -x86_64/" Makefile
   ./scripts/config --set-str CONFIG_INITRAMFS_SOURCE ramfs/initramfs.x86_64 -e CONFIG_CRYPTO_AES_X86_64
   # Plus our additions:
   ./scripts/config -e CONFIG_DRM_VIRTIO_GPU -e CONFIG_DRM_BOCHS -e CONFIG_DRM_QXL \
                    -e CONFIG_DRM_CIRRUS_QEMU -e CONFIG_FB_VESA -e CONFIG_FB_EFI -e CONFIG_FB_SIMPLE
   yes "" | make olddefconfig
   ARCH=x86_64 make -j$(nproc) bzImage
   ```
5. Boot with stock QEMU 11 + `-vga virtio-vga -display cocoa` + custom bzImage.

**Evidence from kernel log:**
```
[    0.826428] [drm] Initialized drm 1.1.0 20060810
[    0.828082] [drm] pci: virtio-vga detected
[    0.831713] [drm] virtio vbuffers: 80 bufs, 192B each, 15kB total.
[    0.856241] virtio_gpu virtio0: fb0: virtiodrmfb frame buffer device
[    0.891587] [drm] Initialized virtio_gpu 0.0.1 0 on minor 0
[/sbin/init] Start init process!!!!!!!!!!!!!!!!
[    7.799901] lwipc: [ 1597    enlightenment] c#0 '/tmp/fms_ready', status=1
```

`grep -c "general protection" qemu_gfx.klog` returns `0`. The libevas crash that consistently appeared on Samsung's QEMU 2.8 TCG is GONE on stock QEMU 11.

**Remaining blocker — Samsung-specific powerdown:**
~28s into boot, system powers off:
```
/usr/bin/run_enlightenment.sh: line 43: /proc/vd_signal_policy_list: No such file or directory
[   28.776741][PWR] powerdown - menu(0)/reset(-1)/always(1)/cold poweroff reason(0 - 31)
[   28.777611][PWR] reboot(poweroff)
ACPI: Preparing to enter system sleep state S5
```

`/proc/vd_signal_policy_list` is created by a Samsung TV-specific kernel module that is **not** part of the public `sdk/emulator/emulator-kernel` source. With the original Samsung kernel, this file exists and the powerdown does not happen. Some Tizen TV "no signal detected" path triggers cold poweroff.

**Why it matters:** Display problem is now provably solvable — virtio-gpu works, libevas crash is QEMU 2.8 TCG, not the binary. The remaining work is unlocking Samsung's TV-specific kernel bits OR patching userspace `run_enlightenment.sh` to ignore the missing proc file.

**Next actions:**
1. Look for the TV-specific module source (likely `platform/kernel/linux-tizen-modules` or a Samsung-internal repo).
2. Or patch `/usr/bin/run_enlightenment.sh` in the qcow2 to handle missing `/proc/vd_signal_policy_list` gracefully (faster path).
3. Or add a kernel cmdline / module that fakes the proc file.

Artifacts saved at `docs/kernel-build/`:
- `bzImage.x86_64.gfx` — our custom kernel with virtio-gpu
- `samsung-original.sh` — Samsung's build script (reference)
- `tizen_emul_defconfig` — base config

---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-05-13 10:25 Europe/Moscow

### Patching `deviced` powerdown_ap to no-op survives the 28s blocker; install works on custom kernel; app still can't render due to vigs ioctl mismatch

**Status:** verified (significant progress, but Tizen userspace vigs dependency is the new wall)

**Finding:** The 28s poweroff was triggered by `/usr/bin/deviced` (Samsung's power-management daemon) in its `powerdown_ap` function — not by the missing `/proc/vd_signal_policy_list` write in `run_enlightenment.sh`. The script's write to that proc file fails harmlessly. The actual trigger:

```
[8.816598][PWR] Invalid wakeup reason (-1924389768) perform standby reboot
[8.822666][PWR] standby reboot invalid wakeup reason
```

`deviced.power-interface.c:pi_get_wakeup_reason` calls a vd_signal-based kernel function which returns garbage when the TV module isn't loaded; this drives `powerdown_ap` to call `reboot(LINUX_REBOOT_MAGIC1)` after a timer.

**Patch applied:** First byte of `powerdown_ap` at deviced file offset `0x909d0` changed from `55` (push rbp) to `c3` (ret). Patched deviced is at file offset `0x46400000 + 0x909d0 = 0x465909d0` in partition 0 of the qcow2 backing. New backing: `/tmp/tizen-patched/base_deviced.qcow2`. Stock QEMU 11 + custom kernel (`docs/kernel-build/bzImage.x86_64.gfx`) + this backing reproducibly boots past 28s and reaches userspace.

**Verified working after the patch:**
- Boot reaches 124s+ without poweroff
- SDB device ready: `emulator-26101 device Tizen_TV_HD1080`
- pkgmgr install succeeds (TPK takes ~85s with WAS chain in cold-start)
- Samsung-issued cert still accepted

**New wall — Tizen libdrm_vigs vs virtio_gpu:**
After install, flutter-tizen attempts to launch the app. sdb forwards are created (e.g. `tcp:51781 → tcp:51781`, `tcp:49431 → tcp:49431`) which means flutter-tizen detected the Observatory port intent — but TCP connections to them get `Connection reset by peer`, meaning the underlying process (the Flutter engine) crashed before binding.

Klog shows the cause:
```
E/AVE: drmWaitVBlank (relative) failed ret: -1, DRM FD: 22, 22:Invalid argument
```
…spammed continuously. Samsung Tizen userspace (`libdrm_vigs.so.10.0.0`, EFL, AVE/AVOC) speaks vigs-specific DRM ioctls. Our kernel now has `virtio_gpu` (which exposes `/dev/dri/card0`), but virtio_gpu doesn't understand vigs ioctls and returns `EINVAL`. Every display-touching component fails: AVE waits for vblank, AVOC waits for EDID init, libflutter_engine fails to make an EGL surface, app exits.

**Why it matters:** The chain is fundamentally hybrid:
- Kernel side: stock virtio_gpu works
- Userspace side: hardcoded for Samsung's custom vigs ABI

Path A (port vigs device to QEMU 11+): same multi-week kernel/QEMU work as before.
Path B (write a vigs-compatible kernel driver that maps to virtio_gpu commands): plausible but requires understanding vigs ioctl set (we have `include/drm/vigs_drm.h` from the source) and writing a translation layer — days of work.
Path C (patch libdrm_vigs to fall back to generic DRM/KMS): also days.

**Why this is a stopping point:** This is the same display-rendering wall as documented earlier, just now with a clearer attribution: not TCG bugs (already fixed by switching to QEMU 11), not power-management triggers (fixed by the deviced patch), but the vigs ABI hardcoded into Tizen TV userspace. None of those further paths is a quick win.

**Current usable state:**
- Build / install / cert flow works end-to-end
- Pixel rendering unavailable (which is the same state as before our display work)
- Net new capability: a kernel + qcow2 combo where boot doesn't die at 28s, giving more guest-side time to do non-rendering work

Artifacts:
- `docs/kernel-build/bzImage.x86_64.gfx` (custom kernel with virtio-gpu)
- `/tmp/tizen-patched/base_deviced.qcow2` (qcow2 with patched deviced; reproducible from `base_patched.qcow2` source via the byte-write at offset `0x465909d0`)

**Next action:** User decision. Honest summary — display rendering needs either Samsung's vigs in QEMU (no public source) or a vigs↔virtio_gpu shim (significant kernel engineering). For developing Flutter Tizen TV apps on Apple Silicon today, the pragmatic stack is:
1. This setup (custom kernel + patched deviced + stock QEMU 11) for build/install/cert validation
2. Real Samsung TV in Dev Mode for actual UI/rendering testing
