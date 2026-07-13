# Mine Sweeper Arcade - MVP

**Status: minimal MVP complete** on `feature/mines-dev`.

Playable chip-wager casino Mines on a 5×5 board: player-chosen mine count, private server RNG, gem multipliers, cash-out, and top-down tile picking. This is the canonical doc for the shipped Mines MVP. It matches `Config.MINE_SWEEPER` and related code as of the join scaffold, per-player round loop, cursor/hover fixes, and board-camera zoom on this branch.

---

## 1. Overview

**Mine Sweeper Arcade** is Shuffle Arcade's casino Mines game (inspired by Shuffle / Stake Mines) - **not** Windows Minesweeper.

- Players stake chips, choose how many mines (1-24), and reveal tiles one at a time.
- Safe tiles (gems) raise a cash-out multiplier via conditional survival odds.
- Hitting a mine ends the round and loses the stake; cashing out banks the payout.
- Design RTP is **above 100%** via `PlayerReturnFactor` (~105%). Short sessions can still bust.
- Server owns mine layout, reveals, and settlement. Client is presentation + input only.
- Rounds are **per player** - no shared board, no adjacency numbers, no chord clears.

---

## 2. How to play

1. Enter the **Mine Sweeper Arcade** lobby portal (hub portals at z ≈ -28).
2. Teleport to **MineSweeperArena** at `(-90, 5, -140)` (west of Rocket Run). Magenta 5×5 board, top-down cam.
3. Set **wager** and **mines** (1-24). HUD shows an approximate 1-gem multiplier preview for the selected mine count.
4. Press **Start Round**. Server deducts the wager and places your private mines (never sent to the client).
5. Hover / click tiles. Gem (lime) → multiplier rises. Mine (magenta) → round over, stake lost.
6. After at least one gem, **Cash Out** to bank `floor(wager * multiplier * PlayerReturnFactor)`, or keep revealing.
7. Leave via Leave button or spawn-pad proximity prompt (mid-round stake is forfeited).

### Round flow

```
idle → Start Round (deduct + private RNG) → reveal gems… → cash out OR mine hit → settled → idle
```

| Step | What happens |
|------|----------------|
| Start Round | Clamp loadout; `deductChips(wager)`. Reject if balance `<` wager or already playing. Server places `mineCount` mines for **this player only**. |
| Reveal | Client sends tile index `0-24`. Server validates unrevealed + in round. Gem → update mult; mine → bust settle. |
| Cash Out | After ≥1 gem while `playing`. Credit payout; clear round. |
| All gems cleared | Auto cash-out at max multiplier for that mine count (`r = n - m`). |

Tile colors and hover are **client-local**. Other players never see your gems, mines, or highlights.

---

## 3. Multiplier formula

Grid has `n = GridSize²` tiles (25) and `m` mines (player-chosen). After `r` safe reveals, the fair cash-out multiplier is the reciprocal of surviving those picks under random mine placement:

\[
\text{mult}(r) = \prod_{i=0}^{r-1} \frac{n - i}{n - m - i} = \frac{\binom{n}{r}}{\binom{n - m}{r}}
\]

Each gem multiplies by the conditional odds that the next unrevealed tile is still safe:

\[
\text{step} = \frac{\text{tiles left}}{\text{safe tiles left}} = \frac{n - r_{\text{before}}}{n - m - r_{\text{before}}}
\]

Higher `m` → larger steps → higher risk / reward. Shared helper: `Config.mineSweeperMultiplier(r, m)`.

Payout applies the player edge toward TargetRTP (~105%):

```
payout = floor(wager * mult(r) * PlayerReturnFactor)
netDelta = payout - wager
```

Mine hit: `payout = 0`, `netDelta = -wager` (stake already deducted).

Example: wager `10`, `m = 3`, `r = 1` → `mult = 25/22 ≈ 1.136`, with `PlayerReturnFactor = 1.05` → `payout = floor(10 * 1.136 * 1.05) = 11`.

---

## 4. Economy

| Outcome | Formula | Balance effect |
|---------|---------|----------------|
| Cash-out | `floor(wager * mult * PlayerReturnFactor)` | Stake already deducted; credit payout. `netDelta = payout - wager`. |
| Mine hit | - | Stake lost; no refund. `payout = 0`, `netDelta = -wager`. |
| Leave / disconnect mid-round | - | Stake forfeited (already deducted; no refund). |

### RTP

- `TargetRTP` (e.g. `1.05`) is the design expected return per chip wagered over many rounds.
- `PlayerReturnFactor` scales cash-out payouts and is the primary lever toward that target.
- Long-term, players are rewarded for volume (RTP > 100%). Short-term variance (mine hits) still drains sessions.

### Daily earn cap

`Config.DAILY_EARN_CAP` applies to earn-only `CurrencyService.awardChips`. Wager payouts use `creditPayout` and are **not** clipped by the cap.

### Authority

- Server: loadout clamps, deduct, private mine RNG, reveal validation, cash-out / bust settle.
- Client: top-down camera, hover highlight, tile clicks, local board paint, HUD.
- Mine positions never leave the server until a mine is hit (client only learns the bust tile).

---

## 5. Architecture

```
Lobby portal → MineSweeper.join → arena teleport + top-down cam
     ↓
HUD (wager / mines) → MineSweeperSetLoadout
     ↓
MineSweeperStartRound → deduct → private mines → RoundStarted
     ↓
click tile → MineSweeperReveal → TileRevealed (gem) or Result (mine)
     ↓
Cash Out → Result (cashed_out) → idle
```

| Layer | Path | Role |
|-------|------|------|
| Server | `src/server/games/MineSweeper/init.luau` | Join/leave, per-player rounds, RNG, settle |
| Client controller | `src/client/controllers/MineSweeperController.luau` | Remotes, board cam, hover, clicks, local FX |
| HUD | `src/client/ui/MineSweeperHud.luau` | Wager, mines +/-, start, cash out, WIN/BUST |
| Shared config | `src/shared/Config.luau` (`MINE_SWEEPER`, `mineSweeperMultiplier`) | Clamps, RTP, arena / cam |
| Types / remotes | `src/shared/Types.luau`, `src/shared/Remotes.luau` | Payloads and event names |
| Arena map | `src/map/MineSweeperArena.model.json` | Floor, spawn, 5×5 tiles, leave prompt |
| Lobby wire | `src/server/services/LobbyService.luau` | `PLAYABLE_GAMES.MineSweeper` → `MineSweeper.join` |

---

## 6. Client UX notes

| Behavior | Detail |
|----------|--------|
| Camera | Straight top-down (`CameraOffset` height-only + `CameraFov`). Spawn side toward bottom of screen. |
| Hover | Unrevealed tile under cursor tints pink; gems/mines stay lime/magenta. |
| Clicks | Blended screen/viewport aim ray so picks match the pointer (Gui inset). |
| HUD overlays | Flash / status labels are pass-through so they do not block board input. |
| Local paint | Tile color changes do not replicate; each client only sees their own round. |

---

## 7. Config knobs

Primary file: `src/shared/Config.luau` → `Config.MINE_SWEEPER`.

| Knob | What to tune |
|------|----------------|
| `GridSize` | Side length (tiles = size²; MVP is 5 → 25) |
| `MinMines` / `MaxMines` / `DefaultMines` | Mine range (1-24) |
| `DefaultWager` / `MinWager` / `MaxWager` | Stake clamps |
| `TargetRTP` / `PlayerReturnFactor` | Design EV / cash-out scale |
| `ArenaOrigin` | World placement (west of Rocket Run) |
| `CameraOffset` / `CameraFov` | Top-down zoom (height + FOV) |

Resolver: `Config.mineSweeperMultiplier(revealedCount, mineCount)`.

---

## 8. Arena coordinates

| Area | Position | Notes |
|------|----------|-------|
| Lobby portals | z ≈ -28 | Unchanged; `Portal_MineSweeper` already existed |
| Rocket Run arena | `(0, 5, -140)` | Cyan; do not modify for Mines |
| Plinko arena | `(90, 5, -140)` | Purple; do not modify for Mines |
| **Mine Sweeper origin** | `(-90, 5, -140)` | Magenta; ~90 studs west of Rocket Run |
| Spawn pad | `(-90, 6, -126)` | Leave prompt attached |
| Board / tiles | z ≈ -148 | `Tiles/Tile_0` … `Tile_24` with `TileIndex` |

All Mine Sweeper geometry lives under `Workspace.MineSweeperArena` only.

---

## 9. Remotes

| Event | Direction | Purpose |
|-------|-----------|---------|
| `MineSweeperSetLoadout` | C→S | Wager + mine count (applies to next round) |
| `MineSweeperJoined` | S→C | Arena enter snapshot |
| `MineSweeperStartRound` | C→S | Deduct wager and place private mines |
| `MineSweeperRoundStarted` | S→C | Round live snapshot (no mine positions) |
| `MineSweeperReveal` | C→S | Reveal tile index `0-24` |
| `MineSweeperTileRevealed` | S→C | Safe gem update |
| `MineSweeperCashOut` | C→S | Bank current multiplier (≥1 gem) |
| `MineSweeperResult` | S→C | Cash-out or mine-hit settle |
| `MineSweeperRejected` | S→C | Action blocked (`{ reason }`) |
| `MineSweeperLeave` / `MineSweeperLeft` | C→S / S→C | Leave handshake |

---

## 10. Known limitations / MVP scope

Shipped and playable, with these known limits:

1. **No mid-round loadout edits** - wager / mines apply to the next start only.
2. **Leave mid-round forfeits stake** - no refund once deducted (same spirit as disconnect).
3. **Local-only visuals** - other clients never see your board state (by design for MVP).
4. **No auto cash-out target** - manual cash-out only (plus auto when all gems cleared).
5. **Fixed 5×5** - grid size is config-driven but MVP ships one size.

Out of scope for this MVP: multi-grid sizes in UI, provably-fair seed display, spectator boards, or cosmetics sinks.

---

## 11. Status

**Mine Sweeper minimal MVP is complete** on this branch:

- Lobby portal enter / leave; arena west of Rocket Run
- Per-player rounds with private mine RNG
- Wager + mines 1-24, start, reveal, cash-out, mine bust
- Survival-odds multipliers + `PlayerReturnFactor` toward ~105% RTP
- Top-down board cam, hover highlight, cursor-aligned picks
- Server-authoritative chip deduct / payout via `CurrencyService`

Further Mines work (polish FX, auto cash-out target, fair seeds) is optional, not MVP blockers.

---

## 12. Verify (manual)

- [ ] Lobby → **Mine Sweeper Arcade** enters arena at x≈-90 (no "coming soon")
- [ ] Top-down cam fills the 5×5; hover highlights the tile under the cursor
- [ ] Click selects that same tile
- [ ] Mines 1-24; more mines → higher 1-gem preview mult
- [ ] Wager 10, 3 mines, 1 safe reveal, cash out → payout > 0, chips update
- [ ] Hit a mine → lose wager (`netDelta = -wager`)
- [ ] Balance `<` wager → start rejected, no deduct
- [ ] Leave mid-round → hub spawn; stake gone
- [ ] Rocket Run and Plinko still playable; no shared arena part conflicts
- [ ] Two players: independent layouts / outcomes; no cross-visible tile paints
