--!strict
--[=[
	@class PlinkoPointsHud
	ScreenGui for Plinko Points: wager, drop, last result, session P/L.

	Shown only while the local player is inside the Plinko arena.
]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local PlinkoPointsHud = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local resultLabel: TextLabel? = nil
local scoreLabel: TextLabel? = nil
local sessionLabel: TextLabel? = nil
local wagerBox: TextBox? = nil
local ballsBox: TextBox? = nil
local dropButton: TextButton? = nil
local loadoutFrame: Frame? = nil
local feedbackFlash: Frame? = nil

local onDrop: (() -> ())? = nil
local onLeave: (() -> ())? = nil
local onApplyLoadout: ((wager: number, ballCount: number) -> ())? = nil

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

ensureGui = function()
	if gui then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "PlinkoPointsHud"
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
	flash.ZIndex = 1
	flash.Parent = screen
	feedbackFlash = flash

	local result = Instance.new("TextLabel")
	result.Name = "Result"
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Position = UDim2.fromScale(0.5, 0.28)
	result.Size = UDim2.fromOffset(520, 72)
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.GothamBlack
	result.TextColor3 = Config.COLORS.NeonPurple
	result.TextScaled = true
	result.Text = "Drop a ball"
	result.ZIndex = 3
	result.Parent = screen
	resultLabel = result

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.fromScale(0.5, 0.36)
	status.Size = UDim2.fromOffset(560, 32)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamMedium
	status.TextColor3 = Config.COLORS.Text
	status.TextScaled = true
	status.Text = "Set wager, then drop"
	status.ZIndex = 3
	status.Parent = screen
	statusLabel = status

	local score = Instance.new("TextLabel")
	score.Name = "Score"
	score.AnchorPoint = Vector2.new(0.5, 0)
	score.Position = UDim2.fromScale(0.5, 0.42)
	score.Size = UDim2.fromOffset(560, 28)
	score.BackgroundTransparency = 1
	score.Font = Enum.Font.Gotham
	score.TextColor3 = Color3.fromRGB(190, 180, 220)
	score.TextScaled = true
	score.Text = "High score: 0"
	score.ZIndex = 3
	score.Parent = screen
	scoreLabel = score

	local session = Instance.new("TextLabel")
	session.Name = "Session"
	session.AnchorPoint = Vector2.new(0.5, 0)
	session.Position = UDim2.fromScale(0.5, 0.47)
	session.Size = UDim2.fromOffset(560, 26)
	session.BackgroundTransparency = 1
	session.Font = Enum.Font.GothamBold
	session.TextColor3 = Config.COLORS.NeonPurple
	session.TextScaled = true
	session.Text = "Session: 0"
	session.ZIndex = 3
	session.Parent = screen
	sessionLabel = session

	local panel = Instance.new("Frame")
	panel.Name = "Loadout"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 24, 0.5, 0)
	panel.Size = UDim2.fromOffset(220, 248)
	panel.BackgroundColor3 = Color3.fromRGB(16, 10, 28)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.ZIndex = 4
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
	panelTitle.Size = UDim2.new(1, -24, 0, 22)
	panelTitle.Font = Enum.Font.GothamBold
	panelTitle.TextXAlignment = Enum.TextXAlignment.Left
	panelTitle.TextColor3 = Config.COLORS.Text
	panelTitle.TextScaled = true
	panelTitle.Text = "Wager / ball"
	panelTitle.Parent = panel

	local wager = Instance.new("TextBox")
	wager.Name = "Wager"
	wager.Position = UDim2.fromOffset(12, 36)
	wager.Size = UDim2.new(1, -24, 0, 32)
	wager.BackgroundColor3 = Color3.fromRGB(28, 18, 48)
	wager.BorderSizePixel = 0
	wager.Font = Enum.Font.GothamBold
	wager.TextColor3 = Config.COLORS.NeonPurple
	wager.PlaceholderText = "Wager"
	wager.Text = tostring(Config.PLINKO.DefaultWager)
	wager.TextScaled = true
	wager.ClearTextOnFocus = false
	wager.Parent = panel
	wagerBox = wager

	local wagerCorner = Instance.new("UICorner")
	wagerCorner.CornerRadius = UDim.new(0, 8)
	wagerCorner.Parent = wager

	local ballsLabel = Instance.new("TextLabel")
	ballsLabel.BackgroundTransparency = 1
	ballsLabel.Position = UDim2.fromOffset(12, 74)
	ballsLabel.Size = UDim2.new(1, -24, 0, 20)
	ballsLabel.Font = Enum.Font.GothamBold
	ballsLabel.TextXAlignment = Enum.TextXAlignment.Left
	ballsLabel.TextColor3 = Config.COLORS.Text
	ballsLabel.TextScaled = true
	ballsLabel.Text = "Balls"
	ballsLabel.Parent = panel

	local balls = Instance.new("TextBox")
	balls.Name = "Balls"
	balls.Position = UDim2.fromOffset(12, 96)
	balls.Size = UDim2.new(1, -24, 0, 32)
	balls.BackgroundColor3 = Color3.fromRGB(28, 18, 48)
	balls.BorderSizePixel = 0
	balls.Font = Enum.Font.GothamBold
	balls.TextColor3 = Config.COLORS.NeonLime
	balls.PlaceholderText = "Balls"
	balls.Text = tostring(Config.PLINKO.DefaultBallCount)
	balls.TextScaled = true
	balls.ClearTextOnFocus = false
	balls.Parent = panel
	ballsBox = balls

	local ballsCorner = Instance.new("UICorner")
	ballsCorner.CornerRadius = UDim.new(0, 8)
	ballsCorner.Parent = balls

	local apply = Instance.new("TextButton")
	apply.Name = "Apply"
	apply.Position = UDim2.fromOffset(12, 140)
	apply.Size = UDim2.new(1, -24, 0, 36)
	apply.BackgroundColor3 = Color3.fromRGB(42, 28, 72)
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
		local wagerValue = tonumber(wager.Text) or Config.PLINKO.DefaultWager
		local ballsValue = tonumber(balls.Text) or Config.PLINKO.DefaultBallCount
		onApplyLoadout(wagerValue, ballsValue)
	end)

	local note = Instance.new("TextLabel")
	note.BackgroundTransparency = 1
	note.Position = UDim2.fromOffset(12, 184)
	note.Size = UDim2.new(1, -24, 0, 48)
	note.Font = Enum.Font.Gotham
	note.TextColor3 = Color3.fromRGB(170, 160, 200)
	note.TextScaled = true
	note.Text = "Wager is per ball.\nBig volleys burst out fast."
	note.Parent = panel

	local drop = Instance.new("TextButton")
	drop.Name = "Drop"
	drop.AnchorPoint = Vector2.new(0.5, 1)
	drop.Position = UDim2.new(0.5, 0, 1, -96)
	drop.Size = UDim2.fromOffset(260, 56)
	drop.BackgroundColor3 = Color3.fromRGB(40, 22, 64)
	drop.BorderSizePixel = 0
	drop.Font = Enum.Font.GothamBold
	drop.TextColor3 = Config.COLORS.NeonPurple
	drop.TextScaled = true
	drop.Text = "DROP"
	drop.AutoButtonColor = true
	drop.ZIndex = 4
	drop.Parent = screen
	dropButton = drop

	local dropCorner = Instance.new("UICorner")
	dropCorner.CornerRadius = UDim.new(0, 10)
	dropCorner.Parent = drop

	local dropStroke = Instance.new("UIStroke")
	dropStroke.Color = Config.COLORS.NeonPurple
	dropStroke.Thickness = 1.5
	dropStroke.Parent = drop

	drop.MouseButton1Click:Connect(function()
		if onDrop then
			onDrop()
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
end

--[=[
	Build the HUD (once) and register drop / leave / loadout callbacks.
]=]
function PlinkoPointsHud.start(
	dropHandler: () -> (),
	leaveHandler: () -> (),
	applyHandler: (wager: number, ballCount: number) -> ()
)
	onDrop = dropHandler
	onLeave = leaveHandler
	onApplyLoadout = applyHandler
	ensureGui()
end

--[=[
	Show or hide the Plinko ScreenGui.
]=]
function PlinkoPointsHud.setVisible(visible: boolean)
	ensureGui()
	if gui then
		gui.Enabled = visible
	end
end

--[=[
	Update the status line under the result readout.
]=]
function PlinkoPointsHud.setStatus(text: string)
	ensureGui()
	if statusLabel then
		statusLabel.Text = text
	end
end

--[=[
	Update the large result / multiplier readout.
]=]
function PlinkoPointsHud.setResult(text: string, color: Color3?)
	ensureGui()
	if resultLabel then
		resultLabel.Text = text
		if color then
			resultLabel.TextColor3 = color
		end
	end
end

--[=[
	Update balance / high-score summary line.
]=]
function PlinkoPointsHud.setScoreLine(text: string)
	ensureGui()
	if scoreLabel then
		scoreLabel.Text = text
	end
end

--[=[
	Update session net P/L line.
]=]
function PlinkoPointsHud.setSessionLine(text: string, color: Color3?)
	ensureGui()
	if sessionLabel then
		sessionLabel.Text = text
		if color then
			sessionLabel.TextColor3 = color
		end
	end
end

--[=[
	Enable or disable the drop button.
]=]
function PlinkoPointsHud.setDropEnabled(enabled: boolean)
	ensureGui()
	if dropButton then
		dropButton.Active = enabled
		dropButton.AutoButtonColor = enabled
		dropButton.TextTransparency = if enabled then 0 else 0.45
	end
end

--[=[
	Toggle whether the wager box accepts edits.
]=]
function PlinkoPointsHud.setWagerEnabled(enabled: boolean)
	ensureGui()
	if loadoutFrame then
		loadoutFrame.Visible = true
	end
	if wagerBox then
		wagerBox.TextEditable = enabled
	end
	if ballsBox then
		ballsBox.TextEditable = enabled
	end
end

--[=[
	Sync wager + ball-count text boxes from server / default values.
]=]
function PlinkoPointsHud.setLoadoutValues(wager: number, ballCount: number)
	ensureGui()
	if wagerBox then
		wagerBox.Text = tostring(wager)
	end
	if ballsBox then
		ballsBox.Text = tostring(ballCount)
	end
end

--[=[
	Update the drop button label (e.g. DROP 5 BALLS).
]=]
function PlinkoPointsHud.setDropLabel(text: string)
	ensureGui()
	if dropButton then
		dropButton.Text = text
	end
end

--[=[
	Sync wager text box only.
]=]
function PlinkoPointsHud.setWagerValue(wager: number)
	ensureGui()
	if wagerBox then
		wagerBox.Text = tostring(wager)
	end
end

--[=[
	Flash a WIN (lime) or BUST/loss (magenta) screen pulse.
]=]
function PlinkoPointsHud.flashOutcome(outcome: string)
	if outcome == "win" then
		flashFeedback(Config.COLORS.NeonLime)
	elseif outcome == "bust" or outcome == "loss" then
		flashFeedback(Config.COLORS.NeonMagenta)
	else
		flashFeedback(Config.COLORS.NeonPurple)
	end
end

return PlinkoPointsHud
