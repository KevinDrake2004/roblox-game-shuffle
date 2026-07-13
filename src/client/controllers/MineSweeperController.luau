--!strict
--[=[
	@class MineSweeperController
	Client controller for Mine Sweeper Arcade: remotes, board camera, tile picks.

	Per-player casino Mines: you choose mine count, each gem raises the multiplier,
	cash out anytime after the first safe reveal. Tile colors are local-only.
]=]
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Janitor = require(Packages.Janitor)

local Remotes = require(Shared.Remotes)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local MineSweeperHud = require(script.Parent.Parent.ui.MineSweeperHud)
local HubHud = require(script.Parent.Parent.ui.HubHud)

type MineSweeperJoined = Types.MineSweeperJoined
type MineSweeperRoundState = Types.MineSweeperRoundState
type MineSweeperRevealPayload = Types.MineSweeperRevealPayload
type MineSweeperResultPayload = Types.MineSweeperResultPayload

local MineSweeperController = {}

local started = false
local active = false
local roundActive = false
local currentRoundId = 0
local currentWager = Config.MINE_SWEEPER.DefaultWager
local currentMineCount = Config.MINE_SWEEPER.DefaultMines
local sessionNet = 0

local cameraJanitor = Janitor.new()
local inputJanitor = Janitor.new()
local savedCameraType: Enum.CameraType? = nil
local cameraActive = false

local tileIdleColors: { [BasePart]: Color3 } = {}
local tileIdleMaterials: { [BasePart]: Enum.Material } = {}
local revealedTiles: { [number]: boolean } = {}
local hoveredTileIndex: number? = nil

local GEM_COLOR = Config.COLORS.NeonLime
local MINE_COLOR = Config.COLORS.NeonMagenta
local HOVER_COLOR = Color3.fromRGB(255, 150, 210)
local IDLE_A = Color3.fromRGB(89, 20, 56)
local IDLE_B = Color3.fromRGB(140, 31, 89)

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
	return Config.COLORS.NeonMagenta
end

local function refreshSessionLine()
	MineSweeperHud.setSessionLine(string.format("Session: %s", formatNetDelta(sessionNet)), sessionColor())
end

local function getArena(): Folder?
	local arena = Workspace:FindFirstChild("MineSweeperArena")
	if arena and arena:IsA("Folder") then
		return arena
	end
	return nil
end

local function getTilesFolder(): Folder?
	local arena = getArena()
	if not arena then
		return nil
	end
	local tiles = arena:FindFirstChild("Tiles")
	if tiles and tiles:IsA("Folder") then
		return tiles
	end
	return nil
end

local function getCameraFocus(): BasePart?
	local arena = getArena()
	if not arena then
		return nil
	end
	local focus = arena:FindFirstChild("CameraFocus")
	if focus and focus:IsA("BasePart") then
		return focus
	end
	return nil
end

local function cacheIdleTileLooks()
	table.clear(tileIdleColors)
	table.clear(tileIdleMaterials)
	local tiles = getTilesFolder()
	if not tiles then
		return
	end
	for _, child in tiles:GetChildren() do
		if child:IsA("BasePart") then
			tileIdleColors[child] = child.Color
			tileIdleMaterials[child] = child.Material
		end
	end
end

local function resetBoardVisuals()
	table.clear(revealedTiles)
	hoveredTileIndex = nil
	local tiles = getTilesFolder()
	if not tiles then
		return
	end
	for _, child in tiles:GetChildren() do
		if child:IsA("BasePart") then
			local index = child:GetAttribute("TileIndex")
			if typeof(index) == "number" then
				local row = math.floor(index / Config.MINE_SWEEPER.GridSize)
				local col = index % Config.MINE_SWEEPER.GridSize
				child.Color = tileIdleColors[child] or (if (row + col) % 2 == 0 then IDLE_A else IDLE_B)
				child.Material = tileIdleMaterials[child] or Enum.Material.SmoothPlastic
			end
		end
	end
end

local function getTilePart(tileIndex: number): BasePart?
	local tiles = getTilesFolder()
	if not tiles then
		return nil
	end
	local part = tiles:FindFirstChild(`Tile_{tileIndex}`)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function idleColorFor(tileIndex: number, part: BasePart): Color3
	local row = math.floor(tileIndex / Config.MINE_SWEEPER.GridSize)
	local col = tileIndex % Config.MINE_SWEEPER.GridSize
	return tileIdleColors[part] or (if (row + col) % 2 == 0 then IDLE_A else IDLE_B)
end

local function paintTile(tileIndex: number, color: Color3, neon: boolean?)
	local part = getTilePart(tileIndex)
	if part then
		part.Color = color
		part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local function restoreUnrevealedTile(tileIndex: number)
	if revealedTiles[tileIndex] then
		return
	end
	local part = getTilePart(tileIndex)
	if not part then
		return
	end
	part.Color = idleColorFor(tileIndex, part)
	part.Material = tileIdleMaterials[part] or Enum.Material.SmoothPlastic
end

local function setHoveredTile(tileIndex: number?)
	if hoveredTileIndex == tileIndex then
		return
	end
	if hoveredTileIndex ~= nil then
		restoreUnrevealedTile(hoveredTileIndex)
	end
	hoveredTileIndex = tileIndex
	if tileIndex ~= nil and not revealedTiles[tileIndex] then
		paintTile(tileIndex, HOVER_COLOR, false)
	end
end

local function markRevealed(tileIndex: number, color: Color3)
	if hoveredTileIndex == tileIndex then
		hoveredTileIndex = nil
	end
	revealedTiles[tileIndex] = true
	paintTile(tileIndex, color, true)
end

local function stopBoardCamera()
	cameraJanitor:Cleanup()
	cameraActive = false
	local camera = Workspace.CurrentCamera
	if camera and savedCameraType then
		camera.CameraType = savedCameraType
	end
	savedCameraType = nil
end

local function startBoardCamera()
	local focus = getCameraFocus()
	local camera = Workspace.CurrentCamera
	if not focus or not camera then
		return
	end

	stopBoardCamera()
	savedCameraType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	cameraActive = true

	local offset = Config.MINE_SWEEPER.CameraOffset
	cameraJanitor:Add(RunService.RenderStepped:Connect(function()
		if not cameraActive then
			return
		end
		local cam = Workspace.CurrentCamera
		local target = getCameraFocus()
		if not cam or not target then
			return
		end
		-- Top-down only. lookAt needs a non-Y up vector when the look axis is vertical;
		-- -Z keeps the spawn side toward the bottom of the screen.
		local lookAt = target.Position
		local from = lookAt + offset
		cam.CFrame = CFrame.lookAt(from, lookAt, -Vector3.zAxis)
	end))
end

local function setIdleHud()
	roundActive = false
	currentRoundId = 0
	MineSweeperHud.setLoadoutEnabled(true)
	MineSweeperHud.setStartEnabled(true)
	MineSweeperHud.setCashOutEnabled(false)
	MineSweeperHud.setMultiplier(1)
	MineSweeperHud.setResult("Pick gems · cash out anytime", Config.COLORS.NeonMagenta)
	MineSweeperHud.setStatus(
		string.format("Wager %d · %d mines · click a tile after start", currentWager, currentMineCount)
	)
	resetBoardVisuals()
end

local function applyLoadout(wager: number, mineCount: number)
	currentWager = wager
	currentMineCount = mineCount
	Remotes.getEvent("MineSweeperSetLoadout"):FireServer(wager, mineCount)
	if not roundActive then
		MineSweeperHud.setStatus(
			string.format("Wager %d · %d mines · click a tile after start", currentWager, currentMineCount)
		)
		MineSweeperHud.setScoreLine("Balance ready · High risk mines raise gem mult")
	end
end

local function requestStart()
	if roundActive then
		return
	end
	Remotes.getEvent("MineSweeperStartRound"):FireServer()
end

local function requestCashOut()
	if not roundActive or currentRoundId <= 0 then
		return
	end
	Remotes.getEvent("MineSweeperCashOut"):FireServer(currentRoundId)
end

local function requestLeave()
	Remotes.getEvent("MineSweeperLeave"):FireServer()
end

local function requestReveal(tileIndex: number)
	if not roundActive or currentRoundId <= 0 then
		return
	end
	Remotes.getEvent("MineSweeperReveal"):FireServer(currentRoundId, tileIndex)
end

local function raycastTileIndex(screenPos: Vector2): number?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	-- ScreenPointToRay matches GetMouseLocation (includes Gui inset).
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local tiles = getTilesFolder()
	if not tiles then
		return nil
	end
	params.FilterDescendantsInstances = { tiles }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 250, params)
	if not result or not result.Instance then
		return nil
	end
	local part = result.Instance
	if not part:IsA("BasePart") then
		return nil
	end
	local index = part:GetAttribute("TileIndex")
	if typeof(index) == "number" then
		return index
	end
	return nil
end

local function mouseOverInteractiveGui(screenPos: Vector2): boolean
	local inset = GuiService:GetGuiInset()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	local objects = playerGui:GetGuiObjectsAtPosition(screenPos.X - inset.X, screenPos.Y - inset.Y)
	for _, obj in objects do
		if obj:IsA("GuiButton") or obj:IsA("TextBox") then
			return true
		end
	end
	return false
end

local function bindTileInput()
	inputJanitor:Cleanup()

	inputJanitor:Add(RunService.RenderStepped:Connect(function()
		if not active then
			setHoveredTile(nil)
			return
		end
		if mouseOverInteractiveGui(UserInputService:GetMouseLocation()) then
			setHoveredTile(nil)
			return
		end
		local tileIndex = raycastTileIndex(UserInputService:GetMouseLocation())
		if tileIndex ~= nil and revealedTiles[tileIndex] then
			setHoveredTile(nil)
			return
		end
		-- Hover highlight while in arena (idle preview + live round).
		setHoveredTile(tileIndex)
	end))

	inputJanitor:Add(UserInputService.InputBegan:Connect(function(input, _gameProcessed)
		if not active or not roundActive then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local mouse = UserInputService:GetMouseLocation()
		if mouseOverInteractiveGui(mouse) then
			return
		end
		local tileIndex = raycastTileIndex(mouse)
		if tileIndex ~= nil and not revealedTiles[tileIndex] then
			requestReveal(tileIndex)
		end
	end))
end

local function onRoundStarted(payload: MineSweeperRoundState)
	if not active then
		return
	end
	roundActive = true
	currentRoundId = payload.roundId
	currentWager = payload.wager
	currentMineCount = payload.mineCount
	resetBoardVisuals()
	for _, tileIndex in payload.revealedTiles do
		markRevealed(tileIndex, GEM_COLOR)
	end
	MineSweeperHud.setLoadoutEnabled(false)
	MineSweeperHud.setStartEnabled(false)
	MineSweeperHud.setCashOutEnabled(payload.revealedCount >= 1)
	MineSweeperHud.setMultiplier(payload.multiplier)
	MineSweeperHud.setResult("Reveal gems - avoid mines", Config.COLORS.NeonLime)
	MineSweeperHud.setStatus(string.format("%d mines hidden · click tiles · cash out when ready", payload.mineCount))
	MineSweeperHud.setScoreLine(
		string.format("Wager %d  |  Gems %d  |  Balance %d", payload.wager, payload.revealedCount, payload.chips)
	)
	HubHud.setChips(payload.chips)
end

local function onTileRevealed(payload: MineSweeperRevealPayload)
	if not active or payload.roundId ~= currentRoundId then
		return
	end
	if payload.safe then
		markRevealed(payload.tileIndex, GEM_COLOR)
		MineSweeperHud.setMultiplier(payload.multiplier)
		MineSweeperHud.setCashOutEnabled(true)
		MineSweeperHud.setResult(string.format("Gem! %.2fx", payload.multiplier), Config.COLORS.NeonLime)
		MineSweeperHud.setStatus(string.format("%d gems safe · cash out or keep going", payload.revealedCount))
		MineSweeperHud.setScoreLine(
			string.format(
				"Wager %d  |  Gems %d  |  Mult %.2fx",
				currentWager,
				payload.revealedCount,
				payload.multiplier
			)
		)
	end
end

local function onResult(payload: MineSweeperResultPayload)
	if not active then
		return
	end

	if payload.outcome == "mine_hit" and payload.hitTile ~= nil then
		markRevealed(payload.hitTile, MINE_COLOR)
	end

	sessionNet += payload.netDelta
	refreshSessionLine()
	HubHud.setChips(payload.chips)

	if payload.outcome == "cashed_out" then
		MineSweeperHud.setResult(
			string.format("CASH OUT +%d (%.2fx)", payload.payout, payload.multiplier),
			Config.COLORS.NeonLime
		)
		MineSweeperHud.setStatus(string.format("Banked %d chips · play again or leave", payload.payout))
	else
		MineSweeperHud.setResult(
			string.format("MINE HIT %s", formatNetDelta(payload.netDelta)),
			Config.COLORS.NeonMagenta
		)
		MineSweeperHud.setStatus("Stake lost · adjust mines or try again")
	end
	MineSweeperHud.setScoreLine(
		string.format(
			"Wager %d  |  Gems %d  |  Balance %d  |  High %d",
			payload.wager,
			payload.revealedCount,
			payload.chips,
			payload.highScore
		)
	)
	MineSweeperHud.flashOutcome(payload.outcome)
	setIdleHud()
end

--[=[
	Tear down HUD / camera and restore hub chrome.
]=]
function MineSweeperController.stopSession()
	if not active then
		return
	end
	active = false
	roundActive = false
	inputJanitor:Cleanup()
	stopBoardCamera()
	resetBoardVisuals()
	MineSweeperHud.setVisible(false)
	HubHud.setTitle(Config.GAME_NAME)
end

--[=[
	Begin client session from a `MineSweeperJoined` payload.
	@param payload MineSweeperJoined
]=]
function MineSweeperController.startSession(payload: MineSweeperJoined)
	active = true
	sessionNet = 0
	currentWager = payload.wager
	currentMineCount = payload.mineCount
	cacheIdleTileLooks()

	HubHud.setTitle("Mine Sweeper Arcade")
	HubHud.setChips(payload.chips)
	MineSweeperHud.setVisible(true)
	MineSweeperHud.setLoadoutValues(payload.wager, payload.mineCount)
	MineSweeperHud.setScoreLine(string.format("Balance %d  |  High score: %d", payload.chips, payload.highScore))
	refreshSessionLine()
	applyLoadout(payload.wager, payload.mineCount)
	setIdleHud()
	startBoardCamera()
	bindTileInput()
end

--[=[
	Wire HUD callbacks and Mine Sweeper remotes. Idempotent.
]=]
function MineSweeperController.start()
	if started then
		return
	end
	started = true

	MineSweeperHud.start(requestStart, requestCashOut, requestLeave, applyLoadout)
	applyLoadout(Config.MINE_SWEEPER.DefaultWager, Config.MINE_SWEEPER.DefaultMines)

	Remotes.getEvent("MineSweeperJoined").OnClientEvent:Connect(function(payload: MineSweeperJoined)
		MineSweeperController.startSession(payload)
	end)

	Remotes.getEvent("MineSweeperRoundStarted").OnClientEvent:Connect(function(payload: MineSweeperRoundState)
		onRoundStarted(payload)
	end)

	Remotes.getEvent("MineSweeperTileRevealed").OnClientEvent:Connect(function(payload: MineSweeperRevealPayload)
		onTileRevealed(payload)
	end)

	Remotes.getEvent("MineSweeperResult").OnClientEvent:Connect(function(payload: MineSweeperResultPayload)
		onResult(payload)
	end)

	Remotes.getEvent("MineSweeperRejected").OnClientEvent:Connect(function(payload: { reason: string })
		MineSweeperHud.setStatus(payload.reason or "Action rejected")
		MineSweeperHud.setResult("Blocked", Config.COLORS.NeonMagenta)
		if not roundActive then
			MineSweeperHud.setStartEnabled(true)
			MineSweeperHud.setLoadoutEnabled(true)
		end
	end)

	Remotes.getEvent("PortalResult").OnClientEvent:Connect(function(payload: Types.PortalResultPayload)
		if payload.gameId == "MineSweeper" and payload.status == "enter" then
			MineSweeperHud.setVisible(true)
			MineSweeperHud.setStatus("Entering Mine Sweeper Arcade…")
			HubHud.setTitle("Mine Sweeper Arcade")
		end
	end)

	Remotes.getEvent("MineSweeperLeft").OnClientEvent:Connect(function()
		MineSweeperController.stopSession()
	end)
end

return MineSweeperController
