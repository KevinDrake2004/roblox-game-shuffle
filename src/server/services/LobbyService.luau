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
local CasinoChairs = require(script.Parent.CasinoChairs)

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
	if sign and sign:IsA("BasePart") then
		-- Recreate each boot so marquee layout updates apply (single-line TextScaled
		-- stays tiny on a wide board because width caps glyph height).
		local oldGui = sign:FindFirstChild("SignGui")
		if oldGui then
			oldGui:Destroy()
		end

		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 100
		gui.Parent = sign

		local root = Instance.new("Frame")
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromScale(1, 1)
		root.Parent = gui

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.04, 0)
		padding.PaddingRight = UDim.new(0.04, 0)
		padding.PaddingTop = UDim.new(0.04, 0)
		padding.PaddingBottom = UDim.new(0.04, 0)
		padding.Parent = root

		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, 6)
		list.Parent = root

		local words = string.split(string.upper(Config.GAME_NAME), " ")
		if #words == 0 then
			words = { string.upper(Config.GAME_NAME) }
		end
		local lineHeight = 0.92 / math.max(#words, 1)
		for _, word in words do
			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Size = UDim2.new(1, 0, lineHeight, 0)
			title.Font = Enum.Font.GothamBlack
			title.TextScaled = true
			title.TextColor3 = Config.COLORS.Text
			title.Text = word
			title.Parent = root

			local stroke = Instance.new("UIStroke")
			stroke.Color = Config.COLORS.NeonCyan
			stroke.Thickness = 4
			stroke.Parent = title
		end
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

	local function dressNamedSign(part: BasePart, text: string, accent: Color3, face: Enum.NormalId)
		if part:FindFirstChild("SignGui") then
			return
		end
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignGui"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 55
		gui.Parent = part

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(1, 1)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = Config.COLORS.Text
		title.Text = text
		title.Parent = gui

		local stroke = Instance.new("UIStroke")
		stroke.Color = accent
		stroke.Thickness = 2
		stroke.Parent = title
	end

	local atmosphere = lobby:FindFirstChild("Atmosphere")
	local plaza = atmosphere and atmosphere:FindFirstChild("Plaza")
	local vestibule = atmosphere and atmosphere:FindFirstChild("Vestibule")
	local valetSign = plaza and plaza:FindFirstChild("ValetSign")
	local vipSign = vestibule and vestibule:FindFirstChild("VipSign")
	local receptionSign = vestibule and vestibule:FindFirstChild("ReceptionSign")
	if valetSign and valetSign:IsA("BasePart") then
		dressNamedSign(valetSign, "VALET", Config.COLORS.NeonCyan, Enum.NormalId.Front)
	end
	if vipSign and vipSign:IsA("BasePart") then
		dressNamedSign(vipSign, "VIP", Config.COLORS.NeonMagenta, Enum.NormalId.Front)
	end
	if receptionSign and receptionSign:IsA("BasePart") then
		dressNamedSign(receptionSign, "RECEPTION", Config.COLORS.NeonCyan, Enum.NormalId.Front)
	end
end

local ROULETTE_RED: { [number]: boolean } = {}
for _, n in { 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36 } do
	ROULETTE_RED[n] = true
end

local FELT_GREEN = Color3.fromRGB(12, 90, 48)
local NUMBER_RED = Color3.fromRGB(190, 28, 38)
local NUMBER_BLACK = Color3.fromRGB(18, 18, 22)
local ZERO_GREEN = Color3.fromRGB(20, 140, 70)
local GOLD_LINE = Color3.fromRGB(235, 200, 90)

local function styleCell(cell: GuiObject, thickness: number)
	cell.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD_LINE
	stroke.Thickness = thickness
	stroke.Transparency = 0.3
	stroke.Parent = cell
end

local function numberCell(n: number, order: number): TextLabel
	local cell = Instance.new("TextLabel")
	cell.LayoutOrder = order
	cell.BackgroundColor3 = if ROULETTE_RED[n] then NUMBER_RED else NUMBER_BLACK
	cell.BackgroundTransparency = 0.05
	cell.Font = Enum.Font.GothamBold
	cell.Text = tostring(n)
	cell.TextColor3 = Config.COLORS.Text
	cell.TextScaled = true
	styleCell(cell, 1)
	return cell
end

local function outsideCell(text: string, order: number, color: Color3?): TextLabel
	local cell = Instance.new("TextLabel")
	cell.LayoutOrder = order
	cell.BackgroundColor3 = color or FELT_GREEN
	cell.BackgroundTransparency = if color then 0.05 else 0.3
	cell.Font = Enum.Font.GothamBold
	cell.Text = text
	cell.TextColor3 = Config.COLORS.Text
	cell.TextScaled = true
	styleCell(cell, 1)
	return cell
end

-- Horizontal band (dozens / even-money) of equally sized outside-bet cells.
-- Clips its children so a padded grid can never bleed into the neighbouring band.
local function outsideBand(parent: Instance, region: UDim2, position: UDim2, cells: number): Frame
	local band = Instance.new("Frame")
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.ClipsDescendants = true
	band.Size = region
	band.Position = position
	band.Parent = parent

	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(3, 0)
	-- Subtract the padding from each cell so all cells fit inside the band.
	layout.CellSize = UDim2.new(1 / cells, -3 + 3 / cells, 1, 0)
	layout.FillDirectionMaxCells = cells
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = band
	return band
end

-- Real European single-zero betting layout: green 0 at the wheel end, a 3x12
-- number grid across the felt, and outside bets (dozens + colours) below.
-- Bands are laid out with explicit gaps and clip their contents, so the number
-- grid and the outside bets can never overlap regardless of text sizing.
local function dressFeltLayout(layout: BasePart)
	if layout:FindFirstChild("FeltGui") then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "FeltGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 80
	gui.Parent = layout

	local root = Instance.new("Frame")
	root.Name = "Layout"
	root.BackgroundColor3 = FELT_GREEN
	root.BackgroundTransparency = 0.25
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.04, 0)
	pad.PaddingBottom = UDim.new(0.04, 0)
	pad.PaddingLeft = UDim.new(0.03, 0)
	pad.PaddingRight = UDim.new(0.03, 0)
	pad.Parent = root

	-- Column x-anchor shared by the grid and the outside bands so they align.
	local gridX = 0.08
	local gridW = 1 - gridX

	-- Band 1: zero + 3x12 number grid (top ~56%).
	local numbers = Instance.new("Frame")
	numbers.Name = "Numbers"
	numbers.BackgroundTransparency = 1
	numbers.BorderSizePixel = 0
	numbers.ClipsDescendants = true
	numbers.Size = UDim2.fromScale(1, 0.56)
	numbers.Position = UDim2.fromScale(0, 0)
	numbers.Parent = root

	local zero = Instance.new("TextLabel")
	zero.BackgroundColor3 = ZERO_GREEN
	zero.BackgroundTransparency = 0.05
	zero.Font = Enum.Font.GothamBold
	zero.Text = "0"
	zero.TextColor3 = Config.COLORS.Text
	zero.TextScaled = true
	zero.Size = UDim2.new(gridX, -3, 1, 0)
	zero.Position = UDim2.fromScale(0, 0)
	styleCell(zero, 1.5)
	zero.Parent = numbers

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Size = UDim2.fromScale(gridW, 1)
	grid.Position = UDim2.fromScale(gridX, 0)
	grid.Parent = numbers

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.fromOffset(3, 3)
	gridLayout.CellSize = UDim2.new(1 / 12, -3 + 3 / 12, 1 / 3, -3 + 3 / 3)
	gridLayout.FillDirectionMaxCells = 12
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local order = 0
	for _, base in { 3, 2, 1 } do
		for col = 0, 11 do
			order += 1
			numberCell(base + col * 3, order).Parent = grid
		end
	end

	-- Band 2: dozens (3 cells). Band 3: even-money (6 cells). Gaps between bands.
	local dozens = outsideBand(root, UDim2.fromScale(gridW, 0.18), UDim2.fromScale(gridX, 0.60), 3)
	outsideCell("1st 12", 1).Parent = dozens
	outsideCell("2nd 12", 2).Parent = dozens
	outsideCell("3rd 12", 3).Parent = dozens

	local evens = outsideBand(root, UDim2.fromScale(gridW, 0.20), UDim2.fromScale(gridX, 0.80), 6)
	outsideCell("1-18", 1).Parent = evens
	outsideCell("EVEN", 2).Parent = evens
	outsideCell("RED", 3, NUMBER_RED).Parent = evens
	outsideCell("BLACK", 4, NUMBER_BLACK).Parent = evens
	outsideCell("ODD", 5).Parent = evens
	outsideCell("19-36", 6).Parent = evens
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

local function dressLoungeBar()
	local lobby = Workspace:FindFirstChild(LOBBY_NAME)
	local atmosphere = lobby and lobby:FindFirstChild("Atmosphere")
	local bar = atmosphere and atmosphere:FindFirstChild("LoungeBar")
	local sign = bar and bar:FindFirstChild("BarSign")
	if not (sign and sign:IsA("BasePart")) or sign:FindFirstChild("BarSignGui") then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BarSignGui"
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Cartoon
	label.Text = "BAR"
	label.TextColor3 = Config.COLORS.NeonMagenta
	label.TextScaled = true
	label.TextStrokeColor3 = Config.COLORS.NeonGold
	label.TextStrokeTransparency = 0.3
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
	dressLoungeBar()

	local lobby = Workspace:FindFirstChild(LOBBY_NAME)
	if lobby then
		CasinoChairs.place(lobby)
	end

	janitor:Add(Players.PlayerAdded:Connect(bindPlayerMovement), "Disconnect")
	for _, player in Players:GetPlayers() do
		bindPlayerMovement(player)
	end
end

return LobbyService
