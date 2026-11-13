--!strict
-- Boots the digging game: tests (Studio) -> terrain -> remotes -> players.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("DigShared")
local DigConfig = require(Shared:WaitForChild("DigConfig"))

local DigWorld = require(script.Parent.DigWorld)
local DigService = require(script.Parent.DigService)
local PlayerData = require(script.Parent.PlayerData)

if RunService:IsStudio() and DigConfig.RunSelfTestsInStudio then
	require(Shared:WaitForChild("DigLogicTests")).run()
end

local started = os.clock()
DigWorld.init()
DigService.init()
PlayerData.start()
DigService.start()

DigWorld.generateTerrain()
DigWorld.restockLoot()
print(string.format("[Dig] dig site ready in %.1fs", os.clock() - started))
