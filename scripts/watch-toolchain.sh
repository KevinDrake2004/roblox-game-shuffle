#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -f "$HOME/.rokit/env" ]; then
	# shellcheck disable=SC1091
	. "$HOME/.rokit/env"
fi

if ! command -v inotifywait >/dev/null 2>&1; then
	echo "inotifywait not found. Install with: sudo apt install inotify-tools" >&2
	exit 1
fi

run_checks() {
	echo ""
	echo "[watch] $(date +%H:%M:%S) running toolchain..."
	stylua src/
	if selene src/; then
		moonwave-extract extract src/shared -b src >/dev/null && echo "[watch] OK"
	else
		echo "[watch] Selene reported issues" >&2
	fi
}

echo "Watching src/ and wally.toml — Ctrl+C to stop"
echo "  • StyLua formats on each change"
echo "  • Selene + Moonwave extract validate after each change"
echo "  • wally install runs when wally.toml changes"
echo ""

LAST_WALLY_HASH=""
while true; do
	inotifywait -q -r -e modify,create,delete,move \
		--exclude '(\.git|Packages|node_modules|\.moonwave)' \
		src wally.toml 2>/dev/null || true

	if [ -f wally.toml ]; then
		HASH=$(md5sum wally.toml | awk '{print $1}')
		if [ "$HASH" != "$LAST_WALLY_HASH" ]; then
			LAST_WALLY_HASH="$HASH"
			echo "[watch] wally.toml changed — installing packages"
			wally install
		fi
	fi

	run_checks
done
