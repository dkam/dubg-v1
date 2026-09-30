# AI outline

## Same inputs as humans

Bots are **server-side entities** that emit the **same input struct** as
human clients, fed into the **same character controller**. A bot cannot do
anything a player couldn't: no teleporting, no instant turns beyond what the
input allows.

## Perception: no omniscience

Perception and decision-making run at **5–10 Hz**, staggered across bots so
the load is spread over ticks.

- **Vision cones** plus **line-of-sight raycasts**.
- **Last-seen memory** that decays over time.
- **Reaction delay** of 200–400 ms between perceiving something and acting on
  it.
- **Aim error** that tightens the longer a target is tracked.
- **Sound events** (footsteps, gunfire, vehicles) as a second perception
  channel.

## Two layers

### Squad brain (1–2 Hz)

Team-level decisions:

- **Rotate** (toward the zone or a position)
- **Hold**
- **Flank**
- **Disengage**

### Role executors

Each bot has a role that turns the squad's intent into inputs:

| Role | Job |
|---|---|
| Entry | First in, closes distance |
| Support | Follows up, trades, covers entry |
| Overwatch | Long sightlines, holds angles |
| Scout | Ranges ahead, finds contacts |

**Roles have locked loadouts.**

## Team blackboard

A shared blackboard per team holding **only perceived info**. Nothing is read
from the true world state. Callouts reach the blackboard after a **callout
delay**, so teammates learn about a contact later than the bot that saw it.

## Parameterised behaviour

All behaviour is driven by parameters so it can be evolved:

- **One genome per slot** (per bot position in the team)
- **A team composition gene** (which roles, in what mix)

Genes are clamped to human-plausible bounds; see
[ladder.md](ladder.md#bounds).

## Open questions

- Navigation: navmesh baked per map and bundled with it?
- Genome contents: which parameters are exposed first.
- How the squad brain picks its intent: utility scores, or a small
  behaviour tree?
