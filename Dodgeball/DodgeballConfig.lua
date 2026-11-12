--!strict
-- DodgeballConfig (ModuleScript) — put in ReplicatedStorage.
-- Every rule of the game lives here. Change the values to change the game;
-- no other script needs editing. Game modes can override any of these.

local Config = {}

-- TEAMS & MATCH ------------------------------------------------------------
Config.TeamNames = { "Red", "Blue" }
Config.MinPlayersToStart = 2       -- total players needed before a match starts
Config.MaxPlayersPerTeam = 6
Config.RoundsToWin = 3             -- best of 5 = first to 3
Config.RoundTime = 180             -- seconds per round
Config.IntermissionTime = 10       -- seconds between rounds

-- What happens when the round timer hits 0:
--   "MostPlayers"  -> team with more players still in wins (tie = SuddenDeath)
--   "SuddenDeath"  -> court shrinks, next hit wins
--   "Draw"         -> nobody scores
Config.OnTimeout = "MostPlayers"
Config.SuddenDeathShrinkSpeed = 1  -- studs per second the court closes in

-- BALLS --------------------------------------------------------------------
Config.BallCount = 5               -- balls placed on the center line each round
Config.OpeningRushDelay = 3        -- countdown before players may run for balls
Config.MaxBallsHeld = 1            -- how many balls one player can carry
Config.ThrowCooldown = 0.6         -- seconds between throws
Config.MinThrowSpeed = 60          -- studs/sec with no charge
Config.MaxThrowSpeed = 140         -- studs/sec at full charge
Config.ChargeTime = 1.0            -- seconds to reach full charge
Config.BallDeadAfterBounce = true  -- ball that touched floor/wall can't get anyone out

-- HITS & OUTS --------------------------------------------------------------
Config.FriendlyFire = false        -- can you get your own teammates out?
Config.HeadshotsCount = true       -- false = head hit is a foul on the thrower instead
Config.HitWhileHoldingBallCounts = true  -- false = the ball you hold acts as a shield
Config.LivesPerRound = 1           -- hits needed to get a player out

-- CATCHING -----------------------------------------------------------------
Config.CatchEnabled = true
Config.CatchWindow = 0.25          -- seconds the catch button stays active
Config.CatchCooldown = 1.0
Config.CatchOutsThrower = true     -- catching the ball gets the thrower out
Config.CatchRevivesTeammate = true -- catching brings one teammate back in (first out, first back)

-- JAIL (players who are out stand behind the enemy team) --------------------
Config.JailEnabled = true          -- false = out players just spectate
Config.JailHitFreesPlayer = true   -- hitting an enemy from jail puts you back in
Config.JailCanCatch = false        -- can jailed players catch balls?

-- LINE RULES ---------------------------------------------------------------
Config.CenterLineEnabled = true
Config.LineCrossPenalty = "Foul"   -- "Foul" (adds foul points), "Out", or "None"
Config.LineCrossFoul = 40

-- SWORDS -------------------------------------------------------------------
Config.SwordsEnabled = true
Config.SwordBlockWindow = 0.35     -- seconds a block stays active after clicking
Config.SwordParryWindow = 0.10     -- last part of the block window = perfect parry
Config.SwordCooldown = 1.5
Config.ParrySpeedMultiplier = 1.3  -- parried ball returns this much faster
Config.SwordCanSliceBall = true    -- held swing destroys the ball
Config.SliceCooldown = 8

-- REF & FOULS --------------------------------------------------------------
Config.RefEnabled = true           -- false = "No Ref" chaos mode
Config.RefViewAngle = 70           -- degrees the ref can see either side of where he looks
Config.RefViewDistance = 120
Config.FoulDecayPerSecond = 2      -- foul meter drains slowly over time
Config.YellowCardAt = 50           -- foul meter value where the ref gives a yellow
Config.RedCardAt = 100
Config.YellowCardFreeze = 5        -- seconds frozen
Config.RedCardSendsToJail = true

-- POWER-UPS ----------------------------------------------------------------
Config.PowerUpsEnabled = true
Config.PowerUpSpawnInterval = 20   -- seconds between spawns
Config.MaxPowerUpsOnCourt = 3
Config.MaxPowerUpsHeld = 1

-- Foul points each dirty power-up adds. Set to 0 to make one "legal".
-- Remove a line to take that power-up out of the game.
Config.PowerUps = {
	BananaPeel  = { Foul = 15, Duration = 2 },   -- slip + drop ball
	BallBlaster = { Foul = 45, Shots = 6 },      -- cartoon ball cannon
	GlueBomb    = { Foul = 25, Duration = 3 },
	SmokeBomb   = { Foul = 10, Duration = 6 },   -- ref can't see through smoke
	HotBall     = { Foul = 25 },                 -- can't be caught
	MagnetBall  = { Foul = 40 },                 -- homes on nearest enemy
	Bribe       = { Foul = 0,  RefBlindTime = 5 },-- clears your foul meter
	FakeBall    = { Foul = 15, StunTime = 1.5 },
	LeafBlower  = { Foul = 20, Force = 60 },
	LineHop     = { Foul = 60, Duration = 4 },   -- cross the center line
}

-- CHARACTERS ---------------------------------------------------------------
Config.AbilitiesEnabled = true
Config.UltimateChargeOnHit = 25    -- ultimate meter is 0-100
Config.UltimateChargeOnCatch = 35
Config.UltimateChargeOnParry = 20

-- REWARDS ------------------------------------------------------------------
Config.Coins = {
	Hit = 5,
	Catch = 10,
	Parry = 8,
	JailEscape = 5,
	RoundWin = 20,
	MatchWin = 50,
	SneakyFoul = 3,  -- used a dirty power-up and the ref didn't see it
}

return Config
