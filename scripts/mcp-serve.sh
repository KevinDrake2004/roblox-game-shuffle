#!/usr/bin/env bash
set -euo pipefail

# Keeps the MCP HTTP bridge alive for Roblox Studio on Windows.
# Run this in a dedicated WSL terminal while developing.
# Studio plugin connects to http://localhost:58741

if [ -f "$HOME/.rokit/env" ]; then
	# shellcheck disable=SC1091
	. "$HOME/.rokit/env"
fi

cd "$(dirname "$0")/.."

echo "Starting robloxstudio-mcp (Studio plugin -> http://localhost:58741)"
echo "Keep this terminal open. Press Ctrl+C to stop."
echo ""

exec npx -y @chrrxs/robloxstudio-mcp@latest
