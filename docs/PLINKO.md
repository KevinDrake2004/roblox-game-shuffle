# Plinko Points

Arcade plinko inspired by Shuffle Plinko. Each **ball drop** stakes a **wager**; a **free gravity/peg simulation** decides the bucket, then the server pays that multiplier.

This document describes **current** behavior for playtesting and economy tuning.

## How to play

1. Enter the **Plinko Points** portal from the lobby (existing hub portal at `(0, 3.5, -28)`).
2. You teleport to **PlinkoArena** (east of Rocket Run). Purple neon board + pegs + buckets.
3. Set **wager** (chips bet per drop) and press **Drop Ball**.
4. Watch the ball fall with gravity and bounce off pegs. It lands wherever physics takes it.
5. WIN / BUST / LOSS feedback updates chips and session P/L.
6. Leave via the Leave button or the spawn-pad proximity prompt.

## Drop flow

```
idle → deduct wager → DropStarted → free client physics → Landed(bucket) → credit payout → Result HUD
```

| Step | What happens |
|------|----------------|
| Request drop | Client fires `PlinkoPointsDrop`. Server rejects if not in arena, on cooldown, already dropping, or balance `<` wager. |
| Deduct | `CurrencyService.deductChips(wager, "PlinkoPoints:wager")`. |
| DropStarted | Server fires `PlinkoPointsDropStarted` (`dropId`, wager, chips). **No bucket is chosen yet.** |
| Physics | Client runs local gravity + peg bounce. Landing is **not** steered or pre-rolled. |
| Landed | Client fires `PlinkoPointsLanded(dropId, bucketIndex)` for the slot the ball entered. |
| Settle | `payout = floor(wager * BucketMultipliers[bucket])`; credit when payout `>` 0. |
| Timeout | If no land report within `LandReportTimeoutSeconds`, server settles as center bust. |
| Leave mid-drop | Pending wager is refunded. |

Ball visuals are client-only (`CurrentCamera.PlinkoLocalFx`). Other players never see your ball. Multiplier labels are local and only spawn while you are in the Plinko arena.

## Economy

| Outcome | Formula | Balance effect |
|---------|---------|----------------|
| Any land | `payout = floor(wager * multiplier)` | Wager already deducted; credit `payout` (0 on bust). `netDelta = payout - wager`. |
| Center `0x` bust | multiplier `0` | Stake lost; `payout = 0`, `netDelta = -wager`. |

### RTP

- Landing distribution comes from **Galton-board physics** (center-biased ≈ normal / binomial).
- `BucketWeights` document the intended `C(8,k)` spread for RTP math; they are not rolled as RNG.
- **RTP is just `E[BucketMultipliers]` under that curve.** Tune the multipliers until that equals `TargetRTP` (1.05). There is no separate player-return factor on Plinko.
- Short-term busts (center `0x`) still drain sessions; edge jackpots are rare.

### Daily earn cap

Same as Rocket Run: `Config.DAILY_EARN_CAP` applies to earn-only `awardChips`. Wager payouts use `creditPayout` and are **not** clipped by the cap.

## Buckets (default)

Left → right (9 buckets). Design land curve ≈ binomial `C(8, k)` (center-heavy / normal-like).

| Index | Multiplier | Weight `C(8,k)` | Approx P |
|-------|------------|-----------------|----------|
| 0 | 24x | 1 | 0.4% |
| 1 | 4x | 8 | 3.1% |
| 2 | 1.5x | 28 | 10.9% |
| 3 | 0.65x | 56 | 21.9% |
| 4 | 0x (bust) | 70 | 27.3% |
| 5 | 0.65x | 56 | 21.9% |
| 6 | 1.5x | 28 | 10.9% |
| 7 | 4x | 8 | 3.1% |
| 8 | 24x | 1 | 0.4% |

`E[multiplier] = 268.8 / 256 = 1.05` exactly → design **RTP = 105%** when lands match this curve.

The Galton peg board (row `r` has `r+1` pegs) is what creates that center bias in the free physics sim. Multipliers pay the rare edges; common center lands are busts / low returns.

## Arena coordinates

| Area | Position | Notes |
|------|----------|-------|
| Lobby portals | z ≈ -28 | Unchanged; do not rebuild lobby |
| Rocket Run arena | `(0, 5, -140)` | Cyan; do not modify |
| **Plinko arena origin** | `(90, 5, -140)` | Purple; ~90 studs east of Rocket Run |
| Plinko spawn pad | `(90, 6, -126)` | Leave prompt attached |
| Plinko board / buckets | z ≈ -150.5 | Facing spawn (+Z) |

All Plinko geometry lives under `Workspace.PlinkoArena` only.

## Key `Config.PLINKO` constants

| Key | Role |
|-----|------|
| `DefaultWager` / `MinWager` / `MaxWager` | Stake clamps |
| `TargetRTP` | Design aim only (1.05); match by tuning multipliers vs land curve |
| `BucketMultipliers` | Payout per landed bucket (`payout = floor(wager * mult)`) |
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
| Ball | Free gravity + peg bounce; **no** soft bias toward a target bucket |
| Peg hits | Brief color flash on contact |
| Bucket land | Local light + size pulse on the slot physics entered |
| Multiplier labels | Created on join, destroyed on leave |
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
- Repeated drops cluster toward center (normal / Galton curve); edge 20x is rare
- Other clients do not see your ball
- Over many drops, average return trends near ~105% RTP (variance still hurts short sessions)
- Balance `<` wager → drop rejected, no deduct
- Leave mid-drop → wager refunded
- Leave after settle → hub spawn `(0, 3, 20)`
- Rocket Run still playable; no shared arena parts
