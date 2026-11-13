--!strict
--[[
	Dig client - input, HUD, effects. Computes nothing authoritative: it
	aims, asks the server to dig, and draws whatever the server says.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DigShared")
local DigConfig = require(Shared:WaitForChild("DigConfig"))
local DigLogic = require(Shared:WaitForChild("DigLogic"))
local LootVisuals = require(Shared:WaitForChild("LootVisuals"))

local remotes = ReplicatedStorage:WaitForChild("DigRemotes")
local digEvent = remotes:WaitForChild("Dig") :: RemoteEvent
local surfaceEvent = remotes:WaitForChild("Surface") :: RemoteEvent
local buyFunction = remotes:WaitForChild("BuyUpgrade") :: RemoteFunction
local fxEvent = remotes:WaitForChild("DigFx") :: RemoteEvent
local notifyEvent = remotes:WaitForChild("Notify") :: RemoteEvent
local hintEvent = remotes:WaitForChild("LootHint") :: RemoteEvent

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local terrain = Workspace.Terrain

local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local CASH_GREEN = Color3.fromRGB(80, 255, 110)

local function bounds(): DigLogic.Bounds
	return {
		MinX = remotes:GetAttribute("MinX") or 0,
		MaxX = remotes:GetAttribute("MaxX") or 0,
		MinZ = remotes:GetAttribute("MinZ") or 0,
		MaxZ = remotes:GetAttribute("MaxZ") or 0,
		SurfaceY = remotes:GetAttribute("SurfaceY") or 0,
		BottomY = remotes:GetAttribute("BottomY") or 0,
	}
end

local function attr(name: string, default: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local fxFolder = Instance.new("Folder")
fxFolder.Name = "DigFxLocal"
fxFolder.Parent = Workspace

--------------------------------------------------------------------------
-- UI construction helpers
--------------------------------------------------------------------------

local function stroke(parent: GuiObject, thickness: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Color3.fromRGB(25, 25, 30)
	s.ApplyStrokeMode = if parent:IsA("TextLabel") or parent:IsA("TextButton")
		then Enum.ApplyStrokeMode.Contextual
		else Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function corner(parent: GuiObject, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Parent = parent
	return l
end

--------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DigHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Each HUD group gets its own UIScale (a UIScale on the ScreenGui would
-- also scale the mouse-following dig ring's position).
local uiScales: { UIScale } = {}
local function addScale(parent: GuiObject)
	local s = Instance.new("UIScale")
	s.Parent = parent
	table.insert(uiScales, s)
end

local top = Instance.new("Frame")
top.Name = "Top"
top.AnchorPoint = Vector2.new(0.5, 0)
top.Position = UDim2.new(0.5, 0, 0, 14)
top.Size = UDim2.fromOffset(600, 104)
top.BackgroundTransparency = 1
top.Parent = gui
addScale(top)

local cashLabel = label(top, "Cash", UDim2.fromOffset(320, 58), UDim2.new(0.5, 0, 0, 0), "$0")
cashLabel.AnchorPoint = Vector2.new(0.5, 0)
cashLabel.TextColor3 = CASH_GREEN
stroke(cashLabel, 3)

local hintLabel = label(top, "Hint", UDim2.fromOffset(600, 40), UDim2.new(0.5, 0, 0, 60), "Find loot")
hintLabel.AnchorPoint = Vector2.new(0.5, 0)
stroke(hintLabel, 2.5)
local hintScale = Instance.new("UIScale")
hintScale.Parent = hintLabel

-- Bottom bar: backpack | stamina | depth
local bar = Instance.new("Frame")
bar.Name = "BottomBar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -18)
bar.Size = UDim2.fromOffset(560, 40)
bar.BackgroundTransparency = 1
bar.Parent = gui
addScale(bar)

local packLabel = label(bar, "Backpack", UDim2.fromOffset(130, 40), UDim2.fromOffset(0, 0), "🎒 0/10")
packLabel.TextXAlignment = Enum.TextXAlignment.Left
stroke(packLabel, 2.5)

local staminaBack = Instance.new("Frame")
staminaBack.Name = "Stamina"
staminaBack.Position = UDim2.fromOffset(170, 11)
staminaBack.Size = UDim2.fromOffset(240, 18)
staminaBack.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
staminaBack.BackgroundTransparency = 0.25
staminaBack.Parent = bar
corner(staminaBack, UDim.new(0, 6))
stroke(staminaBack, 2)

local staminaFill = Instance.new("Frame")
staminaFill.Name = "Fill"
staminaFill.Size = UDim2.fromScale(1, 1)
staminaFill.BackgroundColor3 = Color3.fromRGB(200, 240, 30)
staminaFill.Parent = staminaBack
corner(staminaFill, UDim.new(0, 6))

local boltLabel = label(bar, "Bolt", UDim2.fromOffset(28, 34), UDim2.fromOffset(140, 3), "⚡")
boltLabel.TextColor3 = Color3.fromRGB(230, 240, 60)

local depthLabel = label(bar, "Depth", UDim2.fromOffset(120, 40), UDim2.fromOffset(440, 0), "0m")
depthLabel.TextXAlignment = Enum.TextXAlignment.Right
stroke(depthLabel, 2.5)

local layerLabel = label(bar, "Layer", UDim2.fromOffset(160, 20), UDim2.fromOffset(400, -20), "")
layerLabel.TextXAlignment = Enum.TextXAlignment.Right
layerLabel.TextTransparency = 0.15
stroke(layerLabel, 2)

-- Right side: upgrades + surface button
local panel = Instance.new("Frame")
panel.Name = "Upgrades"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -16, 0.5, 0)
panel.Size = UDim2.fromOffset(210, 210)
panel.BackgroundTransparency = 1
panel.Parent = gui
addScale(panel)

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 10)
list.HorizontalAlignment = Enum.HorizontalAlignment.Right
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = panel

local function makeButton(name: string, order: number, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(210, 60)
	button.BackgroundColor3 = color
	button.AutoButtonColor = true
	button.FontFace = FONT
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = panel
	corner(button, UDim.new(0, 12))
	stroke(button, 2.5)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = button
	return button
end

local shovelButton = makeButton("ShovelUpgrade", 1, Color3.fromRGB(240, 150, 40))
local packButton = makeButton("BackpackUpgrade", 2, Color3.fromRGB(70, 150, 255))
local surfaceButton = makeButton("Surface", 3, Color3.fromRGB(80, 200, 110))
surfaceButton.Text = "⬆ Surface"

-- Dig cursor ring
local ring = Instance.new("Frame")
ring.Name = "DigRing"
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Size = UDim2.fromOffset(110, 110)
ring.BackgroundTransparency = 1
ring.Visible = false
ring.Parent = gui
corner(ring, UDim.new(1, 0))
local ringStroke = Instance.new("UIStroke")
ringStroke.Thickness = 2.5
ringStroke.Transparency = 0.25
ringStroke.Color = Color3.new(1, 1, 1)
ringStroke.Parent = ring

gui.Parent = player:WaitForChild("PlayerGui")

local function updateScale()
	local viewport = camera.ViewportSize
	local scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.55, 1.25)
	for _, s in uiScales do
		s.Scale = scale
	end
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()

--------------------------------------------------------------------------
-- HUD state from attributes
--------------------------------------------------------------------------

local toastUntil = 0

local function defaultHint(): string
	if attr("BackpackCount", 0) >= attr("BackpackMax", 10) then
		return "Backpack full! Sell at the green pad"
	end
	return "Find loot"
end

local function refreshUpgradeButton(
	button: TextButton,
	levelAttr: string,
	defs: { { Name: string, Price: number } },
	icon: string
)
	local nextDef = defs[attr(levelAttr, 1) + 1]
	if not nextDef then
		button.Text = icon .. " MAXED"
		button.BackgroundTransparency = 0.4
		return
	end
	button.Text = string.format("%s %s\n%s", icon, nextDef.Name, DigLogic.formatCash(nextDef.Price))
	button.BackgroundTransparency = if attr("Cash", 0) >= nextDef.Price then 0 else 0.45
end

local function refreshHud()
	cashLabel.Text = DigLogic.formatCash(attr("Cash", 0))
	packLabel.Text = string.format("🎒 %d/%d", attr("BackpackCount", 0), attr("BackpackMax", 10))
	packLabel.TextColor3 = if attr("BackpackCount", 0) >= attr("BackpackMax", 10)
		then Color3.fromRGB(255, 110, 90)
		else Color3.new(1, 1, 1)
	refreshUpgradeButton(shovelButton, "ShovelLevel", DigConfig.Shovels, "⛏")
	refreshUpgradeButton(packButton, "BackpackLevel", DigConfig.Backpacks, "🎒")
	if os.clock() > toastUntil then
		hintLabel.Text = defaultHint()
		hintLabel.TextColor3 = Color3.new(1, 1, 1)
	end
end

local function refreshStamina()
	local ratio = math.clamp(attr("Stamina", 100) / math.max(1, attr("MaxStamina", 100)), 0, 1)
	TweenService:Create(staminaFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(ratio, 1) }):Play()
	staminaFill.BackgroundColor3 = if ratio < 0.25 then Color3.fromRGB(255, 90, 60) else Color3.fromRGB(200, 240, 30)
end

player.AttributeChanged:Connect(function(name)
	if name == "Stamina" or name == "MaxStamina" then
		refreshStamina()
	else
		refreshHud()
	end
end)
refreshHud()
refreshStamina()

local function showToast(text: string, color: Color3?)
	hintLabel.Text = text
	hintLabel.TextColor3 = color or Color3.new(1, 1, 1)
	toastUntil = os.clock() + 2.5
	hintScale.Scale = 1.25
	TweenService:Create(hintScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(2.6, function()
		if os.clock() > toastUntil then
			refreshHud()
		end
	end)
end

local function bump(object: GuiObject)
	local scale = object:FindFirstChild("BumpScale") or Instance.new("UIScale")
	assert(scale:IsA("UIScale"))
	scale.Name = "BumpScale"
	scale.Parent = object
	scale.Scale = 1.2
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

shovelButton.Activated:Connect(function()
	local ok, message = buyFunction:InvokeServer("Shovel")
	showToast(message, if ok then CASH_GREEN else Color3.fromRGB(255, 110, 90))
	if ok then
		bump(shovelButton)
	end
end)
packButton.Activated:Connect(function()
	local ok, message = buyFunction:InvokeServer("Backpack")
	showToast(message, if ok then CASH_GREEN else Color3.fromRGB(255, 110, 90))
	if ok then
		bump(packButton)
	end
end)
surfaceButton.Activated:Connect(function()
	surfaceEvent:FireServer()
end)

--------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------

local rng = Random.new()

local function dirtBurst(center: Vector3, radius: number, color: Color3)
	if (camera.CFrame.Position - center).Magnitude > 220 then
		return
	end
	for _ = 1, math.clamp(math.floor(radius * 1.5), 5, 14) do
		local chunk = Instance.new("Part")
		local s = rng:NextNumber(0.4, 0.9)
		chunk.Size = Vector3.new(s, s, s)
		chunk.Color = color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.25))
		chunk.Material = Enum.Material.Ground
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CastShadow = false
		chunk.CFrame = CFrame.new(center + rng:NextUnitVector() * radius * 0.4)
			* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		local direction = (rng:NextUnitVector() + Vector3.new(0, 1.6, 0)).Unit
		chunk.AssemblyLinearVelocity = direction * rng:NextNumber(14, 26)
		chunk.AssemblyAngularVelocity = rng:NextUnitVector() * 10
		chunk.Parent = fxFolder
		TweenService:Create(chunk, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.5), {
			Size = Vector3.one * 0.05,
		}):Play()
		task.delay(1.05, function()
			chunk:Destroy()
		end)
	end

	local dust = Instance.new("Part")
	dust.Anchored = true
	dust.Transparency = 1
	dust.CanCollide = false
	dust.CanQuery = false
	dust.CanTouch = false
	dust.Size = Vector3.one
	dust.Position = center
	local attachment = Instance.new("Attachment")
	attachment.Parent = dust
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.Transparency = NumberSequence.new(0.35, 1)
	emitter.Size = NumberSequence.new(radius * 0.5, radius * 1.1)
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(3, 7)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.Enabled = false
	emitter.Parent = attachment
	dust.Parent = fxFolder
	emitter:Emit(10)
	task.delay(1.5, function()
		dust:Destroy()
	end)
end

fxEvent.OnClientEvent:Connect(function(center: Vector3, radius: number, color: Color3)
	if typeof(center) == "Vector3" and type(radius) == "number" and typeof(color) == "Color3" then
		dirtBurst(center, radius, color)
	end
end)

-- Loot pops out of the ground, spins, then flies into the player.
local function lootPop(lootId: string, from: Vector3)
	local def = DigConfig.LootById[lootId]
	if not def then
		return
	end
	local part = LootVisuals.build(def)
	part.CanQuery = false
	part.CFrame = CFrame.new(from)
	part.Parent = fxFolder

	local up = TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(from + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.pi, 0),
	})
	up:Play()
	up.Completed:Wait()
	task.wait(0.25)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local fly = TweenService:Create(part, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = root.CFrame,
			Size = part.Size * 0.2,
		})
		fly:Play()
		fly.Completed:Wait()
	end
	part:Destroy()
	bump(packLabel)
end

notifyEvent.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" or type(payload.Text) ~= "string" then
		return
	end
	local color = if typeof(payload.Color) == "Color3" then payload.Color else nil
	showToast(payload.Text, color)
	if type(payload.LootId) == "string" and typeof(payload.Position) == "Vector3" then
		task.spawn(lootPop, payload.LootId, payload.Position)
		bump(cashLabel)
	end
end)

--------------------------------------------------------------------------
-- Loot detector marker
--------------------------------------------------------------------------

local markerPart = Instance.new("Part")
markerPart.Name = "LootMarker"
markerPart.Anchored = true
markerPart.Transparency = 1
markerPart.CanCollide = false
markerPart.CanQuery = false
markerPart.CanTouch = false
markerPart.Size = Vector3.one * 0.2
markerPart.Parent = fxFolder

local markerGui = Instance.new("BillboardGui")
markerGui.Size = UDim2.fromOffset(90, 90)
markerGui.AlwaysOnTop = true
markerGui.Enabled = false
markerGui.Parent = markerPart

local diamond = Instance.new("Frame")
diamond.AnchorPoint = Vector2.new(0.5, 0.5)
diamond.Position = UDim2.fromScale(0.5, 0.35)
diamond.Size = UDim2.fromOffset(34, 34)
diamond.Rotation = 45
diamond.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
diamond.Parent = markerGui
stroke(diamond, 2, Color3.new(1, 1, 1))
local dot = Instance.new("Frame")
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(6, 6)
dot.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
dot.Parent = diamond

local markerDistance = label(markerGui, "Distance", UDim2.new(1, 0, 0, 24), UDim2.fromScale(0, 0.68), "")
stroke(markerDistance, 2)

local markerTarget: Vector3? = nil

hintEvent.OnClientEvent:Connect(function(position: Vector3?, rarity: string?)
	if typeof(position) == "Vector3" then
		markerTarget = position
		markerPart.Position = position
		markerGui.Enabled = true
		local color = rarity and DigConfig.RarityColors[rarity :: any]
		diamond.BackgroundColor3 = if color and rarity ~= "Common" then color else Color3.fromRGB(0, 170, 255)
	else
		markerTarget = nil
		markerGui.Enabled = false
	end
end)

--------------------------------------------------------------------------
-- Digging input
--------------------------------------------------------------------------

local equippedTool: Tool? = nil
local holding = false
local lastDig = 0
local baseGrips: { [Tool]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function aim(): RaycastResult?
	local character = player.Character
	local exposed = Workspace:FindFirstChild("ExposedLoot")
	local ignore: { Instance } = { fxFolder }
	if character then
		table.insert(ignore, character)
	end
	if exposed then
		table.insert(ignore, exposed)
	end
	rayParams.FilterDescendantsInstances = ignore
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	return Workspace:Raycast(ray.Origin, ray.Direction * 400, rayParams)
end

-- Mirrors the server checks only to colour the ring; the server re-checks.
local function evaluate(result: RaycastResult?): (boolean, string?)
	if not result or result.Instance ~= terrain then
		return false, nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, nil
	end
	local shovel = DigLogic.getShovel(attr("ShovelLevel", 1))
	if (result.Position - root.Position).Magnitude > shovel.Reach then
		return false, "Too far"
	end
	local b = bounds()
	if not DigLogic.isInsideBounds(result.Position, b, 2) then
		return false, nil
	end
	local layer = DigLogic.getLayer(b.SurfaceY - (result.Position - result.Normal).Y)
	if not DigLogic.canDig(shovel, layer) then
		return false, "Need " .. DigLogic.requiredShovelName(layer)
	end
	if attr("Stamina", 100) < DigLogic.staminaCost(shovel, layer) then
		return false, "Too tired"
	end
	return true, nil
end

local function swing(tool: Tool)
	local baseGrip = baseGrips[tool] or tool.Grip
	local down = TweenService:Create(tool, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
		Grip = baseGrip * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(-40), 0, 0),
	})
	down:Play()
	down.Completed:Once(function()
		TweenService:Create(tool, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Grip = baseGrip }):Play()
	end)
end

local function tryDig()
	local tool = equippedTool
	if not tool then
		return
	end
	local shovel = DigLogic.getShovel(attr("ShovelLevel", 1))
	local now = os.clock()
	if now - lastDig < shovel.Cooldown then
		return
	end
	local result = aim()
	local ok = evaluate(result)
	if not ok or not result then
		return
	end
	lastDig = now
	swing(tool)
	digEvent:FireServer(result.Position, result.Normal)
end

local function bindTool(tool: Tool)
	equippedTool = tool
	if baseGrips[tool] then
		return -- already wired up on an earlier equip
	end
	local baseGrip = tool.Grip
	baseGrips[tool] = baseGrip
	tool.Activated:Connect(function()
		holding = true
		tryDig()
	end)
	tool.Deactivated:Connect(function()
		holding = false
	end)
	tool.Unequipped:Connect(function()
		holding = false
		if equippedTool == tool then
			equippedTool = nil
		end
		tool.Grip = baseGrip
	end)
end

local function watchCharacter(character: Model)
	equippedTool = nil
	holding = false
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("DigTool") then
			bindTool(child)
		end
	end)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("DigTool") then
			bindTool(child)
		end
	end
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end

RunService.RenderStepped:Connect(function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	-- Depth meter
	local b = bounds()
	if root and root:IsA("BasePart") then
		local feet = root.Position - Vector3.new(0, 3, 0)
		local depth = b.SurfaceY - feet.Y
		if depth > 0.5 and DigLogic.isInsideBounds(feet, b, 2) then
			depthLabel.Text = string.format("%dm", math.floor(depth))
			layerLabel.Text = DigLogic.getLayer(depth).Name
		else
			depthLabel.Text = "0m"
			layerLabel.Text = ""
		end
	end

	-- Marker distance
	if markerTarget and root and root:IsA("BasePart") then
		markerDistance.Text = string.format("%dm", math.floor((markerTarget - root.Position).Magnitude))
	end

	-- Cursor ring + hold-to-dig
	if equippedTool then
		local mouse = UserInputService:GetMouseLocation()
		ring.Position = UDim2.fromOffset(mouse.X, mouse.Y)
		local result = aim()
		local ok, reason = evaluate(result)
		ring.Visible = result ~= nil and result.Instance == terrain
		ringStroke.Color = if ok then Color3.new(1, 1, 1) else Color3.fromRGB(255, 80, 70)
		if reason and holding and os.clock() > toastUntil then
			hintLabel.Text = reason
			hintLabel.TextColor3 = Color3.fromRGB(255, 110, 90)
		elseif not reason and os.clock() > toastUntil then
			hintLabel.Text = defaultHint()
			hintLabel.TextColor3 = Color3.new(1, 1, 1)
		end
		if holding then
			tryDig()
		end
	else
		ring.Visible = false
	end
end)
