--!strict
--[=[
	@class ArenaZones
	Zone-based game entry/exit. Each game room's `Floor` part defines a volume;
	when a player's character walks into it we join that game (HUD + focused
	camera appear on the client) and when they walk out we leave it (HUD tears
	down). No teleports - the arenas are physical rooms inside the casino.
]=]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RocketRun = require(script.Parent.Parent.games.RocketRun)
local PlinkoPoints = require(script.Parent.Parent.games.PlinkoPoints)
local MineSweeper = require(script.Parent.Parent.games.MineSweeper)

type Zone = {
	folderName: string,
	join: (Player) -> (),
	leave: (Player) -> (),
}

local ArenaZones = {}

local started = false

-- Poll cadence and containment tuning (studs). Exit uses a wider margin than
-- entry so lingering on a room threshold cannot flicker join/leave.
local POLL_INTERVAL = 0.2
local ENTER_MARGIN = 2
local EXIT_MARGIN = 4
local Y_BELOW = 4
local Y_ABOVE = 40

local ZONES: { Zone } = {
	{ folderName = "RocketRunArena", join = RocketRun.join, leave = RocketRun.leave },
	{ folderName = "PlinkoArena", join = PlinkoPoints.join, leave = PlinkoPoints.leave },
	{ folderName = "MineSweeperArena", join = MineSweeper.join, leave = MineSweeper.leave },
}

-- folderName the player is currently considered inside (nil = in the lobby).
local currentZone: { [Player]: string } = {}
-- Grace before leave fires after the player steps outside exit bounds (avoids doorway flicker).
local leaveGraceUntil: { [Player]: number } = {}
local LEAVE_GRACE_SECONDS = 0.65

local function zoneByName(name: string): Zone?
	for _, zone in ZONES do
		if zone.folderName == name then
			return zone
		end
	end
	return nil
end

local function floorPart(folderName: string): BasePart?
	local arena = Workspace:FindFirstChild(folderName)
	local floor = arena and arena:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		return floor
	end
	return nil
end

local function inFloor(pos: Vector3, floor: BasePart, margin: number): boolean
	local center = floor.Position
	local size = floor.Size
	if math.abs(pos.X - center.X) > size.X / 2 + margin then
		return false
	end
	if math.abs(pos.Z - center.Z) > size.Z / 2 + margin then
		return false
	end
	local top = center.Y + size.Y / 2
	return pos.Y >= top - Y_BELOW and pos.Y <= top + Y_ABOVE
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function updatePlayer(player: Player)
	local pos = rootPosition(player)
	if not pos then
		return
	end

	local current = currentZone[player]
	if current then
		local floor = floorPart(current)
		if floor and inFloor(pos, floor, EXIT_MARGIN) then
			leaveGraceUntil[player] = nil
			return -- still inside their room; nothing to do
		end
		local graceUntil = leaveGraceUntil[player]
		if not graceUntil then
			leaveGraceUntil[player] = os.clock() + LEAVE_GRACE_SECONDS
			return
		end
		if os.clock() < graceUntil then
			return -- brief exit; keep session alive until grace expires
		end
		currentZone[player] = nil
		leaveGraceUntil[player] = nil
		local zone = zoneByName(current)
		if zone then
			zone.leave(player)
		end
	else
		leaveGraceUntil[player] = nil
	end

	for _, zone in ZONES do
		local floor = floorPart(zone.folderName)
		if floor and inFloor(pos, floor, ENTER_MARGIN) then
			currentZone[player] = zone.folderName
			leaveGraceUntil[player] = nil
			zone.join(player)
			break
		end
	end
end

--[=[
	Begin polling player positions and drive join/leave on room entry/exit.
	Idempotent; call once after the game modules have started.
]=]
function ArenaZones.start()
	if started then
		return
	end
	started = true

	Players.PlayerRemoving:Connect(function(player)
		currentZone[player] = nil
		leaveGraceUntil[player] = nil
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < POLL_INTERVAL then
			return
		end
		accumulator = 0
		for _, player in Players:GetPlayers() do
			updatePlayer(player)
		end
	end)
end

return ArenaZones
