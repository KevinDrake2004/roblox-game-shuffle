--!strict
--[=[
	@class LobbyService
	Wires the Rojo-synced Lobby map (visible in Studio edit mode).

	Does not rebuild the hub at runtime — find doorways under Workspace.Lobby.Portals
	and bind prompts / lighting polish only. Game arenas live in adjacent rooms
	inside the same building (see docs/CASINO.md).
]=]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Janitor = require(Packages.Janitor)

local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local CasinoChairs = require(script.Parent.CasinoChairs)

type GameId = Types.GameId
type PortalResultPayload = Types.PortalResultPayload

local LobbyService = {}

local LOBBY_NAME = "Lobby"
local started = false
local janitor = Janitor.new()

local function applyLighting()
	local lobby = Config.LOBBY
	Lighting.ClockTime = lobby.ClockTime
	Lighting.Brightness = lobby.Brightness
	Lighting.Ambient = lobby.Ambient
	Lighting.OutdoorAmbient = lobby.OutdoorAmbient
	Lighting.FogColor = lobby.FogColor
	Lighting.FogStart = 120
	Lighting.FogEnd = lobby.FogEnd
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.ExposureCompensation = lobby.ExposureCompensation

	local atmosphere = Lighting:FindFirstChild("ShuffleAtmosphere")
	if atmosphere and atmosphere:IsA("Atmosphere") then
		atmosphere.Density = 0.1
		atmosphere.Haze = 0.42
		atmosphere.Color = Color3.fromRGB(100, 75, 150)
		atmosphere.Decay = Color3.fromRGB(60, 35, 95)
		atmosphere.Glare = 0.28
	end

	local colorCorrection = Lighting:FindFirstChild("ShuffleColorCorrection")
	if colorCorrection and colorCorrection:IsA("ColorCorrectionEffect") then
		colorCorrection.Brightness = 0.04
		colorCorrection.Contrast = 0.12
		colorCorrection.Saturation = 0.18
		colorCorrection.TintColor = Color3.fromRGB(255, 240, 255)
	end

	local bloom = Lighting:FindFirstChild("ShuffleBloom")
	if bloom and bloom:IsA("BloomEffect") then
		bloom.Intensity = 0.75
		bloom.Size = 24
		bloom.Threshold = 0.65
	end
end

local function ensurePortalLabels()
	local lobby = Workspace:FindFirstChild(LOBBY_NAME)
	if not lobby then
		warn("[LobbyService] Workspace.Lobby missing — is Rojo syncing src/map?")
		return
	end

	local portals = lobby:FindFirstChild("Portals")
	if not portals then
		return
	end

	for _, portalConfig in Config.PORTALS do
		local model = portals:FindFirstChild(`Portal_{portalConfig.id}`)
		if not (model and model:IsA("Model")) then
			continue
		end

		local frame = model:FindFirstChild("Frame")
		if not (frame and frame:IsA("BasePart")) then
			continue
		end

		if frame:FindFirstChild("Label") then
			continue
		end

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.fromOffset(220, 60)
		billboard.StudsOffset = Vector3.new(0, 5.5, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = frame

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Config.COLORS.Text
		label.TextStrokeTransparency = 0.4
		label.Text = portalConfig.displayName
		label.Parent = billboard

		local stroke = Instance.new("UIStroke")
		stroke.Color = portalConfig.accentColor
		stroke.Thickness = 2
		stroke.Parent = label
	end

	local sign = lobby:FindFirstChild("BrandSign")
	if sign and sign:IsA("BasePart") and not sign:FindFirstChild("SignGui") then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.Parent = sign

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(1, 1)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = Config.COLORS.Text
		title.Text = Config.GAME_NAME
		title.Parent = gui

		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.COLORS.NeonCyan
		stroke.Thickness = 2
		stroke.Parent = title
	end

	local arcadeSign = lobby:FindFirstChild("ArcadeSign")
	if arcadeSign and arcadeSign:IsA("BasePart") and not arcadeSign:FindFirstChild("SignGui") then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.Parent = arcadeSign

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(1, 1)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = Config.COLORS.Text
		title.Text = "ARCADE"
		title.Parent = gui

		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.COLORS.NeonPurple
		stroke.Thickness = 2
		stroke.Parent = title
	end
end

local function dressFeltLayout(layout: BasePart)
	if layout:FindFirstChild("FeltGui") then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "FeltGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 48
	gui.Parent = layout

	local root = Instance.new("Frame")
	root.Name = "Grid"
	root.BackgroundColor3 = Color3.fromRGB(12, 90, 48)
	root.BackgroundTransparency = 0.35
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.04, 0)
	pad.PaddingBottom = UDim.new(0.04, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = root

	local layoutGrid = Instance.new("UIGridLayout")
	layoutGrid.CellPadding = UDim2.fromOffset(3, 3)
	layoutGrid.CellSize = UDim2.fromScale(0.3, 0.1)
	layoutGrid.FillDirectionMaxCells = 3
	layoutGrid.SortOrder = Enum.SortOrder.LayoutOrder
	layoutGrid.Parent = root

	local red = Color3.fromRGB(190, 28, 38)
	local black = Color3.fromRGB(18, 18, 22)
	local greenZero = Color3.fromRGB(20, 140, 70)
	for n = 0, 23 do
		local cell = Instance.new("TextLabel")
		if n == 0 then
			cell.BackgroundColor3 = greenZero
			cell.Text = "0"
		else
			cell.BackgroundColor3 = if n % 2 == 0 then black else red
			cell.Text = tostring(n)
		end
		cell.BackgroundTransparency = 0.05
		cell.BorderSizePixel = 0
		cell.Font = Enum.Font.GothamBold
		cell.TextColor3 = Config.COLORS.Text
		cell.TextScaled = true
		cell.Parent = root

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(235, 200, 90)
		stroke.Thickness = 1
		stroke.Transparency = 0.35
		stroke.Parent = cell
	end
end

local function dressBetSpot(spot: BasePart, index: number)
	if spot:FindFirstChild("BetGui") then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BetGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 55
	gui.Parent = spot

	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(10, 70, 40)
	label.BackgroundTransparency = 0.25
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = tostring(index)
	label.TextColor3 = Config.COLORS.NeonGold
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.COLORS.NeonGold
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = label
end

local function dressPokerFelt(felt: BasePart)
	if felt:FindFirstChild("PokerGui") then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PokerGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = felt

	local oval = Instance.new("Frame")
	oval.AnchorPoint = Vector2.new(0.5, 0.5)
	oval.Position = UDim2.fromScale(0.5, 0.5)
	oval.Size = UDim2.fromScale(0.72, 0.55)
	oval.BackgroundColor3 = Color3.fromRGB(8, 70, 40)
	oval.BackgroundTransparency = 0.2
	oval.BorderSizePixel = 0
	oval.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = oval

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(235, 200, 90)
	stroke.Thickness = 3
	stroke.Transparency = 0.25
	stroke.Parent = oval

	local pot = Instance.new("TextLabel")
	pot.BackgroundTransparency = 1
	pot.Size = UDim2.fromScale(1, 1)
	pot.Font = Enum.Font.GothamBold
	pot.Text = "POT"
	pot.TextColor3 = Config.COLORS.NeonGold
	pot.TextScaled = true
	pot.TextStrokeTransparency = 0.5
	pot.Parent = oval
end

local function dressDealerPad(pad: BasePart)
	if pad:FindFirstChild("DealerGui") then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DealerGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = pad

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = "DEALER"
	label.TextColor3 = Config.COLORS.NeonGold
	label.TextScaled = true
	label.TextStrokeTransparency = 0.45
	label.Parent = gui
end

local function dressCasinoTables()
	local lobby = Workspace:FindFirstChild(LOBBY_NAME)
	if not lobby then
		return
	end
	local atmosphere = lobby:FindFirstChild("Atmosphere")
	if not atmosphere then
		return
	end
	local tables = atmosphere:FindFirstChild("Tables")
	if not tables then
		return
	end

	for _, tableFolder in tables:GetChildren() do
		if not tableFolder:IsA("Folder") then
			continue
		end
		local tableType = tableFolder:GetAttribute("TableType")
		local layout = tableFolder:FindFirstChild("FeltLayout")
		if layout and layout:IsA("BasePart") then
			dressFeltLayout(layout)
		end
		local felt = tableFolder:FindFirstChild("Felt")
		if felt and felt:IsA("BasePart") and tableType == "Poker" then
			dressPokerFelt(felt)
		end
		local dealerPad = tableFolder:FindFirstChild("DealerPad")
		if dealerPad and dealerPad:IsA("BasePart") then
			dressDealerPad(dealerPad)
		end
		for _, child in tableFolder:GetChildren() do
			if child:IsA("BasePart") and string.sub(child.Name, 1, 8) == "BetSpot_" then
				local index = tonumber(string.sub(child.Name, 9)) or 1
				dressBetSpot(child, index + 1)
			end
		end
	end
end

local function handlePortalRequest(player: Player, gameId: GameId)
	local playable = Config.PLAYABLE_GAMES[gameId] == true
	local displayName = gameId
	for _, portal in Config.PORTALS do
		if portal.id == gameId then
			displayName = portal.displayName
			break
		end
	end

	if playable then
		local payload: PortalResultPayload = {
			gameId = gameId,
			status = "enter",
			message = `Entering {displayName}…`,
		}
		Remotes.getEvent("PortalResult"):FireClient(player, payload)

		if gameId == "RocketRun" then
			local RocketRun = require(script.Parent.Parent.games.RocketRun)
			RocketRun.join(player)
		elseif gameId == "PlinkoPoints" then
			local PlinkoPoints = require(script.Parent.Parent.games.PlinkoPoints)
			PlinkoPoints.join(player)
		elseif gameId == "MineSweeper" then
			local MineSweeper = require(script.Parent.Parent.games.MineSweeper)
			MineSweeper.join(player)
		end
	else
		local payload: PortalResultPayload = {
			gameId = gameId,
			status = "coming_soon",
			message = `{displayName} opens in a later phase.`,
		}
		Remotes.getEvent("PortalResult"):FireClient(player, payload)
	end
end

local function bindPortalPrompts()
	local lobby = Workspace:FindFirstChild(LOBBY_NAME)
	if not lobby then
		return
	end
	local portals = lobby:FindFirstChild("Portals")
	if not portals then
		return
	end

	for _, model in portals:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local gameId = model:GetAttribute("GameId")
		if typeof(gameId) ~= "string" then
			continue
		end

		local gate = model:FindFirstChild("Gate")
		if not gate then
			continue
		end
		local prompt = gate:FindFirstChild("EnterPrompt")
		if not (prompt and prompt:IsA("ProximityPrompt")) then
			continue
		end

		janitor:Add(
			prompt.Triggered:Connect(function(player: Player)
				handlePortalRequest(player, gameId :: GameId)
			end),
			"Disconnect"
		)
	end
end

local function applyWalkSpeed(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	end
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = Config.WALK_SPEED
	end
end

local function bindPlayerMovement(player: Player)
	janitor:Add(
		player.CharacterAdded:Connect(function(character)
			task.defer(applyWalkSpeed, character)
		end),
		"Disconnect"
	)
	if player.Character then
		task.defer(applyWalkSpeed, player.Character)
	end
end

function LobbyService.start()
	if started then
		return
	end
	started = true

	-- Remove default Studio baseplate if present so the synced Lobby is the hub.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local defaultSpawn = Workspace:FindFirstChild("SpawnLocation")
	if defaultSpawn and defaultSpawn.Parent == Workspace then
		defaultSpawn:Destroy()
	end

	applyLighting()
	ensurePortalLabels()
	dressCasinoTables()

	local lobby = Workspace:FindFirstChild(LOBBY_NAME)
	if lobby then
		CasinoChairs.place(lobby)
	end

	bindPortalPrompts()

	janitor:Add(Players.PlayerAdded:Connect(bindPlayerMovement), "Disconnect")
	for _, player in Players:GetPlayers() do
		bindPlayerMovement(player)
	end

	janitor:Add(
		Remotes.getEvent("EnterPortal").OnServerEvent:Connect(function(player: Player, gameId: unknown)
			if typeof(gameId) ~= "string" then
				return
			end
			local valid = false
			for _, portal in Config.PORTALS do
				if portal.id == gameId then
					valid = true
					break
				end
			end
			if not valid then
				return
			end
			handlePortalRequest(player, gameId :: GameId)
		end),
		"Disconnect"
	)
end

return LobbyService
