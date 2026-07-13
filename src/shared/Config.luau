--!strict
--[=[
	@class Config
	Shared game configuration constants for Shuffle Arcade.

	Soft currency supports earn grants and wager loops. Rocket Run and Plinko Points
	stake chips and settle with RTP > 100% (see `Config.ROCKET_RUN` /
	`Config.PLINKO`, `docs/ROCKET_RUN.md`, `docs/PLINKO.md`). `DAILY_EARN_CAP`
	applies to earn-only `awardChips` paths, not wager payout credits.
]=]
local Types = require(script.Parent.Types)

type PortalConfig = Types.PortalConfig
type GameId = Types.GameId

local Config = {}

Config.GAME_NAME = "Shuffle Arcade"
Config.STARTING_CHIPS = 100

-- Daily earn cap (chips) for awardChips only. VIP may raise this later via game pass.
-- Wager payouts are not clipped by this cap (see CurrencyService).
Config.DAILY_EARN_CAP = 5_000

Config.COLORS = {
	Background = Color3.fromRGB(12, 8, 24),
	Floor = Color3.fromRGB(22, 14, 40),
	NeonPurple = Color3.fromRGB(168, 85, 247),
	NeonCyan = Color3.fromRGB(34, 211, 238),
	NeonMagenta = Color3.fromRGB(236, 72, 153),
	NeonLime = Color3.fromRGB(163, 230, 53),
	Text = Color3.fromRGB(248, 250, 252),
}

Config.LOBBY = {
	FloorSize = Vector3.new(80, 1, 80),
	SpawnPosition = Vector3.new(0, 3, 20),
	Ambient = Color3.fromRGB(128, 118, 150),
	OutdoorAmbient = Color3.fromRGB(105, 100, 125),
	FogColor = Color3.fromRGB(95, 90, 120),
	FogEnd = 600,
	ClockTime = 15,
	Brightness = 3,
	ExposureCompensation = 0.25,
}

local portals: { PortalConfig } = {
	{
		id = "RocketRun",
		displayName = "Rocket Run",
		position = Vector3.new(-24, 3, -28),
		accentColor = Config.COLORS.NeonCyan,
	},
	{
		id = "PlinkoPoints",
		displayName = "Plinko Points",
		position = Vector3.new(0, 3, -28),
		accentColor = Config.COLORS.NeonPurple,
	},
	{
		id = "MineSweeper",
		displayName = "Mine Sweeper Arcade",
		position = Vector3.new(24, 3, -28),
		accentColor = Config.COLORS.NeonMagenta,
	},
}
Config.PORTALS = portals

local playableGames: { [GameId]: boolean } = {
	RocketRun = true,
	PlinkoPoints = true,
	MineSweeper = false,
}
Config.PLAYABLE_GAMES = playableGames

--[=[
	Rocket Run tuning: shared round timing, wager clamps, RTP, and rocket motion.

	- `GrowthRate` - multiplier = exp(GrowthRate * elapsedSeconds)
	- `MinCrashMultiplier` / `MaxCrashMultiplier` - server crash roll bounds
	- `CountdownSeconds` / `IntermissionSeconds` - round cadence
	- `DefaultWager` / `MinWager` / `MaxWager` - loadout stake clamps
	- `TargetRTP` - design target expected return per chip wagered (> 1.0)
	- `PlayerReturnFactor` - scales cash-out payout: floor(wager * multiplier * factor)
	- Arena / rocket / camera fields drive world presentation only

	@prop ROCKET_RUN table
	@within Config
]=]
Config.ROCKET_RUN = {
	GrowthRate = 0.12,
	MinCrashMultiplier = 1.0,
	MaxCrashMultiplier = 25,
	CountdownSeconds = 5,
	IntermissionSeconds = 2.5,
	DefaultWager = 10,
	MinWager = 1,
	MaxWager = 50,
	-- Target expected return per wagered chip (> 1.0 = player edge over volume).
	TargetRTP = 1.05,
	-- Applied on cash-out: payout = floor(wager * multiplier * PlayerReturnFactor).
	-- Primary lever toward TargetRTP; crash distribution also affects realized EV.
	PlayerReturnFactor = 1.05,
	-- World / camera
	ArenaOrigin = Vector3.new(0, 5, -140),
	RocketHomePosition = Vector3.new(0, 12, -148),
	RocketLaunchSpeed = 22,
	RocketVerticalAcceleration = 3.5,
	RocketHeightPerLog = 52,
	RocketMaxHorizontalDistance = 36,
	RocketCrashTellStart = 0.72,
	RocketSway = 3,
	RocketSwayFrequency = 0.4,
	CameraOffset = Vector3.new(28, 12, 22),
}

--[=[
	Plinko Points tuning: per-drop wager clamps, bucket payouts, and RTP.

	- `DefaultWager` / `MinWager` / `MaxWager` - stake clamps per ball drop
	- `DefaultBallCount` / `MinBallCount` / `BallDropStaggerSeconds` / `BallDropMaxReleaseSeconds` - multi-ball drops (no hard max; balance gates total stake; large volleys burst within a short release window)
	- `BucketMultipliers` - payout multipliers left→right (edges high, soft center)
	- `BucketWeights` - documented binomial land curve for RTP math (not rolled)
	- `TargetRTP` - design aim only (~1.39); achieved by tuning multipliers vs the land curve
	- `DropCooldownSeconds` - minimum delay between drops per player
	- `BallRadius` / `BallGravity` / `BallBounce` - client gravity sim feel
	- `BallPegLeaveSpeed` / `BallPegLeaveAngleDeg` / `BallPegApexNormalX` / `BallPegReflectBlend` / `BallPegMaxUpSpeed` - peg collision leave response (Galton L/R)
	- `BallMaxSimSeconds` / `BallPegHitCooldown` / `BallHorizontalDrag` / `BallStartSpeedX` / `BallMaxSpeed` / `BallSubsteps` - Galton sim feel
	- `PegRows` / `PegSpacingX` / `PegSpacingY` / `PegLayoutVersion` - Galton board layout
	- Arena / camera fields drive world presentation only (east of Rocket Run)

	Payout is `floor(wager * BucketMultipliers[landed])` with no extra scale factor.
	Keep multipliers integer (or ≥1 when fractional) so low wagers do not silently zero out RTP.

	@prop PLINKO table
	@within Config
]=]
Config.PLINKO = {
	DefaultWager = 10,
	MinWager = 1,
	MaxWager = 50,
	DefaultBallCount = 1,
	MinBallCount = 1,
	-- Preferred gap between release waves. Large volleys raise burst size so the
	-- whole release finishes within BallDropMaxReleaseSeconds (not N × stagger).
	BallDropStaggerSeconds = 0.05,
	BallDropMaxReleaseSeconds = 1.5,
	-- Design aim: E[BucketMultipliers] under BucketWeights ≈ TargetRTP (no extra factor).
	-- Integer multipliers only: payout is floor(wager * mult), so fractional mults at
	-- wager=1 were paying 0 and crashed live RTP to ~73% (felt like "always bankrupt").
	TargetRTP = 1.39,
	DropCooldownSeconds = 0.75,
	-- Symmetric board: rare edge jackpots, common center bust / near-push.
	-- Under binomial C(8,k) weights: E[multiplier] = 356/256 = 1.390625.
	BucketMultipliers = { 26, 5, 2, 1, 0, 1, 2, 5, 26 },
	BucketWeights = { 1, 8, 28, 56, 70, 56, 28, 8, 1 },
	-- World / camera (east of Rocket Run at 0, 5, -140 — ~90 studs apart)
	ArenaOrigin = Vector3.new(90, 5, -140),
	CameraOffset = Vector3.new(0, 4, 28),
	-- Galton board: PegRows decision rows → PegRows+1 buckets (keep 8 → 9).
	PegRows = 8,
	PegSpacingX = 2.6,
	PegSpacingY = 2.35,
	PegLayoutVersion = 2,
	-- Client gravity sim (free path; Galton pegs create center-biased lands).
	-- Each peg hit: hit-offset L/R + characteristic leave velocity (not over-damped pure fall).
	BallRadius = 0.5,
	BallGravity = 55,
	BallBounce = 0.42,
	BallMaxSimSeconds = 8,
	BallPegHitCooldown = 0.05,
	-- Light air drag so leave speed carries to the next row without rail flings.
	BallHorizontalDrag = 1.15,
	BallStartSpeedX = 1.0,
	BallMaxSpeed = 40,
	BallSubsteps = 3,
	-- Post-contact leave: ~half peg spacing / fall time between rows → Galton ±1 step.
	BallPegLeaveSpeed = 5.6,
	BallPegLeaveAngleDeg = 33,
	-- |normal.X| below this → unstable apex; coin-flip L/R.
	BallPegApexNormalX = 0.12,
	-- Blend of elastic reflect (visual) vs roll-off leave velocity (distribution).
	BallPegReflectBlend = 0.25,
	BallPegMaxUpSpeed = 5,
	LandReportTimeoutSeconds = 9,
}

Config.JOB = {
	Reward = 15,
	MinReadyDelay = 1.5,
	MaxReadyDelay = 3.5,
	ReactionWindow = 1.25,
	Cooldown = 4,
}

return Config
