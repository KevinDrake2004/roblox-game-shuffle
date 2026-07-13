# Casino Shell (Hub)

Main Shuffle Arcade casino area: spawn, brand signage, and teleporters into the three wager games.

This document covers **world layout** only. Game rules and economy live in [`ROCKET_RUN.md`](ROCKET_RUN.md), [`PLINKO.md`](PLINKO.md), and [`MINES.md`](MINES.md).

## Source of truth

| Piece | Path / instance |
|-------|-----------------|
| Hub map | `src/map/Lobby.model.json` → `Workspace.Lobby` |
| Portal wiring | `src/server/services/LobbyService.luau` |
| Spawn / lighting constants | `Config.LOBBY`, `Config.PORTALS` |
| Lighting defaults | `default.project.json` → `Lighting` |
| Arenas (separate) | `RocketRunArena`, `PlinkoArena`, `MineSweeperArena` |

There is **no** `Casino.model.json` parent yet. The hub stays named `Lobby` so existing `GameId` portal binding and leave-game teleports keep working.

## Player flow

1. Player spawns on `HubSpawn` at `Config.LOBBY.SpawnPosition` `(0, 3, 20)`.
2. Walk north (toward −Z) along the aisle to the portal row at `Z ≈ −28`.
3. ProximityPrompt on each portal `Gate` → server `LobbyService` → game `join`.
4. Leave from an arena returns the player to `Config.LOBBY.SpawnPosition`.

## Hub coordinates

| Feature | Position (approx.) | Notes |
|---------|--------------------|--------|
| Floor | `(0, 0, 0)`, size `96×1×96` | Dark purple `Config.COLORS.Floor` |
| Hub spawn | `(0, 3, 20)` | Cyan neon pad |
| Brand sign | `(0, 12, −46)` | SurfaceGui title from LobbyService |
| Rocket Run portal | `(−24, ·, −28)` | Cyan accent |
| Plinko portal | `(0, ·, −28)` | Purple accent |
| Mines portal | `(24, ·, −28)` | Magenta accent |

Portal accent colors match `Config.PORTALS[].accentColor`.

## Arena origins (do not move in shell phase)

| Arena | `ArenaOrigin` | Folder |
|-------|---------------|--------|
| Rocket Run | `(0, 5, −140)` | `Workspace.RocketRunArena` |
| Plinko Points | `(90, 5, −140)` | `Workspace.PlinkoArena` |
| Mine Sweeper | `(−90, 5, −140)` | `Workspace.MineSweeperArena` |

Portals teleport into these arenas; physical walkways between hub and arenas are optional phase 2.

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

## Phase 2 ideas

- Optional `Workspace.Casino` folder that parents Lobby + corridor props (keep `Lobby` name for service lookups, or update LobbyService)
- Relocate arenas closer to the hub or add scenic corridors
- VIP / cosmetics sinks as chip drains against RTP > 100%
