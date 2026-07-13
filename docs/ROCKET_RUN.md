# Rocket Run

Arcade timing game inspired by Shuffle Crash. One **server-wide** rocket and crash point; each player stakes a **wager** and cashes out independently.

This document describes **current** behavior for playtesting and economy tuning.

## How to play

1. Enter the **Rocket Run** portal from the lobby.
2. Set **wager** (chips bet per round) and optional **auto cash-out** multiplier.
3. Wait for the shared countdown, then watch the multiplier climb.
4. Cash out (button or Space) before the rocket crashes, or spectate after settling.
5. Leave via the Leave button or the arena proximity prompt.

View modes: **Walk** (free cam), **Graph** (telemetry overlay), **Rocket** (follow cam), **Both**.

## Round flow

```
idle → countdown → flying → crashed → intermission → countdown …
```

| Phase | What happens |
|-------|----------------|
| `countdown` | Crash multiplier is rolled server-side. Players already in the arena attempt eligibility: wager is deducted if balance allows; otherwise they spectate. |
| `flying` | Multiplier = `exp(GrowthRate * elapsed)`. Manual and auto cash-outs settle. Rocket keeps flying after individuals cash out. |
| `crashed` | Intact rocket hides; debris rains. Eligible players who never cashed out lose their wager (`netDelta = -wager`). |
| Intermission | Brief pause (`IntermissionSeconds`), then the next countdown. |

### Join timing

- Join during **countdown** → attempt eligibility (deduct wager) for that round.
- Join during **flying** → spectate until the next launch (`eligible = false`, no deduct).
- Loadout changes apply to the **next** round you enter as eligible (values are read when the participant row is created).
- Balance below your wager (after clamps) → cannot play that round; spectate only.

## Loadout

| Field | Meaning |
|-------|---------|
| **Wager** | Integer clamped to `MinWager`–`MaxWager`. Deducted server-side when you become eligible. |
| **Auto cash-out** | Optional target ≥ 1.01x. Server settles at that multiplier if it is still below the crash point. `0` / empty disables. |

## Cash-out vs crash (economy)

| Outcome | Formula | Balance effect |
|---------|---------|----------------|
| Cash-out | `payout = floor(wager * multiplier * PlayerReturnFactor)` | Wager already deducted; credit `payout`. `netDelta = payout - wager`. |
| Crash (no prior cash-out) | - | Wager already deducted; no refund. `payout = 0`, `netDelta = -wager`. |

### RTP

- `TargetRTP` (e.g. `1.05`) is the design target expected return per chip wagered over many rounds.
- `PlayerReturnFactor` scales cash-out payouts and is the primary lever toward that target; the crash roll distribution also affects realized EV.
- Long-term, players are rewarded for volume (RTP > 100%). Short-term variance (busts) still drains sessions.

### Daily earn cap

`Config.DAILY_EARN_CAP` applies to earn-only `CurrencyService.awardChips` (e.g. lobby job). Wager payouts use `creditPayout` and are **not** clipped by the cap - the stake was already removed, and clipping the return would break settlement and RTP. Net profit from wagering still increments `chipsEarnedToday` for display.

## Key `Config.ROCKET_RUN` constants

| Key | Role |
|-----|------|
| `GrowthRate` | Exponential multiplier growth |
| `MinCrashMultiplier` / `MaxCrashMultiplier` | Crash roll bounds (skewed RNG) |
| `CountdownSeconds` | Launch countdown length |
| `IntermissionSeconds` | Delay after crash before reset |
| `DefaultWager` / `MinWager` / `MaxWager` | Loadout stake clamps |
| `TargetRTP` | Design expected return per wager (> 1.0) |
| `PlayerReturnFactor` | Cash-out payout scale factor |
| `CameraOffset` | Client follow-cam offset |
| Rocket motion fields | World presentation / crash tell only |

Full table lives in `src/shared/Config.luau`.

## File map

| Path | Role |
|------|------|
| `src/server/games/RocketRun/init.luau` | Round loop, rocket, settlement, remotes |
| `src/client/controllers/RocketRunController.luau` | Client remotes, camera, predicted multiplier |
| `src/client/ui/RocketRunHud.luau` | Loadout UI, graph, cash-out / leave / mute |
| `src/server/services/CurrencyService.luau` | Deduct / credit / earn chip APIs |
| `src/shared/Config.luau` | `ROCKET_RUN` tuning |
| `src/shared/Types.luau` | Loadout / round / result payloads |
| `src/shared/Remotes.luau` | Rocket Run event names |
| `src/map/RocketRunArena.model.json` | Arena, rocket, telemetry board |

## Verify (manual)

- Wager 10, cash out @ 2x, `PlayerReturnFactor = 1.05` → `payout = 21`, `netDelta = +11`
- Wager 10, crash → lose 10 chips (`netDelta = -10`)
- Balance `<` wager → not eligible that round
