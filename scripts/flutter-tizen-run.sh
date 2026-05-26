#!/bin/bash
# flutter-tizen-run.sh — one-command build/install/launch for Flutter Tizen
# on the popos emulator with the VS Code Tizen Extension–managed SDK.
#
# Usage:
#   ~/flutter-tizen-run.sh              # build + install + launch CWD project
#   ~/flutter-tizen-run.sh <path>       # same but for given project dir
#   ~/flutter-tizen-run.sh -- <flutter-tizen build args>     # custom build args
#   ~/flutter-tizen-run.sh build        # only build
#   ~/flutter-tizen-run.sh install      # only install + launch
#   ~/flutter-tizen-run.sh launch       # only launch (no install)
#   ~/flutter-tizen-run.sh kill         # kill running app
#   ~/flutter-tizen-run.sh dlog         # tail dlog filtered to app
#   ~/flutter-tizen-run.sh emulator-start
#   ~/flutter-tizen-run.sh emulator-stop
#   ~/flutter-tizen-run.sh emulator-reset       # nuke + fresh disk + resize +14G
#
# Defaults:
#   profile  = tv
#   arch     = x64        (Tizen 10 x86_64 emulator)
#   security = tizen-default   (NOT Samsung 'vld' — generic Tizen emulator)
#   release  = --release
#
# Required env (auto-detected if not set):
#   TIZEN_SDK      = ~/.tizen-extension-platform/server/sdktools/data
#   TIZEN_SDK_DATA = ~/.tizen-extension-platform/server/sdktools/sdk-data

set -e
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'
say() { printf "${CYN}[run-tizen]${NC} %s\n" "$*" >&2; }
ok()  { printf "${GRN}[run-tizen]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[run-tizen]${NC} %s\n" "$*" >&2; }
warn(){ printf "${YEL}[run-tizen]${NC} %s\n" "$*" >&2; }

# Auto-detect SDK paths
EXT_SDK="${TIZEN_SDK:-$HOME/.tizen-extension-platform/server/sdktools/data}"
EXT_SDK_DATA="${TIZEN_SDK_DATA:-$HOME/.tizen-extension-platform/server/sdktools/sdk-data}"
[ -d "$EXT_SDK" ]      || { err "TIZEN_SDK not found at $EXT_SDK"; exit 1; }
[ -d "$EXT_SDK_DATA" ] || { err "TIZEN_SDK_DATA not found at $EXT_SDK_DATA"; exit 1; }

SDB="$EXT_SDK/tools/sdb"
EM_CLI="$EXT_SDK/tools/emulator/bin/em-cli"
DEVICE="${DEVICE:-emulator-26101}"
VM_NAME="${VM_NAME:-T-10.0-x86_64}"
VM_DIR="$EXT_SDK_DATA/emulator/vms/$VM_NAME"
BASE_IMG="$EXT_SDK/platforms/tizen-10.0/tizen/emulator-images/tizen-10.0-x86_64/emulimg-10.0.x86_64"

export PATH="$EXT_SDK/tools/ide/bin:$EXT_SDK/tools:$HOME/development/flutter-tizen/bin:$HOME/development/flutter-tizen/flutter/bin:$PATH"
export TIZEN_SDK="$EXT_SDK"
export TIZEN_SDK_ROOT="$EXT_SDK"
export TIZEN_SDK_DATA="$EXT_SDK_DATA"
unset DOTNET_ROOT DOTNET_INSTALL_DIR TIZEN_DOTNET_ROOT

# Helpers
emulator_running() { pgrep -af "emulator-x86_64.*--conf.*$VM_NAME" >/dev/null; }
emulator_alive_sdb() { "$SDB" devices 2>/dev/null | grep -q "$DEVICE"; }
detect_appid() {
    local project="$1"
    local manifest="$project/tizen/tizen-manifest.xml"
    [ -f "$manifest" ] || return 1
    grep -oP 'appid="\K[^"]+' "$manifest" | head -1
}
detect_project() {
    local d="${1:-$PWD}"
    while [ "$d" != "/" ]; do
        [ -f "$d/pubspec.yaml" ] && [ -d "$d/tizen" ] && { echo "$d"; return 0; }
        d=$(dirname "$d")
    done
    return 1
}

# Dispatch sub-commands
CMD="${1:-all}"

case "$CMD" in
    emulator-start)
        if emulator_running; then ok "emulator already running"; exit 0; fi
        say "starting $VM_NAME on Xvfb :99"
        cd "$EXT_SDK/tools/emulator/bin"
        DISPLAY=:99 nohup ./em-cli launch --name "$VM_NAME" > /tmp/em.log 2>&1 </dev/null &
        disown
        say "waiting for sdb to see device..."
        for i in $(seq 1 60); do
            sleep 3
            if emulator_alive_sdb; then ok "emulator up: $DEVICE"; exit 0; fi
        done
        err "emulator didn't come up in 3 min. Check /tmp/em.log"
        tail -20 /tmp/em.log >&2
        exit 1
        ;;

    emulator-stop)
        say "stopping emulator"
        pkill -TERM -f "emulator-x86_64.*--conf.*$VM_NAME" 2>/dev/null && ok stopped || warn "no emulator running"
        exit 0
        ;;

    emulator-reset)
        say "stopping emulator if running"
        pkill -TERM -f "emulator-x86_64.*--conf.*$VM_NAME" 2>/dev/null || true
        sleep 5
        say "replacing disk with fresh base image"
        rm -f "$VM_DIR/emulimg-$VM_NAME.x86_64"
        cp "$BASE_IMG" "$VM_DIR/emulimg-$VM_NAME.x86_64"
        say "resizing qcow2 to 14G"
        qemu-img resize "$VM_DIR/emulimg-$VM_NAME.x86_64" 14G
        say "growing partition + resize2fs (needs sudo)"
        sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true
        sleep 1
        sudo qemu-nbd --connect=/dev/nbd0 -f qcow2 "$VM_DIR/emulimg-$VM_NAME.x86_64"
        sleep 2
        sudo partprobe /dev/nbd0 || true
        sudo parted /dev/nbd0 resizepart 2 100% 2>&1 | tail -2
        sudo partprobe /dev/nbd0 || true
        sleep 1
        sudo e2fsck -fy /dev/nbd0p2 2>&1 | tail -2
        sudo resize2fs /dev/nbd0p2 2>&1 | tail -1
        sudo qemu-nbd --disconnect /dev/nbd0
        ok "disk reset complete"
        "$0" emulator-start
        exit $?
        ;;
esac

# For build/install/launch we need a project
PROJECT_ARG="${PROJECT_DIR:-}"
if [ -z "$PROJECT_ARG" ]; then
    if [ -n "$2" ] && [ -d "$2" ]; then PROJECT_ARG="$2"; fi
fi
PROJECT=$(detect_project "${PROJECT_ARG:-$PWD}") || {
    err "no Flutter Tizen project found (need pubspec.yaml + tizen/ subdir). Run from project root or pass path."
    exit 1
}
APPID=$(detect_appid "$PROJECT") || { err "cannot read appid from $PROJECT/tizen/tizen-manifest.xml"; exit 1; }
TPK="$PROJECT/build/tizen/tpk/${APPID}-1.0.0.tpk"
KLOG="$VM_DIR/logs/emulator.klog"

cd "$PROJECT"
say "project: $PROJECT"
say "appid:   $APPID"

# Build flags (overridable via env)
FT_PROFILE="${FT_PROFILE:-tv}"
FT_ARCH="${FT_ARCH:-x64}"
FT_CERT="${FT_CERT:-tizen-default}"
FT_MODE="${FT_MODE:---release}"

case "$CMD" in
    build|all)
        say "fixing manifest api-version if 6.0 (flutter-tizen default — incompatible with x64)"
        sed -i 's/api-version="6.0"/api-version="10.0"/' tizen/tizen-manifest.xml || true

        say "flutter-tizen pub get"
        flutter-tizen pub get >/dev/null

        say "flutter-tizen build tpk $FT_MODE --device-profile $FT_PROFILE --target-arch $FT_ARCH --security-profile $FT_CERT"
        flutter-tizen build tpk $FT_MODE --device-profile "$FT_PROFILE" --target-arch "$FT_ARCH" --security-profile "$FT_CERT" 2>&1 | tail -10
        [ -f "$TPK" ] && ok ".tpk built: $TPK ($(du -h "$TPK" | cut -f1))" || { err "build did not produce $TPK"; exit 1; }
        ;;
esac

case "$CMD" in
    install|all)
        emulator_alive_sdb || { warn "emulator not connected — starting"; "$0" emulator-start; }
        [ -f "$TPK" ] || { err "no .tpk at $TPK. Run build first."; exit 1; }

        # Ensure target dir exists (sdk_tools push target)
        "$SDB" -s "$DEVICE" shell "mkdir -p /home/owner/share/tmp/sdk_tools" >/dev/null 2>&1 || true

        # Uninstall previous (ignore errors)
        say "uninstalling old version (if any)"
        "$SDB" -s "$DEVICE" uninstall "$APPID" 2>&1 | tail -1 || true

        say "sdb install $TPK"
        OUT=$("$SDB" -s "$DEVICE" install "$TPK" 2>&1)
        echo "$OUT" | tail -3
        echo "$OUT" | grep -q "key\[end\] val\[ok\]" || {
            err "install failed"
            # Heuristic: /opt full?
            if echo "$OUT" | grep -q "Configuration error" || "$SDB" -s "$DEVICE" shell "df /opt" 2>&1 | grep -q "100%"; then
                err "looks like /opt is full. Run: $0 emulator-reset"
            elif echo "$OUT" | grep -q "Invalid certificate"; then
                err "cert chain rejected. Build with FT_CERT=vld or different profile."
            fi
            exit 1
        }
        ok "installed"
        ;;
esac

case "$CMD" in
    launch|all)
        emulator_alive_sdb || { err "emulator not connected"; exit 1; }
        BEFORE=$(wc -l < "$KLOG" 2>/dev/null || echo 0)
        say "app_launcher --start $APPID"
        "$SDB" -s "$DEVICE" shell "app_launcher --start $APPID" 2>&1
        sleep 5
        AFTER=$(wc -l < "$KLOG" 2>/dev/null || echo 0)
        DELTA=$((AFTER-BEFORE))
        say "klog activity since launch ($DELTA new lines, filtered):"
        if [ "$DELTA" -gt 0 ]; then
            tail -n "$DELTA" "$KLOG" \
                | grep -E "($APPID|__on_app_fg_launch|LAUNCHPAD.*Execute|DOTNET_LAUNCHER|APP_CORE|DALI_RENDER)" \
                | grep -v -E "(GMainLoopHandler|smart_deadlock|TVS_API|BXT)" \
                | tail -15
        else
            warn "no new klog lines (timing race or another logger)"
        fi
        ok "launched. App will hang at engine init due to EGL/Mesa wall — that's expected."
        say "Use: $0 dlog   to follow live logs"
        ;;
esac

case "$CMD" in
    kill)
        say "killing $APPID"
        "$SDB" -s "$DEVICE" shell "app_launcher --kill $APPID" 2>&1
        ;;
    dlog)
        say "streaming dlog filtered to $APPID (Ctrl+C to stop)"
        "$SDB" -s "$DEVICE" dlog "$APPID:* DOTNET_LAUNCHER:* APP_CORE:* DALI:* *:S" 2>&1
        ;;
esac
