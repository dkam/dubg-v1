#!/usr/bin/env bash
# Runs the real deploy/rout-update against a fake `docker` on PATH and checks
# when it restarts the server onto a new image, and when it waits.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
UPDATER=$PWD/deploy/rout-update
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rout-update-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
fails=0

mkdir -p "$WORK/bin"
cat >"$WORK/bin/docker" <<'FAKE'
#!/usr/bin/env bash
# Fake docker: records calls, answers from FAKE_* variables.
echo "docker $*" >>"$FAKE_LOG"
case "$*" in
  "compose pull"*)            exit 0 ;;
  "compose config --images"*) echo "ghcr.io/dkam/rout:latest" ;;
  "image inspect"*)           echo "$FAKE_WANT_ID" ;;
  "compose ps -q"*)           echo "$FAKE_CID" ;;
  "inspect --format"*)        echo "$FAKE_HAVE_ID" ;;
  "exec"*)                    [ "$FAKE_STATUS" = FAIL ] && exit 1; echo "$FAKE_STATUS" ;;
  "compose up -d"*)           exit 0 ;;
  "image prune"*)             exit 0 ;;
  *)                          echo "fake docker: unexpected: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "$WORK/bin/docker"

now=$(date +%s)
fresh() { echo "{\"players\":$1,\"updated_unix\":$now,\"version\":\"0.1.0+aaaa1111\"}"; }
stale() { echo "{\"players\":$1,\"updated_unix\":$((now - 600)),\"version\":\"0.1.0+aaaa1111\"}"; }

# case NAME EXPECT(up|no-up) CID HAVE WANT STATUS
case_() {
  local name=$1 expect=$2
  export FAKE_CID=$3 FAKE_HAVE_ID=$4 FAKE_WANT_ID=$5 FAKE_STATUS=$6
  export FAKE_LOG="$WORK/$name.calls"; : >"$FAKE_LOG"
  PATH="$WORK/bin:$PATH" ROUT_DIR="$WORK" "$UPDATER" >"$WORK/$name.out" 2>&1
  local rc=$?
  local did=no-up
  grep -q '^docker compose up -d' "$FAKE_LOG" && did=up
  if [ $rc -eq 0 ] && [ "$did" = "$expect" ]; then
    echo "  ok   $name ($did)"
  else
    echo "  FAIL $name: expected $expect, got $did (exit $rc)"; sed 's/^/       /' "$WORK/$name.out" "$FAKE_LOG"
    fails=$((fails + 1))
  fi
}

case_ "same image: nothing to do"               no-up c1 sha256:old sha256:old "$(fresh 0)"
case_ "new image, nobody playing: update"       up    c1 sha256:old sha256:new "$(fresh 0)"
case_ "new image, 2 playing: wait"              no-up c1 sha256:old sha256:new "$(fresh 2)"
case_ "new image, status stale: server hung, update" up c1 sha256:old sha256:new "$(stale 2)"
case_ "new image, status unreadable: update"    up    c1 sha256:old sha256:new FAIL
case_ "server not running: start it"            up    "" ""          sha256:new "$(fresh 0)"
grep -q 'waiting.*2 player' "$WORK/new image, 2 playing: wait.out" \
  && echo "  ok   says why it's waiting" || { echo "  FAIL doesn't say why it's waiting"; fails=$((fails + 1)); }

[ $fails -eq 0 ] && echo "all updater checks passed" || { echo "$fails updater check(s) failed"; exit 1; }
