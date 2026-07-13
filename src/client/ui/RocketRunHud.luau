--!strict
--[=[
	@class RocketRunHud
	ScreenGui for Rocket Run: loadout, view modes, live multiplier, graph, cash-out.

	Loadout fields:
	- Wager - chips staked when you become eligible for a round
	- Auto cash-out - optional target multiplier (0 / empty disables)

	View modes (labels in UI: Walk / Graph / Rocket / Both):
	- Walk - free camera, no overlay graph
	- Telemetry / Graph - full-screen multiplier curve
	- Rocket - follow-cam on the rocket
	- Both - follow-cam plus a compact overlay graph
]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local RocketRunHud = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui: ScreenGui? = nil
local multiplierLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local scoreLabel: TextLabel? = nil
local cashOutButton: TextButton? = nil
local wagerBox: TextBox? = nil
local autoBox: TextBox? = nil
local loadoutFrame: Frame? = nil
local muteButton: TextButton? = nil
local graphFrame: Frame? = nil
local graphPlot: Frame? = nil
local graphSegments: Frame? = nil
local graphMarkers: Frame? = nil
local viewButtons: { [string]: TextButton } = {}
local currentViewMode = "Walk"
local onViewModeChanged: ((mode: string) -> ())? = nil

type GraphPoint = {
	elapsed: number,
	multiplier: number,
}

type GraphMarker = {
	label: string,
	elapsed: number,
	multiplier: number,
	color: Color3,
	isCrash: boolean,
}

local graphPoints: { GraphPoint } = {}
local cashOutMarkers: { GraphMarker } = {}
local linePool: { Frame } = {}

local onCashOut: (() -> ())? = nil
local onLeave: (() -> ())? = nil
local onMute: (() -> ())? = nil
local onApplyLoadout: ((wager: number, autoCashOut: number?) -> ())? = nil

local function setLine(line: Frame, from: Vector2, to: Vector2, color: Color3, thickness: number)
	local delta = to - from
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
	line.Size = UDim2.fromOffset(delta.Magnitude, thickness)
	line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	line.BackgroundColor3 = color
	line.Visible = true
end

local function redrawGraph()
	local plot = graphPlot
	local segments = graphSegments
	local markers = graphMarkers
	if not plot or not segments or not markers or #graphPoints == 0 then
		return
	end

	for _, child in markers:GetChildren() do
		child:Destroy()
	end

	local size = plot.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local lastPoint = graphPoints[#graphPoints]
	local maxElapsed = math.max(8, lastPoint.elapsed)
	local maxMultiplier = math.max(2, lastPoint.multiplier)
	for _, marker in cashOutMarkers do
		maxMultiplier = math.max(maxMultiplier, marker.multiplier)
	end
	maxMultiplier *= 1.12

	local function toPlot(elapsed: number, multiplier: number): Vector2
		local x = math.clamp(elapsed / maxElapsed, 0, 1) * size.X
		local normalizedY = (math.max(1, multiplier) - 1) / (maxMultiplier - 1)
		return Vector2.new(x, size.Y * (1 - math.clamp(normalizedY, 0, 1)))
	end

	local usedLines = 0
	local function drawLine(from: Vector2, to: Vector2)
		usedLines += 1
		local line = linePool[usedLines]
		if not line then
			line = Instance.new("Frame")
			line.Name = "CurveSegment"
			line.BorderSizePixel = 0
			line.Parent = segments
			table.insert(linePool, line)
		end
		setLine(line, from, to, Config.COLORS.NeonCyan, 3)
	end

	-- The multiplier is exponential, so draw a fixed analytic curve. Keeping
	-- the same segment count prevents decimation thresholds from flashing or
	-- producing temporary off-path segments.
	local segmentCount = 64
	local logMultiplier = math.log(math.max(1, lastPoint.multiplier))
	local previous = toPlot(0, 1)
	for index = 1, segmentCount do
		local alpha = index / segmentCount
		local elapsed = lastPoint.elapsed * alpha
		local multiplier = math.exp(logMultiplier * alpha)
		local current = toPlot(elapsed, multiplier)
		drawLine(previous, current)
		previous = current
	end

	for index = usedLines + 1, #linePool do
		linePool[index].Visible = false
	end

	for _, marker in cashOutMarkers do
		local point = toPlot(marker.elapsed, marker.multiplier)
		local dot = Instance.new("Frame")
		dot.Name = if marker.isCrash then "CrashMarker" else "CashOutMarker"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromOffset(point.X, point.Y)
		dot.Size = UDim2.fromOffset(if marker.isCrash then 14 else 10, if marker.isCrash then 14 else 10)
		dot.BackgroundColor3 = marker.color
		dot.BorderSizePixel = 0
		dot.Rotation = 45
		dot.Parent = markers

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromOffset(point.X, point.Y - 8)
		label.Size = UDim2.fromOffset(140, 22)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = marker.color
		label.TextScaled = true
		label.Text = marker.label
		label.Parent = markers
	end

	local livePoint = toPlot(lastPoint.elapsed, lastPoint.multiplier)
	local liveDot = Instance.new("Frame")
	liveDot.Name = "LiveCursor"
	liveDot.AnchorPoint = Vector2.new(0.5, 0.5)
	liveDot.Position = UDim2.fromOffset(livePoint.X, livePoint.Y)
	liveDot.Size = UDim2.fromOffset(12, 12)
	liveDot.BackgroundColor3 = Config.COLORS.NeonCyan
	liveDot.BorderSizePixel = 0
	liveDot.Parent = markers

	local liveCorner = Instance.new("UICorner")
	liveCorner.CornerRadius = UDim.new(1, 0)
	liveCorner.Parent = liveDot

	local liveLabel = Instance.new("TextLabel")
	liveLabel.Name = "LiveValue"
	liveLabel.AnchorPoint = Vector2.new(1, 0.5)
	liveLabel.Position = UDim2.fromOffset(livePoint.X - 10, livePoint.Y)
	liveLabel.Size = UDim2.fromOffset(90, 24)
	liveLabel.BackgroundTransparency = 1
	liveLabel.Font = Enum.Font.GothamBold
	liveLabel.TextColor3 = Config.COLORS.NeonCyan
	liveLabel.TextScaled = true
	liveLabel.Text = string.format("%.2fx", lastPoint.multiplier)
	liveLabel.Parent = markers
end

local function ensureGui()
	if gui then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "RocketRunHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui
	gui = screen

	local graph = Instance.new("Frame")
	graph.Name = "RoundTelemetry"
	graph.AnchorPoint = Vector2.new(0.5, 0)
	graph.Position = UDim2.new(0.5, 0, 0, 124)
	graph.Size = UDim2.fromOffset(620, 260)
	graph.BackgroundColor3 = Color3.fromRGB(10, 7, 20)
	graph.BackgroundTransparency = 0.18
	graph.BorderSizePixel = 0
	graph.ClipsDescendants = true
	graph.Parent = screen
	graphFrame = graph

	local graphCorner = Instance.new("UICorner")
	graphCorner.CornerRadius = UDim.new(0, 12)
	graphCorner.Parent = graph

	local graphStroke = Instance.new("UIStroke")
	graphStroke.Color = Config.COLORS.NeonPurple
	graphStroke.Thickness = 1
	graphStroke.Transparency = 0.5
	graphStroke.Parent = graph

	local graphTitle = Instance.new("TextLabel")
	graphTitle.Name = "Title"
	graphTitle.BackgroundTransparency = 1
	graphTitle.Position = UDim2.fromOffset(12, 6)
	graphTitle.Size = UDim2.new(1, -24, 0, 22)
	graphTitle.Font = Enum.Font.GothamBold
	graphTitle.TextColor3 = Color3.fromRGB(165, 150, 195)
	graphTitle.TextSize = 14
	graphTitle.TextXAlignment = Enum.TextXAlignment.Left
	graphTitle.Text = "TELEMETRY  •  cash-out  ◆  crash"
	graphTitle.Parent = graph

	local plot = Instance.new("Frame")
	plot.Name = "Plot"
	plot.Position = UDim2.fromOffset(16, 36)
	plot.Size = UDim2.new(1, -32, 1, -52)
	plot.BackgroundTransparency = 1
	plot.ClipsDescendants = true
	plot.Parent = graph
	graphPlot = plot

	local segments = Instance.new("Frame")
	segments.Name = "Curve"
	segments.Size = UDim2.fromScale(1, 1)
	segments.BackgroundTransparency = 1
	segments.ClipsDescendants = true
	segments.Parent = plot
	graphSegments = segments

	local markers = Instance.new("Frame")
	markers.Name = "Markers"
	markers.Size = UDim2.fromScale(1, 1)
	markers.BackgroundTransparency = 1
	markers.ClipsDescendants = true
	markers.Parent = plot
	graphMarkers = markers

	local mute = Instance.new("TextButton")
	mute.Name = "MuteRocket"
	mute.AnchorPoint = Vector2.new(1, 0)
	mute.Position = UDim2.new(1, -20, 0, 78)
	mute.Size = UDim2.fromOffset(132, 34)
	mute.BackgroundColor3 = Color3.fromRGB(28, 20, 44)
	mute.BorderSizePixel = 0
	mute.Font = Enum.Font.GothamBold
	mute.TextColor3 = Config.COLORS.Text
	mute.TextSize = 14
	mute.TextScaled = false
	mute.Text = "Mute"
	mute.ZIndex = 6
	mute.Parent = screen
	muteButton = mute

	local muteCorner = Instance.new("UICorner")
	muteCorner.CornerRadius = UDim.new(0, 8)
	muteCorner.Parent = mute

	mute.MouseButton1Click:Connect(function()
		if onMute then
			onMute()
		end
	end)

	-- Sits under HubHud top bar (y≈16–68) so it never overlaps chips/title.
	local viewControls = Instance.new("Frame")
	viewControls.Name = "ViewControls"
	viewControls.AnchorPoint = Vector2.new(0.5, 0)
	viewControls.Position = UDim2.new(0.5, 0, 0, 78)
	viewControls.Size = UDim2.fromOffset(404, 34)
	viewControls.BackgroundColor3 = Color3.fromRGB(14, 10, 26)
	viewControls.BackgroundTransparency = 0.12
	viewControls.BorderSizePixel = 0
	viewControls.ZIndex = 6
	viewControls.Parent = screen

	local viewCorner = Instance.new("UICorner")
	viewCorner.CornerRadius = UDim.new(0, 8)
	viewCorner.Parent = viewControls

	local viewStroke = Instance.new("UIStroke")
	viewStroke.Color = Config.COLORS.NeonPurple
	viewStroke.Thickness = 1
	viewStroke.Transparency = 0.55
	viewStroke.Parent = viewControls

	local viewPadding = Instance.new("UIPadding")
	viewPadding.PaddingLeft = UDim.new(0, 4)
	viewPadding.PaddingRight = UDim.new(0, 4)
	viewPadding.PaddingTop = UDim.new(0, 3)
	viewPadding.PaddingBottom = UDim.new(0, 3)
	viewPadding.Parent = viewControls

	local viewLayout = Instance.new("UIListLayout")
	viewLayout.FillDirection = Enum.FillDirection.Horizontal
	viewLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	viewLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	viewLayout.Padding = UDim.new(0, 4)
	viewLayout.Parent = viewControls

	local viewLabels = {
		{ id = "Walk", label = "Walk" },
		{ id = "Telemetry", label = "Graph" },
		{ id = "Rocket", label = "Rocket" },
		{ id = "Both", label = "Both" },
	}
	for _, mode in viewLabels do
		local button = Instance.new("TextButton")
		button.Name = `View{mode.id}`
		button.Size = UDim2.fromOffset(94, 28)
		button.BackgroundColor3 = Color3.fromRGB(28, 20, 44)
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.TextColor3 = Config.COLORS.Text
		button.TextSize = 14
		button.TextScaled = false
		button.Text = mode.label
		button.ZIndex = 7
		button.Parent = viewControls
		viewButtons[mode.id] = button

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button

		button.MouseButton1Click:Connect(function()
			RocketRunHud.setViewMode(mode.id)
		end)
	end

	local multiplier = Instance.new("TextLabel")
	multiplier.Name = "Multiplier"
	multiplier.AnchorPoint = Vector2.new(0.5, 0.5)
	multiplier.Position = UDim2.fromScale(0.5, 0.34)
	multiplier.Size = UDim2.fromOffset(360, 120)
	multiplier.BackgroundTransparency = 1
	multiplier.Font = Enum.Font.GothamBlack
	multiplier.TextColor3 = Config.COLORS.NeonCyan
	multiplier.TextScaled = true
	multiplier.Text = "1.00x"
	multiplier.ZIndex = 3
	multiplier.Parent = screen
	multiplierLabel = multiplier

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.fromScale(0.5, 0.44)
	status.Size = UDim2.fromOffset(520, 36)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamMedium
	status.TextColor3 = Config.COLORS.Text
	status.TextScaled = true
	status.Text = "Get ready…"
	status.ZIndex = 3
	status.Parent = screen
	statusLabel = status

	local score = Instance.new("TextLabel")
	score.Name = "Score"
	score.AnchorPoint = Vector2.new(0.5, 0)
	score.Position = UDim2.fromScale(0.5, 0.5)
	score.Size = UDim2.fromOffset(520, 28)
	score.BackgroundTransparency = 1
	score.Font = Enum.Font.Gotham
	score.TextColor3 = Color3.fromRGB(190, 180, 220)
	score.TextScaled = true
	score.Text = "High score: 0"
	score.ZIndex = 3
	score.Parent = screen
	scoreLabel = score

	local panel = Instance.new("Frame")
	panel.Name = "Loadout"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 24, 0.5, 0)
	panel.Size = UDim2.fromOffset(220, 210)
	panel.BackgroundColor3 = Color3.fromRGB(16, 10, 28)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Parent = screen
	loadoutFrame = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Config.COLORS.NeonPurple
	panelStroke.Thickness = 1.2
	panelStroke.Transparency = 0.3
	panelStroke.Parent = panel

	local panelTitle = Instance.new("TextLabel")
	panelTitle.BackgroundTransparency = 1
	panelTitle.Position = UDim2.fromOffset(12, 10)
	panelTitle.Size = UDim2.new(1, -24, 0, 24)
	panelTitle.Font = Enum.Font.GothamBold
	panelTitle.TextXAlignment = Enum.TextXAlignment.Left
	panelTitle.TextColor3 = Config.COLORS.Text
	panelTitle.TextScaled = true
	panelTitle.Text = "Wager"
	panelTitle.Parent = panel

	local wager = Instance.new("TextBox")
	wager.Name = "Wager"
	wager.Position = UDim2.fromOffset(12, 42)
	wager.Size = UDim2.new(1, -24, 0, 34)
	wager.BackgroundColor3 = Color3.fromRGB(28, 18, 48)
	wager.BorderSizePixel = 0
	wager.Font = Enum.Font.GothamBold
	wager.TextColor3 = Config.COLORS.NeonCyan
	wager.PlaceholderText = "Wager"
	wager.Text = tostring(Config.ROCKET_RUN.DefaultWager)
	wager.TextScaled = true
	wager.ClearTextOnFocus = false
	wager.Parent = panel
	wagerBox = wager

	local wagerCorner = Instance.new("UICorner")
	wagerCorner.CornerRadius = UDim.new(0, 8)
	wagerCorner.Parent = wager

	local autoLabel = Instance.new("TextLabel")
	autoLabel.BackgroundTransparency = 1
	autoLabel.Position = UDim2.fromOffset(12, 86)
	autoLabel.Size = UDim2.new(1, -24, 0, 22)
	autoLabel.Font = Enum.Font.GothamBold
	autoLabel.TextXAlignment = Enum.TextXAlignment.Left
	autoLabel.TextColor3 = Config.COLORS.Text
	autoLabel.TextScaled = true
	autoLabel.Text = "Auto cash-out (0=off)"
	autoLabel.Parent = panel

	local auto = Instance.new("TextBox")
	auto.Name = "AutoCashOut"
	auto.Position = UDim2.fromOffset(12, 114)
	auto.Size = UDim2.new(1, -24, 0, 34)
	auto.BackgroundColor3 = Color3.fromRGB(28, 18, 48)
	auto.BorderSizePixel = 0
	auto.Font = Enum.Font.GothamBold
	auto.TextColor3 = Config.COLORS.NeonLime
	auto.PlaceholderText = "e.g. 2.00"
	auto.Text = "0"
	auto.TextScaled = true
	auto.ClearTextOnFocus = false
	auto.Parent = panel
	autoBox = auto

	local autoCorner = Instance.new("UICorner")
	autoCorner.CornerRadius = UDim.new(0, 8)
	autoCorner.Parent = auto

	local apply = Instance.new("TextButton")
	apply.Name = "Apply"
	apply.Position = UDim2.fromOffset(12, 160)
	apply.Size = UDim2.new(1, -24, 0, 36)
	apply.BackgroundColor3 = Color3.fromRGB(32, 24, 56)
	apply.BorderSizePixel = 0
	apply.Font = Enum.Font.GothamBold
	apply.TextColor3 = Config.COLORS.Text
	apply.TextScaled = true
	apply.Text = "Apply"
	apply.Parent = panel

	local applyCorner = Instance.new("UICorner")
	applyCorner.CornerRadius = UDim.new(0, 8)
	applyCorner.Parent = apply

	apply.MouseButton1Click:Connect(function()
		if not onApplyLoadout then
			return
		end
		local wagerValue = tonumber(wager.Text) or Config.ROCKET_RUN.DefaultWager
		local autoValue = tonumber(auto.Text)
		onApplyLoadout(wagerValue, if autoValue and autoValue >= 1.01 then autoValue else nil)
	end)

	local note = Instance.new("TextLabel")
	note.BackgroundTransparency = 1
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Position = UDim2.new(0.5, 0, 1, -160)
	note.Size = UDim2.fromOffset(560, 28)
	note.Font = Enum.Font.Gotham
	note.TextColor3 = Color3.fromRGB(170, 160, 200)
	note.TextScaled = true
	note.Text = "Wager chips each round. Cash out to collect payout - crash loses the wager."
	note.Parent = screen

	local cashOut = Instance.new("TextButton")
	cashOut.Name = "CashOut"
	cashOut.AnchorPoint = Vector2.new(0.5, 1)
	cashOut.Position = UDim2.new(0.5, 0, 1, -96)
	cashOut.Size = UDim2.fromOffset(240, 56)
	cashOut.BackgroundColor3 = Color3.fromRGB(20, 40, 48)
	cashOut.BorderSizePixel = 0
	cashOut.Font = Enum.Font.GothamBold
	cashOut.TextColor3 = Config.COLORS.NeonLime
	cashOut.TextScaled = true
	cashOut.Text = "CASH OUT [Space]"
	cashOut.AutoButtonColor = true
	cashOut.Parent = screen
	cashOutButton = cashOut

	local cashCorner = Instance.new("UICorner")
	cashCorner.CornerRadius = UDim.new(0, 10)
	cashCorner.Parent = cashOut

	local cashStroke = Instance.new("UIStroke")
	cashStroke.Color = Config.COLORS.NeonLime
	cashStroke.Thickness = 1.5
	cashStroke.Parent = cashOut

	cashOut.MouseButton1Click:Connect(function()
		if onCashOut then
			onCashOut()
		end
	end)

	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(1, 1)
	leave.Position = UDim2.new(1, -24, 1, -24)
	leave.Size = UDim2.fromOffset(140, 40)
	leave.BackgroundColor3 = Color3.fromRGB(36, 18, 40)
	leave.BorderSizePixel = 0
	leave.Font = Enum.Font.GothamBold
	leave.TextColor3 = Config.COLORS.Text
	leave.TextScaled = true
	leave.Text = "Leave"
	leave.Parent = screen

	local leaveCorner = Instance.new("UICorner")
	leaveCorner.CornerRadius = UDim.new(0, 8)
	leaveCorner.Parent = leave

	leave.MouseButton1Click:Connect(function()
		if onLeave then
			onLeave()
		end
	end)
end

--[=[
	Build the HUD (once) and register cash-out / leave / loadout / mute / view callbacks.
]=]
function RocketRunHud.start(
	cashOutHandler: () -> (),
	leaveHandler: () -> (),
	applyHandler: (wager: number, autoCashOut: number?) -> (),
	muteHandler: () -> (),
	viewModeHandler: ((mode: string) -> ())?
)
	onCashOut = cashOutHandler
	onLeave = leaveHandler
	onApplyLoadout = applyHandler
	onMute = muteHandler
	onViewModeChanged = viewModeHandler
	ensureGui()
	RocketRunHud.setViewMode("Walk")
end

--[=[
	Show or hide the entire Rocket Run ScreenGui.
]=]
function RocketRunHud.setVisible(visible: boolean)
	ensureGui()
	if gui then
		gui.Enabled = visible
	end
end

--[=[
	Update the large center multiplier readout.
]=]
function RocketRunHud.setMultiplier(multiplier: number, color: Color3?)
	ensureGui()
	if multiplierLabel then
		multiplierLabel.Text = string.format("%.2fx", multiplier)
		if color then
			multiplierLabel.TextColor3 = color
		end
	end
end

--[=[
	Update the status line under the multiplier.
]=]
function RocketRunHud.setStatus(text: string)
	ensureGui()
	if statusLabel then
		statusLabel.Text = text
	end
end

--[=[
	Update the secondary score / loadout summary line.
]=]
function RocketRunHud.setScoreLine(text: string)
	ensureGui()
	if scoreLabel then
		scoreLabel.Text = text
	end
end

--[=[
	Enable or hide the cash-out button (Space still routes through the controller).
]=]
function RocketRunHud.setCashOutEnabled(enabled: boolean)
	ensureGui()
	if cashOutButton then
		cashOutButton.Visible = enabled
		cashOutButton.Active = enabled
	end
end

--[=[
	Toggle whether loadout text boxes accept edits. Panel stays visible in all modes.
]=]
function RocketRunHud.setLoadoutEnabled(enabled: boolean)
	ensureGui()
	if loadoutFrame then
		loadoutFrame.Visible = true
	end
	if wagerBox then
		wagerBox.TextEditable = enabled
	end
	if autoBox then
		autoBox.TextEditable = enabled
	end
end

--[=[
	@return string -- Current view mode: Walk, Telemetry, Rocket, or Both
]=]
function RocketRunHud.getViewMode(): string
	return currentViewMode
end

--[=[
	Apply a view mode and notify the controller (camera / graph layout).
]=]
function RocketRunHud.setViewMode(mode: string)
	ensureGui()
	if mode ~= "Walk" and mode ~= "Telemetry" and mode ~= "Rocket" and mode ~= "Both" then
		return
	end
	currentViewMode = mode

	if graphFrame then
		if mode == "Telemetry" then
			graphFrame.Visible = true
			graphFrame.AnchorPoint = Vector2.new(0.5, 0)
			graphFrame.Position = UDim2.new(0.5, 0, 0, 124)
			graphFrame.Size = UDim2.new(1, -64, 1, -190)
			graphFrame.BackgroundTransparency = 0.02
		elseif mode == "Both" then
			graphFrame.Visible = true
			graphFrame.AnchorPoint = Vector2.new(0.5, 0)
			graphFrame.Position = UDim2.new(0.5, 0, 0, 124)
			graphFrame.Size = UDim2.fromOffset(620, 260)
			graphFrame.BackgroundTransparency = 0.18
		else
			-- Walk and Rocket: free/follow view without the big overlay graph
			graphFrame.Visible = false
		end
	end

	if loadoutFrame then
		loadoutFrame.Visible = true
	end

	for buttonMode, button in viewButtons do
		local selected = buttonMode == mode
		button.BackgroundColor3 = if selected then Color3.fromRGB(42, 35, 70) else Color3.fromRGB(28, 20, 44)
		button.TextColor3 = if selected then Config.COLORS.NeonCyan else Config.COLORS.Text
	end

	if onViewModeChanged then
		onViewModeChanged(mode)
	end
	redrawGraph()
end

--[=[
	Sync loadout text boxes from server round / default values.
]=]
function RocketRunHud.setLoadoutValues(wager: number, autoCashOut: number?)
	ensureGui()
	if wagerBox then
		wagerBox.Text = tostring(wager)
	end
	if autoBox then
		autoBox.Text = if autoCashOut then string.format("%.2f", autoCashOut) else "0"
	end
end

--[=[
	Update Mute / Unmute button copy and accent.
]=]
function RocketRunHud.setMuted(muted: boolean)
	ensureGui()
	if muteButton then
		muteButton.Text = if muted then "Unmute" else "Mute"
		muteButton.TextColor3 = if muted then Config.COLORS.NeonMagenta else Config.COLORS.Text
	end
end

--[=[
	Reset the overlay graph for a new round.
]=]
function RocketRunHud.beginGraph()
	ensureGui()
	table.clear(graphPoints)
	table.clear(cashOutMarkers)
	table.insert(graphPoints, {
		elapsed = 0,
		multiplier = 1,
	})
	redrawGraph()
end

--[=[
	Append a sample to the live multiplier curve (throttled).
]=]
function RocketRunHud.updateGraph(elapsed: number, multiplier: number)
	ensureGui()
	local lastPoint = graphPoints[#graphPoints]
	if lastPoint and elapsed - lastPoint.elapsed < 0.06 then
		return
	end
	table.insert(graphPoints, {
		elapsed = elapsed,
		multiplier = multiplier,
	})
	redrawGraph()
end

--[=[
	Mark another player's (or the local player's) cash-out on the graph.
]=]
function RocketRunHud.addCashOutMarker(displayName: string, elapsed: number, multiplier: number, isLocal: boolean)
	table.insert(cashOutMarkers, {
		label = string.format("%s %.2fx", if isLocal then "YOU" else string.sub(displayName, 1, 10), multiplier),
		elapsed = elapsed,
		multiplier = multiplier,
		color = if isLocal then Config.COLORS.NeonLime else Config.COLORS.NeonPurple,
		isCrash = false,
	})
	redrawGraph()
end

--[=[
	Finalize the graph with a crash marker at the given point.
]=]
function RocketRunHud.finishGraph(elapsed: number, multiplier: number)
	RocketRunHud.updateGraph(elapsed, multiplier)
	table.insert(cashOutMarkers, {
		label = string.format("CRASH %.2fx", multiplier),
		elapsed = elapsed,
		multiplier = multiplier,
		color = Config.COLORS.NeonMagenta,
		isCrash = true,
	})
	redrawGraph()
end

return RocketRunHud
