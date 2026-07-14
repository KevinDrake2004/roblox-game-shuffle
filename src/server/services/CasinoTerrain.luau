--!strict
--[[
	Casino Terrain: flat front under plaza + smooth walkable slope to a two-hill back range.

	Bakes Terrain once per place / server when ShuffleCasinoTerrainVersion matches.
	-- Pavement + lamps always refresh; heights use FillBall crest (rampTopY + 0.22*radius), not rampTopY alone.

	Uses LeafyGrass recolored to match WorldGrass (synthetic green, no grass blades).
	Slope is overlapping FillBalls (no block steps). Building shell is air-carved with margin.
	Spawn stays at (0, 3, 112). ArenaOrigins unchanged.
]]

local Workspace = game:GetService("Workspace")

local CasinoTerrain = {}

-- Bump when reshaping hills so servers / Studio rebuild once.
local VERSION = 6

local WALL_X = 94.0
local WALL_Z_S = 68.0
local WALL_Z_N = -142.0

-- Match WorldGrass part color in rebuild_casino_polish.py (GRASS = 0.18, 0.42, 0.16)
local SYNTH_GREEN = Color3.new(0.18, 0.42, 0.16)
local ASPHALT = Color3.new(0.12, 0.12, 0.14)
local STONE = Color3.new(0.45, 0.42, 0.4)
local GOLD = Color3.new(0.85, 0.65, 0.2)
local METAL = Color3.new(0.12, 0.12, 0.14)
local WARM = Color3.new(1, 0.85, 0.55)

local SURFACE = Enum.Material.LeafyGrass
local DIRT = Enum.Material.Ground
local ROCK = Enum.Material.Rock

local FRONT_TOP_Y = -1.5
local CREST_TOP_Y = 22.0
-- Shell depth ~210; start rise ~25% back from south facade.
local RAMP_Z0 = WALL_Z_S - (WALL_Z_S - WALL_Z_N) * 0.25 -- ≈ 15.5
local RAMP_Z1 = -190.0

-- Must match FillBall radius used for the walkable ramp.
local RAMP_BALL_RADIUS = 20.0
-- Centers are placed at rampTopY - radius*0.78, so the crest is +radius*0.22 above rampTopY.
local RAMP_BALL_CREST_EXTRA = RAMP_BALL_RADIUS * 0.22
-- Extra clearance for voxel smoothing + pavement thickness so parts sit ON the grass.
local PATH_SURFACE_CLEARANCE = 1.25

-- Flank path sits on the Terrain ramp balls (|x| ≈ 120–155).
local PATH_X = { -128.0, 128.0 }
local PATH_WIDTH = 10.0
local PATH_THICKNESS = 0.55
local PATH_SEG = 7.0
local PATH_Z_START = WALL_Z_S + 4.0 -- south facade corners
local PATH_Z_END = WALL_Z_N - 12.0 -- past the north wall / back of casino
local LAMP_SPACING = 28.0
local LAMP_OUTSET = 7.0 -- lamps sit just outside the pavement

local function fillBall(terrain: Terrain, pos: Vector3, radius: number, material: Enum.Material)
	terrain:FillBall(pos, radius, material)
end

local function fillBlock(terrain: Terrain, cf: CFrame, size: Vector3, material: Enum.Material)
	terrain:FillBlock(cf, size, material)
end

local function applySynthGreen(terrain: Terrain)
	terrain:SetMaterialColor(SURFACE, SYNTH_GREEN)
	terrain:SetMaterialColor(Enum.Material.Grass, SYNTH_GREEN)
end

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function rampTopY(z: number): number
	if z >= RAMP_Z0 then
		return FRONT_TOP_Y
	end
	if z <= RAMP_Z1 then
		return CREST_TOP_Y
	end
	local t = smoothstep((RAMP_Z0 - z) / (RAMP_Z0 - RAMP_Z1))
	return FRONT_TOP_Y + t * (CREST_TOP_Y - FRONT_TOP_Y)
end

-- Actual Terrain grass crest under the flank path (FillBall peak, not rampTopY alone).
local function terrainCrestY(z: number): number
	if z >= RAMP_Z0 then
		-- Flat front pad top is FRONT_TOP_Y
		return FRONT_TOP_Y
	end
	return rampTopY(z) + RAMP_BALL_CREST_EXTRA
end

-- Part center Y so pavement top sits clearly above Terrain.
local function pathY(z: number): number
	local plazaCenter = 0.28 + PATH_THICKNESS * 0.5
	local onRampCenter = terrainCrestY(z) + PATH_SURFACE_CLEARANCE + PATH_THICKNESS * 0.5
	if z >= RAMP_Z0 then
		return plazaCenter
	end
	return math.max(plazaCenter, onRampCenter)
end

-- Walkable top of the pavement (lamp bases sit here).
local function pathSurfaceY(z: number): number
	return pathY(z) + PATH_THICKNESS * 0.5
end

local function inBuildingPlan(x: number, z: number, margin: number): boolean
	return math.abs(x) <= WALL_X + margin and z <= WALL_Z_S + margin and z >= WALL_Z_N - margin
end

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = canCollide
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function addStreetLamp(parent: Instance, name: string, x: number, z: number, groundY: number, yawDeg: number)
	local yaw = math.rad(yawDeg)
	local gy = groundY

	makePart(
		parent,
		name .. "_Base",
		Vector3.new(1.2, 0.35, 1.2),
		CFrame.new(x, gy + 0.4, z),
		STONE,
		Enum.Material.Concrete,
		false
	)
	makePart(
		parent,
		name .. "_Pole",
		Vector3.new(0.35, 12.0, 0.35),
		CFrame.new(x, gy + 6.4, z),
		METAL,
		Enum.Material.Metal,
		false
	)
	makePart(
		parent,
		name .. "_Collar",
		Vector3.new(0.55, 0.25, 0.55),
		CFrame.new(x, gy + 12.2, z),
		GOLD,
		Enum.Material.Metal,
		false
	)

	local armLen = 2.4
	local ax = x + armLen * 0.5 * math.sin(yaw)
	local az = z + armLen * 0.5 * math.cos(yaw)
	local arm = makePart(
		parent,
		name .. "_Arm",
		Vector3.new(0.25, 0.25, armLen),
		CFrame.new(ax, gy + 12.35, az) * CFrame.Angles(0, yaw, 0),
		METAL,
		Enum.Material.Metal,
		false
	)
	arm.Name = name .. "_Arm"

	local hx = x + armLen * math.sin(yaw)
	local hz = z + armLen * math.cos(yaw)
	makePart(
		parent,
		name .. "_Head",
		Vector3.new(1.1, 0.55, 1.1),
		CFrame.new(hx, gy + 12.1, hz),
		METAL,
		Enum.Material.Metal,
		false
	)

	local glow = makePart(
		parent,
		name .. "_Glow",
		Vector3.new(0.7, 0.35, 0.7),
		CFrame.new(hx, gy + 11.85, hz),
		WARM,
		Enum.Material.Neon,
		false
	)
	glow.Transparency = 0.15

	local lightHost = makePart(
		parent,
		name .. "_Light",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(hx, gy + 11.5, hz),
		WARM,
		Enum.Material.SmoothPlastic,
		false
	)
	lightHost.Transparency = 1
	local pl = Instance.new("PointLight")
	pl.Brightness = 2.8
	pl.Range = 48
	pl.Color = WARM
	pl.Parent = lightHost
end

local function buildRampWalkway()
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		warn("[Shuffle] CasinoTerrain: Lobby missing - skip RampWalkway")
		return
	end

	local atmosphere = lobby:FindFirstChild("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Folder")
		atmosphere.Name = "Atmosphere"
		atmosphere.Parent = lobby
	end

	local existing = atmosphere:FindFirstChild("RampWalkway")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "RampWalkway"
	folder.Parent = atmosphere

	for _, pathX in PATH_X do
		local sideName = if pathX < 0 then "W" else "E"
		local lampX = if pathX < 0 then pathX - LAMP_OUTSET else pathX + LAMP_OUTSET
		-- Arms face the pavement (toward path centerline)
		local lampYaw = if pathX < 0 then 90.0 else -90.0

		local segIndex = 0
		local z = PATH_Z_START
		while z > PATH_Z_END do
			local z1 = math.max(z - PATH_SEG, PATH_Z_END)
			local y0 = pathY(z)
			local y1 = pathY(z1)
			local mid = Vector3.new(pathX, (y0 + y1) * 0.5, (z + z1) * 0.5)
			local dz = z - z1 -- positive length along -Z travel
			local dy = y1 - y0
			local length = math.sqrt(dz * dz + dy * dy)
			local pitch = math.atan2(dy, dz)
			local cf = CFrame.new(mid) * CFrame.Angles(pitch, 0, 0)
			makePart(
				folder,
				`Path_{sideName}_{segIndex}`,
				Vector3.new(PATH_WIDTH, PATH_THICKNESS, length + 0.2),
				cf,
				ASPHALT,
				Enum.Material.Asphalt,
				true
			)
			-- Thin gold edge toward the building
			local edgeX = if pathX < 0 then pathX + PATH_WIDTH * 0.5 - 0.15 else pathX - PATH_WIDTH * 0.5 + 0.15
			local edgeMid = Vector3.new(edgeX, mid.Y + 0.1, mid.Z)
			makePart(
				folder,
				`PathEdge_{sideName}_{segIndex}`,
				Vector3.new(0.25, 0.12, length + 0.15),
				CFrame.new(edgeMid) * CFrame.Angles(pitch, 0, 0),
				GOLD,
				Enum.Material.Metal,
				false
			)

			segIndex += 1
			z = z1
			if z1 <= PATH_Z_END then
				break
			end
		end

		-- Small landing pad at the back of the casino
		local landZ = PATH_Z_END
		local landY = pathY(landZ)
		makePart(
			folder,
			`Landing_{sideName}`,
			Vector3.new(PATH_WIDTH + 4, PATH_THICKNESS, 14),
			CFrame.new(pathX, landY, landZ - 4),
			ASPHALT,
			Enum.Material.Asphalt,
			true
		)

		-- Street lamps along the outer edge (bases on pavement top)
		local lampI = 0
		local lz = PATH_Z_START - 4
		while lz >= PATH_Z_END do
			addStreetLamp(folder, `RampLamp_{sideName}{lampI}`, lampX, lz, pathSurfaceY(lz), lampYaw)
			lampI += 1
			lz -= LAMP_SPACING
		end
		-- Final lamp on the back landing
		addStreetLamp(folder, `RampLamp_{sideName}End`, lampX, PATH_Z_END - 2, pathSurfaceY(PATH_Z_END - 2), lampYaw)
	end

	print(`[Shuffle] RampWalkway built ({PATH_Z_START} → {PATH_Z_END})`)
end

function CasinoTerrain.start()
	local terrain = Workspace.Terrain
	applySynthGreen(terrain)

	local baked = Workspace:GetAttribute("ShuffleCasinoTerrainVersion")
	if baked ~= VERSION then
		local ok, err = pcall(function()
			terrain:Clear()
			applySynthGreen(terrain)

			-- Deep base under the whole resort
			fillBlock(terrain, CFrame.new(0, -18, -40), Vector3.new(400, 32, 440), DIRT)

			-- Flat front under plaza / WorldGrass only (stop before ramp toe)
			local flatDepth = 200.0
			local flatCenterZ = RAMP_Z0 + flatDepth * 0.5
			fillBlock(terrain, CFrame.new(0, FRONT_TOP_Y - 8, flatCenterZ), Vector3.new(300, 16, flatDepth), SURFACE)

			-- Smooth walkable ramp: dense overlapping balls, surface follows rampTopY
			local radius = RAMP_BALL_RADIUS
			local step = 7
			for z = RAMP_Z0, RAMP_Z1 - 40, -step do
				local top = rampTopY(z)
				local cy = top - radius * 0.78
				local xs: { number }
				if z > WALL_Z_N - 8 and z < WALL_Z_S + 8 then
					xs = { -155, -135, -120, 120, 135, 155 }
				else
					xs = { -130, -95, -55, -20, 20, 55, 95, 130 }
				end
				for _, x in xs do
					if not inBuildingPlan(x, z, 8) then
						fillBall(terrain, Vector3.new(x, cy, z), radius, SURFACE)
					end
				end
			end

			fillBall(terrain, Vector3.new(-50, 8, -205), 62, SURFACE)
			fillBall(terrain, Vector3.new(50, 8, -205), 62, SURFACE)
			fillBall(terrain, Vector3.new(0, 2, -220), 55, SURFACE)
			fillBall(terrain, Vector3.new(-110, 0, -185), 42, SURFACE)
			fillBall(terrain, Vector3.new(110, 0, -185), 42, SURFACE)

			fillBall(terrain, Vector3.new(-48, 30, -195), 14, ROCK)
			fillBall(terrain, Vector3.new(48, 30, -195), 14, ROCK)

			fillBlock(terrain, CFrame.new(0, 3.5, 95), Vector3.new(200, 12, 70), Enum.Material.Air)

			local midZ = (WALL_Z_S + WALL_Z_N) * 0.5
			fillBlock(
				terrain,
				CFrame.new(0, 40, midZ),
				Vector3.new(WALL_X * 2 + 28, 90, WALL_Z_S - WALL_Z_N + 28),
				Enum.Material.Air
			)
		end)

		if not ok then
			warn(`[Shuffle] CasinoTerrain failed: {err}`)
		else
			Workspace:SetAttribute("ShuffleCasinoTerrainVersion", VERSION)
			print(`[Shuffle] CasinoTerrain baked v{VERSION} (synth green, smooth ramp, shell cleared)`)
		end
	else
		print(`[Shuffle] CasinoTerrain already baked (v{VERSION}) - skip`)
	end

	-- Pavement + lamps always refresh so they stay locked to rampTopY
	local walkOk, walkErr = pcall(buildRampWalkway)
	if not walkOk then
		warn(`[Shuffle] RampWalkway failed: {walkErr}`)
	end
end

return CasinoTerrain
