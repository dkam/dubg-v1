# Godot spike

A capsule on a plane with networked players. Throwaway: it exists to compare
Godot against Bevy (see ../docs/roadmap.md).

## Run

    godot --path spike-godot                                # menu: Host / Join
    godot --path spike-godot -- --host                      # listen server, you play
    godot --path spike-godot -- --join=192.168.1.20         # join (port 24650)
    godot --headless --path spike-godot -- --server         # dedicated server

WASD, mouse, Space. Esc frees the mouse; click to recapture.

Useful for poking at the netcode:

    --fake-lag-ms=100     client only, each direction (HUD shows the correction)
    --auto=circle|line    scripted input instead of keyboard
    --fake-version=X      pretend to be another version (should be rejected)
    --quit-after=SEC      exit and print a one-line report

## Test

    spike-godot/tests/run.sh

Runs the unit tests (input sanitising, handshake checks, map hash, and
rewind-and-replay determinism checked at every tick), then end-to-end runs
over localhost. Those cover a dedicated server with two clients (one lagged)
plus one wrong-version client that must be rejected, and a listen server with
one client.

## Layout

| Path | What |
|---|---|
| `sim/player_input.gd` | The one input struct: keyboard, network, bots |
| `sim/character.gd` | The one character controller, used for authority, prediction and replay |
| `net/protocol.gd` | Version, tick rate, map hash, handshake checks |
| `game/session.gd` | Server half and client half (one script, so RPC tables match) |
| `game/world.gd` | Map loading and characters |
| `maps/plane/` | `geometry.tscn` plus `data.json` (spawns, zone, loot) |
