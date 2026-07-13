--!strict
--[=[
	@class MineSweeperHud
	ScreenGui for Mine Sweeper Arcade: wager, mine count (1-24), start, cash out,
	WIN/BUST feedback. Casino Mines style - not Windows Minesweeper.
]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local MineSweeperHud = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local resultLabel: TextLabel? = nil
local scoreLabel: TextLabel? = nil
local sessionLabel: TextLabel? = nil
local multiplierLabel: TextLabel? = nil
local minesValueLabel: TextLabel? = nil
local wagerBox: TextBox? = nil
local minesSlider: TextButton? = nil
local startButton: TextButton? = nil
local cashOutButton: TextButton? = nil
local loadoutFrame: Frame? = nil
local feedbackFlash: Frame? = nil

local selectedMines = Config.MINE_SWEEPER.DefaultMines
local loadoutEnabled = true

local onStart: (() -> ())? = nil
local onCashOut: (() -> ())? = nil
local onLeave: (() -> ())? = nil
local onApplyLoadout: ((wager: number, mineCount: number) -> ())? = nil

local ensureGui: () -> ()

local function flashFeedback(color: Color3)
	ensureGui()
	if not feedbackFlash then
		return
	end
	feedbackFlash.BackgroundColor3 = color
	feedbackFlash.BackgroundTransparency = 0.55
	local tween = TweenService:Create(
		feedbackFlash,
		TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
end

local function formatMultiplier(mult: number): string
	if mult >= 100 then
		return string.format("%.1fx", mult)
	end
	return string.format("%.2fx", mult)
end

local function previewMultiplier(mineCount: number, revealed: number?): string
	local r = revealed or 1
	local mult = Config.mineSweeperMultiplier(r, mineCount)
	return formatMultiplier(mult)
end

local function refreshMinesLabel()
	if minesValueLabel then
		minesValueLabel.Text =
			string.format("Mines: %d  ·  1 gem ≈ %s", selectedMines, previewMultiplier(selectedMines, 1))
	end
end

local function pushLoadout()
	if not onApplyLoadout or not wagerBox then
		return
	end
	local wager = math.floor(tonumber(wagerBox.Text) or Config.MINE_SWEEPER.DefaultWager)
	wager = math.clamp(wager, Config.MINE_SWEEPER.MinWager, Config.MINE_SWEEPER.MaxWager)
	wagerBox.Text = tostring(wager)
	onApplyLoadout(wager, selectedMines)
end

local function setMines(count: number)
	selectedMines = math.clamp(math.floor(count), Config.MINE_SWEEPER.MinMines, Config.MINE_SWEEPER.MaxMines)
	refreshMinesLabel()
	if loadoutEnabled then
		pushLoadout()
	end
end

ensureGui = function()
	if gui then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "MineSweeperHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui
	gui = screen

	local flash = Instance.new("Frame")
	flash.Name = "FeedbackFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Config.COLORS.NeonLime
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Active = false
	flash.Selectable = false
	flash.ZIndex = 1
	flash.Parent = screen
	feedbackFlash = flash

	local function makePassThroughLabel(label: TextLabel)
		label.Active = false
		label.Selectable = false
	end

	local result = Instance.new("TextLabel")
	result.Name = "Result"
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Position = UDim2.fromScale(0.5, 0.26)
	result.Size = UDim2.fromOffset(560, 72)
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.GothamBlack
	result.TextColor3 = Config.COLORS.NeonMagenta
	result.TextScaled = true
	result.Text = "Pick gems · cash out anytime"
	result.ZIndex = 3
	result.Parent = screen
	makePassThroughLabel(result)
	resultLabel = result

	local mult = Instance.new("TextLabel")
	mult.Name = "Multiplier"
	mult.AnchorPoint = Vector2.new(0.5, 0)
	mult.Position = UDim2.fromScale(0.5, 0.34)
	mult.Size = UDim2.fromOffset(320, 48)
	mult.BackgroundTransparency = 1
	mult.Font = Enum.Font.GothamBlack
	mult.TextColor3 = Config.COLORS.NeonLime
	mult.TextScaled = true
	mult.Text = "1.00x"
	mult.ZIndex = 3
	mult.Parent = screen
	makePassThroughLabel(mult)
	multiplierLabel = mult

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.fromScale(0.5, 0.42)
	status.Size = UDim2.fromOffset(560, 28)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamMedium
	status.TextColor3 = Config.COLORS.Text
	status.TextScaled = true
	status.Text = "Set wager + mines, then start"
	status.ZIndex = 3
	status.Parent = screen
	makePassThroughLabel(status)
	statusLabel = status

	local score = Instance.new("TextLabel")
	score.Name = "Score"
	score.AnchorPoint = Vector2.new(0.5, 0)
	score.Position = UDim2.fromScale(0.5, 0.47)
	score.Size = UDim2.fromOffset(560, 26)
	score.BackgroundTransparency = 1
	score.Font = Enum.Font.Gotham
	score.TextColor3 = Color3.fromRGB(200, 180, 210)
	score.TextScaled = true
	score.Text = ""
	score.ZIndex = 3
	score.Parent = screen
	makePassThroughLabel(score)
	scoreLabel = score

	local session = Instance.new("TextLabel")
	session.Name = "Session"
	session.AnchorPoint = Vector2.new(0.5, 0)
	session.Position = UDim2.fromScale(0.5, 0.515)
	session.Size = UDim2.fromOffset(560, 24)
	session.BackgroundTransparency = 1
	session.Font = Enum.Font.GothamBold
	session.TextColor3 = Config.COLORS.NeonMagenta
	session.TextScaled = true
	session.Text = "Session: 0"
	session.ZIndex = 3
	session.Parent = screen
	makePassThroughLabel(session)
	sessionLabel = session

	local panel = Instance.new("Frame")
	panel.Name = "Loadout"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 24, 0.5, 0)
	panel.Size = UDim2.fromOffset(232, 360)
	panel.BackgroundColor3 = Color3.fromRGB(22, 10, 28)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.ZIndex = 4
	panel.Parent = screen
	loadoutFrame = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Config.COLORS.NeonMagenta
	panelStroke.Thickness = 1.2
	panelStroke.Transparency = 0.3
	panelStroke.Parent = panel

	local panelTitle = Instance.new("TextLabel")
	panelTitle.BackgroundTransparency = 1
	panelTitle.Position = UDim2.fromOffset(12, 10)
	panelTitle.Size = UDim2.new(1, -24, 0, 22)
	panelTitle.Font = Enum.Font.GothamBold
	panelTitle.TextXAlignment = Enum.TextXAlignment.Left
	panelTitle.TextColor3 = Config.COLORS.Text
	panelTitle.TextScaled = true
	panelTitle.Text = "Your round"
	panelTitle.Parent = panel

	local wagerCaption = Instance.new("TextLabel")
	wagerCaption.BackgroundTransparency = 1
	wagerCaption.Position = UDim2.fromOffset(12, 40)
	wagerCaption.Size = UDim2.new(1, -24, 0, 18)
	wagerCaption.Font = Enum.Font.GothamBold
	wagerCaption.TextXAlignment = Enum.TextXAlignment.Left
	wagerCaption.TextColor3 = Config.COLORS.Text
	wagerCaption.TextScaled = true
	wagerCaption.Text = "Wager"
	wagerCaption.Parent = panel

	local wager = Instance.new("TextBox")
	wager.Name = "Wager"
	wager.Position = UDim2.fromOffset(12, 62)
	wager.Size = UDim2.new(1, -24, 0, 34)
	wager.BackgroundColor3 = Color3.fromRGB(42, 18, 36)
	wager.BorderSizePixel = 0
	wager.Font = Enum.Font.GothamBold
	wager.TextColor3 = Config.COLORS.NeonMagenta
	wager.PlaceholderText = "Wager"
	wager.Text = tostring(Config.MINE_SWEEPER.DefaultWager)
	wager.TextScaled = true
	wager.ClearTextOnFocus = false
	wager.Parent = panel
	wagerBox = wager

	local wagerCorner = Instance.new("UICorner")
	wagerCorner.CornerRadius = UDim.new(0, 8)
	wagerCorner.Parent = wager

	wager.FocusLost:Connect(function()
		if loadoutEnabled then
			pushLoadout()
		end
	end)

	local minesCaption = Instance.new("TextLabel")
	minesCaption.Name = "MinesCaption"
	minesCaption.BackgroundTransparency = 1
	minesCaption.Position = UDim2.fromOffset(12, 108)
	minesCaption.Size = UDim2.new(1, -24, 0, 36)
	minesCaption.Font = Enum.Font.GothamBold
	minesCaption.TextXAlignment = Enum.TextXAlignment.Left
	minesCaption.TextYAlignment = Enum.TextYAlignment.Top
	minesCaption.TextColor3 = Config.COLORS.Text
	minesCaption.TextScaled = true
	minesCaption.Text = "Mines: 3"
	minesCaption.Parent = panel
	minesValueLabel = minesCaption

	local minus = Instance.new("TextButton")
	minus.Name = "MinesMinus"
	minus.Position = UDim2.fromOffset(12, 150)
	minus.Size = UDim2.fromOffset(44, 34)
	minus.BackgroundColor3 = Color3.fromRGB(54, 22, 48)
	minus.BorderSizePixel = 0
	minus.Font = Enum.Font.GothamBlack
	minus.TextColor3 = Config.COLORS.Text
	minus.TextScaled = true
	minus.Text = "-"
	minus.Parent = panel
	minesSlider = minus

	local minusCorner = Instance.new("UICorner")
	minusCorner.CornerRadius = UDim.new(0, 8)
	minusCorner.Parent = minus

	local plus = Instance.new("TextButton")
	plus.Name = "MinesPlus"
	plus.Position = UDim2.fromOffset(64, 150)
	plus.Size = UDim2.fromOffset(44, 34)
	plus.BackgroundColor3 = Color3.fromRGB(54, 22, 48)
	plus.BorderSizePixel = 0
	plus.Font = Enum.Font.GothamBlack
	plus.TextColor3 = Config.COLORS.Text
	plus.TextScaled = true
	plus.Text = "+"
	plus.Parent = panel

	local plusCorner = Instance.new("UICorner")
	plusCorner.CornerRadius = UDim.new(0, 8)
	plusCorner.Parent = plus

	minus.MouseButton1Click:Connect(function()
		if loadoutEnabled then
			setMines(selectedMines - 1)
		end
	end)
	plus.MouseButton1Click:Connect(function()
		if loadoutEnabled then
			setMines(selectedMines + 1)
		end
	end)

	local note = Instance.new("TextLabel")
	note.BackgroundTransparency = 1
	note.Position = UDim2.fromOffset(12, 194)
	note.Size = UDim2.new(1, -24, 0, 48)
	note.Font = Enum.Font.Gotham
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextYAlignment = Enum.TextYAlignment.Top
	note.TextColor3 = Color3.fromRGB(190, 160, 185)
	note.TextScaled = true
	note.Text = "More mines = higher mult\nper gem. Your board only."
	note.Parent = panel

	local start = Instance.new("TextButton")
	start.Name = "Start"
	start.Position = UDim2.fromOffset(12, 250)
	start.Size = UDim2.new(1, -24, 0, 40)
	start.BackgroundColor3 = Color3.fromRGB(72, 28, 62)
	start.BorderSizePixel = 0
	start.Font = Enum.Font.GothamBlack
	start.TextColor3 = Config.COLORS.Text
	start.TextScaled = true
	start.Text = "START ROUND"
	start.Parent = panel
	startButton = start

	local startCorner = Instance.new("UICorner")
	startCorner.CornerRadius = UDim.new(0, 8)
	startCorner.Parent = start

	start.MouseButton1Click:Connect(function()
		pushLoadout()
		if onStart then
			onStart()
		end
	end)

	local cash = Instance.new("TextButton")
	cash.Name = "CashOut"
	cash.Position = UDim2.fromOffset(12, 300)
	cash.Size = UDim2.new(1, -24, 0, 40)
	cash.BackgroundColor3 = Color3.fromRGB(36, 72, 40)
	cash.BorderSizePixel = 0
	cash.Font = Enum.Font.GothamBlack
	cash.TextColor3 = Config.COLORS.NeonLime
	cash.TextScaled = true
	cash.Text = "CASH OUT"
	cash.Visible = false
	cash.Parent = panel
	cashOutButton = cash

	local cashCorner = Instance.new("UICorner")
	cashCorner.CornerRadius = UDim.new(0, 8)
	cashCorner.Parent = cash

	cash.MouseButton1Click:Connect(function()
		if onCashOut then
			onCashOut()
		end
	end)

	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(1, 1)
	leave.Position = UDim2.new(1, -24, 1, -24)
	leave.Size = UDim2.fromOffset(120, 40)
	leave.BackgroundColor3 = Color3.fromRGB(54, 22, 48)
	leave.BorderSizePixel = 0
	leave.Font = Enum.Font.GothamBold
	leave.TextColor3 = Config.COLORS.Text
	leave.TextScaled = true
	leave.Text = "LEAVE"
	leave.ZIndex = 4
	leave.Parent = screen

	local leaveCorner = Instance.new("UICorner")
	leaveCorner.CornerRadius = UDim.new(0, 8)
	leaveCorner.Parent = leave

	leave.MouseButton1Click:Connect(function()
		if onLeave then
			onLeave()
		end
	end)

	refreshMinesLabel()
end

function MineSweeperHud.start(
	startCallback: () -> (),
	cashOutCallback: () -> (),
	leaveCallback: () -> (),
	applyLoadoutCallback: (wager: number, mineCount: number) -> ()
)
	onStart = startCallback
	onCashOut = cashOutCallback
	onLeave = leaveCallback
	onApplyLoadout = applyLoadoutCallback
	ensureGui()
end

function MineSweeperHud.setVisible(visible: boolean)
	ensureGui()
	if gui then
		gui.Enabled = visible
	end
end

function MineSweeperHud.setStatus(text: string)
	ensureGui()
	if statusLabel then
		statusLabel.Text = text
	end
end

function MineSweeperHud.setResult(text: string, color: Color3?)
	ensureGui()
	if resultLabel then
		resultLabel.Text = text
		resultLabel.TextColor3 = color or Config.COLORS.NeonMagenta
	end
end

function MineSweeperHud.setScoreLine(text: string)
	ensureGui()
	if scoreLabel then
		scoreLabel.Text = text
	end
end

function MineSweeperHud.setSessionLine(text: string, color: Color3?)
	ensureGui()
	if sessionLabel then
		sessionLabel.Text = text
		if color then
			sessionLabel.TextColor3 = color
		end
	end
end

function MineSweeperHud.setMultiplier(multiplier: number)
	ensureGui()
	if multiplierLabel then
		multiplierLabel.Text = formatMultiplier(multiplier)
		if multiplier > 1 then
			multiplierLabel.TextColor3 = Config.COLORS.NeonLime
		else
			multiplierLabel.TextColor3 = Config.COLORS.Text
		end
	end
end

function MineSweeperHud.setLoadoutValues(wager: number, mineCount: number)
	ensureGui()
	if wagerBox then
		wagerBox.Text = tostring(wager)
	end
	selectedMines = math.clamp(mineCount, Config.MINE_SWEEPER.MinMines, Config.MINE_SWEEPER.MaxMines)
	refreshMinesLabel()
end

function MineSweeperHud.setLoadoutEnabled(enabled: boolean)
	ensureGui()
	loadoutEnabled = enabled
	if wagerBox then
		wagerBox.TextEditable = enabled
		wagerBox.BackgroundColor3 = if enabled then Color3.fromRGB(42, 18, 36) else Color3.fromRGB(28, 14, 24)
	end
	if minesSlider then
		minesSlider.Active = enabled
	end
	if loadoutFrame then
		local plus = loadoutFrame:FindFirstChild("MinesPlus")
		if plus and plus:IsA("GuiButton") then
			plus.Active = enabled
		end
	end
end

function MineSweeperHud.setStartEnabled(enabled: boolean)
	ensureGui()
	if startButton then
		startButton.Active = enabled
		startButton.AutoButtonColor = enabled
		startButton.BackgroundColor3 = if enabled then Color3.fromRGB(72, 28, 62) else Color3.fromRGB(40, 20, 36)
	end
end

function MineSweeperHud.setCashOutEnabled(enabled: boolean)
	ensureGui()
	if cashOutButton then
		cashOutButton.Visible = enabled
		cashOutButton.Active = enabled
	end
end

function MineSweeperHud.flashOutcome(outcome: string)
	if outcome == "cashed_out" or outcome == "win" then
		flashFeedback(Config.COLORS.NeonLime)
	elseif outcome == "mine_hit" or outcome == "bust" then
		flashFeedback(Config.COLORS.NeonMagenta)
	else
		flashFeedback(Config.COLORS.NeonPurple)
	end
end

return MineSweeperHud
