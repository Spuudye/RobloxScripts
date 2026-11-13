--!strict
--[[
	DigLogic - pure functions (no Instances, no services) shared by server
	and client. Kept pure so DigLogicTests can check them in isolation.
]]

local DigConfig = require(script.Parent.DigConfig)

type LayerDef = DigConfig.LayerDef
type ShovelDef = DigConfig.ShovelDef
type BackpackDef = DigConfig.BackpackDef
type LootDef = DigConfig.LootDef

export type Bounds = {
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	SurfaceY: number,
	BottomY: number,
}

local DigLogic = {}

-- Returns the layer index for a depth below the surface (clamped to the
-- first/last layer so a point slightly above ground counts as topsoil).
function DigLogic.getLayerIndex(depth: number): number
	local layers = DigConfig.Layers
	if depth < layers[1].Bottom then
		return 1
	end
	for index, layer in layers do
		if depth >= layer.Top and depth < layer.Bottom then
			return index
		end
	end
	return #layers
end

function DigLogic.getLayer(depth: number): LayerDef
	return DigConfig.Layers[DigLogic.getLayerIndex(depth)]
end

function DigLogic.canDig(shovel: ShovelDef, layer: LayerDef): boolean
	return shovel.Tier >= layer.MinTier
end

-- Harder layers shrink the hole; never below one voxel so a dig always
-- removes something.
function DigLogic.effectiveRadius(shovel: ShovelDef, layer: LayerDef): number
	return math.max(DigConfig.VoxelSize * 0.75, shovel.Radius / math.sqrt(layer.Hardness))
end

function DigLogic.staminaCost(shovel: ShovelDef, layer: LayerDef): number
	return shovel.Stamina * layer.Hardness
end

-- Name of the cheapest shovel that can dig the layer, for "Too hard" hints.
function DigLogic.requiredShovelName(layer: LayerDef): string
	for _, shovel in DigConfig.Shovels do
		if shovel.Tier >= layer.MinTier then
			return shovel.Name
		end
	end
	return "?"
end

function DigLogic.getShovel(level: number): ShovelDef
	local shovels = DigConfig.Shovels
	return shovels[math.clamp(level, 1, #shovels)]
end

function DigLogic.getBackpack(level: number): BackpackDef
	local packs = DigConfig.Backpacks
	return packs[math.clamp(level, 1, #packs)]
end

-- Weighted roll from a layer's loot table. `roll` is a number in [0, 1).
function DigLogic.pickLoot(layerIndex: number, roll: number): LootDef
	local tableForLayer = DigConfig.Loot[math.clamp(layerIndex, 1, #DigConfig.Loot)]
	local total = 0
	for _, def in tableForLayer do
		total += def.Weight
	end
	local target = roll * total
	local running = 0
	for _, def in tableForLayer do
		running += def.Weight
		if target < running then
			return def
		end
	end
	return tableForLayer[#tableForLayer]
end

function DigLogic.sellValue(itemIds: { string }): number
	local total = 0
	for _, id in itemIds do
		local def = DigConfig.LootById[id]
		if def then
			total += def.Value
		end
	end
	return total
end

-- Keep a dig ball of `radius` fully inside the diggable box so it can
-- never eat the border ring or bedrock.
function DigLogic.clampDigCenter(center: Vector3, radius: number, bounds: Bounds): Vector3
	local function clampAxis(value: number, low: number, high: number): number
		if low > high then
			return (low + high) / 2
		end
		return math.clamp(value, low, high)
	end
	return Vector3.new(
		clampAxis(center.X, bounds.MinX + radius, bounds.MaxX - radius),
		clampAxis(center.Y, bounds.BottomY + radius, bounds.SurfaceY + radius),
		clampAxis(center.Z, bounds.MinZ + radius, bounds.MaxZ - radius)
	)
end

function DigLogic.isInsideBounds(position: Vector3, bounds: Bounds, padding: number): boolean
	return position.X >= bounds.MinX - padding
		and position.X <= bounds.MaxX + padding
		and position.Z >= bounds.MinZ - padding
		and position.Z <= bounds.MaxZ + padding
		and position.Y >= bounds.BottomY - padding
		and position.Y <= bounds.SurfaceY + padding
end

function DigLogic.isFiniteVector(v: Vector3): boolean
	for _, n in { v.X, v.Y, v.Z } do
		if n ~= n or math.abs(n) > 1e6 then
			return false
		end
	end
	return true
end

function DigLogic.formatCash(amount: number): string
	local whole = math.floor(amount)
	local text = tostring(whole)
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

return DigLogic
