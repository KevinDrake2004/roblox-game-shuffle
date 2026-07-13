# Mine Sweeper Arcade

**Status: join scaffold** on `feature/mines-dev`. Portal enter / leave / arena camera work; round play (start, reveal, cash-out) is next.

Arcade mine game inspired by Shuffle Mines. Players stake chips on a **5×5** board, pick a mine count, reveal gems to raise the multiplier, and cash out - or hit a mine and lose the stake.

---

## 1. How to play (target flow)

1. Enter the **Mine Sweeper Arcade** lobby portal (hub portals at z ≈ -28).
2. Teleport to **MineSweeperArena** at `(-90, 5, -140)` (west of Rocket Run). Magenta board, 25 tiles.
3. Set **wager** and **mine count** (1-24), then **Start Round** (server deducts wager and places mines).
4. Reveal tiles one at a time. Gem → multiplier rises. Mine → round over, stake lost.
5. After at least one safe reveal, **Cash Out** to bank `floor(wager * multiplier * PlayerReturnFactor)`.
6. Leave via Leave button or spawn-pad proximity prompt.

### Round flow

```
idle → Start Round (deduct) → reveal gems… → cash out OR mine hit → settled → idle
```

| Step | What happens |
|------|----------------|
| Start Round | Clamp loadout; `deductChips(wager)`. Reject if balance `<` wager or already playing. Server places `mineCount` mines via RNG (never sent to client). |
| Reveal | Client sends tile index `0-24`. Server validates unrevealed + in round. Gem → update multiplier; mine → settle bust. |
| Cash Out | Allowed after ≥1 safe reveal while `playing`. Credit payout; clear round. |

---

## 2. Multiplier formula

Grid has `n = GridSize²` tiles (25) and `m` mines. After `r` safe reveals, the **fair** cash-out multiplier is the reciprocal of the probability of surviving those picks under random mine placement:

\[
\text{mult}(r) = \prod_{i=0}^{r-1} \frac{n - i}{n - m - i} = \frac{\binom{n}{r}}{\binom{n - m}{r}}
\]

Each gem multiplies by the conditional survival odds of the next unrevealed safe tile:

\[
\text{step} = \frac{\text{tiles left}}{\text{safe tiles left}} = \frac{n - r_{\text{before}}}{n - m - r_{\text{before}}}
\]

Payout applies the player edge toward TargetRTP (~105%):

```
payout = floor(wager * mult(r) * PlayerReturnFactor)
netDelta = payout - wager
```

Mine hit: `payout = 0`, `netDelta = -wager` (stake already deducted).

`PlayerReturnFactor` (e.g. `1.05`) is the primary lever toward `TargetRTP`. Short sessions can still bust before the long-run edge shows up.

---

## 3. Economy

| Outcome | Formula | Balance effect |
|---------|---------|----------------|
| Cash-out | `floor(wager * mult * PlayerReturnFactor)` | Stake already deducted; credit payout |
| Mine hit | - | Stake lost; no refund |
| Leave mid-round | TBD with gameplay | Prefer forfeit stake (no refund) once deducted |

Daily earn cap (`Config.DAILY_EARN_CAP`) applies to earn-only `awardChips`. Wager payouts use `creditPayout` and are **not** clipped by the cap.

---

## 4. File map

| Path | Role |
|------|------|
| `src/server/games/MineSweeper/init.luau` | Join/leave (round lifecycle next) |
| `src/client/controllers/MineSweeperController.luau` | Remotes, board camera, session |
| `src/client/ui/MineSweeperHud.luau` | Status + leave (full controls next) |
| `src/shared/Config.luau` (`MINE_SWEEPER`) | Grid, mines, wager, RTP, arena / cam |
| `src/shared/Types.luau` / `Remotes.luau` | Loadout / round / result payloads + events |
| `src/map/MineSweeperArena.model.json` | Floor, spawn, 5×5 tiles, leave prompt |
| `docs/MINES.md` | This doc |

---

## 5. Arena coordinates

| Area | Position | Notes |
|------|----------|-------|
| Lobby portals | z ≈ -28 | Unchanged; `Portal_MineSweeper` already exists |
| Rocket Run arena | `(0, 5, -140)` | Cyan; do not modify |
| Plinko arena | `(90, 5, -140)` | Purple; do not modify |
| **Mine Sweeper origin** | `(-90, 5, -140)` | Magenta; ~90 studs west of Rocket Run |
| Spawn pad | `(-90, 6, -126)` | Leave prompt attached |
| Board / tiles | z ≈ -148 | `Tiles/Tile_0` … `Tile_24` with `TileIndex` |

All Mine Sweeper geometry lives under `Workspace.MineSweeperArena` only.

---

## 6. Remotes

| Event | Direction | Purpose |
|-------|-----------|---------|
| `MineSweeperSetLoadout` | C→S | Wager + mine count |
| `MineSweeperJoined` | S→C | Arena enter snapshot |
| `MineSweeperStartRound` | C→S | Request start (gameplay next) |
| `MineSweeperRoundStarted` | S→C | Round live snapshot |
| `MineSweeperReveal` | C→S | Reveal tile index |
| `MineSweeperTileRevealed` | S→C | Safe gem update |
| `MineSweeperCashOut` | C→S | Bank current multiplier |
| `MineSweeperResult` | S→C | Cash-out or mine-hit settle |
| `MineSweeperRejected` | S→C | Action blocked |
| `MineSweeperLeave` / `MineSweeperLeft` | C→S / S→C | Leave handshake |

---

## 7. Config knobs

Primary file: `src/shared/Config.luau` → `Config.MINE_SWEEPER`.

| Knob | What to tune |
|------|----------------|
| `GridSize` | Side length (tiles = size²) |
| `MinMines` / `MaxMines` / `DefaultMines` | Mine range |
| `DefaultWager` / `MinWager` / `MaxWager` | Stake clamps |
| `TargetRTP` / `PlayerReturnFactor` | Design EV / cash-out scale |
| `ArenaOrigin` / `CameraOffset` | World placement and board cam |

---

## 8. Verify (manual)

### Join scaffold (this commit)

- [ ] Lobby → **Mine Sweeper Arcade** portal enters arena at x≈-90 (no "coming soon")
- [ ] Board camera frames the 5×5; title sign reads MINE SWEEPER
- [ ] Leave button / spawn prompt → hub spawn
- [ ] Rocket Run and Plinko still playable; no shared arena part conflicts

### Gameplay (upcoming)

- [ ] Wager 10, 3 mines, 1 safe reveal, cash out → payout > 0, chips update
- [ ] Hit a mine → lose wager (`netDelta = -wager`)
- [ ] Balance `<` wager → cannot start round
- [ ] Leave mid-round behavior matches settlement rules
