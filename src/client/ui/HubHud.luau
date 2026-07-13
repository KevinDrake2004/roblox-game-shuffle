--!strict
--[=[
	@class HubHud
	Persistent chips / game-name HUD for the arcade hub.
]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local HubHud = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui: ScreenGui? = nil
local chipsLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local jobButton: TextButton? = nil
local jobStatus: TextLabel? = nil
local onJobClicked: (() -> ())? = nil

local function ensureGui()
	if gui then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "HubHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui
	gui = screen

	local bar = Instance.new("Frame")
	bar.Name = "TopBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 16)
	bar.Size = UDim2.fromOffset(420, 52)
	bar.BackgroundColor3 = Color3.fromRGB(16, 10, 28)
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bar

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.COLORS.NeonPurple
	stroke.Thickness = 1.5
	stroke.Transparency = 0.35
	stroke.Parent = bar

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 0)
	title.Size = UDim2.new(0.55, -16, 1, 0)
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Config.COLORS.Text
	title.TextScaled = true
	title.Text = Config.GAME_NAME
	title.Parent = bar
	titleLabel = title

	local chips = Instance.new("TextLabel")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.AnchorPoint = Vector2.new(1, 0)
	chips.Position = UDim2.new(1, -16, 0, 0)
	chips.Size = UDim2.new(0.4, 0, 1, 0)
	chips.Font = Enum.Font.GothamBold
	chips.TextXAlignment = Enum.TextXAlignment.Right
	chips.TextColor3 = Config.COLORS.NeonCyan
	chips.TextScaled = true
	chips.Text = "Chips: --"
	chips.Parent = bar
	chipsLabel = chips

	local work = Instance.new("TextButton")
	work.Name = "WorkJob"
	work.AnchorPoint = Vector2.new(0, 1)
	work.Position = UDim2.new(0, 20, 1, -20)
	work.Size = UDim2.fromOffset(190, 48)
	work.BackgroundColor3 = Color3.fromRGB(24, 38, 48)
	work.BorderSizePixel = 0
	work.Font = Enum.Font.GothamBold
	work.TextColor3 = Config.COLORS.NeonCyan
	work.TextScaled = true
	work.Text = "WORK A SHIFT"
	work.Parent = screen
	jobButton = work

	local workCorner = Instance.new("UICorner")
	workCorner.CornerRadius = UDim.new(0, 10)
	workCorner.Parent = work

	local workStroke = Instance.new("UIStroke")
	workStroke.Color = Config.COLORS.NeonCyan
	workStroke.Thickness = 1.5
	workStroke.Parent = work

	work.MouseButton1Click:Connect(function()
		if onJobClicked then
			onJobClicked()
		end
	end)

	local status = Instance.new("TextLabel")
	status.Name = "JobStatus"
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 20, 1, -74)
	status.Size = UDim2.fromOffset(300, 30)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamMedium
	status.TextColor3 = Config.COLORS.Text
	status.TextScaled = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = `Timing job: earn {Config.JOB.Reward} chips`
	status.Parent = screen
	jobStatus = status
end

function HubHud.start(jobClicked: (() -> ())?)
	onJobClicked = jobClicked
	ensureGui()
end

function HubHud.setChips(chips: number)
	ensureGui()
	if chipsLabel then
		chipsLabel.Text = `Chips: {chips}`
	end
end

function HubHud.setTitle(text: string)
	ensureGui()
	if titleLabel then
		titleLabel.Text = text
	end
end

function HubHud.setVisible(visible: boolean)
	ensureGui()
	if gui then
		gui.Enabled = visible
	end
end

function HubHud.setJobState(buttonText: string, statusText: string, color: Color3?)
	ensureGui()
	if jobButton then
		jobButton.Text = buttonText
		jobButton.TextColor3 = color or Config.COLORS.NeonCyan
	end
	if jobStatus then
		jobStatus.Text = statusText
	end
end

return HubHud
