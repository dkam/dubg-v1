#!/usr/bin/env bash
# Import the project (registers class_name scripts), then unit, e2e and
# updater tests. tests/docker.sh (needs Docker) runs separately.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
"$GODOT" --headless --path . --import >/dev/null 2>&1
echo "unit tests"
"$GODOT" --headless --path . --script res://tests/unit_tests.gd
echo "e2e tests"
tests/e2e.sh
echo "updater tests"
tests/test_rout_update.sh
