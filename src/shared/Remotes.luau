--!strict
--[=[
	@class Remotes
	RemoteEvent / RemoteFunction namespace for Shuffle Arcade.

	Call `Remotes.init()` once on the server before services start.
	Clients should resolve remotes via getters (WaitForChild-safe).

	## Rocket Run events

	| Name | Direction | Purpose |
	|------|-----------|---------|
	| `RocketRunSetLoadout` | C→S | Set wager + optional auto cash-out (next eligible round) |
	| `RocketRunRoundStarted` | S→C | Shared round snapshot (`RocketRunRoundStarted`) |
	| `RocketRunCashOut` | C→S | Request cash-out for `roundId` while flying |
	| `RocketRunCashOutMarker` | S→C | Another player cashed out (`RocketRunCashOutMarker`) |
	| `RocketRunResult` | S→C | Per-player settle (`RocketRunResultPayload`) |
	| `RocketRunCrashed` | S→C | Global crash notification `{ roundId, crashMultiplier }` |
	| `RocketRunLeave` | C→S | Leave arena |
	| `RocketRunLeft` | S→C | Confirm leave / tear down client HUD |

	## Plinko Points events

	| Name | Direction | Purpose |
	|------|-----------|---------|
	| `PlinkoPointsSetWager` | C→S | Set chips wagered per ball + ball count + risk id |
	| `PlinkoPointsJoined` | S→C | Arena enter snapshot (`PlinkoPointsJoined`) |
	| `PlinkoPointsDrop` | C→S | Request a ball drop at the current wager |
	| `PlinkoPointsDropStarted` | S→C | Wager accepted; client starts free physics (`PlinkoPointsDropStarted`) |
	| `PlinkoPointsLanded` | C→S | Report which bucket the local sim landed in |
	| `PlinkoPointsResult` | S→C | Per-drop settle (`PlinkoPointsResultPayload`) |
	| `PlinkoPointsDropRejected` | S→C | Drop blocked (`{ reason: string }`) |
	| `PlinkoPointsLeave` | C→S | Leave arena |
	| `PlinkoPointsLeft` | S→C | Confirm leave / tear down client HUD |
]=]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "Remotes"

export type EventName =
	"ChipsUpdated"
	| "ProfileLoaded"
	| "PortalResult"
	| "EnterPortal"
	| "RocketRunRoundStarted"
	| "RocketRunCrashed"
	| "RocketRunResult"
	| "RocketRunCashOutMarker"
	| "RocketRunCashOut"
	| "RocketRunLeave"
	| "RocketRunLeft"
	| "RocketRunSetLoadout"
	| "PlinkoPointsSetWager"
	| "PlinkoPointsJoined"
	| "PlinkoPointsDrop"
	| "PlinkoPointsDropStarted"
	| "PlinkoPointsLanded"
	| "PlinkoPointsResult"
	| "PlinkoPointsDropRejected"
	| "PlinkoPointsLeave"
	| "PlinkoPointsLeft"
	| "JobAction"
	| "JobPrompt"
	| "JobResult"

export type FunctionName = "GetProfile"

local EVENT_NAMES: { EventName } = {
	"ChipsUpdated",
	"ProfileLoaded",
	"PortalResult",
	"EnterPortal",
	"RocketRunRoundStarted",
	"RocketRunCrashed",
	"RocketRunResult",
	"RocketRunCashOutMarker",
	"RocketRunCashOut",
	"RocketRunLeave",
	"RocketRunLeft",
	"RocketRunSetLoadout",
	"PlinkoPointsSetWager",
	"PlinkoPointsJoined",
	"PlinkoPointsDrop",
	"PlinkoPointsDropStarted",
	"PlinkoPointsLanded",
	"PlinkoPointsResult",
	"PlinkoPointsDropRejected",
	"PlinkoPointsLeave",
	"PlinkoPointsLeft",
	"JobAction",
	"JobPrompt",
	"JobResult",
}

local FUNCTION_NAMES: { FunctionName } = {
	"GetProfile",
}

local function getFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end

	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function getOrCreateRemoteEvent(name: EventName): RemoteEvent
	local folder = getFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	if RunService:IsServer() then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	return folder:WaitForChild(name) :: RemoteEvent
end

local function getOrCreateRemoteFunction(name: FunctionName): RemoteFunction
	local folder = getFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	if RunService:IsServer() then
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	return folder:WaitForChild(name) :: RemoteFunction
end

--[=[
	Create the Remotes folder and all named events/functions. Server only.
]=]
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init must be called on the server")
	getFolder()
	for _, name in EVENT_NAMES do
		getOrCreateRemoteEvent(name)
	end
	for _, name in FUNCTION_NAMES do
		getOrCreateRemoteFunction(name)
	end
end

--[=[
	Resolve a RemoteEvent by name (creates on server, waits on client).
]=]
function Remotes.getEvent(name: EventName): RemoteEvent
	return getOrCreateRemoteEvent(name)
end

--[=[
	Resolve a RemoteFunction by name (creates on server, waits on client).
]=]
function Remotes.getFunction(name: FunctionName): RemoteFunction
	return getOrCreateRemoteFunction(name)
end

return Remotes
