#!/usr/bin/env bash
# Builds the server image, runs it with a password, and joins it with a
# headless client from this checkout. Proves the image starts, runs the same
# code version as the source, enforces its password, and reports players in
# its status file.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
GODOT=${GODOT:-godot}
IMAGE=${IMAGE:-rout:test}
OUT=$(mktemp -d "${TMPDIR:-/tmp}/rout-docker.XXXXXX")
PORT=$((20000 + RANDOM % 20000))
fails=0
pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; fails=$((fails + 1)); }
expect() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
field() { grep -o "$2=[^ ]*" "$OUT/$1.log" | tail -1 | cut -d= -f2; }

echo "building $IMAGE"
if ! docker build -q -t "$IMAGE" . >"$OUT/build.log" 2>&1; then
  cat "$OUT/build.log"; echo "image build failed"; exit 1
fi
cid=$(docker run -d -e ROUT_PASSWORD=s3cret -p 127.0.0.1:$PORT:24650/udp "$IMAGE")
trap 'docker logs "$cid" >"$OUT/server.log" 2>&1; docker rm -f "$cid" >/dev/null 2>&1' EXIT
for _ in $(seq 40); do docker logs "$cid" 2>&1 | grep -q 'serving map' && break; sleep 0.5; done

"$GODOT" --headless --path . -- --join=127.0.0.1:$PORT --name=dockhand --password=s3cret \
  --auto=circle --quit-after=5 >"$OUT/client.log" 2>&1 &
"$GODOT" --headless --path . -- --join=127.0.0.1:$PORT --name=intruder --password=guess \
  --quit-after=5 >"$OUT/intruder.log" 2>&1 &
sleep 3
docker exec "$cid" cat /tmp/rout-status.json >"$OUT/status-mid.json" 2>&1
wait
docker logs "$cid" >"$OUT/server.log" 2>&1

image_version=$(grep -o 'version [^,]*' "$OUT/server.log" | head -1 | cut -d' ' -f2)
source_version=$(grep -o '(version [^)]*)' "$OUT/client.log" | head -1 | tr -d '()' | cut -d' ' -f2)
expect "image started a password-protected server" "grep -q 'password required' $OUT/server.log"
expect "image runs the same code as the source (image ${image_version:-?}, source ${source_version:-?})" \
  "[ -n '$image_version' ] && [ '$image_version' = '$source_version' ]"
expect "client joined the container" "grep -q 'joined as peer' $OUT/client.log"
expect "client moved on the container's simulation (travelled=$(field client travelled))" \
  "awk 'BEGIN { exit !(\"$(field client travelled)\" + 0 > 5) }'"
expect "prediction held against the container (max_correction_cm=$(field client max_correction_cm))" \
  "awk 'BEGIN { v = \"$(field client max_correction_cm)\"; exit !(v != \"\" && v + 0 < 5) }'"
expect "wrong password was refused" "grep -q 'rejected: wrong password' $OUT/intruder.log"
expect "status file showed the player ($(cat $OUT/status-mid.json))" "grep -q '\"players\": *1[,}]' $OUT/status-mid.json"
health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid")
expect "container has a healthcheck (status: ${health:-none})" "[ -n '$health' ]"

if [ $fails -gt 0 ]; then echo "$fails docker check(s) failed; logs in $OUT"; exit 1; fi
echo "all docker checks passed; logs in $OUT"
