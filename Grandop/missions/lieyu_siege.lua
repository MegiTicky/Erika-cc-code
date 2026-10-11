-- Mission: Lieyu PVE Siege
-- Objective mode: pve_siege — one defended zone at Town X (4836, 19, 6160).
-- Players (USMC, Blue) deploy as full standard squads from the town and hold
-- the objective against 6 waves of Steve's Army enemies ordered to assault
-- it. Enemies capture by presence alone; players cannot slow the capture,
-- only keep the zone clear of enemies. See lib/objective/pve_siege.lua,
-- lib/siege/waves.lua, and lib/siege/director.lua.

local stageState = { current = 1 }

-- Team-wide respawn quota: 10 deployments shared by every defender.
local RESPAWN_POOL_PLAYER = "SiegeSpawn"
local RESPAWN_POOL_START = 10

local function scoreboardValue(player, objective)
    local ok, output, value = commands.exec("/scoreboard players get " .. player .. " " .. objective)
    if not ok then return 0 end
    if tonumber(value) then return tonumber(value) end
    for _, line in ipairs(output or {}) do
        local value = tostring(line):match("has%s+(-?%d+)")
        if value then return tonumber(value) end
    end
    return 0
end

local function setStrength(player, value)
    local ok, reason = commands.exec("/scoreboard players set " .. player .. " Troops_Strength " .. value)
    if not ok then
        print("Strength update failed for " .. player .. ": " .. textutils.serialise(reason))
        return false
    end
    return true
end

-- Two-statement declaration: canDeploy/consumeDeployment reference the
-- table itself, and a Lua local is not in scope inside its own initializer
-- (one-statement form binds them to the nil GLOBAL — the crash from the
-- first live test).
-- Set by waves.lua the moment the start horn fires; gates the squad-refill
-- horn until the siege is underway.
local siegeFlags = {}

local respawn
respawn = {
    loadout_file = "data/loadouts/lieyu_phase_2_new.json",
    -- Keep startup unattended; the operator backend performs explicit resets.
    resetSpawns = false,
    -- Players respawn here, receive a book, and choose their deployment.
    -- Waiting room uses the exact lieyu_phase_2 staging coordinates: the
    -- respawn point and the chat-prompt trigger scan both key off this one
    -- area, same as the main event.
    stagingAreas = {
        USMC = { default = { x = 4607, y = 277, z = 5538, radius = 10 } },
        -- Validation shim: the enemy faction has no players and no book flow.
        siege_enemy = { default = { x = 0, y = 0, z = 0, radius = 1 } },
    },
    spawnRadius = 15,
    -- Reset Menu: every teamed player carries a written book whose button
    -- hard-resets a stuck respawn session (missing or frozen menu, stale
    -- tags — typically after a relog) without admin help.
    sessionReset = { label = "Reset Menu" },
    -- Squad Refill: the lieyu phase 2 reinforcement horn — blowing it
    -- spends one shared-pool ticket and calls a friendly 14-soldier squad
    -- to the player. Held back until the start horn fires so the pre-start
    -- inventory carries only the start horn (all goat horns share one use
    -- criterion; two at once cannot be told apart by the scoreboard).
    squadRefill = {
        label = "Squad Refill",
        activeWhen = function() return siegeFlags.siegeStarted end,
    },

    infantrySpawns = {
        USMC = {
            [1] = {
                { name = "Town Square", x = 4836, y = 20, z = 6160 },
                { name = "East Gate", x = 4866, y = 20, z = 6160 },
                { name = "West Gate", x = 4806, y = 20, z = 6160 },
            },
        },
        -- Validation shim; never used (no enemy players).
        siege_enemy = {},
    },

    -- Weapon squad: the loadout's USMC.weapon_squad class (player-carried
    -- heavy weapon + support section) draws from a shared pool.
    weaponSquad = { maxLive = 2, cooldown = 180 },

    initScoreboard = function(reset)
        if reset then
            commands.exec("/scoreboard objectives remove Troops_Strength")
            commands.exec("/team remove " .. RESPAWN_POOL_PLAYER)
        end
        commands.exec("/scoreboard objectives add Troops_Strength dummy")
        commands.exec("/team add " .. RESPAWN_POOL_PLAYER)
        if reset then
            setStrength(RESPAWN_POOL_PLAYER, RESPAWN_POOL_START)
        else
            setStrength(RESPAWN_POOL_PLAYER, scoreboardValue(RESPAWN_POOL_PLAYER, "Troops_Strength"))
        end
        commands.exec("/scoreboard objectives setdisplay sidebar Troops_Strength")
    end,

    hasQuota = function()
        return scoreboardValue(RESPAWN_POOL_PLAYER, "Troops_Strength") > 0
    end,

    decrementQuota = function()
        local remaining = scoreboardValue(RESPAWN_POOL_PLAYER, "Troops_Strength")
        if remaining < 1 then return false end
        print("Respawn pool: " .. remaining .. " -> " .. (remaining - 1))
        return setStrength(RESPAWN_POOL_PLAYER, remaining - 1)
    end,

    displayScoreboard = function()
        -- Troops_Strength is the authoritative remaining-respawn counter.
    end,

    -- One shared pool: every defender deployment (first spawn or respawn)
    -- consumes one of the 10 team respawns.
    canDeploy = function()
        return respawn.hasQuota()
    end,

    consumeDeployment = function()
        return respawn.decrementQuota()
    end,
}

local objective = {
    type = "pve_siege",
    stageState = stageState,
    bossbarId = 3,
    attackTeam = "steves_army_enemy",
    defenseTeam = "Blue",
    startZone = 1,

    captureZones = {
        { x = 4836, y = 19, z = 6160 },
    },

    -- Enemy counting by entity type — immune to scoreboard-team assignment
    -- quirks on command-spawned enemies. Used by the capture engine and the
    -- wave wipe check alike.
    enemyEntityTypes = { "steves_army:enemy_soldier", "steves_army:enemy_anti_tank" },

    capture = {
        radius = 40,
        updateInterval = 0.5,
        -- 5x the lieyu staged-capture threshold (200): capture takes five
        -- times as long at any given enemy count.
        threshold = 1000,
        maxValue = 100,
        scoreChange = 3,
        maxCaptureMultiplier = 2.5,
        netheriteBase = true,
    },
}

local siege = {
    objective = objective,
    enemyTeam = "steves_army_enemy",
    defenderTeam = "Blue",

    -- Hand-picked lane points: random generation used to drop soldiers on
    -- roofs and canopies. Bearings for the sector spread are computed from
    -- the objective at startup. If a point still misbehaves, nudge its
    -- coordinates (the no-leaves heightmap snap applies around each point).
    lanePoints = {
        { x = 4947, y = 31, z = 6100 },
        { x = 4905, y = 21, z = 6055 },
        { x = 4850, y = 18, z = 6028 },
        { x = 4771, y = 12, z = 6084 },
        { x = 4720, y = 12, z = 6151 },
        { x = 4715, y = 11, z = 6225 },
        { x = 4717, y =  9, z = 6279 },
        { x = 4791, y = 16, z = 6310 },
        { x = 4858, y = 19, z = 6316 },
        { x = 4910, y = 22, z = 6266 },
        { x = 4954, y = 30, z = 6218 },
    },

    -- Spawn formation (mirrors cc_battle_deploy): soldiers in a firing line
    -- perpendicular to the approach, 3 blocks apart, ranks behind for
    -- squads larger than one line (14 soldiers = 2 ranks of 7).
    spawnSpacing = 3,
    spawnPerRank = 7,

    -- Squad counts scale off the defender headcount: waves 1-2 field one
    -- squad per defender, waves 3-4 1.5x (rounded up), waves 5-6 2x. The
    -- headcount is typed on this computer's terminal when the program
    -- starts. All six waves attack through one sector: 90 degrees wide for
    -- waves 1-4, 180 for waves 5-6.
    defenderCount = function()
        while true do
            write("Number of defenders: ")
            local n = tonumber(read())
            if n and n >= 1 then return math.floor(n) end
            print("Enter a whole number of 1 or more")
        end
    end,
    waveMultiplier = { 1, 1, 1.5, 1.5, 2, 2 },
    spread = { "sector", "sector", "sector", "sector", "sector", "sector" },
    sectorWidth = { 90, 90, 90, 90, 180, 180 },

    -- Wave 1 starts only when a defender blows the start horn (every Blue
    -- player carries one, taken back the moment it fires). "Force Next
    -- Wave" is a signal flare (firework rocket, harmless pop) fired to end
    -- the current wait early — its use stat shares nothing with the
    -- goat-horn use stat the start and refill horns ride. Subsequent waves
    -- follow the wipe + breather pace.
    flags = siegeFlags,
    startHorn = { label = "Start Wave 1" },
    forceHorn = { label = "Force Next Wave" },
    waveDelay = 30,    -- breather between waves
    squadSpawnInterval = 40, -- seconds between squad spawns within a wave (trickle-in)
    stuckTimeout = 600, -- next wave spawns anyway if enemies never reach 0
    enemyEntityTypes = { "steves_army:enemy_soldier", "steves_army:enemy_anti_tank" },

    -- Enemy squads mirror the USMC.standard composition (14 soldiers).
    -- All spawn as `stevesarmy spawn enemy squad <cs>` — MG/AT kits ride
    -- rifleman-role soldiers, the only enemy type that joins orderable
    -- squads.
    squad = { rifleman = 9, machine_gunner = 3, anti_tank = 2 },
    kits = { source = "data/loadouts/lieyu_phase_2_new.json", class = "USMC.standard" },

    -- One real `stevesarmy spawn enemy anti_tank` per active lane: squad-less
    -- and unorderable by design (mod limitation), it holds the lane approach
    -- and rockets players/vehicles on sight.
    ambushersPerLane = 1,

    -- Registration list consumed by the assault director.
    activeSquads = {},

    director = {
        tick = 2,
        chargeEveryMin = 20, chargeEveryMax = 45,     -- seconds between charges
        chargeDistMin = 15, chargeDistMax = 30,       -- charge length (blocks)
        lateralMin = 10, lateralMax = 25,             -- lateral drift (blocks)
        chargeDurationMin = 5, chargeDurationMax = 8, -- seconds exposed
        attackRefresh = 45,                           -- re-ping before the mod's 60s expiry
        suppressEveryMin = 30, suppressEveryMax = 60,
        suppressDurationMin = 8, suppressDurationMax = 10,
        suppressRange = 150,                          -- prefer defenders near the objective
    },
}

return {
    id = "lieyu_siege",
    name = "Lieyu PVE Siege",
    mode = "siege",

    features = {
        tanks = false,
        creative = false,
        stageSync = false,
        onboarding = true,
    },

    onboarding = {
        red_team = "Red",
        blue_team = "Blue",
        loop_interval = 1,
        -- PVE: only the defender team is joinable. Red exists only as the
        -- validation shim faction; the join prompt never offers it.
        defenders_only = true,
    },

    objective = objective,

    teams = {
        Blue = "USMC",
        Red = "siege_enemy",
    },

    operator = {
        quota_pools = { SiegeSpawn = true },
    },

    siege = siege,
    respawn = respawn,
}
