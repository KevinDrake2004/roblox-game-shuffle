--!strict
--[[
	Casino on a Terrain hill.
	Safe rules:
	- Never FillBlock-carve the plaza / spawn (that wiped the play area white)
	- HubSpawn stays outside at (0, 3, 112)
	- Green Grass surface with Decoration off (color match, no blade poke-through)
	- Tall back ridge for room wing; gentle front fall only south of spawn
]]

local Workspace = game:GetService("Workspace")

local CasinoTerrain = {}

local RESOLUTION = 4

local WALL_X = 94.0
local WALL_Z_S = 68.0
local WALL_Z_N = -142.0
local ROOM_WING_Z_S = -55.0

-- Cover WorldGrass (250x290 @ z=-20) fully
local PLATEAU_RX = 145.0
local PLATEAU_RZ_S = 150.0
local PLATEAU_RZ_N = 170.0

-- Meet WorldGrass pad (part Y=-0.55)
local SUMMIT_Y = -0.55

-- Front downhill starts south of spawn/path (spawn Z=112)
local FRONT_SLOPE_Z = 145.0

local WIPE_MIN = Vector3.new(-280, -48, -300)
local WIPE_MAX = Vector3.new(280, 90, 220)

local HILL_MIN = Vector3.new(-260, -40, -280)
local HILL_MAX = Vector3.new(260, 85, 200)

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function noise2(x: number, z: number): number
	return math.sin(x * 0.045) * math.cos(z * 0.038) * 0.5
		+ math.sin(x * 0.11 + z * 0.07) * 0.25
		+ math.sin(z * 0.09 - x * 0.05) * 0.2
end

local function insideBuilding(x: number, z: number): boolean
	return math.abs(x) <= WALL_X and z <= WALL_Z_S and z >= WALL_Z_N
end

local function plateauEdgeDist(x: number, z: number): number
	local nx = x / PLATEAU_RX
	local nz = if z >= 0 then z / PLATEAU_RZ_S else z / PLATEAU_RZ_N
	local r = math.sqrt(nx * nx + nz * nz)
	return (r - 1) * ((PLATEAU_RX + PLATEAU_RZ_S) * 0.5)
end

local function surfaceHeight(x: number, z: number): number
	local n = noise2(x, z)
	local edge = plateauEdgeDist(x, z)
	local h: number

	if insideBuilding(x, z) then
		-- Sub-floor fill only
		return SUMMIT_Y - 2.5
	end

	if edge <= 0 then
		h = SUMMIT_Y + n * 0.05
	elseif edge < 45 then
		local t = smoothstep(edge / 45)
		h = SUMMIT_Y - 12 * t + n * 0.5
	else
		local t = smoothstep(math.clamp((edge - 45) / 95, 0, 1))
		h = SUMMIT_Y - 12 - 24 * t + n * 1.6
	end

	-- Front fall only past spawn / south path - keep plaza flat
	if z > FRONT_SLOPE_Z then
		local front = (z - FRONT_SLOPE_Z) / 55
		h = math.min(h, SUMMIT_Y - 20 * smoothstep(math.clamp(front, 0, 1)) + n * 0.6)
	end

	-- Back: natural rise into tall room wing
	if z < ROOM_WING_Z_S then
		local fromWing = ROOM_WING_Z_S - z
		local rise = 14 * smoothstep(math.clamp(fromWing / 40, 0, 1))
		local behindWall = math.max(WALL_Z_N - z, 0)
		local crest = 68 * math.exp(-((behindWall - 26) / 34) ^ 2)
		local along = math.clamp(1 - math.abs(z + 100) / 60, 0, 1)
		local ridge = (rise + crest) * (0.55 + 0.45 * along)

		if z >= WALL_Z_N - 18 and math.abs(x) > WALL_X - 6 then
			local dx = math.max(math.abs(x) - WALL_X, 0)
			local flank = 55 * math.exp(-((dx - 14) / 30) ^ 2) * along
			ridge = math.max(ridge, flank + rise)
		end

		if z < -110 and math.abs(x) > 65 then
			local shoulder = 45 * math.exp(-((math.abs(x) - 120) / 38) ^ 2) * math.exp(-((z + 162) / 36) ^ 2)
			ridge = math.max(ridge, shoulder)
		end

		h = math.max(h, ridge + n * 3)
	end

	return h
end

local function materialAt(x: number, z: number, y: number, surfaceY: number): Enum.Material
	local depth = surfaceY - y
	if depth > 16 then
		return Enum.Material.Slate
	end
	if depth > 5 then
		return Enum.Material.Ground
	end
	if surfaceY > 22 and depth < 9 then
		if (math.floor(x / 8) + math.floor(z / 8)) % 5 == 0 then
			return Enum.Material.Rock
		end
	end
	return Enum.Material.Grass
end

function CasinoTerrain.start()
	local terrain = Workspace.Terrain

	-- Green Grass color without decorative blades poking floors
	terrain.Decoration = false

	local wipe = Region3.new(WIPE_MIN, WIPE_MAX):ExpandToGrid(RESOLUTION)
	terrain:FillRegion(wipe, RESOLUTION, Enum.Material.Air)

	local region = Region3.new(HILL_MIN, HILL_MAX):ExpandToGrid(RESOLUTION)
	local size = region.Size / RESOLUTION
	local sizeX = math.floor(size.X + 0.5)
	local sizeY = math.floor(size.Y + 0.5)
	local sizeZ = math.floor(size.Z + 0.5)

	local materials = table.create(sizeX)
	local occupancy = table.create(sizeX)
	local corner = region.CFrame.Position - region.Size / 2

	for ix = 1, sizeX do
		materials[ix] = table.create(sizeY)
		occupancy[ix] = table.create(sizeY)
		local worldX = corner.X + (ix - 0.5) * RESOLUTION
		for iy = 1, sizeY do
			materials[ix][iy] = table.create(sizeZ)
			occupancy[ix][iy] = table.create(sizeZ)
			local worldY = corner.Y + (iy - 0.5) * RESOLUTION
			for iz = 1, sizeZ do
				local worldZ = corner.Z + (iz - 0.5) * RESOLUTION
				local top = surfaceHeight(worldX, worldZ)

				if worldY <= top and worldY >= HILL_MIN.Y + 1 then
					materials[ix][iy][iz] = materialAt(worldX, worldZ, worldY, top)
					local edge = top - worldY
					if edge < RESOLUTION then
						occupancy[ix][iy][iz] = math.clamp(edge / RESOLUTION, 0.25, 1)
					else
						occupancy[ix][iy][iz] = 1
					end
				else
					materials[ix][iy][iz] = Enum.Material.Air
					occupancy[ix][iy][iz] = 0
				end
			end
		end
	end

	terrain:WriteVoxels(region, RESOLUTION, materials, occupancy)

	-- Hollow building interiors ONLY (above floors). Never carve plaza/spawn.
	terrain:FillBlock(
		CFrame.new(0, 36, (WALL_Z_S + WALL_Z_N) * 0.5),
		Vector3.new(WALL_X * 2 - 6, 60, WALL_Z_S - WALL_Z_N - 6),
		Enum.Material.Air
	)

	print("[Shuffle] CasinoTerrain safe plateau (spawn outside, plaza intact)")
end

return CasinoTerrain
