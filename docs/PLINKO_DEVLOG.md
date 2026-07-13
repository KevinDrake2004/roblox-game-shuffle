# Plinko Points - Dev Log

Session notes for `feature/plinko-dev`. Flaws and successes as we iterate.

## 2026-07-13 - Risk scale (Low / Medium / High)

### Goal

Let players pick a risk profile that sets max jackpot, design RTP, and ball cap.

### Design

| Risk | Max mult | Design RTP | Ball cap |
|------|----------|------------|----------|
| Low | 10x | ~148% | 200 |
| Medium (default) | 26x | ~139% | 100 |
| High | 60x | 100% | 25 |

Higher risk → RTP approaches 100% with bigger edges; lower risk → smaller jackpots,
gentler curve, higher RTP, higher ball cap. Bucket labels refresh when risk is Applied.

## 2026-07-13 - Wager=1 floor was killing RTP (not ball speed)

### Flaw

Burst release only changed stagger / balls-per-wave - **not** fall physics. But
`0.2x` / `0.85x` / `1.8x` with `floor(wager * mult)` at wager `1` paid `0` / `0` / `1`,
so effective RTP ≈ **73%**. Three bankrupt 100-ball runs at 1 chip each matched that.

### Fix

Integer multipliers `{ 26, 5, 2, 1, 0, 1, 2, 5, 26 }` → `E[mult] = 356/256 ≈ 139%`
even at wager 1. Release timing stays burst/stagger only (no sim velocity changes).

### Successes

- Low-wager multi-ball no longer secretly house-edged by integer truncation.

## 2026-07-13 - Fast burst release for large multi-ball

### Flaw

Fixed `0.3s` per-ball stagger made big volleys feel awful (e.g. 131 balls ≈ 40s
just to finish releasing).

### Fix

Release timing scales with count: preferred `0.05s` between waves, but burst size
grows so the whole volley starts within `BallDropMaxReleaseSeconds` (1.5s).
Example: ~131 balls → ~5 per wave across ~27 waves ≈ 1.3s of release.

### Successes

- Small counts still cascade; huge counts dump a satisfying stream quickly.

## 2026-07-13 - UI: bucket labels, title contrast, uncapped balls

### Flaw

1. Multiplier billboards floated above the cups and did not read as sitting on them.
2. "PLINKO POINTS" title used pale text + purple stroke that melted into the board.
3. Ball count was hard-capped at 10 even when the player could afford more.

### Fix

1. Local multiplier labels are now `SurfaceGui` plates on each bucket face (short text,
   dark plate, black stroke) so they fit the boxes.
2. Title sign rebuilds with dark plate, lime text, white outline, `LightInfluence = 0`.
3. Removed `MaxBallCount`; only `MinBallCount` + `wager * balls ≤ balance` gate drops.

### Successes

- Labels align with the cups; title is readable against the purple board.
- Players can drop as many balls as their chip balance allows.

## 2026-07-13 - Softer payouts + pinned buckets

### Flaw

1. Design 105% RTP with a hard center `0x` still felt punishing in short sessions
   (easy to dump ~30 chips to variance).
2. Landing FX tweened bucket `Size`, which scales from center and stacked badly under
   multi-ball hits - boxes visibly drifted / "moved" after lands.

### Fix

1. Raised `BucketMultipliers` and `TargetRTP` (~134% under `C(8,k)`). Center is now
   `0.2x` (soft return) instead of a total wipe; near-center and mid buckets bumped too.
2. Land glow is color + light only. Buckets capture a home CFrame/Size once, stay
   `Anchored` / `CanCollide = false`, and get re-pinned after every flash.

### Successes

- Short sessions should feel less brutal while edges stay exciting (26x).
- Bottom boxes stay tethered in place across multi-ball volleys.

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

- Multi-ball: pick any affordable ball count; balls release staggered, no ball-ball collision (peg-only).

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
