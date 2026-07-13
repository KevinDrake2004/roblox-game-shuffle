#!/usr/bin/env bash
set -euo pipefail

if [ -f "$HOME/.rokit/env" ]; then
	# shellcheck disable=SC1091
	. "$HOME/.rokit/env"
fi

cd "$(dirname "$0")/.."

echo "==> Selene"
selene src/

echo "==> StyLua"
stylua --check src/

echo "==> Moonwave extract"
moonwave-extract extract src/shared -b src

echo "All checks passed."
