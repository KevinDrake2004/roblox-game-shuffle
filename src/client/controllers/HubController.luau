--!strict
--[=[
	@class HubController
	Client hub bootstrap: profile sync, chips HUD, portal messaging.
]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Janitor = require(Packages.Janitor)

local Remotes = require(Shared.Remotes)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local HubHud = require(script.Parent.Parent.ui.HubHud)

type ProfileSnapshot = Types.ProfileSnapshot
type ChipsUpdatedPayload = Types.ChipsUpdatedPayload
type PortalResultPayload = Types.PortalResultPayload
type JobPromptPayload = Types.JobPromptPayload
type JobResultPayload = Types.JobResultPayload

local HubController = {}

local started = false
local janitor = Janitor.new()
local localPlayer = Players.LocalPlayer

local chips = 0
local activeJobId: number? = nil

local function onJobClicked()
	if activeJobId then
		Remotes.getEvent("JobAction"):FireServer("complete", activeJobId)
	else
		Remotes.getEvent("JobAction"):FireServer("start")
		HubHud.setJobState("WAIT…", "Get ready for the delivery signal")
	end
end

local function onJobPrompt(payload: JobPromptPayload)
	activeJobId = payload.jobId
	HubHud.setJobState("WAIT…", "Click only when DELIVER appears")

	local readyDelay = math.max(0, payload.readyAt - Workspace:GetServerTimeNow())
	task.delay(readyDelay, function()
		if activeJobId ~= payload.jobId then
			return
		end
		HubHud.setJobState("DELIVER!", "Click now!", Config.COLORS.NeonLime)
	end)

	local expireDelay = math.max(0, payload.expiresAt - Workspace:GetServerTimeNow() + 0.05)
	task.delay(expireDelay, function()
		if activeJobId ~= payload.jobId then
			return
		end
		Remotes.getEvent("JobAction"):FireServer("complete", payload.jobId)
	end)
end

local function onJobResult(payload: JobResultPayload)
	activeJobId = nil
	HubHud.setJobState(
		"WORK A SHIFT",
		payload.message,
		if payload.success then Config.COLORS.NeonLime else Config.COLORS.NeonMagenta
	)
end

local function onProfileLoaded(snapshot: ProfileSnapshot)
	chips = snapshot.chips
	HubHud.setChips(chips)
	print(
		`[Hub] Welcome to Shuffle Arcade — chips: {chips} (daily {snapshot.chipsEarnedToday}/{snapshot.dailyEarnCap})`
	)
end

local function onChipsUpdated(payload: ChipsUpdatedPayload)
	chips = payload.chips
	HubHud.setChips(chips)
	if payload.delta > 0 then
		print(`[Hub] +{payload.delta} chips from {payload.source} → {chips}`)
	elseif payload.source:find("daily_cap", 1, true) then
		print(`[Hub] Daily chip cap reached ({payload.dailyEarnCap})`)
	end
end

local function onPortalResult(payload: PortalResultPayload)
	if payload.status == "enter" then
		print(`[Hub] {payload.message}`)
	else
		print(`[Hub] Coming soon: {payload.message}`)
	end
end

function HubController.start()
	if started then
		return
	end
	started = true

	HubHud.start(onJobClicked)
	HubHud.setTitle(Config.GAME_NAME)

	janitor:Add(Remotes.getEvent("ProfileLoaded").OnClientEvent:Connect(onProfileLoaded), "Disconnect")
	janitor:Add(Remotes.getEvent("ChipsUpdated").OnClientEvent:Connect(onChipsUpdated), "Disconnect")
	janitor:Add(Remotes.getEvent("PortalResult").OnClientEvent:Connect(onPortalResult), "Disconnect")
	janitor:Add(Remotes.getEvent("JobPrompt").OnClientEvent:Connect(onJobPrompt), "Disconnect")
	janitor:Add(Remotes.getEvent("JobResult").OnClientEvent:Connect(onJobResult), "Disconnect")

	task.spawn(function()
		local ok, snapshot = pcall(function()
			return Remotes.getFunction("GetProfile"):InvokeServer()
		end)
		if ok and snapshot then
			onProfileLoaded(snapshot :: ProfileSnapshot)
		end
	end)

	print(`[Hub] Controller ready for {localPlayer.Name}`)
end

function HubController.getCachedChips(): number
	return chips
end

function HubController.stop()
	janitor:Cleanup()
	started = false
end

return HubController
