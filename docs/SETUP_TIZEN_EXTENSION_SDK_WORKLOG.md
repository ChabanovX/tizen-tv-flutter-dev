# Tizen Extension SDK Migration — popos Worklog

Migration from manual `~/tizen-studio` (patched) to VS Code Tizen Extension
managed SDK at `~/.tizen-extension-platform/server/sdktools/data`.

Started: 2026-05-25, popos (Tailscale `100.101.239.6`).

## Phase 0 — Environment inspection

**OS / shell:** Pop!_OS 24.04 LTS, kernel 6.18.7, x86_64, `/bin/bash`.

**VS Code:**
- Native `.deb` `/usr/bin/code` v1.121.0 (preferred for migration target)
- Flatpak `com.visualstudio.code` (must be ignored — Flatpak sandbox blocks `libSDL-1.2.so.0` for emulator binary)

**Extensions (native VS Code):**
- `tizen.vscode-tizen-csharp-10.3.5`
- `dart-code.dart-code-3.134.0`
- `dart-code.flutter-3.134.0`
- `ms-vscode.cpptools-1.32.2-linux-x64`

**Flutter installs detected (will reconcile):**
- `~/development/flutter` (3.44.0 stable) — first in PATH
- `~/develop/flutter` (older) — lower PATH precedence
- `~/development/flutter-tizen/flutter` (3.41.9, user-branch) — flutter-tizen's bundled

**Tizen SDKs on disk:**
| Path | Size | Status |
|---|---|---|
| `~/tizen-studio` | 24 GB | manual install, **active**, has `tv-samsung` profile |
| `~/tizen-studio-data` | 15 GB | manual install data (profiles.xml, VMs, logs) |
| `~/.tizen-extension-platform` | 13 GB | extension SDK, **72% installed (110/151)**, missing critical packages |
| `~/SamsungCertificate` | 92 KB | Samsung dev certs (author.p12, distributor.p12) — preserve |

**Active env vars (before migration):**
```
TIZEN_SDK=/home/vld/tizen-studio
TIZEN_SDK_ROOT=/home/vld/tizen-studio
TIZEN_TOOLS_PATH=/home/vld/tizen-studio/tools
TIZEN_CLI_PATH=/home/vld/tizen-studio/tools/ide/bin
PATH=...tizen-studio/tools/ide/bin...tizen-studio/tools...tizen-extension-platform/.../dotnet (x3)...tizen-extension-platform/.../data (x3)...flutter-tizen/bin...development/flutter/bin...develop/flutter/bin...
```

**Extension SDK content (state before migration):**
- ✓ `tools/sdb` exists at `~/.tizen-extension-platform/server/sdktools/data/tools/sdb`
- ✗ `tools/ide/bin/tizen` **MISSING** (critical, blocks all CLI workflow)
- ✓ `platforms/tizen-10.0`, `tizen-9.0` dirs exist but contents partial
- ✗ Emulator binaries (qemu, kernel, lib) — failed downloads
- ✗ Emulator disk images (T-10.0-x86_64, T-9.0-x86_64) — 0 bytes

**Failed package downloads (from extension log, 3 retries each):**
- `10.0-MANDATORY_0.0.35` (contains `tizen` CLI itself)
- `10.0-platform-info_5.2.8`
- `10.0-efl-renderer_0.8.7`
- `10.0-efl-tools_1.23.5`
- `10.0-emulator-qemu-x86_5.0.3.6`
- `10.0-emulator-kernel-x86_4.4.35.37`
- `10.0-emulator-lib_1.8.3`
- `10.0-emulator-qemu-common_5.0.3.6`
- `10.0-libav_10.3.7`
- `10.0-vs-tools-add-ons_0.0.222`
- `9.0-emulator-kernel-x86_4.4.35.36`
- `dotnet-sdk-9.0.304-linux-x64.tar.gz`
- `Microsoft.VisualStudio.Services.VSIXPackage` (dotnet extension)

**Strategy:** Force re-fetch of missing packages directly from `download.tizen.org` URLs (same as extension uses), then resume migration.
