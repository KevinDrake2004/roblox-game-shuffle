--!strict
--[=[
	@class Types
	Shared type definitions for Shuffle Arcade.

	Rocket Run payloads describe wager settlement: stake deducted on eligibility;
	cash-out credits `payout`; crash leaves the stake lost (`netDelta = -wager`).
	Plinko Points deducts per drop and credits `floor(wager * bucketMultiplier)`.
]=]
local Types = {}

export type GameId = "RocketRun" | "PlinkoPoints" | "MineSweeper"

export type PortalConfig = {
	id: GameId,
	displayName: string,
	position: Vector3,
	accentColor: Color3,
}

export type HighScores = {
	RocketRun: number,
	PlinkoPoints: number,
	MineSweeper: number,
}

export type PlayerProfile = {
	chips: number,
	chipsEarnedToday: number,
	lastDailyResetDay: number,
	highScores: HighScores,
}

export type ProfileSnapshot = {
	chips: number,
	chipsEarnedToday: number,
	dailyEarnCap: number,
	highScores: HighScores,
}

export type PortalResultPayload = {
	gameId: GameId,
	status: "enter" | "coming_soon",
	message: string,
}

export type ChipsUpdatedPayload = {
	chips: number,
	delta: number,
	source: string,
	chipsEarnedToday: number,
	dailyEarnCap: number,
}

--[=[
	Per-player Rocket Run loadout. `wager` is chips staked when the player becomes
	eligible for a round. `autoCashOut` nil disables auto settle.

	@type RocketRunLoadout {wager: number, autoCashOut: number?}
	@within Types
]=]
export type RocketRunLoadout = {
	wager: number,
	autoCashOut: number?, -- nil / 0 = disabled
}

--[=[
	Fired to arena clients when a shared round enters countdown or when a late
	joiner needs the live round snapshot.

	@type RocketRunRoundStarted {roundId: number, flyStartTime: number, growthRate: number, countdownSeconds: number, highScore: number, wager: number, autoCashOut: number?, chips: number, phase: string, eligible: boolean}
	@within Types
]=]
export type RocketRunRoundStarted = {
	roundId: number,
	flyStartTime: number,
	growthRate: number,
	countdownSeconds: number,
	highScore: number,
	wager: number,
	autoCashOut: number?,
	chips: number,
	phase: "countdown" | "flying",
	eligible: boolean,
}

--[=[
	Per-player settlement after cash-out or crash.

	- Cash-out: `payout = floor(wager * multiplier * PlayerReturnFactor)`, `netDelta = payout - wager`
	- Crash: `payout = 0`, `netDelta = -wager` (stake already deducted)

	@type RocketRunResultPayload {roundId: number, outcome: string, multiplier: number, score: number, wager: number, payout: number, netDelta: number, highScore: number, chips: number, crashMultiplier: number?}
	@within Types
]=]
export type RocketRunResultPayload = {
	roundId: number,
	outcome: "cashed_out" | "crashed",
	multiplier: number,
	score: number,
	wager: number,
	payout: number,
	netDelta: number,
	highScore: number,
	chips: number,
	crashMultiplier: number?,
}

--[=[
	Broadcast marker when any eligible player cashes out (HUD + world board).

	@type RocketRunCashOutMarker {roundId: number, userId: number, displayName: string, multiplier: number, elapsed: number}
	@within Types
]=]
export type RocketRunCashOutMarker = {
	roundId: number,
	userId: number,
	displayName: string,
	multiplier: number,
	elapsed: number,
}

export type JobPromptPayload = {
	jobId: number,
	readyAt: number,
	expiresAt: number,
}

export type JobResultPayload = {
	success: boolean,
	chipsAwarded: number,
	message: string,
}

--[=[
	Per-player Plinko loadout. Clamped to `Config.PLINKO` min/max on the server.

	@type PlinkoPointsLoadout {wager: number, ballCount: number}
	@within Types
]=]
export type PlinkoPointsLoadout = {
	wager: number,
	ballCount: number,
}

--[=[
	Fired when the player enters the Plinko arena (HUD bootstrap).

	@type PlinkoPointsJoined {wager: number, ballCount: number, chips: number, highScore: number}
	@within Types
]=]
export type PlinkoPointsJoined = {
	wager: number,
	ballCount: number,
	chips: number,
	highScore: number,
}

--[=[
	Fired after the server accepts a drop (total stake deducted). Client releases
	`dropIds` in order with stagger; each ball is an independent free physics sim.

	@type PlinkoPointsDropStarted {dropIds: {number}, wager: number, ballCount: number, staggerSeconds: number, chips: number}
	@within Types
]=]
export type PlinkoPointsDropStarted = {
	dropIds: { number },
	wager: number,
	ballCount: number,
	staggerSeconds: number,
	chips: number,
}

--[=[
	Per-drop settlement after the ball lands in a bucket.

	- Landing bucket comes from the client gravity sim (not pre-rolled)
	- `payout = floor(wager * multiplier)` (0 for bust bucket)
	- Stake already deducted; `netDelta = payout - wager`
	- `outcome`: `win` if netDelta > 0, `bust` if payout == 0, else `loss` / `push`

	@type PlinkoPointsResultPayload {dropId: number, bucketIndex: number, multiplier: number, wager: number, payout: number, netDelta: number, highScore: number, chips: number, outcome: string}
	@within Types
]=]
export type PlinkoPointsResultPayload = {
	dropId: number,
	bucketIndex: number,
	multiplier: number,
	wager: number,
	payout: number,
	netDelta: number,
	highScore: number,
	chips: number,
	outcome: "win" | "bust" | "loss" | "push",
}

return Types
