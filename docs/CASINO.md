# Casino Shell (Hub)

Main Shuffle Arcade building: one footprint with a main hall, side game rooms, and a Rocket Run launch exit.

This document covers **world layout** only. Game rules and economy live in [`ROCKET_RUN.md`](ROCKET_RUN.md), [`PLINKO.md`](PLINKO.md), and [`MINES.md`](MINES.md).

## Design intent

Games live **in the casino**, not behind a distant portal strip:

| Space | Role |
|-------|------|
| Main hall | Spawn, brand, circulation |
| East room | Plinko - walk in, then soft-TP at the room gate for board cam |
| West room | Mines - same pattern |
| North apron | Rocket Run exit - outdoor/launch feel (roof/yard later) |

Enter prompts still call `LobbyService` → game `join`. Arenas stay at remote `ArenaOrigin`s until phase 2 relocates them next to these rooms.

## Source of truth

| Piece | Path / instance |
|-------|-----------------|
| Hub map | `src/map/Lobby.model.json` → `Workspace.Lobby` |
| Portal wiring | `src/server/services/LobbyService.luau` |
| Spawn / lighting constants | `Config.LOBBY`, `Config.PORTALS` |
| Lighting defaults | `default.project.json` → `Lighting` |
| Arenas (separate for now) | `RocketRunArena`, `PlinkoArena`, `MineSweeperArena` |

There is **no** `Casino.model.json` parent yet. The hub stays named `Lobby` so existing `GameId` portal binding and leave-game teleports keep working.

## Footprint (top-down)

```
                         -Z (north)
                              |
                    [ Rocket apron ]
                    [ cyan Launch  ]
                    [ gate @ 0,-30 ]
            ------------||------------
            |  Mines    ||   Plinko  |
            |  room     ||   room    |
            |  -42,-14  ||   42,-14  |
            |     magenta  purple    |
            |-----door--| |--door----|
            |                        |
            |      MAIN HALL         |
            |   BrandSign @ N wall   |
            |   HubSpawn @ 0, 20     |
            |         entry          |
            --------------------------
                         +Z (south)
```

Approximate extents: X ≈ −54…54, Z ≈ −40…24 (`Config.LOBBY.FloorSize` ≈ `110×72`).

## Player flow

1. Spawn on `HubSpawn` at `Config.LOBBY.SpawnPosition` `(0, 3, 20)`.
2. Walk the hall:
   - **West door** → Mines room → magenta Enter gate
   - **East door** → Plinko room → purple Enter gate
   - **North exit** → rocket apron → cyan Launch gate
3. ProximityPrompt on each portal `Gate` → server `LobbyService` → game `join` (still TPs to remote arena).
4. Leave from an arena returns to `Config.LOBBY.SpawnPosition`.

## Key coordinates

| Feature | Position (approx.) | Notes |
|---------|--------------------|--------|
| Main hall floor | `(0, 0, 2)`, `52×44` | Dark purple |
| Hub spawn | `(0, 3, 20)` | Cyan neon pad |
| Brand sign | `(0, 11.5, −18.8)` | SurfaceGui from LobbyService |
| Mines room floor | `(−40, 0, −4)`, `28×32` | Magenta accents |
| Plinko room floor | `(40, 0, −4)`, `28×32` | Purple accents |
| Rocket apron | `(0, 0, −32)`, `22×16` | Outdoor strip |
| Rocket Launch gate | `(0, ·, −30)` | Cyan |
| Plinko Enter gate | `(42, ·, −14)` | Purple |
| Mines Enter gate | `(−42, ·, −14)` | Magenta |

Portal accent colors match `Config.PORTALS[].accentColor`.

## Arena origins (still remote - do not move yet)

| Arena | `ArenaOrigin` | Folder |
|-------|---------------|--------|
| Rocket Run | `(0, 5, −140)` | `Workspace.RocketRunArena` |
| Plinko Points | `(90, 5, −140)` | `Workspace.PlinkoArena` |
| Mine Sweeper | `(−90, 5, −140)` | `Workspace.MineSweeperArena` |

Phase 2 should pull these origins into / beside the matching rooms so the soft TP is a few studs (camera setup), not a continent hop.

## Portal contract (required)

Each portal under `Workspace.Lobby.Portals` must keep:

- Model name `Portal_<GameId>` (e.g. `Portal_RocketRun`)
- Attribute `GameId` (`RocketRun` / `PlinkoPoints` / `MineSweeper`)
- Child `Frame` (`BasePart`) - billboard label anchor
- Child `Gate` with `EnterPrompt` (`ProximityPrompt`) and optional `GateLight`

Do not rename these for cosmetics. Extra decorative parts (pillars, pads, arch neon) are fine.

## What not to touch

- Rocket Run / Plinko / Mines **gameplay**, wager, RNG, or settle code
- Arena model gameplay parts (rocket, pegs, mine board) unless fixing a shell-only collision
- Portal `GameId` attribute values or `Config.PLAYABLE_GAMES` without a deliberate product change
- Leave-prompt / spawn teleports that use `Config.LOBBY.SpawnPosition`

## Lighting

Night casino look: `ClockTime = 22`, purple fog, stronger bloom on neon. Runtime applies `Config.LOBBY` plus atmosphere / color correction / bloom tweaks in `LobbyService.applyLighting`. Edit both `Config.LOBBY` and `default.project.json` Lighting when changing the hub mood so Studio edit mode matches play.

## Phase 2

- Relocate Plinko / Mines arenas into (or just behind) their rooms; keep soft TP only for camera / session framing
- Grow Rocket apron into a real backyard or roof launch (shared rocket can stay outdoors)
- Optional `Workspace.Casino` parent folder (keep `Lobby` name for service lookups, or update LobbyService)
- VIP / cosmetics sinks as chip drains against RTP > 100%
