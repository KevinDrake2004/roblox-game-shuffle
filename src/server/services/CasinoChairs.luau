--!strict
--[=[
	@class CasinoChairs
	Places casino chairs at runtime with CFrame.lookAt so seats always face
	their table correctly (JSON world-positioned chairs break on angled tables).
]=]
local CasinoChairs = {}

local CHAIR_PITCH = 2.75
local SEAT_Y = 1.68
local TABLE_CLEAR = 1.4
local SEAT_HALF = 0.9

local WOOD = Color3.fromRGB(82, 41, 20)
local WOOD_DARK = Color3.fromRGB(41, 20, 10)
local GOLD = Color3.fromRGB(235, 191, 82)
local BURGUNDY = Color3.fromRGB(115, 15, 31)
local BURGUNDY_DARK = Color3.fromRGB(71, 10, 20)

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = if canCollide == nil then true else canCollide
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Open side of the chair is local +Z; backrest is local -Z.
-- CFrame.lookAt points local -Z at the target, so flip 180° to face +Z at target.
local function seatCFrameFacing(position: Vector3, facePoint: Vector3): CFrame
	local flat = Vector3.new(facePoint.X, position.Y, facePoint.Z)
	if (flat - position).Magnitude < 0.05 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, flat) * CFrame.Angles(0, math.pi, 0)
end

-- Face along a world direction (unit-ish); open side (+Z) points along direction.
local function seatCFrameDirection(position: Vector3, direction: Vector3): CFrame
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.05 then
		return CFrame.new(position)
	end
	return seatCFrameFacing(position, position + flat.Unit)
end

local function buildChair(parent: Instance, name: string, seatCF: CFrame)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local function localPart(
		partName: string,
		size: Vector3,
		localCf: CFrame,
		color: Color3,
		material: Enum.Material,
		canCollide: boolean?
	)
		return makePart(model, partName, size, seatCF * localCf, color, material, canCollide)
	end

	for i, offset in
		{
			Vector3.new(-0.5, -1.0, -0.5),
			Vector3.new(0.5, -1.0, -0.5),
			Vector3.new(-0.5, -1.0, 0.5),
			Vector3.new(0.5, -1.0, 0.5),
		}
	do
		localPart(`Leg_{i}`, Vector3.new(0.18, 1.35, 0.18), CFrame.new(offset), WOOD_DARK, Enum.Material.Wood)
		localPart(
			`LegFerrule_{i}`,
			Vector3.new(0.22, 0.08, 0.22),
			CFrame.new(offset.X, -1.62, offset.Z),
			GOLD,
			Enum.Material.Metal
		)
	end

	localPart("SeatFrame", Vector3.new(1.85, 0.2, 1.85), CFrame.new(0, -0.28, 0), WOOD, Enum.Material.Wood)
	localPart("SeatCushion", Vector3.new(1.7, 0.35, 1.7), CFrame.new(), BURGUNDY, Enum.Material.Fabric)
	localPart("SeatPiping", Vector3.new(1.75, 0.05, 1.75), CFrame.new(0, 0.2, 0), GOLD, Enum.Material.Neon, false)

	for i, x in { -0.62, 0.62 } do
		localPart(`BackPost_{i}`, Vector3.new(0.18, 2.0, 0.18), CFrame.new(x, 0.72, -0.78), WOOD, Enum.Material.Wood)
	end
	localPart("BackCross", Vector3.new(1.5, 0.18, 0.18), CFrame.new(0, 1.57, -0.78), WOOD, Enum.Material.Wood)
	localPart("BackCushion", Vector3.new(1.5, 1.35, 0.3), CFrame.new(0, 0.87, -0.78), BURGUNDY, Enum.Material.Fabric)
	localPart("BackTop", Vector3.new(1.65, 0.22, 0.3), CFrame.new(0, 1.67, -0.78), WOOD, Enum.Material.Wood)

	for i, x in { -0.88, 0.88 } do
		localPart(`ArmSupport_{i}`, Vector3.new(0.16, 0.85, 0.16), CFrame.new(x, 0.42, -0.1), WOOD, Enum.Material.Wood)
		localPart(`Armrest_{i}`, Vector3.new(0.3, 0.16, 1.35), CFrame.new(x, 0.87, -0.1), WOOD, Enum.Material.Wood)
		localPart(
			`ArmPad_{i}`,
			Vector3.new(0.28, 0.1, 1.2),
			CFrame.new(x, 1.0, -0.1),
			BURGUNDY_DARK,
			Enum.Material.Fabric
		)
	end

	return model
end

local function tableCenter(tableFolder: Instance): (Vector3, CFrame, Vector3)
	local felt = tableFolder:FindFirstChild("Felt")
	if felt and felt:IsA("BasePart") then
		return felt.Position, felt.CFrame, felt.Size
	end
	local rim = tableFolder:FindFirstChild("Rim")
	if rim and rim:IsA("BasePart") then
		return rim.Position, rim.CFrame, rim.Size
	end
	local base = tableFolder:FindFirstChild("Base")
	if base and base:IsA("BasePart") then
		return base.Position, base.CFrame, base.Size
	end
	return Vector3.zero, CFrame.new(), Vector3.new(8, 1, 8)
end

local function placeRoulette(chairsFolder: Folder, tableFolder: Instance)
	local center, tableCF, size = tableCenter(tableFolder)
	local radius = math.max(size.X, size.Z) / 2 + TABLE_CLEAR + SEAT_HALF
	for i = 0, 5 do
		local ang = i * (math.pi * 2 / 6)
		local worldPos = (tableCF * CFrame.new(math.sin(ang) * radius, 0, math.cos(ang) * radius)).Position
		local seatPos = Vector3.new(worldPos.X, SEAT_Y, worldPos.Z)
		buildChair(chairsFolder, `Roulette_{tableFolder.Name}_{i}`, seatCFrameFacing(seatPos, center))
	end
end

local function placeBlackjack(chairsFolder: Folder, tableFolder: Instance)
	local _, tableCF, size = tableCenter(tableFolder)
	local seatLocalZ = size.Z / 2 + TABLE_CLEAR + SEAT_HALF
	-- Face straight into the table along -local Z (not toward center - keeps the row aligned).
	local inward = tableCF.LookVector
	local span = 4 * CHAIR_PITCH
	local start = -span / 2
	for i = 0, 4 do
		local ox = start + i * CHAIR_PITCH
		local worldPos = (tableCF * CFrame.new(ox, 0, seatLocalZ)).Position
		local seatPos = Vector3.new(worldPos.X, SEAT_Y, worldPos.Z)
		buildChair(chairsFolder, `Blackjack_{tableFolder.Name}_{i}`, seatCFrameDirection(seatPos, inward))
	end
end

local function placePoker(chairsFolder: Folder, tableFolder: Instance)
	local _, tableCF, size = tableCenter(tableFolder)
	local seatLocalZ = size.Z / 2 + TABLE_CLEAR + SEAT_HALF
	local seatLocalX = size.X / 2 + TABLE_CLEAR + SEAT_HALF
	local inward = tableCF.LookVector
	local right = tableCF.RightVector

	-- Long sides: 3 + 3, facing straight in
	for i = 0, 2 do
		local ox = (i - 1) * CHAIR_PITCH
		local worldPos = (tableCF * CFrame.new(ox, 0, seatLocalZ)).Position
		local seatPos = Vector3.new(worldPos.X, SEAT_Y, worldPos.Z)
		buildChair(chairsFolder, `Poker_{tableFolder.Name}_N{i}`, seatCFrameDirection(seatPos, inward))
	end
	for i = 0, 2 do
		local ox = (i - 1) * CHAIR_PITCH
		local worldPos = (tableCF * CFrame.new(ox, 0, -seatLocalZ)).Position
		local seatPos = Vector3.new(worldPos.X, SEAT_Y, worldPos.Z)
		buildChair(chairsFolder, `Poker_{tableFolder.Name}_S{i}`, seatCFrameDirection(seatPos, -inward))
	end
	-- Short ends
	local worldE = (tableCF * CFrame.new(seatLocalX, 0, 0)).Position
	buildChair(
		chairsFolder,
		`Poker_{tableFolder.Name}_E0`,
		seatCFrameDirection(Vector3.new(worldE.X, SEAT_Y, worldE.Z), -right)
	)
	local worldW = (tableCF * CFrame.new(-seatLocalX, 0, 0)).Position
	buildChair(
		chairsFolder,
		`Poker_{tableFolder.Name}_E1`,
		seatCFrameDirection(Vector3.new(worldW.X, SEAT_Y, worldW.Z), right)
	)
end

local function placeBarStools(chairsFolder: Folder, bar: Instance)
	local top = bar:FindFirstChild("BarTop")
	if not (top and top:IsA("BasePart")) then
		return
	end
	-- Stools along +X face of bar (world), facing -X into the bar.
	local face = Vector3.new(-1, 0, 0)
	for i = 0, 4 do
		local seatPos = Vector3.new(-67.5, SEAT_Y, -4.0 + i * CHAIR_PITCH)
		buildChair(chairsFolder, `BarStool_{i}`, seatCFrameDirection(seatPos, face))
	end
end

function CasinoChairs.place(lobby: Instance)
	local atmosphere = lobby:FindFirstChild("Atmosphere")
	if not atmosphere then
		return
	end

	local chairsFolder = atmosphere:FindFirstChild("Chairs")
	if chairsFolder then
		chairsFolder:ClearAllChildren()
	else
		chairsFolder = Instance.new("Folder")
		chairsFolder.Name = "Chairs"
		chairsFolder.Parent = atmosphere
	end
	assert(chairsFolder:IsA("Folder"), "Chairs folder missing")

	local tables = atmosphere:FindFirstChild("Tables")
	if tables then
		for _, tableFolder in tables:GetChildren() do
			if not tableFolder:IsA("Folder") then
				continue
			end
			local tableType = tableFolder:GetAttribute("TableType")
			if tableType == "Roulette" then
				placeRoulette(chairsFolder, tableFolder)
			elseif tableType == "Blackjack" then
				placeBlackjack(chairsFolder, tableFolder)
			elseif tableType == "Poker" then
				placePoker(chairsFolder, tableFolder)
			end
		end
	end

	local bar = atmosphere:FindFirstChild("LoungeBar")
	if bar then
		placeBarStools(chairsFolder, bar)
	end
end

return CasinoChairs
