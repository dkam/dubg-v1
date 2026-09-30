# Roadmap

## Engine decision

Undecided between **Godot 4 (GDScript)** and **Bevy (Rust)**. Each engine gets
a throwaway **spike** built to the same spec:

> A capsule moving on a plane, with a second player connected over the
> network. Server-authoritative, listen-server capable, headless-server
> capable, version and map-hash check on connect.

| Spike | Status |
|---|---|
| `spike-godot/` | Working: listen and dedicated server, handshake, prediction/reconciliation, tests |
| `spike-bevy/` | Not started |

After both exist, pick one. The loser is deleted. The winner is either
promoted or rebuilt cleanly at the repo root. Neither spike is the game.

### What to compare

- How much of the netcode the engine does for you, and how much it fights
  a custom prediction/reconciliation loop.
- Headless server: startup time, memory, and ticks per second at 10× time
  scale with many characters (this matters for the ladder).
- Raycast and physics-query throughput for bot perception.
- Iteration speed: edit → run loop, and how testable it is headless.
- Tooling for building maps.
- Cross-compiling for Windows and Mac later.

### Godot spike findings so far

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
