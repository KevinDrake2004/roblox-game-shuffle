--!strict
--[=[
	@class PlinkoPoints
	Server-authoritative Plinko Points: wager per ball drop, physics-land settle.

	## Flow

	1. Lobby portal → `PlinkoPoints.join` teleports into `Workspace.PlinkoArena`.
	2. Client sets wager via `PlinkoPointsSetWager` (clamped to Config).
	3. `PlinkoPointsDrop` deducts the wager and fires `PlinkoPointsDropStarted`.
	4. Client runs a **free** local gravity/peg sim (landing is not pre-rolled).
	5. Client reports `PlinkoPointsLanded` with the bucket the ball entered.
	6. Server credits `floor(wager * multiplier)` for that bucket.
	7. Leave returns the player to `Config.LOBBY.SpawnPosition`.

	## Economy

	- Wager deducted with `CurrencyService.deductChips` before the drop starts.
	- Insufficient balance → drop rejected.
	- Landing bucket comes from client physics; multipliers come from Config.
	- Zero-multiplier (center) buckets are busts: stake gone, `payout = 0`.
	- Design RTP ≈ 105% by tuning `BucketMultipliers` against the Galton / binomial
	  land curve (`TargetRTP` is the aim, not an extra payout multiply).
	- Unreported lands time out as a center bust (anti-hang). Leave mid-drop refunds.

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
type PlinkoPointsDropStarted = Types.PlinkoPointsDropStarted
type PlinkoPointsResultPayload = Types.PlinkoPointsResultPayload

type PendingDrop = {
	dropId: number,
	wager: number,
	startedAt: number,
}

local PlinkoPoints = {}

local ARENA_NAME = "PlinkoArena"
local started = false
local nextDropId = 1

local playersInArena: { [Player]: boolean } = {}
local loadouts: { [Player]: PlinkoPointsLoadout } = {}
local lastDropAt: { [Player]: number } = {}
local pendingDrops: { [Player]: PendingDrop } = {}
local playerJanitors: { [Player]: any } = {}

local spawnPart: BasePart? = nil
local dropOrigin: BasePart? = nil
local bucketsFolder: Folder? = nil
local pegsFolder: Folder? = nil
local titleSign: BasePart? = nil

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

-- Bucket multiplier billboards are created client-side only while the local
-- player is in Plinko, so lobby / other games never see AlwaysOnTop labels.

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

	local layoutVersion = Config.PLINKO.PegLayoutVersion
	if pegsFolder:GetAttribute("LayoutVersion") == layoutVersion and pegsFolder:FindFirstChild("Peg_0_0") then
		return
	end

	for _, child in pegsFolder:GetChildren() do
		child:Destroy()
	end

	-- Galton / bean-machine board: row r has (r+1) pegs, centered on ArenaOrigin.
	-- With PegRows = 8, the bottom row has 8 pegs → 9 slots matching the buckets.
	local origin = Config.PLINKO.ArenaOrigin
	local rows = Config.PLINKO.PegRows
	local boardZ = dropOrigin.Position.Z
	local topY = dropOrigin.Position.Y - 2
	local spacingX = Config.PLINKO.PegSpacingX
	local spacingY = Config.PLINKO.PegSpacingY
	for row = 0, rows - 1 do
		local pegsInRow = row + 1
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
			peg.Size = Vector3.new(0.65, 0.65, 0.65)
			peg.Position = Vector3.new(startX + col * spacingX, y, boardZ)
			peg.Color = Config.COLORS.NeonPurple
			peg.Material = Enum.Material.Neon
			peg.Parent = pegsFolder
		end
	end

	pegsFolder:SetAttribute("LayoutVersion", layoutVersion)
end

local function resolveArena(): boolean
	if spawnPart and dropOrigin and bucketsFolder then
		ensurePegs()
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

local function settlePending(player: Player, bucketIndex0: number)
	local pending = pendingDrops[player]
	if not pending then
		return
	end
	pendingDrops[player] = nil

	local multipliers = Config.PLINKO.BucketMultipliers
	local maxIndex = #multipliers - 1
	local bucketIndex0Clamped = math.clamp(math.floor(bucketIndex0), 0, maxIndex)
	local multiplier = multipliers[bucketIndex0Clamped + 1] or 0
	local wager = pending.wager
	local payout = math.floor(wager * multiplier)
	if payout > 0 then
		CurrencyService.creditPayout(player, payout, wager, "PlinkoPoints:payout")
	end

	local netDelta = payout - wager
	local outcome = settleOutcome(payout, netDelta)
	local highScore = DataService.setHighScore(player, "PlinkoPoints", payout)

	local payload: PlinkoPointsResultPayload = {
		dropId = pending.dropId,
		bucketIndex = bucketIndex0Clamped,
		multiplier = multiplier,
		wager = wager,
		payout = payout,
		netDelta = netDelta,
		highScore = highScore,
		chips = CurrencyService.getChips(player),
		outcome = outcome,
	}
	Remotes.getEvent("PlinkoPointsResult"):FireClient(player, payload)
end

local function refundPending(player: Player, source: string)
	local pending = pendingDrops[player]
	if not pending then
		return
	end
	pendingDrops[player] = nil
	CurrencyService.creditPayout(player, pending.wager, pending.wager, source)
end

local function beginDrop(player: Player)
	if not playersInArena[player] then
		return
	end
	if pendingDrops[player] then
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

	local deducted = CurrencyService.deductChips(player, wager, "PlinkoPoints:wager")
	if not deducted then
		rejectDrop(player, "Insufficient chips for this wager")
		return
	end

	lastDropAt[player] = now
	local dropId = nextDropId
	nextDropId += 1
	pendingDrops[player] = {
		dropId = dropId,
		wager = wager,
		startedAt = now,
	}

	local startedPayload: PlinkoPointsDropStarted = {
		dropId = dropId,
		wager = wager,
		chips = CurrencyService.getChips(player),
	}
	Remotes.getEvent("PlinkoPointsDropStarted"):FireClient(player, startedPayload)

	task.delay(Config.PLINKO.LandReportTimeoutSeconds, function()
		local pending = pendingDrops[player]
		if not pending or pending.dropId ~= dropId then
			return
		end
		-- Timed out without a land report: treat as center bust.
		local center = math.floor((#Config.PLINKO.BucketMultipliers - 1) / 2)
		settlePending(player, center)
	end)
end

local function handleLanded(player: Player, dropId: unknown, bucketIndex: unknown)
	local pending = pendingDrops[player]
	if not pending then
		return
	end
	if typeof(dropId) ~= "number" or dropId ~= pending.dropId then
		return
	end
	if typeof(bucketIndex) ~= "number" then
		return
	end
	if not playersInArena[player] then
		return
	end
	settlePending(player, bucketIndex)
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
	refundPending(player, "PlinkoPoints:leave_refund")

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
	Resolve the arena, bind remotes, and prepare pegs.
]=]
function PlinkoPoints.start()
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
				PlinkoPoints.leave(player)
			end)
		end
	end

	Remotes.getEvent("PlinkoPointsSetWager").OnServerEvent:Connect(function(player: Player, wager: unknown)
		loadouts[player] = { wager = clampWager(wager) }
	end)

	Remotes.getEvent("PlinkoPointsDrop").OnServerEvent:Connect(function(player: Player)
		beginDrop(player)
	end)

	Remotes.getEvent("PlinkoPointsLanded").OnServerEvent
		:Connect(function(player: Player, dropId: unknown, bucketIndex: unknown)
			handleLanded(player, dropId, bucketIndex)
		end)

	Remotes.getEvent("PlinkoPointsLeave").OnServerEvent:Connect(function(player: Player)
		PlinkoPoints.leave(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playersInArena[player] = nil
		loadouts[player] = nil
		lastDropAt[player] = nil
		-- Disconnect mid-drop: stake already taken; do not refund.
		pendingDrops[player] = nil
		local janitor = playerJanitors[player]
		if janitor then
			janitor:Destroy()
			playerJanitors[player] = nil
		end
	end)
end

return PlinkoPoints
