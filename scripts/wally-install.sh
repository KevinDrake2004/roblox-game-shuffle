#!/usr/bin/env bash
set -euo pipefail

if [ -f "$HOME/.rokit/env" ]; then
	# shellcheck disable=SC1091
	. "$HOME/.rokit/env"
fi

cd "$(dirname "$0")/.."
wally install
echo "Wally packages installed to Packages/"
