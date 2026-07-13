--!strict
--[=[
	@class PlinkoPointsController
	Client controller for Plinko Points UI, board camera, and remote handling.

	- Forwards wager / drop / leave requests; server remains authoritative on settle.
	- Optional ball tween toward the server-chosen bucket for show only.
	- Tracks session net P/L locally from result payloads.
	- Board camera only while in the Plinko arena; restores Custom on leave.
]=]
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Janitor = require(Packages.Janitor)

local Remotes = require(Shared.Remotes)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local PlinkoPointsHud = require(script.Parent.Parent.ui.PlinkoPointsHud)
local HubHud = require(script.Parent.Parent.ui.HubHud)

type PlinkoPointsJoined = Types.PlinkoPointsJoined
type PlinkoPointsResultPayload = Types.PlinkoPointsResultPayload

local PlinkoPointsController = {}

local started = false
local active = false
local cameraJanitor = Janitor.new()
local sessionNet = 0
local dropBusy = false
local savedCameraType: Enum.CameraType? = nil
local cameraActive = false

local function formatNetDelta(netDelta: number): string
	if netDelta > 0 then
		return string.format("+%d", netDelta)
	end
	return tostring(netDelta)
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

local function getBucketPart(bucketIndex: number): BasePart?
	local arena = Workspace:FindFirstChild("PlinkoArena")
	if not arena then
		return nil
	end
	local buckets = arena:FindFirstChild("Buckets")
	if not buckets then
		return nil
	end
	local bucket = buckets:FindFirstChild(`Bucket_{bucketIndex}`)
	if bucket and bucket:IsA("BasePart") then
		return bucket
	end
	return nil
end

local function getDropOrigin(): BasePart?
	local arena = Workspace:FindFirstChild("PlinkoArena")
	if not arena then
		return nil
	end
	local origin = arena:FindFirstChild("DropOrigin")
	if origin and origin:IsA("BasePart") then
		return origin
	end
	return nil
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

local function animateBallToBucket(bucketIndex: number)
	local origin = getDropOrigin()
	local bucket = getBucketPart(bucketIndex)
	if not origin or not bucket then
		return
	end

	local ball = Instance.new("Part")
	ball.Name = "PlinkoBall"
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Size = Vector3.new(1.1, 1.1, 1.1)
	ball.Color = Config.COLORS.NeonPurple
	ball.Material = Enum.Material.Neon
	ball.Position = origin.Position
	ball.Parent = Workspace

	local mid = Vector3.new(
		(origin.Position.X + bucket.Position.X) / 2 + (math.random() - 0.5) * 2,
		(origin.Position.Y + bucket.Position.Y) / 2,
		origin.Position.Z
	)
	local duration = Config.PLINKO.BallDropDuration
	local half = duration * 0.55

	local tweenA = TweenService:Create(
		ball,
		TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ Position = mid }
	)
	local tweenB = TweenService:Create(
		ball,
		TweenInfo.new(duration - half, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = bucket.Position + Vector3.new(0, 0.8, 0) }
	)
	tweenA:Play()
	tweenA.Completed:Connect(function()
		if ball.Parent then
			tweenB:Play()
		end
	end)
	Debris:AddItem(ball, duration + 0.35)
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

--[=[
	Hide Plinko HUD and restore default hub camera / title after leaving.
]=]
function PlinkoPointsController.stopSession()
	active = false
	dropBusy = false
	sessionNet = 0
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

	PlinkoPointsHud.start(requestDrop, requestLeave, applyWager)
	applyWager(Config.PLINKO.DefaultWager)

	Remotes.getEvent("PlinkoPointsJoined").OnClientEvent:Connect(function(payload: PlinkoPointsJoined)
		PlinkoPointsController.startSession(payload)
	end)

	Remotes.getEvent("PlinkoPointsResult").OnClientEvent:Connect(function(payload: PlinkoPointsResultPayload)
		if not active then
			return
		end

		animateBallToBucket(payload.bucketIndex)
		task.delay(Config.PLINKO.BallDropDuration * 0.85, function()
			if not active then
				return
			end

			sessionNet += payload.netDelta
			HubHud.setChips(payload.chips)
			PlinkoPointsHud.flashOutcome(payload.outcome)

			local outcomeColor = if payload.outcome == "win"
				then Config.COLORS.NeonLime
				elseif payload.outcome == "bust" or payload.outcome == "loss" then Config.COLORS.NeonMagenta
				else Config.COLORS.NeonPurple

			local headline = if payload.outcome == "win"
				then string.format("WIN  %.2fx", payload.multiplier)
				elseif payload.outcome == "bust" then "BUST  0x"
				elseif payload.outcome == "push" then string.format("PUSH  %.2fx", payload.multiplier)
				else string.format("LOSS  %.2fx", payload.multiplier)

			PlinkoPointsHud.setResult(headline, outcomeColor)
			PlinkoPointsHud.setStatus(
				string.format(
					"Payout %d (%s)  ·  landed bucket %d",
					payload.payout,
					formatNetDelta(payload.netDelta),
					payload.bucketIndex + 1
				)
			)
			PlinkoPointsHud.setScoreLine(
				string.format(
					"Wager %d  |  Balance %d  |  High score: %d",
					payload.wager,
					payload.chips,
					payload.highScore
				)
			)
			refreshSessionLine()
			dropBusy = false
			PlinkoPointsHud.setDropEnabled(true)
		end)
	end)

	Remotes.getEvent("PlinkoPointsDropRejected").OnClientEvent:Connect(function(payload: { reason: string })
		dropBusy = false
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
