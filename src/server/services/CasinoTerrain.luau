--!strict
--[[
	Casino Terrain: flat front plaza + slope up to a two-hill back range.
	Uses FillBlock / FillBall only (no WriteVoxels).
	LeafyGrass (not Grass) so animated grass blades never spawn.
	Spawn stays outside at (0, 3, 112). Plaza is not air-carved.
]]

local Workspace = game:GetService("Workspace")

local CasinoTerrain = {}

local WALL_X = 94.0
local WALL_Z_S = 68.0
local WALL_Z_N = -142.0

-- Green without Terrain grass blades. Grass material always grows decoration.
local SURFACE = Enum.Material.LeafyGrass
local DIRT = Enum.Material.Ground
local ROCK = Enum.Material.Rock

local function fillBall(terrain: Terrain, pos: Vector3, radius: number, material: Enum.Material)
	terrain:FillBall(pos, radius, material)
end

local function fillBlock(terrain: Terrain, cf: CFrame, size: Vector3, material: Enum.Material)
	terrain:FillBlock(cf, size, material)
end

function CasinoTerrain.start()
	local terrain = Workspace.Terrain

	local ok, err = pcall(function()
		-- Drop prior FillBall skirts so Play mode does not keep old blobs
		terrain:Clear()

		-- Deep dirt base under the whole resort (meets WorldGrass ~y=-0.55)
		fillBlock(terrain, CFrame.new(0, -14, -20), Vector3.new(360, 28, 400), DIRT)

		-- Flat front + building pad (spawn → mid site). No balls here.
		-- Covers z ≈ 200 down through the facade / pit; surface under WorldGrass.
		fillBlock(terrain, CFrame.new(0, -7, 30), Vector3.new(300, 14, 300), SURFACE)

		-- Soft side berms only beside / behind the envelope (not in front of the plaza)
		fillBlock(terrain, CFrame.new(-145, -2, -40), Vector3.new(50, 18, 200), SURFACE)
		fillBlock(terrain, CFrame.new(145, -2, -40), Vector3.new(50, 18, 200), SURFACE)

		-- Gradual rise toward the north wing (still blocky-smooth, not spheres)
		-- Flat top ~y=-0.5 at z=-80 → ~y=14 at z=-145
		local steps = {
			{ z = -85, y = -4.5, h = 10, w = 220, d = 28 },
			{ z = -105, y = -1.5, h = 14, w = 230, d = 28 },
			{ z = -125, y = 2.0, h = 18, w = 240, d = 28 },
			{ z = -145, y = 6.0, h = 22, w = 250, d = 32 },
		}
		for _, s in steps do
			fillBlock(terrain, CFrame.new(0, s.y, s.z), Vector3.new(s.w, s.h, s.d), SURFACE)
		end

		-- Back two-range hills (user-approved look) - centers buried north of rooms
		fillBall(terrain, Vector3.new(-42, 10, -188), 58, SURFACE)
		fillBall(terrain, Vector3.new(42, 10, -188), 58, SURFACE)
		-- Soft saddle / deeper spine so the pair reads as one range
		fillBall(terrain, Vector3.new(0, 4, -200), 52, SURFACE)
		fillBall(terrain, Vector3.new(-95, 2, -165), 40, SURFACE)
		fillBall(terrain, Vector3.new(95, 2, -165), 40, SURFACE)

		-- Rock knuckles on the crest only
		fillBall(terrain, Vector3.new(-40, 28, -175), 14, ROCK)
		fillBall(terrain, Vector3.new(40, 28, -175), 14, ROCK)

		-- Hollow building volume only (keep plaza / spawn Terrain)
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

	print("[Shuffle] CasinoTerrain flat-front + back-range hill written")
end

return CasinoTerrain
