# Dedicated Rout server: the game project run by headless Godot.
#   docker run -p 24650:24650/udp -e ROUT_PASSWORD=... ghcr.io/dkam/rout
FROM debian:trixie-slim AS godot
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*
COPY tools/install-godot.sh /tmp/
RUN /tmp/install-godot.sh /usr/local/bin/godot

FROM debian:trixie-slim
# tini as PID 1 so `docker stop` (SIGTERM) actually stops Godot.
RUN apt-get update \
 && apt-get install -y --no-install-recommends tini \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --create-home --home-dir /home/rout rout
COPY --from=godot /usr/local/bin/godot /usr/local/bin/godot
COPY --chown=rout:rout . /game
USER rout
# Builds .godot/ (class registry, imports) so the server starts fast.
RUN godot --headless --path /game --import >/dev/null 2>&1 && test -d /game/.godot
EXPOSE 24650/udp
# The server rewrites its status file every 2 s; stale means hung.
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s \
  CMD test $(( $(date +%s) - $(stat -c %Y /tmp/rout-status.json) )) -lt 30
ENTRYPOINT ["tini", "--", "godot", "--headless", "--path", "/game", "--", "--server", "--status-file=/tmp/rout-status.json"]
