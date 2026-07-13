#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -f "$HOME/.rokit/env" ]; then
	# shellcheck disable=SC1091
	. "$HOME/.rokit/env"
fi

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit

echo "Git hooks installed (.githooks/pre-commit runs ./scripts/check.sh on commit)."
