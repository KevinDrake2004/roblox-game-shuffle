--!strict
--[=[
	@class Config
	Shared game configuration constants for Shuffle Arcade.

	Soft currency supports earn grants and wager loops. Rocket Run, Plinko Points,
	and Mine Sweeper stake chips and settle with RTP > 100% (see `Config.ROCKET_RUN` /
	`Config.PLINKO` / `Config.MINE_SWEEPER`, `docs/ROCKET_RUN.md`, `docs/PLINKO.md`,
	`docs/MINES.md`). `DAILY_EARN_CAP` applies to earn-only `awardChips` paths, not
	wager payout credits.
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
	-- Jackpot / near-max Plinko bucket flash (distinct from lime mid-high hits).
	NeonGold = Color3.fromRGB(250, 204, 21),
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
	MineSweeper = true,
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
	Plinko Points tuning: per-drop wager clamps, risk tiers, and RTP.

	- `DefaultWager` / `MinWager` / `MaxWager` - stake clamps per ball drop
	- `DefaultBallCount` / `MinBallCount` / `BallDropStaggerSeconds` / `BallDropMaxReleaseSeconds` - multi-ball release timing
	- `RiskLevels` / `DefaultRiskId` - risk scale (peg rows + max jackpot ↑ as risk ↑; design RTP → 100%)
	- `BucketWeights` - documented binomial land curve for RTP math (not rolled)
	- `BucketMultipliers` - mirrors the default (medium) risk tier for convenience
	- `DropCooldownSeconds` - minimum delay between drops per player
	- Ball / peg / arena fields drive client sim + world presentation

	Payout is `floor(wager * risk.bucketMultipliers[landed])`. Multipliers stay integer
	so wager=1 does not silently zero sub-1x buckets.

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
	DefaultRiskId = "medium",
	-- Risk scale: board size (pegRows) grows with risk; RTP approaches 100% at High.
	-- Buckets = pegRows + 1. Exact binomial RTP = Σ C(pegRows,k)·m[k] / 2^pegRows:
	--   low 8 rows = 354/256 = 177/128 ≈ 1.383, medium 12 = 4916/4096 = 1229/1024 ≈ 1.200,
	--   high 16 = 65536/65536 = 1.000. (Prior tables were ~1.203 / ~1.150 / ~1.060.)
	-- Each tier carries its own Galton physics profile (ball/peg size, leave speed, drag).
	-- Peg/bucket layout still scales from rail width; sim tunables do NOT share one formula.
	RiskLevels = {
		{
			id = "low",
			displayName = "Low",
			targetRTP = 1.38,
			maxBallCount = 200,
			maxMultiplier = 17,
			pegRows = 8,
			bucketMultipliers = { 17, 6, 2, 1, 0, 1, 2, 6, 17 },
			-- Wide pitch (~4.4 stud): larger ball/pegs, strong leave X, light mid-board drag.
			physics = {
				ballRadius = 1.0,
				pegSize = 1.35,
				leaveSpeed = 6.4,
				leaveAngleDeg = 34,
				reflectBlend = 0.08,
				horizontalDrag = 0.55,
				startSpeedX = 1.45,
				startSpread = 0.55,
				pegHitCooldown = 0.14,
				apexNormalX = 0.18,
				maxUpSpeed = 6.5,
				railNearDamp = 2.2,
			},
		},
		{
			id = "medium",
			displayName = "Medium",
			targetRTP = 1.20,
			maxBallCount = 100,
			maxMultiplier = 121,
			pegRows = 12,
			bucketMultipliers = { 121, 38, 11, 3, 1, 0, 0, 0, 1, 3, 11, 38, 121 },
			-- Mid pitch (~3.1 stud): reference Galton feel.
			physics = {
				ballRadius = 0.72,
				pegSize = 0.98,
				leaveSpeed = 5.5,
				leaveAngleDeg = 32,
				reflectBlend = 0.09,
				horizontalDrag = 0.65,
				startSpeedX = 1.15,
				startSpread = 0.38,
				pegHitCooldown = 0.12,
				apexNormalX = 0.18,
				maxUpSpeed = 6.0,
				railNearDamp = 2.4,
			},
		},
		{
			id = "high",
			displayName = "High",
			targetRTP = 1.00,
			maxBallCount = 25,
			maxMultiplier = 316,
			pegRows = 16,
			bucketMultipliers = { 316, 88, 27, 10, 3, 2, 1, 0, 0, 0, 1, 2, 3, 10, 27, 88, 316 },
			-- Tight pitch (~2.35 stud): smaller ball/pegs, careful leave, light drag so X survives.
			physics = {
				ballRadius = 0.52,
				pegSize = 0.70,
				leaveSpeed = 4.4,
				leaveAngleDeg = 30,
				reflectBlend = 0.10,
				horizontalDrag = 0.75,
				startSpeedX = 0.80,
				startSpread = 0.24,
				pegHitCooldown = 0.12,
				apexNormalX = 0.16,
				maxUpSpeed = 5.5,
				railNearDamp = 2.8,
			},
		},
	},
	-- Convenience mirror of medium tier (fallbacks / docs).
	TargetRTP = 1.20,
	BucketMultipliers = { 121, 38, 11, 3, 1, 0, 0, 0, 1, 3, 11, 38, 121 },
	DropCooldownSeconds = 0.75,
	-- Reference weights for the default medium row count (C(12,k)); per-risk uses C(pegRows,k).
	BucketWeights = { 1, 12, 66, 220, 495, 792, 924, 792, 495, 220, 66, 12, 1 },
	-- World / camera (east of Rocket Run at 0, 5, -140 — ~90 studs apart)
	-- Larger playfield + closer camera so pegs/balls stay easy to track on all risk tiers.
	ArenaOrigin = Vector3.new(90, 5, -140),
	-- Head-on board cam: offset is along +Z (toward spawn), no downward pitch.
	CameraOffset = Vector3.new(0, 0, 36),
	-- Default Galton spacing; local boards may scale X/Y to fit the rails.
	PegRows = 12,
	PegSpacingX = 2.8,
	PegSpacingY = 2.4,
	PegLayoutVersion = 4,
	-- Client gravity sim (free path; Galton pegs create center-biased lands).
	-- Per-risk ball/peg/leave tunables live on RiskLevels[].physics; globals below are fallbacks only.
	BallRadius = 0.72,
	BallGravity = 62,
	BallBounce = 0.42,
	BallRailBounce = 0.18,
	BallRailNearDamp = 2.4,
	BallMaxSimSeconds = 8,
	BallPegHitCooldown = 0.12,
	-- Light air drag so leave speed carries to the next row without rail flings.
	BallHorizontalDrag = 0.65,
	BallStartSpeedX = 1.1,
	BallMaxSpeed = 42,
	BallSubsteps = 3,
	-- Post-contact leave: ~half peg spacing / fall time between rows → Galton ±1 step.
	BallPegLeaveSpeed = 5.5,
	BallPegLeaveAngleDeg = 32,
	-- |normal.X| below this → unstable apex; coin-flip L/R.
	BallPegApexNormalX = 0.18,
	-- Blend of elastic reflect (visual) vs roll-off leave velocity (distribution).
	BallPegReflectBlend = 0.09,
	BallPegMaxUpSpeed = 6,
	LandReportTimeoutSeconds = 9,
}

type PlinkoPhysicsProfile = {
	ballRadius: number,
	pegSize: number,
	leaveSpeed: number,
	leaveAngleDeg: number,
	reflectBlend: number,
	horizontalDrag: number,
	startSpeedX: number,
	startSpread: number,
	pegHitCooldown: number,
	apexNormalX: number,
	maxUpSpeed: number,
	railNearDamp: number,
}

type PlinkoRiskLevel = {
	id: string,
	displayName: string,
	targetRTP: number,
	maxBallCount: number,
	maxMultiplier: number,
	pegRows: number,
	bucketMultipliers: { number },
	physics: PlinkoPhysicsProfile,
}

--[=[
	Resolve a Plinko risk tier by id (falls back to DefaultRiskId).
]=]
function Config.getPlinkoRisk(riskId: unknown): PlinkoRiskLevel
	local levels = Config.PLINKO.RiskLevels
	local wanted = if typeof(riskId) == "string" then riskId else Config.PLINKO.DefaultRiskId
	for _, level in levels do
		if level.id == wanted then
			return level
		end
	end
	for _, level in levels do
		if level.id == Config.PLINKO.DefaultRiskId then
			return level
		end
	end
	return levels[1]
end

--[=[
	Mine Sweeper Arcade tuning: 5x5 grid, mine count, wager clamps, RTP.

	- `GridSize` - side length (tiles = GridSize^2)
	- `MinMines` / `MaxMines` / `DefaultMines` - mines placed per round
	- `DefaultWager` / `MinWager` / `MaxWager` - stake clamps
	- `TargetRTP` - design expected return per chip wagered (> 1.0)
	- `PlayerReturnFactor` - scales cash-out: floor(wager * multiplier * factor)
	- Multiplier after r safe reveals with m mines on n tiles:
	  `∏_{i=0}^{r-1} (n - i) / (n - m - i)` (conditional survival odds), then × factor
	- Arena / camera fields drive world presentation only

	@prop MINE_SWEEPER table
	@within Config
]=]
Config.MINE_SWEEPER = {
	GridSize = 5,
	MinMines = 1,
	MaxMines = 24,
	DefaultMines = 3,
	DefaultWager = 10,
	MinWager = 1,
	MaxWager = 50,
	-- Target expected return per wagered chip (> 1.0 = player edge over volume).
	TargetRTP = 1.05,
	-- Applied on cash-out: payout = floor(wager * multiplier * PlayerReturnFactor).
	PlayerReturnFactor = 1.05,
	-- World / camera (west of Rocket Run at 0, 5, -140 - ~90 studs apart)
	ArenaOrigin = Vector3.new(-90, 5, -140),
	-- Elevated board cam: look down from spawn side toward the grid.
	CameraOffset = Vector3.new(0, 22, 28),
}

--[=[
	Fair cash-out multiplier after `revealedCount` safe gems with `mineCount` mines
	on an `n = GridSize^2` board (Shuffle/Stake-style conditional survival odds).

	`mult = ∏_{i=0}^{r-1} (n - i) / (n - m - i)`. Returns 1 when r < 1.
]=]
function Config.mineSweeperMultiplier(revealedCount: number, mineCount: number): number
	local cfg = Config.MINE_SWEEPER
	local n = cfg.GridSize * cfg.GridSize
	local m = math.clamp(math.floor(mineCount), cfg.MinMines, cfg.MaxMines)
	local r = math.floor(revealedCount)
	if r < 1 then
		return 1
	end
	local maxSafe = n - m
	if r > maxSafe then
		r = maxSafe
	end
	local mult = 1
	for i = 0, r - 1 do
		local denom = n - m - i
		if denom <= 0 then
			break
		end
		mult *= (n - i) / denom
	end
	return mult
end

Config.JOB = {
	Reward = 15,
	MinReadyDelay = 1.5,
	MaxReadyDelay = 3.5,
	ReactionWindow = 1.25,
	Cooldown = 4,
}

return Config
