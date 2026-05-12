#!/bin/bash
# Bootstrap script: re-installs Samsung TV Tizen 10.0 emulator artifacts that
# the VS Code Tizen extension's package manager has marked installed but whose
# files have been wiped from $SDK_BASE/data/.
#
# Downloads the same .zip packages the extension uses, unpacks them to the same
# paths, then leaves you ready to run /tmp/tizen-utm/start-tizen-emulator.sh.
#
# Pre-req: brew install qemu  (for qemu-system-x86_64 11.x — the official QEMU
#          2.8 in the Samsung bundle doesn't work on Apple Silicon).

set -euo pipefail

SDK_BASE="$HOME/.tizen-extension-platform/server/sdktools"
DATA="$SDK_BASE/data"
DOWNLOADS="$SDK_BASE/download-emulator"
REPO="https://download.tizen.org/sdk/extensions/tv_extensions"

# Each zip has a top-level "data/" prefix, so we unzip into $SDK_BASE (parent of $DATA).
UNZIP_TARGET="$SDK_BASE"

# Packages we need, with their archive paths under $REPO/binary/.
# Order: emulator core (qemu/kernel/utils) → image → resources → control-panel.
PKGS=(
  "tv-samsung-emulator-qemu-common_2.8.0.38_macos-64.zip"
  "tv-samsung-emulator-qemu-x86_2.8.0.38_macos-64.zip"
  "tv-samsung-emulator-kernel-x86_4.4.35.24_macos-64.zip"
  "tv-samsung-emulator-lib_1.12.0_macos-64.zip"
  "tv-samsung-emulator-resources_10.0.0_macos-64.zip"
  "tv-samsung-emulator-still-image_10.0.0_macos-64.zip"
  "tv-samsung-emulator-manager-resources_10.0.0_macos-64.zip"
  "tv-samsung-emulator-control-panel-devices_10.0.1_macos-64.zip"
  "TV-SAMSUNG-Emulator-Utils_10.0.0_macos-64.zip"
  "TV-SAMSUNG-Public-Emulator_10.0.0_macos-64.zip"
  "tv-samsung-public-emulator-image-x86-64_10.0.6_macos-64.zip"
  "tv-samsung-libav_10.8.0_macos-64.zip"
  "tv-samsung-log-server_5.5.0_macos-64.zip"
)

mkdir -p "$DOWNLOADS"
mkdir -p "$DATA"

for pkg in "${PKGS[@]}"; do
  out="$DOWNLOADS/$pkg"
  if [[ ! -s "$out" ]]; then
    echo "↓ Downloading $pkg"
    curl -fsSL -o "$out" "$REPO/binary/$pkg"
  else
    echo "✓ Cached $pkg"
  fi
done

echo ""
echo "==> Verifying checksums against snapshot list"
fail=0
while read -r pkg expected; do
  out="$DOWNLOADS/$pkg"
  [[ -s "$out" ]] || continue
  got=$(shasum -a 256 "$out" | awk '{print $1}')
  if [[ "$got" != "$expected" ]]; then
    echo "  ✗ $pkg: hash mismatch (got $got, expected $expected)"
    fail=1
  fi
done < <(
  awk '
    /^Package :/ { p=$3 }
    /^Path :/    { gsub("/binary/", "", $3); path=$3 }
    /^SHA256 :/  { print path, $3 }
  ' "$SDK_BASE/snapshots/tv-samsung/pkg_list_macos-64" \
  | awk -v pkgs="${PKGS[*]}" 'BEGIN { n=split(pkgs, arr, " "); for(i=1;i<=n;i++) need[arr[i]]=1 } need[$1] { print }'
)
[[ "$fail" -eq 0 ]] || { echo "Checksum verification failed; aborting"; exit 1; }
echo "All checksums OK"

echo ""
echo "==> Unpacking into $UNZIP_TARGET (each zip has top-level data/ prefix)"
for pkg in "${PKGS[@]}"; do
  echo "  → $pkg"
  unzip -oq "$DOWNLOADS/$pkg" -d "$UNZIP_TARGET"
done

# Restore exec bits on common helpers / emulator binaries
echo ""
echo "==> Fixing exec bits"
find "$DATA/tools" -type f \( -name "qemu-img" -o -name "check-*" -o -name "sdb" -o -name "emulator*" \) -exec chmod +x {} \; 2>/dev/null || true
find "$DATA/platforms" -type f \( -name "emulator-x86_64" -o -name "qemu-system-*" -o -name "*.sh" \) -exec chmod +x {} \; 2>/dev/null || true

echo ""
echo "==> Quick sanity check"
KERNEL="$DATA/platforms/tizen-10.0/tv-samsung/emulator/data/kernel/bzImage.x86_64"
IMAGE="$DATA/platforms/tizen-10.0/tv-samsung/emulator-images/tv-samsung-10.0-x86_64/emulimg-10.0.x86_64"
for f in "$KERNEL" "$IMAGE"; do
  if [[ -e "$f" ]]; then
    echo "  ✓ $f ($(du -h "$f" | awk '{print $1}'))"
  else
    echo "  ✗ MISSING: $f"
  fi
done

# sdb is not part of the TV emulator packages; start-tizen-emulator.sh will
# fall back to $HOME/tizen-studio/tools/sdb. Just check it's reachable.
if [[ -x "$HOME/tizen-studio/tools/sdb" ]]; then
  echo "  ✓ sdb (fallback): $HOME/tizen-studio/tools/sdb"
else
  echo "  ⚠ sdb not found at $HOME/tizen-studio/tools/sdb — install Tizen Studio common tools"
fi

echo ""
echo "Done. Next: bash docs/start-tizen-emulator.sh"
