--!strict
--[[
	DigService - server-authoritative digging gameplay.

	Remotes (ReplicatedStorage.DigRemotes):
	  Dig          client -> server  (hitPosition: Vector3, hitNormal: Vector3)
	  Surface      client -> server  ()                      teleport out of the pit
	  BuyUpgrade   client -> server  RemoteFunction(kind: "Shovel" | "Backpack") -> (ok, message)
	  DigFx        server -> all     (center: Vector3, radius: number, color: Color3)
	  Notify       server -> client  (payload: NotifyPayload)
	  LootHint     server -> client  (position: Vector3?, rarity: string?)

	Player state the HUD shows is replicated with Player attributes, so a
	late-joining or respawning client always sees the current values.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DigShared")
local DigConfig = require(Shared:WaitForChild("DigConfig"))
local DigLogic = require(Shared:WaitForChild("DigLogic"))
local DigWorld = require(script.Parent.DigWorld)
local PlayerData = require(script.Parent.PlayerData)

type LootDef = DigConfig.LootDef

type State = {
	Stamina: number,
	LastDig: number,
	LastWarn: number,
	LastSell: number,
	LastSurface: number,
	LastBuy: number,
	HintId: number,
}

local DigService = {}

local states: { [Player]: State } = {}
local terrain = Workspace.Terrain

local remotes: Folder
local digEvent: RemoteEvent
local surfaceEvent: RemoteEvent
local buyFunction: RemoteFunction
local fxEvent: RemoteEvent
local notifyEvent: RemoteEvent
local hintEvent: RemoteEvent

local surfacePoint = Vector3.zero

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function makeRemote(className: string, name: string): Instance
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local function notify(player: Player, text: string, color: Color3?)
	notifyEvent:FireClient(player, { Text = text, Color = color })
end

-- Throttled warnings so holding the mouse on rock doesn't spam the HUD.
local function warnPlayer(player: Player, text: string)
	local state = states[player]
	if not state then
		return
	end
	local now = os.clock()
	if now - state.LastWarn < 1.5 then
		return
	end
	state.LastWarn = now
	notify(player, text, Color3.fromRGB(255, 110, 90))
end

local function getAliveRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function syncAttributes(player: Player)
	local profile = PlayerData.get(player)
	local state = states[player]
	if not profile or not state then
		return
	end
	local shovel = DigLogic.getShovel(profile.ShovelLevel)
	local pack = DigLogic.getBackpack(profile.BackpackLevel)
	player:SetAttribute("Cash", profile.Cash)
	player:SetAttribute("ShovelLevel", profile.ShovelLevel)
	player:SetAttribute("ShovelName", shovel.Name)
	player:SetAttribute("BackpackLevel", profile.BackpackLevel)
	player:SetAttribute("BackpackCount", #profile.Backpack)
	player:SetAttribute("BackpackMax", pack.Capacity)
	player:SetAttribute("Stamina", math.floor(state.Stamina))
	player:SetAttribute("MaxStamina", DigConfig.Stamina.Max)
	player:SetAttribute("DataSaving", PlayerData.isSaving(player))

	local leaderstats = player:FindFirstChild("leaderstats")
	local cashValue = leaderstats and leaderstats:FindFirstChild("Cash")
	if cashValue and cashValue:IsA("IntValue") then
		cashValue.Value = profile.Cash
	end
end

--------------------------------------------------------------------------
-- Shovel tool
--------------------------------------------------------------------------

local function weldTo(handle: BasePart, part: BasePart)
	local weld = Instance.new("Weld")
	weld.Part0 = handle
	weld.Part1 = part
	weld.C0 = handle.CFrame:Inverse() * part.CFrame
	weld.Parent = part
end

local function buildShovel(def: DigConfig.ShovelDef): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.ToolTip = "Click the ground to dig"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("DigTool", true)
	-- Hold the rear end of the shaft, blade pointing forward and down.
	tool.Grip = CFrame.new(0, -1.6, 0) * CFrame.Angles(math.rad(25), 0, 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 4.4, 0.35)
	handle.Color = Color3.fromRGB(150, 98, 56)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = tool

	local grip = Instance.new("Part")
	grip.Name = "GripBar"
	grip.Size = Vector3.new(1.1, 0.3, 0.3)
	grip.Color = handle.Color
	grip.Material = Enum.Material.Wood
	grip.CanCollide = false
	grip.Massless = true
	grip.CFrame = CFrame.new(0, -2.25, 0)
	grip.Parent = tool
	weldTo(handle, grip)

	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(1.3, 1.7, 0.15)
	blade.Color = def.BladeColor
	blade.Material = def.BladeMaterial
	blade.CanCollide = false
	blade.Massless = true
	blade.CFrame = CFrame.new(0, 2.9, 0)
	blade.Parent = tool
	weldTo(handle, blade)

	return tool
end

local function giveShovel(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	local wasEquipped = false
	for _, container in { character, backpack } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("DigTool") then
					wasEquipped = wasEquipped or child.Parent == character
					child:Destroy()
				end
			end
		end
	end

	local tool = buildShovel(DigLogic.getShovel(profile.ShovelLevel))
	if wasEquipped and character then
		tool.Parent = character
	elseif backpack then
		tool.Parent = backpack
	end
end

--------------------------------------------------------------------------
-- Loot
--------------------------------------------------------------------------

local function addToBackpack(player: Player, def: LootDef, fromPosition: Vector3): boolean
	local profile = PlayerData.get(player)
	if not profile then
		return false
	end
	if #profile.Backpack >= DigLogic.getBackpack(profile.BackpackLevel).Capacity then
		return false
	end
	table.insert(profile.Backpack, def.Id)
	profile.TotalFound += 1
	notifyEvent:FireClient(player, {
		Text = string.format("+ %s (%s)", def.Name, DigLogic.formatCash(def.Value)),
		Color = DigConfig.RarityColors[def.Rarity],
		LootId = def.Id,
		Position = fromPosition,
	})
	return true
end

local function onExposedPickup(player: Player, def: LootDef, part: BasePart)
	local root = getAliveRoot(player)
	if not root or (root.Position - part.Position).Magnitude > 16 then
		return
	end
	if addToBackpack(player, def, part.Position) then
		part:Destroy()
		syncAttributes(player)
	else
		warnPlayer(player, "Backpack full! Sell your loot at the pad.")
	end
end

--------------------------------------------------------------------------
-- Remote handlers (rate limit -> types -> ranges -> plausibility -> mutate)
--------------------------------------------------------------------------

local function onDig(player: Player, position: unknown, normal: unknown)
	local state = states[player]
	local profile = PlayerData.get(player)
	if not state or not profile then
		return
	end

	local shovel = DigLogic.getShovel(profile.ShovelLevel)
	local now = os.clock()
	if now - state.LastDig < shovel.Cooldown * DigConfig.CooldownTolerance then
		return
	end

	if typeof(position) ~= "Vector3" or typeof(normal) ~= "Vector3" then
		return
	end
	if not DigLogic.isFiniteVector(position) or not DigLogic.isFiniteVector(normal) then
		return
	end

	local root = getAliveRoot(player)
	local character = player.Character
	if not root or not character then
		return
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or not tool:GetAttribute("DigTool") then
		return
	end
	if (position - root.Position).Magnitude > shovel.Reach + DigConfig.ReachTolerance then
		return
	end

	local bounds = DigWorld.getBounds()
	if not DigLogic.isInsideBounds(position, bounds, 2) then
		warnPlayer(player, "You can only dig inside the dig site.")
		return
	end

	local inward = if normal.Magnitude > 0.5 then -normal.Unit else -Vector3.yAxis
	local layer = DigLogic.getLayer(bounds.SurfaceY - (position + inward).Y)
	if not DigLogic.canDig(shovel, layer) then
		warnPlayer(
			player,
			string.format("%s is too hard! You need a %s.", layer.Name, DigLogic.requiredShovelName(layer))
		)
		return
	end

	local cost = DigLogic.staminaCost(shovel, layer)
	if state.Stamina < cost then
		warnPlayer(player, "Too tired! Catch your breath.")
		return
	end

	local radius = DigLogic.effectiveRadius(shovel, layer)
	local center = DigLogic.clampDigCenter(position + inward * (radius * 0.45), radius, bounds)
	if not DigWorld.isSolidNear(center, radius * 0.75) then
		return
	end

	state.LastDig = now
	state.Stamina -= cost
	terrain:FillBall(center, radius, Enum.Material.Air)
	fxEvent:FireAllClients(center, radius, layer.Color)

	local warnedFull = false
	for _, loot in DigWorld.collectInSphere(center, radius) do
		if not addToBackpack(player, loot.Def, loot.Position) then
			DigWorld.exposeLoot(loot, onExposedPickup)
			if not warnedFull then
				warnedFull = true
				warnPlayer(player, "Backpack full! Sell your loot at the pad.")
			end
		end
	end

	syncAttributes(player)
end

local function onBuyUpgrade(player: Player, kind: unknown): (boolean, string)
	local state = states[player]
	local profile = PlayerData.get(player)
	if not state or not profile then
		return false, "Still loading..."
	end
	local now = os.clock()
	if now - state.LastBuy < 0.3 then
		return false, "Slow down!"
	end
	state.LastBuy = now

	if kind ~= "Shovel" and kind ~= "Backpack" then
		return false, "Unknown upgrade"
	end

	local list: { { Name: string, Price: number } } = if kind == "Shovel"
		then DigConfig.Shovels
		else DigConfig.Backpacks
	local currentLevel = if kind == "Shovel" then profile.ShovelLevel else profile.BackpackLevel
	local nextDef = list[currentLevel + 1]
	if not nextDef then
		return false, "Already maxed out!"
	end
	if profile.Cash < nextDef.Price then
		return false, string.format("Need %s more", DigLogic.formatCash(nextDef.Price - profile.Cash))
	end

	profile.Cash -= nextDef.Price
	if kind == "Shovel" then
		profile.ShovelLevel = currentLevel + 1
		giveShovel(player)
	else
		profile.BackpackLevel = currentLevel + 1
	end
	syncAttributes(player)
	return true, "Unlocked " .. nextDef.Name .. "!"
end

local function onSurface(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local now = os.clock()
	if now - state.LastSurface < DigConfig.SurfaceCooldown then
		warnPlayer(player, string.format("Wait %ds", math.ceil(DigConfig.SurfaceCooldown - (now - state.LastSurface))))
		return
	end
	local root = getAliveRoot(player)
	local character = player.Character
	if not root or not character then
		return
	end
	state.LastSurface = now
	local offset = Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
	character:PivotTo(CFrame.new(surfacePoint + offset))
end

local function sell(player: Player)
	local state = states[player]
	local profile = PlayerData.get(player)
	if not state or not profile then
		return
	end
	local now = os.clock()
	if now - state.LastSell < 1 then
		return
	end
	state.LastSell = now
	if #profile.Backpack == 0 then
		warnPlayer(player, "Nothing to sell. Go dig!")
		return
	end
	local count = #profile.Backpack
	local value = DigLogic.sellValue(profile.Backpack)
	profile.Cash += value
	table.clear(profile.Backpack)
	notify(
		player,
		string.format("Sold %d item%s for %s!", count, if count == 1 then "" else "s", DigLogic.formatCash(value)),
		Color3.fromRGB(90, 255, 120)
	)
	syncAttributes(player)
end

--------------------------------------------------------------------------
-- World setup
--------------------------------------------------------------------------

local function setupSellPad()
	local bounds = DigWorld.getBounds()
	local borderMid = bounds.MaxX + DigConfig.Area.Border / 2
	local centerZ = (bounds.MinZ + bounds.MaxZ) / 2
	surfacePoint = Vector3.new(borderMid, bounds.SurfaceY + 4, centerZ - 10)

	local pad = Workspace:FindFirstChild("SellPad")
	if not (pad and pad:IsA("BasePart")) then
		local newPad = Instance.new("Part")
		newPad.Name = "SellPad"
		newPad.Anchored = true
		newPad.Size = Vector3.new(12, 1, 12)
		newPad.Position = Vector3.new(borderMid, bounds.SurfaceY + 0.5, centerZ + 8)
		newPad.Color = Color3.fromRGB(70, 220, 110)
		newPad.Material = Enum.Material.Neon
		newPad.TopSurface = Enum.SurfaceType.Smooth

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(200, 60)
		billboard.StudsOffset = Vector3.new(0, 4, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 250
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "SELL LOOT"
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(20, 90, 40)
		stroke.Parent = label
		label.Parent = billboard
		billboard.Parent = newPad

		newPad.Parent = Workspace
		pad = newPad
	end

	local sellPad = pad :: BasePart
	sellPad.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			sell(player)
		end
	end)
end

local function teleportPlayersOutOfPit()
	local bounds = DigWorld.getBounds()
	for player in states do
		local root = getAliveRoot(player)
		local character = player.Character
		if
			root
			and character
			and root.Position.Y < bounds.SurfaceY + 2
			and DigLogic.isInsideBounds(root.Position, bounds, 4)
		then
			character:PivotTo(CFrame.new(surfacePoint + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))))
		end
	end
end

--------------------------------------------------------------------------
-- QA commands (Studio, or the place owner): /cash 500  /fill  /maxshovel  /resetdig
--------------------------------------------------------------------------

local function isTester(player: Player): boolean
	return RunService:IsStudio() or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
end

local function onChatted(player: Player, message: string)
	if not isTester(player) then
		return
	end
	local profile = PlayerData.get(player)
	local state = states[player]
	if not profile or not state then
		return
	end
	local command, arg = string.match(message, "^/(%w+)%s*(%S*)")
	if command == "cash" then
		profile.Cash += math.clamp(tonumber(arg) or 1000, 0, 1e9)
	elseif command == "fill" then
		local capacity = DigLogic.getBackpack(profile.BackpackLevel).Capacity
		while #profile.Backpack < capacity do
			table.insert(profile.Backpack, DigLogic.pickLoot(math.random(1, #DigConfig.Layers), math.random()).Id)
		end
	elseif command == "maxshovel" then
		profile.ShovelLevel = #DigConfig.Shovels
		giveShovel(player)
	elseif command == "stamina" then
		state.Stamina = DigConfig.Stamina.Max
	elseif command == "resetdig" then
		teleportPlayersOutOfPit()
		DigWorld.reset()
	else
		return
	end
	notify(player, "[QA] " .. command .. " done", Color3.fromRGB(255, 220, 80))
	syncAttributes(player)
end

--------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = leaderstats
	leaderstats.Parent = player

	PlayerData.load(player)
	if not player.Parent then
		PlayerData.release(player)
		return
	end

	states[player] = {
		Stamina = DigConfig.Stamina.Max,
		LastDig = 0,
		LastWarn = 0,
		LastSell = 0,
		LastSurface = 0,
		LastBuy = 0,
		HintId = 0,
	}
	syncAttributes(player)

	player.CharacterAdded:Connect(function()
		giveShovel(player)
	end)
	if player.Character then
		giveShovel(player)
	end
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)

	if not PlayerData.isSaving(player) then
		notify(player, "Progress won't save this session (DataStore unavailable).", Color3.fromRGB(255, 200, 80))
	end
end

--------------------------------------------------------------------------
-- Init / start
--------------------------------------------------------------------------

function DigService.init()
	remotes = Instance.new("Folder")
	remotes.Name = "DigRemotes"
	digEvent = makeRemote("RemoteEvent", "Dig") :: RemoteEvent
	surfaceEvent = makeRemote("RemoteEvent", "Surface") :: RemoteEvent
	buyFunction = makeRemote("RemoteFunction", "BuyUpgrade") :: RemoteFunction
	fxEvent = makeRemote("RemoteEvent", "DigFx") :: RemoteEvent
	notifyEvent = makeRemote("RemoteEvent", "Notify") :: RemoteEvent
	hintEvent = makeRemote("RemoteEvent", "LootHint") :: RemoteEvent

	local bounds = DigWorld.getBounds()
	remotes:SetAttribute("SurfaceY", bounds.SurfaceY)
	remotes:SetAttribute("MinX", bounds.MinX)
	remotes:SetAttribute("MaxX", bounds.MaxX)
	remotes:SetAttribute("MinZ", bounds.MinZ)
	remotes:SetAttribute("MaxZ", bounds.MaxZ)
	remotes:SetAttribute("BottomY", bounds.BottomY)
	remotes.Parent = ReplicatedStorage

	digEvent.OnServerEvent:Connect(onDig)
	surfaceEvent.OnServerEvent:Connect(onSurface)
	buyFunction.OnServerInvoke = onBuyUpgrade

	setupSellPad()
end

function DigService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	-- Stamina regen (server-authoritative; attribute only updates when it changes).
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		local step = accumulator
		accumulator = 0
		local now = os.clock()
		local max = DigConfig.Stamina.Max
		for player, state in states do
			if state.Stamina < max and now - state.LastDig >= DigConfig.Stamina.RegenDelay then
				local before = math.floor(state.Stamina)
				state.Stamina = math.min(max, state.Stamina + DigConfig.Stamina.RegenPerSecond * step)
				local after = math.floor(state.Stamina)
				if after ~= before then
					player:SetAttribute("Stamina", after)
				end
			end
		end
	end)

	-- Loot detector: each player only ever learns about their nearest item.
	task.spawn(function()
		while true do
			task.wait(DigConfig.DetectorInterval)
			for player, state in states do
				local root = getAliveRoot(player)
				local loot = if root then DigWorld.nearestLoot(root.Position, DigConfig.DetectorRange) else nil
				local id = if loot then loot.Id else 0
				if id ~= state.HintId then
					state.HintId = id
					if loot then
						hintEvent:FireClient(player, loot.Position, loot.Def.Rarity)
					else
						hintEvent:FireClient(player, nil, nil)
					end
				end
			end
		end
	end)

	-- Keep the ground stocked with loot.
	task.spawn(function()
		while true do
			task.wait(20)
			DigWorld.restockLoot()
		end
	end)

	-- Periodic full reset so the pit doesn't end up hollow.
	if DigConfig.ResetIntervalMinutes > 0 then
		task.spawn(function()
			while true do
				task.wait(math.max(60, DigConfig.ResetIntervalMinutes * 60 - 30))
				for player in states do
					notify(player, "The dig site resets in 30 seconds!", Color3.fromRGB(255, 200, 80))
				end
				task.wait(30)
				teleportPlayersOutOfPit()
				DigWorld.reset()
				for player in states do
					notify(player, "Fresh ground! New loot is buried.", Color3.fromRGB(120, 220, 255))
				end
			end
		end)
	end
end

return DigService
