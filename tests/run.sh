#!/usr/bin/env bash
# Import the project (registers class_name scripts), then unit and e2e tests.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
"$GODOT" --headless --path . --import >/dev/null 2>&1
echo "unit tests"
"$GODOT" --headless --path . --script res://tests/unit_tests.gd
echo "e2e tests"
tests/e2e.sh
