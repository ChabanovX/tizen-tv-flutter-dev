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
