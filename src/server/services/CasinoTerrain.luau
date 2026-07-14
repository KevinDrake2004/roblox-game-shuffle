--!strict
--[[
	Casino on a Terrain hill plateau.
	- Summit flush with the green apron (vibrant Grass, Decoration off = no blades)
	- Natural rise into the tall room wing at the back
	- Natural fall toward the front approach with room for a downhill walkway
	ArenaOrigins untouched.
]]

local Workspace = game:GetService("Workspace")

local CasinoTerrain = {}

local RESOLUTION = 4

local WALL_X = 94.0
local WALL_Z_S = 68.0
local WALL_Z_N = -142.0
local ROOM_WING_Z_S = -55.0

-- Flat summit covers shell + plaza; south rim sits just past the approach carpet.
-- Matches WorldGrass pad (~250 x 290 @ z=-20) without overhanging a cliff.
local PLATEAU_RX = 140.0
local PLATEAU_RZ_S = 118.0 -- south rim ~z=118 (spawn still on summit; slope beyond)
local PLATEAU_RZ_N = 165.0

-- Flush with WorldGrass (part at y=-0.55, top ≈ -0.05). Summit = pad top.
local SUMMIT_Y = -0.05

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
		-- Dirt under floors only; air-carved above after WriteVoxels
		return SUMMIT_Y - 2.0
	end

	if edge <= 0 then
		h = SUMMIT_Y + n * 0.08
	elseif edge < 55 then
		-- Wide soft shoulder: apron edge blends into the hillside (no floating lip)
		local t = smoothstep(edge / 55)
		h = SUMMIT_Y - 18 * t + n * 0.6
	else
		local t = smoothstep(math.clamp((edge - 55) / 100, 0, 1))
		h = SUMMIT_Y - 18 - 22 * t + n * 1.8
	end

	-- Front approach: extra downhill south of the facade so the walkway can descend
	if z > WALL_Z_S + 8 then
		local front = (z - (WALL_Z_S + 8)) / 70
		h = math.min(h, SUMMIT_Y - 22 * smoothstep(math.clamp(front, 0, 1)) + n * 0.8)
	end

	-- Back: natural slope UP into / behind the tall room wing
	if z < ROOM_WING_Z_S then
		local fromWing = ROOM_WING_Z_S - z -- 0 at wing south, grows north
		local rise = 12 * smoothstep(math.clamp(fromWing / 35, 0, 1))
		local behindWall = math.max(WALL_Z_N - z, 0)
		local crest = 70 * math.exp(-((behindWall - 28) / 36) ^ 2)
		local along = math.clamp(1 - math.abs(z + 100) / 62, 0, 1)
		local ridge = (rise + crest) * (0.5 + 0.5 * along)

		-- Wrap flanks so the rooms read as built into the hill
		if z >= WALL_Z_N - 20 and math.abs(x) > WALL_X - 8 then
			local dx = math.max(math.abs(x) - WALL_X, 0)
			local flank = 58 * math.exp(-((dx - 14) / 32) ^ 2) * along
			ridge = math.max(ridge, flank + rise)
		end

		if z < -110 and math.abs(x) > 65 then
			local shoulder = 48 * math.exp(-((math.abs(x) - 120) / 40) ^ 2) * math.exp(-((z + 165) / 38) ^ 2)
			ridge = math.max(ridge, shoulder)
		end

		h = math.max(h, ridge + n * 3.5)
	end

	return h
end

local function materialAt(_x: number, _z: number, y: number, surfaceY: number): Enum.Material
	local depth = surfaceY - y
	if depth > 16 then
		return Enum.Material.Slate
	end
	if depth > 5 then
		return Enum.Material.Ground
	end
	-- Rocky knuckles on steep high faces
	if surfaceY > 24 and depth < 9 then
		if (math.floor(_x / 8) + math.floor(_z / 8)) % 5 == 0 then
			return Enum.Material.Rock
		end
	end
	-- Vibrant green surface (Decoration is off - no blade poke-through)
	return Enum.Material.Grass
end

function CasinoTerrain.start()
	local terrain = Workspace.Terrain

	-- Grass color without decorative blades (blades were poking floors)
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

	-- Only hollow the building interior above the floor - do NOT carve the plateau summit
	terrain:FillBlock(
		CFrame.new(0, 32, (WALL_Z_S + WALL_Z_N) * 0.5),
		Vector3.new(WALL_X * 2 - 4, 68, WALL_Z_S - WALL_Z_N - 4),
		Enum.Material.Air
	)

	print("[Shuffle] CasinoTerrain flush green plateau + front/back slopes")
end

return CasinoTerrain
