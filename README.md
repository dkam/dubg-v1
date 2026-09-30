# Rout

A PUBG-style battle royale for a few friends plus teams of bots. Godot 4,
Linux first. Very early: right now it's capsules on a plane with working
netcode.

## Run a server

Everyone needs [Godot 4.7](https://godotengine.org/download) and a copy of
this repo, all on the same commit (the server refuses mismatched versions).

    git clone git@github.com:dkam/rout.git && cd rout
    godot --headless --path . -- --server                  # dedicated, port 24650/udp

Or host and play in the same window:

    godot --path . -- --host

## Run a client

    godot --path .                                         # menu: enter address, Join
    godot --path . -- --join=192.168.1.20                  # or straight in (port 24650)

WASD to move, mouse to look, Space to jump. Esc frees the mouse; click to
recapture it.

## Flags

    --port=N              listen or connect port (default 24650)
    --name=NAME           player name
    --fake-lag-ms=N       client only: delay each direction (HUD shows corrections)
    --auto=circle|line    scripted movement instead of the keyboard
    --fake-version=X      claim another version (should be rejected)
    --quit-after=SEC      exit after SEC seconds and print a one-line report

## Tests

    tests/run.sh

Unit tests (input sanitising, handshake checks, map hash, and
rewind-and-replay determinism checked at every tick), then end-to-end runs
over localhost with real headless processes. Those cover a dedicated server
with two clients (one lagged) plus a wrong-version client that must be
rejected, and a listen server with one client.

## Layout

| Path | What |
|---|---|
| `sim/player_input.gd` | The one input struct: keyboard, network, bots |
| `sim/character.gd` | The one character controller: authority, prediction, replay |
| `net/protocol.gd` | Version, tick rate, map hash, handshake checks |
| `game/session.gd` | Server half and client half (one script, so RPC tables match) |
| `game/world.gd` | Map loading and characters |
| `maps/<id>/` | `geometry.tscn` plus `data.json` (spawns, zone, loot) |
| `docs/` | Design: game, client-server, AI, ladder, roadmap |
