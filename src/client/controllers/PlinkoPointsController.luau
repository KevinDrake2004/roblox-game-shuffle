--!strict
--[=[
	@class PlinkoPointsController
	Client controller for Plinko Points UI, board camera, and remote handling.

	- Forwards wager / ball-count / drop / leave requests.
	- After DropStarted, releases balls on a stagger; each is an independent sim
	  (balls do not collide with each other, only pegs).
	- Multiplier labels and balls exist only for the local player while in-arena.
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
local pendingResults = 0
local activeDropIds: { [number]: boolean } = {}
-- Invalidates in-flight cup-flash batch counters on cancel / new drop.
local bucketFlashBatch = 0
local currentBallCount = Config.PLINKO.DefaultBallCount
local currentRiskId = Config.PLINKO.DefaultRiskId
local savedCameraType: Enum.CameraType? = nil
local cameraActive = false

local function formatNetDelta(netDelta: number): string
	if netDelta > 0 then
		return string.format("+%d", netDelta)
	end
	return tostring(netDelta)
end

local function formatMultiplierLabel(multiplier: number): string
	if multiplier <= 0 then
		return "0x"
	end
	if multiplier == math.floor(multiplier) then
		return string.format("%dx", multiplier)
	end
	-- Prefer short labels so they fit on the bucket face (0.85x, 1.8x, 0.2x).
	local tenths = math.floor(multiplier * 10 + 1e-6)
	if math.abs(multiplier * 10 - tenths) < 1e-6 then
		return string.format("%.1fx", multiplier)
	end
	return string.format("%.2fx", multiplier)
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

local function dropButtonLabel(ballCount: number): string
	if ballCount <= 1 then
		return "DROP 1 BALL"
	end
	return string.format("DROP %d BALLS", ballCount)
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
	local buckets = PlinkoBallPhysics.getLocalBucketsFolder()
	if not buckets then
		return
	end
	for _, child in buckets:GetChildren() do
		if child:IsA("BasePart") then
			local gui = child:FindFirstChild("LocalMultiplierGui")
			if gui then
				gui:Destroy()
			end
		end
	end
end

local function showLocalMultiplierLabels()
	clearLocalMultiplierLabels()
	local buckets = PlinkoBallPhysics.getLocalBucketsFolder()
	if not buckets then
		return
	end

	local risk = Config.getPlinkoRisk(currentRiskId)
	local multipliers = risk.bucketMultipliers
	for index, multiplier in multipliers do
		local bucket = buckets:FindFirstChild(`Bucket_{index - 1}`)
		if not (bucket and bucket:IsA("BasePart")) then
			continue
		end
		bucket.Anchored = true
		bucket.CanCollide = false

		-- SurfaceGui on the player-facing face so the label sits on the box, not above it.
		local gui = Instance.new("SurfaceGui")
		gui.Name = "LocalMultiplierGui"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 64
		gui.LightInfluence = 0
		gui.Brightness = 2
		gui.Parent = bucket
		labelJanitor:Add(gui)

		local bg = Instance.new("Frame")
		bg.Name = "Plate"
		bg.BackgroundColor3 = Color3.fromRGB(10, 6, 20)
		bg.BackgroundTransparency = 0.12
		bg.BorderSizePixel = 0
		bg.Size = UDim2.fromScale(1, 1)
		bg.Parent = gui

		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, 6)
		bgCorner.Parent = bg

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.06, 0)
		pad.PaddingRight = UDim.new(0.06, 0)
		pad.PaddingTop = UDim.new(0.12, 0)
		pad.PaddingBottom = UDim.new(0.12, 0)
		pad.Parent = bg

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.Text = formatMultiplierLabel(multiplier)
		if multiplier < 1 then
			label.TextColor3 = Config.COLORS.NeonMagenta
		elseif multiplier >= risk.maxMultiplier * 0.5 then
			label.TextColor3 = Config.COLORS.NeonLime
		else
			label.TextColor3 = Config.COLORS.Text
		end
		label.Parent = bg

		local sizeConstraint = Instance.new("UITextSizeConstraint")
		sizeConstraint.MaxTextSize = 42
		sizeConstraint.MinTextSize = 8
		sizeConstraint.Parent = label
	end
end

local function rebuildRiskBoard(riskId: string)
	bucketFlashBatch += 1
	PlinkoBallPhysics.cancel()
	PlinkoBallPhysics.rebuildBoard(riskId)
	showLocalMultiplierLabels()
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
			-- Look straight at the board face (world up) so the full peg field stays framed.
			cam.FieldOfView = 70
			cam.CFrame = CFrame.lookAt(target + offset, target, Vector3.yAxis)
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

	activeDropIds[payload.dropId] = nil
	pendingResults = math.max(0, pendingResults - 1)
	if pendingResults <= 0 then
		dropBusy = false
		table.clear(activeDropIds)
		PlinkoPointsHud.setDropEnabled(true)
		PlinkoPointsHud.setDropLabel(dropButtonLabel(currentBallCount))
		PlinkoPointsHud.setStatus("Set wager & balls, then drop")
	else
		PlinkoPointsHud.setStatus(string.format("%d ball(s) still in play…", pendingResults))
	end
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

local function applyLoadout(wager: number, ballCount: number, riskId: string)
	local risk = Config.getPlinkoRisk(riskId)
	local clampedWager = math.clamp(math.floor(wager), Config.PLINKO.MinWager, Config.PLINKO.MaxWager)
	local clampedBalls = math.clamp(
		math.max(Config.PLINKO.MinBallCount, math.floor(ballCount)),
		Config.PLINKO.MinBallCount,
		risk.maxBallCount
	)
	currentRiskId = risk.id
	Remotes.getEvent("PlinkoPointsSetWager"):FireServer(clampedWager, clampedBalls, risk.id)
	currentBallCount = clampedBalls
	PlinkoPointsHud.setLoadoutValues(clampedWager, clampedBalls, risk.id)
	PlinkoPointsHud.setDropLabel(dropButtonLabel(clampedBalls))
	PlinkoPointsHud.setStatus(
		string.format(
			"%s · %d rows · wager %d × %d = %d · max %dx",
			risk.displayName,
			risk.pegRows,
			clampedWager,
			clampedBalls,
			clampedWager * clampedBalls,
			risk.maxMultiplier
		)
	)
	if active then
		rebuildRiskBoard(risk.id)
	end
end

local function startFreeDrop(payload: PlinkoPointsDropStarted)
	table.clear(activeDropIds)
	pendingResults = #payload.dropIds
	currentBallCount = payload.ballCount
	HubHud.setChips(payload.chips)
	PlinkoPointsHud.setDropLabel(dropButtonLabel(payload.ballCount))
	PlinkoPointsHud.setStatus(
		if payload.ballCount > 1 then string.format("Releasing %d balls…", payload.ballCount) else "Ball in play…"
	)
	PlinkoPointsHud.setScoreLine(
		string.format("Wager %d × %d  |  Balance %d", payload.wager, payload.ballCount, payload.chips)
	)

	-- Track local sim completions so cup colors reset when the whole drop batch finishes.
	bucketFlashBatch += 1
	local batchId = bucketFlashBatch
	local ballsLeft = #payload.dropIds
	local function noteBallFinished()
		if batchId ~= bucketFlashBatch then
			return
		end
		ballsLeft = math.max(0, ballsLeft - 1)
		if ballsLeft <= 0 then
			PlinkoBallPhysics.resetBucketsIdle()
		end
	end

	local burstSize = math.max(1, math.floor(payload.burstSize or 1))
	for index, dropId in payload.dropIds do
		activeDropIds[dropId] = true
		local wave = math.floor((index - 1) / burstSize)
		local delaySeconds = wave * payload.staggerSeconds
		task.delay(delaySeconds, function()
			if not active or not activeDropIds[dropId] then
				noteBallFinished()
				return
			end
			PlinkoBallPhysics.drop(function(bucketIndex: number)
				noteBallFinished()
				if not active or not activeDropIds[dropId] then
					return
				end
				Remotes.getEvent("PlinkoPointsLanded"):FireServer(dropId, bucketIndex)
			end)
		end)
	end
end

--[=[
	Hide Plinko HUD and restore default hub camera / title after leaving.
]=]
function PlinkoPointsController.stopSession()
	active = false
	dropBusy = false
	pendingResults = 0
	table.clear(activeDropIds)
	bucketFlashBatch += 1
	sessionNet = 0
	PlinkoBallPhysics.cancel()
	PlinkoBallPhysics.resetBucketsIdle()
	clearLocalMultiplierLabels()
	PlinkoBallPhysics.clearBoard()
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
	pendingResults = 0
	table.clear(activeDropIds)
	sessionNet = 0
	currentBallCount = payload.ballCount
	currentRiskId = payload.riskId

	HubHud.setTitle("Plinko Points")
	HubHud.setChips(payload.chips)
	PlinkoPointsHud.setVisible(true)
	PlinkoPointsHud.setWagerEnabled(true)
	PlinkoPointsHud.setLoadoutValues(payload.wager, payload.ballCount, payload.riskId)
	PlinkoPointsHud.setDropEnabled(true)
	PlinkoPointsHud.setDropLabel(dropButtonLabel(payload.ballCount))
	PlinkoPointsHud.setResult("Drop a ball", Config.COLORS.NeonPurple)
	local risk = Config.getPlinkoRisk(payload.riskId)
	PlinkoPointsHud.setStatus(
		string.format(
			"Risk %s · %d rows · max %dx · ball cap %d",
			risk.displayName,
			risk.pegRows,
			risk.maxMultiplier,
			payload.maxBallCount
		)
	)
	PlinkoPointsHud.setScoreLine(
		string.format(
			"Wager %d × %d  |  Balance %d  |  High score: %d",
			payload.wager,
			payload.ballCount,
			payload.chips,
			payload.highScore
		)
	)
	refreshSessionLine()
	rebuildRiskBoard(payload.riskId)
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

	PlinkoPointsHud.start(requestDrop, requestLeave, applyLoadout)
	applyLoadout(Config.PLINKO.DefaultWager, Config.PLINKO.DefaultBallCount, Config.PLINKO.DefaultRiskId)

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
		pendingResults = 0
		table.clear(activeDropIds)
		bucketFlashBatch += 1
		PlinkoBallPhysics.cancel()
		PlinkoBallPhysics.resetBucketsIdle()
		PlinkoPointsHud.setDropEnabled(true)
		PlinkoPointsHud.setDropLabel(dropButtonLabel(currentBallCount))
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
