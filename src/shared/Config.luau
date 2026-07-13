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
	- `BucketMultipliers` - payout multipliers left→right (edges high, center bust)
	- `BucketWeights` - relative land probabilities (binomial-style center bias)
	- `TargetRTP` - design expected return per chip wagered (> 1.0)
	- `PlayerReturnFactor` - scales payout: floor(wager * multiplier * factor)
	- `DropCooldownSeconds` - minimum delay between drops per player
	- Arena / camera fields drive world presentation only (east of Rocket Run)

	Expected raw multiplier ≈ 1.0 from weights × multipliers; with
	`PlayerReturnFactor = 1.05`, realized EV ≈ TargetRTP over many drops.

	@prop PLINKO table
	@within Config
]=]
Config.PLINKO = {
	DefaultWager = 10,
	MinWager = 1,
	MaxWager = 50,
	-- Target expected return per wagered chip (> 1.0 = player edge over volume).
	TargetRTP = 1.05,
	-- Applied on settle: payout = floor(wager * bucketMultiplier * PlayerReturnFactor).
	PlayerReturnFactor = 1.05,
	DropCooldownSeconds = 0.75,
	-- Symmetric Shuffle-style board: edge jackpots, center 0x bust.
	-- Weights are binomial C(8, k); E[multiplier] ≈ 1.006 before PlayerReturnFactor.
	BucketMultipliers = { 10, 4, 1.5, 0.8, 0, 0.8, 1.5, 4, 10 },
	BucketWeights = { 1, 8, 28, 56, 70, 56, 28, 8, 1 },
	-- World / camera (east of Rocket Run at 0, 5, -140 — ~90 studs apart)
	ArenaOrigin = Vector3.new(90, 5, -140),
	CameraOffset = Vector3.new(0, 4, 28),
	PegRows = 8,
	BallDropDuration = 1.15,
}

Config.JOB = {
	Reward = 15,
	MinReadyDelay = 1.5,
	MaxReadyDelay = 3.5,
	ReactionWindow = 1.25,
	Cooldown = 4,
}

return Config
