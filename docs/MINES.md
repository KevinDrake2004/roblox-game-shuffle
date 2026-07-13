# Mine Sweeper Arcade

**Status: playable alpha** on `feature/mines-dev`.

Casino-style Mines (Shuffle / Stake), **not** Windows Minesweeper. Each player runs their own private round: they choose how many mines (1-24), flip gems to raise a multiplier, and cash out whenever they want after at least one safe reveal.

---

## 1. Overview

- **Per player** - mine layout is rolled privately when that player starts a round. No shared server board.
- **Player picks risk** - mine count 1-24. More mines → steeper multiplier growth per gem.
- **Gem = multiply** - every non-mine tile multiplies the cash-out factor via conditional survival odds.
- **Cash out anytime** - after ≥1 safe reveal, bank `floor(wager * mult * PlayerReturnFactor)`.
- **Mine = bust** - stake already deducted; `netDelta = -wager`.
- Design RTP > 100% via `PlayerReturnFactor` (~105%). Short sessions can still bust.

No adjacency numbers, no chord clears, no shared grid state between players.

---

## 2. How to play

1. Enter the **Mine Sweeper Arcade** lobby portal.
2. Teleport to **MineSweeperArena** at `(-90, 5, -140)` (west of Rocket Run).
3. Set **wager** and **mines** (1-24). HUD shows ~1-gem multiplier preview for the selected mine count.
4. **Start Round** - server deducts wager and places your private mines (never sent to the client).
5. Click tiles on the board. Gem (lime) → multiplier rises. Mine (magenta) → round over.
6. **Cash Out** after any gem to bank the payout, or keep going.
7. Leave via Leave / spawn prompt (active round stake is forfeited).

### Round flow

```
idle → Start Round (deduct + private RNG mines) → reveal gems… → cash out OR mine hit → settled → idle
```

| Step | What happens |
|------|----------------|
| Start Round | Clamp loadout; `deductChips(wager)`. Reject if balance `<` wager or already playing. Server places `mineCount` mines for **this player only**. |
| Reveal | Client sends tile index `0-24`. Server validates. Gem → update mult; mine → bust settle. |
| Cash Out | After ≥1 gem while playing. `payout = floor(wager * mult * PlayerReturnFactor)`. |
| All gems cleared | Auto cash-out at max multiplier for that mine count. |

---

## 3. Multiplier formula

Grid has `n = GridSize²` tiles (25) and `m` mines (player-chosen). After `r` safe reveals:

\[
\text{mult}(r) = \prod_{i=0}^{r-1} \frac{n - i}{n - m - i}
\]

Each gem multiplies by the odds that the next unrevealed tile is still safe:

\[
\text{step} = \frac{\text{tiles left}}{\text{safe tiles left}}
\]

Higher `m` → larger steps → higher risk / reward. Shared helper: `Config.mineSweeperMultiplier(r, m)`.

```
payout = floor(wager * mult(r) * PlayerReturnFactor)
netDelta = payout - wager
```

Mine hit: `payout = 0`, `netDelta = -wager`.

---

## 4. Economy

| Outcome | Formula | Balance effect |
|---------|---------|----------------|
| Cash-out | `floor(wager * mult * PlayerReturnFactor)` | Stake already deducted; credit payout |
| Mine hit | - | Stake lost; no refund |
| Leave / disconnect mid-round | - | Stake forfeited (no refund) |

Daily earn cap applies to earn-only `awardChips`, not `creditPayout`.

---

## 5. File map

| Path | Role |
|------|------|
| `src/server/games/MineSweeper/init.luau` | Per-player join/leave, mine RNG, reveal, cash-out |
| `src/client/controllers/MineSweeperController.luau` | Remotes, camera, local tile paint, click input |
| `src/client/ui/MineSweeperHud.luau` | Wager, mines +/- , start, cash out, WIN/BUST |
| `src/shared/Config.luau` | `MINE_SWEEPER` + `mineSweeperMultiplier` |
| `src/shared/Types.luau` / `Remotes.luau` | Payloads and events |
| `src/map/MineSweeperArena.model.json` | Floor, spawn, 5×5 tiles |
| `docs/MINES.md` | This doc |

---

## 6. Arena coordinates

| Area | Position | Notes |
|------|----------|-------|
| Rocket Run | `(0, 5, -140)` | Unchanged |
| Plinko | `(90, 5, -140)` | Unchanged |
| **Mine Sweeper** | `(-90, 5, -140)` | Magenta; west of Rocket Run |
| Spawn pad | `(-90, 6, -126)` | Leave prompt |
| Tiles | z ≈ -148 | `Tile_0`…`Tile_24` with `TileIndex` |

Geometry only under `Workspace.MineSweeperArena`. Tile color changes are **client-local** (other players do not see your gems/mines).

---

## 7. Remotes

| Event | Direction | Purpose |
|-------|-----------|---------|
| `MineSweeperSetLoadout` | C→S | Wager + mine count (next round) |
| `MineSweeperJoined` | S→C | Arena enter snapshot |
| `MineSweeperStartRound` | C→S | Deduct + place private mines |
| `MineSweeperRoundStarted` | S→C | Round live (no mine positions) |
| `MineSweeperReveal` | C→S | Reveal tile index |
| `MineSweeperTileRevealed` | S→C | Safe gem update |
| `MineSweeperCashOut` | C→S | Bank current multiplier |
| `MineSweeperResult` | S→C | Cash-out or mine-hit settle |
| `MineSweeperRejected` | S→C | Action blocked |
| `MineSweeperLeave` / `Left` | C→S / S→C | Leave handshake |

---

## 8. Verify (manual)

- [ ] Lobby portal enters arena (no "coming soon"); Rocket Run / Plinko unchanged
- [ ] Mines slider 1-24; more mines → higher 1-gem preview mult
- [ ] Wager 10, 3 mines, 1 safe reveal, cash out → payout > 0, chips update
- [ ] Hit a mine → `netDelta = -wager`
- [ ] Balance `<` wager → start rejected
- [ ] Leave mid-round → hub; stake gone
- [ ] Two players: each has independent boards / outcomes
