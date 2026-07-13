--!strict
--[=[
	@class MineSweeper
	Server-authoritative Mine Sweeper Arcade: per-player rounds on a 5x5 grid.

	## Flow (scaffold)

	1. Lobby portal → `MineSweeper.join` teleports into `Workspace.MineSweeperArena`.
	2. Client may set loadout via `MineSweeperSetLoadout` (clamped to Config).
	3. Leave returns the player to `Config.LOBBY.SpawnPosition`.

	Round start / reveal / cash-out land in a follow-up commit. Remotes and types
	are registered so the client can wire without another shared-layer pass.

	## Economy (target)

	- Stake deducted on round start; mine hit loses the stake.
	- Cash-out: `payout = floor(wager * multiplier * PlayerReturnFactor)`.
	- Multiplier uses conditional survival odds (see `docs/MINES.md`).

	Arena geometry lives only under `Workspace.MineSweeperArena` (west of Rocket Run).
]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Janitor = require(Packages.Janitor)

local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local CurrencyService = require(script.Parent.Parent.services.CurrencyService)
local DataService = require(script.Parent.Parent.services.DataService)

type MineSweeperLoadout = Types.MineSweeperLoadout
type MineSweeperJoined = Types.MineSweeperJoined

local MineSweeper = {}

local ARENA_NAME = "MineSweeperArena"
local started = false

local playersInArena: { [Player]: boolean } = {}
local loadouts: { [Player]: MineSweeperLoadout } = {}
local playerJanitors: { [Player]: any } = {}

local spawnPart: BasePart? = nil
local tilesFolder: Folder? = nil
local titleSign: BasePart? = nil

local function clampWager(rawWager: unknown): number
	local cfg = Config.MINE_SWEEPER
	local wager = math.floor(tonumber(rawWager) or cfg.DefaultWager)
	return math.clamp(wager, cfg.MinWager, cfg.MaxWager)
end

local function clampMineCount(rawCount: unknown): number
	local cfg = Config.MINE_SWEEPER
	local count = math.floor(tonumber(rawCount) or cfg.DefaultMines)
	return math.clamp(count, cfg.MinMines, cfg.MaxMines)
end

local function clampLoadout(rawWager: unknown, rawMineCount: unknown): MineSweeperLoadout
	return {
		wager = clampWager(rawWager),
		mineCount = clampMineCount(rawMineCount),
	}
end

local function getLoadout(player: Player): MineSweeperLoadout
	return loadouts[player] or clampLoadout(nil, nil)
end

local function teleportTo(player: Player, position: Vector3)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	end
end

local function ensureTitleSign()
	if not titleSign then
		return
	end

	local existing = titleSign:FindFirstChild("SignGui")
	if existing then
		existing:Destroy()
	end

	titleSign.Color = Color3.fromRGB(24, 8, 20)
	titleSign.Material = Enum.Material.SmoothPlastic

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 2.5
	gui.Parent = titleSign

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.BackgroundColor3 = Color3.fromRGB(18, 6, 16)
	plate.BackgroundTransparency = 0.05
	plate.BorderSizePixel = 0
	plate.Size = UDim2.fromScale(1, 1)
	plate.Parent = gui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Config.COLORS.NeonMagenta
	title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	title.TextStrokeTransparency = 0
	title.Text = "MINE SWEEPER"
	title.Parent = plate

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = plate

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.COLORS.Text
	stroke.Thickness = 2.5
	stroke.Parent = title
end

local function resolveArena(): boolean
	if spawnPart and tilesFolder then
		return true
	end

	local arena = Workspace:FindFirstChild(ARENA_NAME)
	if not (arena and arena:IsA("Folder")) then
		warn("[MineSweeper] Workspace.MineSweeperArena is missing")
		return false
	end

	local pad = arena:FindFirstChild("SpawnPad")
	local tiles = arena:FindFirstChild("Tiles")
	local sign = arena:FindFirstChild("TitleSign")

	if not (pad and pad:IsA("BasePart")) then
		warn("[MineSweeper] Arena is missing SpawnPad")
		return false
	end
	if not (tiles and tiles:IsA("Folder")) then
		warn("[MineSweeper] Arena is missing Tiles folder")
		return false
	end

	spawnPart = pad
	tilesFolder = tiles
	titleSign = if sign and sign:IsA("BasePart") then sign else nil

	ensureTitleSign()
	return true
end

local function joinedPayload(player: Player): MineSweeperJoined
	local loadout = getLoadout(player)
	return {
		wager = loadout.wager,
		mineCount = loadout.mineCount,
		chips = CurrencyService.getChips(player),
		highScore = DataService.getHighScore(player, "MineSweeper"),
	}
end

--[=[
	Teleport the player into the Mine Sweeper arena and bootstrap their client HUD.
	@param player Player
]=]
function MineSweeper.join(player: Player)
	if not resolveArena() or not spawnPart then
		return
	end

	playersInArena[player] = true
	teleportTo(player, spawnPart.Position)

	local oldJanitor = playerJanitors[player]
	if oldJanitor then
		oldJanitor:Destroy()
	end
	local janitor = Janitor.new()
	playerJanitors[player] = janitor
	janitor:Add(
		player.CharacterAdded:Connect(function()
			task.defer(function()
				if playersInArena[player] and spawnPart then
					teleportTo(player, spawnPart.Position)
				end
			end)
		end),
		"Disconnect"
	)

	Remotes.getEvent("MineSweeperJoined"):FireClient(player, joinedPayload(player))
end

--[=[
	Remove the player from the arena and return them to the lobby spawn.
	@param player Player
]=]
function MineSweeper.leave(player: Player)
	if not playersInArena[player] then
		return
	end
	playersInArena[player] = nil

	local janitor = playerJanitors[player]
	if janitor then
		janitor:Destroy()
		playerJanitors[player] = nil
	end

	teleportTo(player, Config.LOBBY.SpawnPosition)
	Remotes.getEvent("MineSweeperLeft"):FireClient(player)
end

--[=[
	Whether the player is currently inside the Mine Sweeper arena.
	@param player Player
	@return boolean
]=]
function MineSweeper.isPlaying(player: Player): boolean
	return playersInArena[player] == true
end

--[=[
	Resolve the arena, bind remotes, and prepare the title sign.
]=]
function MineSweeper.start()
	if started then
		return
	end
	started = true

	if not resolveArena() then
		return
	end

	if spawnPart then
		local leavePrompt = spawnPart:FindFirstChild("LeavePrompt")
		if leavePrompt and leavePrompt:IsA("ProximityPrompt") then
			leavePrompt.Triggered:Connect(function(player: Player)
				MineSweeper.leave(player)
			end)
		end
	end

	Remotes.getEvent("MineSweeperSetLoadout").OnServerEvent
		:Connect(function(player: Player, wager: unknown, mineCount: unknown)
			if not playersInArena[player] then
				return
			end
			loadouts[player] = clampLoadout(wager, mineCount)
		end)

	Remotes.getEvent("MineSweeperLeave").OnServerEvent:Connect(function(player: Player)
		MineSweeper.leave(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playersInArena[player] = nil
		loadouts[player] = nil
		local janitor = playerJanitors[player]
		if janitor then
			janitor:Destroy()
			playerJanitors[player] = nil
		end
	end)
end

return MineSweeper
