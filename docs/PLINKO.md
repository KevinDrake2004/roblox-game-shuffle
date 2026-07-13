# Plinko Points

Arcade plinko inspired by Shuffle Plinko. Each **ball drop** stakes a **wager**; a **free gravity/peg simulation** decides the bucket, then the server pays that multiplier.

This document describes **current** behavior for playtesting and economy tuning.

## How to play

1. Enter the **Plinko Points** portal from the lobby (existing hub portal at `(0, 3.5, -28)`).
2. You teleport to **PlinkoArena** (east of Rocket Run). Purple neon board + pegs + buckets.
3. Set **wager**, **balls**, and **risk** (Low / Medium / High), press Apply, then **Drop**.
4. Watch the ball fall with gravity and bounce off pegs. It lands wherever physics takes it.
5. WIN / BUST / LOSS feedback updates chips and session P/L.
6. Leave via the Leave button or the spawn-pad proximity prompt.

## Drop flow

```
idle → deduct wager×balls → DropStarted(dropIds) → staggered free physics → Landed each → settle each
```

| Step | What happens |
|------|----------------|
| Request drop | Client fires `PlinkoPointsDrop`. Server rejects if busy, on cooldown, or balance `<` wager×balls. |
| Deduct | `CurrencyService.deductChips(wager * ballCount)`. |
| DropStarted | Server sends `dropIds` + stagger. **No buckets chosen yet.** |
| Physics | Client releases balls back-to-back; each is an independent gravity sim. Balls ignore each other (peg/rail only). |
| Landed | Client fires `PlinkoPointsLanded(dropId, bucketIndex)` per ball. |
| Settle | Per ball: `payout = floor(wager * BucketMultipliers[bucket])`. |

Ball visuals are client-only (`CurrentCamera.PlinkoLocalFx`). Other players never see your ball. Multiplier labels are local and only spawn while you are in the Plinko arena.

## Economy

| Outcome | Formula | Balance effect |
|---------|---------|----------------|
| Any land | `payout = floor(wager * multiplier)` | Wager already deducted; credit `payout` (0 on bust). `netDelta = payout - wager`. |
| Center soft land | multiplier `0` | Stake lost; `payout = 0`. Near-center is `1x` (push). |

### RTP / risk scale

- Landing distribution comes from **Galton-board physics** (center-biased ≈ normal / binomial).
- `BucketWeights` document the intended `C(8,k)` spread for RTP math; they are not rolled as RNG.
- Players pick a **risk tier**; each tier has its own integer `bucketMultipliers`, design RTP, and **ball cap**.
- Higher risk → larger max jackpot, design RTP approaches **100%**, lower ball cap.
- Lower risk → smaller jackpots, higher design RTP, higher ball cap.
- Default is **Medium** (current ~139% / 26x max / 100 ball cap).
- Multipliers are **integers** so `floor(wager * mult)` does not wipe sub-1x buckets at wager `1`.

| Risk | Rows | Buckets | Max mult | Design RTP | Ball cap | Multipliers (edges…center…) |
|------|------|---------|----------|------------|----------|------------------------------|
| Low | 8 | 9 | 10x | ~148% | 200 | `10, 4, 2, 1, 1, 1, 2, 4, 10` |
| Medium | 12 | 13 | 50x | ~137% | 100 | `50, 15, 6, 2, 1, 1, 1, 1, 1, 2, 6, 15, 50` |
| High | 16 | 17 | 100x | ~100% | 25 | `100, 38, 14, 5, 2, 1, 1, 1, 0, …` |

Each player rebuilds a **local** peg/bucket board for their risk (shared arena decor hides while playing).

### Daily earn cap

Same as Rocket Run: `Config.DAILY_EARN_CAP` applies to earn-only `awardChips`. Wager payouts use `creditPayout` and are **not** clipped by the cap.

## Buckets (medium / default, 12 rows)

Left → right (13 buckets). Design land curve ≈ binomial `C(12, k)`.

| Index | Multiplier | Weight `C(12,k)` |
|-------|------------|------------------|
| 0 / 12 | 50x | 1 |
| 1 / 11 | 15x | 12 |
| 2 / 10 | 6x | 66 |
| 3 / 9 | 2x | 220 |
| 4 / 8 | 1x | 495 |
| 5 / 7 | 1x | 792 |
| 6 | 1x | 924 |

`E[multiplier] ≈ 1.375` on Medium when lands match `C(12,k)`.

The Galton peg board (row `r` has `r+1` pegs) creates that center bias; row count follows risk.

## Arena coordinates

| Area | Position | Notes |
|------|----------|-------|
| Lobby portals | z ≈ -28 | Unchanged; do not rebuild lobby |
| Rocket Run arena | `(0, 5, -140)` | Cyan; do not modify |
| **Plinko arena origin** | `(90, 5, -140)` | Purple; ~90 studs east of Rocket Run |
| Plinko spawn pad | `(90, 6, -126)` | Leave prompt attached |
| Plinko board / buckets | z ≈ -150.5 | Wider/taller playfield (~40 stud rails) |

All Plinko geometry lives under `Workspace.PlinkoArena` only.

## Key `Config.PLINKO` constants

| Key | Role |
|-----|------|
| `DefaultWager` / `MinWager` / `MaxWager` | Stake clamps |
| `DefaultRiskId` / `RiskLevels` | Risk scale: multipliers, target RTP, ball cap per tier |
| `TargetRTP` / `BucketMultipliers` | Mirror of Medium tier (convenience / fallbacks) |
| `BucketWeights` | Tuning reference for physical land spread (not rolled) |
| `DropCooldownSeconds` | Per-player drop throttle |
| `LandReportTimeoutSeconds` | Max wait for client land report |
| `ArenaOrigin` | World center of PlinkoArena |
| `CameraOffset` | Client board-cam offset from `CameraFocus` |
| `PegRows` | Visual peg grid rows |
| `BallRadius` / `BallGravity` / `BallBounce` | Client gravity sim feel |
| `BallMaxSimSeconds` / `BallPegHitCooldown` | Sim limits |

Full table lives in `src/shared/Config.luau`.

## Client visuals (local only)

| Piece | Behavior |
|-------|----------|
| Ball | Free gravity + soft peg bounce; multi-ball overlap allowed; **no ball-ball collision** |
| Multi-drop | Choose any ball count you can afford; stake = wager×count; large volleys burst within ~1.5s |
| Peg hits | Brief color flash on contact |
| Bucket land | Local light + color flash on the slot physics entered (size stays fixed) |
| Multiplier labels | SurfaceGui on each bucket face (local only); destroyed on leave |
| Other players | Never see your ball or your labels |

## File map

| Path | Role |
|------|------|
| `src/server/games/PlinkoPoints/init.luau` | Join/leave, wager deduct, land settle |
| `src/client/controllers/PlinkoPointsController.luau` | Remotes, board camera, local labels, session P/L |
| `src/client/controllers/PlinkoBallPhysics.luau` | Free local gravity + peg bounce sim |
| `src/client/ui/PlinkoPointsHud.luau` | Wager UI, drop / leave, WIN/BUST feedback |
| `src/map/PlinkoArena.model.json` | Floor, spawn, board, buckets (pegs spawned on server) |
| `src/shared/Config.luau` | `PLINKO` tuning |
| `src/shared/Types.luau` | Joined / drop started / result payloads |
| `src/shared/Remotes.luau` | Plinko event names |

## Verify (manual)

- Lobby → Plinko portal → arena at x≈90; Rocket Run at `(0, 5, -140)` unchanged
- Multiplier labels visible in Plinko only; gone in lobby / Rocket Run
- Ball bounces off pegs with gravity; path does **not** curve toward a pre-chosen slot
- Repeated drops cluster toward center (normal / Galton curve); edge 26x is rare
- Other clients do not see your ball
- Over many drops, average return trends near ~139% RTP (variance still hurts short sessions)
- Balance `<` wager → drop rejected, no deduct
- Leave mid-drop → wager refunded
- Leave after settle → hub spawn `(0, 3, 20)`
- Rocket Run still playable; no shared arena parts
