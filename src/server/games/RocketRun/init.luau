--!strict
--[=[
	@class RocketRun
	Server-authoritative Rocket Run: one shared rocket and crash point per server.

	## Round phases

	1. `idle` - between rounds / before the loop starts
	2. `countdown` - crash multiplier rolled; eligible players stake their wager
	3. `flying` - multiplier grows as `exp(growthRate * elapsed)`; cash-outs allowed
	4. `crashed` - rocket explodes; unsettled eligible players lose their wager

	## Economy

	- Loadout **wager** is deducted when the player becomes eligible (insufficient chips → spectate).
	- Cash-out: `payout = floor(wager * multiplier * PlayerReturnFactor)` via `CurrencyService.creditPayout`.
	- Crash: stake already gone; `netDelta = -wager` (no refund).
	- Target RTP > 100% via `Config.ROCKET_RUN.TargetRTP` / `PlayerReturnFactor`.
	- Auto cash-out fires at the configured multiplier if it is still below the crash point.

	## Participation

	- Players join via lobby portal → `RocketRun.join`.
	- Joining during `countdown` attempts eligibility (deduct wager) for that round.
	- Joining during `flying` spectates until the next launch (`eligible = false`).
	- Cashing out never stops the rocket; other players keep flying / spectating.
]=]
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
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

type RocketRunLoadout = Types.RocketRunLoadout
type RocketRunCashOutMarker = Types.RocketRunCashOutMarker
type RocketRunResultPayload = Types.RocketRunResultPayload
type RocketRunRoundStarted = Types.RocketRunRoundStarted

type RoundPhase = "idle" | "countdown" | "flying" | "crashed"

type Participant = {
	eligible: boolean,
	cashedOut: boolean,
	wager: number,
	autoCashOut: number?,
}

local RocketRun = {}

local ARENA_NAME = "RocketRunArena"
local rng = Random.new()
local started = false
local nextRoundId = 1

local roundId = 0
local roundPhase: RoundPhase = "idle"
local flyStartTime = 0
local crashMultiplier = 1

local playersInArena: { [Player]: boolean } = {}
local participants: { [Player]: Participant } = {}
local loadouts: { [Player]: RocketRunLoadout } = {}
local playerJanitors: { [Player]: any } = {}

local spawnPart: BasePart? = nil
local rocketModel: Model? = nil
local rocketFlame: BasePart? = nil
local cameraFocus: BasePart? = nil
local thrusterEmitter: ParticleEmitter? = nil
local thrusterTrail: Trail? = nil
local thrusterSound: Sound? = nil
local engineLight: PointLight? = nil
local rocketHome = Config.ROCKET_RUN.RocketHomePosition
local rocketHomePivot = CFrame.new(Config.ROCKET_RUN.RocketHomePosition)

local boardMultiplier: TextLabel? = nil
local boardStatus: TextLabel? = nil
local boardPlot: Frame? = nil
local boardCurve: Frame? = nil
local boardMarkers: Frame? = nil
local boardLinePool: { Frame } = {}
local boardCashOuts: { { name: string, elapsed: number, multiplier: number } } = {}
local boardLastElapsed = 0
local boardLastMultiplier = 1

local function setBoardLine(line: Frame, from: Vector2, to: Vector2)
	local delta = to - from
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
	line.Size = UDim2.fromOffset(math.max(1, delta.Magnitude), 4)
	line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	line.BackgroundColor3 = Config.COLORS.NeonCyan
	line.Visible = true
end

local function redrawBoardGraph()
	local plot = boardPlot
	local curve = boardCurve
	local markers = boardMarkers
	if not plot or not curve or not markers then
		return
	end

	for _, child in markers:GetChildren() do
		child:Destroy()
	end

	local size = plot.AbsoluteSize
	if size.X <= 1 or size.Y <= 1 then
		-- SurfaceGui may not have absolute size yet on the first frames.
		size = Vector2.new(760, 420)
	end

	local maxElapsed = math.max(8, boardLastElapsed)
	local maxMultiplier = math.max(2, boardLastMultiplier)
	for _, marker in boardCashOuts do
		maxMultiplier = math.max(maxMultiplier, marker.multiplier)
	end
	maxMultiplier *= 1.12

	local function toPlot(elapsed: number, multiplier: number): Vector2
		local x = math.clamp(elapsed / maxElapsed, 0, 1) * size.X
		local y = size.Y * (1 - math.clamp((math.max(1, multiplier) - 1) / (maxMultiplier - 1), 0, 1))
		return Vector2.new(x, y)
	end

	local used = 0
	local function drawLine(from: Vector2, to: Vector2)
		used += 1
		local line = boardLinePool[used]
		if not line then
			line = Instance.new("Frame")
			line.Name = "Segment"
			line.BorderSizePixel = 0
			line.Parent = curve
			table.insert(boardLinePool, line)
		end
		setBoardLine(line, from, to)
	end

	local segmentCount = 48
	local logMultiplier = math.log(math.max(1, boardLastMultiplier))
	local previous = toPlot(0, 1)
	for index = 1, segmentCount do
		local alpha = index / segmentCount
		local elapsed = boardLastElapsed * alpha
		local multiplier = math.exp(logMultiplier * alpha)
		local current = toPlot(elapsed, multiplier)
		drawLine(previous, current)
		previous = current
	end
	for index = used + 1, #boardLinePool do
		boardLinePool[index].Visible = false
	end

	for _, marker in boardCashOuts do
		local point = toPlot(marker.elapsed, marker.multiplier)
		local dot = Instance.new("Frame")
		dot.Name = "Marker"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromOffset(point.X, point.Y)
		dot.Size = UDim2.fromOffset(14, 14)
		dot.BackgroundColor3 = Config.COLORS.NeonLime
		dot.BorderSizePixel = 0
		dot.Rotation = 45
		dot.Parent = markers

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromOffset(point.X, point.Y - 10)
		label.Size = UDim2.fromOffset(180, 28)
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Config.COLORS.NeonLime
		label.TextScaled = true
		label.Text = string.format("%s %.2fx", string.sub(marker.name, 1, 10), marker.multiplier)
		label.Parent = markers
	end

	local live = toPlot(boardLastElapsed, boardLastMultiplier)
	local cursor = Instance.new("Frame")
	cursor.Name = "Live"
	cursor.AnchorPoint = Vector2.new(0.5, 0.5)
	cursor.Position = UDim2.fromOffset(live.X, live.Y)
	cursor.Size = UDim2.fromOffset(16, 16)
	cursor.BackgroundColor3 = Config.COLORS.NeonCyan
	cursor.BorderSizePixel = 0
	cursor.Parent = markers
	local cursorCorner = Instance.new("UICorner")
	cursorCorner.CornerRadius = UDim.new(1, 0)
	cursorCorner.Parent = cursor
end

local function updateWorldBoard(elapsed: number, multiplier: number, statusText: string, color: Color3?)
	boardLastElapsed = math.max(0, elapsed)
	boardLastMultiplier = math.max(1, multiplier)
	if boardMultiplier then
		boardMultiplier.Text = string.format("%.2fx", boardLastMultiplier)
		boardMultiplier.TextColor3 = color or Config.COLORS.NeonCyan
	end
	if boardStatus then
		boardStatus.Text = statusText
	end
	redrawBoardGraph()
end

local function resetWorldBoard(statusText: string)
	table.clear(boardCashOuts)
	boardLastElapsed = 0
	boardLastMultiplier = 1
	updateWorldBoard(0, 1, statusText, Config.COLORS.NeonCyan)
end

local function addWorldBoardCashOut(displayName: string, elapsed: number, multiplier: number)
	table.insert(boardCashOuts, {
		name = displayName,
		elapsed = elapsed,
		multiplier = multiplier,
	})
	redrawBoardGraph()
end

local function ensureTelemetryBoard(arena: Folder)
	local board = arena:FindFirstChild("TelemetryBoard")
	if not (board and board:IsA("BasePart")) then
		return
	end

	local gui = board:FindFirstChild("TelemetryGui")
	if gui and gui:IsA("SurfaceGui") then
		-- Keep older sessions aligned if the board was previously rotated.
		gui.Face = Enum.NormalId.Right
	end
	if not (gui and gui:IsA("SurfaceGui")) then
		gui = Instance.new("SurfaceGui")
		gui.Name = "TelemetryGui"
		gui.Face = Enum.NormalId.Right
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.Parent = board

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(24, 18)
		title.Size = UDim2.new(1, -48, 0, 36)
		title.Font = Enum.Font.GothamBold
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Color3.fromRGB(170, 155, 210)
		title.TextScaled = true
		title.Text = "ARENA TELEMETRY"
		title.Parent = gui

		local multiplier = Instance.new("TextLabel")
		multiplier.Name = "Multiplier"
		multiplier.BackgroundTransparency = 1
		multiplier.Position = UDim2.fromOffset(24, 60)
		multiplier.Size = UDim2.new(0.45, 0, 0, 90)
		multiplier.Font = Enum.Font.GothamBlack
		multiplier.TextXAlignment = Enum.TextXAlignment.Left
		multiplier.TextColor3 = Config.COLORS.NeonCyan
		multiplier.TextScaled = true
		multiplier.Text = "1.00x"
		multiplier.Parent = gui

		local status = Instance.new("TextLabel")
		status.Name = "Status"
		status.BackgroundTransparency = 1
		status.Position = UDim2.new(0.45, 0, 0, 78)
		status.Size = UDim2.new(0.5, -24, 0, 50)
		status.Font = Enum.Font.GothamMedium
		status.TextXAlignment = Enum.TextXAlignment.Right
		status.TextColor3 = Config.COLORS.Text
		status.TextScaled = true
		status.Text = "Waiting for launch…"
		status.Parent = gui

		local plot = Instance.new("Frame")
		plot.Name = "Plot"
		plot.Position = UDim2.fromOffset(24, 170)
		plot.Size = UDim2.new(1, -48, 1, -200)
		plot.BackgroundColor3 = Color3.fromRGB(8, 6, 18)
		plot.BorderSizePixel = 0
		plot.ClipsDescendants = true
		plot.Parent = gui

		local plotCorner = Instance.new("UICorner")
		plotCorner.CornerRadius = UDim.new(0, 12)
		plotCorner.Parent = plot

		local curve = Instance.new("Frame")
		curve.Name = "Curve"
		curve.Size = UDim2.fromScale(1, 1)
		curve.BackgroundTransparency = 1
		curve.Parent = plot

		local markers = Instance.new("Frame")
		markers.Name = "Markers"
		markers.Size = UDim2.fromScale(1, 1)
		markers.BackgroundTransparency = 1
		markers.Parent = plot
	end

	-- Force board geometry flush to the west perimeter even if an older
	-- rotated instance was already synced into the place.
	board.Size = Vector3.new(1, 18, 42)
	local origin = Config.ROCKET_RUN.ArenaOrigin
	board.CFrame = CFrame.new(origin + Vector3.new(-24.5, 10, 0))
	board.Orientation = Vector3.zero

	boardMultiplier = gui:FindFirstChild("Multiplier") :: TextLabel?
	boardStatus = gui:FindFirstChild("Status") :: TextLabel?
	local plot = gui:FindFirstChild("Plot")
	if plot and plot:IsA("Frame") then
		boardPlot = plot
		boardCurve = plot:FindFirstChild("Curve") :: Frame?
		boardMarkers = plot:FindFirstChild("Markers") :: Frame?
	end
end

local function multiplierAt(elapsed: number): number
	return math.exp(Config.ROCKET_RUN.GrowthRate * math.max(0, elapsed))
end

local function rocketTrajectory(elapsed: number, multiplier: number): (Vector3, Vector3)
	local cfg = Config.ROCKET_RUN
	local swayPhase = elapsed * cfg.RocketSwayFrequency
	local crashElapsed = math.log(crashMultiplier) / cfg.GrowthRate
	local progress = math.clamp(elapsed / math.max(crashElapsed, 0.001), 0, 1)
	local tellDuration = math.max(0.001, 1 - cfg.RocketCrashTellStart)
	local tellProgress = math.clamp((progress - cfg.RocketCrashTellStart) / tellDuration, 0, 1)

	-- Smoothstep caps total sideways travel while producing a visible bank near
	-- the crash. Its derivative gives the rocket's horizontal facing direction.
	local horizontalAlpha = tellProgress ^ 2 * (3 - 2 * tellProgress)
	local horizontalDerivative = 6 * tellProgress * (1 - tellProgress) / (tellDuration * math.max(crashElapsed, 0.001))

	local position = rocketHome
		+ Vector3.new(
			cfg.RocketMaxHorizontalDistance * horizontalAlpha,
			elapsed * cfg.RocketLaunchSpeed
				+ 0.5 * cfg.RocketVerticalAcceleration * elapsed ^ 2
				+ math.log(math.max(1, multiplier)) * cfg.RocketHeightPerLog,
			math.sin(swayPhase) * cfg.RocketSway
		)
	local tangent = Vector3.new(
		cfg.RocketMaxHorizontalDistance * horizontalDerivative,
		cfg.RocketLaunchSpeed + cfg.RocketVerticalAcceleration * elapsed + cfg.GrowthRate * cfg.RocketHeightPerLog,
		math.cos(swayPhase) * cfg.RocketSway * cfg.RocketSwayFrequency
	)
	return position, tangent.Unit
end

local function rocketCFrame(position: Vector3, tangent: Vector3): CFrame
	local reference = Vector3.zAxis
	if math.abs(tangent:Dot(reference)) > 0.98 then
		reference = Vector3.xAxis
	end
	-- The detailed fuselage is a cylinder whose local X axis is its length.
	local up = reference:Cross(tangent).Unit
	local back = tangent:Cross(up).Unit
	return CFrame.fromMatrix(position, tangent, up, back)
end

local function rollCrashMultiplier(): number
	local cfg = Config.ROCKET_RUN
	local skewed = rng:NextNumber() ^ 2
	return cfg.MinCrashMultiplier + skewed * (cfg.MaxCrashMultiplier - cfg.MinCrashMultiplier)
end

local function clampLoadout(rawWager: unknown, rawAutoCashOut: unknown): RocketRunLoadout
	local cfg = Config.ROCKET_RUN
	local wager = math.floor(tonumber(rawWager) or cfg.DefaultWager)
	wager = math.clamp(wager, cfg.MinWager, cfg.MaxWager)

	local autoCashOut: number? = nil
	local autoValue = tonumber(rawAutoCashOut)
	if autoValue and autoValue >= 1.01 then
		autoCashOut = math.clamp(autoValue, 1.01, cfg.MaxCrashMultiplier)
	end

	return {
		wager = wager,
		autoCashOut = autoCashOut,
	}
end

local function getLoadout(player: Player): RocketRunLoadout
	return loadouts[player] or clampLoadout(nil, nil)
end

local function cashOutPayout(wager: number, multiplier: number): number
	return math.floor(wager * multiplier * Config.ROCKET_RUN.PlayerReturnFactor)
end

-- Attempt to stake the loadout wager. On success the player is eligible for this round.
local function tryBecomeEligible(player: Player, loadout: RocketRunLoadout): Participant
	local deducted = CurrencyService.deductChips(player, loadout.wager, "RocketRun:wager")
	if not deducted then
		return {
			eligible = false,
			cashedOut = true,
			wager = loadout.wager,
			autoCashOut = loadout.autoCashOut,
		}
	end

	return {
		eligible = true,
		cashedOut = false,
		wager = loadout.wager,
		autoCashOut = loadout.autoCashOut,
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

local debrisFolder: Folder? = nil
local hiddenPartStates: { [BasePart]: number } = {}

local function clearDebris()
	if debrisFolder then
		debrisFolder:Destroy()
		debrisFolder = nil
	end
end

local function showRocketParts()
	for part, transparency in hiddenPartStates do
		if part.Parent then
			part.Transparency = transparency
		end
	end
	table.clear(hiddenPartStates)
end

local function hideRocketParts()
	if not rocketModel then
		return
	end
	table.clear(hiddenPartStates)
	for _, descendant in rocketModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			hiddenPartStates[descendant] = descendant.Transparency
			descendant.Transparency = 1
		end
	end
end

local function explodeRocket()
	if not rocketModel then
		return
	end

	clearDebris()
	local folder = Instance.new("Folder")
	folder.Name = "RocketDebris"
	folder.Parent = Workspace
	debrisFolder = folder

	hideRocketParts()

	for _, descendant in rocketModel:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if descendant.Name == "Flame" then
			continue
		end

		local piece = descendant:Clone()
		for _, child in piece:GetDescendants() do
			if child:IsA("Sound") or child:IsA("ParticleEmitter") or child:IsA("Trail") or child:IsA("PointLight") then
				child:Destroy()
			end
		end
		for _, child in piece:GetChildren() do
			if child:IsA("Sound") or child:IsA("ParticleEmitter") or child:IsA("Trail") or child:IsA("PointLight") then
				child:Destroy()
			end
		end

		piece.Anchored = false
		piece.CanCollide = true
		piece.CanQuery = false
		piece.CanTouch = false
		piece.Transparency = hiddenPartStates[descendant] or 0
		piece.Parent = folder

		local outward = piece.Position - rocketHome
		if outward.Magnitude < 0.001 then
			outward = Vector3.yAxis
		else
			outward = outward.Unit
		end
		piece.AssemblyLinearVelocity = outward * rng:NextNumber(28, 62)
			+ Vector3.new(rng:NextNumber(-24, 24), rng:NextNumber(36, 78), rng:NextNumber(-24, 24))
		piece.AssemblyAngularVelocity =
			Vector3.new(rng:NextNumber(-18, 18), rng:NextNumber(-18, 18), rng:NextNumber(-18, 18))

		Debris:AddItem(piece, Config.ROCKET_RUN.IntermissionSeconds + 1)
	end

	if thrusterEmitter then
		thrusterEmitter.Enabled = false
		thrusterEmitter:Emit(60)
	end
	if thrusterTrail then
		thrusterTrail.Enabled = false
	end
	if thrusterSound then
		thrusterSound:Stop()
	end
	if engineLight then
		engineLight.Brightness = 0
	end
end

local function resetRocket()
	if not rocketModel then
		return
	end
	clearDebris()
	showRocketParts()
	rocketModel:PivotTo(rocketHomePivot)
	if rocketFlame then
		rocketFlame.Transparency = 0.45
	end
	if thrusterEmitter then
		thrusterEmitter.Enabled = false
	end
	if thrusterTrail then
		thrusterTrail.Enabled = false
	end
	if thrusterSound then
		thrusterSound:Stop()
	end
	if engineLight then
		engineLight.Brightness = 1
	end
	if cameraFocus then
		cameraFocus.Position = rocketHome
	end
	resetWorldBoard("Waiting for launch…")
end

local function moveRocket(elapsed: number, multiplier: number, crashed: boolean?)
	if not rocketModel then
		return
	end

	local position, tangent = rocketTrajectory(elapsed, multiplier)
	local bodyCFrame = rocketCFrame(position, tangent)
	rocketModel:PivotTo(bodyCFrame)
	if rocketFlame then
		rocketFlame.Transparency = if crashed then 1 else 0.12
	end
	if thrusterEmitter then
		thrusterEmitter.Enabled = not crashed
		thrusterEmitter.Rate = math.clamp(70 + multiplier * 8, 70, 190)
		if crashed then
			thrusterEmitter:Emit(45)
		end
	end
	if thrusterTrail then
		thrusterTrail.Enabled = not crashed
	end
	if thrusterSound then
		if crashed then
			thrusterSound:Stop()
		elseif not thrusterSound.IsPlaying then
			thrusterSound:Play()
		end
		thrusterSound.PlaybackSpeed = math.clamp(0.9 + multiplier * 0.025, 0.9, 1.5)
	end
	if engineLight then
		engineLight.Brightness = if crashed then 0 else math.clamp(1.5 + multiplier * 0.15, 1.5, 5)
	end
	if cameraFocus then
		cameraFocus.Position = position
	end

	local statusText = if crashed
		then string.format("CRASHED @ %.2fx", multiplier)
		elseif roundPhase == "countdown" then "COUNTDOWN"
		else "IN FLIGHT"
	local color = if crashed
		then Config.COLORS.NeonMagenta
		elseif multiplier >= 5 then Config.COLORS.NeonMagenta
		elseif multiplier >= 2 then Config.COLORS.NeonLime
		else Config.COLORS.NeonCyan
	updateWorldBoard(elapsed, multiplier, statusText, color)
end

local function ensureRocketEffects(body: BasePart, flame: BasePart?)
	if not flame then
		return
	end

	local exhaust = flame:FindFirstChild("ThrusterAttachment")
	if not (exhaust and exhaust:IsA("Attachment")) then
		exhaust = Instance.new("Attachment")
		exhaust.Name = "ThrusterAttachment"
		exhaust.Position = Vector3.new(0, -flame.Size.Y / 2, 0)
		exhaust.Parent = flame
	end

	local emitter = exhaust:FindFirstChild("ThrusterParticles")
	if not (emitter and emitter:IsA("ParticleEmitter")) then
		emitter = Instance.new("ParticleEmitter")
		emitter.Name = "ThrusterParticles"
		emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(210, 250, 255)),
			ColorSequenceKeypoint.new(0.35, Config.COLORS.NeonCyan),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 30)),
		})
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Lifetime = NumberRange.new(0.25, 0.55)
		emitter.Rate = 80
		emitter.Rotation = NumberRange.new(-180, 180)
		emitter.RotSpeed = NumberRange.new(-90, 90)
		emitter.Speed = NumberRange.new(22, 34)
		emitter.SpreadAngle = Vector2.new(12, 12)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2.4),
			NumberSequenceKeypoint.new(0.35, 1.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Enabled = false
		emitter.Parent = exhaust
	end
	thrusterEmitter = emitter

	local left = flame:FindFirstChild("TrailLeft")
	if not (left and left:IsA("Attachment")) then
		left = Instance.new("Attachment")
		left.Name = "TrailLeft"
		left.Position = Vector3.new(-0.8, -flame.Size.Y / 2, 0)
		left.Parent = flame
	end
	local right = flame:FindFirstChild("TrailRight")
	if not (right and right:IsA("Attachment")) then
		right = Instance.new("Attachment")
		right.Name = "TrailRight"
		right.Position = Vector3.new(0.8, -flame.Size.Y / 2, 0)
		right.Parent = flame
	end

	local trail = flame:FindFirstChild("ThrusterTrail")
	if not (trail and trail:IsA("Trail")) then
		trail = Instance.new("Trail")
		trail.Name = "ThrusterTrail"
		trail.Attachment0 = left
		trail.Attachment1 = right
		trail.Color = ColorSequence.new(Config.COLORS.NeonCyan, Color3.fromRGB(255, 80, 25))
		trail.LightEmission = 1
		trail.Lifetime = 0.3
		trail.MinLength = 0.1
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Enabled = false
		trail.Parent = flame
	end
	thrusterTrail = trail

	local engine = body:FindFirstChild("ThrusterLoop")
	if not (engine and engine:IsA("Sound")) then
		engine = Instance.new("Sound")
		engine.Name = "ThrusterLoop"
		engine.SoundId = "rbxasset://sounds/Rocket whoosh 01.wav"
		engine.Looped = true
		engine.Volume = 0.18
		engine.RollOffMinDistance = 15
		engine.RollOffMaxDistance = 220
		engine.Parent = body
	end
	thrusterSound = engine

	local light = body:FindFirstChild("EngineLight")
	if light and light:IsA("PointLight") then
		engineLight = light
	end
end

local function resolveArena(): boolean
	-- Never recapture the home pivot while a round is in flight.
	local arena = Workspace:FindFirstChild(ARENA_NAME)
	if arena and arena:IsA("Folder") then
		ensureTelemetryBoard(arena)
	end

	if rocketModel and spawnPart then
		return true
	end

	if not (arena and arena:IsA("Folder")) then
		warn("[RocketRun] Workspace.RocketRunArena is missing")
		return false
	end

	local pad = arena:FindFirstChild("SpawnPad")
	local rocket = arena:FindFirstChild("Rocket")
	local focus = arena:FindFirstChild("CameraFocus")
	if not (pad and pad:IsA("BasePart") and rocket and rocket:IsA("Model")) then
		warn("[RocketRun] Arena is missing SpawnPad or Rocket")
		return false
	end

	local body = rocket:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		warn("[RocketRun] Rocket.Body is missing")
		return false
	end

	spawnPart = pad
	rocketModel = rocket
	rocketHome = body.Position

	local flame = rocket:FindFirstChild("Flame")
	rocketFlame = if flame and flame:IsA("BasePart") then flame else nil
	cameraFocus = if focus and focus:IsA("BasePart") then focus else nil
	ensureRocketEffects(body, rocketFlame)

	-- Treat the rocket as one rigid visual assembly. Only PivotTo moves it.
	for _, descendant in rocket:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end

	rocket.PrimaryPart = body
	rocketHomePivot = rocket:GetPivot()
	ensureTelemetryBoard(arena)
	resetWorldBoard("Waiting for launch…")
	return true
end

local function roundPayload(player: Player, participant: Participant): RocketRunRoundStarted
	return {
		roundId = roundId,
		flyStartTime = flyStartTime,
		growthRate = Config.ROCKET_RUN.GrowthRate,
		countdownSeconds = Config.ROCKET_RUN.CountdownSeconds,
		highScore = DataService.getHighScore(player, "RocketRun"),
		wager = participant.wager,
		autoCashOut = participant.autoCashOut,
		chips = CurrencyService.getChips(player),
		phase = if roundPhase == "flying" then "flying" else "countdown",
		eligible = participant.eligible,
	}
end

local function sendCurrentRound(player: Player)
	local participant = participants[player]
	if not participant or roundPhase == "idle" or roundPhase == "crashed" then
		return
	end
	Remotes.getEvent("RocketRunRoundStarted"):FireClient(player, roundPayload(player, participant))
end

local function settleCashOut(player: Player, participant: Participant, multiplier: number)
	if not participant.eligible or participant.cashedOut or roundPhase ~= "flying" then
		return
	end

	participant.cashedOut = true
	local wager = participant.wager
	local payout = cashOutPayout(wager, multiplier)
	CurrencyService.creditPayout(player, payout, wager, "RocketRun:payout")
	local netDelta = payout - wager
	local highScore = DataService.setHighScore(player, "RocketRun", payout)

	local payload: RocketRunResultPayload = {
		roundId = roundId,
		outcome = "cashed_out",
		multiplier = multiplier,
		score = payout,
		wager = wager,
		payout = payout,
		netDelta = netDelta,
		highScore = highScore,
		chips = CurrencyService.getChips(player),
		crashMultiplier = nil,
	}
	Remotes.getEvent("RocketRunResult"):FireClient(player, payload)

	local marker: RocketRunCashOutMarker = {
		roundId = roundId,
		userId = player.UserId,
		displayName = player.DisplayName,
		multiplier = multiplier,
		elapsed = math.max(0, Workspace:GetServerTimeNow() - flyStartTime),
	}
	for spectator in playersInArena do
		Remotes.getEvent("RocketRunCashOutMarker"):FireClient(spectator, marker)
	end
	addWorldBoardCashOut(player.DisplayName, marker.elapsed, marker.multiplier)
end

local function settleCrash(player: Player, participant: Participant)
	if participant.cashedOut or not participant.eligible then
		return
	end

	participant.cashedOut = true
	local wager = participant.wager
	local payload: RocketRunResultPayload = {
		roundId = roundId,
		outcome = "crashed",
		multiplier = crashMultiplier,
		score = 0,
		wager = wager,
		payout = 0,
		netDelta = -wager,
		highScore = DataService.getHighScore(player, "RocketRun"),
		chips = CurrencyService.getChips(player),
		crashMultiplier = crashMultiplier,
	}
	Remotes.getEvent("RocketRunResult"):FireClient(player, payload)
end

local function beginRound()
	roundId = nextRoundId
	nextRoundId += 1
	roundPhase = "countdown"
	crashMultiplier = rollCrashMultiplier()
	flyStartTime = Workspace:GetServerTimeNow() + Config.ROCKET_RUN.CountdownSeconds
	resetRocket()
	resetWorldBoard(string.format("Launching in %ds…", Config.ROCKET_RUN.CountdownSeconds))

	table.clear(participants)
	for player in playersInArena do
		local loadout = getLoadout(player)
		local participant = tryBecomeEligible(player, loadout)
		participants[player] = participant
		Remotes.getEvent("RocketRunRoundStarted"):FireClient(player, roundPayload(player, participant))
	end
end

local function runRound()
	beginRound()
	while Workspace:GetServerTimeNow() < flyStartTime do
		local remaining = flyStartTime - Workspace:GetServerTimeNow()
		updateWorldBoard(0, 1, string.format("Launching in %.1fs…", remaining), Config.COLORS.NeonCyan)
		task.wait(0.1)
	end
	roundPhase = "flying"

	local crashElapsed = math.log(crashMultiplier) / Config.ROCKET_RUN.GrowthRate
	while roundPhase == "flying" do
		local elapsed = math.max(0, Workspace:GetServerTimeNow() - flyStartTime)
		local multiplier = multiplierAt(elapsed)

		if elapsed >= crashElapsed or multiplier >= crashMultiplier then
			roundPhase = "crashed"
			moveRocket(crashElapsed, crashMultiplier, true)
			explodeRocket()
			for player in playersInArena do
				Remotes.getEvent("RocketRunCrashed"):FireClient(player, {
					roundId = roundId,
					crashMultiplier = crashMultiplier,
				})
				local participant = participants[player]
				if participant then
					settleCrash(player, participant)
				end
			end
			break
		end

		moveRocket(elapsed, multiplier, false)
		for player, participant in participants do
			local autoAt = participant.autoCashOut
			if autoAt and not participant.cashedOut and multiplier >= autoAt and autoAt < crashMultiplier then
				settleCashOut(player, participant, autoAt)
			end
		end
		task.wait(0.03)
	end

	task.wait(Config.ROCKET_RUN.IntermissionSeconds)
	resetRocket()
end

local function roundLoop()
	while true do
		runRound()
	end
end

--[=[
	Teleport the player into the arena and register them for the current/next round.
	@param player Player
]=]
function RocketRun.join(player: Player)
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

	if roundPhase == "countdown" then
		participants[player] = tryBecomeEligible(player, getLoadout(player))
	elseif roundPhase == "flying" then
		local loadout = getLoadout(player)
		participants[player] = {
			eligible = false,
			cashedOut = true,
			wager = loadout.wager,
			autoCashOut = loadout.autoCashOut,
		}
	end
	sendCurrentRound(player)
end

--[=[
	Remove the player from the arena, clear participation, and return them to the casino corridor.
	@param player Player
]=]
function RocketRun.leave(player: Player)
	if not playersInArena[player] then
		return
	end
	playersInArena[player] = nil
	participants[player] = nil

	local janitor = playerJanitors[player]
	if janitor then
		janitor:Destroy()
		playerJanitors[player] = nil
	end

	teleportTo(player, Config.ROCKET_RUN.LeavePosition)
	Remotes.getEvent("RocketRunLeft"):FireClient(player)
end

--[=[
	Whether the player is currently inside the Rocket Run arena.
	@param player Player
	@return boolean
]=]
function RocketRun.isPlaying(player: Player): boolean
	return playersInArena[player] == true
end

--[=[
	Resolve the arena, bind remotes, and start the infinite shared round loop.
]=]
function RocketRun.start()
	if started then
		return
	end
	started = true

	if not resolveArena() then
		return
	end
	resetRocket()

	if spawnPart then
		local leavePrompt = spawnPart:FindFirstChild("LeavePrompt")
		if leavePrompt and leavePrompt:IsA("ProximityPrompt") then
			leavePrompt.Triggered:Connect(function(player: Player)
				RocketRun.leave(player)
			end)
		end
	end

	Remotes.getEvent("RocketRunSetLoadout").OnServerEvent
		:Connect(function(player: Player, wager: unknown, autoCashOut: unknown)
			loadouts[player] = clampLoadout(wager, autoCashOut)
		end)

	Remotes.getEvent("RocketRunCashOut").OnServerEvent:Connect(function(player: Player, requestedRoundId: unknown)
		if typeof(requestedRoundId) ~= "number" or requestedRoundId ~= roundId or roundPhase ~= "flying" then
			return
		end

		local participant = participants[player]
		if not participant or not participant.eligible or participant.cashedOut then
			return
		end

		local elapsed = Workspace:GetServerTimeNow() - flyStartTime
		local multiplier = multiplierAt(elapsed)
		if multiplier >= crashMultiplier then
			return
		end
		settleCashOut(player, participant, multiplier)
	end)

	Remotes.getEvent("RocketRunLeave").OnServerEvent:Connect(function(player: Player)
		RocketRun.leave(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playersInArena[player] = nil
		participants[player] = nil
		loadouts[player] = nil
		local janitor = playerJanitors[player]
		if janitor then
			janitor:Destroy()
			playerJanitors[player] = nil
		end
	end)

	task.spawn(roundLoop)
end

return RocketRun
