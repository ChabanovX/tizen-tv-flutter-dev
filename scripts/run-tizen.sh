#!/bin/bash
# Запускалка Flutter Tizen TV на эмулятор hello_tv
# Использование: ~/run-tizen.sh [build|install|run|all]   (по умолчанию all)
set -e

# Принудительно: manual install SDK + system dotnet (extension's incomplete)
export TIZEN_SDK="$HOME/tizen-studio"
export TIZEN_SDK_ROOT="$HOME/tizen-studio"
export PATH="$HOME/tizen-studio/tools/ide/bin:$HOME/development/flutter-tizen/bin:$HOME/development/flutter-tizen/flutter/bin:$PATH"
# critical: unset extension's incomplete DOTNET_ROOT (breaks Tizen.NET.Sdk loading)
unset DOTNET_ROOT
unset DOTNET_INSTALL_DIR
unset TIZEN_DOTNET_ROOT

SDB="$HOME/tizen-studio/tools/sdb"
PROJECT="$HOME/hello_tizen_tv"
APPID="com.example.hello_tizen_tv"
DEVICE="emulator-26101"
TPK="$PROJECT/build/tizen/tpk/${APPID}-1.0.0.tpk"

cd "$PROJECT"
MODE="${1:-all}"

if [ "$MODE" = "build" ] || [ "$MODE" = "all" ]; then
    echo "==> pub get + build (x64 emulator profile)"
    flutter-tizen pub get
    flutter-tizen build tpk --release --device-profile tv --target-arch x64
    ls -la "$TPK"
fi

if [ "$MODE" = "install" ] || [ "$MODE" = "all" ]; then
    echo "==> uninstall old + install fresh"
    "$SDB" -s "$DEVICE" uninstall "$APPID" 2>&1 | tail -2 || true
    sleep 1
    "$SDB" -s "$DEVICE" install "$TPK" 2>&1 | tail -5
fi

if [ "$MODE" = "run" ] || [ "$MODE" = "all" ]; then
    echo "==> launch via supported path"
    "$SDB" -s "$DEVICE" shell 0 execute "$APPID"
    echo
    echo "==> watching klog for 15 sec (Ctrl+C to stop)"
    KLOG="$HOME/tizen-studio-data/emulator/vms/hello_tv/logs/emulator.klog"
    BEFORE=$(wc -l < "$KLOG")
    sleep 15
    AFTER=$(wc -l < "$KLOG")
    echo "--- $((AFTER-BEFORE)) new klog lines ---"
    tail -n $((AFTER-BEFORE)) "$KLOG" \
        | grep -E "(__on_app_fg_launch|PHASE3|APP_CORE|LAUNCHPAD.*Execute|DOTNET_LAUNCHER.*${APPID:0:20}|MinimalNUI)" \
        | grep -v -E "(GMainLoopHandler|smart_deadlock|TVS_API)" \
        | tail -20
fi

if [ "$MODE" = "kill" ]; then
    "$SDB" -s "$DEVICE" shell 0 kill "$APPID"
fi
