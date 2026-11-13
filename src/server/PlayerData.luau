--!strict
--[[
	PlayerData - load/save the digging profile with retries.

	If a load fails (e.g. Studio without "Enable Studio Access to API
	Services") the player gets a fresh profile that is NEVER saved, so a
	DataStore outage can't overwrite real progress with an empty profile.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DigShared")
local DigConfig = require(Shared:WaitForChild("DigConfig"))

export type Profile = {
	Version: number,
	Cash: number,
	ShovelLevel: number,
	BackpackLevel: number,
	Backpack: { string },
	TotalFound: number,
}

local PROFILE_VERSION = 1
local MAX_RETRIES = 3

local PlayerData = {}

local profiles: { [Player]: Profile } = {}
local canSave: { [Player]: boolean } = {}

local store: DataStore? = nil
local storeOk, storeResult = pcall(function()
	return DataStoreService:GetDataStore(DigConfig.DataStoreName)
end)
if storeOk then
	store = storeResult
else
	warn("[DigData] DataStores unavailable, progress will not save:", storeResult)
end

local function newProfile(): Profile
	return {
		Version = PROFILE_VERSION,
		Cash = 0,
		ShovelLevel = 1,
		BackpackLevel = 1,
		Backpack = {},
		TotalFound = 0,
	}
end

-- Never trust stored data blindly: clamp numbers and drop unknown items.
local function sanitize(raw: any): Profile
	local profile = newProfile()
	if type(raw) ~= "table" then
		return profile
	end
	if type(raw.Cash) == "number" and raw.Cash == raw.Cash then
		profile.Cash = math.max(0, math.floor(raw.Cash))
	end
	if type(raw.ShovelLevel) == "number" then
		profile.ShovelLevel = math.clamp(math.floor(raw.ShovelLevel), 1, #DigConfig.Shovels)
	end
	if type(raw.BackpackLevel) == "number" then
		profile.BackpackLevel = math.clamp(math.floor(raw.BackpackLevel), 1, #DigConfig.Backpacks)
	end
	if type(raw.TotalFound) == "number" then
		profile.TotalFound = math.max(0, math.floor(raw.TotalFound))
	end
	if type(raw.Backpack) == "table" then
		local capacity = DigConfig.Backpacks[profile.BackpackLevel].Capacity
		for _, id in raw.Backpack do
			if type(id) == "string" and DigConfig.LootById[id] and #profile.Backpack < capacity then
				table.insert(profile.Backpack, id)
			end
		end
	end
	return profile
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function isPermanentError(message: string): boolean
	-- Studio without API access fails the same way every time; don't retry.
	return string.find(message, "API", 1, true) ~= nil or string.find(message, "403", 1, true) ~= nil
end

function PlayerData.load(player: Player): Profile
	local activeStore = store
	if not activeStore then
		canSave[player] = false
		profiles[player] = newProfile()
		return profiles[player]
	end

	local loaded = false
	local raw: any = nil
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function()
			return activeStore:GetAsync(keyFor(player))
		end)
		if ok then
			loaded = true
			raw = result
			break
		end
		warn(string.format("[DigData] load attempt %d for %s failed: %s", attempt, player.Name, tostring(result)))
		if isPermanentError(tostring(result)) or not player.Parent then
			break
		end
		task.wait(2 ^ attempt)
	end

	local profile = sanitize(raw)
	profiles[player] = profile
	canSave[player] = loaded
	if not loaded then
		warn("[DigData] " .. player.Name .. " is playing on a temporary profile (will not save)")
	end
	return profile
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

function PlayerData.isSaving(player: Player): boolean
	return canSave[player] == true
end

function PlayerData.save(player: Player): boolean
	local profile = profiles[player]
	local activeStore = store
	if not profile or not activeStore or not canSave[player] then
		return false
	end
	local snapshot = table.clone(profile)
	snapshot.Backpack = table.clone(profile.Backpack)
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			activeStore:UpdateAsync(keyFor(player), function()
				return snapshot
			end)
		end)
		if ok then
			return true
		end
		warn(string.format("[DigData] save attempt %d for %s failed: %s", attempt, player.Name, tostring(err)))
		task.wait(2 ^ attempt)
	end
	return false
end

function PlayerData.release(player: Player)
	PlayerData.save(player)
	profiles[player] = nil
	canSave[player] = nil
end

function PlayerData.start()
	task.spawn(function()
		while true do
			task.wait(DigConfig.AutosaveSeconds)
			for player in profiles do
				task.spawn(PlayerData.save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				PlayerData.save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	Players.PlayerRemoving:Connect(PlayerData.release)
end

return PlayerData
