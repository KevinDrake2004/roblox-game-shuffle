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
	-- Buckets = pegRows + 1. E[mult] under binomial C(pegRows, k):
	--   low 8 rows ≈ 1.203, medium 12 rows ≈ 1.150, high 16 rows ≈ 1.060.
	RiskLevels = {
		{
			id = "low",
			displayName = "Low",
			targetRTP = 1.20,
			maxBallCount = 200,
			maxMultiplier = 10,
			pegRows = 8,
			bucketMultipliers = { 10, 4, 2, 1, 0, 1, 2, 4, 10 },
		},
		{
			id = "medium",
			displayName = "Medium",
			targetRTP = 1.15,
			maxBallCount = 100,
			maxMultiplier = 120,
			pegRows = 12,
			bucketMultipliers = { 120, 35, 10, 3, 1, 0, 0, 0, 1, 3, 10, 35, 120 },
		},
		{
			id = "high",
			displayName = "High",
			targetRTP = 1.06,
			maxBallCount = 25,
			maxMultiplier = 320,
			pegRows = 16,
			bucketMultipliers = { 320, 90, 28, 10, 4, 2, 1, 0, 0, 0, 1, 2, 4, 10, 28, 90, 320 },
		},
	},
	-- Convenience mirror of medium tier (fallbacks / docs).
	TargetRTP = 1.15,
	BucketMultipliers = { 120, 35, 10, 3, 1, 0, 0, 0, 1, 3, 10, 35, 120 },
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
	-- Each peg hit: hit-offset L/R + characteristic leave velocity (not over-damped pure fall).
	-- BallRadius is the *max* cap; live size scales down with peg channel on dense boards.
	BallRadius = 0.85,
	BallGravity = 62,
	BallBounce = 0.42,
	BallRailBounce = 0.18,
	BallRailNearDamp = 2.4,
	BallMaxSimSeconds = 8,
	BallPegHitCooldown = 0.05,
	-- Light air drag so leave speed carries to the next row without rail flings.
	BallHorizontalDrag = 1.35,
	BallStartSpeedX = 1.1,
	BallMaxSpeed = 42,
	BallSubsteps = 3,
	-- Post-contact leave: ~half peg spacing / fall time between rows → Galton ±1 step.
	BallPegLeaveSpeed = 5.5,
	BallPegLeaveAngleDeg = 30,
	-- |normal.X| below this → unstable apex; coin-flip L/R.
	BallPegApexNormalX = 0.14,
	-- Blend of elastic reflect (visual) vs roll-off leave velocity (distribution).
	BallPegReflectBlend = 0.18,
	BallPegMaxUpSpeed = 6,
	LandReportTimeoutSeconds = 9,
}

type PlinkoRiskLevel = {
	id: string,
	displayName: string,
	targetRTP: number,
	maxBallCount: number,
	maxMultiplier: number,
	pegRows: number,
	bucketMultipliers: { number },
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

Config.JOB = {
	Reward = 15,
	MinReadyDelay = 1.5,
	MaxReadyDelay = 3.5,
	ReactionWindow = 1.25,
	Cooldown = 4,
}

return Config
