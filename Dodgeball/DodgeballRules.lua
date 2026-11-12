--!strict
-- DodgeballRules (ModuleScript) — put in ServerScriptService (server only).
-- Pure rule logic: it decides what a hit, catch, block or foul MEANS.
-- It never touches parts, physics or UI, so other server scripts call it
-- after they detect something, then act on the result it returns.
--
-- Usage:
--   local Rules = require(path.DodgeballRules)
--   local match = Rules.newMatch(require(path.DodgeballConfig))
--   Rules.addPlayer(match, player.UserId, "Red")
--   Rules.startRound(match, os.clock())
--   local result = Rules.resolveHit(match, throwerId, targetId, { bounced = false, headshot = false })

export type Status = "In" | "Jail" | "Out"

export type PlayerState = {
	team: string,
	status: Status,
	lives: number,
	foul: number,
	ultimate: number,
	outOrder: number, -- when they got out; used to pick who a catch revives
	frozenUntil: number,
}

export type Match = {
	config: any,
	players: { [number]: PlayerState },
	scores: { [string]: number },
	round: number,
	phase: "Waiting" | "Playing" | "SuddenDeath" | "Intermission" | "Finished",
	roundStart: number,
	outCounter: number,
}

export type Event = { kind: string, player: number?, data: any? }

local Rules = {}

-- helpers -----------------------------------------------------------------

local function otherTeam(match: Match, team: string): string
	local names = match.config.TeamNames
	return if names[1] == team then names[2] else names[1]
end

local function sendOut(match: Match, id: number, events: { Event })
	local p = match.players[id]
	if not p or p.status ~= "In" then
		return
	end
	p.lives -= 1
	if p.lives > 0 then
		table.insert(events, { kind = "LifeLost", player = id, data = p.lives })
		return
	end
	match.outCounter += 1
	p.outOrder = match.outCounter
	p.status = if match.config.JailEnabled then "Jail" else "Out"
	table.insert(events, { kind = if p.status == "Jail" then "Jailed" else "Out", player = id })
end

local function bringBackIn(match: Match, id: number, events: { Event })
	local p = match.players[id]
	if not p or p.status == "In" then
		return
	end
	p.status = "In"
	p.lives = match.config.LivesPerRound
	table.insert(events, { kind = "BackIn", player = id })
end

-- the teammate who has been out the longest
local function firstOutTeammate(match: Match, team: string): number?
	local bestId, bestOrder = nil, math.huge
	for id, p in match.players do
		if p.team == team and p.status ~= "In" and p.outOrder < bestOrder then
			bestId, bestOrder = id, p.outOrder
		end
	end
	return bestId
end

local function addUltimate(match: Match, id: number, amount: number)
	local p = match.players[id]
	if p and match.config.AbilitiesEnabled then
		p.ultimate = math.min(100, p.ultimate + amount)
	end
end

-- setup -------------------------------------------------------------------

function Rules.newMatch(config: any): Match
	local scores = {}
	for _, name in config.TeamNames do
		scores[name] = 0
	end
	return {
		config = config,
		players = {},
		scores = scores,
		round = 0,
		phase = "Waiting",
		roundStart = 0,
		outCounter = 0,
	}
end

function Rules.addPlayer(match: Match, id: number, team: string)
	match.players[id] = {
		team = team,
		-- players who join mid-round wait in jail (or spectate) until next round
		status = if match.phase == "Playing" then (if match.config.JailEnabled then "Jail" else "Out") else "In",
		lives = match.config.LivesPerRound,
		foul = 0,
		ultimate = 0,
		outOrder = 0,
		frozenUntil = 0,
	}
end

function Rules.removePlayer(match: Match, id: number)
	match.players[id] = nil
end

-- put new players on the smaller team
function Rules.pickTeam(match: Match): string
	local counts = {}
	for _, name in match.config.TeamNames do
		counts[name] = 0
	end
	for _, p in match.players do
		counts[p.team] += 1
	end
	local names = match.config.TeamNames
	return if counts[names[1]] <= counts[names[2]] then names[1] else names[2]
end

function Rules.startRound(match: Match, now: number)
	match.round += 1
	match.phase = "Playing"
	match.roundStart = now
	match.outCounter = 0
	for _, p in match.players do
		p.status = "In"
		p.lives = match.config.LivesPerRound
		p.foul = 0
		p.frozenUntil = 0
		p.outOrder = 0
	end
end

-- core rules --------------------------------------------------------------

export type HitInfo = {
	bounced: boolean?,       -- ball touched floor/wall first
	headshot: boolean?,
	targetHoldingBall: boolean?,
	now: number?,            -- current time (os.clock()), used for card freezes
}

-- A thrown ball touched a player. Returns events for other scripts to act on.
function Rules.resolveHit(match: Match, throwerId: number, targetId: number, info: HitInfo): { Event }
	local cfg = match.config
	local events: { Event } = {}
	local thrower, target = match.players[throwerId], match.players[targetId]
	if match.phase ~= "Playing" and match.phase ~= "SuddenDeath" then
		return events
	end
	if not thrower or not target or target.status ~= "In" then
		return events
	end
	if thrower.status == "Out" then
		return events
	end
	if thrower.status == "Jail" and not cfg.JailEnabled then
		return events
	end

	if info.bounced and cfg.BallDeadAfterBounce then
		table.insert(events, { kind = "DeadBall", player = targetId })
		return events
	end
	if thrower.team == target.team and not cfg.FriendlyFire then
		return events
	end
	if info.targetHoldingBall and not cfg.HitWhileHoldingBallCounts then
		table.insert(events, { kind = "Blocked", player = targetId })
		return events
	end
	if info.headshot and not cfg.HeadshotsCount then
		table.insert(events, { kind = "HeadshotFoul", player = throwerId })
		local foulEvents = Rules.addFoul(match, throwerId, 30, true, info.now or 0)
		for _, e in foulEvents do
			table.insert(events, e)
		end
		return events
	end

	sendOut(match, targetId, events)
	table.insert(events, { kind = "Hit", player = throwerId, data = targetId })
	addUltimate(match, throwerId, cfg.UltimateChargeOnHit)

	if thrower.status == "Jail" and cfg.JailHitFreesPlayer then
		bringBackIn(match, throwerId, events)
		table.insert(events, { kind = "JailEscape", player = throwerId })
	end

	if match.phase == "SuddenDeath" then
		table.insert(events, { kind = "SuddenDeathHit", player = throwerId })
	end
	return events
end

-- A player caught a live ball thrown by throwerId.
function Rules.resolveCatch(match: Match, catcherId: number, throwerId: number): { Event }
	local cfg = match.config
	local events: { Event } = {}
	local catcher, thrower = match.players[catcherId], match.players[throwerId]
	if not cfg.CatchEnabled or not catcher or not thrower then
		return events
	end
	if catcher.status == "Out" or (catcher.status == "Jail" and not cfg.JailCanCatch) then
		return events
	end
	if catcher.team == thrower.team then
		return events
	end

	table.insert(events, { kind = "Catch", player = catcherId, data = throwerId })
	addUltimate(match, catcherId, cfg.UltimateChargeOnCatch)

	if cfg.CatchOutsThrower then
		sendOut(match, throwerId, events)
	end
	if cfg.CatchRevivesTeammate then
		local reviveId = firstOutTeammate(match, catcher.team)
		if reviveId then
			bringBackIn(match, reviveId, events)
		end
	end
	return events
end

-- A sword swing met a ball. timeSinceSwing = seconds between click and contact.
-- Returns "Parry", "Block" or "Miss".
function Rules.resolveSwordBlock(match: Match, playerId: number, timeSinceSwing: number): string
	local cfg = match.config
	local p = match.players[playerId]
	if not cfg.SwordsEnabled or not p or p.status ~= "In" then
		return "Miss"
	end
	if timeSinceSwing < 0 or timeSinceSwing > cfg.SwordBlockWindow then
		return "Miss"
	end
	if timeSinceSwing >= cfg.SwordBlockWindow - cfg.SwordParryWindow then
		addUltimate(match, playerId, cfg.UltimateChargeOnParry)
		return "Parry"
	end
	return "Block"
end

-- Player crossed the center line.
function Rules.resolveLineCross(match: Match, playerId: number, refSees: boolean, now: number): { Event }
	local cfg = match.config
	local events: { Event } = {}
	if not cfg.CenterLineEnabled then
		return events
	end
	if cfg.LineCrossPenalty == "Out" then
		sendOut(match, playerId, events)
	elseif cfg.LineCrossPenalty == "Foul" then
		events = Rules.addFoul(match, playerId, cfg.LineCrossFoul, refSees, now)
	end
	return events
end

-- Add foul points. The ref only hands out a card if he sees the foul.
function Rules.addFoul(match: Match, playerId: number, amount: number, refSees: boolean, now: number): { Event }
	local cfg = match.config
	local events: { Event } = {}
	local p = match.players[playerId]
	if not p or not cfg.RefEnabled or amount <= 0 then
		return events
	end
	p.foul = math.min(cfg.RedCardAt, p.foul + amount)

	if not refSees then
		table.insert(events, { kind = "SneakyFoul", player = playerId })
		return events
	end
	if p.foul >= cfg.RedCardAt then
		table.insert(events, { kind = "RedCard", player = playerId })
		p.foul = 0
		if cfg.RedCardSendsToJail then
			p.lives = 1
			sendOut(match, playerId, events)
		end
	elseif p.foul >= cfg.YellowCardAt then
		table.insert(events, { kind = "YellowCard", player = playerId })
		p.frozenUntil = now + cfg.YellowCardFreeze
	end
	return events
end

-- Bribe power-up: wipe the meter.
function Rules.clearFoul(match: Match, playerId: number)
	local p = match.players[playerId]
	if p then
		p.foul = 0
	end
end

-- Call every frame/tick from the server loop.
function Rules.tick(match: Match, dt: number)
	local decay = match.config.FoulDecayPerSecond * dt
	for _, p in match.players do
		p.foul = math.max(0, p.foul - decay)
	end
end

function Rules.isFrozen(match: Match, playerId: number, now: number): boolean
	local p = match.players[playerId]
	return p ~= nil and now < p.frozenUntil
end

-- round & match end ----------------------------------------------------------

function Rules.countIn(match: Match, team: string): number
	local n = 0
	for _, p in match.players do
		if p.team == team and p.status == "In" then
			n += 1
		end
	end
	return n
end

-- Returns the winning team name, "Draw", or nil if the round keeps going.
function Rules.checkRoundEnd(match: Match, now: number): string?
	local cfg = match.config
	local a, b = cfg.TeamNames[1], cfg.TeamNames[2]
	local inA, inB = Rules.countIn(match, a), Rules.countIn(match, b)

	if inA == 0 and inB == 0 then
		return "Draw"
	elseif inA == 0 then
		return b
	elseif inB == 0 then
		return a
	end

	if match.phase == "Playing" and now - match.roundStart >= cfg.RoundTime then
		local mode = cfg.OnTimeout
		if mode == "MostPlayers" and inA ~= inB then
			return if inA > inB then a else b
		elseif mode == "Draw" then
			return "Draw"
		end
		match.phase = "SuddenDeath" -- tie or "SuddenDeath" mode; court starts shrinking
	end
	return nil
end

-- Score the round. Returns the match winner's team name, or nil if the match continues.
function Rules.endRound(match: Match, winner: string): string?
	if winner ~= "Draw" then
		match.scores[winner] += 1
		if match.scores[winner] >= match.config.RoundsToWin then
			match.phase = "Finished"
			return winner
		end
	end
	match.phase = "Intermission"
	return nil
end

Rules.otherTeam = otherTeam

return Rules
