--!strict
--[=[
	@class PlinkoBallPhysics
	Local-only gravity + peg bounce simulation for Plinko Points.

	The path is **not** predetermined. A Galton peg layout plus gravity and
	elastic-ish peg collisions decide the land. No soft bias toward a bucket.
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
}

type SimHandles = {
	cancel: () -> (),
}

local activeCancel: (() -> ())? = nil

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

local function flashPeg(part: BasePart)
	local original = part.Color
	part.Color = Color3.fromRGB(255, 240, 255)
	task.delay(0.08, function()
		if part.Parent then
			part.Color = original
		end
	end)
end

local function glowBucket(bucket: BasePart, color: Color3)
	local light = Instance.new("PointLight")
	light.Name = "LandGlow"
	light.Brightness = 4
	light.Range = 14
	light.Color = color
	light.Parent = bucket

	local baseSize = bucket.Size
	local grow = TweenService:Create(
		bucket,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = baseSize + Vector3.new(0.35, 0.35, 0.35) }
	)
	local shrink = TweenService:Create(
		bucket,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = baseSize }
	)
	grow:Play()
	grow.Completed:Connect(function()
		if bucket.Parent then
			shrink:Play()
		end
	end)
	Debris:AddItem(light, 0.7)
end

local function collectPegs(arena: Folder): { PegState }
	local pegs: { PegState } = {}
	local folder = arena:FindFirstChild("Pegs")
	if not folder then
		return pegs
	end
	for _, child in folder:GetChildren() do
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

local function collectBuckets(arena: Folder): { BucketInfo }
	local list: { BucketInfo } = {}
	local folder = arena:FindFirstChild("Buckets")
	if not folder then
		return list
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			local index = tonumber(string.match(child.Name, "^Bucket_(%d+)$"))
			if index ~= nil then
				local half = child.Size.X * 0.5
				table.insert(list, {
					index = index,
					part = child,
					minX = child.Position.X - half,
					maxX = child.Position.X + half,
					centerX = child.Position.X,
					landY = child.Position.Y + child.Size.Y * 0.35,
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
	Cancel any in-flight local ball simulation.
]=]
function PlinkoBallPhysics.cancel()
	if activeCancel then
		activeCancel()
		activeCancel = nil
	end
	local camera = Workspace.CurrentCamera
	local folder = if camera then camera:FindFirstChild("PlinkoLocalFx") else nil
	if folder then
		folder:ClearAllChildren()
	end
end

--[=[
	Run a free local gravity/peg bounce drop. Landing bucket is decided by physics.

	@param onLanded (bucketIndex: number) -> () -- 0-based bucket the ball actually entered
	@return SimHandles
]=]
function PlinkoBallPhysics.drop(onLanded: (bucketIndex: number) -> ()): SimHandles
	PlinkoBallPhysics.cancel()

	local arena = getArena()
	local cancelled = false
	local connection: RBXScriptConnection? = nil

	local function cleanup()
		cancelled = true
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if activeCancel == cleanup then
			activeCancel = nil
		end
	end
	activeCancel = cleanup

	local function failLand()
		if cancelled then
			return
		end
		local fallback = math.floor((#Config.PLINKO.BucketMultipliers - 1) / 2)
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

	local buckets = collectBuckets(arena)
	if #buckets == 0 then
		failLand()
		return { cancel = cleanup }
	end

	local cfg = Config.PLINKO
	local radius = cfg.BallRadius
	local pegs = collectPegs(arena)
	local leftX, rightX = railBounds(arena)
	local boardZ = origin.Position.Z
	local landY = buckets[1].landY
	for _, bucket in buckets do
		landY = math.min(landY, bucket.landY)
	end

	local rng = Random.new()
	local startSpread = math.max(0.15, cfg.BallStartSpeedX * 0.15)
	local pos = Vector3.new(origin.Position.X + rng:NextNumber(-startSpread, startSpread), origin.Position.Y, boardZ)
	local vel = Vector3.new(rng:NextNumber(-cfg.BallStartSpeedX, cfg.BallStartSpeedX), rng:NextNumber(-2, 0), 0)

	local fx = getLocalFxFolder()
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
	ball.Parent = fx

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
		local glowColor = if bucket.index == 4 then Config.COLORS.NeonMagenta else Config.COLORS.NeonLime
		glowBucket(bucket.part, glowColor)
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
			if activeCancel == cleanup then
				activeCancel = nil
			end
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
		for _, peg in pegs do
			local delta = Vector3.new(stepPos.X - peg.part.Position.X, stepPos.Y - peg.part.Position.Y, 0)
			local dist = delta.Magnitude
			local minDist = radius + peg.radius
			if dist < 1e-5 then
				-- Exact center overlap: nudge sideways so reflection has a normal.
				delta = Vector3.new(if rng:NextNumber() < 0.5 then -1 else 1, 0.2, 0)
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
					-- Reflect the approach component; keep tangential slide.
					local reflected = stepVel - normal * ((1 + cfg.BallBounce) * approaching)
					-- Tiny tangential noise only - impact direction still dominates.
					local tangent = Vector3.new(-normal.Y, normal.X, 0)
					local jitter = tangent * rng:NextNumber(-0.8, 0.8)
					stepVel = reflected + jitter
					peg.lastHit = now
					flashPeg(peg.part)
				elseif dist < minDist * 0.98 then
					-- Still overlapping while moving away: push out without rewriting velocity.
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
