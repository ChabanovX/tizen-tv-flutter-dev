#!/bin/bash
# Start Tizen TV emulator using stock QEMU 11 (much faster + correct than
# Samsung's bundled QEMU 2.8 on Apple Silicon).
#
# Pre-reqs:
#   1. brew install qemu  (provides /opt/homebrew/bin/qemu-system-x86_64 ≥11.0)
#   2. Tizen TV 10.0 emulator artifacts present under
#      ~/.tizen-extension-platform/.../data/platforms/tizen-10.0/tv-samsung/...
#      If missing, first run: bash docs/bootstrap-tizen-tv-emulator.sh
#
# Boot reaches sdbd-ready in ~100s on M-series. Verified working 2026-04-28.

set -e

VM_DIR=/tmp/tizen-utm
KERNEL="$HOME/.tizen-extension-platform/server/sdktools/data/platforms/tizen-10.0/tv-samsung/emulator/data/kernel/bzImage.x86_64"
BACKING="$HOME/.tizen-extension-platform/server/sdktools/data/platforms/tizen-10.0/tv-samsung/emulator-images/tv-samsung-10.0-x86_64/emulimg-10.0.x86_64"
SDB="$HOME/.tizen-extension-platform/server/sdktools/data/tools/sdb"

# Fall back to tizen-studio's sdb if the extension's is missing
if [[ ! -x "$SDB" ]]; then
  SDB="$HOME/tizen-studio/tools/sdb"
fi

# Sanity-check required files exist before doing anything destructive
for f in "$KERNEL" "$BACKING" "$SDB"; do
  if [[ ! -e "$f" ]]; then
    echo "✗ Missing: $f"
    echo "  Run docs/bootstrap-tizen-tv-emulator.sh first to restore TV emulator packages."
    exit 1
  fi
done

mkdir -p "$VM_DIR"

# Fresh overlay (don't disturb the Samsung-managed one)
[ -f "$VM_DIR/tizen_overlay.qcow2" ] || \
  qemu-img create -f qcow2 -F qcow2 -b "$BACKING" "$VM_DIR/tizen_overlay.qcow2" >/dev/null

# Kill anything stale and clear klog
pkill -9 -f qemu-system-x86_64 2>/dev/null || true
sleep 1
> "$VM_DIR/qemu.klog"

# SDB server must listen on host:26099 BEFORE guest boots — guest's sdbd
# connects out via SLIRP to 10.0.2.2:26099 (which routes to host's 127.0.0.1)
"$SDB" start-server >/dev/null 2>&1 || true

# vm_name must not contain spaces or commas
# (sdbd-env-generator awk regex: /vm_name=([^, ]*)/)
VM_NAME=Tizen_TV_HD1080
SDB_PORT=26100

qemu-system-x86_64 \
  -accel tcg \
  -machine pc \
  -cpu Haswell-noTSX \
  -smp 4 \
  -m 1024 \
  -drive file="$VM_DIR/tizen_overlay.qcow2",if=virtio,format=qcow2,cache=writeback \
  -kernel "$KERNEL" \
  -append "vm_name=$VM_NAME video=LVDS-1:1920x1080-32@60 dpi=72 clocksource=hpet consoleblank=0 console=ttyS0 model=4ksero ip=10.0.2.15::10.0.2.2:255.255.255.0::eth0:off host_ip=10.0.2.2 sdb_port=$SDB_PORT, vm_resolution=1920x1080" \
  -netdev user,id=net0,hostfwd=tcp::26101-:26101,hostfwd=tcp::26102-:26102 \
  -device e1000,netdev=net0 \
  -chardev file,path="$VM_DIR/qemu.klog",id=con0 \
  -device isa-serial,chardev=con0 \
  -monitor telnet:127.0.0.1:55222,server,nowait \
  -display none \
  -no-reboot \
  -nodefaults &

QEMU_PID=$!
echo "QEMU started (PID $QEMU_PID). Booting Tizen TV..."
echo "  klog:    $VM_DIR/qemu.klog"
echo "  monitor: telnet 127.0.0.1 55222"
echo "  Wait ~100s for sdbd to register, then: sdb devices"

# Wait for SDB to see the device
for i in $(seq 1 60); do
  sleep 5
  if "$SDB" devices 2>/dev/null | grep -q emulator-26101; then
    echo ""
    echo "✅ SDB device ready: emulator-26101"
    "$SDB" devices
    exit 0
  fi
  printf "."
done
echo ""
echo "⚠️  Timed out waiting for sdbd to register; check $VM_DIR/qemu.klog"
exit 1
