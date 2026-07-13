# Casino Shell - First Pass

Hard Rock-style enclosed casino hub. Players spawn on the floor, walk the pit, then enter physical game rooms in the north wing.

This document is the **source of truth for the first casino floor pass** (building shell, atmosphere, decorative tables). Game rules stay in [`ROCKET_RUN.md`](ROCKET_RUN.md), [`PLINKO.md`](PLINKO.md), and [`MINES.md`](MINES.md). Game-room interiors are **out of scope for this pass** and will be fixed region-by-region later.

## Pass status

| Area | Status |
|------|--------|
| Building envelope, walls, roofs | Done |
| Floor layers (green field, red aisles, chips) | Done |
| Decorative table pit (roulette / blackjack / poker) | Done |
| Runtime chairs + dealer seats | Done |
| Lounge bar (west wall) | Done |
| Lighting (chandeliers, sconces, ceiling lights) | Done |
| Game-room doorways / portal labels | Done (visual) |
| Zone-based room entry (walk in / walk out) | In progress on `feature/casino-shell` |
| Rocket / Plinko / Mines room polish | **Deferred** - fix per region later |

## Design intent

| Zone | What it is |
|------|------------|
| **Casino floor** | Enclosed building - green pit field, red aisle runners, pillars, lounge |
| **Table pit** | Non-playable roulette, blackjack, and poker props |
| **Game hall** | North corridor with three labeled doorways |
| **Game rooms** | Physical `*Arena` folders seated in those rooms (gameplay polish later) |

Atmosphere props never touch remotes or currency. Only the three playable rooms run wager loops.

## Source of truth

| Piece | Path / instance |
|-------|-----------------|
| Casino shell | `src/map/Lobby.model.json` → `Workspace.Lobby` |
| Runtime chairs | `src/server/services/CasinoChairs.luau` |
| Felt / bar dressing | `src/server/services/LobbyService.luau` |
| Zone entry (in progress) | `src/server/services/ArenaZones.luau` |
| Game rooms | `RocketRunArena`, `PlinkoArena`, `MineSweeperArena` |
| Origins | `Config.ROCKET_RUN` / `PLINKO` / `MINE_SWEEPER` (`ArenaOrigin`) |

Map rebuild / fix helpers (idempotent Python):

- `scripts/rebuild_roulette_and_bar.py`
- `scripts/fix_floor_carpet_zfight.py`
- `scripts/fix_blackjack_betspots.py`
- `scripts/fix_blackjack_alignment.py`

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
            |   (roulette / blackjack / poker)      |
            |         red carpet aisle              |
            |  LoungeBar (west)                     |
            |======= grand entrance / spawn ========|
                         +Z (south)
```

Envelope ≈ **184 × 206** studs (outer walls at X±92, Z +66 / −140). Pit roof ~22 studs; game-room roof ~54 studs (Plinko board height).

## Floor and walls (first-pass rules)

Floor layers use a **strict height ladder** so coplanar faces never z-fight:

1. Base / green casino field under pits and rooms
2. Red aisle runners and cross arms (walk paths only)
3. Medallion / accents
4. Decorative floor chips

**Red carpet stays on walk aisles only.** Table pits stay on green so chairs do not sit on red (avoids red-on-red parallax flicker).

Walls and corner posts are nudged so room-facing faces are not coplanar with hall fills. Do not stack overlapping floor parts at the same Y.

## Decorative tables

Under `Workspace.Lobby.Atmosphere.Tables`. Each folder carries:

- `TableType` - `"Roulette"` | `"Blackjack"` | `"Poker"`
- `TableYaw` - degrees; props and chairs rotate with this

| Type | Count | Layout notes |
|------|-------|--------------|
| Roulette | 4 | Rectangular: wheel at one end, European single-zero felt across the rest |
| Blackjack | 6 | Felt + shoe / discard / dealer pad + numbered bet spots (flush on felt) |
| Poker | 4 | Oval felt with pot label |

### Roulette

- Wheel end: housing, well, bowl, disk, pockets, hub, spindle (unique Y tops - no coplanar flicker)
- Felt: runtime `SurfaceGui` European layout (0 + 3×12 grid + dozens + even-money), gap-separated clipped bands
- Seats: 3 per long side, 1 at the open end, **1 dealer at the wheel end**

### Blackjack

- Bet spots: numbered disc flush on felt; gold ring as a lower halo (never covers the number)
- Angled tables (`TableYaw` ≠ 0): shoe / discard / dealer pad / bet spots realigned with Roblox `Orientation(0, yaw, 0)` via `fix_blackjack_alignment.py`

### Poker

- Decorative only; pot oval dressed at runtime

## Chairs

Chairs are **not** authored in `Lobby.model.json`. `CasinoChairs.place(lobby)` runs from `LobbyService.start()` and fills `Atmosphere.Chairs` with `CFrame.lookAt` seats that face each table regardless of yaw.

- Player chairs: burgundy cushion
- Dealer chairs: dark cushion + gold trim (`IsDealer` attribute)
- Bar stools: derived from `LoungeBar.CounterTop` geometry

Re-running chair placement is safe after clearing `Atmosphere.Chairs`.

## Lounge bar

`Atmosphere.LoungeBar` sits on the **west wall**: back cabinet, bottle shelves, marble counter, foot rail, lit `BarSign` ("BAR" SurfaceGui). Tagged `TableType = "Bar"` for stool placement. This replaced an earlier ambiguous pit prop that read as a "weird area."

## Lighting

`Workspace.Lobby.Structure`:

- `CeilingLights` / `Chandeliers` / `Sconces` - pit and hall
- Lobby lighting also set in `LobbyService` from `Config.LOBBY` (clock, ambient, fog)

## Player flow (target)

1. Spawn at `Config.LOBBY.SpawnPosition` `(0, 3, 48)`.
2. Walk the red carpet through the table pit into the game hall.
3. Walk into a game room - session starts (HUD / focused camera). **No teleport.**
4. Walk out of the room floor bounds - session ends. **No leave button required.**

Doorway models under `Lobby.Portals` keep visual gates / labels (`Portal_<GameId>` + `GameId` attribute). Enter / leave **ProximityPrompts** are removed; volume entry is driven by `ArenaZones` against each arena `Floor` part.

Legacy `LeavePosition` values in Config still point at the corridor just south of each doorway (`z ≈ -78`) for docs / fallback reference - join/leave no longer teleports there.

## Arena origins (inside the building)

| Game | `ArenaOrigin` | Corridor reference |
|------|---------------|--------------------|
| Mine Sweeper | `(-55, 0, -110)` | `(-55, 3, -78)` |
| Rocket Run | `(0, 0, -110)` | `(0, 3, -78)` |
| Plinko Points | `(55, 0, -110)` | `(55, 3, -78)` |

Rocket home: `Config.ROCKET_RUN.RocketHomePosition` `(0, 7, -118)`.

## What this pass does not own

Fix these **per region** in later passes - do not treat them as casino-floor regressions:

- Rocket Run room presentation (roof / atrium / pad polish)
- Plinko board / rail / camera framing tweaks inside `PlinkoArena`
- Mine Sweeper table / tile presentation inside `MineSweeperArena`
- Free-walk vs focused-camera HUD polish per game
- Richer table meshes / real casino kit assets

## What not to touch

- Wager / RNG / settle logic
- Arena gameplay parts (pegs, rocket, mine tiles) except position sync with `ArenaOrigin`
- `GameId` / `PLAYABLE_GAMES` without a product change
- Floor height ladder without re-checking z-fight

## Follow-ups

1. Finish zone-based entry client polish (HUD leave removal, free-walk toggles) on `feature/casino-shell`
2. Region passes: Mines room → Rocket room → Plinko room
3. Optional chip sinks (VIP, cosmetics) to offset RTP > 100%
