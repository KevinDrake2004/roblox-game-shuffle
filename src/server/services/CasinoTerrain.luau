--!strict
--[[
	Casino Terrain via FillBlock / FillBall (reliable).
	Avoids WriteVoxels grid-size mismatches that wiped the site to empty air.
	Spawn stays outside at (0, 3, 112). Plaza is not air-carved.
]]

local Workspace = game:GetService("Workspace")

local CasinoTerrain = {}

local WALL_X = 94.0
local WALL_Z_S = 68.0
local WALL_Z_N = -142.0

local function fillBall(terrain: Terrain, pos: Vector3, radius: number, material: Enum.Material)
	terrain:FillBall(pos, radius, material)
end

local function fillBlock(terrain: Terrain, cf: CFrame, size: Vector3, material: Enum.Material)
	terrain:FillBlock(cf, size, material)
end

function CasinoTerrain.start()
	local terrain = Workspace.Terrain
	terrain.Decoration = false

	local ok, err = pcall(function()
		-- Broad dirt/grass foundation under the whole resort (meets WorldGrass ~y=-0.55)
		fillBlock(terrain, CFrame.new(0, -10, -20), Vector3.new(320, 20, 340), Enum.Material.Grass)

		-- Outer skirt mounds so the site reads as a hill from far away
		local skirt = {
			-- x, y, z, radius
			{ 0, -18, 175, 55 },
			{ -70, -16, 150, 42 },
			{ 70, -16, 150, 42 },
			{ -130, -14, 40, 48 },
			{ 130, -14, 40, 48 },
			{ -130, -14, -40, 48 },
			{ 130, -14, -40, 48 },
			{ -100, -12, 100, 36 },
			{ 100, -12, 100, 36 },
			{ 0, -20, 210, 50 },
		}
		for _, m in skirt do
			fillBall(terrain, Vector3.new(m[1], m[2], m[3]), m[4], Enum.Material.Grass)
		end

		-- Tall back ridge / flanks - nest the game-room wing
		local ridge = {
			{ 0, 18, -175, 62 },
			{ -45, 22, -168, 52 },
			{ 45, 22, -168, 52 },
			{ -85, 16, -155, 46 },
			{ 85, 16, -155, 46 },
			{ 0, 28, -195, 48 },
			{ -120, 8, -110, 44 },
			{ 120, 8, -110, 44 },
			{ -115, 12, -145, 40 },
			{ 115, 12, -145, 40 },
			{ -70, 14, -130, 38 },
			{ 70, 14, -130, 38 },
		}
		for _, m in ridge do
			fillBall(terrain, Vector3.new(m[1], m[2], m[3]), m[4], Enum.Material.Grass)
		end

		-- Rock knuckles on the crest
		fillBall(terrain, Vector3.new(0, 30, -160), 22, Enum.Material.Rock)
		fillBall(terrain, Vector3.new(-55, 24, -170), 16, Enum.Material.Rock)
		fillBall(terrain, Vector3.new(55, 24, -170), 16, Enum.Material.Rock)

		-- Smooth green cap on the plaza / apron (under WorldGrass, not above floors)
		fillBlock(terrain, CFrame.new(0, -1.2, 10), Vector3.new(240, 2.2, 240), Enum.Material.Grass)

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

	print("[Shuffle] CasinoTerrain FillBall/FillBlock hill written")
end

return CasinoTerrain
