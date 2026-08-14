-- Mission: Lieyu Phase 2
-- Objective mode: staged capture (forward only).
-- Respawn config: USMC vs Japan (town-based quotas) with town retreats.

local townQuotas = {
    ["Town X"] = 30,
    ["Town Y"] = 30,
    ["Town Z"] = 40,
}

local retreat = {
    townXRetreated = false,
    townYRetreated = false,
}

local stageState = { current = 1 }

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
    local actual = scoreboardValue(player, "Troops_Strength")
    if actual ~= value then
        print("Strength readback mismatch for " .. player .. ": expected " .. value .. ", got " .. actual)
        return false
    end
    return true
end

local function strengthPlayer(country, townName)
    if country == "USMC" then return "USMCSpawn" end
    return ("Town%s_JPSpawn"):format(townName:sub(6))
end

local respawn
respawn = {
    loadout_file = "data/loadouts/lieyu_phase_2_new.json",
    tankListFile = "tanksList.txt",
    -- Keep ROM startup unattended. Change these to true for an explicit reset.
    resetTanks = false,
    resetSpawns = false,
    -- Players respawn here, receive a book, and choose their deployment.
    -- Stage-specific entries may replace `default` in later missions.
    stagingAreas = {
        USMC = { default = { x = 4243, y = 308, z = 6653, radius = 10 } },
        japan = { default = { x = 4237, y = 308, z = 6653, radius = 10 } },
    },
    reserve = { x = 1572, y = 90, z = 6280 },
    numPointsX = 3, numPointsZ = 3, spacing = 20,
    spawnRadius = 50,
    creativeRadius = 50,

    -- Breakthrough pools are additive. Phase 2 makes every listed vehicle
    -- available at stage 1 and adds none at later stages.
    vehiclePools = {
        policy = "add",
        initial = {
            japan = {
                chinu = { stock = 2, cooldown = 180, buffer = 1 },
                horo  = { stock = 1, cooldown = 180, buffer = 1 },
            },
            USMC = {
                sherman75usmc = { stock = 3, cooldown = 180, buffer = 1 },
            },
        },
        additions = {},
    },

    vehicleSpawns = {
        japan = {
            { name = "S1 Town Spawn", x = 6068, y = 27, z = 5417, useGrid = true },
            { name = "S2 Hill Top", x = 5401, y = 62, z = 4658, useGrid = true },
            { name = "S3 West Plane", x = 4747, y = 21, z = 4602, useGrid = true },
        },
        USMC = { { name = "Main tank spawn", x = 4293, y = 23, z = 6700, useGrid = true } },
    },

    infantrySpawns = {
        germany = {
            [1] = { { name = "G_S1 Trench", x = 5800, y = 40, z = 6500 }, { name = "G_S1 Forest", x = 5825, y = 40, z = 6520 } },
            [2] = { { name = "G_S2 Ruins", x = 5930, y = 42, z = 6600 }, { name = "G_S2 Road", x = 5960, y = 42, z = 6630 } },
        },
        allied = {
            [1] = { { name = "A_S1 Beach", x = 7080, y = 28, z = 6460 }, { name = "A_S1 Cliff", x = 7110, y = 30, z = 6485 } },
            [2] = { { name = "A_S2 Depot", x = 7200, y = 29, z = 6550 }, { name = "A_S2 Yard", x = 7230, y = 29, z = 6575 } },
        },
        japan = {
            [1] = {
                { name = "Town X", x = 4836, y = 20, z = 6160 },
                { name = "Town Y", x = 4711, y = 17, z = 5925 },
                { name = "Town Z", x = 4815, y = 29, z = 5561 },
            },
            [2] = {
                { name = "Town X", x = 4836, y = 20, z = 6160 },
                { name = "Town Y", x = 4711, y = 17, z = 5925 },
                { name = "Town Z", x = 4815, y = 29, z = 5561 },
            },
            [3] = {
                { name = "Town X", x = 4836, y = 20, z = 6160 },
                { name = "Town Y", x = 4711, y = 17, z = 5925 },
                { name = "Town Z", x = 4815, y = 29, z = 5561 },
            },
        },
        USMC = {
            [1] = { { name = "S1 Main Town", x = 4592, y = 18, z = 6411 }, { name = "USCommander", x = 0, y = 0, z = 0 } },
            [2] = { { name = "S2 Town X", x = 4825, y = 19, z = 6149 }, { name = "USCommander", x = 0, y = 0, z = 0 } },
            [3] = { { name = "S3 Town Y", x = 4735, y = 20, z = 5881 }, { name = "USCommander", x = 0, y = 0, z = 0 } },
        },
    },

    -- USMC uses one global quota; japan uses per-town quotas.
    quotas = {
        USMC = { quota = 100, scoreboardPlayer = "USMC" },
    },
    townQuotas = townQuotas,

    creativeZones = function(country)
        return respawn.vehicleSpawns[country] or {}
    end,

    initScoreboard = function(reset)
        commands.exec("/scoreboard objectives add Troops_Strength dummy")
        if reset then
            setStrength("USMCSpawn", 100)
            setStrength("TownX_JPSpawn", townQuotas["Town X"])
            setStrength("TownY_JPSpawn", townQuotas["Town Y"])
            setStrength("TownZ_JPSpawn", townQuotas["Town Z"])
        end
        commands.exec("/scoreboard objectives setdisplay sidebar Troops_Strength")
        commands.exec("/team add USMCSpawn")
        commands.exec("/team add TownX_JPSpawn")
        commands.exec("/team add TownY_JPSpawn")
        commands.exec("/team add TownZ_JPSpawn")

        -- Do not overwrite live reinforcement values unless an explicit reset was requested.
        if not reset then
            setStrength("USMCSpawn", scoreboardValue("USMCSpawn", "Troops_Strength"))
            setStrength("TownX_JPSpawn", scoreboardValue("TownX_JPSpawn", "Troops_Strength"))
            setStrength("TownY_JPSpawn", scoreboardValue("TownY_JPSpawn", "Troops_Strength"))
            setStrength("TownZ_JPSpawn", scoreboardValue("TownZ_JPSpawn", "Troops_Strength"))
        end
    end,

    hasQuota = function(country, townName)
        if country ~= "USMC" and not townQuotas[townName] then return false end
        return scoreboardValue(strengthPlayer(country, townName), "Troops_Strength") > 0
    end,

    decrementQuota = function(country, townName)
        if country ~= "USMC" and not townQuotas[townName] then return false end
        local player = strengthPlayer(country, townName)
        local remaining = scoreboardValue(player, "Troops_Strength")
        if remaining < 1 then return false end
        local updated = remaining - 1
        if setStrength(player, updated) then
            print("Reinforcements: " .. (townName or country) .. " " .. remaining .. " -> " .. updated)
            return true
        end
        return false
    end,

    displayScoreboard = function()
        -- Troops_Strength is the authoritative remaining-reinforcement counter.
    end,

    -- A reinforcement is committed only after a book deployment succeeds.
    -- Japan's town quota applies to infantry choices; tank stock is separate.
    canDeploy = function(country, kind, spawnName)
        if country == "USMC" then return respawn.hasQuota(country) end
        if kind == "infantry" then return respawn.hasQuota(country, spawnName) end
        return true
    end,

    consumeDeployment = function(country, kind, spawnName)
        if country == "USMC" then return respawn.decrementQuota(country) end
        if kind == "infantry" then return respawn.decrementQuota(country, spawnName) end
        return true
    end,

    attackerDepleted = function()
        return scoreboardValue("USMCSpawn", "Troops_Strength") < 1
    end,

    -- JP units retreat from a town to the next when the stage advances.
    retreatLoop = function(ctx)
        while true do
            if ctx.stage.current == 2 and not retreat.townXRetreated then
                print("Retreat from X")
                local remainingX = scoreboardValue("TownX_JPSpawn", "Troops_Strength")
                local remainingY = scoreboardValue("TownY_JPSpawn", "Troops_Strength")
                setStrength("TownX_JPSpawn", 0)
                setStrength("TownY_JPSpawn", remainingY + math.floor(remainingX * 0.7))
                commands.exec("/say JP soldier in town X retreated to town Y")
                retreat.townXRetreated = true
            elseif ctx.stage.current == 3 and not retreat.townYRetreated then
                print("Retreat from Y")
                local remainingY = scoreboardValue("TownY_JPSpawn", "Troops_Strength")
                local remainingZ = scoreboardValue("TownZ_JPSpawn", "Troops_Strength")
                setStrength("TownY_JPSpawn", 0)
                setStrength("TownZ_JPSpawn", remainingZ + math.floor(remainingY * 0.7))
                commands.exec("/say JP soldier in town Y retreated to town Z")
                retreat.townYRetreated = true
            end
            sleep(0.5)
        end
    end,
}

return {
    id = "lieyu_phase_2",
    name = "Lieyu Phase 2",
    mode = "breakthrough",

    features = {
        tanks = true,
        creative = false,
        stageSync = false,
    },

    objective = {
        type = "staged_capture",
        stage_channel = 125,
        stageState = stageState,
        localTickets = true,
        ticketStart = { attack = 500, defense = 500 },
        bossbarId = 1,
        attackTeam = "Blue",
        defenseTeam = "Red",
        ticketComputerId = 2,
        startZone = 1,

        captureZones = {
            { x = 4836, y = 19, z = 6160 },
            { x = 4711, y = 16, z = 5925 },
            { x = 4815, y = 28, z = 5561 },
        },

        ticketRewards = {
            { a = 200, d = -50 },
            { a = 200, d = -50 },
            { a = 200, d = -50 },
        },

        capture = {
            mode = "forward",
            radius = 50,
            updateInterval = 0.001,
            threshold = 200,
            maxValue = 100,
            attackScore = 1,
            defenseScore = -1,
            neutralScore = -1,
            skipCooldown = 3,
        },
    },

    teams = {
        Blue = "USMC",
        Red = "japan",
    },

    operator = {
        quota_pools = { USMCSpawn = true, TownX_JPSpawn = true, TownY_JPSpawn = true, TownZ_JPSpawn = true },
    },

    respawn = respawn,
}
