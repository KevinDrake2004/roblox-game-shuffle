--!strict
--[[
	Casino Terrain: flat front under plaza + smooth walkable slope to a two-hill back range.

	Bakes once per place / server when ShuffleCasinoTerrainVersion matches.
	Bump VERSION to reshape; Play once, then Save the place.

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

local SURFACE = Enum.Material.LeafyGrass
local DIRT = Enum.Material.Ground
local ROCK = Enum.Material.Rock

local FRONT_TOP_Y = -1.5
local CREST_TOP_Y = 22.0
-- Shell depth ~210; start rise ~25% back from south facade (was ~50% at z=-40).
local RAMP_Z0 = WALL_Z_S - (WALL_Z_S - WALL_Z_N) * 0.25 -- ≈ 15.5
local RAMP_Z1 = -190.0

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

local function inBuildingPlan(x: number, z: number, margin: number): boolean
	return math.abs(x) <= WALL_X + margin and z <= WALL_Z_S + margin and z >= WALL_Z_N - margin
end

function CasinoTerrain.start()
	local terrain = Workspace.Terrain
	applySynthGreen(terrain)

	local baked = Workspace:GetAttribute("ShuffleCasinoTerrainVersion")
	if baked == VERSION then
		print(`[Shuffle] CasinoTerrain already baked (v{VERSION}) - skip`)
		return
	end

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
		local radius = 20
		local step = 7
		for z = RAMP_Z0, RAMP_Z1 - 40, -step do
			local top = rampTopY(z)
			local cy = top - radius * 0.78
			local xs: { number }
			if z > WALL_Z_N - 8 and z < WALL_Z_S + 8 then
				-- Flanks only - keep clear of the casino shell
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

		-- Soft north saddle into the back two-range (still smooth balls)
		fillBall(terrain, Vector3.new(-50, 8, -205), 62, SURFACE)
		fillBall(terrain, Vector3.new(50, 8, -205), 62, SURFACE)
		fillBall(terrain, Vector3.new(0, 2, -220), 55, SURFACE)
		fillBall(terrain, Vector3.new(-110, 0, -185), 42, SURFACE)
		fillBall(terrain, Vector3.new(110, 0, -185), 42, SURFACE)

		fillBall(terrain, Vector3.new(-48, 30, -195), 14, ROCK)
		fillBall(terrain, Vector3.new(48, 30, -195), 14, ROCK)

		-- Plaza / carpet relief only (do not flatten the early flank ramp)
		fillBlock(terrain, CFrame.new(0, 3.5, 95), Vector3.new(200, 12, 70), Enum.Material.Air)

		-- Hollow building + exterior margin so mounds never clip walls / rooms
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
		return
	end

	Workspace:SetAttribute("ShuffleCasinoTerrainVersion", VERSION)
	print(`[Shuffle] CasinoTerrain baked v{VERSION} (synth green, smooth ramp, shell cleared)`)
end

return CasinoTerrain
