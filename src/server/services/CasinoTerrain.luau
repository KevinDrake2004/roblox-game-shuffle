--!strict
--[[
	Casino sits on a real Terrain hill plateau.
	- Summit under the site (just below part floors / plaza) so walkways stay clean
	- Outer slopes fall away so the resort reads as perched on a big hill
	- Taller north / flank ridge nests the tall game-room wing into the hillside
	ArenaOrigins and wager loops untouched.
]]

local Workspace = game:GetService("Workspace")

local CasinoTerrain = {}

local RESOLUTION = 4

local WALL_X = 94.0
local WALL_Z_S = 68.0
local WALL_Z_N = -142.0
local ROOM_WING_Z_S = -55.0

-- Plateau ellipse (flat summit under casino + plaza)
local PLATEAU_RX = 128.0
local PLATEAU_RZ_S = 138.0 -- south toward spawn
local PLATEAU_RZ_N = 158.0 -- north behind rooms

local WIPE_MIN = Vector3.new(-280, -48, -300)
local WIPE_MAX = Vector3.new(280, 90, 220)

local HILL_MIN = Vector3.new(-260, -40, -280)
local HILL_MAX = Vector3.new(260, 80, 200)

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

-- 0 on/inside rim, >0 outside. Uses different south/north radii.
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

	if edge <= 0 then
		-- Flat summit: under part apron / floors (never bury walkways)
		if insideBuilding(x, z) then
			h = -1.4
		else
			h = -0.4 + n * 0.12
		end
	else
		-- Outer hill flanks: drop from summit rim down to lowlands
		local t = smoothstep(math.clamp(edge / 95, 0, 1))
		h = -0.35 - 32 * t + n * 2.2
	end

	-- Tall back ridge - rooms built into the hillside
	if z < ROOM_WING_Z_S then
		local behind = math.max(WALL_Z_N - z, 0)
		local along = math.clamp(1 - math.abs(z + 100) / 58, 0, 1)

		-- Peak just behind the north wall, higher than before
		local ridge = 62 * math.exp(-((behind - 22) / 32) ^ 2) * (0.55 + 0.45 * along)
		-- Extra mass when still beside the room wing (wrap around)
		if z >= WALL_Z_N - 12 and z <= ROOM_WING_Z_S then
			local dx = math.abs(x) - WALL_X
			if dx > -4 then
				local flank = 56 * math.exp(-((math.max(dx, 0) - 16) / 30) ^ 2) * along
				ridge = math.max(ridge, flank)
			end
		end
		-- NE / NW shoulders
		if z < -115 and math.abs(x) > 70 then
			local shoulder = 40 * math.exp(-((math.abs(x) - 118) / 36) ^ 2) * math.exp(-((z + 160) / 34) ^ 2)
			ridge = math.max(ridge, shoulder)
		end

		h = math.max(h, ridge + n * 3)
	end

	return h
end

local function materialAt(x: number, z: number, y: number, surfaceY: number): Enum.Material
	local depth = surfaceY - y
	if depth > 14 then
		return Enum.Material.Slate
	end
	if depth > 4 then
		return Enum.Material.Ground
	end
	-- Rocky faces on the steep back / flank
	if surfaceY > 18 and (z < WALL_Z_N + 8 or math.abs(x) > WALL_X + 8) and depth < 8 then
		if (math.floor(x / 7) + math.floor(z / 7)) % 4 == 0 then
			return Enum.Material.Rock
		end
	end
	return Enum.Material.Grass
end

function CasinoTerrain.start()
	local terrain = Workspace.Terrain

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
						occupancy[ix][iy][iz] = math.clamp(edge / RESOLUTION, 0.2, 1)
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

	-- Keep interiors / pit / plaza walk space clear above the summit pad
	terrain:FillBlock(
		CFrame.new(0, 30, (WALL_Z_S + WALL_Z_N) * 0.5),
		Vector3.new(WALL_X * 2 - 2, 72, WALL_Z_S - WALL_Z_N - 2),
		Enum.Material.Air
	)
	-- Plaza + approach: air above y=0 so asphalt / carpet / paths stay dominant
	terrain:FillBlock(CFrame.new(0, 22, 95), Vector3.new(200, 44, 90), Enum.Material.Air)

	print("[Shuffle] CasinoTerrain plateau + back-ridge written")
end

return CasinoTerrain
