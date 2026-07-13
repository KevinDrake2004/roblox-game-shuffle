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

-- Flash color + light only. Never tween Size/CFrame - that made buckets drift under multi-hit.
local function glowBucket(bucket: BasePart, color: Color3, homeCFrame: CFrame, homeSize: Vector3)
	pinBucket(bucket, homeCFrame, homeSize)

	local light = Instance.new("PointLight")
	light.Name = "LandGlow"
	light.Brightness = 4
	light.Range = 14
	light.Color = color
	light.Parent = bucket

	local originalColor = bucket.Color
	local flash = TweenService:Create(
		bucket,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Color = color }
	)
	local restore = TweenService:Create(
		bucket,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Color = originalColor }
	)
	flash:Play()
	flash.Completed:Connect(function()
		if bucket.Parent then
			pinBucket(bucket, homeCFrame, homeSize)
			restore:Play()
		end
	end)
	restore.Completed:Connect(function()
		if bucket.Parent then
			pinBucket(bucket, homeCFrame, homeSize)
		end
	end)
	Debris:AddItem(light, 0.7)
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
	local leftX = if left and left:IsA("BasePart")
		then left.Position.X + left.Size.X * 0.5
		else Config.PLINKO.ArenaOrigin.X - 13
	local rightX = if right and right:IsA("BasePart")
		then right.Position.X - right.Size.X * 0.5
		else Config.PLINKO.ArenaOrigin.X + 13
	return leftX, rightX
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
	local usableWidth = math.max(4, (rightX - leftX) - 0.8)
	local spacingX = usableWidth / rows
	local topY = origin.Position.Y - 1.5
	local bottomY = Config.PLINKO.ArenaOrigin.Y + 2.4
	local spacingY = math.max(1.1, (topY - bottomY) / rows)
	local boardZ = origin.Position.Z - 0.15
	local originX = Config.PLINKO.ArenaOrigin.X
	-- Leave speed scales with peg spacing so denser boards still Galton-step.
	local leaveSpeed = math.clamp(spacingX * 2.15, 3.8, 7.5)
	board:SetAttribute("RiskId", risk.id)
	board:SetAttribute("PegRows", rows)
	board:SetAttribute("LeaveSpeed", leaveSpeed)
	board:SetAttribute("SpacingX", spacingX)

	local pegSize = math.clamp(spacingX * 0.28, 0.4, 0.7)
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
			peg.Size = Vector3.new(pegSize, pegSize, pegSize)
			peg.Position = Vector3.new(startX + col * spacingX, y, boardZ)
			peg.Color = Config.COLORS.NeonPurple
			peg.Material = Enum.Material.Neon
			peg.Parent = pegsFolder
		end
	end

	local bucketWidth = spacingX * 0.92
	local bucketHeight = 2.0
	local bucketDepth = 2.0
	local bucketY = bottomY - 0.35
	local firstCenter = originX - (bucketCount - 1) * spacingX * 0.5
	for index = 0, bucketCount - 1 do
		local bucket = Instance.new("Part")
		bucket.Name = `Bucket_{index}`
		bucket.Anchored = true
		bucket.CanCollide = false
		bucket.CanQuery = false
		bucket.CanTouch = false
		bucket.CastShadow = false
		bucket.Size = Vector3.new(bucketWidth, bucketHeight, bucketDepth)
		bucket.Position = Vector3.new(firstCenter + index * spacingX, bucketY, boardZ)
		local mult = multipliers[index + 1] or 0
		if mult <= 0 then
			bucket.Color = Config.COLORS.NeonMagenta
		elseif mult >= risk.maxMultiplier * 0.5 then
			bucket.Color = Config.COLORS.NeonLime
		else
			bucket.Color = Config.COLORS.NeonPurple
		end
		bucket.Material = Enum.Material.Neon
		bucket.Parent = bucketsFolder
	end

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

local function resolveBucketAtX(buckets: { BucketInfo }, x: number): BucketInfo?
	if #buckets == 0 then
		return nil
	end
	for _, bucket in buckets do
		if x >= bucket.minX and x <= bucket.maxX then
			return bucket
		end
	end
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
	local radius = cfg.BallRadius
	local pegs = collectPegs(pegsFolder)
	local leftX, rightX = railBounds(arena)
	local boardZ = origin.Position.Z - 0.15
	local leaveSpeedAttr = if board then board:GetAttribute("LeaveSpeed") else nil
	local leaveSpeed = if typeof(leaveSpeedAttr) == "number" then leaveSpeedAttr else cfg.BallPegLeaveSpeed
	local landY = buckets[1].landY
	for _, bucket in buckets do
		landY = math.min(landY, bucket.landY)
	end
	local centerBucketIndex = math.floor((#buckets - 1) / 2)

	local rng = Random.new()
	local startSpread = math.max(0.15, cfg.BallStartSpeedX * 0.15)
	local pos = Vector3.new(origin.Position.X + rng:NextNumber(-startSpread, startSpread), origin.Position.Y, boardZ)
	local vel = Vector3.new(rng:NextNumber(-cfg.BallStartSpeedX, cfg.BallStartSpeedX), rng:NextNumber(-2, 0), 0)

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
		local glowColor = if bucket.index == centerBucketIndex
			then Config.COLORS.NeonMagenta
			else Config.COLORS.NeonLime
		glowBucket(bucket.part, glowColor, bucket.homeCFrame, bucket.homeSize)
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

	local function collideRails(stepPos: Vector3, stepVel: Vector3): (Vector3, Vector3)
		local minX = leftX + radius
		local maxX = rightX - radius
		if stepPos.X < minX then
			stepPos = Vector3.new(minX, stepPos.Y, boardZ)
			stepVel = Vector3.new(math.abs(stepVel.X) * cfg.BallBounce, stepVel.Y * 0.95, 0)
		elseif stepPos.X > maxX then
			stepPos = Vector3.new(maxX, stepPos.Y, boardZ)
			stepVel = Vector3.new(-(math.abs(stepVel.X) * cfg.BallBounce), stepVel.Y * 0.95, 0)
		end
		return stepPos, stepVel
	end

	local function collidePegs(stepPos: Vector3, stepVel: Vector3, now: number): (Vector3, Vector3)
		local leaveDeg = cfg.BallPegLeaveAngleDeg
		local apexNx = cfg.BallPegApexNormalX
		local reflectBlend = math.clamp(cfg.BallPegReflectBlend, 0, 1)
		local maxUp = cfg.BallPegMaxUpSpeed
		local restitution = cfg.BallBounce

		for _, peg in pegs do
			local delta = Vector3.new(stepPos.X - peg.part.Position.X, stepPos.Y - peg.part.Position.Y, 0)
			local dist = delta.Magnitude
			local minDist = radius + peg.radius
			if dist < 1e-5 then
				-- Exact center overlap: invent a side so the normal is defined.
				delta = Vector3.new(if rng:NextNumber() < 0.5 then -1 else 1, 0.25, 0)
				dist = delta.Magnitude
			end
			if dist < minDist and (now - peg.lastHit) >= cfg.BallPegHitCooldown then
				local normal = delta.Unit
				-- Separate so the ball sits on the peg surface.
				stepPos = Vector3.new(
					peg.part.Position.X + normal.X * minDist,
					peg.part.Position.Y + normal.Y * minDist,
					boardZ
				)

				local approaching = stepVel:Dot(normal)
				if approaching < 0 then
					-- Galton L/R from hit offset. Dead-center is unstable → coin-flip.
					local side: number
					if math.abs(normal.X) < apexNx then
						side = if rng:NextNumber() < 0.5 then -1 else 1
					else
						side = if normal.X > 0 then 1 else -1
					end

					-- Characteristic roll-off leave velocity (angle from vertical).
					-- Tuned so each row ≈ one ± half-spacing step → binomial lands.
					local ang = math.rad(rng:NextNumber(leaveDeg * 0.8, leaveDeg * 1.2))
					local impact = math.abs(approaching)
					local speed = leaveSpeed + 0.06 * math.max(0, impact - 12)
					local leave = Vector3.new(side * speed * math.sin(ang), -speed * math.cos(ang), 0)

					-- Elastic reflect along contact normal (visual bounce), blended with leave.
					local reflected = stepVel - normal * ((1 + restitution) * approaching)
					local out = reflected * reflectBlend + leave * (1 - reflectBlend)

					if out.Y > maxUp then
						out = Vector3.new(out.X, maxUp, 0)
					end
					-- Keep falling through the board (no pinball hang).
					if out.Y > -2.5 then
						out = Vector3.new(out.X, -2.5, 0)
					end
					stepVel = out
					peg.lastHit = now
					flashPeg(peg.part)
				elseif dist < minDist * 0.98 then
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
		dt = math.clamp(dt, 0, 1 / 20)
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
			local drag = math.clamp(1 - cfg.BallHorizontalDrag * stepDt, 0.92, 1)
			vel = Vector3.new(vel.X * drag, vel.Y - cfg.BallGravity * stepDt, 0)
			vel = clampSpeed(vel, cfg.BallMaxSpeed)
			pos = Vector3.new(pos.X + vel.X * stepDt, pos.Y + vel.Y * stepDt, boardZ)

			pos, vel = collideRails(pos, vel)
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
