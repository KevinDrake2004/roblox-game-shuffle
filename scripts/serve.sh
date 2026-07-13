#!/usr/bin/env bash
set -euo pipefail

if [ -f "$HOME/.rokit/env" ]; then
	# shellcheck disable=SC1091
	. "$HOME/.rokit/env"
else
	echo "Rokit not found. Install it with:" >&2
	echo "  curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash" >&2
	exit 1
fi

cd "$(dirname "$0")/.."
exec rojo serve "$@"
