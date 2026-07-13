# Casino Shell (Hub)

Enclosed Hard Rock-style casino building: walk the floor, soak in atmosphere, then play Shuffle games in the indoor Arcade wing.

This document covers **world layout** only. Game rules and economy live in [`ROCKET_RUN.md`](ROCKET_RUN.md), [`PLINKO.md`](PLINKO.md), and [`MINES.md`](MINES.md).

## Design intent

| Zone | What it is |
|------|------------|
| **Casino floor** | Massive enclosed building - red carpets, pillars, chandeliers, lounge bar |
| **Table pit** | Non-playable roulette / blackjack / poker props for vibe only |
| **Arcade wing** | North end - the three real wager games as walk-up stations |
| Soft TP | Enter still joins remote arenas until phase 2 relocates boards into the building |

No detached outdoor portal pads. Rocket Run sits **in the same arcade row** as Plinko and Mines.

## Source of truth

| Piece | Path / instance |
|-------|-----------------|
| Hub map | `src/map/Lobby.model.json` → `Workspace.Lobby` |
| Portal wiring | `src/server/services/LobbyService.luau` |
| Spawn / lighting | `Config.LOBBY`, `Config.PORTALS` |
| Lighting defaults | `default.project.json` → `Lighting` |
| Arenas (still remote) | `RocketRunArena`, `PlinkoArena`, `MineSweeperArena` |

Hub stays named `Lobby` so `GameId` portal binding and leave teleports keep working.

## Footprint (top-down)

```
                         -Z (north)
            ================================
            |     ARCADE WING (indoor)     |
            |  Mines   Rocket   Plinko     |
            |  -28      0        28  @-48  |
            |------------------------------|
            |         ARCADE sign          |
            |         red carpet           |
            |  poker/roulette   blackjack  |
            |      TABLE PIT (props)       |
            |         red carpet           |
            |      Shuffle Arcade brand    |
            |======= grand entrance =======|
                         +Z (south)
                      spawn @ (0, 48)
```

Envelope ≈ **140 × 120** studs (`Config.LOBBY.FloorSize`), fully walled + roofed. Entry opening on the south wall only.

## Player flow

1. Spawn on the entry carpet at `Config.LOBBY.SpawnPosition` `(0, 3, 48)`.
2. Walk the red carpet through the table pit (atmosphere only - no wager on those props).
3. Reach the Arcade wing; walk up to a neon station and use the ProximityPrompt.
4. Server `LobbyService` → game `join` (soft TP to remote `ArenaOrigin` for now).
5. Leave returns to `Config.LOBBY.SpawnPosition`.

## Arcade station coordinates

| Station | Gate position | Accent |
|---------|---------------|--------|
| Mine Sweeper | `(−28, ·, −48)` | Magenta |
| Rocket Run | `(0, ·, −48)` | Cyan |
| Plinko Points | `(28, ·, −48)` | Purple |

All three share the same Z line on the arcade backdrop - no gap outside the building.

## Atmosphere props (non-playable)

Under `Workspace.Lobby.Atmosphere`:

- `Tables` - roulette, blackjack, poker set dressing
- `LoungeBar` - west-wall bar silhouette

Do not wire these to remotes or currency.

## Arena origins (still remote)

| Arena | `ArenaOrigin` | Folder |
|-------|---------------|--------|
| Rocket Run | `(0, 5, −140)` | `Workspace.RocketRunArena` |
| Plinko Points | `(90, 5, −140)` | `Workspace.PlinkoArena` |
| Mine Sweeper | `(−90, 5, −140)` | `Workspace.MineSweeperArena` |

Phase 2: pull arenas into / behind arcade alcoves so soft TP is framing-only.

## Portal contract (required)

Each portal under `Workspace.Lobby.Portals`:

- Model name `Portal_<GameId>`
- Attribute `GameId`
- Child `Frame` (`BasePart`)
- Child `Gate` with `EnterPrompt` (+ optional `GateLight`)

## What not to touch

- Gameplay / wager / RNG / settle for Rocket Run, Plinko, Mines
- Arena gameplay parts unless fixing shell collisions
- `GameId` values / `Config.PLAYABLE_GAMES` without a product change
- Leave teleports that use `Config.LOBBY.SpawnPosition`

## Lighting

Night casino: `ClockTime = 22`, purple fog, bloom on neon. Keep `Config.LOBBY` and `default.project.json` Lighting in sync.

## Phase 2

- Relocate Plinko / Mines boards into arcade alcoves; Rocket launch yard or roof attached to the building shell
- Richer table meshes / dealers as pure decoration
- Chip sinks (VIP, cosmetics) against RTP > 100%
