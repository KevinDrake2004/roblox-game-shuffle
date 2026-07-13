# Plinko Points - MVP

**Status: MVP complete** on `feature/plinko-dev`.

Playable chip-wager Galton board with Low / Medium / High risk, multi-ball drops, server settle, local physics boards, and multiplier land feedback. This is the canonical doc for the shipped Plinko MVP. It matches `Config.PLINKO` and related code as of the RTP retune, per-risk physics, and bucket-flash work on this branch.

---

## 1. Overview

**Plinko Points** is Shuffle Arcade's chip-wager Galton board (inspired by Shuffle Plinko).

- Players stake chips per ball, drop one or more balls on a peg board, and land in multiplier buckets.
- Losing lands (0x center busts) deduct value; winning lands pay out via the risk table.
- Design RTP is **above 100%** on Low and Medium, and **exactly 100%** on High (binomial tables). Short sessions can still bust before the long-run edge shows up.
- Server owns wagers and payouts. Client owns free gravity / peg sim and reports the land bucket.

---

## 2. How to play

1. Enter the **Plinko Points** lobby portal (hub portals at z ≈ -28).
2. Teleport to **PlinkoArena** at `(90, 5, -140)` (east of Rocket Run). Purple neon board, pegs, buckets.
3. In the HUD, set **wager**, **ball count**, and **risk** (Low / Medium / High), then Apply.
4. Press **Drop**. Server deducts `wager × ballCount` if balance allows.
5. Balls release in short bursts (large volleys finish within ~1.5s). Each ball falls with gravity and bounces off pegs - path is **not** pre-chosen.
6. On land, the client reports the bucket; the server pays `floor(wager * multiplier)` and updates chips / session P/L.
7. Leave via Leave button or spawn-pad proximity prompt (unsettled balls refund).

### Drop flow

```
idle → deduct wager×balls → DropStarted(dropIds) → staggered free physics → Landed each → settle each
```

| Step | What happens |
|------|----------------|
| Request drop | Client fires `PlinkoPointsDrop`. Rejected if busy, on cooldown, or balance `<` wager×balls. |
| Deduct | `CurrencyService.deductChips(wager * ballCount)`. |
| DropStarted | Server sends `dropIds` + stagger / burst. **No buckets chosen yet.** |
| Physics | Client releases balls; independent gravity sims. Balls ignore each other (peg/rail only). |
| Landed | Client fires `PlinkoPointsLanded(dropId, bucketIndex)` per ball. |
| Settle | Per ball: `payout = floor(wager * risk.bucketMultipliers[bucket])`. |

Ball visuals and multiplier labels are client-only under `CurrentCamera.PlinkoLocalFx`. Other players never see your balls or labels.

---

## 3. Risk tiers

Players pick a risk tier. Each tier has its own row count, multipliers, design RTP, ball cap, and physics profile.

Buckets = `pegRows + 1`. Exact binomial design RTP = `Σ C(pegRows, k) · m[k] / 2^pegRows`.

| Risk | `pegRows` | Buckets | Max balls | Max mult | Design RTP | Center bust |
|------|-----------|---------|-----------|----------|------------|-------------|
| **Low** | 8 | 9 | 200 | 17x | ~138% (`354/256` ≈ 1.383) | Single center `0` |
| **Medium** (default) | 12 | 13 | 100 | 121x | ~120% (`4916/4096` ≈ 1.200) | Three center `0`s |
| **High** | 16 | 17 | 25 | 316x | 100% (`65536/65536` = 1.000) | Three center `0`s |

### Exact `bucketMultipliers` (left edge → center → right edge)

| Risk | Multipliers |
|------|-------------|
| Low | `17, 6, 2, 1, 0, 1, 2, 6, 17` |
| Medium | `121, 38, 11, 3, 1, 0, 0, 0, 1, 3, 11, 38, 121` |
| High | `316, 88, 27, 10, 3, 2, 1, 0, 0, 0, 1, 2, 3, 10, 27, 88, 316` |

Higher risk → more rows, larger edge jackpots, tighter ball cap, design RTP → 100%. Lower risk → smaller jackpots, higher design RTP, higher ball cap.

Multipliers are **integers** so `floor(wager * mult)` does not wipe sub-1x buckets at wager `1`.

### Medium reference weights

`Config.PLINKO.BucketWeights` documents `C(12, k)` for the default Medium board (not rolled as RNG):

`1, 12, 66, 220, 495, 792, 924, 792, 495, 220, 66, 12, 1`

---

## 4. Economy

| Outcome | Formula | Balance effect |
|---------|---------|----------------|
| Any land | `payout = floor(wager * multiplier)` | Stake already deducted; credit `payout` (0 on bust). `netDelta = payout - wager`. |
| Center soft land | multiplier `0` | Stake lost; `payout = 0`. |
| Leave mid-drop | Refund unsettled balls | `creditPayout` for remaining pending wagers. |
| Land timeout | Center bucket of that risk | Anti-hang if client never reports. |

### RTP assumptions

- Design RTP uses **exact binomial** lands (`C(pegRows, k)`). Tables are tuned so Low ≈ 138%, Medium ≈ 120%, High = 100%.
- **Live lands follow client Galton physics**, not a server binomial roll. Realized RTP can diverge from the table if the sim is not a perfect bean machine.
- Arcade economy intent still holds: Low/Med reward volume (RTP > 100%); High is fair EV on the design table.
- Daily earn cap (`Config.DAILY_EARN_CAP`) applies to earn-only `awardChips`. Wager payouts use `creditPayout` and are **not** clipped by the cap.

### Authority

- Server: loadout clamps, deduct, settle, refund, cooldown, timeout.
- Client: physics path and land bucket report.
- **Integrity follow-up:** land reports are client-trusted. A cheater could report favorable buckets. Multipliers themselves always come from the server risk table.

---

## 5. Architecture

```
Lobby portal → PlinkoPoints.join → arena teleport
     ↓
Client HUD (wager / balls / risk) → PlinkoPointsSetWager
     ↓
PlinkoPointsDrop → deduct → PlinkoPointsDropStarted
     ↓
PlinkoBallPhysics (local board under camera FX)
     ↓
PlinkoPointsLanded → settle → PlinkoPointsResult
```

| Layer | Path | Role |
|-------|------|------|
| Server | `src/server/games/PlinkoPoints/init.luau` | Join/leave, wager deduct, land settle, timeout, refund |
| Client controller | `src/client/controllers/PlinkoPointsController.luau` | Remotes, board camera, labels, session P/L, drop batch flash reset |
| Client physics | `src/client/controllers/PlinkoBallPhysics.luau` | Local Galton board, free gravity sim, peg/bucket FX |
| HUD | `src/client/ui/PlinkoPointsHud.luau` | Wager UI, drop / leave, WIN/BUST feedback |
| Shared config | `src/shared/Config.luau` (`PLINKO`, `getPlinkoRisk`) | Risk tables, physics profiles, arena / sim constants |
| Types / remotes | `src/shared/Types.luau`, `src/shared/Remotes.luau` | Payloads and event names |
| Arena map | `src/map/PlinkoArena.model.json` | Floor, spawn, rails, shared decor pegs/buckets |

### Local boards vs shared decor

- While in session, the client builds a **per-risk** peg/bucket board under `CurrentCamera.PlinkoLocalFx/Board`.
- Shared arena `Pegs` / `Buckets` are hidden via `LocalTransparencyModifier` so only the local risk board is visible.
- On leave, local board clears and shared decor returns.

---

## 6. Physics

Not one global formula. Each risk carries a **physics profile** on `RiskLevels[].physics` (ball/peg size, leave speed/angle, drag, start spread, rail damp, etc.). Board layout still scales to rail width; sim knobs do not share one formula across tiers.

| Idea | Behavior |
|------|----------|
| Free path | Gravity + peg collisions decide the land. No soft bias toward a chosen bucket. |
| Galton leave X | After a peg hit, horizontal leave is floored to a board-computed `GaltonLeaveX` (~half pitch per row) so the ball reaches the next row near a peg instead of dropping straight down. |
| Peg ghost-until-clear | After a valid leave, that peg is ignored (`awaitingClear`) until the ball clears it. Stops apex re-hits from canceling horizontal leave. |
| Apex coin-flip | Near-vertical contact normals pick L/R randomly; off-apex prefers the hit-offset side (~62%). |
| Multi-ball | Independent sims; no ball-ball collision. |
| Shared globals | `BallGravity`, `BallBounce`, `BallMaxSpeed`, `BallMaxSimSeconds`, etc. are fallbacks / shared constants when board attrs are missing. |

---

## 7. UI feedback

### Bucket land colors

Idle cups are base **purple** (`Config.COLORS.NeonPurple`). On land, the cup flashes by multiplier relative to the risk's `maxMultiplier`:

| Band | Color |
|------|-------|
| `0x` (bust) | Magenta |
| Low relative mult (`t < 0.06`) | Cyan |
| Mid-low (`t < 0.20`) | Purple |
| Mid-high (`t < 0.50`) | Lime |
| High / jackpot | Gold |

Land color **persists** for the drop batch. When every ball in the volley has finished (or on cancel / leave), cups **reset to idle purple** via `PlinkoBallPhysics.resetBucketsIdle`.

### Other feedback

- Peg hits: brief white flash.
- HUD: WIN / BUST / LOSS outcome flash, chips, session net delta.
- Multiplier labels: local SurfaceGuis on bucket faces; destroyed on leave.

---

## 8. Known limitations / MVP scope

Shipped and playable, with these known limits:

1. **Client-trusted land reports** - integrity follow-up (server should not blindly trust bucket index long-term).
2. **Physics ≠ perfect binomial** - design RTP assumes `C(n,k)`; live lands can skew vs the table.
3. **Unreported lands time out as center** - center is often a 0x bust on Med/High; protects hangs, not fairness against malice.
4. **Local-only visuals** - other players never see your balls (by design for MVP).
5. **No server-side physics replay** - settle trusts the reported index after clamps.

Out of scope for this MVP: anti-cheat land validation, Minesweeper, or further economy sinks.

---

## 9. Config knobs

Primary file: `src/shared/Config.luau` → `Config.PLINKO`.

| Knob | What to tune |
|------|----------------|
| `RiskLevels[].bucketMultipliers` / `pegRows` / `targetRTP` / `maxBallCount` / `maxMultiplier` | Risk tables and design RTP |
| `RiskLevels[].physics` | Per-tier ball/peg size, leave speed/angle, drag, start spread, rail damp |
| `DefaultRiskId` | Default tier (`"medium"`) |
| `DefaultWager` / `MinWager` / `MaxWager` | Stake clamps |
| `DefaultBallCount` / `MinBallCount` / `BallDropStaggerSeconds` / `BallDropMaxReleaseSeconds` | Multi-ball release timing |
| `BucketWeights` | Documented Medium binomial curve (reference only) |
| `BucketMultipliers` / `TargetRTP` / `PegRows` | Convenience mirrors of Medium |
| `DropCooldownSeconds` / `LandReportTimeoutSeconds` | Drop throttle and hang timeout |
| `ArenaOrigin` / `CameraOffset` | World placement and board cam |
| `BallGravity` / `BallBounce` / `BallMaxSpeed` / `BallMaxSimSeconds` / … | Shared sim fallbacks |

Resolver: `Config.getPlinkoRisk(riskId)`.

---

## 10. Status

**Plinko MVP is complete** on this branch:

- Enter arena, choose risk / wager / balls, drop, land, settle
- Three risk tables with current multipliers and design RTPs (~138% / ~120% / 100%)
- Per-risk local boards and physics profiles
- Multi-ball volleys with stagger / burst
- Multiplier bucket flash + batch purple reset
- Server-authoritative chip deduct / payout / refund

Further Plinko work (integrity, closer binomial match) is optional polish, not MVP blockers.

---

## Arena coordinates

| Area | Position | Notes |
|------|----------|-------|
| Lobby portals | z ≈ -28 | Unchanged |
| Rocket Run arena | `(0, 5, -140)` | Cyan; do not modify for Plinko |
| **Plinko arena origin** | `(90, 5, -140)` | Purple; ~90 studs east of Rocket Run |
| Plinko spawn pad | `(90, 6, -126)` | Leave prompt attached |
| Plinko board / buckets | z ≈ -150.5 | Rails ~40 studs wide |

All Plinko geometry lives under `Workspace.PlinkoArena` only.

## Remotes

| Event | Direction | Purpose |
|-------|-----------|---------|
| `PlinkoPointsSetWager` | C→S | Wager + ball count + risk id |
| `PlinkoPointsJoined` | S→C | Arena enter snapshot |
| `PlinkoPointsDrop` | C→S | Request drop |
| `PlinkoPointsDropStarted` | S→C | Wager accepted; start physics |
| `PlinkoPointsLanded` | C→S | Report land bucket |
| `PlinkoPointsResult` | S→C | Per-ball settle |
| `PlinkoPointsDropRejected` | S→C | Drop blocked |
| `PlinkoPointsLeave` / `PlinkoPointsLeft` | C→S / S→C | Leave handshake |

## Verify (manual)

- Lobby → Plinko portal → arena at x≈90; Rocket Run unchanged
- Risk switch rebuilds local peg/bucket count (9 / 13 / 17 cups)
- Multiplier labels only in Plinko; gone in lobby / Rocket Run
- Ball path is free physics (not a pre-chosen slot)
- Lands cluster toward center; edge jackpots are rare
- Cups flash by mult, then reset to purple when the batch finishes
- Other clients do not see your ball
- Balance `<` stake → drop rejected, no deduct
- Leave mid-drop → unsettled wager refunded
- Rocket Run still playable; no shared arena part conflicts
