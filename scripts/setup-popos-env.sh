#!/bin/bash
# Append to ~/.bashrc to override Tizen extension's incomplete SDK paths
# with the manual ~/tizen-studio install (which has tv-samsung profile).
#
# Run once: bash scripts/setup-popos-env.sh
# Or copy the block below manually into your ~/.bashrc.
set -e

MARKER="=== Tizen SDK override:"

if grep -q "$MARKER" ~/.bashrc 2>/dev/null; then
    echo "Override block already present in ~/.bashrc — skipping."
    exit 0
fi

cat >> ~/.bashrc << 'EOF'

# === Tizen SDK override: prefer manual install (~/tizen-studio) + system dotnet ===
# Extension at .tizen-extension-platform may be incomplete or missing tv-samsung
# profile. When extension is fully working and you want to switch, comment this
# block out.
if [ -f "$HOME/tizen-studio/tools/ide/bin/tizen" ]; then
    export TIZEN_SDK="$HOME/tizen-studio"
    export TIZEN_SDK_ROOT="$HOME/tizen-studio"
    export TIZEN_TOOLS_PATH="$HOME/tizen-studio/tools"
    export TIZEN_CLI_PATH="$HOME/tizen-studio/tools/ide/bin"
    export PATH="$HOME/tizen-studio/tools/ide/bin:$HOME/tizen-studio/tools:$PATH"
    # critical: use system dotnet — extension's bundled dotnet breaks Tizen.NET.Sdk
    unset DOTNET_ROOT
    unset DOTNET_INSTALL_DIR
    unset TIZEN_DOTNET_ROOT
fi
EOF

echo "Appended Tizen SDK override block to ~/.bashrc."
echo "Open a NEW terminal (or run: source ~/.bashrc) and verify:"
echo "  echo \$TIZEN_SDK     # expect: /home/vld/tizen-studio"
echo "  echo \$DOTNET_ROOT   # expect: empty"
echo "  which tizen          # expect: ~/tizen-studio/tools/ide/bin/tizen"
