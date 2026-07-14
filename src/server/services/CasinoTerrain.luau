--!strict
--[[
	Builds real Roblox Terrain around the casino shell (heightmap via WriteVoxels).
	Does not move ArenaOrigins or touch wager/RNG. Clears air inside the building
	volume so floors stay playable.
]]

local Workspace = game:GetService("Workspace")

local CasinoTerrain = {}

local RESOLUTION = 4

-- Building envelope (studs). Keep air / flat inside so interiors stay clear.
local WALL_X = 94.0
local WALL_Z_S = 68.0
local WALL_Z_N = -142.0

-- Terrain generation bounds
local MIN_X = -220.0
local MAX_X = 220.0
local MIN_Z = -260.0
local MAX_Z = 180.0
local MIN_Y = -24.0
local MAX_Y = 72.0

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function noise2(x: number, z: number): number
	-- Cheap deterministic ripple (no RandomStream needed for a fixed site).
	return math.sin(x * 0.045) * math.cos(z * 0.038) * 0.5
		+ math.sin(x * 0.11 + z * 0.07) * 0.25
		+ math.sin(z * 0.09 - x * 0.05) * 0.2
end

local function insideBuilding(x: number, z: number): boolean
	return math.abs(x) <= WALL_X and z <= WALL_Z_S and z >= WALL_Z_N
end

-- Surface height (studs) above y=0. Nil means leave as base apron / air carve.
local function surfaceHeight(x: number, z: number): number
	local n = noise2(x, z)
	local h = 1.2 + n * 1.5 -- gentle apron undulation

	-- North ridge behind the room wing
	if z < WALL_Z_N then
		local d = WALL_Z_N - z
		local ridge = 46 * math.exp(-((d - 18) / 28) ^ 2)
		local fall = smoothstep(1 - d / 95)
		h = math.max(h, ridge * fall + n * 4)
	end

	-- East / west flanks along the tall room wing
	local flankBand = z < -50 and z > WALL_Z_N - 10
	if flankBand then
		local dx = math.abs(x) - WALL_X
		if dx > 0 then
			local flank = 36 * math.exp(-((dx - 22) / 26) ^ 2)
			local zFade = 1 - math.abs(z + 97) / 55
			h = math.max(h, flank * math.clamp(zFade, 0, 1) + n * 3)
		end
	end

	-- Corner blends (NE / NW)
	if z < -120 and math.abs(x) > 70 then
		local corner = 28 * math.exp(-((math.abs(x) - 110) / 35) ^ 2) * math.exp(-((z + 155) / 30) ^ 2)
		h = math.max(h, corner + n * 2)
	end

	-- Soft south / side mounds (keep plaza carpet clear: |x|<20, z 70..120)
	local onPlazaCarpet = math.abs(x) < 18 and z > 70 and z < 125
	if not onPlazaCarpet then
		local mound = 0
		mound = math.max(mound, 8 * math.exp(-((x + 105) / 28) ^ 2) * math.exp(-((z - 118) / 22) ^ 2))
		mound = math.max(mound, 7 * math.exp(-((x - 110) / 26) ^ 2) * math.exp(-((z - 120) / 20) ^ 2))
		mound = math.max(mound, 10 * math.exp(-((x + 160) / 32) ^ 2) * math.exp(-((z - 25) / 40) ^ 2))
		mound = math.max(mound, 10 * math.exp(-((x - 160) / 32) ^ 2) * math.exp(-((z - 20) / 40) ^ 2))
		mound = math.max(mound, 5 * math.exp(-((x + 40) / 36) ^ 2) * math.exp(-((z - 168) / 18) ^ 2))
		h = math.max(h, mound + n * 1.2)
	end

	-- Keep spawn / approach walkable
	if math.abs(x) < 14 and z > 85 and z < 130 then
		h = math.min(h, 1.5)
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
	-- Rocky knuckles on steep north / flank faces
	if surfaceY > 22 and (z < WALL_Z_N + 5 or math.abs(x) > WALL_X + 5) and depth < 6 then
		if (math.floor(x / 8) + math.floor(z / 8)) % 5 == 0 then
			return Enum.Material.Rock
		end
	end
	return Enum.Material.Grass
end

function CasinoTerrain.start()
	local terrain = Workspace.Terrain

	-- Wipe previous site terrain so reloads stay idempotent
	local clearRegion = Region3.new(Vector3.new(MIN_X, MIN_Y, MIN_Z), Vector3.new(MAX_X, MAX_Y, MAX_Z))
		:ExpandToGrid(RESOLUTION)
	terrain:FillRegion(clearRegion, RESOLUTION, Enum.Material.Air)

	local region = Region3.new(Vector3.new(MIN_X, MIN_Y, MIN_Z), Vector3.new(MAX_X, MAX_Y, MAX_Z))
		:ExpandToGrid(RESOLUTION)

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

				if insideBuilding(worldX, worldZ) then
					-- Hollow the shell: keep a thin soil pad under the floors only
					if worldY < -1 and worldY > MIN_Y + 2 then
						materials[ix][iy][iz] = Enum.Material.Ground
						occupancy[ix][iy][iz] = 1
					else
						materials[ix][iy][iz] = Enum.Material.Air
						occupancy[ix][iy][iz] = 0
					end
				else
					local top = surfaceHeight(worldX, worldZ)
					if worldY <= top and worldY >= MIN_Y + 1 then
						materials[ix][iy][iz] = materialAt(worldX, worldZ, worldY, top)
						-- Soft occupancy near the surface for smoother slopes
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
	end

	terrain:WriteVoxels(region, RESOLUTION, materials, occupancy)

	-- Ensure building interior volume is air (floors / rooms / portals)
	terrain:FillBlock(
		CFrame.new(0, 28, (WALL_Z_S + WALL_Z_N) * 0.5),
		Vector3.new(WALL_X * 2 - 2, 70, WALL_Z_S - WALL_Z_N - 2),
		Enum.Material.Air
	)

	print("[Shuffle] CasinoTerrain heightmap written")
end

return CasinoTerrain
