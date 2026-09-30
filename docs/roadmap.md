# Roadmap

## Engine decision

**Godot 4 (GDScript), decided 2026-09-30.** Bevy (Rust) was the alternative.
The Godot spike (a capsule on a plane with a networked second player,
server-authoritative, listen and headless servers, version and map-hash
check) did everything needed without fighting the engine. It was promoted to
the repo root rather than rewritten.

Reasons Godot won:

- **An editor for maps.** Bevy has none, so Blender would become the level
  editor.
- **Mature pieces:** glTF import, CSG, the Terrain3D and func_godot add-ons.
- **Headless:** the same binary runs as a dedicated server.
- **Enough networking:** its `SceneMultiplayer` authentication step and RPCs
  cover what we need, and it stays out of the way of custom prediction.

### Findings from the spike

- **Handshake:** `SceneMultiplayer`'s auth step (`auth_callback`,
  `send_auth`, `complete_auth`) fits the version/map-hash check exactly. A peer
  never becomes "connected" until it passes.
- **Prediction:** `CharacterBody3D.move_and_slide()` can be called many times
  in one frame for replay, and it replays exactly. The end-to-end runs show
  0.00 cm of correction with 60 ms of fake lag. Restoring state for a replay
  needs our own `grounded` flag, because `is_on_floor()` can't be set.
- **RPCs** are routed by node path plus a per-script method table, so both
  ends must run the same script at the same path. That's fine with one
  project; it's also why the handshake doesn't use RPCs.
- **Headless:** `godot --headless` runs the server and scripted clients; the
  full test suite takes about 25 s.
- Custom netcode is all hand-written: roughly 450 lines of GDScript. Godot's
  `MultiplayerSynchronizer` doesn't do prediction, so it wasn't used.

## Build order

1. **Networked movement** ← spike territory
2. **A single competent bot**
3. **The squad brain**, with identical bots
4. **Roles**
5. **Evolution and the ladder**
