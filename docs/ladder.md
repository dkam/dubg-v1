# Self-tuning ladder

## Arenas

- **Headless bot-vs-bot** matches, run with the same server build.
- **4–10× time scale.**
- **Parallel instances.**

## Rating and selection

- Teams are rated with **TrueSkill**.
- Each generation, **cull the bottom performers**, then **breed and mutate the
  top**.

## Bounds

Parameters are clamped to **human-plausible bounds**. For example, the
reaction-time floor is about **180 ms**. The aim is bots that play like good
humans, not aimbots.

## Fitness

Fitness blends:

- **Team outcome** (placement, wins)
- **A role-specific component** (e.g. an overwatch bot scores for spotting and
  holding, not just kills)
- **A tedium penalty**: behaviour that wins but is boring to play against
  (endless camping, stalling) is penalised.

## Progression

- **Ranked teams form the progression ladder** that humans climb.
- **Snapshots of earlier generations are kept** as easy tiers.

## Human feedback

**Human match results feed back** into the ratings, correcting the ordering
where bot-vs-bot ratings don't match how the bots fare against people.

## Open questions

- How time scaling interacts with the fixed 60 Hz tick: more ticks per
  wall-clock second, not a larger timestep, so behaviour is unchanged.
- Genome crossover scheme, mutation rates, population size.
- What counts as "tedium", measurably.
