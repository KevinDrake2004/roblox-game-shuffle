# Casino Shell (Hub)

Enclosed Hard Rock-style casino: walk the floor, then walk into real game rooms. The Plinko board, Mines table, and Rocket Run pad live **inside the building** - not across the map behind a teleporter.

This document covers **world layout** only. Game rules live in [`ROCKET_RUN.md`](ROCKET_RUN.md), [`PLINKO.md`](PLINKO.md), and [`MINES.md`](MINES.md).

## Design intent

| Zone | What it is |
|------|------------|
| **Casino floor** | Enclosed building - red carpets, pillars, lounge, decorative tables |
| **Table pit** | Non-playable roulette / blackjack / poker props |
| **Game hall** | North corridor with three doorways |
| **Game rooms** | Physical `*Arena` folders seated in those rooms |

**Play** at a doorway starts the session (HUD / camera). If you already walked into the room, join does **not** hard-teleport you. Leave drops you in the corridor outside that room.

## Source of truth

| Piece | Path / instance |
|-------|-----------------|
| Casino shell | `src/map/Lobby.model.json` → `Workspace.Lobby` |
| Doorway prompts | `Lobby.Portals` + `LobbyService` |
| Game rooms | `RocketRunArena`, `PlinkoArena`, `MineSweeperArena` |
| Origins / exits | `Config.ROCKET_RUN` / `PLINKO` / `MINE_SWEEPER` (`ArenaOrigin`, `LeavePosition`) |

## Footprint (top-down)

```
                         -Z (north)
            ========================================
            | Mines room | Rocket room | Plinko room|
            |  origin    |   origin    |   origin   |
            |  (-55,0,   |  (0,0,      |  (55,0,    |
            |   -110)    |   -110)     |   -110)    |
            |----door----|----door-----|----door----|
            |         GAME HALL (carpet)            |
            |              ARCADE sign              |
            |---------------------------------------|
            |     decorative TABLE PIT              |
            |         red carpet aisle              |
            |======= grand entrance / spawn ========|
                         +Z (south)
```

Envelope ≈ **180 × 200** studs. Pit roof ~22 studs; game-room roof ~54 studs (Plinko board height).

## Arena origins (inside the building)

| Game | `ArenaOrigin` | Doorway / `LeavePosition` |
|------|---------------|---------------------------|
| Mine Sweeper | `(-55, 0, -110)` | `(-55, 3, -78)` |
| Rocket Run | `(0, 0, -110)` | `(0, 3, -78)` |
| Plinko Points | `(55, 0, -110)` | `(55, 3, -78)` |

Rocket home: `Config.ROCKET_RUN.RocketHomePosition` `(0, 7, -118)`.

## Player flow

1. Spawn at `Config.LOBBY.SpawnPosition` `(0, 3, 48)`.
2. Walk the red carpet through the table pit into the game hall.
3. Enter a room doorway (walk in + **Play** to start the session).
4. Leave → corridor `LeavePosition` for that game (not the front door).

## Portal contract (doorways)

Under `Workspace.Lobby.Portals` each model still needs:

- Name `Portal_<GameId>` + attribute `GameId`
- `Frame` (`BasePart`)
- `Gate` with `EnterPrompt`

These are **room doorways**, not destination teleporters.

## Atmosphere props (non-playable)

`Workspace.Lobby.Atmosphere`:

- `Tables` - roulette / blackjack / poker props (felt, rims, chips, lamps)
- **Chairs** are placed at runtime by `CasinoChairs` via `CFrame.lookAt` so every seat faces its table (including angled tables)
- Felt labels (roulette grid / BET spots) via `LobbyService.dressCasinoTables`
- `LoungeBar` - marble bar + bottle shelf; stools placed by `CasinoChairs`
- Floor: green casino field carpet + red runners + decorative floor chips

`Workspace.Lobby.Structure.CeilingLights` / `Chandeliers` / `Sconces` - pit and hall lighting.

Do not wire atmosphere props to remotes or currency.

## What not to touch

- Wager / RNG / settle logic
- Arena gameplay parts (pegs, rocket, mine tiles) except position sync with `ArenaOrigin`
- `GameId` / `PLAYABLE_GAMES` without a product change

## Phase 2 polish

- Richer table meshes; auto-join on room volume enter
- Rocket roof / glass atrium presentation
- Optional chip sinks (VIP, cosmetics)
