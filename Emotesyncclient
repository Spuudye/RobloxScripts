--[[
    EmoteSyncClient.lua - Upload to GitHub
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Settings = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("emoteSyncSettings"))
local EmoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("emote")

local localPlayer = Players.LocalPlayer
local emotes = {}
local preloadedAssets = {}

local telemetryAccumulator = 0

local function shouldDebugPlayer(playerName)
	if not Settings.debug or not Settings.debugClient then
		return false
	end

	if Settings.debugAllPlayers then
		return true
	end

	return playerName == localPlayer.Name
end

local function debugLog(playerName, ...)
	if shouldDebugPlayer(playerName) then
		print("[EMOTE SYNC CLIENT][" .. playerName .. "]", ...)
	end
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

local function getState(playerName)
	local state = emotes[playerName]
	if not state then
		state = {
			animation = nil,
			track = nil,
			speed = Settings.defaultSpeed,
			assetId = nil,
			character = nil
		}
		emotes[playerName] = state
	end
	return state
end

local function preloadAsset(assetId)
	if preloadedAssets[assetId] then
		return
	end

	preloadedAssets[assetId] = true

	task.spawn(function()
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://" .. assetId

		pcall(function()
			ContentProvider:PreloadAsync({animation})
		end)

		animation:Destroy()
	end)
end

local function getAnimator(player)
	if not player.Character then
		return nil, nil, nil
	end

	local humanoid = player.Character:FindFirstChildWhichIsA("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil, nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = humanoid:WaitForChild("Animator", 1)
	end

	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	return animator, humanoid, player.Character
end

local function waitForTrackLength(track)
	local started = os.clock()

	while track.Length <= 0 and (os.clock() - started) < Settings.trackLengthWaitTimeout do
		task.wait()
	end
end

local function stopEmote(player)
	if not player then
		return
	end

	local state = emotes[player.Name]
	if not state then
		return
	end

	if state.track then
		pcall(function()
			state.track:Stop(0.1)
		end)

		pcall(function()
			state.track:Destroy()
		end)
	end

	state.track = nil
	state.animation = nil
	state.assetId = nil
	state.character = nil
end

local function cleanupExtraDanceTracks(humanoid, keepTrack)
	for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
		if track ~= keepTrack and track.Priority == Enum.AnimationPriority.Action4 then
			pcall(function()
				track:Stop(0.05)
			end)
		end
	end
end

local function loadAndPlay(player, animation, speed, timePosition)
	if not player or not animation or not animation.AssetId then
		return
	end

	local animator, humanoid, character = getAnimator(player)
	if not animator then
		return
	end

	local state = getState(player.Name)
	local assetId = tonumber(animation.AssetId)
	local reuseTrack = state.track and state.assetId == assetId and state.character == character

	if not reuseTrack then
		stopEmote(player)
		preloadAsset(assetId)

		local animationObject = Instance.new("Animation")
		animationObject.AnimationId = "rbxassetid://" .. assetId

		local success, track = pcall(function()
			return animator:LoadAnimation(animationObject)
		end)

		animationObject:Destroy()

		if not success or not track then
			debugLog(player.Name, "FAILED LOAD", tostring(assetId))
			return
		end

		track.Priority = Enum.AnimationPriority.Action4
		waitForTrackLength(track)

		pcall(function()
			track:Play(0.05)
		end)

		cleanupExtraDanceTracks(humanoid, track)

		state.track = track
		state.assetId = assetId
		state.character = character
	else
		cleanupExtraDanceTracks(humanoid, state.track)
	end

	state.animation = cloneAnimation(animation)
	state.speed = tonumber(speed) or Settings.defaultSpeed

	local track = state.track
	if not track then
		return
	end

	pcall(function()
		if not track.IsPlaying then
			track:Play(0.05)
		end
	end)

	pcall(function()
		track:AdjustSpeed(state.speed)
	end)

	if timePosition ~= nil then
		local targetPosition = tonumber(timePosition) or 0
		if track.Length > 0 then
			targetPosition = targetPosition % track.Length
		end

		pcall(function()
			track.TimePosition = targetPosition
		end)
	end
end

local function applySpeed(player, speed)
	if not player then
		return
	end

	local state = emotes[player.Name]
	if not state or not state.track then
		return
	end

	state.speed = tonumber(speed) or state.speed

	pcall(function()
		state.track:AdjustSpeed(state.speed)
	end)
end

local function playEmote(targetPlayer, animation, speed, syncedPlayers, timePosition)
	if not targetPlayer then
		return
	end

	stopEmote(targetPlayer)

	if syncedPlayers then
		for _, syncedPlayer in ipairs(syncedPlayers) do
			stopEmote(syncedPlayer)
		end
	end

	if animation then
		loadAndPlay(targetPlayer, animation, speed, timePosition)

		if syncedPlayers then
			for _, syncedPlayer in ipairs(syncedPlayers) do
				loadAndPlay(syncedPlayer, animation, speed, timePosition)
			end
		end
	end
end

local function getWrappedDifference(current, desired, length)
	if not length or length <= 0 then
		return math.abs(desired - current)
	end

	local diff = math.abs(desired - current)
	local alt1 = math.abs((desired - current) + length)
	local alt2 = math.abs((desired - current) - length)

	return math.min(diff, alt1, alt2)
end

local function attemptSyncFromSource(targetPlayer, sourceName, triesLeft)
	local sourceState = sourceName and emotes[sourceName] or nil

	if sourceState and sourceState.track and sourceState.animation then
		local targetState = emotes[targetPlayer.Name]

		if targetState and targetState.track then
			local sourceLength = sourceState.track.Length > 0 and sourceState.track.Length or nil
			local diff = getWrappedDifference(
				targetState.track.TimePosition,
				sourceState.track.TimePosition,
				sourceLength
			)

			if diff < Settings.resyncThreshold then
				return
			end
		end

		playEmote(
			targetPlayer,
			sourceState.animation,
			sourceState.track.Speed,
			nil,
			sourceState.track.TimePosition
		)

		debugLog(
			targetPlayer.Name,
			"SYNCED FROM SOURCE",
			sourceName,
			"timePosition", string.format("%.3f", sourceState.track.TimePosition),
			"speed", string.format("%.3f", sourceState.track.Speed)
		)

		return
	end

	if triesLeft > 0 then
		task.delay(Settings.syncRetryDelay, function()
			attemptSyncFromSource(targetPlayer, sourceName, triesLeft - 1)
		end)
	end
end

RunService.RenderStepped:Connect(function()
	for playerName, state in pairs(emotes) do
		local player = Players:FindFirstChild(playerName)

		if not player or not player.Character then
			emotes[playerName] = nil
			continue
		end

		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			emotes[playerName] = nil
			continue
		end

		if state.track then
			for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
				if track ~= state.track and track.Priority ~= Enum.AnimationPriority.Core then
					pcall(function()
						track:Stop(0.05)
					end)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	emotes[player.Name] = nil
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function()
		stopEmote(player)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterRemoving:Connect(function()
		stopEmote(player)
	end)
end

EmoteEvent.OnClientEvent:Connect(function(eventPlayer, data)
	if type(data) ~= "table" or type(data.operation) ~= "string" then
		return
	end

	local operation = data.operation

	if operation == "load" then
		local payload = data.data and data.data.emotes
		if type(payload) ~= "table" then
			return
		end

		for playerName, playerData in pairs(payload) do
			local targetPlayer = Players:FindFirstChild(playerName)
			if targetPlayer and playerData.animation then
				playEmote(
					targetPlayer,
					playerData.animation,
					playerData.speed,
					nil,
					nil
				)
			end
		end

		return
	end

	if operation == "play" then
		playEmote(
			eventPlayer,
			data.data and data.data.animation,
			data.data and data.data.speed,
			data.data and data.data.synced,
			nil
		)
		return
	end

	if operation == "speed" then
		applySpeed(eventPlayer, data.data and data.data.speed)

		local syncedPlayers = data.data and data.data.synced
		if type(syncedPlayers) == "table" then
			for _, syncedPlayer in ipairs(syncedPlayers) do
				applySpeed(syncedPlayer, data.data.speed)
			end
		end

		return
	end

	if operation == "sync" then
		local sourcePlayer = data.data and data.data.player
		if typeof(sourcePlayer) ~= "Instance" or not sourcePlayer:IsA("Player") then
			return
		end

		if not eventPlayer then
			return
		end

		local targetState = getState(eventPlayer.Name)
		targetState.animation = cloneAnimation(data.data.animation)
		targetState.speed = tonumber(data.data.speed) or targetState.speed

		attemptSyncFromSource(eventPlayer, sourcePlayer.Name, Settings.syncRetryCount)
		return
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	telemetryAccumulator += deltaTime

	if not (Settings.debug and Settings.debugClient) then
		return
	end

	if telemetryAccumulator < Settings.debugTelemetryInterval then
		return
	end

	telemetryAccumulator = 0

	local localState = emotes[localPlayer.Name]
	if localState and localState.track then
		EmoteEvent:FireServer({
			operation = "debugTrackReport",
			data = {
				trackTimePosition = localState.track.TimePosition,
				trackLength = localState.track.Length,
				appliedSpeed = localState.track.Speed
			}
		})
	end
end)
