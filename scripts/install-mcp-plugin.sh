#!/usr/bin/env bash
set -euo pipefail

WINDOWS_USER="${WINDOWS_USER:-black}"
PLUGINS_DIR="/mnt/c/Users/${WINDOWS_USER}/AppData/Local/Roblox/Plugins"

mkdir -p "$PLUGINS_DIR"

echo "Installing MCP plugin to: $PLUGINS_DIR"
MCP_PLUGINS_DIR="$PLUGINS_DIR" npx -y @chrrxs/robloxstudio-mcp@latest --install-plugin

echo ""
echo "Done. Next steps:"
echo "  1. Fully close and reopen Roblox Studio"
echo "  2. Enable Allow HTTP Requests in Game Settings → Security"
echo "  3. Reload Cursor (Ctrl+Shift+P → Reload Window)"
echo "  4. Check Plugins toolbar — MCP should show Connected"
