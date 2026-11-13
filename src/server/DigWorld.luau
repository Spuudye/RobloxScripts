--!strict
--[[
	DigWorld - owns the terrain pit and all buried loot.

	Buried loot exists only as data on the server (no Instance), so exploiters
	can't scan Workspace for it. An item becomes a Part only when a dig
	uncovers it and the finder's backpack is full.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DigShared")
local DigConfig = require(Shared:WaitForChild("DigConfig"))
local DigLogic = require(Shared:WaitForChild("DigLogic"))
local LootVisuals = require(Shared:WaitForChild("LootVisuals"))

type Bounds = DigLogic.Bounds
type LootDef = DigConfig.LootDef

export type BuriedLoot = {
	Id: number,
	Def: LootDef,
	Position: Vector3,
	LayerIndex: number,
}

local VOXEL = DigConfig.VoxelSize
local CHUNK = 64

local DigWorld = {}

local terrain = Workspace.Terrain
local rng = Random.new()
local bounds: Bounds
local buried: { [number]: BuriedLoot } = {}
local layerCounts: { number } = {}
local nextLootId = 0

local exposedFolder = Instance.new("Folder")
exposedFolder.Name = "ExposedLoot"
exposedFolder.Parent = Workspace

local function snapDown(n: number): number
	return math.floor(n / VOXEL) * VOXEL
end

local function snapUp(n: number): number
	return math.ceil(n / VOXEL) * VOXEL
end

local function resolveBounds(): Bounds
	local area = DigConfig.Area
	local center = area.Center
	local sizeX, sizeZ = area.SizeX, area.SizeZ
	local surfaceY = center.Y

	local zone = Workspace:FindFirstChild("DigZone")
	if zone and zone:IsA("BasePart") then
		center = zone.Position
		sizeX, sizeZ = zone.Size.X, zone.Size.Z
		surfaceY = zone.Position.Y + zone.Size.Y / 2
		zone.Transparency = 1
		zone.CanCollide = false
		zone.CanQuery = false
		zone.CanTouch = false
		zone.Anchored = true
	end

	local minX = snapDown(center.X - sizeX / 2)
	local minZ = snapDown(center.Z - sizeZ / 2)
	local snappedSurface = snapDown(surfaceY)
	return {
		MinX = minX,
		MaxX = minX + snapUp(sizeX),
		MinZ = minZ,
		MaxZ = minZ + snapUp(sizeZ),
		SurfaceY = snappedSurface,
		BottomY = snappedSurface - area.Depth,
	}
end

-- FillBlock in 64-stud columns so huge regions never hit terrain limits.
local function fillBox(minCorner: Vector3, maxCorner: Vector3, material: Enum.Material)
	local x = minCorner.X
	while x < maxCorner.X do
		local x2 = math.min(x + CHUNK, maxCorner.X)
		local z = minCorner.Z
		while z < maxCorner.Z do
			local z2 = math.min(z + CHUNK, maxCorner.Z)
			local lo = Vector3.new(x, minCorner.Y, z)
			local hi = Vector3.new(x2, maxCorner.Y, z2)
			terrain:FillBlock(CFrame.new((lo + hi) / 2), hi - lo, material)
			z = z2
		end
		x = x2
		task.wait()
	end
end

function DigWorld.getBounds(): Bounds
	return bounds
end

function DigWorld.generateTerrain()
	local area = DigConfig.Area
	local border = snapUp(area.Border)
	local minX, maxX = bounds.MinX - border, bounds.MaxX + border
	local minZ, maxZ = bounds.MinZ - border, bounds.MaxZ + border
	local surface = bounds.SurfaceY

	for _, layer in DigConfig.Layers do
		pcall(function()
			terrain:SetMaterialColor(layer.Material, layer.Color)
		end)
	end
	pcall(function()
		terrain:SetMaterialColor(Enum.Material.Grass, DigConfig.GrassColor)
		terrain:SetMaterialColor(DigConfig.BedrockMaterial, DigConfig.BedrockColor)
	end)

	fillBox(
		Vector3.new(minX, surface, minZ),
		Vector3.new(maxX, surface + snapUp(area.ClearHeight), maxZ),
		Enum.Material.Air
	)
	for index, layer in DigConfig.Layers do
		local top = surface - layer.Top
		if index == 1 then
			fillBox(
				Vector3.new(minX, top - DigConfig.GrassDepth, minZ),
				Vector3.new(maxX, top, maxZ),
				Enum.Material.Grass
			)
			top -= DigConfig.GrassDepth
		end
		fillBox(Vector3.new(minX, surface - layer.Bottom, minZ), Vector3.new(maxX, top, maxZ), layer.Material)
	end
	fillBox(
		Vector3.new(minX, bounds.BottomY - snapUp(area.BedrockThickness), minZ),
		Vector3.new(maxX, bounds.BottomY, maxZ),
		DigConfig.BedrockMaterial
	)
end

-- True if any voxel within `radius` of the point has terrain in it.
function DigWorld.isSolidNear(position: Vector3, radius: number): boolean
	local half = Vector3.one * radius
	local region = Region3.new(position - half, position + half):ExpandToGrid(VOXEL)
	local ok, materials, occupancies = pcall(function()
		return terrain:ReadVoxels(region, VOXEL)
	end)
	if not ok then
		return false
	end
	local size = materials.Size
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				if materials[x][y][z] ~= Enum.Material.Air and occupancies[x][y][z] > 0.1 then
					return true
				end
			end
		end
	end
	return false
end

local function isFullySolid(position: Vector3): boolean
	local region = Region3.new(position - Vector3.one * 2, position + Vector3.one * 2):ExpandToGrid(VOXEL)
	local ok, materials, occupancies = pcall(function()
		return terrain:ReadVoxels(region, VOXEL)
	end)
	if not ok then
		return false
	end
	local size = materials.Size
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				if materials[x][y][z] == Enum.Material.Air or occupancies[x][y][z] < 0.9 then
					return false
				end
			end
		end
	end
	return true
end

local function spawnLoot(layerIndex: number): boolean
	local layer = DigConfig.Layers[layerIndex]
	local margin = VOXEL
	for _ = 1, 10 do
		local depth = rng:NextNumber(layer.Top + margin, layer.Bottom - margin)
		local position = Vector3.new(
			rng:NextNumber(bounds.MinX + margin, bounds.MaxX - margin),
			bounds.SurfaceY - depth,
			rng:NextNumber(bounds.MinZ + margin, bounds.MaxZ - margin)
		)
		if isFullySolid(position) then
			nextLootId += 1
			buried[nextLootId] = {
				Id = nextLootId,
				Def = DigLogic.pickLoot(layerIndex, rng:NextNumber()),
				Position = position,
				LayerIndex = layerIndex,
			}
			layerCounts[layerIndex] += 1
			return true
		end
	end
	return false
end

function DigWorld.restockLoot()
	for index, layer in DigConfig.Layers do
		local missing = layer.LootCount - layerCounts[index]
		for _ = 1, missing do
			if not spawnLoot(index) then
				break -- layer is mostly dug out; try again next restock
			end
		end
	end
end

-- Removes and returns every buried item the dig ball uncovered.
function DigWorld.collectInSphere(center: Vector3, radius: number): { BuriedLoot }
	local found = {}
	local reach = radius + DigConfig.LootPickupPadding
	for id, loot in buried do
		if (loot.Position - center).Magnitude <= reach then
			buried[id] = nil
			layerCounts[loot.LayerIndex] -= 1
			table.insert(found, loot)
		end
	end
	return found
end

function DigWorld.nearestLoot(position: Vector3, range: number): BuriedLoot?
	local best: BuriedLoot? = nil
	local bestDistance = range
	for _, loot in buried do
		local distance = (loot.Position - position).Magnitude
		if distance < bestDistance then
			best = loot
			bestDistance = distance
		end
	end
	return best
end

-- Leave an uncovered item in the hole with a prompt (finder's pack was full).
function DigWorld.exposeLoot(loot: BuriedLoot, onPickup: (Player, LootDef, BasePart) -> ())
	local part = LootVisuals.build(loot.Def)
	part.CFrame = CFrame.new(loot.Position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = loot.Def.Name
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		if part.Parent then
			onPickup(player, loot.Def, part)
		end
	end)

	part.Parent = exposedFolder
	task.delay(DigConfig.ExposedLootLifetime, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

function DigWorld.reset()
	exposedFolder:ClearAllChildren()
	table.clear(buried)
	for index in DigConfig.Layers do
		layerCounts[index] = 0
	end
	DigWorld.generateTerrain()
	DigWorld.restockLoot()
end

function DigWorld.init()
	bounds = resolveBounds()
	for index in DigConfig.Layers do
		layerCounts[index] = 0
	end
end

return DigWorld
