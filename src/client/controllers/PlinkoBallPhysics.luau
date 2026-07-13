--!strict
--[=[
	@class PlinkoBallPhysics
	Local-only gravity + peg bounce simulation for Plinko Points.

	The path is **not** predetermined. A Galton peg layout plus gravity and
	peg collisions decide the land. Each hit uses contact normal + restitution
	blended with a characteristic L/R leave velocity from hit offset (bean-machine
	±1 step per row). No soft bias toward a bucket.
	Parts live under CurrentCamera so other players never see your ball.
]=]
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local PlinkoBallPhysics = {}

type PegState = {
	part: BasePart,
	radius: number,
	lastHit: number,
	-- After a valid leave, ignore re-resolve until the ball clears this peg.
	-- Prevents apex re-hits from coin-flipping and canceling horizontal leave.
	awaitingClear: boolean,
}

type BucketInfo = {
	index: number,
	part: BasePart,
	minX: number,
	maxX: number,
	centerX: number,
	landY: number,
	homeCFrame: CFrame,
	homeSize: Vector3,
}

type SimHandles = {
	cancel: () -> (),
}

type BoardPhysics = {
	ballRadius: number,
	pegSize: number,
	leaveSpeed: number,
	leaveAngleDeg: number,
	reflectBlend: number,
	horizontalDrag: number,
	startSpeedX: number,
	startSpread: number,
	pegHitCooldown: number,
	apexNormalX: number,
	maxUpSpeed: number,
	railNearDamp: number,
	-- Horizontal leave needed for ~± half peg pitch per row (Galton step).
	galtonLeaveX: number,
}

local activeCancels: { [() -> ()]: boolean } = {}

type BucketHome = {
	cframe: CFrame,
	size: Vector3,
}

local bucketHomes: { [BasePart]: BucketHome } = {}

local function getBucketHome(bucket: BasePart): BucketHome
	local existing = bucketHomes[bucket]
	if existing then
		return existing
	end
	local home = {
		cframe = bucket.CFrame,
		size = bucket.Size,
	}
	bucketHomes[bucket] = home
	return home
end

local function pinBucket(bucket: BasePart, homeCFrame: CFrame, homeSize: Vector3)
	bucket.Anchored = true
	bucket.CanCollide = false
	bucket.AssemblyLinearVelocity = Vector3.zero
	bucket.AssemblyAngularVelocity = Vector3.zero
	bucket.Size = homeSize
	bucket.CFrame = homeCFrame
end

-- Idle cup color after a drop batch (and at board build).
local IDLE_BUCKET_COLOR = Config.COLORS.NeonPurple

--[=[
	Map a bucket multiplier to a land-flash color, normalized by the risk's max.
	Bands stay distinct across Low (~17x), Med (~121x), and High (~316x) tables.
]=]
local function bucketLandColor(multiplier: number, maxMultiplier: number): Color3
	if multiplier <= 0 then
		return Config.COLORS.NeonMagenta
	end
	local t = if maxMultiplier > 0 then multiplier / maxMultiplier else 0
	if t < 0.06 then
		return Config.COLORS.NeonCyan
	elseif t < 0.20 then
		return Config.COLORS.NeonPurple
	elseif t < 0.50 then
		return Config.COLORS.NeonLime
	end
	return Config.COLORS.NeonGold
end

-- Flash color + light only. Never tween Size/CFrame - that made buckets drift under multi-hit.
-- Land color persists until resetBucketsIdle (batch complete / cancel).
local function glowBucket(bucket: BasePart, color: Color3, homeCFrame: CFrame, homeSize: Vector3)
	pinBucket(bucket, homeCFrame, homeSize)

	local light = Instance.new("PointLight")
	light.Name = "LandGlow"
	light.Brightness = 4
	light.Range = 14
	light.Color = color
	light.Parent = bucket

	local flash = TweenService:Create(
		bucket,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Color = color }
	)
	flash:Play()
	flash.Completed:Connect(function()
		if bucket.Parent then
			pinBucket(bucket, homeCFrame, homeSize)
			bucket.Color = color
		end
	end)
	Debris:AddItem(light, 0.7)
end

local function setBucketLandColor(
	bucket: BasePart,
	multiplier: number,
	maxMultiplier: number,
	homeCFrame: CFrame,
	homeSize: Vector3
)
	glowBucket(bucket, bucketLandColor(multiplier, maxMultiplier), homeCFrame, homeSize)
end

local function flashPeg(part: BasePart)
	local original = part.Color
	part.Color = Color3.fromRGB(255, 240, 255)
	task.delay(0.08, function()
		if part.Parent then
			part.Color = original
		end
	end)
end

local function getArena(): Folder?
	local arena = Workspace:FindFirstChild("PlinkoArena")
	if arena and arena:IsA("Folder") then
		return arena
	end
	return nil
end

local function getLocalFxFolder(): Folder
	local camera = Workspace.CurrentCamera
	local parent: Instance = camera or Workspace
	local existing = parent:FindFirstChild("PlinkoLocalFx")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "PlinkoLocalFx"
	folder.Parent = parent
	return folder
end

local function getOrCreateSubfolder(name: string): Folder
	local fx = getLocalFxFolder()
	local existing = fx:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = fx
	return folder
end

local function setSharedDecorVisible(visible: boolean)
	local arena = getArena()
	if not arena then
		return
	end
	local transparency = if visible then 0 else 1
	for _, folderName in { "Pegs", "Buckets" } do
		local folder = arena:FindFirstChild(folderName)
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("BasePart") then
					child.LocalTransparencyModifier = transparency
				end
			end
		end
	end
end

local function collectPegs(pegsFolder: Instance): { PegState }
	local pegs: { PegState } = {}
	for _, child in pegsFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(pegs, {
				part = child,
				radius = math.max(child.Size.X, child.Size.Y, child.Size.Z) * 0.5,
				lastHit = -math.huge,
				awaitingClear = false,
			})
		end
	end
	return pegs
end

local function collectBuckets(bucketsFolder: Instance): { BucketInfo }
	local list: { BucketInfo } = {}
	for _, child in bucketsFolder:GetChildren() do
		if child:IsA("BasePart") then
			local index = tonumber(string.match(child.Name, "^Bucket_(%d+)$"))
			if index ~= nil then
				local home = getBucketHome(child)
				pinBucket(child, home.cframe, home.size)
				local half = home.size.X * 0.5
				local pos = home.cframe.Position
				table.insert(list, {
					index = index,
					part = child,
					minX = pos.X - half,
					maxX = pos.X + half,
					centerX = pos.X,
					landY = pos.Y + home.size.Y * 0.35,
					homeCFrame = home.cframe,
					homeSize = home.size,
				})
			end
		end
	end
	table.sort(list, function(a, b)
		return a.centerX < b.centerX
	end)
	return list
end

local function railBounds(arena: Folder): (number, number)
	local left = arena:FindFirstChild("BoardRailLeft")
	local right = arena:FindFirstChild("BoardRailRight")
	-- Match map rails (~40.8 stud inner width). Fallback used only if rails missing.
	local leftX = if left and left:IsA("BasePart")
		then left.Position.X + left.Size.X * 0.5
		else Config.PLINKO.ArenaOrigin.X - 20.4
	local rightX = if right and right:IsA("BasePart")
		then right.Position.X - right.Size.X * 0.5
		else Config.PLINKO.ArenaOrigin.X + 20.4
	return leftX, rightX
end

local function writeBoardPhysics(
	board: Folder,
	physics: {
		ballRadius: number,
		pegSize: number,
		leaveSpeed: number,
		leaveAngleDeg: number,
		reflectBlend: number,
		horizontalDrag: number,
		startSpeedX: number,
		startSpread: number,
		pegHitCooldown: number,
		apexNormalX: number,
		maxUpSpeed: number,
		railNearDamp: number,
	},
	spacingX: number,
	rows: number,
	riskId: string,
	galtonLeaveX: number
)
	board:SetAttribute("RiskId", riskId)
	board:SetAttribute("PegRows", rows)
	board:SetAttribute("SpacingX", spacingX)
	board:SetAttribute("BallRadius", physics.ballRadius)
	board:SetAttribute("PegSize", physics.pegSize)
	board:SetAttribute("LeaveSpeed", physics.leaveSpeed)
	board:SetAttribute("LeaveAngleDeg", physics.leaveAngleDeg)
	board:SetAttribute("ReflectBlend", physics.reflectBlend)
	board:SetAttribute("HorizontalDrag", physics.horizontalDrag)
	board:SetAttribute("StartSpeedX", physics.startSpeedX)
	board:SetAttribute("StartSpread", physics.startSpread)
	board:SetAttribute("PegHitCooldown", physics.pegHitCooldown)
	board:SetAttribute("ApexNormalX", physics.apexNormalX)
	board:SetAttribute("MaxUpSpeed", physics.maxUpSpeed)
	board:SetAttribute("RailNearDamp", physics.railNearDamp)
	board:SetAttribute("GaltonLeaveX", galtonLeaveX)
end

local function readBoardPhysics(board: Instance?, cfg: typeof(Config.PLINKO)): BoardPhysics
	local function num(attr: string, fallback: number): number
		if board then
			local value = board:GetAttribute(attr)
			if typeof(value) == "number" then
				return value
			end
		end
		return fallback
	end
	local leaveSpeed = num("LeaveSpeed", cfg.BallPegLeaveSpeed)
	local leaveDeg = num("LeaveAngleDeg", cfg.BallPegLeaveAngleDeg)
	local spacingX = num("SpacingX", cfg.PegSpacingX)
	-- Fallback half-pitch leave if board was built before GaltonLeaveX existed.
	local fallbackLeaveX = math.max(leaveSpeed * math.sin(math.rad(leaveDeg)), spacingX * 0.45)
	return {
		ballRadius = num("BallRadius", cfg.BallRadius),
		pegSize = num("PegSize", cfg.PegSpacingX * 0.32),
		leaveSpeed = leaveSpeed,
		leaveAngleDeg = leaveDeg,
		reflectBlend = num("ReflectBlend", cfg.BallPegReflectBlend),
		horizontalDrag = num("HorizontalDrag", cfg.BallHorizontalDrag),
		startSpeedX = num("StartSpeedX", cfg.BallStartSpeedX),
		startSpread = num("StartSpread", cfg.BallStartSpeedX * 0.35),
		pegHitCooldown = num("PegHitCooldown", cfg.BallPegHitCooldown),
		apexNormalX = num("ApexNormalX", cfg.BallPegApexNormalX),
		maxUpSpeed = num("MaxUpSpeed", cfg.BallPegMaxUpSpeed),
		railNearDamp = num("RailNearDamp", cfg.BallRailNearDamp),
		galtonLeaveX = num("GaltonLeaveX", fallbackLeaveX),
	}
end

--[=[
	Build a local-only Galton board for the selected risk (pegs + buckets).
	Hides the shared arena decor so each player sees their own row count.
]=]
function PlinkoBallPhysics.rebuildBoard(riskId: string): boolean
	local arena = getArena()
	if not arena then
		return false
	end
	local origin = arena:FindFirstChild("DropOrigin")
	if not (origin and origin:IsA("BasePart")) then
		return false
	end

	local risk = Config.getPlinkoRisk(riskId)
	local rows = risk.pegRows
	local bucketCount = rows + 1
	local multipliers = risk.bucketMultipliers
	if #multipliers ~= bucketCount then
		warn("[PlinkoBallPhysics] Risk multipliers length mismatch for", risk.id)
		return false
	end

	table.clear(bucketHomes)
	local board = getOrCreateSubfolder("Board")
	board:ClearAllChildren()
	local pegsFolder = Instance.new("Folder")
	pegsFolder.Name = "Pegs"
	pegsFolder.Parent = board
	local bucketsFolder = Instance.new("Folder")
	bucketsFolder.Name = "Buckets"
	bucketsFolder.Parent = board

	local leftX, rightX = railBounds(arena)
	-- Fill rail-to-rail with a continuous bucket bar (no gaps between cups).
	local usableWidth = math.max(4, rightX - leftX)
	local bucketWidth = usableWidth / bucketCount
	local spacingX = bucketWidth
	local topY = origin.Position.Y - 1.5
	local bottomY = Config.PLINKO.ArenaOrigin.Y + 2.4
	local spacingY = math.max(1.45, (topY - bottomY) / rows)
	local boardZ = origin.Position.Z - 0.15
	local originX = Config.PLINKO.ArenaOrigin.X
	local physics = risk.physics
	-- Horizontal leave must cover ~half pitch before the next row. Effective fall
	-- time is a bit under rest-from-rest because balls already carry downward speed.
	local fallTime = math.max(0.10, math.sqrt(2 * spacingY / Config.PLINKO.BallGravity) * 0.82)
	local galtonLeaveX = (spacingX * 0.48) / fallTime
	galtonLeaveX = math.clamp(galtonLeaveX, spacingX * 1.25, spacingX * 2.4)
	writeBoardPhysics(board, physics, spacingX, rows, risk.id, galtonLeaveX)

	for row = 0, rows - 1 do
		local pegsInRow = row + 1
		local rowWidth = (pegsInRow - 1) * spacingX
		local startX = originX - rowWidth / 2
		local y = topY - row * spacingY
		for col = 0, pegsInRow - 1 do
			local peg = Instance.new("Part")
			peg.Name = `Peg_{row}_{col}`
			peg.Shape = Enum.PartType.Ball
			peg.Anchored = true
			peg.CanCollide = false
			peg.CanQuery = false
			peg.CanTouch = false
			peg.CastShadow = false
			peg.Size = Vector3.new(physics.pegSize, physics.pegSize, physics.pegSize)
			peg.Position = Vector3.new(startX + col * spacingX, y, boardZ)
			peg.Color = Config.COLORS.NeonPurple
			peg.Material = Enum.Material.Neon
			peg.Parent = pegsFolder
		end
	end

	-- Edge-to-edge cups: width == spacing so the bottom reads as one solid bar.
	local bucketHeight = 2.8
	local bucketDepth = 2.6
	local bucketY = bottomY - 0.2
	local firstCenter = originX - usableWidth * 0.5 + bucketWidth * 0.5
	local sizeX = bucketWidth + 0.02 -- tiny overlap hides seam gaps
	for index = 0, bucketCount - 1 do
		local bucket = Instance.new("Part")
		bucket.Name = `Bucket_{index}`
		bucket.Anchored = true
		bucket.CanCollide = false
		bucket.CanQuery = false
		bucket.CanTouch = false
		bucket.CastShadow = false
		bucket.Size = Vector3.new(sizeX, bucketHeight, bucketDepth)
		bucket.Position = Vector3.new(firstCenter + index * bucketWidth, bucketY, boardZ)
		local mult = multipliers[index + 1] or 0
		bucket:SetAttribute("Multiplier", mult)
		-- Idle cups are all base purple; land flash paints by multiplier.
		bucket.Color = IDLE_BUCKET_COLOR
		bucket.Material = Enum.Material.Neon
		bucket.Parent = bucketsFolder
	end

	-- Continuous plate behind the cups so the bottom always reads as one solid bar.
	local bar = Instance.new("Part")
	bar.Name = "BucketBar"
	bar.Anchored = true
	bar.CanCollide = false
	bar.CanQuery = false
	bar.CanTouch = false
	bar.CastShadow = false
	bar.Size = Vector3.new(usableWidth + 0.1, bucketHeight * 0.92, bucketDepth * 0.7)
	bar.Position = Vector3.new(originX, bucketY, boardZ + 0.12)
	bar.Color = Color3.fromRGB(18, 10, 32)
	bar.Material = Enum.Material.SmoothPlastic
	bar.Parent = bucketsFolder

	setSharedDecorVisible(false)
	return true
end

--[=[
	Destroy the local risk board and show shared arena decor again.
]=]
function PlinkoBallPhysics.clearBoard()
	local fx = getLocalFxFolder()
	local board = fx:FindFirstChild("Board")
	if board then
		board:Destroy()
	end
	table.clear(bucketHomes)
	setSharedDecorVisible(true)
end

--[=[
	Folder of local bucket parts for the active risk board (if any).
]=]
function PlinkoBallPhysics.getLocalBucketsFolder(): Folder?
	local fx = getLocalFxFolder()
	local board = fx:FindFirstChild("Board")
	if not board then
		return nil
	end
	local buckets = board:FindFirstChild("Buckets")
	if buckets and buckets:IsA("Folder") then
		return buckets
	end
	return nil
end

--[=[
	Reset every local cup to idle base purple (after a drop batch or cancel/leave).
]=]
function PlinkoBallPhysics.resetBucketsIdle()
	local buckets = PlinkoBallPhysics.getLocalBucketsFolder()
	if not buckets then
		return
	end
	for _, child in buckets:GetChildren() do
		if child:IsA("BasePart") and string.match(child.Name, "^Bucket_%d+$") then
			local home = getBucketHome(child)
			pinBucket(child, home.cframe, home.size)
			child.Color = IDLE_BUCKET_COLOR
			local glow = child:FindFirstChild("LandGlow")
			if glow then
				glow:Destroy()
			end
		end
	end
end

local function resolveBucketAtX(buckets: { BucketInfo }, x: number): BucketInfo?
	if #buckets == 0 then
		return nil
	end
	-- Nearest center (bucket sizes may overlap slightly for a seamless bar).
	local best = buckets[1]
	local bestDist = math.abs(x - best.centerX)
	for index = 2, #buckets do
		local candidate = buckets[index]
		local dist = math.abs(x - candidate.centerX)
		if dist < bestDist then
			best = candidate
			bestDist = dist
		end
	end
	return best
end

local function clampSpeed(vel: Vector3, maxSpeed: number): Vector3
	local speed = vel.Magnitude
	if speed <= maxSpeed or speed < 1e-6 then
		return vel
	end
	return vel.Unit * maxSpeed
end

--[=[
	Cancel every in-flight local ball simulation (keeps the local risk board).
	Also restores cups to idle purple so land flashes do not stick.
]=]
function PlinkoBallPhysics.cancel()
	local snapshot: { () -> () } = {}
	for cancelFn in activeCancels do
		table.insert(snapshot, cancelFn)
	end
	for _, cancelFn in snapshot do
		cancelFn()
	end
	table.clear(activeCancels)
	local ballsFolder = getOrCreateSubfolder("Balls")
	ballsFolder:ClearAllChildren()
	PlinkoBallPhysics.resetBucketsIdle()
end

--[=[
	Run a free local gravity/peg bounce drop. Landing bucket is decided by physics.
	Multiple drops may run at once; balls do not collide with each other (peg-only).

	@param onLanded (bucketIndex: number) -> () -- 0-based bucket the ball actually entered
	@return SimHandles
]=]
function PlinkoBallPhysics.drop(onLanded: (bucketIndex: number) -> ()): SimHandles
	local arena = getArena()
	local cancelled = false
	local connection: RBXScriptConnection? = nil

	local function cleanup()
		if cancelled then
			return
		end
		cancelled = true
		if connection then
			connection:Disconnect()
			connection = nil
		end
		activeCancels[cleanup] = nil
	end
	activeCancels[cleanup] = true

	local function failLand()
		if cancelled then
			return
		end
		local board = getLocalFxFolder():FindFirstChild("Board")
		local rows = if board then board:GetAttribute("PegRows") else nil
		local fallback = if typeof(rows) == "number"
			then math.floor(rows / 2)
			else math.floor((#Config.PLINKO.BucketMultipliers - 1) / 2)
		warn("[PlinkoBallPhysics] Sim failed; falling back to center bucket", fallback)
		cleanup()
		onLanded(fallback)
	end

	if not arena then
		failLand()
		return { cancel = cleanup }
	end

	local origin = arena:FindFirstChild("DropOrigin")
	if not (origin and origin:IsA("BasePart")) then
		failLand()
		return { cancel = cleanup }
	end

	local board = getLocalFxFolder():FindFirstChild("Board")
	local pegsFolder = if board then board:FindFirstChild("Pegs") else nil
	local bucketsFolder = if board then board:FindFirstChild("Buckets") else nil
	if not (pegsFolder and bucketsFolder) then
		failLand()
		return { cancel = cleanup }
	end

	local buckets = collectBuckets(bucketsFolder)
	if #buckets == 0 then
		failLand()
		return { cancel = cleanup }
	end

	local cfg = Config.PLINKO
	local physics = readBoardPhysics(board, cfg)
	local radius = physics.ballRadius
	local pegs = collectPegs(pegsFolder)
	local leftX, rightX = railBounds(arena)
	local boardZ = origin.Position.Z - 0.15
	local leaveSpeed = physics.leaveSpeed
	local spacingXAttr = if board then board:GetAttribute("SpacingX") else nil
	local spacingX = if typeof(spacingXAttr) == "number" then spacingXAttr else cfg.PegSpacingX
	local landY = buckets[1].landY
	for _, bucket in buckets do
		landY = math.min(landY, bucket.landY)
	end

	local riskIdAttr = if board then board:GetAttribute("RiskId") else nil
	local riskId = if typeof(riskIdAttr) == "string" then riskIdAttr else Config.PLINKO.DefaultRiskId
	local risk = Config.getPlinkoRisk(riskId)
	local maxMultiplier = risk.maxMultiplier

	local rng = Random.new()
	local startSpread = physics.startSpread
	local startSpeedX = physics.startSpeedX
	local pos = Vector3.new(origin.Position.X + rng:NextNumber(-startSpread, startSpread), origin.Position.Y, boardZ)
	local vel = Vector3.new(rng:NextNumber(-startSpeedX, startSpeedX), rng:NextNumber(-2, 0), 0)

	local ballsFolder = getOrCreateSubfolder("Balls")
	local ball = Instance.new("Part")
	ball.Name = "LocalPlinkoBall"
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	ball.Color = Config.COLORS.NeonPurple
	ball.Material = Enum.Material.Neon
	ball.Position = pos
	ball.Parent = ballsFolder

	local trailA0 = Instance.new("Attachment")
	trailA0.Position = Vector3.new(-radius * 0.2, 0, 0)
	trailA0.Parent = ball
	local trailA1 = Instance.new("Attachment")
	trailA1.Position = Vector3.new(radius * 0.2, 0, 0)
	trailA1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = trailA0
	trail.Attachment1 = trailA1
	trail.Color = ColorSequence.new(Config.COLORS.NeonPurple, Color3.fromRGB(255, 200, 255))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.4
	trail.LightEmission = 0.85
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = ball

	local elapsed = 0
	local finished = false

	local function finish(bucket: BucketInfo)
		if finished or cancelled then
			return
		end
		finished = true
		-- Keep the natural X; only settle Y into the cup.
		pos = Vector3.new(pos.X, bucket.landY, boardZ)
		ball.Position = pos
		local multAttr = bucket.part:GetAttribute("Multiplier")
		local multiplier = if typeof(multAttr) == "number"
			then multAttr
			else (risk.bucketMultipliers[bucket.index + 1] or 0)
		setBucketLandColor(bucket.part, multiplier, maxMultiplier, bucket.homeCFrame, bucket.homeSize)
		if connection then
			connection:Disconnect()
			connection = nil
		end
		Debris:AddItem(ball, 0.5)
		local landedIndex = bucket.index
		task.defer(function()
			if not cancelled then
				onLanded(landedIndex)
			end
			activeCancels[cleanup] = nil
		end)
	end

	local function collideRails(stepPos: Vector3, stepVel: Vector3, stepDt: number): (Vector3, Vector3)
		local minX = leftX + radius
		local maxX = rightX - radius
		local inwardNudge = math.min(leaveSpeed * 0.12, spacingX * 0.08)
		local railBand = math.max(spacingX * 0.85, radius * 2.5)
		if stepPos.X < minX then
			stepPos = Vector3.new(minX, stepPos.Y, boardZ)
			-- Kill outward skate; weak bounce + gentle push back into the board.
			stepVel = Vector3.new(inwardNudge, stepVel.Y * 0.88, 0)
		elseif stepPos.X > maxX then
			stepPos = Vector3.new(maxX, stepPos.Y, boardZ)
			stepVel = Vector3.new(-inwardNudge, stepVel.Y * 0.88, 0)
		else
			local nearRail = (stepPos.X - minX) < railBand or (maxX - stepPos.X) < railBand
			if nearRail and math.abs(stepVel.X) > leaveSpeed * 1.35 then
				-- Near-rail only: bleed excess horizontal speed before wall contact.
				local damp = math.clamp(1 - physics.railNearDamp * stepDt, 0.82, 1)
				stepVel = Vector3.new(stepVel.X * damp, stepVel.Y, 0)
			end
		end
		return stepPos, stepVel
	end

	local function collidePegs(stepPos: Vector3, stepVel: Vector3, now: number): (Vector3, Vector3)
		local leaveDeg = physics.leaveAngleDeg
		local apexNx = physics.apexNormalX
		local reflectBlend = math.clamp(physics.reflectBlend, 0, 1)
		local maxUp = physics.maxUpSpeed
		local restitution = cfg.BallBounce
		local clearSlack = math.max(0.14, radius * 0.18)
		local galtonLeaveX = physics.galtonLeaveX
		local minLeaveX = galtonLeaveX * 0.92

		for _, peg in pegs do
			local pegPos = peg.part.Position
			local delta = Vector3.new(stepPos.X - pegPos.X, stepPos.Y - pegPos.Y, 0)
			local dist = delta.Magnitude
			local minDist = radius + peg.radius
			if dist < 1e-5 then
				-- Exact center overlap: invent a side so the normal is defined.
				delta = Vector3.new(if rng:NextNumber() < 0.5 then -1 else 1, 0.25, 0)
				dist = delta.Magnitude
			end

			if peg.awaitingClear then
				-- Ghost this peg until the leave carries past it. Re-separating here
				-- fought gravity on the apex and pinned balls until X died.
				local cleared = stepPos.Y < (pegPos.Y - peg.radius * 0.25)
					or math.abs(stepPos.X - pegPos.X) >= (minDist + clearSlack)
					or dist >= (minDist + clearSlack)
				if cleared then
					peg.awaitingClear = false
				end
				continue
			end

			if dist < minDist and (now - peg.lastHit) >= physics.pegHitCooldown then
				local normal = delta.Unit

				local approaching = stepVel:Dot(normal)
				if approaching < 0 then
					-- Galton L/R from hit offset, with soft bias so inner-face clips
					-- don't always reverse to center and outer clips don't always edge-dump.
					local side: number
					local roll = rng:NextNumber()
					if math.abs(normal.X) < apexNx then
						side = if roll < 0.5 then -1 else 1
					else
						local prefer = if normal.X > 0 then 1 else -1
						side = if roll < 0.62 then prefer else -prefer
					end

					-- Separate onto the surface, then nudge along the leave side so the
					-- next substeps are already moving into the gap (not sitting on apex).
					local sep = minDist + 0.04
					stepPos = Vector3.new(
						pegPos.X + normal.X * sep + side * clearSlack * 0.25,
						pegPos.Y + normal.Y * sep,
						boardZ
					)

					-- Total leave speed for bounce feel; horizontal floored to Galton step
					-- so the ball reaches the next row near a peg (not a pure vertical drop).
					local ang = math.rad(rng:NextNumber(leaveDeg * 0.85, leaveDeg * 1.15))
					local impact = math.abs(approaching)
					local speed = leaveSpeed + 0.03 * math.max(0, impact - 14)
					local leaveX = math.max(speed * math.sin(ang), minLeaveX)
					local leaveY = -math.max(speed * math.cos(ang), leaveSpeed * 0.55)
					local leave = Vector3.new(side * leaveX, leaveY, 0)

					-- Mostly leave; small elastic reflect for visual bounce only.
					local reflected = stepVel - normal * ((1 + restitution) * approaching)
					local out = reflected * reflectBlend + leave * (1 - reflectBlend)

					-- Never let reflect/blend collapse the committed horizontal leave.
					if math.abs(out.X) < minLeaveX then
						out = Vector3.new(side * minLeaveX, out.Y, 0)
					end

					if out.Y > maxUp then
						out = Vector3.new(out.X, maxUp, 0)
					end
					-- Keep falling through the board (no pinball hang). Preserve leave X.
					if out.Y > -2.5 then
						out = Vector3.new(out.X, -2.5, 0)
					end
					stepVel = out
					peg.lastHit = now
					peg.awaitingClear = true
					flashPeg(peg.part)
				elseif dist < minDist * 0.98 then
					-- Overlap while moving away: separate without rewriting velocity.
					stepPos = Vector3.new(pegPos.X + normal.X * minDist, pegPos.Y + normal.Y * minDist, boardZ)
					peg.lastHit = now
				end
			end
		end
		return stepPos, stepVel
	end

	connection = RunService.Heartbeat:Connect(function(dt)
		if cancelled or finished then
			return
		end
		dt = math.clamp(dt, 0, 1 / 40)
		elapsed += dt
		if elapsed >= cfg.BallMaxSimSeconds then
			local bucket = resolveBucketAtX(buckets, pos.X)
			if bucket then
				finish(bucket)
			else
				failLand()
			end
			return
		end

		local substeps = math.max(1, math.floor(cfg.BallSubsteps))
		local stepDt = dt / substeps
		for _ = 1, substeps do
			-- Gravity + light air drag (does not erase impact sideways motion).
			local drag = math.clamp(1 - physics.horizontalDrag * stepDt, 0.92, 1)
			vel = Vector3.new(vel.X * drag, vel.Y - cfg.BallGravity * stepDt, 0)
			vel = clampSpeed(vel, cfg.BallMaxSpeed)
			pos = Vector3.new(pos.X + vel.X * stepDt, pos.Y + vel.Y * stepDt, boardZ)

			pos, vel = collideRails(pos, vel, stepDt)
			pos, vel = collidePegs(pos, vel, elapsed)
			vel = clampSpeed(vel, cfg.BallMaxSpeed)
		end

		ball.Position = pos

		if pos.Y <= landY then
			local bucket = resolveBucketAtX(buckets, pos.X)
			if bucket then
				finish(bucket)
			else
				failLand()
			end
		end
	end)

	return { cancel = cleanup }
end

return PlinkoBallPhysics
