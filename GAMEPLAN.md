# Shuffle Arcade — Game Plan

Roblox arcade hub inspired by [Shuffle.com](https://shuffle.com). Soft currency (chips) with **wager loops** on live games; roadmap games below remain unbuilt.

## Economy (current)

- Players **wager chips** to play; losing rounds deduct the stake. Wins credit a payout (stake already removed).
- **RTP > 100%** per game (e.g. Rocket Run `TargetRTP = 1.05`) so long-term play is rewarding; short-term busts still hurt.
- Server validates balance, RNG, and settlement. See [`docs/ROCKET_RUN.md`](docs/ROCKET_RUN.md).
- Daily earn cap: `Config.DAILY_EARN_CAP` applies to earn-only `awardChips` (jobs). Wager payouts are not clipped by the cap.
- Timing job (`JobService`) remains an earn-only chip source.

## Mini-Game Roadmap

| Shuffle Original | Roblox Name | Status / notes |
|------------------|-------------|----------------|
| Crash | **Rocket Run** | **Shipped (wager + RTP).** Shared server rocket; wager deduct on eligibility; cash-out / crash settle. See `docs/ROCKET_RUN.md`. |
| Plinko | **Plinko Points** | **Shipped (wager + RTP).** Per-drop stake; weighted buckets; see `docs/PLINKO.md`. |
| Mines | **Mine Sweeper Arcade** | Portal stub / coming soon |
| Dice | **Dice Duel** | Unbuilt |
| Wheel | **Prize Wheel** | Unbuilt |
| Limbo | **Limbo Jump** | Unbuilt |
| HiLo | **Card Climb** | Unbuilt |

## Build Phases

### Done

- Dev environment, lobby, services, Rocket Run (shared rounds, wager loadout, telemetry, camera views)
- Plinko Points (isolated arena, per-drop wager, weighted buckets, RTP > 100%)
- Skill timing job for chip earn
- Currency deduct / credit payout APIs for wager games

### Next

- Mines (wager + RTP patterns)
- Leaderboards / hub polish
- Optional chip sinks (cosmetics, VIP) to offset RTP inflation

### Later

- Cosmetics, VIP, game passes

## Architecture

Each live game validates client requests on the server. Rocket Run settlement:

`eligible` (wager deducted) → cash-out → `creditPayout(floor(wager * multiplier * PlayerReturnFactor))`  
or crash → `netDelta = -wager` (no refund).

## Monetization

Cosmetics and VIP. No pay-to-win edge on outcomes.
