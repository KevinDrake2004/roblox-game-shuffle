# Plinko Points

Arcade plinko inspired by Shuffle Plinko. Each **ball drop** stakes a **wager**; the server picks a multiplier bucket and settles chips.

This document describes **current** behavior for playtesting and economy tuning.

## How to play

1. Enter the **Plinko Points** portal from the lobby (existing hub portal at `(0, 3.5, -28)`).
2. You teleport to **PlinkoArena** (east of Rocket Run). Purple neon board + pegs + buckets.
3. Set **wager** (chips bet per drop) and press **Drop Ball**.
4. Watch the ball fall into a multiplier bucket. WIN / BUST / LOSS feedback updates chips and session P/L.
5. Leave via the Leave button or the spawn-pad proximity prompt.

## Drop flow

```
idle → deduct wager → roll weighted bucket → credit payout (if any) → result HUD
```

| Step | What happens |
|------|----------------|
| Request drop | Client fires `PlinkoPointsDrop`. Server rejects if not in arena, on cooldown, already dropping, or balance `<` wager. |
| Deduct | `CurrencyService.deductChips(wager, "PlinkoPoints:wager")`. |
| Roll | Weighted pick from `BucketWeights` → `BucketMultipliers[index]`. |
| Settle | `payout = floor(wager * multiplier * PlayerReturnFactor)`; credit via `creditPayout` when payout `>` 0. |
| Result | Client animates ball to the chosen bucket (cosmetic only), then shows outcome. |

## Economy

| Outcome | Formula | Balance effect |
|---------|---------|----------------|
| Any land | `payout = floor(wager * multiplier * PlayerReturnFactor)` | Wager already deducted; credit `payout` (0 on bust). `netDelta = payout - wager`. |
| Center `0x` bust | multiplier `0` | Stake lost; `payout = 0`, `netDelta = -wager`. |

### RTP

- `TargetRTP` (e.g. `1.05`) is the design expected return per chip wagered over many drops.
- Bucket multipliers × binomial-style weights yield **E[multiplier] ≈ 1.0**.
- `PlayerReturnFactor` (e.g. `1.05`) scales payouts so realized EV ≈ TargetRTP.
- Long-term volume is rewarding (RTP > 100%). Short-term busts (center `0x`, low buckets) still drain sessions.

### Daily earn cap

Same as Rocket Run: `Config.DAILY_EARN_CAP` applies to earn-only `awardChips`. Wager payouts use `creditPayout` and are **not** clipped by the cap.

## Buckets (default)

Left → right (9 buckets). Weights are binomial `C(8, k)`.

| Index | Multiplier | Weight |
|-------|------------|--------|
| 0 | 10x | 1 |
| 1 | 4x | 8 |
| 2 | 1.5x | 28 |
| 3 | 0.8x | 56 |
| 4 | 0x (bust) | 70 |
| 5 | 0.8x | 56 |
| 6 | 1.5x | 28 |
| 7 | 4x | 8 |
| 8 | 10x | 1 |

Tune in `Config.PLINKO.BucketMultipliers` / `BucketWeights`. Keep `#multipliers == #weights`.

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
| `TargetRTP` | Design expected return per wager (> 1.0) |
| `PlayerReturnFactor` | Payout scale factor |
| `BucketMultipliers` / `BucketWeights` | Board payout distribution |
| `DropCooldownSeconds` | Per-player drop throttle |
| `ArenaOrigin` | World center of PlinkoArena |
| `CameraOffset` | Client board-cam offset from `CameraFocus` |
| `PegRows` / `BallDropDuration` | Visual pegs + client ball tween |

Full table lives in `src/shared/Config.luau`.

## File map

| Path | Role |
|------|------|
| `src/server/games/PlinkoPoints/init.luau` | Join/leave, wager deduct, bucket RNG, settlement |
| `src/client/controllers/PlinkoPointsController.luau` | Remotes, board camera, ball tween, session P/L |
| `src/client/ui/PlinkoPointsHud.luau` | Wager UI, drop / leave, WIN/BUST feedback |
| `src/map/PlinkoArena.model.json` | Floor, spawn, board, buckets (pegs spawned on server) |
| `src/shared/Config.luau` | `PLINKO` tuning |
| `src/shared/Types.luau` | Joined / result payloads |
| `src/shared/Remotes.luau` | Plinko event names |

## Verify (manual)

- Lobby → Plinko portal → arena at x≈90; Rocket Run at `(0, 5, -140)` unchanged
- Wager 10, land 1.5x, `PlayerReturnFactor = 1.05` → `payout = floor(10 * 1.5 * 1.05) = 15`, `netDelta = +5`
- Wager 10, center 0x → lose 10 chips (`netDelta = -10`)
- Balance `<` wager → drop rejected, no deduct
- Leave → hub spawn `(0, 3, 20)`
- Rocket Run still playable; no shared arena parts
