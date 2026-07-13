# Plinko Points - Dev Log

Session notes for `feature/plinko-dev`. Flaws and successes as we iterate.

## 2026-07-13 - Peg leave velocity restores Galton spread

### Flaw

After bounce was toned down to stop rail flings, balls lost meaningful horizontal motion.
`BallPegSideDamp` / upward kill / forced downward rewrite left nearly pure vertical falls,
so almost every land was the center `0x` bucket.

### Fix

Reworked peg response around Galton/bean-machine math:

1. Separate along contact normal.
2. Choose leave side from hit offset (`normal.X`); coin-flip only at the unstable apex.
3. Set a characteristic roll-off leave velocity (angle from vertical ≈ half peg spacing /
   fall time between rows) so each row is roughly an independent ±1 step.
4. Blend a small elastic reflection for bounce feel; cap upward speed so rails stay calm.
5. Dropped the old side-damp that erased lateral velocity after every hit.

Offline Monte Carlo (~5k drops) with the tuned leave params matches `C(8,k)` closely
(center ~27%, edges rare). Still no ball-ball collision.

### Successes

- Lands spread again with center bias instead of always `0x`.
- Horizontal motion comes from peg collisions, not a soft bucket bias.
- Bounce stays controlled (leave speed ~5.6, max up 5) rather than pinball flings.

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
- Auto-drop and risk tiers still not started (multi-ball is in).
- No automated Monte Carlo yet in-repo to confirm live RTP vs design 105%.

### Playtest focus

1. ~30 single drops: lands should cluster near center; 24x edges rare.
2. Paths should zigzag L/R off pegs - not fall straight into the middle every time.
3. No mid-air curve into a chosen slot.
4. Labels only inside Plinko; other players do not see your ball.
5. Multi-ball (e.g. 5): stagger release, no ball-ball bounce, stake = wager×count, leave mid-volley refunds unsettled.
