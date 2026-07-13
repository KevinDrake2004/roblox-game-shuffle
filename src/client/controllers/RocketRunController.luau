--!strict
--[=[
	@class RocketRunController
	Client controller for Rocket Run UI, camera, and remote handling.

	- Predicts the live multiplier from `flyStartTime` + `growthRate` (server time).
	- Forwards loadout / cash-out / leave requests; server remains authoritative.
	- Shows wager, balance, and potential payout while eligible and flying.
	- View modes: Walk / Telemetry (graph label) / Rocket / Both.
	- Rocket and Both use a scriptable follow camera; Walk and Telemetry free-cam.
]=]
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Janitor = require(Packages.Janitor)

local Remotes = require(Shared.Remotes)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local RocketRunHud = require(script.Parent.Parent.ui.RocketRunHud)
local HubHud = require(script.Parent.Parent.ui.HubHud)

type RocketRunRoundStarted = Types.RocketRunRoundStarted
type RocketRunResultPayload = Types.RocketRunResultPayload
type RocketRunCashOutMarker = Types.RocketRunCashOutMarker

local RocketRunController = {}

local started = false
local active = false
local roundJanitor = Janitor.new()
local currentRoundId: number? = nil
local flyStartTime = 0
local growthRate = Config.ROCKET_RUN.GrowthRate
local cashedOut = false
local eligible = false
local currentWager = Config.ROCKET_RUN.DefaultWager
local currentAutoCashOut: number? = nil
local currentHighScore = 0
local lastPayoutMessage = ""
local savedCameraType: Enum.CameraType? = nil
local cameraActive = false
local rocketMuted = false
local followRocketCamera = false

local function potentialPayout(multiplier: number): number
	return math.floor(currentWager * multiplier * Config.ROCKET_RUN.PlayerReturnFactor)
end

local function formatNetDelta(netDelta: number): string
	if netDelta > 0 then
		return string.format("+%d", netDelta)
	end
	return tostring(netDelta)
end

local function getCameraFocus(): BasePart?
	local arena = Workspace:FindFirstChild("RocketRunArena")
	if not arena then
		return nil
	end
	local focus = arena:FindFirstChild("CameraFocus")
	if focus and focus:IsA("BasePart") then
		return focus
	end
	local rocket = arena:FindFirstChild("Rocket")
	if rocket and rocket:IsA("Model") then
		local body = rocket:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			return body
		end
	end
	return nil
end

local function startExternalCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if not cameraActive then
		savedCameraType = camera.CameraType
		cameraActive = true
	end
	camera.CameraType = Enum.CameraType.Scriptable
	followRocketCamera = true
end

local function stopExternalCamera()
	local camera = Workspace.CurrentCamera
	if camera and cameraActive then
		camera.CameraType = savedCameraType or Enum.CameraType.Custom
		local character = Players.LocalPlayer.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
	cameraActive = false
	followRocketCamera = false
	savedCameraType = nil
end

local function applyViewMode(mode: string)
	if mode == "Rocket" or mode == "Both" then
		startExternalCamera()
	else
		-- Walk and Telemetry let the player roam the arena freely.
		stopExternalCamera()
	end
end

local function updateCamera()
	if not followRocketCamera then
		return
	end
	local camera = Workspace.CurrentCamera
	local focus = getCameraFocus()
	if not camera or not focus then
		return
	end
	local offset = Config.ROCKET_RUN.CameraOffset
	local target = focus.Position
	camera.CFrame = CFrame.lookAt(target + offset, target)
end

local function requestCashOut()
	if not active or currentRoundId == nil then
		return
	end
	Remotes.getEvent("RocketRunCashOut"):FireServer(currentRoundId)
end

local function requestLeave()
	Remotes.getEvent("RocketRunLeave"):FireServer()
end

local function applyRocketVolume()
	local arena = Workspace:FindFirstChild("RocketRunArena")
	local rocket = if arena then arena:FindFirstChild("Rocket") else nil
	if not rocket then
		return
	end
	for _, descendant in rocket:GetDescendants() do
		if descendant:IsA("Sound") then
			descendant.Volume = if rocketMuted then 0 else 0.18
		end
	end
	RocketRunHud.setMuted(rocketMuted)
end

local function toggleRocketMute()
	rocketMuted = not rocketMuted
	applyRocketVolume()
end

local function applyLoadout(wager: number, autoCashOut: number?)
	Remotes.getEvent("RocketRunSetLoadout"):FireServer(wager, autoCashOut)
	currentWager = math.clamp(math.floor(wager), Config.ROCKET_RUN.MinWager, Config.ROCKET_RUN.MaxWager)
	currentAutoCashOut = autoCashOut
	RocketRunHud.setStatus(
		if autoCashOut
			then string.format("Wager %d, auto @ %.2fx (applies next round)", currentWager, autoCashOut)
			else string.format("Wager %d, auto off (applies next round)", currentWager)
	)
end

local function bindRoundRender()
	roundJanitor:Cleanup()

	roundJanitor:Add(
		RunService.RenderStepped:Connect(function()
			updateCamera()
			if not active or currentRoundId == nil then
				return
			end

			local now = Workspace:GetServerTimeNow()
			local untilFly = flyStartTime - now
			if untilFly > 0 then
				RocketRunHud.setMultiplier(1, Config.COLORS.NeonCyan)
				RocketRunHud.setStatus(string.format("Launching in %.1fs", untilFly))
				RocketRunHud.setCashOutEnabled(false)
				if eligible and not cashedOut then
					RocketRunHud.setScoreLine(
						string.format(
							"Wager %d  |  Potential %d  |  High score: %d",
							currentWager,
							potentialPayout(1),
							currentHighScore
						)
					)
				end
				return
			end

			local elapsed = now - flyStartTime
			local multiplier = math.exp(growthRate * elapsed)
			RocketRunHud.updateGraph(elapsed, multiplier)
			local color = if multiplier >= 5
				then Config.COLORS.NeonMagenta
				elseif multiplier >= 2 then Config.COLORS.NeonLime
				else Config.COLORS.NeonCyan

			RocketRunHud.setMultiplier(multiplier, color)
			if cashedOut or not eligible then
				RocketRunHud.setStatus(
					if lastPayoutMessage ~= ""
						then `{lastPayoutMessage} - spectating rocket`
						else "Spectating this round"
				)
				RocketRunHud.setCashOutEnabled(false)
			else
				local payout = potentialPayout(multiplier)
				RocketRunHud.setStatus(string.format("Cash out for ~%d chips!", payout))
				RocketRunHud.setScoreLine(
					string.format(
						"Wager %d  |  Potential %d%s  |  High score: %d",
						currentWager,
						payout,
						if currentAutoCashOut then string.format("  |  Auto %.2fx", currentAutoCashOut) else "",
						currentHighScore
					)
				)
				RocketRunHud.setCashOutEnabled(true)
			end
		end),
		"Disconnect"
	)

	roundJanitor:Add(
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Space then
				requestCashOut()
			end
		end),
		"Disconnect"
	)
end

--[=[
	Hide Rocket Run HUD and restore default hub camera / title after leaving.
]=]
function RocketRunController.stopRound()
	active = false
	currentRoundId = nil
	cashedOut = false
	eligible = false
	lastPayoutMessage = ""
	roundJanitor:Cleanup()
	RocketRunHud.setVisible(false)
	RocketRunHud.setCashOutEnabled(false)
	RocketRunHud.setLoadoutEnabled(true)
	HubHud.setTitle(Config.GAME_NAME)
	stopExternalCamera()
	rocketMuted = false
	applyRocketVolume()
end

--[=[
	Begin client round state from a `RocketRunRoundStarted` payload.
	@param payload RocketRunRoundStarted
]=]
function RocketRunController.startRound(payload: RocketRunRoundStarted)
	active = true
	currentRoundId = payload.roundId
	flyStartTime = payload.flyStartTime
	growthRate = payload.growthRate
	cashedOut = not payload.eligible
	eligible = payload.eligible
	currentWager = payload.wager
	currentAutoCashOut = payload.autoCashOut
	currentHighScore = payload.highScore
	lastPayoutMessage = ""

	HubHud.setTitle("Rocket Run")
	HubHud.setChips(payload.chips)
	RocketRunHud.setVisible(true)
	RocketRunHud.setLoadoutEnabled(true)
	RocketRunHud.setLoadoutValues(payload.wager, payload.autoCashOut)
	RocketRunHud.setScoreLine(
		string.format(
			"Wager %d%s  |  Balance %d  |  High score: %d",
			payload.wager,
			if payload.autoCashOut then string.format("  |  Auto %.2fx", payload.autoCashOut) else "",
			payload.chips,
			payload.highScore
		)
	)
	RocketRunHud.setStatus(
		if payload.eligible
			then "Get ready…"
			elseif payload.phase == "countdown" then "Insufficient chips for this wager - spectating"
			else "Round in progress - spectating until next launch"
	)
	RocketRunHud.setMultiplier(1, Config.COLORS.NeonCyan)
	RocketRunHud.beginGraph()
	if payload.phase == "flying" then
		local elapsed = math.max(0, Workspace:GetServerTimeNow() - payload.flyStartTime)
		RocketRunHud.updateGraph(elapsed, math.exp(payload.growthRate * elapsed))
	end
	RocketRunHud.setCashOutEnabled(false)
	applyRocketVolume()
	applyViewMode(RocketRunHud.getViewMode())
	bindRoundRender()
end

--[=[
	Wire HUD callbacks and Rocket Run remotes. Idempotent.
]=]
function RocketRunController.start()
	if started then
		return
	end
	started = true

	RocketRunHud.start(requestCashOut, requestLeave, applyLoadout, toggleRocketMute, applyViewMode)
	-- Push default loadout once
	applyLoadout(Config.ROCKET_RUN.DefaultWager, nil)

	Remotes.getEvent("RocketRunRoundStarted").OnClientEvent:Connect(function(payload: RocketRunRoundStarted)
		RocketRunController.startRound(payload)
	end)

	Remotes.getEvent("RocketRunCrashed").OnClientEvent
		:Connect(function(payload: { roundId: number, crashMultiplier: number })
			if currentRoundId ~= payload.roundId then
				return
			end
			active = false
			RocketRunHud.setCashOutEnabled(false)
			RocketRunHud.setMultiplier(payload.crashMultiplier, Config.COLORS.NeonMagenta)
			RocketRunHud.finishGraph(math.log(payload.crashMultiplier) / growthRate, payload.crashMultiplier)
			RocketRunHud.setStatus(
				if lastPayoutMessage ~= ""
					then string.format("%s - rocket crashed @ %.2fx", lastPayoutMessage, payload.crashMultiplier)
					else string.format("Rocket crashed @ %.2fx", payload.crashMultiplier)
			)
		end)

	Remotes.getEvent("RocketRunCashOutMarker").OnClientEvent:Connect(function(payload: RocketRunCashOutMarker)
		if currentRoundId ~= payload.roundId then
			return
		end
		RocketRunHud.addCashOutMarker(
			payload.displayName,
			payload.elapsed,
			payload.multiplier,
			payload.userId == Players.LocalPlayer.UserId
		)
	end)

	Remotes.getEvent("RocketRunResult").OnClientEvent:Connect(function(payload: RocketRunResultPayload)
		if currentRoundId ~= nil and payload.roundId ~= currentRoundId then
			return
		end
		RocketRunHud.setCashOutEnabled(false)
		RocketRunHud.setLoadoutEnabled(true)
		HubHud.setChips(payload.chips)
		currentHighScore = payload.highScore
		currentWager = payload.wager

		if payload.outcome == "cashed_out" then
			cashedOut = true
			lastPayoutMessage = string.format(
				"Cashed @ %.2fx, payout %d (%s)",
				payload.multiplier,
				payload.payout,
				formatNetDelta(payload.netDelta)
			)
			RocketRunHud.setStatus(`{lastPayoutMessage} - spectating rocket`)
		else
			cashedOut = true
			lastPayoutMessage =
				string.format("Crashed @ %.2fx, %s chips", payload.multiplier, formatNetDelta(payload.netDelta))
			RocketRunHud.setStatus(lastPayoutMessage)
		end
		RocketRunHud.setScoreLine(
			string.format("Wager %d  |  Balance %d  |  High score: %d", payload.wager, payload.chips, payload.highScore)
		)
	end)

	Remotes.getEvent("PortalResult").OnClientEvent:Connect(function(payload: Types.PortalResultPayload)
		if payload.gameId == "RocketRun" and payload.status == "enter" then
			RocketRunHud.setVisible(true)
			RocketRunHud.setLoadoutEnabled(true)
			RocketRunHud.setStatus("Entering Rocket Run… set wager & auto cash-out")
			HubHud.setTitle("Rocket Run")
			RocketRunHud.setViewMode("Walk")
			roundJanitor:Cleanup()
			roundJanitor:Add(RunService.RenderStepped:Connect(updateCamera), "Disconnect")
		end
	end)

	Remotes.getEvent("RocketRunLeft").OnClientEvent:Connect(function()
		RocketRunController.stopRound()
	end)
end

return RocketRunController
