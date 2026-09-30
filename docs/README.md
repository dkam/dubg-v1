# Rout — design docs

A PUBG-style battle royale for a few friends plus teams of bots. No
monetisation. Linux first, Windows and Mac later. Metric units throughout
(1 engine unit = 1 metre, speeds in m/s, time in seconds).

| Doc | Covers |
|---|---|
| [game.md](game.md) | The game itself: match flow, maps, what is and isn't decided |
| [client-server.md](client-server.md) | Authority, listen/dedicated servers, handshake, match state, netcode |
| [ai.md](ai.md) | Bots: perception, squad brain, roles, genomes |
| [ladder.md](ladder.md) | Self-tuning: headless arenas, TrueSkill, evolution, progression tiers |
| [roadmap.md](roadmap.md) | Build order and the engine decision |

Engine is **undecided** between Godot 4 (GDScript) and Bevy (Rust). Each gets
a throwaway spike (`spike-godot/`, `spike-bevy/`) building the same thing; see
[roadmap.md](roadmap.md).
