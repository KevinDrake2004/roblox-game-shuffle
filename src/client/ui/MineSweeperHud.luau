--!strict
--[=[
	@class MineSweeperHud
	ScreenGui for Mine Sweeper Arcade.

	Scaffold: status, chips/loadout summary, leave. Wager / mines / grid / cash-out
	land in the gameplay commit.
]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local MineSweeperHud = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local scoreLabel: TextLabel? = nil

local onLeave: (() -> ())? = nil

local ensureGui: () -> ()

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

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -28)
	panel.Size = UDim2.fromOffset(420, 148)
	panel.BackgroundColor3 = Color3.fromRGB(22, 10, 28)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.COLORS.NeonMagenta
	stroke.Thickness = 1.5
	stroke.Transparency = 0.35
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -36, 0, 28)
	title.Font = Enum.Font.GothamBlack
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Config.COLORS.NeonMagenta
	title.TextScaled = true
	title.Text = "MINE SWEEPER ARCADE"
	title.Parent = panel

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(18, 46)
	status.Size = UDim2.new(1, -36, 0, 24)
	status.Font = Enum.Font.GothamMedium
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Config.COLORS.Text
	status.TextScaled = true
	status.Text = "Set loadout, then start a round"
	status.Parent = panel
	statusLabel = status

	local score = Instance.new("TextLabel")
	score.Name = "Score"
	score.BackgroundTransparency = 1
	score.Position = UDim2.fromOffset(18, 74)
	score.Size = UDim2.new(1, -36, 0, 22)
	score.Font = Enum.Font.Gotham
	score.TextXAlignment = Enum.TextXAlignment.Left
	score.TextColor3 = Color3.fromRGB(200, 180, 210)
	score.TextScaled = true
	score.Text = ""
	score.Parent = panel
	scoreLabel = score

	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(1, 1)
	leave.Position = UDim2.new(1, -16, 1, -14)
	leave.Size = UDim2.fromOffset(120, 34)
	leave.BackgroundColor3 = Color3.fromRGB(54, 22, 48)
	leave.BorderSizePixel = 0
	leave.Font = Enum.Font.GothamBold
	leave.TextColor3 = Config.COLORS.Text
	leave.TextScaled = true
	leave.Text = "LEAVE"
	leave.Parent = panel

	local leaveCorner = Instance.new("UICorner")
	leaveCorner.CornerRadius = UDim.new(0, 8)
	leaveCorner.Parent = leave

	leave.MouseButton1Click:Connect(function()
		if onLeave then
			onLeave()
		end
	end)
end

function MineSweeperHud.start(leaveCallback: () -> ())
	onLeave = leaveCallback
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

function MineSweeperHud.setScoreLine(text: string)
	ensureGui()
	if scoreLabel then
		scoreLabel.Text = text
	end
end

return MineSweeperHud
