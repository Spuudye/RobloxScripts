--!strict
--[[
	LootVisuals - builds the Part used to show a loot item. Used by the server
	for exposed loot and by the client for the "pop out of the ground" effect,
	so both look identical.
]]

local DigConfig = require(script.Parent.DigConfig)

local LootVisuals = {}

function LootVisuals.build(def: DigConfig.LootDef): BasePart
	local part: BasePart
	if def.Shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		p.Shape = if def.Shape == "Ball"
			then Enum.PartType.Ball
			elseif def.Shape == "Cylinder" then Enum.PartType.Cylinder
			else Enum.PartType.Block
		part = p
	end
	part.Name = def.Name
	part.Size = def.Size
	part.Color = def.Color
	part.Material = def.Material
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = true
	part:SetAttribute("LootId", def.Id)

	local rarityColor = DigConfig.RarityColors[def.Rarity]
	if def.Rarity ~= "Common" then
		local light = Instance.new("PointLight")
		light.Color = rarityColor
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = part
	end

	local sparkle = Instance.new("Attachment")
	sparkle.Name = "FxAttachment"
	sparkle.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkle"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(rarityColor)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = if def.Rarity == "Common" then 2 else 8
	emitter.Parent = sparkle

	return part
end

return LootVisuals
