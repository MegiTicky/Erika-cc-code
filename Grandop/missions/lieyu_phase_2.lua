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

local respawn = {
    loadout_file = "data/loadouts/lieyu_phase_2.json",
    tankListFile = "tanksList.txt",
    -- Keep ROM startup unattended. Change these to true for an explicit reset.
    resetTanks = false,
    resetSpawns = false,
    area = { x = 4293, y = 23, z = 6700, radius = 50 },
    reserve = { x = 1572, y = 90, z = 6280 },
    numPointsX = 3, numPointsZ = 3, spacing = 20,
    spawnRadius = 50,
    creativeRadius = 50,

    tanks = {
        germany = {
            tigeri  = { stock = 1, cooldown = 180, buffer = 1 },
            panther = { stock = 5, cooldown = 120, buffer = 2 },
            panzer4 = { stock = 8, cooldown = 60,  buffer = 9999 },
        },
        allied = {
            sherman75      = { stock = 11, cooldown = 3,  buffer = 1 },
            shermanfirefly = { stock = 2,  cooldown = 60, buffer = 1 },
            churchillvii   = { stock = 2,  cooldown = 60, buffer = 1 },
        },
        japan = {
            chinu = { stock = 2, cooldown = 180, buffer = 1 },
            horo  = { stock = 1, cooldown = 180, buffer = 1 },
        },
        USMC = {
            sherman75usmc = { stock = 3, cooldown = 180, buffer = 1 },
        },
    },

    coords = {
        germany = { { name = "Main", x = 5847, y = 38, z = 6540 } },
        allied  = { { name = "Main", x = 7094, y = 28, z = 6473 } },
        japan = {
            { name = "S1 Town Spawn", x = 6068, y = 27, z = 5417 },
            { name = "S2 Hill Top", x = 5401, y = 62, z = 4658 },
            { name = "S3 West Plane", x = 4747, y = 21, z = 4602 },
        },
        USMC = { { name = "Main spawn", x = 4293, y = 23, z = 6700 } },
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
        return respawn.coords[country] or {}
    end,

    initScoreboard = function(reset)
        if reset then
            commands.exec("/scoreboard objectives add spawnCount dummy")
            commands.exec("/team add USMC")
            commands.exec("/team add TownX_JP")
            commands.exec("/team add TownY_JP")
            commands.exec("/team add TownZ_JP")
            commands.exec("/scoreboard players set USMC spawnCount 0")
            commands.exec("/scoreboard players set TownX_JP spawnCount 0")
            commands.exec("/scoreboard players set TownY_JP spawnCount 0")
            commands.exec("/scoreboard players set TownZ_JP spawnCount 0")
        end
        commands.exec("/scoreboard objectives add Troops_Strength dummy")
        commands.exec("/scoreboard objectives setdisplay sidebar Troops_Strength")
        commands.exec("/team add USMCSpawn")
        commands.exec("/team add TownX_JPSpawn")
        commands.exec("/team add TownY_JPSpawn")
        commands.exec("/team add TownZ_JPSpawn")

        local _, _, us = commands.exec("/scoreboard players get USMC spawnCount")
        local _, _, x = commands.exec("/scoreboard players get TownX_JP spawnCount")
        local _, _, y = commands.exec("/scoreboard players get TownY_JP spawnCount")
        local _, _, z = commands.exec("/scoreboard players get TownZ_JP spawnCount")
        commands.exec("/scoreboard players set USMCSpawn Troops_Strength " .. (100 - (tonumber(us) or 0)))
        commands.exec("/scoreboard players set TownX_JPSpawn Troops_Strength " .. (townQuotas["Town X"] - (tonumber(x) or 0)))
        commands.exec("/scoreboard players set TownY_JPSpawn Troops_Strength " .. (townQuotas["Town Y"] - (tonumber(y) or 0)))
        commands.exec("/scoreboard players set TownZ_JPSpawn Troops_Strength " .. (townQuotas["Town Z"] - (tonumber(z) or 0)))
    end,

    hasQuota = function(country, townName)
        if country == "USMC" then
            local _, _, count = commands.exec("/scoreboard players get USMC spawnCount")
            return (100 - (tonumber(count) or 0)) > 0
        end
        local quota = townQuotas[townName]
        if not quota then return false end
        local player = ("Town%s_JP"):format(townName:sub(6))  -- "Town X" -> "TownX_JP"
        local _, _, count = commands.exec("/scoreboard players get " .. player .. " spawnCount")
        return (quota - (tonumber(count) or 0)) > 0
    end,

    decrementQuota = function(country, townName)
        if country == "USMC" then
            local _, _, count = commands.exec("/scoreboard players get USMC spawnCount")
            count = tonumber(count) or 0
            if count < 100 then
                commands.exec("/scoreboard players add USMC spawnCount 1")
                return true
            end
            return false
        end
        local quota = townQuotas[townName]
        if not quota then return false end
        local player = ("Town%s_JP"):format(townName:sub(6))
        local _, _, count = commands.exec("/scoreboard players get " .. player .. " spawnCount")
        count = tonumber(count) or 0
        if count < quota then
            commands.exec("/scoreboard players add " .. player .. " spawnCount 1")
            return true
        end
        return false
    end,

    displayScoreboard = function()
        local _, _, us = commands.exec("/scoreboard players get USMC spawnCount")
        local _, _, x = commands.exec("/scoreboard players get TownX_JP spawnCount")
        local _, _, y = commands.exec("/scoreboard players get TownY_JP spawnCount")
        local _, _, z = commands.exec("/scoreboard players get TownZ_JP spawnCount")
        commands.exec("/scoreboard players set USMCSpawn Troops_Strength " .. (100 - (tonumber(us) or 0)))
        commands.exec("/scoreboard players set TownX_JPSpawn Troops_Strength " .. (townQuotas["Town X"] - (tonumber(x) or 0)))
        commands.exec("/scoreboard players set TownY_JPSpawn Troops_Strength " .. (townQuotas["Town Y"] - (tonumber(y) or 0)))
        commands.exec("/scoreboard players set TownZ_JPSpawn Troops_Strength " .. (townQuotas["Town Z"] - (tonumber(z) or 0)))
    end,

    -- JP units retreat from a town to the next when the stage advances.
    retreatLoop = function(ctx)
        while true do
            if ctx.country == "japan" then
                if ctx.stage.current == 2 and not retreat.townXRetreated then
                    print("Retreat from X")
                    local _, _, xCount = commands.exec("/scoreboard players get TownX_JP spawnCount")
                    local remainingX = townQuotas["Town X"] - (tonumber(xCount) or 0)
                    commands.exec("/scoreboard players set TownX_JP spawnCount " .. townQuotas["Town X"])
                    commands.exec("/scoreboard players remove TownY_JP spawnCount " .. math.floor(remainingX * 0.7))
                    commands.exec("/say JP soldier in town X retreated to town Y")
                    retreat.townXRetreated = true
                elseif ctx.stage.current == 3 and not retreat.townYRetreated then
                    print("Retreat from Y")
                    local _, _, yCount = commands.exec("/scoreboard players get TownY_JP spawnCount")
                    local remainingY = townQuotas["Town Y"] - (tonumber(yCount) or 0)
                    commands.exec("/scoreboard players set TownY_JP spawnCount " .. townQuotas["Town Y"])
                    commands.exec("/scoreboard players remove TownZ_JP spawnCount " .. math.floor(remainingY * 0.7))
                    commands.exec("/say JP soldier in town Y retreated to town Z")
                    retreat.townYRetreated = true
                end
            end
            sleep(0.5)
        end
    end,
}

return {
    id = "lieyu_phase_2",
    name = "Lieyu Phase 2",

    objective = {
        type = "staged_capture",
        stage_channel = 125,
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

        attackerSpawns = {
            { x = 4243, y = 308, z = 6653 },
            { x = 4243, y = 308, z = 6653 },
            { x = 4243, y = 308, z = 6653 },
        },
        defenderSpawns = {
            { x = 4237, y = 308, z = 6653 },
            { x = 4237, y = 308, z = 6653 },
            { x = 4237, y = 308, z = 6653 },
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

    respawn = respawn,
}
