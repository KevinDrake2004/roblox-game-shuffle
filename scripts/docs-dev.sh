#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d node_modules/moonwave ]; then
	echo "Installing Moonwave docs CLI..."
	npm install
fi

echo "Starting docs dev server (http://localhost:3000)"
exec npx moonwave dev --code src
