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

## Connecting: version and map check

Maps are bundled, so the host never sends geometry. On connect:

1. Server → client: `server_hello {version, map_id, map_hash}`
2. Client → server: `client_hello {version, map_id, map_hash, name}`. The client
   hashes its own copy of the map, and sends an empty hash if it doesn't have
   that map.
3. Server compares. On mismatch it sends `reject {reason}` and drops the peer.
   Otherwise it sends `accept`, and only then does the peer join the game.

The handshake uses Godot's `SceneMultiplayer` authentication step, with JSON
payloads, rather than RPCs. RPC method IDs are table indices, so across
mismatched versions a "hello" RPC could land on the wrong method. The
handshake has to stay readable by *any* version, which is the reason for JSON.

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
