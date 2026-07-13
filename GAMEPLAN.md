# Shuffle Arcade — Game Plan

Roblox arcade hub inspired by [Shuffle.com](https://shuffle.com). Soft currency (chips) with **wager loops** on live games; roadmap games below remain unbuilt.

## Economy (current)

- Players **wager chips** to play; losing rounds deduct the stake. Wins credit a payout (stake already removed).
- **RTP > 100%** per game (e.g. Rocket Run / Mines `TargetRTP = 1.05`, Plinko risk tiers) so long-term play is rewarding; short-term busts still hurt.
- Server validates balance, RNG, and settlement. See [`docs/ROCKET_RUN.md`](docs/ROCKET_RUN.md), [`docs/PLINKO.md`](docs/PLINKO.md), [`docs/MINES.md`](docs/MINES.md).
- Daily earn cap: `Config.DAILY_EARN_CAP` applies to earn-only `awardChips` (jobs). Wager payouts are not clipped by the cap.
- Timing job (`JobService`) remains an earn-only chip source.

## Mini-Game Roadmap

| Shuffle Original | Roblox Name | Status / notes |
|------------------|-------------|----------------|
| Crash | **Rocket Run** | **Shipped (wager + RTP).** Shared server rocket; wager deduct on eligibility; cash-out / crash settle. See `docs/ROCKET_RUN.md`. |
| Plinko | **Plinko Points** | **Shipped (MVP).** Risk tiers, multi-ball, settle, local physics; see `docs/PLINKO.md`. |
| Mines | **Mine Sweeper Arcade** | **Shipped (MVP).** 5×5 grid, wager + cash-out, RTP > 100%; see `docs/MINES.md`. |
| Dice | **Dice Duel** | Unbuilt |
| Wheel | **Prize Wheel** | Unbuilt |
| Limbo | **Limbo Jump** | Unbuilt |
| HiLo | **Card Climb** | Unbuilt |

## Build Phases

### Done

- Dev environment, lobby services, currency deduct / credit payout APIs
- Rocket Run (shared rounds, wager loadout, telemetry, camera views)
- Plinko Points (isolated arena, per-drop wager, risk tiers, RTP)
- Mine Sweeper Arcade (isolated arena, reveal / cash-out, RTP)
- Skill timing job for chip earn

### In progress

- **Casino shell** - Hard Rock-style building with physical game rooms inside (`feature/casino-shell`). See [`docs/CASINO.md`](docs/CASINO.md). Doorways start sessions; arenas sit in-building.

### Next

- Casino shell phase 2 (richer props, auto-join volumes, rocket atrium polish)
- Leaderboards / further hub polish
- Optional chip sinks (cosmetics, VIP) to offset RTP inflation

### Later

- Cosmetics, VIP, game passes

## Architecture

Each live game validates client requests on the server. Typical wager settlement:

`eligible` / stake deducted → cash-out → `creditPayout(...)`  
or bust / crash / mine → stake kept by the round (`netDelta` negative).

Hub entry: spawn in `Workspace.Lobby` → walk casino floor → game-room doorway → session `join`. Leave returns to that room's corridor `LeavePosition`.

## Monetization

Cosmetics and VIP. No pay-to-win edge on outcomes.
