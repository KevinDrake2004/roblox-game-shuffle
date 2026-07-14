# Casino Shell - Resort Polish Pass

Hard Rock / Vegas-strip inspired enclosed casino hub with a south resort facade and approach plaza. Players spawn on the plaza, walk the porte-cochere into the lobby, cross the pit, then enter physical game rooms in the north wing.

This document is the **source of truth for the casino floor + exterior polish** (building shell, plaza, vestibule, atmosphere). Game rules stay in [`ROCKET_RUN.md`](ROCKET_RUN.md), [`PLINKO.md`](PLINKO.md), and [`MINES.md`](MINES.md). Game-room interiors remain **deferred** and are fixed region-by-region later.

## Pass status

| Area | Status |
|------|--------|
| Building envelope, walls, roofs | Done (first pass) |
| Floor layers (green field, red aisles, chips) | Done |
| Decorative table pit (roulette / blackjack / poker) | Done |
| Runtime chairs + dealer seats | Done |
| Lounge bar (west wall) | Done + bar-glow polish |
| Lighting (chandeliers, sconces, ceiling lights) | Done + cove / foyer wash |
| Game-room doorways / portal labels | Done (visual) |
| Zone-based room entry (walk in / walk out) | Done on main |
| **Exterior resort facade + plaza (Phase A)** | **Done on `feature/casino-polish`** |
| **Entrance vestibule / foyer (Phase B)** | **Done on `feature/casino-polish`** |
| **Interior luxury trim (Phase C)** | **Done on `feature/casino-polish`** |
| **Facade quality pass (window bays, columns, crown)** | **Done on `feature/casino-polish`** |
| Rocket / Plinko / Mines room polish | **Deferred** - fix per region later |

## Design intent

| Zone | What it is |
|------|------------|
| **Approach plaza** | South of the envelope - valet curb loop, fountain medallion, lit planters, red-carpet queue language (decorative, not a wait system) |
| **Resort facade** | Tall south front with window-bay grid, porte-cochere + fluted columns, marquee, diamond crown, corner towers, side elevation bays |
| **Vestibule / foyer** | Open double doors, reception desk, VIP rope cue, foyer chandelier - clear doors → aisle → pit sightline |
| **Casino floor** | Enclosed building - green pit field, red aisle runners, pillars, lounge |
| **Table pit** | Non-playable roulette, blackjack, and poker props + chip-tray / pit-rail polish |
| **Game hall** | North corridor with three labeled VIP-framed doorways |
| **Game rooms** | Physical `*Arena` folders seated in those rooms (gameplay polish later) |

Atmosphere props never touch remotes or currency. Only the three playable rooms run wager loops.

## Source of truth

| Piece | Path / instance |
|-------|-----------------|
| Casino shell + exterior | `src/map/Lobby.model.json` → `Workspace.Lobby` |
| Runtime chairs | `src/server/services/CasinoChairs.luau` |
| Felt / bar / sign dressing | `src/server/services/LobbyService.luau` |
| Zone entry | `src/server/services/ArenaZones.luau` |
| Game rooms | `RocketRunArena`, `PlinkoArena`, `MineSweeperArena` |
| Origins | `Config.ROCKET_RUN` / `PLINKO` / `MINE_SWEEPER` (`ArenaOrigin`) |

Map rebuild / fix helpers (idempotent Python):

- `scripts/rebuild_casino_polish.py` - exterior, plaza, vestibule, luxury trim (this pass)
- `scripts/rebuild_roulette_and_bar.py`
- `scripts/fix_floor_carpet_zfight.py`
- `scripts/fix_blackjack_betspots.py`
- `scripts/fix_blackjack_alignment.py`

Re-run polish after floor/wall rebuilds if those scripts replace `Structure` children wholesale:

```bash
python3 scripts/rebuild_casino_polish.py
```

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
            |======= vestibule / grand doors =======|
            |    porte-cochere / canopy (z~66-84)   |
            |  plaza carpet · fountain · valet loop |
            |           spawn (0, 3, 112)            |
                         +Z (south)
```

Envelope ≈ **184 × 206** studs (outer walls at X±92, Z +66 / −140). South / pit wing walls are **~22** studs tall; game-room wing walls stay **~54** for Plinko height. Plaza extends to roughly **Z +125**. World grass apron ≈ **420 × 420**. Marquee / crown read above the south parapet (~Y 25–51).

South entry has a real door cutout (`|x| < 12`, under `Ext_South_Lint` / `EntryBayLint`). `EntryBayBack` is L/R only so the opening is visible. Canopy soffit uses a strict Y ladder (neon / coffer inset / coffer / deck) so down-spots do not z-fight.

## Exterior (facade pass)

`Structure.Exterior` + `Atmosphere.Plaza` + `Atmosphere.Ground` + `Atmosphere.SiteLighting`:

- **South hero** - wing podium + gold water-table (door bay kept clear), tall center entry bay with entablature, marble veneer, **repeating window modules** (frame / glass / mullion / warm glow)
- **Porte-cochere** - thicker canopy, gold fascia, soffit coffers, cyan underside neon, four **classical fluted columns** (plinth / shaft / capital) outside the walk channel (`|x|≈17`)
- **Marquee** - deep board + stepped cyan / purple / magenta neon bezels; `Lobby.BrandSign` at `(0, 29.5, 72.2)` sized `56×10` facing south (fills outer neon board)
- **Crown** - multi-part diamond + fins + spire + SpecialMesh Sphere/FileMesh gem accents (original silhouette; not third-party IP)
- **Corners** - SW / SE towers with gold caps and window bays
- **Sides** - marble veneer, pilaster rhythm, east/west window modules (no continuous side neon belts)
- **Plaza / ground / site lighting** - flat apron parts + perimeter lamps; hills from real Terrain
- **Terrain** (`CasinoTerrain`) - bakes once (`ShuffleCasinoTerrainVersion`); LeafyGrass recolored to WorldGrass synthetic green; smooth FillBall ramp starting ~25% back from the south facade (flanks + behind shell); spawn `(0, 3, 112)` outside. Bump `VERSION` to reshape, then Save. ArenaOrigins unchanged

### Mesh accents

| Instance | Approach | Notes |
|----------|----------|-------|
| Column shafts / capitals | Part + `Shape=Cylinder` + flute ribs | Always loads |
| `CrownMeshGem` | SpecialMesh `MeshType=Sphere` | Always loads |
| `CrownMeshGemFile` | SpecialMesh FileMesh `rbxassetid://67524904` | Optional gem; swap ID in `rebuild_casino_polish.py` if needed |
| `mesh_part()` helper | MeshPart + `MeshId` | Ready for future catalog meshes via Rojo |

Rebuild: `python3 scripts/rebuild_casino_polish.py`

Night wash lights use fully invisible host parts (`Transparency = 1`) so no floating neon cubes appear near the marquee. Lamp posts keep a small intentional neon glow under the head.

## Entrance sequence (Phase B)

`Atmosphere.Vestibule`:

- Swung-open double doors with gold frames + glass
- Stone threshold into the pit
- **Reception desk** just inside on the east (`ReceptionSign` SurfaceGui)
- **VIP podium + rope pen** on the west (`VipSign` SurfaceGui)
- Foyer chandelier ring + mirrored side panels
- Center carpet sightline kept clear

## Interior luxury (Phase C)

| Folder | Role |
|--------|------|
| `Structure.LuxuryTrim` | Marble veneers, gold baseboards/cornice, aisle gold borders, VIP door frames, wall art, wayfinding bar |
| `Structure.Coffers` | Pit ceiling coffer grid |
| `Structure.CoveLights` | Warm / cyan / magenta cove strips |
| `Atmosphere.PitDressing` | Blackjack chip trays + pit rail caps (non-playable) |
| `Atmosphere.BarGlow` | Bar canopy neon, back-bar glow, extra bottles |

Floor height ladder is unchanged:

1. Base / green casino field under pits and rooms
2. Red aisle runners and cross arms (walk paths only)
3. Medallion / accents
4. Decorative floor chips

Plaza carpets sit on their own apron/asphalt south of the envelope and do not stack on green pit layers.

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

`Atmosphere.LoungeBar` sits on the **west wall**: back cabinet, bottle shelves, marble counter, foot rail, lit `BarSign` ("BAR" SurfaceGui). Tagged `TableType = "Bar"` for stool placement. `Atmosphere.BarGlow` adds canopy / back-bar neon and an extra bottle row without rewriting the core bar rebuild.

## Lighting

`Workspace.Lobby.Structure`:

- `CeilingLights` / `Chandeliers` / `Sconces` - pit and hall
- `CoveLights` / foyer + plaza washes - polish pass
- Lobby lighting also set in `LobbyService` from `Config.LOBBY` (clock, ambient, fog)

`Config.LOBBY` keeps a night clock (`ClockTime = 22`) so facade neon and window glow read correctly.

## Player flow (target)

1. Spawn at `Config.LOBBY.SpawnPosition` `(0, 3, 112)` on the plaza, facing the facade.
2. Walk the red carpet under the porte-cochere through the grand doors into the foyer (reception east, VIP west).
3. Follow the red carpet through the table pit into the game hall.
4. Walk into a game room - session starts (HUD / focused camera). **No teleport.**
5. Walk out of the room floor bounds - session ends. **No leave button required.**

Players can also leave the asphalt plaza onto the grass apron and walk around the building.

Doorway models under `Lobby.Portals` keep visual gates / labels (`Portal_<GameId>` + `GameId` attribute). Enter / leave **ProximityPrompts** are removed; volume entry is driven by `ArenaZones` against each arena `Floor` part.

Legacy `LeavePosition` values in Config still point at the corridor just south of each doorway (`z ≈ -78`) for docs / fallback reference - join/leave no longer teleports there.

## Arena origins (inside the building)

| Game | `ArenaOrigin` | Corridor reference |
|------|---------------|--------------------|
| Mine Sweeper | `(-55, 0, -110)` | `(-55, 3, -78)` |
| Rocket Run | `(0, 0, -110)` | `(0, 3, -78)` |
| Plinko Points | `(55, 0, -110)` | `(55, 3, -78)` |

Rocket home: `Config.ROCKET_RUN.RocketHomePosition` `(0, 7, -118)`.

**This polish pass does not move ArenaOrigins.**

## Manual verify checklist

- [ ] Approach from south / spawn on plaza - facade reads hotel-casino (podium, tall center bay, window grid, marquee, crown, corner towers)
- [ ] No floating neon cubes near the marquee / wash lights
- [ ] Continuous carpet with side ropes only; walk doors → foyer → pit → game hall (columns outside walk)
- [ ] Reception (east) and VIP podium (west) readable just inside the doors
- [ ] Fountain visible east of the approach; grass walkable around the building
- [ ] Brand sign shows game name on the exterior marquee
- [ ] Sides readable from grass perimeter (pilasters + windows + gold belt)
- [ ] Rocket Run / Plinko / Mines still join, wager, settle, and leave via zone walk
- [ ] No new remotes or currency touches from atmosphere props

## What this pass does not own

Fix these **per region** in later passes - do not treat them as casino-floor regressions:

- Rocket Run room presentation (roof / atrium / pad polish)
- Plinko board / rail / camera framing tweaks inside `PlinkoArena`
- Mine Sweeper table / tile presentation inside `MineSweeperArena`
- Free-walk vs focused-camera HUD polish per game
- Richer table meshes / real casino kit assets
- Mandatory queue / skip monetization
- Cosmetics / VIP product

## What not to touch

- Wager / RNG / settle logic
- Arena gameplay parts (pegs, rocket, mine tiles) except position sync with `ArenaOrigin`
- `GameId` / `PLAYABLE_GAMES` without a product change
- Floor height ladder without re-checking z-fight

## Follow-ups

1. Region passes: Mines room → Rocket room → Plinko room
2. Optional richer marquee letter meshes if SurfaceGui read is weak at distance
3. Optional chip sinks (VIP, cosmetics) to offset RTP > 100%
