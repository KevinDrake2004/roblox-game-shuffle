--!strict
--[=[
	@class DataService
	Session player profiles for Phase 1 (in-memory).

	Phase 2 will swap the load/save path to DataStore / ProfileStore without
	changing the public API used by CurrencyService and remotes.
]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Janitor = require(Packages.Janitor)
local Promise = require(Packages.Promise)
local Signal = require(Packages.Signal)

local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

type PlayerProfile = Types.PlayerProfile
type ProfileSnapshot = Types.ProfileSnapshot
type HighScores = Types.HighScores

local DataService = {}

local profiles: { [Player]: PlayerProfile } = {}
local janitors: { [Player]: any } = {}
local started = false

DataService.ProfileLoaded = Signal.new()

local function dayKey(unixTime: number): number
	local utc = os.date("!*t", unixTime)
	return utc.year * 10000 + utc.month * 100 + utc.day
end

local function defaultHighScores(): HighScores
	return {
		RocketRun = 0,
		PlinkoPoints = 0,
		MineSweeper = 0,
	}
end

local function createDefaultProfile(): PlayerProfile
	return {
		chips = Config.STARTING_CHIPS,
		chipsEarnedToday = 0,
		lastDailyResetDay = dayKey(os.time()),
		highScores = defaultHighScores(),
	}
end

local function maybeResetDaily(profile: PlayerProfile)
	local today = dayKey(os.time())
	if profile.lastDailyResetDay ~= today then
		profile.lastDailyResetDay = today
		profile.chipsEarnedToday = 0
	end
end

local function toSnapshot(profile: PlayerProfile): ProfileSnapshot
	maybeResetDaily(profile)
	return {
		chips = profile.chips,
		chipsEarnedToday = profile.chipsEarnedToday,
		dailyEarnCap = Config.DAILY_EARN_CAP,
		highScores = {
			RocketRun = profile.highScores.RocketRun,
			PlinkoPoints = profile.highScores.PlinkoPoints,
			MineSweeper = profile.highScores.MineSweeper,
		},
	}
end

local function loadProfileAsync(_player: Player)
	-- Phase 1: instant session profile. Phase 2: DataStore yield goes here.
	return Promise.resolve(createDefaultProfile())
end

local function onPlayerAdded(player: Player)
	local playerJanitor = Janitor.new()
	janitors[player] = playerJanitor

	playerJanitor:AddPromise(loadProfileAsync(player)
		:andThen(function(profile: PlayerProfile)
			if player.Parent ~= Players then
				return
			end

			profiles[player] = profile
			maybeResetDaily(profile)

			local snapshot = toSnapshot(profile)
			DataService.ProfileLoaded:Fire(player, snapshot)
			Remotes.getEvent("ProfileLoaded"):FireClient(player, snapshot)
		end)
		:catch(function(err)
			warn(`[DataService] Failed to load profile for {player.Name}: {err}`)
		end))
end

local function onPlayerRemoving(player: Player)
	-- Phase 2: persist profile here before clearing.
	profiles[player] = nil

	local playerJanitor = janitors[player]
	if playerJanitor then
		playerJanitor:Destroy()
		janitors[player] = nil
	end
end

function DataService.start()
	if started then
		return
	end
	started = true

	Remotes.getFunction("GetProfile").OnServerInvoke = function(player: Player): ProfileSnapshot?
		local profile = profiles[player]
		if not profile then
			return nil
		end
		return toSnapshot(profile)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function DataService.getProfile(player: Player): PlayerProfile?
	local profile = profiles[player]
	if profile then
		maybeResetDaily(profile)
	end
	return profile
end

function DataService.getSnapshot(player: Player): ProfileSnapshot?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end
	return toSnapshot(profile)
end

function DataService.waitForProfile(player: Player, timeoutSeconds: number?): PlayerProfile?
	local existing = profiles[player]
	if existing then
		maybeResetDaily(existing)
		return existing
	end

	local timeout = timeoutSeconds or 10
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local profile = profiles[player]
		if profile then
			maybeResetDaily(profile)
			return profile
		end
		task.wait(0.05)
	end
	return nil
end

function DataService.getHighScore(player: Player, gameId: Types.GameId): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 0
	end
	return profile.highScores[gameId] or 0
end

function DataService.setHighScore(player: Player, gameId: Types.GameId, score: number): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 0
	end
	local current = profile.highScores[gameId] or 0
	if score > current then
		profile.highScores[gameId] = score
		return score
	end
	return current
end

return DataService
