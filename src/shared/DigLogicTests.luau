--!strict
--[[
	DigLogicTests - tiny self-contained test runner for DigLogic and the
	config tables. The server runs it once on start in Studio
	(DigConfig.RunSelfTestsInStudio) and prints the result to Output.
]]

local DigConfig = require(script.Parent.DigConfig)
local DigLogic = require(script.Parent.DigLogic)

local DigLogicTests = {}

type Case = { name: string, fn: () -> () }

local function expectEq(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
	end
end

local function expectTrue(value: boolean, label: string)
	if not value then
		error(label .. ": expected true", 2)
	end
end

local cases: { Case } = {
	{
		name = "layers are contiguous, voxel aligned and reach Area.Depth",
		fn = function()
			local previousBottom = 0
			for i, layer in DigConfig.Layers do
				expectEq(layer.Top, previousBottom, "layer " .. i .. " top")
				expectTrue(layer.Bottom > layer.Top, "layer " .. i .. " has thickness")
				expectEq(layer.Top % DigConfig.VoxelSize, 0, "layer " .. i .. " top aligned")
				expectEq(layer.Bottom % DigConfig.VoxelSize, 0, "layer " .. i .. " bottom aligned")
				previousBottom = layer.Bottom
			end
			expectEq(previousBottom, DigConfig.Area.Depth, "last layer bottom")
			expectEq(#DigConfig.Loot, #DigConfig.Layers, "one loot table per layer")
		end,
	},
	{
		name = "getLayerIndex boundaries",
		fn = function()
			expectEq(DigLogic.getLayerIndex(-5), 1, "above surface")
			expectEq(DigLogic.getLayerIndex(0), 1, "surface")
			expectEq(DigLogic.getLayerIndex(23.9), 1, "just above clay")
			expectEq(DigLogic.getLayerIndex(24), 2, "clay top")
			expectEq(DigLogic.getLayerIndex(159), #DigConfig.Layers, "deepest")
			expectEq(DigLogic.getLayerIndex(9999), #DigConfig.Layers, "below bottom clamps")
		end,
	},
	{
		name = "shovel tiers gate hard layers",
		fn = function()
			local rusty = DigLogic.getShovel(1)
			expectTrue(DigLogic.canDig(rusty, DigConfig.Layers[1]), "rusty digs topsoil")
			expectTrue(not DigLogic.canDig(rusty, DigConfig.Layers[3]), "rusty can't dig stone")
			expectEq(DigLogic.requiredShovelName(DigConfig.Layers[3]), "Iron Shovel", "stone needs iron")
			local best = DigLogic.getShovel(#DigConfig.Shovels)
			for _, layer in DigConfig.Layers do
				expectTrue(DigLogic.canDig(best, layer), "best shovel digs " .. layer.Name)
			end
		end,
	},
	{
		name = "upgrade tables are priced in ascending order",
		fn = function()
			for i = 2, #DigConfig.Shovels do
				expectTrue(DigConfig.Shovels[i].Price > DigConfig.Shovels[i - 1].Price, "shovel price " .. i)
			end
			for i = 2, #DigConfig.Backpacks do
				expectTrue(DigConfig.Backpacks[i].Capacity > DigConfig.Backpacks[i - 1].Capacity, "pack size " .. i)
			end
			expectEq(DigLogic.getShovel(0).Name, DigConfig.Shovels[1].Name, "level 0 clamps")
			expectEq(DigLogic.getShovel(99).Name, DigConfig.Shovels[#DigConfig.Shovels].Name, "level 99 clamps")
		end,
	},
	{
		name = "radius never drops below a voxel and cost scales with hardness",
		fn = function()
			local rusty = DigLogic.getShovel(1)
			for _, layer in DigConfig.Layers do
				expectTrue(
					DigLogic.effectiveRadius(rusty, layer) >= DigConfig.VoxelSize * 0.75,
					"radius in " .. layer.Name
				)
			end
			expectTrue(
				DigLogic.staminaCost(rusty, DigConfig.Layers[2]) > DigLogic.staminaCost(rusty, DigConfig.Layers[1]),
				"clay costs more than topsoil"
			)
		end,
	},
	{
		name = "pickLoot covers the whole roll range",
		fn = function()
			for layerIndex, lootTable in DigConfig.Loot do
				expectEq(DigLogic.pickLoot(layerIndex, 0).Id, lootTable[1].Id, "roll 0")
				expectEq(DigLogic.pickLoot(layerIndex, 0.999999).Id, lootTable[#lootTable].Id, "roll ~1")
			end
		end,
	},
	{
		name = "sellValue ignores unknown ids",
		fn = function()
			expectEq(DigLogic.sellValue({ "rusty_can", "bone", "not_real" }), 11, "sum")
			expectEq(DigLogic.sellValue({}), 0, "empty")
		end,
	},
	{
		name = "clampDigCenter keeps the ball inside the pit",
		fn = function()
			local bounds = { MinX = 0, MaxX = 100, MinZ = 0, MaxZ = 100, SurfaceY = 0, BottomY = -160 }
			local c = DigLogic.clampDigCenter(Vector3.new(-50, -500, 200), 5, bounds)
			expectEq(c.X, 5, "x")
			expectEq(c.Y, -155, "y")
			expectEq(c.Z, 95, "z")
		end,
	},
	{
		name = "formatCash and isFiniteVector",
		fn = function()
			expectEq(DigLogic.formatCash(12), "$12", "small")
			expectEq(DigLogic.formatCash(1500), "$1,500", "thousands")
			expectEq(DigLogic.formatCash(123456), "$123,456", "six digits")
			expectTrue(not DigLogic.isFiniteVector(Vector3.new(0 / 0, 0, 0)), "nan")
			expectTrue(not DigLogic.isFiniteVector(Vector3.new(math.huge, 0, 0)), "inf")
			expectTrue(DigLogic.isFiniteVector(Vector3.new(1, 2, 3)), "normal")
		end,
	},
}

function DigLogicTests.run(): (number, number)
	local passed, failed = 0, 0
	for _, case in cases do
		local ok, err = pcall(case.fn)
		if ok then
			passed += 1
		else
			failed += 1
			warn("[DigTests] FAIL " .. case.name .. " -> " .. tostring(err))
		end
	end
	if failed == 0 then
		print(string.format("[DigTests] all %d tests passed", passed))
	else
		warn(string.format("[DigTests] %d passed, %d FAILED", passed, failed))
	end
	return passed, failed
end

return DigLogicTests
