--!strict
--[=[
	@class MineSweeperController
	Client controller for Mine Sweeper Arcade: remotes, board camera, leave.

	Scaffold covers join / leave only. Tile input and round HUD land next.
]=]
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Janitor = require(Packages.Janitor)

local Remotes = require(Shared.Remotes)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local MineSweeperHud = require(script.Parent.Parent.ui.MineSweeperHud)
local HubHud = require(script.Parent.Parent.ui.HubHud)

type MineSweeperJoined = Types.MineSweeperJoined

local MineSweeperController = {}

local started = false
local active = false
local cameraJanitor = Janitor.new()
local savedCameraType: Enum.CameraType? = nil
local cameraActive = false

local function getCameraFocus(): BasePart?
	local arena = Workspace:FindFirstChild("MineSweeperArena")
	if not arena then
		return nil
	end
	local focus = arena:FindFirstChild("CameraFocus")
	if focus and focus:IsA("BasePart") then
		return focus
	end
	return nil
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
		local lookAt = target.Position
		local from = lookAt + offset
		cam.CFrame = CFrame.lookAt(from, lookAt)
	end))
end

local function requestLeave()
	Remotes.getEvent("MineSweeperLeave"):FireServer()
end

local function applyLoadout(wager: number, mineCount: number)
	Remotes.getEvent("MineSweeperSetLoadout"):FireServer(wager, mineCount)
end

--[=[
	Tear down HUD / camera and restore hub chrome.
]=]
function MineSweeperController.stopSession()
	if not active then
		return
	end
	active = false
	stopBoardCamera()
	MineSweeperHud.setVisible(false)
	HubHud.setTitle(Config.GAME_NAME)
end

--[=[
	Begin client session from a `MineSweeperJoined` payload.
	@param payload MineSweeperJoined
]=]
function MineSweeperController.startSession(payload: MineSweeperJoined)
	active = true

	HubHud.setTitle("Mine Sweeper Arcade")
	HubHud.setChips(payload.chips)
	MineSweeperHud.setVisible(true)
	MineSweeperHud.setStatus("Arena ready - round play lands next")
	MineSweeperHud.setScoreLine(
		string.format(
			"Wager %d  |  Mines %d  |  Balance %d  |  High score: %d",
			payload.wager,
			payload.mineCount,
			payload.chips,
			payload.highScore
		)
	)
	applyLoadout(payload.wager, payload.mineCount)
	startBoardCamera()
end

--[=[
	Wire HUD callbacks and Mine Sweeper remotes. Idempotent.
]=]
function MineSweeperController.start()
	if started then
		return
	end
	started = true

	MineSweeperHud.start(requestLeave)
	applyLoadout(Config.MINE_SWEEPER.DefaultWager, Config.MINE_SWEEPER.DefaultMines)

	Remotes.getEvent("MineSweeperJoined").OnClientEvent:Connect(function(payload: MineSweeperJoined)
		MineSweeperController.startSession(payload)
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
