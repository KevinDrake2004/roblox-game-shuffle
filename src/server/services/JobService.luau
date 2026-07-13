--!strict
--[=[
	@class JobService
	Repeatable timing job that lets players earn chips through active play.

	The server chooses the ready window and validates completion timing.
]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared

local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local CurrencyService = require(script.Parent.CurrencyService)

type JobPromptPayload = Types.JobPromptPayload
type JobResultPayload = Types.JobResultPayload

type ActiveJob = {
	id: number,
	readyAt: number,
	expiresAt: number,
}

local JobService = {}

local rng = Random.new()
local activeJobs: { [Player]: ActiveJob } = {}
local cooldownUntil: { [Player]: number } = {}
local nextJobId = 1
local started = false

local function sendResult(player: Player, success: boolean, chipsAwarded: number, message: string)
	local payload: JobResultPayload = {
		success = success,
		chipsAwarded = chipsAwarded,
		message = message,
	}
	Remotes.getEvent("JobResult"):FireClient(player, payload)
end

local function startJob(player: Player)
	local now = Workspace:GetServerTimeNow()
	if activeJobs[player] then
		return
	end
	if now < (cooldownUntil[player] or 0) then
		sendResult(player, false, 0, "Shift is cooling down")
		return
	end

	local cfg = Config.JOB
	local readyAt = now + rng:NextNumber(cfg.MinReadyDelay, cfg.MaxReadyDelay)
	local job: ActiveJob = {
		id = nextJobId,
		readyAt = readyAt,
		expiresAt = readyAt + cfg.ReactionWindow,
	}
	nextJobId += 1
	activeJobs[player] = job

	local payload: JobPromptPayload = {
		jobId = job.id,
		readyAt = job.readyAt,
		expiresAt = job.expiresAt,
	}
	Remotes.getEvent("JobPrompt"):FireClient(player, payload)
end

local function completeJob(player: Player, requestedJobId: unknown)
	local job = activeJobs[player]
	if not job or typeof(requestedJobId) ~= "number" or requestedJobId ~= job.id then
		return
	end

	local now = Workspace:GetServerTimeNow()
	activeJobs[player] = nil
	cooldownUntil[player] = now + Config.JOB.Cooldown

	if now < job.readyAt then
		sendResult(player, false, 0, "Too early - wait for DELIVER!")
		return
	end
	if now > job.expiresAt then
		sendResult(player, false, 0, "Too late - try another shift")
		return
	end

	local awarded = CurrencyService.awardChips(player, Config.JOB.Reward, "LobbyJob")
	sendResult(player, awarded > 0, awarded, `Delivery complete: +{awarded} chips`)
end

function JobService.start()
	if started then
		return
	end
	started = true

	Remotes.getEvent("JobAction").OnServerEvent:Connect(function(player: Player, action: unknown, jobId: unknown)
		if action == "start" then
			startJob(player)
		elseif action == "complete" then
			completeJob(player, jobId)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		activeJobs[player] = nil
		cooldownUntil[player] = nil
	end)
end

return JobService
