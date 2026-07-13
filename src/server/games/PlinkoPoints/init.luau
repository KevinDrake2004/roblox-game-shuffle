--!strict
--[=[
	@class PlinkoPoints
	Server-authoritative Plinko Points: wager per ball drop, physics-land settle.

	## Flow

	1. Lobby portal → `PlinkoPoints.join` teleports into `Workspace.PlinkoArena`.
	2. Client sets wager / balls / risk via `PlinkoPointsSetWager` (clamped to Config).
	3. `PlinkoPointsDrop` deducts `wager * ballCount` and fires `PlinkoPointsDropStarted`.
	4. Client releases balls in short bursts; each runs an independent free physics sim
	   (balls never collide with each other, only pegs).
	5. Client reports `PlinkoPointsLanded` per ball; server settles with the risk tier's multipliers.
	6. Leave returns the player to `Config.PLINKO.LeavePosition` (refunds unsettled balls).

	## Economy

	- Total stake `wager * ballCount` deducted before the volley starts.
	- Insufficient balance → drop rejected.
	- Landing bucket comes from client physics; multipliers come from the selected risk tier.
	- Risk scale: Low (8 rows, small jackpots, higher RTP) → Medium (12 rows) →
	  High (16 rows, large max mult, RTP → 100%, tight ball cap).
	- Each player gets a local board for their risk; shared arena pegs are decor only while playing.
	- Unreported lands time out as a center land (anti-hang). Leave mid-drop refunds.

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

type PendingBall = {
	dropId: number,
	wager: number,
	riskId: string,
}

type PendingSession = {
	balls: { [number]: PendingBall },
	expected: number,
	settled: number,
	startedAt: number,
}

local PlinkoPoints = {}

local ARENA_NAME = "PlinkoArena"
local started = false
local nextDropId = 1

local playersInArena: { [Player]: boolean } = {}
local loadouts: { [Player]: PlinkoPointsLoadout } = {}
local lastDropAt: { [Player]: number } = {}
local pendingSessions: { [Player]: PendingSession } = {}
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

local function clampBallCount(rawCount: unknown, riskId: unknown): number
	local cfg = Config.PLINKO
	local risk = Config.getPlinkoRisk(riskId)
	local count = math.floor(tonumber(rawCount) or cfg.DefaultBallCount)
	if count ~= count or count < cfg.MinBallCount then
		count = cfg.MinBallCount
	end
	return math.clamp(count, cfg.MinBallCount, risk.maxBallCount)
end

local function clampRiskId(rawRisk: unknown): string
	return Config.getPlinkoRisk(rawRisk).id
end

-- Large volleys release several balls per wave so total release stays under MaxReleaseSeconds.
local function computeReleaseTiming(ballCount: number): (number, number)
	if ballCount <= 1 then
		return 0, 1
	end
	local preferred = Config.PLINKO.BallDropStaggerSeconds
	local maxWindow = Config.PLINKO.BallDropMaxReleaseSeconds
	local maxWaves = math.max(1, math.floor(maxWindow / preferred + 1e-9))
	local burstSize = math.max(1, math.ceil(ballCount / maxWaves))
	local waves = math.ceil(ballCount / burstSize)
	local stagger = if waves <= 1 then 0 else math.min(preferred, maxWindow / (waves - 1))
	return stagger, burstSize
end

local function getLoadout(player: Player): PlinkoPointsLoadout
	return loadouts[player]
		or {
			wager = Config.PLINKO.DefaultWager,
			ballCount = Config.PLINKO.DefaultBallCount,
			riskId = Config.PLINKO.DefaultRiskId,
		}
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

	local existing = titleSign:FindFirstChild("SignGui")
	if existing then
		existing:Destroy()
	end

	-- Dark plate + high-contrast lime title so it does not melt into the purple board.
	titleSign.Color = Color3.fromRGB(8, 4, 16)
	titleSign.Material = Enum.Material.SmoothPlastic

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 2.5
	gui.Parent = titleSign

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.BackgroundColor3 = Color3.fromRGB(6, 3, 14)
	plate.BackgroundTransparency = 0.05
	plate.BorderSizePixel = 0
	plate.Size = UDim2.fromScale(1, 1)
	plate.Parent = gui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Config.COLORS.NeonLime
	title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	title.TextStrokeTransparency = 0
	title.Text = "PLINKO POINTS"
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
			peg.Size = Vector3.new(0.9, 0.9, 0.9)
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
	local risk = Config.getPlinkoRisk(loadout.riskId)
	return {
		wager = loadout.wager,
		ballCount = loadout.ballCount,
		riskId = risk.id,
		maxBallCount = risk.maxBallCount,
		chips = CurrencyService.getChips(player),
		highScore = DataService.getHighScore(player, "PlinkoPoints"),
	}
end

local function rejectDrop(player: Player, reason: string)
	Remotes.getEvent("PlinkoPointsDropRejected"):FireClient(player, { reason = reason })
end

local function settleBall(player: Player, ball: PendingBall, bucketIndex0: number)
	local risk = Config.getPlinkoRisk(ball.riskId)
	local multipliers = risk.bucketMultipliers
	local maxIndex = #multipliers - 1
	local bucketIndex0Clamped = math.clamp(math.floor(bucketIndex0), 0, maxIndex)
	local multiplier = multipliers[bucketIndex0Clamped + 1] or 0
	local wager = ball.wager
	-- Integer chips: floor(wager * mult). Multipliers must stay integer-friendly or
	-- low wagers (especially 1) silently pay 0 on sub-1x buckets and destroy RTP.
	local payout = math.floor(wager * multiplier)
	if payout > 0 then
		CurrencyService.creditPayout(player, payout, wager, "PlinkoPoints:payout")
	end

	local netDelta = payout - wager
	local outcome = settleOutcome(payout, netDelta)
	local highScore = DataService.setHighScore(player, "PlinkoPoints", payout)

	local payload: PlinkoPointsResultPayload = {
		dropId = ball.dropId,
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

local function refundSession(player: Player, source: string)
	local session = pendingSessions[player]
	if not session then
		return
	end
	pendingSessions[player] = nil
	local refund = 0
	for _, ball in session.balls do
		refund += ball.wager
	end
	if refund > 0 then
		CurrencyService.creditPayout(player, refund, refund, source)
	end
end

local function settleTimedOutBalls(player: Player, session: PendingSession)
	local remaining: { PendingBall } = {}
	for _, ball in session.balls do
		table.insert(remaining, ball)
	end
	for _, ball in remaining do
		local risk = Config.getPlinkoRisk(ball.riskId)
		local center = math.floor(risk.pegRows / 2)
		session.balls[ball.dropId] = nil
		session.settled += 1
		settleBall(player, ball, center)
	end
	if session.settled >= session.expected then
		pendingSessions[player] = nil
	end
end

local function beginDrop(player: Player)
	if not playersInArena[player] then
		return
	end
	if pendingSessions[player] then
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
	local ballCount = loadout.ballCount
	local riskId = clampRiskId(loadout.riskId)
	local totalStake = wager * ballCount
	if CurrencyService.getChips(player) < totalStake then
		rejectDrop(player, string.format("Need %d chips for %d balls", totalStake, ballCount))
		return
	end

	local deducted = CurrencyService.deductChips(player, totalStake, "PlinkoPoints:wager")
	if not deducted then
		rejectDrop(player, string.format("Need %d chips for %d balls", totalStake, ballCount))
		return
	end

	lastDropAt[player] = now
	local dropIds: { number } = {}
	local balls: { [number]: PendingBall } = {}
	for _ = 1, ballCount do
		local dropId = nextDropId
		nextDropId += 1
		table.insert(dropIds, dropId)
		balls[dropId] = {
			dropId = dropId,
			wager = wager,
			riskId = riskId,
		}
	end

	pendingSessions[player] = {
		balls = balls,
		expected = ballCount,
		settled = 0,
		startedAt = now,
	}

	local staggerSeconds, burstSize = computeReleaseTiming(ballCount)
	local startedPayload: PlinkoPointsDropStarted = {
		dropIds = dropIds,
		wager = wager,
		ballCount = ballCount,
		staggerSeconds = staggerSeconds,
		burstSize = burstSize,
		chips = CurrencyService.getChips(player),
	}
	Remotes.getEvent("PlinkoPointsDropStarted"):FireClient(player, startedPayload)

	local waves = math.ceil(ballCount / burstSize)
	local timeout = Config.PLINKO.LandReportTimeoutSeconds + math.max(0, waves - 1) * staggerSeconds + 2
	task.delay(timeout, function()
		local session = pendingSessions[player]
		if not session or session.startedAt ~= now then
			return
		end
		settleTimedOutBalls(player, session)
	end)
end

local function handleLanded(player: Player, dropId: unknown, bucketIndex: unknown)
	local session = pendingSessions[player]
	if not session then
		return
	end
	if typeof(dropId) ~= "number" or typeof(bucketIndex) ~= "number" then
		return
	end
	if not playersInArena[player] then
		return
	end
	local ball = session.balls[dropId]
	if not ball then
		return
	end
	session.balls[dropId] = nil
	session.settled += 1
	settleBall(player, ball, bucketIndex)
	if session.settled >= session.expected then
		pendingSessions[player] = nil
	end
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

	Remotes.getEvent("PlinkoPointsJoined"):FireClient(player, joinedPayload(player))
end

--[=[
	Remove the player from the arena and return them to the casino corridor.
	@param player Player
]=]
function PlinkoPoints.leave(player: Player)
	if not playersInArena[player] then
		return
	end
	playersInArena[player] = nil
	refundSession(player, "PlinkoPoints:leave_refund")

	local janitor = playerJanitors[player]
	if janitor then
		janitor:Destroy()
		playerJanitors[player] = nil
	end

	teleportTo(player, Config.PLINKO.LeavePosition)
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

	Remotes.getEvent("PlinkoPointsSetWager").OnServerEvent
		:Connect(function(player: Player, wager: unknown, ballCount: unknown, riskId: unknown)
			local clampedRisk = clampRiskId(riskId)
			loadouts[player] = {
				wager = clampWager(wager),
				ballCount = clampBallCount(ballCount, clampedRisk),
				riskId = clampedRisk,
			}
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
		pendingSessions[player] = nil
		local janitor = playerJanitors[player]
		if janitor then
			janitor:Destroy()
			playerJanitors[player] = nil
		end
	end)
end

return PlinkoPoints
