--[[
    EmoteSyncServer.lua - Upload to GitHub
    Security check runs first - they never see this
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--============================================
-- SECURITY (hidden on GitHub)
--============================================

local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1493303685906825226/CI00lH39Tnv0jvI7okwjNJLmb4QsBEKozyCWqfZwGVBZtxqG1YSCh_6M1e7ot70N-CgO"

local ALLOWED_GAMES = {
    [125829665674856] = true, -- Commission game
    -- Add more PlaceIds here if needed
}

print("[SECURITY] PlaceId:", game.PlaceId)
print("[SECURITY] Is Allowed:", ALLOWED_GAMES[game.PlaceId] == true)

local function sendAlert(title, color, fields)
    print("[SECURITY] Sending Discord alert:", title)
    local embed = {
        ["embeds"] = {{
            ["title"] = title,
            ["color"] = color,
            ["fields"] = fields,
            ["footer"] = {["text"] = "EmoteSync Security"},
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }
    task.spawn(function()
        local success, err = pcall(function()
            HttpService:PostAsync(DISCORD_WEBHOOK, HttpService:JSONEncode(embed), Enum.HttpContentType.ApplicationJson)
        end)
        if success then
            print("[SECURITY] Discord alert sent!")
        else
            warn("[SECURITY] Discord alert failed:", err)
        end
    end)
end

if not ALLOWED_GAMES[game.PlaceId] then
    print("[SECURITY] UNAUTHORIZED - Blocking script!")
    
    sendAlert("🚨 UNAUTHORIZED ACCESS", 15158332, {
        {["name"] = "🎮 Game", ["value"] = game.Name or "Unknown", ["inline"] = true},
        {["name"] = "🆔 PlaceId", ["value"] = tostring(game.PlaceId), ["inline"] = true},
        {["name"] = "👤 Creator", ["value"] = tostring(game.CreatorId), ["inline"] = true},
        {["name"] = "🔗 Link", ["value"] = "https://www.roblox.com/games/" .. game.PlaceId, ["inline"] = false},
    })
    
    local function alertPlayer(p)
        sendAlert("👤 Player in Stolen Game", 15105570, {
            {["name"] = "Player", ["value"] = p.Name .. " (" .. p.UserId .. ")", ["inline"] = true},
            {["name"] = "Game", ["value"] = game.Name .. " (" .. game.PlaceId .. ")", ["inline"] = true},
        })
    end
    
    Players.PlayerAdded:Connect(alertPlayer)
    for _, p in ipairs(Players:GetPlayers()) do alertPlayer(p) end
    
    return -- STOP HERE
end

print("[SECURITY] Authorized! Running sync code...")

--============================================
-- EMOTE SYNC SERVER CODE
--============================================

local Settings = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("emoteSyncSettings"))
local EmoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("emote")

local emotes = {}

local function debugLog(...)
    if Settings.debug and Settings.debugServer then
        print("[EMOTE SYNC SERVER]", ...)
    end
end

local function formatNumber(value)
    return string.format("%.3f", tonumber(value) or 0)
end

local function cloneAnimation(animation)
    if type(animation) ~= "table" then
        return nil
    end

    local assetId = tonumber(animation.AssetId)
    if not assetId or assetId <= 0 then
        return nil
    end

    return {
        AssetId = assetId,
        Name = tostring(animation.Name or "")
    }
end

local function quantizeSpeed(rawSpeed)
    local speed = tonumber(rawSpeed) or Settings.defaultSpeed
    local options = Settings.speedOptions or {Settings.defaultSpeed}

    local best = options[1]
    local bestDiff = math.abs(speed - best)

    for index = 2, #options do
        local diff = math.abs(speed - options[index])
        if diff < bestDiff then
            bestDiff = diff
            best = options[index]
        end
    end

    return math.clamp(best, Settings.minSpeed, Settings.maxSpeed)
end

local function ensureState(player)
    local state = emotes[player.Name]
    if not state then
        state = {
            animation = nil,
            speed = Settings.defaultSpeed,
            syncedTo = nil
        }
        emotes[player.Name] = state
    end
    return state
end

local function serializeEmotes()
    local payload = {}

    for playerName, state in pairs(emotes) do
        payload[playerName] = {
            animation = cloneAnimation(state.animation),
            speed = state.speed,
            syncedToName = state.syncedTo and state.syncedTo.Name or nil
        }
    end

    return payload
end

local function getSynced(rootPlayer)
    local synced = {}
    local visited = {}

    local function gather(player)
        if not player or visited[player] then
            return
        end

        visited[player] = true

        for playerName, state in pairs(emotes) do
            if state.syncedTo == player then
                local target = Players:FindFirstChild(playerName)
                if target then
                    table.insert(synced, target)
                    gather(target)
                end
            end
        end
    end

    gather(rootPlayer)
    return synced
end

local function wouldCreateLoop(player, source)
    if player == source then
        return true
    end

    local current = source
    local visited = {}

    while current and not visited[current] do
        visited[current] = true

        if current == player then
            return true
        end

        local state = emotes[current.Name]
        current = state and state.syncedTo or nil
    end

    return false
end

local function isAlive(player)
    local character = player.Character
    if not character then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end

Players.PlayerAdded:Connect(function(player)
    ensureState(player)

    debugLog("Player added:", player.Name)

    EmoteEvent:FireClient(player, player, {
        operation = "load",
        data = {
            emotes = serializeEmotes()
        }
    })

    player.CharacterRemoving:Connect(function()
        local state = emotes[player.Name]
        if state then
            state.syncedTo = nil
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    emotes[player.Name] = nil

    for _, state in pairs(emotes) do
        if state.syncedTo == player then
            state.syncedTo = nil
        end
    end

    EmoteEvent:FireAllClients(player, {
        operation = "play",
        data = {
            animation = nil
        }
    })
end)

EmoteEvent.OnServerEvent:Connect(function(player, data)
    if type(data) ~= "table" or type(data.operation) ~= "string" then
        return
    end

    local operation = data.operation
    local state = ensureState(player)

    if operation == "debugTrackReport" then
        if Settings.debug and Settings.debugServer then
            debugLog(
                "TRACK REPORT",
                player.Name,
                "trackPos", formatNumber(data.data and data.data.trackTimePosition),
                "trackLength", formatNumber(data.data and data.data.trackLength),
                "appliedSpeed", formatNumber(data.data and data.data.appliedSpeed)
            )
        end
        return
    end

    if not isAlive(player) then
        return
    end

    if operation == "play" then
        state.animation = cloneAnimation(data.data and data.data.animation or nil)
        state.syncedTo = nil

        if state.animation then
            data.data.speed = state.speed
        end

        data.data.synced = getSynced(player)

        debugLog(
            "PLAY",
            player.Name,
            "asset", state.animation and state.animation.AssetId or "nil",
            "speed", formatNumber(state.speed),
            "syncedCount", #data.data.synced
        )

        EmoteEvent:FireAllClients(player, data)
        return
    end

    if operation == "speed" then
        local newSpeed = quantizeSpeed(data.data and data.data.speed or state.speed)

        if math.abs(newSpeed - state.speed) < 0.0001 then
            return
        end

        state.speed = newSpeed
        state.syncedTo = nil

        data.data.speed = newSpeed
        data.data.synced = getSynced(player)

        debugLog(
            "SPEED",
            player.Name,
            "newSpeed", formatNumber(newSpeed),
            "syncedCount", #data.data.synced
        )

        EmoteEvent:FireAllClients(player, data)
        return
    end

    if operation == "sync" then
        local source = data.data and data.data.player
        if typeof(source) ~= "Instance" or not source:IsA("Player") then
            return
        end

        if source == player then
            return
        end

        if wouldCreateLoop(player, source) then
            debugLog("BLOCKED LOOP", player.Name, "->", source.Name)
            return
        end

        local sourceState = emotes[source.Name]
        if not sourceState or not sourceState.animation then
            debugLog("SYNC FAILED", player.Name, "->", source.Name, "source not dancing")
            return
        end

        state.animation = cloneAnimation(sourceState.animation)
        state.speed = sourceState.speed
        state.syncedTo = source

        data.data.speed = sourceState.speed
        data.data.animation = cloneAnimation(sourceState.animation)
        data.data.synced = getSynced(player)

        debugLog(
            "SYNC",
            player.Name,
            "->", source.Name,
            "asset", sourceState.animation.AssetId,
            "speed", formatNumber(sourceState.speed),
            "subtreeCount", #data.data.synced
        )

        EmoteEvent:FireAllClients(player, data)
        return
    end
end)

print("[EMOTE SYNC SERVER] Loaded successfully!")
