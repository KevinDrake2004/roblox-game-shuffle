--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))

local DataService = require(script.services.DataService)
local CurrencyService = require(script.services.CurrencyService)
local JobService = require(script.services.JobService)
local LobbyService = require(script.services.LobbyService)
local RocketRun = require(script.games.RocketRun)
local PlinkoPoints = require(script.games.PlinkoPoints)
local MineSweeper = require(script.games.MineSweeper)
local ArenaZones = require(script.services.ArenaZones)
local CasinoTerrain = require(script.services.CasinoTerrain)

Remotes.init()
CasinoTerrain.start()
DataService.start()
CurrencyService.start()
JobService.start()
LobbyService.start()
RocketRun.start()
PlinkoPoints.start()
MineSweeper.start()
ArenaZones.start()

print(`[Shuffle] Server ready — {Config.GAME_NAME}`)
