# Game outline

## Premise

Last-team-standing battle royale in the PUBG mould. Players and bot teams drop
from a plane onto a map, loot, and fight while a zone shrinks. Humans are a
handful of friends; bots fill the rest of the lobby in teams.

## Match flow

1. **Lobby.** A friend clicks **Host** (listen server) or a dedicated headless
   server is running. Others join.
2. **Match start.** The host generates the match state: map ID, loot seed,
   plane path, zone circles, bot spawns. See
   [client-server.md](client-server.md#match-state).
3. **Plane and drop.** The plane follows the chosen path; players jump.
4. **Loot and fight.** Loot is placed from the loot seed and the map's loot
   tables.
5. **Zone.** Circles shrink according to the map's zone parameters.
6. **End.** Last team alive wins. Results feed the bot ladder
   ([ladder.md](ladder.md#human-feedback)).

## Maps

- Maps are **bundled with the client**. They are never streamed.
- Each map is two parts, kept separate:
  - **Geometry**: the level itself (terrain, buildings, collision).
  - **Data file**: spawns, loot tables, zone parameters.
- A map is identified by an ID plus a content hash covering both parts. Clients
  whose hash differs are rejected on connect.

## Units

Metric throughout. Reference values used in the spike (not final tuning):

| Quantity | Value |
|---|---|
| Character height | 1.8 m |
| Capsule radius | 0.35 m |
| Run speed | 5.0 m/s |
| Gravity | 9.81 m/s² |

## Open questions

- **Camera: first person, third person, or both?** PUBG is third person with
  first-person-only servers. The simulation doesn't care, since the camera is
  client-side. It does matter for fairness (third person lets you peek
  around corners) and for art (first-person arms and weapons versus full-body
  animation seen from behind). The spike uses an over-the-shoulder third-person
  camera for now.

- Team size (duos? squads of four?) and lobby size.
- Weapons, attachments, armour, healing: which subset of PUBG, and how
  simplified.
- Vehicles: in or out?
- Map size for the first real map.
- Friendly fire, revives, and the knocked-down state.
