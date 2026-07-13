# Plinko Points - Dev Log

Session notes for `feature/plinko-dev`. Flaws and successes as we iterate.

## 2026-07-13 - Free physics + Galton / 105% RTP

### Successes

- Ball path is no longer a bezier / soft-bias toward a pre-rolled bucket.
- Flow is deduct → free client gravity sim → report landed bucket → server settle.
- Multiplier labels and balls are local-only (not visible from lobby / to other players).
- Peg board rebuilt as a Galton layout (row `r` has `r+1` pegs → 9 slots).
- Multipliers retuned so `E[mult]` under binomial weights is **exactly 105%**; removed Plinko `PlayerReturnFactor` (RTP is the curve × multipliers only).
- Bounce feel: soft peg deflects (low restitution + side/up damp) so hits read, but the ball keeps falling instead of pinballing to the rails.

- Multi-ball: pick ball count (1–10); balls release staggered, no ball-ball collision (peg-only).

### Flaws / follow-ups

- Land report is still client-trusted (soft-currency alpha). A cheater could lie about the bucket; later: server-side seed replay or hash commit.
- Realized land histogram may not perfectly match `C(8,k)` until more playtest; adjust peg spacing / bounce if edges stay hot.
- `floor(wager * mult)` slightly lowers live RTP on small wagers.
- Still a custom 2D sim (not Roblox Workspace physics); close visually, not a full rigid-body solver.
- Old Studio sessions may keep stale pegs until `PegLayoutVersion` rebuild runs (restart server / rejoin after sync).
- Auto-drop / multi-ball / risk tiers still not started.
- No automated Monte Carlo yet to confirm live RTP vs design 105%.

### Playtest focus

1. ~30 drops: lands should cluster near center; 20x edges rare.
2. No mid-air curve into a chosen slot.
3. Labels only inside Plinko; other players do not see your ball.
