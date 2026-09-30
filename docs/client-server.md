# Client–server outline

## One engine, both ends

The server is **the same project** as the client, run headless:

- `godot --headless --path . -- --server`
- or the Docker image (see the top-level README).

**Listen server** is the normal case: a friend clicks **Host** and plays in
the same process that is serving. A dedicated headless server is the same code
with no local player.

## Authority

The server is authoritative for everything that matters:

- Movement and physics
- Hit registration, by server-side raycast
- All bots (they exist only on the server)

Clients send inputs. The server sends back state.

## The input struct

One input struct drives every character: humans, the network and bots all
produce it, and one character controller consumes it. In the spike it holds:

| Field | Meaning |
|---|---|
| `seq` | Monotonic per-sender sequence number |
| `move` | 2D vector, x = strafe right, y = forward, length ≤ 1 |
| `yaw` | Facing in radians, world space |
| `jump` | Boolean |

It will grow (pitch, fire, crouch, interact…), but it stays a single struct
that bots emit too. See [ai.md](ai.md#same-inputs-as-humans).

## Connecting: version, map and password check

Maps are bundled, so the host never sends geometry. On connect:

1. Server → client: `server_hello {version, map_id, map_hash, nonce, password}`.
   The nonce is 16 random bytes, fresh for each connection. `password` says
   whether one is required.
2. Client → server: `client_hello {version, map_id, map_hash, name, proof}`.
   The client hashes its own copy of the map, and sends an empty hash if it
   doesn't have that map. `proof` is HMAC-SHA256(password, nonce).
3. The server checks, in this order: version, then password, then map. On a
   mismatch it sends `reject {reason}` and drops the peer. Otherwise it sends
   `accept`, and only then does the peer join the game.

The password never crosses the wire, and a proof is only good for one nonce.
Gameplay traffic is not encrypted.

The handshake uses Godot's `SceneMultiplayer` authentication step, with JSON
payloads, rather than RPCs. RPC method IDs are table indices, so across
mismatched versions a "hello" RPC could land on the wrong method. The
handshake has to stay readable by *any* version, which is the reason for JSON.

### What "version" means

The version is `GAME_VERSION` plus the first 8 hex digits of a SHA-256 over
the game code (`*.gd` and `*.tscn`, plus `project.godot`), excluding
`tests/`, `docs/`, `deploy/` and `maps/`, since maps have their own hash).
Any code difference between client and server is a refusal at connect, not
a desync mid-game. `.gitattributes` forces LF line endings so Windows
checkouts hash the same.

When clients are eventually exported (not run from source), scripts are
tokenised and scenes may be converted to binary. The hash will then need
computing at build time into a manifest, rather than at runtime.

## Deployment

- The **server image** is the project plus pinned headless Godot, with tini as
  PID 1. CI builds it on every push to the default branch and publishes it
  to `ghcr.io/dkam/rout`.
- **Status file:** the server writes `/tmp/rout-status.json` every 2 s
  (players, names, version, uptime). The image healthcheck fails if it goes
  stale.
- **Updater:** `deploy/rout-update` runs from a systemd timer. It pulls the
  image and restarts onto a new one only when the status file shows zero
  players, or is stale, meaning the server is hung.

## Match state

After accepting, the host sends **match state only**:

- Map ID
- Loot seed
- Plane path
- Zone circles
- Bot spawns

Everything else is derived locally from bundled data plus these values.

## Netcode (as in the spike)

- Fixed simulation tick: **60 Hz**. Snapshots are sent at **30 Hz**.
- **Inputs:** the client sends each input redundantly (the last 3 per packet)
  over an unreliable, ordered channel. The server queues them per player and
  applies one per tick, or two per tick when the queue is backing up to catch
  up.
- **Own character:** the client predicts locally. When a snapshot arrives it
  resets to the server's state for the last acknowledged input and replays the
  unacknowledged ones. The replayed state includes position, velocity, yaw and
  grounded.
- **Other characters:** interpolated 100 ms (6 ticks) behind the newest
  snapshot.
- **Hit registration:** not in the spike yet. It will need server-side lag
  compensation (rewinding hitboxes to what the shooter saw).

## Open questions

- Transport security: not a concern among friends, but a plain version check
  isn't authentication.
- NAT traversal for listen servers: port forwarding, a relay, or Steam
  networking later?
- Bandwidth at full lobby size, and interest management by distance.
