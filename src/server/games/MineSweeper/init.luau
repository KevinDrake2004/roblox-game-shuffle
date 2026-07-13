--!strict
--[=[
	@class MineSweeper
	Server-authoritative Mine Sweeper Arcade: per-player casino Mines rounds.

	## Flow

	1. Lobby portal → `MineSweeper.join` teleports into `Workspace.MineSweeperArena`.
	2. Player sets wager + mine count (1-24) via `MineSweeperSetLoadout`.
	3. `MineSweeperStartRound` deducts wager and places a **private** mine layout (RNG).
	4. Each safe reveal raises the multiplier (conditional survival odds).
	5. Cash out after ≥1 gem, or hit a mine and lose the stake.
	6. Leave returns to lobby (active round stake is forfeited - no refund).

	Not Windows Minesweeper: no adjacency numbers, no shared board. Closer to
	Shuffle/Stake Mines - pick risk (mine count), flip gems, cash out anytime.

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
type MineSweeperRoundState = Types.MineSweeperRoundState
type MineSweeperRevealPayload = Types.MineSweeperRevealPayload
type MineSweeperResultPayload = Types.MineSweeperResultPayload

type RoundSession = {
	roundId: number,
	wager: number,
	mineCount: number,
	mines: { [number]: boolean },
	revealed: { [number]: boolean },
	revealedTiles: { number },
	revealedCount: number,
	multiplier: number,
	settled: boolean,
}

local MineSweeper = {}

local ARENA_NAME = "MineSweeperArena"
local rng = Random.new()
local started = false
local nextRoundId = 1

local playersInArena: { [Player]: boolean } = {}
local loadouts: { [Player]: MineSweeperLoadout } = {}
local rounds: { [Player]: RoundSession } = {}
local playerJanitors: { [Player]: any } = {}

local spawnPart: BasePart? = nil
local tilesFolder: Folder? = nil
local titleSign: BasePart? = nil

local function tileCount(): number
	local size = Config.MINE_SWEEPER.GridSize
	return size * size
end

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

-- Rooms are inside the casino: only snap to the pad if the player is still outside the room.
local function teleportIntoRoom(player: Player, position: Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and (root.Position - position).Magnitude < 45 then
		return
	end
	teleportTo(player, position)
end

local function reject(player: Player, reason: string)
	Remotes.getEvent("MineSweeperRejected"):FireClient(player, { reason = reason })
end

local function cashOutPayout(wager: number, multiplier: number): number
	return math.floor(wager * multiplier * Config.MINE_SWEEPER.PlayerReturnFactor)
end

local function placeMines(mineCount: number): { [number]: boolean }
	local n = tileCount()
	local indices = table.create(n)
	for i = 0, n - 1 do
		indices[i + 1] = i
	end
	-- Fisher-Yates shuffle, then take the first mineCount indices.
	for i = n, 2, -1 do
		local j = rng:NextInteger(1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end
	local mines: { [number]: boolean } = {}
	for i = 1, mineCount do
		mines[indices[i]] = true
	end
	return mines
end

local function roundStatePayload(player: Player, session: RoundSession): MineSweeperRoundState
	return {
		roundId = session.roundId,
		phase = if session.settled then "settled" else "playing",
		wager = session.wager,
		mineCount = session.mineCount,
		revealedCount = session.revealedCount,
		multiplier = session.multiplier,
		revealedTiles = table.clone(session.revealedTiles),
		chips = CurrencyService.getChips(player),
	}
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

local function clearRound(player: Player)
	rounds[player] = nil
end

local function settleCashOut(player: Player, session: RoundSession)
	if session.settled or session.revealedCount < 1 then
		return
	end
	session.settled = true

	local wager = session.wager
	local multiplier = session.multiplier
	local payout = cashOutPayout(wager, multiplier)
	CurrencyService.creditPayout(player, payout, wager, "MineSweeper:payout")
	local netDelta = payout - wager
	local highScore = DataService.setHighScore(player, "MineSweeper", payout)

	local payload: MineSweeperResultPayload = {
		roundId = session.roundId,
		outcome = "cashed_out",
		wager = wager,
		mineCount = session.mineCount,
		revealedCount = session.revealedCount,
		multiplier = multiplier,
		payout = payout,
		netDelta = netDelta,
		highScore = highScore,
		chips = CurrencyService.getChips(player),
		hitTile = nil,
	}
	clearRound(player)
	Remotes.getEvent("MineSweeperResult"):FireClient(player, payload)
end

local function settleMineHit(player: Player, session: RoundSession, tileIndex: number)
	if session.settled then
		return
	end
	session.settled = true

	local wager = session.wager
	local payload: MineSweeperResultPayload = {
		roundId = session.roundId,
		outcome = "mine_hit",
		wager = wager,
		mineCount = session.mineCount,
		revealedCount = session.revealedCount,
		multiplier = session.multiplier,
		payout = 0,
		netDelta = -wager,
		highScore = DataService.getHighScore(player, "MineSweeper"),
		chips = CurrencyService.getChips(player),
		hitTile = tileIndex,
	}
	clearRound(player)
	Remotes.getEvent("MineSweeperResult"):FireClient(player, payload)
end

local function beginRound(player: Player)
	if not playersInArena[player] then
		return
	end
	if rounds[player] then
		reject(player, "Round already in progress")
		return
	end

	local loadout = getLoadout(player)
	local wager = loadout.wager
	local mineCount = loadout.mineCount
	if CurrencyService.getChips(player) < wager then
		reject(player, string.format("Need %d chips to start", wager))
		return
	end

	local deducted = CurrencyService.deductChips(player, wager, "MineSweeper:wager")
	if not deducted then
		reject(player, string.format("Need %d chips to start", wager))
		return
	end

	local roundId = nextRoundId
	nextRoundId += 1
	local session: RoundSession = {
		roundId = roundId,
		wager = wager,
		mineCount = mineCount,
		mines = placeMines(mineCount),
		revealed = {},
		revealedTiles = {},
		revealedCount = 0,
		multiplier = 1,
		settled = false,
	}
	rounds[player] = session
	Remotes.getEvent("MineSweeperRoundStarted"):FireClient(player, roundStatePayload(player, session))
end

local function handleReveal(player: Player, rawRoundId: unknown, rawTileIndex: unknown)
	local session = rounds[player]
	if not session or session.settled then
		return
	end
	if typeof(rawRoundId) ~= "number" or rawRoundId ~= session.roundId then
		return
	end
	if typeof(rawTileIndex) ~= "number" then
		return
	end
	if not playersInArena[player] then
		return
	end

	local n = tileCount()
	local tileIndex = math.floor(rawTileIndex)
	if tileIndex < 0 or tileIndex >= n then
		reject(player, "Invalid tile")
		return
	end
	if session.revealed[tileIndex] then
		reject(player, "Tile already revealed")
		return
	end

	if session.mines[tileIndex] then
		settleMineHit(player, session, tileIndex)
		return
	end

	session.revealed[tileIndex] = true
	table.insert(session.revealedTiles, tileIndex)
	session.revealedCount += 1
	session.multiplier = Config.mineSweeperMultiplier(session.revealedCount, session.mineCount)

	local revealPayload: MineSweeperRevealPayload = {
		roundId = session.roundId,
		tileIndex = tileIndex,
		safe = true,
		revealedCount = session.revealedCount,
		multiplier = session.multiplier,
	}
	Remotes.getEvent("MineSweeperTileRevealed"):FireClient(player, revealPayload)

	-- All gems cleared → auto cash out at max multiplier.
	local maxSafe = n - session.mineCount
	if session.revealedCount >= maxSafe then
		settleCashOut(player, session)
	end
end

local function handleCashOut(player: Player, rawRoundId: unknown)
	local session = rounds[player]
	if not session or session.settled then
		return
	end
	if typeof(rawRoundId) ~= "number" or rawRoundId ~= session.roundId then
		return
	end
	if session.revealedCount < 1 then
		reject(player, "Reveal at least one gem before cashing out")
		return
	end
	settleCashOut(player, session)
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
	teleportIntoRoom(player, spawnPart.Position)

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
					teleportIntoRoom(player, spawnPart.Position)
				end
			end)
		end),
		"Disconnect"
	)

	Remotes.getEvent("MineSweeperJoined"):FireClient(player, joinedPayload(player))
end

--[=[
	Remove the player from the arena and return them to the casino corridor.
	Active round stake is forfeited (already deducted; no refund).
	@param player Player
]=]
function MineSweeper.leave(player: Player)
	if not playersInArena[player] then
		return
	end
	playersInArena[player] = nil
	clearRound(player)

	local janitor = playerJanitors[player]
	if janitor then
		janitor:Destroy()
		playerJanitors[player] = nil
	end

	teleportTo(player, Config.MINE_SWEEPER.LeavePosition)
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
			-- Loadout applies to the next round; ignore mid-round edits.
			if rounds[player] then
				return
			end
			loadouts[player] = clampLoadout(wager, mineCount)
		end)

	Remotes.getEvent("MineSweeperStartRound").OnServerEvent:Connect(function(player: Player)
		beginRound(player)
	end)

	Remotes.getEvent("MineSweeperReveal").OnServerEvent
		:Connect(function(player: Player, roundId: unknown, tileIndex: unknown)
			handleReveal(player, roundId, tileIndex)
		end)

	Remotes.getEvent("MineSweeperCashOut").OnServerEvent:Connect(function(player: Player, roundId: unknown)
		handleCashOut(player, roundId)
	end)

	Remotes.getEvent("MineSweeperLeave").OnServerEvent:Connect(function(player: Player)
		MineSweeper.leave(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playersInArena[player] = nil
		loadouts[player] = nil
		-- Disconnect mid-round: stake already taken; do not refund.
		clearRound(player)
		local janitor = playerJanitors[player]
		if janitor then
			janitor:Destroy()
			playerJanitors[player] = nil
		end
	end)
end

return MineSweeper
