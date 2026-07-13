--!strict
--[=[
	@class PlinkoPointsController
	Client controller for Plinko Points UI, board camera, and remote handling.

	- Forwards wager / drop / leave requests.
	- After DropStarted, runs a free local gravity sim; reports the landed bucket.
	- Multiplier labels and balls exist only for the local player while in-arena.
	- Tracks session net P/L locally from result payloads.
]=]
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

local PlinkoBallPhysics = require(script.Parent.PlinkoBallPhysics)
local PlinkoPointsHud = require(script.Parent.Parent.ui.PlinkoPointsHud)
local HubHud = require(script.Parent.Parent.ui.HubHud)

type PlinkoPointsJoined = Types.PlinkoPointsJoined
type PlinkoPointsDropStarted = Types.PlinkoPointsDropStarted
type PlinkoPointsResultPayload = Types.PlinkoPointsResultPayload

local PlinkoPointsController = {}

local started = false
local active = false
local cameraJanitor = Janitor.new()
local labelJanitor = Janitor.new()
local sessionNet = 0
local dropBusy = false
local activeDropId: number? = nil
local savedCameraType: Enum.CameraType? = nil
local cameraActive = false

local function formatNetDelta(netDelta: number): string
	if netDelta > 0 then
		return string.format("+%d", netDelta)
	end
	return tostring(netDelta)
end

local function formatMultiplierLabel(multiplier: number): string
	if multiplier == 0 then
		return "0x"
	end
	if multiplier == math.floor(multiplier) then
		return string.format("%dx", multiplier)
	end
	return string.format("%.1fx", multiplier)
end

local function sessionColor(): Color3
	if sessionNet > 0 then
		return Config.COLORS.NeonLime
	elseif sessionNet < 0 then
		return Config.COLORS.NeonMagenta
	end
	return Config.COLORS.NeonPurple
end

local function refreshSessionLine()
	PlinkoPointsHud.setSessionLine(string.format("Session: %s", formatNetDelta(sessionNet)), sessionColor())
end

local function getCameraFocus(): BasePart?
	local arena = Workspace:FindFirstChild("PlinkoArena")
	if not arena then
		return nil
	end
	local focus = arena:FindFirstChild("CameraFocus")
	if focus and focus:IsA("BasePart") then
		return focus
	end
	return nil
end

local function clearLocalMultiplierLabels()
	labelJanitor:Cleanup()
	local arena = Workspace:FindFirstChild("PlinkoArena")
	if not arena then
		return
	end
	local buckets = arena:FindFirstChild("Buckets")
	if not buckets then
		return
	end
	for _, child in buckets:GetChildren() do
		if child:IsA("BasePart") then
			local gui = child:FindFirstChild("LocalMultiplierGui")
			if gui then
				gui:Destroy()
			end
			local legacy = child:FindFirstChild("MultiplierGui")
			if legacy and legacy:IsA("BillboardGui") then
				legacy.Enabled = false
			end
		end
	end
end

local function showLocalMultiplierLabels()
	clearLocalMultiplierLabels()
	local arena = Workspace:FindFirstChild("PlinkoArena")
	if not arena then
		return
	end
	local buckets = arena:FindFirstChild("Buckets")
	if not buckets then
		return
	end

	local multipliers = Config.PLINKO.BucketMultipliers
	for index, multiplier in multipliers do
		local bucket = buckets:FindFirstChild(`Bucket_{index - 1}`)
		if not (bucket and bucket:IsA("BasePart")) then
			continue
		end

		local gui = Instance.new("BillboardGui")
		gui.Name = "LocalMultiplierGui"
		gui.Size = UDim2.fromOffset(72, 36)
		gui.StudsOffset = Vector3.new(0, 1.6, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 80
		gui.Parent = bucket
		labelJanitor:Add(gui)

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextStrokeTransparency = 0.35
		label.Text = formatMultiplierLabel(multiplier)
		if multiplier <= 0 then
			label.TextColor3 = Config.COLORS.NeonMagenta
		elseif multiplier >= 4 then
			label.TextColor3 = Config.COLORS.NeonLime
		else
			label.TextColor3 = Config.COLORS.Text
		end
		label.Parent = gui

		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.COLORS.NeonPurple
		stroke.Thickness = 1.5
		stroke.Parent = label
	end
end

local function startBoardCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if not cameraActive then
		savedCameraType = camera.CameraType
		cameraActive = true
	end
	camera.CameraType = Enum.CameraType.Scriptable

	cameraJanitor:Cleanup()
	cameraJanitor:Add(
		RunService.RenderStepped:Connect(function()
			if not cameraActive then
				return
			end
			local cam = Workspace.CurrentCamera
			local focus = getCameraFocus()
			if not cam or not focus then
				return
			end
			local offset = Config.PLINKO.CameraOffset
			local target = focus.Position
			cam.CFrame = CFrame.lookAt(target + offset, target)
		end),
		"Disconnect"
	)
end

local function stopBoardCamera()
	cameraJanitor:Cleanup()
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
	savedCameraType = nil
end

local function applyResultHud(payload: PlinkoPointsResultPayload)
	sessionNet += payload.netDelta
	HubHud.setChips(payload.chips)
	PlinkoPointsHud.flashOutcome(payload.outcome)

	local outcomeColor = if payload.outcome == "win"
		then Config.COLORS.NeonLime
		elseif payload.outcome == "bust" or payload.outcome == "loss" then Config.COLORS.NeonMagenta
		else Config.COLORS.NeonPurple

	local headline = if payload.outcome == "win"
		then string.format("WIN  %s  %.2fx", formatNetDelta(payload.netDelta), payload.multiplier)
		elseif payload.outcome == "bust" then string.format("BUST  %s", formatNetDelta(payload.netDelta))
		elseif payload.outcome == "push" then string.format("PUSH  %.2fx", payload.multiplier)
		else string.format("LOSS  %s  %.2fx", formatNetDelta(payload.netDelta), payload.multiplier)

	PlinkoPointsHud.setResult(headline, outcomeColor)
	PlinkoPointsHud.setStatus(
		string.format(
			"Payout %d (%s)  ·  bucket %d",
			payload.payout,
			formatNetDelta(payload.netDelta),
			payload.bucketIndex + 1
		)
	)
	PlinkoPointsHud.setScoreLine(
		string.format("Wager %d  |  Balance %d  |  High score: %d", payload.wager, payload.chips, payload.highScore)
	)
	refreshSessionLine()
	dropBusy = false
	activeDropId = nil
	PlinkoPointsHud.setDropEnabled(true)
end

local function requestDrop()
	if not active or dropBusy then
		return
	end
	dropBusy = true
	PlinkoPointsHud.setDropEnabled(false)
	PlinkoPointsHud.setStatus("Dropping…")
	Remotes.getEvent("PlinkoPointsDrop"):FireServer()
end

local function requestLeave()
	Remotes.getEvent("PlinkoPointsLeave"):FireServer()
end

local function applyWager(wager: number)
	local clamped = math.clamp(math.floor(wager), Config.PLINKO.MinWager, Config.PLINKO.MaxWager)
	Remotes.getEvent("PlinkoPointsSetWager"):FireServer(clamped)
	PlinkoPointsHud.setWagerValue(clamped)
	PlinkoPointsHud.setStatus(string.format("Wager set to %d chips", clamped))
end

local function startFreeDrop(payload: PlinkoPointsDropStarted)
	activeDropId = payload.dropId
	HubHud.setChips(payload.chips)
	PlinkoPointsHud.setStatus("Ball in play…")
	PlinkoPointsHud.setScoreLine(string.format("Wager %d  |  Balance %d", payload.wager, payload.chips))

	PlinkoBallPhysics.drop(function(bucketIndex: number)
		if not active or activeDropId ~= payload.dropId then
			return
		end
		Remotes.getEvent("PlinkoPointsLanded"):FireServer(payload.dropId, bucketIndex)
		PlinkoPointsHud.setStatus("Settling…")
	end)
end

--[=[
	Hide Plinko HUD and restore default hub camera / title after leaving.
]=]
function PlinkoPointsController.stopSession()
	active = false
	dropBusy = false
	activeDropId = nil
	sessionNet = 0
	PlinkoBallPhysics.cancel()
	clearLocalMultiplierLabels()
	cameraJanitor:Cleanup()
	PlinkoPointsHud.setVisible(false)
	PlinkoPointsHud.setDropEnabled(true)
	HubHud.setTitle(Config.GAME_NAME)
	stopBoardCamera()
end

--[=[
	Begin client session from a `PlinkoPointsJoined` payload.
	@param payload PlinkoPointsJoined
]=]
function PlinkoPointsController.startSession(payload: PlinkoPointsJoined)
	active = true
	dropBusy = false
	activeDropId = nil
	sessionNet = 0

	HubHud.setTitle("Plinko Points")
	HubHud.setChips(payload.chips)
	PlinkoPointsHud.setVisible(true)
	PlinkoPointsHud.setWagerEnabled(true)
	PlinkoPointsHud.setWagerValue(payload.wager)
	PlinkoPointsHud.setDropEnabled(true)
	PlinkoPointsHud.setResult("Drop a ball", Config.COLORS.NeonPurple)
	PlinkoPointsHud.setStatus("Set wager, then drop")
	PlinkoPointsHud.setScoreLine(
		string.format("Wager %d  |  Balance %d  |  High score: %d", payload.wager, payload.chips, payload.highScore)
	)
	refreshSessionLine()
	showLocalMultiplierLabels()
	startBoardCamera()
end

--[=[
	Wire HUD callbacks and Plinko remotes. Idempotent.
]=]
function PlinkoPointsController.start()
	if started then
		return
	end
	started = true

	clearLocalMultiplierLabels()

	PlinkoPointsHud.start(requestDrop, requestLeave, applyWager)
	applyWager(Config.PLINKO.DefaultWager)

	Remotes.getEvent("PlinkoPointsJoined").OnClientEvent:Connect(function(payload: PlinkoPointsJoined)
		PlinkoPointsController.startSession(payload)
	end)

	Remotes.getEvent("PlinkoPointsDropStarted").OnClientEvent:Connect(function(payload: PlinkoPointsDropStarted)
		if not active then
			return
		end
		startFreeDrop(payload)
	end)

	Remotes.getEvent("PlinkoPointsResult").OnClientEvent:Connect(function(payload: PlinkoPointsResultPayload)
		if not active then
			return
		end
		applyResultHud(payload)
	end)

	Remotes.getEvent("PlinkoPointsDropRejected").OnClientEvent:Connect(function(payload: { reason: string })
		dropBusy = false
		activeDropId = nil
		PlinkoBallPhysics.cancel()
		PlinkoPointsHud.setDropEnabled(true)
		PlinkoPointsHud.setStatus(payload.reason or "Drop rejected")
		PlinkoPointsHud.setResult("Blocked", Config.COLORS.NeonMagenta)
	end)

	Remotes.getEvent("PortalResult").OnClientEvent:Connect(function(payload: Types.PortalResultPayload)
		if payload.gameId == "PlinkoPoints" and payload.status == "enter" then
			PlinkoPointsHud.setVisible(true)
			PlinkoPointsHud.setStatus("Entering Plinko Points…")
			HubHud.setTitle("Plinko Points")
		end
	end)

	Remotes.getEvent("PlinkoPointsLeft").OnClientEvent:Connect(function()
		PlinkoPointsController.stopSession()
	end)
end

return PlinkoPointsController
