# DUBG

Dkam's Uknown Battle Ground - A PUBG-style battle royale for a few friends plus teams of bots. Godot 4,
Linux first. Very early: right now it's capsules on a plane with working
netcode.

## Run a server

The server is a Docker image that CI builds from every push to the default
branch: `ghcr.io/dkam/rout`. On any Linux box with Docker:

    mkdir -p /opt/rout && cd /opt/rout
    curl -fsSLO https://raw.githubusercontent.com/dkam/rout/HEAD/deploy/compose.yaml
    curl -fsSLO https://raw.githubusercontent.com/dkam/rout/HEAD/deploy/rout-update
    curl -fsSL -o .env https://raw.githubusercontent.com/dkam/rout/HEAD/deploy/env.example
    chmod +x rout-update
    $EDITOR .env                      # set ROUT_PASSWORD
    docker compose up -d

(Or copy the files from `deploy/` in a checkout.) Players need **UDP 24650**
open. Note that Docker's published ports bypass ufw.

If the repo or its package is private, first run
`docker login ghcr.io -u <github user>` with a token that has
`read:packages`.

**Auto-update.** `rout-update` pulls the image. When there's a new one it
restarts the server onto it, but only once nobody is connected; while
players are on, it waits and tries again next run. Run it every 5 minutes
with the systemd units in `deploy/` (edit `User=` and the paths first):

    sudo cp deploy/rout-update.service deploy/rout-update.timer /etc/systemd/system/
    sudo systemctl enable --now rout-update.timer
    journalctl -u rout-update            # what it decided, and why

Or from cron: `*/5 * * * * cd /opt/rout && ./rout-update`.

For a quick game without Docker, one player can host and play in the same
window:

    godot --path . -- --host --password=secret

## Run a client

You need [Godot 4.7](https://godotengine.org/download) and this repo **on the
same commit as the server**. The server runs the latest default branch, so
pull before you play:

    git clone git@github.com:dkam/rout.git && cd rout    # first time
    git pull                                             # every time
    godot --path .

Enter the server's `address:port` and the password, then **Join**. Or go
straight in:

    ROUT_PASSWORD=secret godot --path . -- --join=game.example.com

WASD to move, mouse to look, Space to jump. Esc frees the mouse; click to
recapture it.

If you're refused with **"version mismatch"**, your code differs from the
server's: `git pull`, and check for local edits (`git status`). The version
is a hash of the game code, so any difference counts, and it's shown under
the title in the menu.

## Flags

    --port=N              listen or connect port (default 24650)
    --name=NAME           player name
    --password=X          server password (or set ROUT_PASSWORD, which keeps it out of `ps`)
    --status-file=PATH    server: keep a JSON status file (players, version) fresh
    --fake-lag-ms=N       client only: delay each direction (HUD shows corrections)
    --auto=circle|line    scripted movement instead of the keyboard
    --fake-version=X      claim another version (should be rejected)
    --quit-after=SEC      exit after SEC seconds and print a one-line report

## How the password works

The server sends a fresh random nonce with each connection. The client
answers with HMAC-SHA256(password, nonce). The password never crosses the
network, and a captured answer is useless for the next connection. Gameplay
traffic itself is not encrypted, so use a long password: it's the only lock
on the door.

## Tests

    tests/run.sh          # unit, end-to-end over localhost, updater
    tests/docker.sh       # builds the image, joins it, checks the password and status

CI (`.github/workflows/ci.yml`) runs both on every push. On the default branch
it then publishes `ghcr.io/dkam/rout:latest` and `:sha-<commit>`.

## Layout

| Path | What |
|---|---|
| `sim/player_input.gd` | The one input struct: keyboard, network, bots |
| `sim/character.gd` | The one character controller: authority, prediction, replay |
| `net/protocol.gd` | Version, tick rate, map hash, password proof, handshake checks |
| `game/session.gd` | Server half and client half (one script, so RPC tables match) |
| `game/world.gd` | Map loading and characters |
| `game/character_visual.gd` | The animated mannequin on top of the capsule (never built on headless servers) |
| `assets/characters/` | Quaternius Universal Animation Library, CC0 (see its `LICENSE.txt`) |
| `maps/<id>/` | `geometry.tscn` plus `data.json` (spawns, zone, loot) |
| `deploy/` | Compose file, updater, systemd units |
| `tools/install-godot.sh` | The pinned Godot build, used by the image and CI |
| `docs/` | Design: game, client-server, AI, ladder, roadmap |

## Credits

- Character model and animations: [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html)
  by [Quaternius](https://quaternius.com), CC0. Not required, but deserved;
  consider [supporting them](https://www.patreon.com/quaternius).
