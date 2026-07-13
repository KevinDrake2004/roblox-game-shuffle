--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local HubController = require(script.controllers.HubController)
local RocketRunController = require(script.controllers.RocketRunController)
local PlinkoPointsController = require(script.controllers.PlinkoPointsController)

HubController.start()
RocketRunController.start()
PlinkoPointsController.start()

print(`[Shuffle] Client ready — {Config.GAME_NAME}`)
