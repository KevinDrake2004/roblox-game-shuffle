--!strict
--[[
	Casino sits on a real Terrain hill plateau.
	- Summit sits UNDER the part apron (no Grass near the resort - Ground/Rock only)
	- Outer slopes fall away; Grass only on far flanks
	- Tall north / flank ridge nests the game-room wing
	ArenaOrigins untouched.
]]

local Workspace = game:GetService("Workspace")

local CasinoTerrain = {}

local RESOLUTION = 4

local WALL_X = 94.0
local WALL_Z_S = 68.0
local WALL_Z_N = -142.0
local ROOM_WING_Z_S = -55.0

-- Plateau must fully cover WorldGrass (250 x 290 @ z=-20) so the apron never floats.
local PLATEAU_RX = 148.0
local PLATEAU_RZ_S = 155.0
local PLATEAU_RZ_N = 175.0

-- WorldGrass bottom ≈ -1.05; keep summit below that so blades never poke the floor.
local SUMMIT_Y = -1.3

-- No Grass within this many studs outside the plateau rim
local NO_GRASS_EDGE = 55.0

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
		-- Flat packed earth under the apron / building (below WorldGrass)
		if insideBuilding(x, z) then
			h = SUMMIT_Y - 0.4
		else
			h = SUMMIT_Y
		end
	elseif edge < 40 then
		-- Soft shoulder so the apron edge meets the hillside flush (no floating lip)
		local t = smoothstep(edge / 40)
		h = SUMMIT_Y - 10 * t + n * 0.4
	else
		local t = smoothstep(math.clamp((edge - 40) / 90, 0, 1))
		h = SUMMIT_Y - 10 - 30 * t + n * 2.0
	end

	-- Tall back ridge - rooms built into the hillside
	if z < ROOM_WING_Z_S then
		local behind = math.max(WALL_Z_N - z, 0)
		local along = math.clamp(1 - math.abs(z + 100) / 58, 0, 1)

		local ridge = 62 * math.exp(-((behind - 22) / 32) ^ 2) * (0.55 + 0.45 * along)
		if z >= WALL_Z_N - 12 and z <= ROOM_WING_Z_S then
			local dx = math.abs(x) - WALL_X
			if dx > -4 then
				local flank = 56 * math.exp(-((math.max(dx, 0) - 16) / 30) ^ 2) * along
				ridge = math.max(ridge, flank)
			end
		end
		if z < -115 and math.abs(x) > 70 then
			local shoulder = 40 * math.exp(-((math.abs(x) - 118) / 36) ^ 2) * math.exp(-((z + 160) / 34) ^ 2)
			ridge = math.max(ridge, shoulder)
		end

		h = math.max(h, ridge + n * 3)
	end

	return h
end

local function nearCasino(x: number, z: number): boolean
	return plateauEdgeDist(x, z) < NO_GRASS_EDGE
end

local function materialAt(x: number, z: number, y: number, surfaceY: number): Enum.Material
	local depth = surfaceY - y

	-- Near the resort: Ground / Rock / Slate only (Grass decorations poke through floors)
	if nearCasino(x, z) then
		if depth > 12 then
			return Enum.Material.Slate
		end
		if surfaceY > 16 and depth < 10 then
			return Enum.Material.Rock
		end
		return Enum.Material.Ground
	end

	if depth > 14 then
		return Enum.Material.Slate
	end
	if depth > 4 then
		return Enum.Material.Ground
	end
	if surfaceY > 18 and depth < 8 then
		if (math.floor(x / 7) + math.floor(z / 7)) % 4 == 0 then
			return Enum.Material.Rock
		end
	end
	-- Grass only on far outer slopes
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

	-- Carve air above the apron so nothing pokes walkways / plaza / interior.
	-- Do NOT carve the north ridge (z < ROOM_WING_Z_S) - that is intentional hillside.
	terrain:FillBlock(
		CFrame.new(0, 30, (WALL_Z_S + WALL_Z_N) * 0.5),
		Vector3.new(WALL_X * 2 - 2, 72, WALL_Z_S - WALL_Z_N - 2),
		Enum.Material.Air
	)
	-- Plaza / pit / approach only (south of room wing)
	terrain:FillBlock(CFrame.new(0, 28, 45), Vector3.new(300, 58, 210), Enum.Material.Air)

	print("[Shuffle] CasinoTerrain aligned plateau (no near-casino Grass)")
end

return CasinoTerrain
