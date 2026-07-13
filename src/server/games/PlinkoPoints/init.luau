--!strict
--[=[
	@class PlinkoPoints
	Server-authoritative Plinko Points: wager per ball drop, weighted bucket settle.

	## Flow

	1. Lobby portal → `PlinkoPoints.join` teleports into `Workspace.PlinkoArena`.
	2. Client sets wager via `PlinkoPointsSetWager` (clamped to Config).
	3. `PlinkoPointsDrop` deducts the wager, rolls a weighted bucket, credits payout.
	4. Leave returns the player to `Config.LOBBY.SpawnPosition`.

	## Economy

	- Wager deducted with `CurrencyService.deductChips` before the roll.
	- Insufficient balance → drop rejected (no roll).
	- `payout = floor(wager * bucketMultiplier * PlayerReturnFactor)` via `creditPayout`.
	- Zero-multiplier (center) buckets are busts: stake gone, `payout = 0`.
	- Target RTP > 100% via `Config.PLINKO.TargetRTP` / `PlayerReturnFactor` and
	  tuned `BucketMultipliers` × `BucketWeights` (E[multiplier] ≈ 1.0 before factor).

	Arena geometry lives only under `Workspace.PlinkoArena` (east of Rocket Run).
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

type PlinkoPointsLoadout = Types.PlinkoPointsLoadout
type PlinkoPointsJoined = Types.PlinkoPointsJoined
type PlinkoPointsResultPayload = Types.PlinkoPointsResultPayload

local PlinkoPoints = {}

local ARENA_NAME = "PlinkoArena"
local rng = Random.new()
local started = false
local nextDropId = 1

local playersInArena: { [Player]: boolean } = {}
local loadouts: { [Player]: PlinkoPointsLoadout } = {}
local lastDropAt: { [Player]: number } = {}
local dropping: { [Player]: boolean } = {}
local playerJanitors: { [Player]: any } = {}

local spawnPart: BasePart? = nil
local dropOrigin: BasePart? = nil
local bucketsFolder: Folder? = nil
local pegsFolder: Folder? = nil
local titleSign: BasePart? = nil

local weightTotal = 0

local function refreshWeightTotal()
	weightTotal = 0
	for _, weight in Config.PLINKO.BucketWeights do
		weightTotal += weight
	end
end

local function clampWager(rawWager: unknown): number
	local cfg = Config.PLINKO
	local wager = math.floor(tonumber(rawWager) or cfg.DefaultWager)
	return math.clamp(wager, cfg.MinWager, cfg.MaxWager)
end

local function getLoadout(player: Player): PlinkoPointsLoadout
	return loadouts[player] or { wager = Config.PLINKO.DefaultWager }
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

local function rollBucketIndex(): number
	local roll = rng:NextNumber(0, weightTotal)
	local cumulative = 0
	local multipliers = Config.PLINKO.BucketMultipliers
	local weights = Config.PLINKO.BucketWeights
	for index = 1, #weights do
		cumulative += weights[index]
		if roll <= cumulative then
			return index
		end
	end
	return #multipliers
end

local function settleOutcome(payout: number, netDelta: number): "win" | "bust" | "loss" | "push"
	if payout <= 0 then
		return "bust"
	end
	if netDelta > 0 then
		return "win"
	end
	if netDelta < 0 then
		return "loss"
	end
	return "push"
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

local function ensureBucketLabels()
	if not bucketsFolder then
		return
	end

	local multipliers = Config.PLINKO.BucketMultipliers
	for index, multiplier in multipliers do
		local bucket = bucketsFolder:FindFirstChild(`Bucket_{index - 1}`)
		if not (bucket and bucket:IsA("BasePart")) then
			continue
		end

		local gui = bucket:FindFirstChild("MultiplierGui")
		if not (gui and gui:IsA("BillboardGui")) then
			gui = Instance.new("BillboardGui")
			gui.Name = "MultiplierGui"
			gui.Size = UDim2.fromOffset(72, 36)
			gui.StudsOffset = Vector3.new(0, 1.6, 0)
			gui.AlwaysOnTop = true
			gui.Parent = bucket

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = true
			label.TextColor3 = Config.COLORS.Text
			label.TextStrokeTransparency = 0.35
			label.Parent = gui

			local stroke = Instance.new("UIStroke")
			stroke.Color = Config.COLORS.NeonPurple
			stroke.Thickness = 1.5
			stroke.Parent = label
		end

		local label = gui:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = formatMultiplierLabel(multiplier)
			if multiplier <= 0 then
				label.TextColor3 = Config.COLORS.NeonMagenta
			elseif multiplier >= 4 then
				label.TextColor3 = Config.COLORS.NeonLime
			else
				label.TextColor3 = Config.COLORS.Text
			end
		end
	end
end

local function ensureTitleSign()
	if not titleSign then
		return
	end
	if titleSign:FindFirstChild("SignGui") then
		return
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = titleSign

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Config.COLORS.Text
	title.Text = "PLINKO POINTS"
	title.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.COLORS.NeonPurple
	stroke.Thickness = 2
	stroke.Parent = title
end

local function ensurePegs()
	if not pegsFolder or not dropOrigin then
		return
	end
	if pegsFolder:FindFirstChild("Peg_0_0") then
		return
	end

	local origin = Config.PLINKO.ArenaOrigin
	local rows = Config.PLINKO.PegRows
	local boardZ = dropOrigin.Position.Z
	local topY = dropOrigin.Position.Y - 2
	local spacingX = 2.6
	local spacingY = 2.4
	for row = 0, rows - 1 do
		local pegsInRow = 5 + (row % 2)
		local rowWidth = (pegsInRow - 1) * spacingX
		local startX = origin.X - rowWidth / 2
		local y = topY - row * spacingY
		for col = 0, pegsInRow - 1 do
			local peg = Instance.new("Part")
			peg.Name = `Peg_{row}_{col}`
			peg.Shape = Enum.PartType.Ball
			peg.Anchored = true
			peg.CanCollide = false
			peg.CanQuery = false
			peg.Size = Vector3.new(0.7, 0.7, 0.7)
			peg.Position = Vector3.new(startX + col * spacingX, y, boardZ)
			peg.Color = Config.COLORS.NeonPurple
			peg.Material = Enum.Material.Neon
			peg.Parent = pegsFolder
		end
	end
end

local function resolveArena(): boolean
	if spawnPart and dropOrigin and bucketsFolder then
		return true
	end

	local arena = Workspace:FindFirstChild(ARENA_NAME)
	if not (arena and arena:IsA("Folder")) then
		warn("[PlinkoPoints] Workspace.PlinkoArena is missing")
		return false
	end

	local pad = arena:FindFirstChild("SpawnPad")
	local origin = arena:FindFirstChild("DropOrigin")
	local buckets = arena:FindFirstChild("Buckets")
	local pegs = arena:FindFirstChild("Pegs")
	local sign = arena:FindFirstChild("TitleSign")

	if not (pad and pad:IsA("BasePart")) then
		warn("[PlinkoPoints] Arena is missing SpawnPad")
		return false
	end
	if not (origin and origin:IsA("BasePart")) then
		warn("[PlinkoPoints] Arena is missing DropOrigin")
		return false
	end
	if not (buckets and buckets:IsA("Folder")) then
		warn("[PlinkoPoints] Arena is missing Buckets folder")
		return false
	end

	spawnPart = pad
	dropOrigin = origin
	bucketsFolder = buckets
	pegsFolder = if pegs and pegs:IsA("Folder") then pegs else nil
	titleSign = if sign and sign:IsA("BasePart") then sign else nil

	ensurePegs()
	ensureBucketLabels()
	ensureTitleSign()
	return true
end

local function joinedPayload(player: Player): PlinkoPointsJoined
	local loadout = getLoadout(player)
	return {
		wager = loadout.wager,
		chips = CurrencyService.getChips(player),
		highScore = DataService.getHighScore(player, "PlinkoPoints"),
	}
end

local function rejectDrop(player: Player, reason: string)
	Remotes.getEvent("PlinkoPointsDropRejected"):FireClient(player, { reason = reason })
end

local function processDrop(player: Player)
	if not playersInArena[player] then
		return
	end
	if dropping[player] then
		rejectDrop(player, "Drop already in progress")
		return
	end

	local now = os.clock()
	local last = lastDropAt[player] or 0
	if now - last < Config.PLINKO.DropCooldownSeconds then
		rejectDrop(player, "Wait a moment before the next drop")
		return
	end

	local loadout = getLoadout(player)
	local wager = loadout.wager
	if CurrencyService.getChips(player) < wager then
		rejectDrop(player, "Insufficient chips for this wager")
		return
	end

	dropping[player] = true
	lastDropAt[player] = now

	local deducted = CurrencyService.deductChips(player, wager, "PlinkoPoints:wager")
	if not deducted then
		dropping[player] = nil
		rejectDrop(player, "Insufficient chips for this wager")
		return
	end

	local bucketIndex = rollBucketIndex()
	local multiplier = Config.PLINKO.BucketMultipliers[bucketIndex] or 0
	local payout = math.floor(wager * multiplier * Config.PLINKO.PlayerReturnFactor)
	if payout > 0 then
		CurrencyService.creditPayout(player, payout, wager, "PlinkoPoints:payout")
	end

	local netDelta = payout - wager
	local outcome = settleOutcome(payout, netDelta)
	local highScore = DataService.setHighScore(player, "PlinkoPoints", payout)
	local dropId = nextDropId
	nextDropId += 1

	local payload: PlinkoPointsResultPayload = {
		dropId = dropId,
		bucketIndex = bucketIndex - 1, -- 0-based for client bucket parts
		multiplier = multiplier,
		wager = wager,
		payout = payout,
		netDelta = netDelta,
		highScore = highScore,
		chips = CurrencyService.getChips(player),
		outcome = outcome,
	}
	Remotes.getEvent("PlinkoPointsResult"):FireClient(player, payload)
	dropping[player] = nil
end

--[=[
	Teleport the player into the Plinko arena and bootstrap their client HUD.
	@param player Player
]=]
function PlinkoPoints.join(player: Player)
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

	Remotes.getEvent("PlinkoPointsJoined"):FireClient(player, joinedPayload(player))
end

--[=[
	Remove the player from the arena and return them to the lobby spawn.
	@param player Player
]=]
function PlinkoPoints.leave(player: Player)
	if not playersInArena[player] then
		return
	end
	playersInArena[player] = nil
	dropping[player] = nil

	local janitor = playerJanitors[player]
	if janitor then
		janitor:Destroy()
		playerJanitors[player] = nil
	end

	teleportTo(player, Config.LOBBY.SpawnPosition)
	Remotes.getEvent("PlinkoPointsLeft"):FireClient(player)
end

--[=[
	Whether the player is currently inside the Plinko arena.
	@param player Player
	@return boolean
]=]
function PlinkoPoints.isPlaying(player: Player): boolean
	return playersInArena[player] == true
end

--[=[
	Resolve the arena, bind remotes, and prepare pegs / bucket labels.
]=]
function PlinkoPoints.start()
	if started then
		return
	end
	started = true
	refreshWeightTotal()

	if not resolveArena() then
		return
	end

	if spawnPart then
		local leavePrompt = spawnPart:FindFirstChild("LeavePrompt")
		if leavePrompt and leavePrompt:IsA("ProximityPrompt") then
			leavePrompt.Triggered:Connect(function(player: Player)
				PlinkoPoints.leave(player)
			end)
		end
	end

	Remotes.getEvent("PlinkoPointsSetWager").OnServerEvent:Connect(function(player: Player, wager: unknown)
		loadouts[player] = { wager = clampWager(wager) }
	end)

	Remotes.getEvent("PlinkoPointsDrop").OnServerEvent:Connect(function(player: Player)
		processDrop(player)
	end)

	Remotes.getEvent("PlinkoPointsLeave").OnServerEvent:Connect(function(player: Player)
		PlinkoPoints.leave(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playersInArena[player] = nil
		loadouts[player] = nil
		lastDropAt[player] = nil
		dropping[player] = nil
		local janitor = playerJanitors[player]
		if janitor then
			janitor:Destroy()
			playerJanitors[player] = nil
		end
	end)
end

return PlinkoPoints
