--!strict
--[[
	Real Roblox Terrain heightmap - BACK of the casino only.
	Hides the tall game-room wing (north / flanks). Does NOT paint plaza,
	walkways, pit, or building interior. ArenaOrigins untouched.
]]

local Workspace = game:GetService("Workspace")

local CasinoTerrain = {}

local RESOLUTION = 4

-- Building envelope
local WALL_X = 94.0
local WALL_Z_N = -142.0
-- South limit of the tall room wing (~origins at z=-110). No hills south of this.
local ROOM_WING_Z_S = -55.0

-- Full wipe bounds (clears any prior mistaken plaza / interior terrain)
local WIPE_MIN = Vector3.new(-240, -28, -280)
local WIPE_MAX = Vector3.new(240, 80, 200)

-- Write bounds: north ridge + room-wing flanks only
local HILL_MIN = Vector3.new(-210, -24, -260)
local HILL_MAX = Vector3.new(210, 72, ROOM_WING_Z_S)

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
	return math.abs(x) <= WALL_X and z <= 68 and z >= WALL_Z_N
end

-- Height above y=0, or nil = leave Air (no terrain here).
local function surfaceHeight(x: number, z: number): number?
	-- Never inside the shell
	if insideBuilding(x, z) then
		return nil
	end
	-- Never south of the room wing (plaza, pit, walkways, entrance)
	if z > ROOM_WING_Z_S then
		return nil
	end

	local n = noise2(x, z)
	local h = 0.0

	-- North ridge behind the room-wing wall
	if z < WALL_Z_N then
		local d = WALL_Z_N - z
		local ridge = 48 * math.exp(-((d - 16) / 26) ^ 2)
		local fall = smoothstep(1 - d / 100)
		h = math.max(h, ridge * fall + n * 4)
	end

	-- East / west flanks outside the tall room wing only
	if z <= ROOM_WING_Z_S and z >= WALL_Z_N - 8 then
		local dx = math.abs(x) - WALL_X
		if dx > 2 then
			local flank = 38 * math.exp(-((dx - 20) / 24) ^ 2)
			local zFade = 1 - math.abs(z + 97) / 52
			h = math.max(h, flank * math.clamp(zFade, 0, 1) + n * 3)
		end
	end

	-- NE / NW corner blend (still behind / beside rooms)
	if z < -120 and math.abs(x) > 75 then
		local corner = 30 * math.exp(-((math.abs(x) - 112) / 32) ^ 2) * math.exp(-((z + 158) / 28) ^ 2)
		h = math.max(h, corner + n * 2)
	end

	if h < 2.5 then
		return nil
	end
	return h
end

local function materialAt(x: number, z: number, y: number, surfaceY: number): Enum.Material
	local depth = surfaceY - y
	if depth > 10 then
		return Enum.Material.Slate
	end
	if depth > 3.5 then
		return Enum.Material.Ground
	end
	if surfaceY > 22 and depth < 6 then
		if (math.floor(x / 8) + math.floor(z / 8)) % 5 == 0 then
			return Enum.Material.Rock
		end
	end
	return Enum.Material.Grass
end

function CasinoTerrain.start()
	local terrain = Workspace.Terrain

	-- Wipe entire prior site so plaza / interior never keep old grass voxels
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

				if top ~= nil and worldY <= top and worldY >= HILL_MIN.Y + 1 then
					materials[ix][iy][iz] = materialAt(worldX, worldZ, worldY, top)
					local edge = top - worldY
					if edge < RESOLUTION then
						occupancy[ix][iy][iz] = math.clamp(edge / RESOLUTION, 0.15, 1)
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

	-- Hard-clear plaza / pit / approach and full building volume (belt + braces)
	terrain:FillBlock(CFrame.new(0, 20, 50), Vector3.new(420, 80, 220), Enum.Material.Air)
	terrain:FillBlock(
		CFrame.new(0, 28, (68 + WALL_Z_N) * 0.5),
		Vector3.new(WALL_X * 2 + 4, 75, 68 - WALL_Z_N + 4),
		Enum.Material.Air
	)

	print("[Shuffle] CasinoTerrain back-ridge heightmap written")
end

return CasinoTerrain
