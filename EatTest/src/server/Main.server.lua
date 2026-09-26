local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)

print(`[{Config.GameName}] server started`)

Players.PlayerAdded:Connect(function(player)
	print(`[{Config.GameName}] {player.Name} joined`)
end)
