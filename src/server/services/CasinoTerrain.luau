--!strict
--[[
	Casino Terrain: flat front under plaza parts + aggressive rise to a two-hill back range.

	Bakes once per place / server when ShuffleCasinoTerrainVersion matches.
	Bump VERSION below to reshape; Play once, then Save the place so Studio keeps
	the voxels for walkway / platform work (no Clear every Play).

	LeafyGrass (not Grass) so animated grass blades never spawn.
	Spawn stays outside at (0, 3, 112). ArenaOrigins unchanged.
]]

local Workspace = game:GetService("Workspace")

local CasinoTerrain = {}

-- Bump when reshaping hills so servers / Studio rebuild once.
local VERSION = 4

local WALL_X = 94.0
local WALL_Z_S = 68.0
local WALL_Z_N = -142.0

-- Green without Terrain grass blades. Grass material always grows decoration.
local SURFACE = Enum.Material.LeafyGrass
local DIRT = Enum.Material.Ground
local ROCK = Enum.Material.Rock

-- Plaza / WorldGrass sit near y=0; keep Terrain under them.
local FRONT_TOP_Y = -1.5

local function fillBall(terrain: Terrain, pos: Vector3, radius: number, material: Enum.Material)
	terrain:FillBall(pos, radius, material)
end

local function fillBlock(terrain: Terrain, cf: CFrame, size: Vector3, material: Enum.Material)
	terrain:FillBlock(cf, size, material)
end

local function fillPad(
	terrain: Terrain,
	center: Vector3,
	sizeXZ: Vector2,
	topY: number,
	thickness: number,
	material: Enum.Material
)
	local height = thickness
	local cy = topY - height * 0.5
	fillBlock(terrain, CFrame.new(center.X, cy, center.Z), Vector3.new(sizeXZ.X, height, sizeXZ.Y), material)
end

function CasinoTerrain.start()
	local terrain = Workspace.Terrain
	local baked = Workspace:GetAttribute("ShuffleCasinoTerrainVersion")
	if baked == VERSION then
		print(`[Shuffle] CasinoTerrain already baked (v{VERSION}) - skip`)
		return
	end

	local ok, err = pcall(function()
		terrain:Clear()

		-- Deep dirt base under the whole resort
		fillBlock(terrain, CFrame.new(0, -16, -30), Vector3.new(380, 30, 420), DIRT)

		-- Flat front pad: top under WorldGrass / PlazaFloor / carpet (not flush with y=0)
		fillPad(terrain, Vector3.new(0, 0, 40), Vector2.new(300, 300), FRONT_TOP_Y, 16, SURFACE)

		-- Low side berms (rise only as we go north - stay under facade sides up front)
		fillPad(terrain, Vector3.new(-150, 0, 20), Vector2.new(55, 160), -0.5, 14, SURFACE)
		fillPad(terrain, Vector3.new(150, 0, 20), Vector2.new(55, 160), -0.5, 14, SURFACE)
		fillPad(terrain, Vector3.new(-155, 0, -80), Vector2.new(60, 140), 6, 20, SURFACE)
		fillPad(terrain, Vector3.new(155, 0, -80), Vector2.new(60, 140), 6, 20, SURFACE)

		-- Aggressive rise toward the north wing / back range
		-- Flat ~-1.5 at z≈-55 → ~y=36 crest behind rooms
		local steps = {
			{ z = -60, top = 1.5, h = 12, w = 230, d = 24 },
			{ z = -80, top = 6.0, h = 16, w = 240, d = 26 },
			{ z = -100, top = 12.0, h = 20, w = 250, d = 28 },
			{ z = -120, top = 20.0, h = 26, w = 260, d = 30 },
			{ z = -140, top = 28.0, h = 32, w = 270, d = 32 },
			{ z = -160, top = 34.0, h = 36, w = 280, d = 34 },
		}
		for _, s in steps do
			fillPad(terrain, Vector3.new(0, 0, s.z), Vector2.new(s.w, s.d), s.top, s.h, SURFACE)
		end

		-- Back two-range hills (taller / farther north so the slope reads hard)
		fillBall(terrain, Vector3.new(-48, 22, -200), 68, SURFACE)
		fillBall(terrain, Vector3.new(48, 22, -200), 68, SURFACE)
		fillBall(terrain, Vector3.new(0, 14, -215), 58, SURFACE)
		fillBall(terrain, Vector3.new(-105, 10, -175), 46, SURFACE)
		fillBall(terrain, Vector3.new(105, 10, -175), 46, SURFACE)

		fillBall(terrain, Vector3.new(-45, 42, -185), 16, ROCK)
		fillBall(terrain, Vector3.new(45, 42, -185), 16, ROCK)

		-- Relieve plaza / apron / carpet only (do not flatten the back slope)
		fillBlock(terrain, CFrame.new(0, 3.5, 60), Vector3.new(200, 12, 140), Enum.Material.Air)

		-- Hollow building volume
		fillBlock(
			terrain,
			CFrame.new(0, 34, (WALL_Z_S + WALL_Z_N) * 0.5),
			Vector3.new(WALL_X * 2 - 8, 64, WALL_Z_S - WALL_Z_N - 8),
			Enum.Material.Air
		)
	end)

	if not ok then
		warn(`[Shuffle] CasinoTerrain failed: {err}`)
		return
	end

	Workspace:SetAttribute("ShuffleCasinoTerrainVersion", VERSION)
	print(`[Shuffle] CasinoTerrain baked v{VERSION} (flat front under plaza, steep back range)`)
end

return CasinoTerrain
