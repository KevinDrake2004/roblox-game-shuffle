--!strict
--[=[
	@class LobbyService
	Wires the Rojo-synced Lobby map (visible in Studio edit mode).

	Does not rebuild the hub at runtime — find doorways under Workspace.Lobby.Portals
	and bind prompts / lighting polish only. Game arenas live in adjacent rooms
	inside the same building (see docs/CASINO.md).
]=]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Janitor = require(Packages.Janitor)

local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

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
		atmosphere.Density = 0.08
		atmosphere.Haze = 0.35
		atmosphere.Color = Color3.fromRGB(90, 70, 140)
		atmosphere.Decay = Color3.fromRGB(55, 35, 90)
		atmosphere.Glare = 0.18
	end

	local colorCorrection = Lighting:FindFirstChild("ShuffleColorCorrection")
	if colorCorrection and colorCorrection:IsA("ColorCorrectionEffect") then
		colorCorrection.Brightness = 0.02
		colorCorrection.Contrast = 0.08
		colorCorrection.Saturation = 0.12
		colorCorrection.TintColor = Color3.fromRGB(245, 235, 255)
	end

	local bloom = Lighting:FindFirstChild("ShuffleBloom")
	if bloom and bloom:IsA("BloomEffect") then
		bloom.Intensity = 0.55
		bloom.Size = 18
		bloom.Threshold = 0.75
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
	bindPortalPrompts()

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
