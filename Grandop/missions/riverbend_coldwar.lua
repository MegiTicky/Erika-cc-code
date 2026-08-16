-- Mission: Riverbend Cold War
-- Objective mode: bidirectional Frontline.
-- Both teams start at their bases and contest the central objective B.

local QUOTA = 10
local stageState = { current = 2 }

local function scoreboardValue(player, objective)
    local ok, output, value = commands.exec("/scoreboard players get " .. player .. " " .. objective)
    if ok and tonumber(value) then return tonumber(value) end
    for _, line in ipairs(output or {}) do
        local found = tostring(line):match("has%s+(-?%d+)")
        if found then return tonumber(found) end
    end
    return 0
end

local function setStrength(player, value)
    commands.exec("/scoreboard players set " .. player .. " Troops_Strength " .. math.max(0, math.floor(value)))
end

local respawn = {
    loadout_file = "data/loadouts/riverbend_coldwar.json",
    resetSpawns = false,
    spawnRadius = 10,

    -- Players respawn here, receive the chat menu, and choose a deployment
    -- point for the current Frontline objective.
    stagingAreas = {
        USSR = { default = { x = 170, y = 190, z = -1, radius = 10 } },
        NATO = { default = { x = 155, y = 190, z = -1, radius = 10 } },
    },

    -- The active objective starts at B (stage 2). Each team has one deploy
    -- point per stage; the respawn service applies the 10-block random radius.
    infantrySpawns = {
        NATO = {
            [1] = { { name = "NATO A Base", x = 73, y = 23, z = -11 } },
            [2] = { { name = "NATO A Base", x = 73, y = 23, z = -11 } },
            [3] = { { name = "NATO B Objective", x = 167, y = 22, z = -3 } },
        },
        USSR = {
            [1] = { { name = "USSR B Objective", x = 167, y = 22, z = -3 } },
            [2] = { { name = "USSR C Base", x = 326, y = 22, z = -63 } },
            [3] = { { name = "USSR C Base", x = 326, y = 22, z = -63 } },
        },
    },

    quotas = {
        NATO = { quota = QUOTA, scoreboardPlayer = "NATO" },
        USSR = { quota = QUOTA, scoreboardPlayer = "USSR" },
    },

    initScoreboard = function(reset)
        commands.exec("/scoreboard objectives add Troops_Strength dummy")
        commands.exec("/scoreboard objectives setdisplay sidebar Troops_Strength")
        if reset then
            setStrength("NATO", QUOTA)
            setStrength("USSR", QUOTA)
        else
            -- Ensure both entries exist without restoring or increasing a
            -- persisted quota during a normal controller restart.
            commands.exec("/scoreboard players add NATO Troops_Strength 0")
            commands.exec("/scoreboard players add USSR Troops_Strength 0")
        end
    end,

    hasQuota = function(country)
        local quota = respawn.quotas[country]
        if not quota then return false end
        return scoreboardValue(quota.scoreboardPlayer, "Troops_Strength") > 0
    end,

    decrementQuota = function(country)
        local quota = respawn.quotas[country]
        if not quota then return false end
        local player = quota.scoreboardPlayer
        local remaining = scoreboardValue(player, "Troops_Strength")
        if remaining < 1 then return false end
        setStrength(player, remaining - 1)
        return scoreboardValue(player, "Troops_Strength") == remaining - 1
    end,

    canDeploy = function(country, kind)
        return kind == "infantry" and respawn.hasQuota(country)
    end,

    consumeDeployment = function(country, kind)
        return kind == "infantry" and respawn.decrementQuota(country)
    end,

    displayScoreboard = function()
        -- The sidebar is maintained by initScoreboard; values are updated on
        -- every successful deployment.
    end,
}

return {
    id = "riverbend_coldwar",
    name = "Riverbend Cold War",
    mode = "frontline",

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
    },

    objective = {
        type = "staged_capture",
        stageState = stageState,
        bossbarId = "riverbend_frontline",
        attackTeam = "Blue",
        defenseTeam = "Red",
        startZone = 2,

        captureZones = {
            { x = 73, y = 23, z = -11 },
            { x = 167, y = 22, z = -3 },
            { x = 326, y = 22, z = -63 },
        },
        objectiveNames = { "A (NATO base)", "B", "C (USSR base)" },

        capture = {
            mode = "bidirectional",
            radius = 20,
            updateInterval = 0.05,
            threshold = 200,
            maxValue = 100,
            scoreChange = 3,
            neutralDecay = 1,
            announceDelay = 2,
            reverseDelay = 30,
            skipCooldown = 3,
        },
    },

    teams = {
        Blue = "NATO",
        Red = "USSR",
    },

    -- Quota values are checkpointed, but exhaustion never ends the match.
    operator = {
        quota_pools = { NATO = true, USSR = true },
    },

    respawn = respawn,
}
