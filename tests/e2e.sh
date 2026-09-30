#!/usr/bin/env bash
# End-to-end: real headless Godot processes talking ENet over localhost.
# Scenario 1: dedicated server, two clients (one with fake lag), one client on
#             the wrong version that must be rejected.
# Scenario 2: listen server (host plays) plus one client.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
GODOT=${GODOT:-godot}
OUT=$(mktemp -d "${TMPDIR:-/tmp}/rout-e2e.XXXXXX")
MAX_CORRECTION_CM=${MAX_CORRECTION_CM:-5}
fails=0

run() {  # run NAME ARGS... ; log to $OUT/NAME.log, exit code to $OUT/NAME.exit
  local name=$1; shift
  "$GODOT" --headless --path . -- "$@" >"$OUT/$name.log" 2>&1
  echo $? >"$OUT/$name.exit"
}
field() { grep -o "$2=[^ ]*" "$OUT/$1.log" | tail -1 | cut -d= -f2; }
pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; fails=$((fails + 1)); }
expect() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 > b + 0) }'; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a != "" && a + 0 < b + 0) }'; }

port=$((20000 + RANDOM % 20000))
echo "scenario 1: dedicated server on :$port, password protected"
run server --server --port=$port --password=hunter2 --status-file="$OUT/status.json" --quit-after=9 &
sleep 1.5
run alpha --join=127.0.0.1:$port --name=alpha --password=hunter2 --auto=circle --fake-lag-ms=60 --quit-after=6 &
run bravo --join=127.0.0.1:$port --name=bravo --password=hunter2 --auto=line --quit-after=6 &
run charlie --join=127.0.0.1:$port --name=charlie --password=hunter2 --fake-version=0.0.0-old --quit-after=6 &
run echo --join=127.0.0.1:$port --name=echo --password=hunter3 --quit-after=6 &
run foxtrot --join=127.0.0.1:$port --name=foxtrot --quit-after=6 &
(sleep 3.5; cp "$OUT/status.json" "$OUT/status-mid.json" 2>/dev/null) &
wait

expect "server accepted alpha" "grep -q 'accepted peer .* (alpha)' $OUT/server.log"
expect "server accepted bravo" "grep -q 'accepted peer .* (bravo)' $OUT/server.log"
expect "server rejected charlie for version" "grep -q 'rejected peer .* (charlie): version mismatch' $OUT/server.log"
expect "charlie was told why and exited 3" "grep -q 'session ended: rejected: version mismatch' $OUT/charlie.log && [ \"\$(cat $OUT/charlie.exit)\" = 3 ]"
expect "charlie never got a character" "! grep -q 'joined as peer' $OUT/charlie.log"
expect "server rejected echo for a wrong password" "grep -q 'rejected peer .* (echo): wrong password' $OUT/server.log"
expect "echo was told and exited 3" "grep -q 'session ended: rejected: wrong password' $OUT/echo.log && [ \"\$(cat $OUT/echo.exit)\" = 3 ]"
expect "server rejected foxtrot for no password" "grep -q 'rejected peer .* (foxtrot): password required' $OUT/server.log"
expect "foxtrot was told and exited 3" "grep -q 'session ended: rejected: password required' $OUT/foxtrot.log && [ \"\$(cat $OUT/foxtrot.exit)\" = 3 ]"
expect "server never logged the password" "! grep -q hunter2 $OUT/server.log"
expect "status file showed 2 players mid-match ($(cat $OUT/status-mid.json 2>/dev/null))" \
  "grep -q '\"players\": *2[,}]' $OUT/status-mid.json"
expect "status file showed 0 players at the end ($(cat $OUT/status.json 2>/dev/null))" \
  "grep -q '\"players\": *0[,}]' $OUT/status.json"
expect "status file carries the version" "grep -q '\"version\": *\"[^\"]*+[0-9a-f]\\{8\\}\"' $OUT/status.json"
for c in alpha bravo; do
  other=$([ $c = alpha ] && echo bravo || echo alpha)
  expect "$c exited cleanly" "[ \"\$(cat $OUT/$c.exit)\" = 0 ]"
  expect "$c sees $other (others=$(field $c others))" "[ \"$(field $c others)\" = $other ]"
  expect "$c travelled (travelled=$(field $c travelled) m)" "gt '$(field $c travelled)' 10"
  expect "$c got snapshots (reconciles=$(field $c reconciles))" "gt '$(field $c reconciles)' 100"
  expect "$c prediction held (max_correction_cm=$(field $c max_correction_cm) < $MAX_CORRECTION_CM)" \
    "lt '$(field $c max_correction_cm)' $MAX_CORRECTION_CM"
done

port2=$((port + 1))
echo "scenario 2: listen server on :$port2"
run host --host --port=$port2 --name=hostess --auto=circle --quit-after=9 &
sleep 1.5
run delta --join=127.0.0.1:$port2 --name=delta --auto=line --fake-lag-ms=40 --quit-after=5 &
wait

expect "host accepted delta" "grep -q 'accepted peer .* (delta)' $OUT/host.log"
delta_on_host=$(grep -o '(delta) left after travelling [0-9.]*' $OUT/host.log | awk '{print $NF}')
expect "host simulated delta's inputs (travelled=${delta_on_host:-none} m on the server)" "gt '$delta_on_host' 10"
expect "host's own player travelled (travelled=$(field host travelled) m)" "gt '$(field host travelled)' 10"
expect "delta sees hostess (others=$(field delta others))" "[ \"$(field delta others)\" = hostess ]"
expect "delta prediction held (max_correction_cm=$(field delta max_correction_cm) < $MAX_CORRECTION_CM)" \
  "lt '$(field delta max_correction_cm)' $MAX_CORRECTION_CM"

if [ $fails -gt 0 ]; then
  echo "$fails e2e check(s) failed; logs in $OUT"
  exit 1
fi
echo "all e2e checks passed; logs in $OUT"
