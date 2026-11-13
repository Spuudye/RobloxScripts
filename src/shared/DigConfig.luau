--!strict
--[[
	DigConfig - every tunable number for the digging game lives here.

	Lives in ReplicatedStorage.DigShared so the client can read names/prices
	for UI. The server is still the only thing that *uses* these numbers to
	decide outcomes.
]]

export type LayerDef = {
	Name: string,
	Top: number, -- depth (studs below surface) where the layer starts
	Bottom: number, -- depth where it ends
	Material: Enum.Material,
	Color: Color3,
	Hardness: number, -- multiplies stamina cost, shrinks dig radius
	MinTier: number, -- shovel tier needed to dig it
	LootCount: number, -- how many buried items this layer keeps stocked
}

export type ShovelDef = {
	Name: string,
	Price: number,
	Tier: number,
	Radius: number,
	Cooldown: number,
	Stamina: number,
	Reach: number,
	BladeColor: Color3,
	BladeMaterial: Enum.Material,
}

export type BackpackDef = {
	Name: string,
	Price: number,
	Capacity: number,
}

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type LootDef = {
	Id: string,
	Name: string,
	Value: number,
	Weight: number,
	Rarity: Rarity,
	Shape: "Block" | "Ball" | "Cylinder" | "Wedge",
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
}

local DigConfig = {}

-- Grid size of Roblox terrain voxels. Don't change.
DigConfig.VoxelSize = 4

-- Where the dig site goes. If Workspace has a BasePart called "DigZone",
-- its top face becomes the surface and its X/Z footprint becomes the
-- diggable area (the part is hidden). Otherwise these defaults are used.
DigConfig.Area = {
	Center = Vector3.new(0, 0, 0), -- Y is the surface height
	SizeX = 192,
	SizeZ = 192,
	Depth = 160,
	Border = 24, -- undiggable ground ring around the pit (sell pad sits here)
	BedrockThickness = 8,
	ClearHeight = 60, -- terrain above the surface is cleared this high
}

DigConfig.GrassDepth = 4

-- Ordered top to bottom; Top/Bottom must be multiples of VoxelSize and
-- the last Bottom must equal Area.Depth.
DigConfig.Layers = {
	{
		Name = "Topsoil",
		Top = 0,
		Bottom = 24,
		Material = Enum.Material.Ground,
		Color = Color3.fromRGB(214, 160, 98),
		Hardness = 1,
		MinTier = 1,
		LootCount = 45,
	},
	{
		Name = "Clay",
		Top = 24,
		Bottom = 56,
		Material = Enum.Material.Sandstone,
		Color = Color3.fromRGB(196, 120, 78),
		Hardness = 1.4,
		MinTier = 1,
		LootCount = 40,
	},
	{
		Name = "Stone",
		Top = 56,
		Bottom = 96,
		Material = Enum.Material.Rock,
		Color = Color3.fromRGB(128, 124, 120),
		Hardness = 2,
		MinTier = 2,
		LootCount = 35,
	},
	{
		Name = "Deep Slate",
		Top = 96,
		Bottom = 136,
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(74, 78, 92),
		Hardness = 2.8,
		MinTier = 3,
		LootCount = 28,
	},
	{
		Name = "Magma Core",
		Top = 136,
		Bottom = 160,
		Material = Enum.Material.CrackedLava,
		Color = Color3.fromRGB(255, 96, 32),
		Hardness = 3.6,
		MinTier = 4,
		LootCount = 20,
	},
} :: { LayerDef }

DigConfig.GrassColor = Color3.fromRGB(110, 200, 60)
DigConfig.BedrockMaterial = Enum.Material.Basalt
DigConfig.BedrockColor = Color3.fromRGB(30, 28, 34)

DigConfig.Shovels = {
	{
		Name = "Rusty Shovel",
		Price = 0,
		Tier = 1,
		Radius = 4.5,
		Cooldown = 0.35,
		Stamina = 4,
		Reach = 16,
		BladeColor = Color3.fromRGB(150, 82, 40),
		BladeMaterial = Enum.Material.CorrodedMetal,
	},
	{
		Name = "Iron Shovel",
		Price = 150,
		Tier = 2,
		Radius = 5.5,
		Cooldown = 0.3,
		Stamina = 3.5,
		Reach = 17,
		BladeColor = Color3.fromRGB(160, 165, 172),
		BladeMaterial = Enum.Material.Metal,
	},
	{
		Name = "Steel Shovel",
		Price = 800,
		Tier = 3,
		Radius = 6.5,
		Cooldown = 0.26,
		Stamina = 3,
		Reach = 18,
		BladeColor = Color3.fromRGB(205, 215, 230),
		BladeMaterial = Enum.Material.DiamondPlate,
	},
	{
		Name = "Diamond Shovel",
		Price = 3500,
		Tier = 4,
		Radius = 8,
		Cooldown = 0.22,
		Stamina = 2.5,
		Reach = 20,
		BladeColor = Color3.fromRGB(90, 220, 255),
		BladeMaterial = Enum.Material.Glass,
	},
	{
		Name = "Mythic Drill",
		Price = 15000,
		Tier = 5,
		Radius = 10,
		Cooldown = 0.18,
		Stamina = 2,
		Reach = 22,
		BladeColor = Color3.fromRGB(190, 90, 255),
		BladeMaterial = Enum.Material.Neon,
	},
} :: { ShovelDef }

DigConfig.Backpacks = {
	{ Name = "Pockets", Price = 0, Capacity = 10 },
	{ Name = "Satchel", Price = 200, Capacity = 20 },
	{ Name = "Backpack", Price = 1000, Capacity = 35 },
	{ Name = "Hiking Pack", Price = 4000, Capacity = 60 },
	{ Name = "Cargo Pack", Price = 12000, Capacity = 100 },
} :: { BackpackDef }

DigConfig.Stamina = {
	Max = 100,
	RegenPerSecond = 14,
	RegenDelay = 0.6, -- seconds after a dig before regen starts
}

-- Server tolerances (latency slack on top of the shovel's Reach).
DigConfig.ReachTolerance = 4
DigConfig.CooldownTolerance = 0.85 -- accept digs at 85% of the cooldown (ping jitter)
DigConfig.LootPickupPadding = 2 -- loot this far outside the dig ball is still unearthed

-- Loot detector (the blue diamond marker).
DigConfig.DetectorRange = 70
DigConfig.DetectorInterval = 0.5

DigConfig.ExposedLootLifetime = 300
DigConfig.SurfaceCooldown = 5
DigConfig.ResetIntervalMinutes = 30 -- 0 disables the automatic dig site reset
DigConfig.AutosaveSeconds = 120
DigConfig.DataStoreName = "DigGame_v1"
DigConfig.RunSelfTestsInStudio = true

DigConfig.RarityColors = {
	Common = Color3.fromRGB(235, 235, 235),
	Uncommon = Color3.fromRGB(110, 230, 90),
	Rare = Color3.fromRGB(70, 160, 255),
	Epic = Color3.fromRGB(190, 90, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
} :: { [Rarity]: Color3 }

-- Loot per layer index (same order as Layers). Weight is relative chance.
DigConfig.Loot = {
	{
		{
			Id = "rusty_can",
			Name = "Rusty Can",
			Value = 3,
			Weight = 40,
			Rarity = "Common",
			Shape = "Cylinder",
			Size = Vector3.new(1, 0.8, 0.8),
			Color = Color3.fromRGB(140, 80, 50),
			Material = Enum.Material.CorrodedMetal,
		},
		{
			Id = "old_bottle",
			Name = "Old Bottle",
			Value = 5,
			Weight = 30,
			Rarity = "Common",
			Shape = "Cylinder",
			Size = Vector3.new(1.4, 0.6, 0.6),
			Color = Color3.fromRGB(80, 160, 90),
			Material = Enum.Material.Glass,
		},
		{
			Id = "bone",
			Name = "Bone",
			Value = 8,
			Weight = 20,
			Rarity = "Uncommon",
			Shape = "Block",
			Size = Vector3.new(1.8, 0.4, 0.4),
			Color = Color3.fromRGB(240, 232, 210),
			Material = Enum.Material.SmoothPlastic,
		},
		{
			Id = "old_coin",
			Name = "Old Coin",
			Value = 15,
			Weight = 10,
			Rarity = "Rare",
			Shape = "Cylinder",
			Size = Vector3.new(0.2, 1, 1),
			Color = Color3.fromRGB(200, 150, 60),
			Material = Enum.Material.Metal,
		},
	},
	{
		{
			Id = "clay_pot",
			Name = "Clay Pot",
			Value = 20,
			Weight = 40,
			Rarity = "Common",
			Shape = "Ball",
			Size = Vector3.new(1.4, 1.4, 1.4),
			Color = Color3.fromRGB(180, 90, 50),
			Material = Enum.Material.Slate,
		},
		{
			Id = "fossil",
			Name = "Fossil",
			Value = 35,
			Weight = 30,
			Rarity = "Uncommon",
			Shape = "Block",
			Size = Vector3.new(1.6, 0.5, 1.2),
			Color = Color3.fromRGB(200, 190, 160),
			Material = Enum.Material.Limestone,
		},
		{
			Id = "silver_coin",
			Name = "Silver Coin",
			Value = 45,
			Weight = 20,
			Rarity = "Rare",
			Shape = "Cylinder",
			Size = Vector3.new(0.2, 1, 1),
			Color = Color3.fromRGB(210, 215, 225),
			Material = Enum.Material.Metal,
		},
		{
			Id = "arrowhead",
			Name = "Arrowhead",
			Value = 70,
			Weight = 10,
			Rarity = "Epic",
			Shape = "Wedge",
			Size = Vector3.new(0.3, 1, 1.4),
			Color = Color3.fromRGB(60, 60, 70),
			Material = Enum.Material.Slate,
		},
	},
	{
		{
			Id = "iron_ore",
			Name = "Iron Ore",
			Value = 60,
			Weight = 40,
			Rarity = "Common",
			Shape = "Block",
			Size = Vector3.new(1.4, 1.2, 1.3),
			Color = Color3.fromRGB(150, 110, 90),
			Material = Enum.Material.Rock,
		},
		{
			Id = "gold_nugget",
			Name = "Gold Nugget",
			Value = 120,
			Weight = 30,
			Rarity = "Uncommon",
			Shape = "Ball",
			Size = Vector3.new(1, 1, 1),
			Color = Color3.fromRGB(255, 200, 40),
			Material = Enum.Material.Foil,
		},
		{
			Id = "ancient_mask",
			Name = "Ancient Mask",
			Value = 200,
			Weight = 20,
			Rarity = "Rare",
			Shape = "Block",
			Size = Vector3.new(1.4, 1.8, 0.4),
			Color = Color3.fromRGB(70, 150, 120),
			Material = Enum.Material.Marble,
		},
		{
			Id = "emerald",
			Name = "Emerald",
			Value = 320,
			Weight = 10,
			Rarity = "Epic",
			Shape = "Block",
			Size = Vector3.new(0.8, 1.2, 0.8),
			Color = Color3.fromRGB(40, 220, 110),
			Material = Enum.Material.Glass,
		},
	},
	{
		{
			Id = "ruby",
			Name = "Ruby",
			Value = 350,
			Weight = 40,
			Rarity = "Uncommon",
			Shape = "Block",
			Size = Vector3.new(0.9, 1.2, 0.9),
			Color = Color3.fromRGB(230, 30, 60),
			Material = Enum.Material.Glass,
		},
		{
			Id = "sapphire",
			Name = "Sapphire",
			Value = 450,
			Weight = 30,
			Rarity = "Rare",
			Shape = "Block",
			Size = Vector3.new(0.9, 1.2, 0.9),
			Color = Color3.fromRGB(40, 90, 255),
			Material = Enum.Material.Glass,
		},
		{
			Id = "crown",
			Name = "Lost Crown",
			Value = 900,
			Weight = 20,
			Rarity = "Epic",
			Shape = "Cylinder",
			Size = Vector3.new(0.8, 1.6, 1.6),
			Color = Color3.fromRGB(255, 205, 60),
			Material = Enum.Material.Foil,
		},
		{
			Id = "skull_relic",
			Name = "Crystal Skull",
			Value = 1500,
			Weight = 10,
			Rarity = "Legendary",
			Shape = "Ball",
			Size = Vector3.new(1.4, 1.6, 1.4),
			Color = Color3.fromRGB(190, 240, 255),
			Material = Enum.Material.Glass,
		},
	},
	{
		{
			Id = "magma_shard",
			Name = "Magma Shard",
			Value = 1200,
			Weight = 40,
			Rarity = "Rare",
			Shape = "Wedge",
			Size = Vector3.new(0.8, 1.6, 1.2),
			Color = Color3.fromRGB(255, 110, 30),
			Material = Enum.Material.Neon,
		},
		{
			Id = "dragon_egg",
			Name = "Dragon Egg",
			Value = 2500,
			Weight = 30,
			Rarity = "Epic",
			Shape = "Ball",
			Size = Vector3.new(1.4, 1.9, 1.4),
			Color = Color3.fromRGB(120, 30, 40),
			Material = Enum.Material.Marble,
		},
		{
			Id = "meteorite",
			Name = "Meteorite",
			Value = 4000,
			Weight = 20,
			Rarity = "Legendary",
			Shape = "Ball",
			Size = Vector3.new(1.6, 1.6, 1.6),
			Color = Color3.fromRGB(60, 50, 70),
			Material = Enum.Material.Basalt,
		},
		{
			Id = "golden_idol",
			Name = "Golden Idol",
			Value = 7500,
			Weight = 10,
			Rarity = "Legendary",
			Shape = "Block",
			Size = Vector3.new(1, 2, 1),
			Color = Color3.fromRGB(255, 215, 80),
			Material = Enum.Material.Foil,
		},
	},
} :: { { LootDef } }

-- Flat lookup: item id -> definition.
DigConfig.LootById = {} :: { [string]: LootDef }
for _, layerLoot in DigConfig.Loot do
	for _, def in layerLoot do
		DigConfig.LootById[def.Id] = def
	end
end

return DigConfig
