--!strict
--[=[
	@class CurrencyService
	Server-authoritative soft currency (Chips): earn grants, wager deducts, and payout credits.

	## APIs

	- `awardChips` - pure earn (jobs, etc.). Floored, positive, clipped by `Config.DAILY_EARN_CAP`.
	- `deductChips` - spend / stake chips. Fails (returns false) if balance is insufficient.
	- `creditPayout` - credit a wager settlement return in full (no daily-cap clip).

	## Daily earn cap vs wagering

	`DAILY_EARN_CAP` applies only to **earn-only** grants via `awardChips`.
	Wager payouts use `creditPayout` and are **not** clipped by the daily cap:

	- The stake was already removed with `deductChips`; clipping the return would strand
	  chips the player paid in and break per-game RTP (> 100%).
	- Net profit from wagering still increments `chipsEarnedToday` for progress display,
	  but never reduces the credited payout.

	Hitting the daily earn cap on `awardChips` notifies the client with `delta = 0`
	and a `:daily_cap` source suffix.
]=]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Signal = require(Packages.Signal)

local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)

type ChipsUpdatedPayload = Types.ChipsUpdatedPayload

local CurrencyService = {}

local started = false

CurrencyService.ChipsChanged = Signal.new()

local function buildPayload(player: Player, delta: number, source: string): ChipsUpdatedPayload?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end

	return {
		chips = profile.chips,
		delta = delta,
		source = source,
		chipsEarnedToday = profile.chipsEarnedToday,
		dailyEarnCap = Config.DAILY_EARN_CAP,
	}
end

local function notify(player: Player, delta: number, source: string)
	local payload = buildPayload(player, delta, source)
	if not payload then
		return
	end

	CurrencyService.ChipsChanged:Fire(player, payload)
	Remotes.getEvent("ChipsUpdated"):FireClient(player, payload)
end

--[=[
	No-op idempotent start hook so services share a common lifecycle.
]=]
function CurrencyService.start()
	if started then
		return
	end
	started = true
end

--[=[
	@return number -- Current chip balance, or 0 if the profile is not loaded
]=]
function CurrencyService.getChips(player: Player): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 0
	end
	return profile.chips
end

--[=[
	Grant chips (earn-only). Never decreases balance. Clipped by daily earn cap.

	@param player Player
	@param amount number -- Positive amount; floored before apply
	@param source string -- Audit label (e.g. `"LobbyJob"`)
	@return number -- Chips actually granted after daily-cap clipping (may be 0)
]=]
function CurrencyService.awardChips(player: Player, amount: number, source: string): number
	assert(typeof(amount) == "number", "amount must be a number")
	assert(amount == amount and amount > 0, "amount must be a positive finite number")
	assert(typeof(source) == "string" and source ~= "", "source is required")

	local grant = math.floor(amount)
	if grant <= 0 then
		return 0
	end

	local profile = DataService.waitForProfile(player)
	if not profile then
		warn(`[CurrencyService] No profile for {player.Name}; award skipped`)
		return 0
	end

	local remaining = Config.DAILY_EARN_CAP - profile.chipsEarnedToday
	if remaining <= 0 then
		notify(player, 0, `{source}:daily_cap`)
		return 0
	end

	grant = math.min(grant, remaining)
	profile.chips += grant
	profile.chipsEarnedToday += grant
	notify(player, grant, source)
	return grant
end

--[=[
	Deduct chips for a wager or spend. Does not go below zero; fails if balance is too low.

	@param player Player
	@param amount number -- Positive amount; floored before apply
	@param source string -- Audit label (e.g. `"RocketRun:wager"`)
	@return boolean -- true if deducted, false if insufficient balance or no profile
]=]
function CurrencyService.deductChips(player: Player, amount: number, source: string): boolean
	assert(typeof(amount) == "number", "amount must be a number")
	assert(amount == amount and amount > 0, "amount must be a positive finite number")
	assert(typeof(source) == "string" and source ~= "", "source is required")

	local cost = math.floor(amount)
	if cost <= 0 then
		return false
	end

	local profile = DataService.waitForProfile(player)
	if not profile then
		warn(`[CurrencyService] No profile for {player.Name}; deduct skipped`)
		return false
	end

	if profile.chips < cost then
		return false
	end

	profile.chips -= cost
	notify(player, -cost, source)
	return true
end

--[=[
	Credit a wager settlement payout in full (stake already deducted separately).

	Does **not** apply `DAILY_EARN_CAP` to the credit - see class docs. Net profit
	(`max(0, payout - wager)`) increments `chipsEarnedToday` for display only.

	@param player Player
	@param payout number -- Gross chips to credit; floored, must be >= 0
	@param wager number -- Original stake (for net-profit tracking); floored
	@param source string -- Audit label (e.g. `"RocketRun:payout"`)
	@return number -- Chips credited (floored payout)
]=]
function CurrencyService.creditPayout(player: Player, payout: number, wager: number, source: string): number
	assert(typeof(payout) == "number", "payout must be a number")
	assert(payout == payout and payout >= 0, "payout must be a non-negative finite number")
	assert(typeof(wager) == "number", "wager must be a number")
	assert(wager == wager and wager >= 0, "wager must be a non-negative finite number")
	assert(typeof(source) == "string" and source ~= "", "source is required")

	local credit = math.floor(payout)
	if credit <= 0 then
		return 0
	end

	local profile = DataService.waitForProfile(player)
	if not profile then
		warn(`[CurrencyService] No profile for {player.Name}; payout skipped`)
		return 0
	end

	profile.chips += credit
	local netProfit = math.max(0, credit - math.floor(wager))
	if netProfit > 0 then
		profile.chipsEarnedToday += netProfit
	end
	notify(player, credit, source)
	return credit
end

return CurrencyService
