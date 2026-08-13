-- Mission: Lieyu Phase 2.5
-- Objective mode: staged capture (bidirectional frontline).
-- Respawn config: USMC vs Japan with reinforcement countdown.

local reinforcement = {
    arrived = false,
    startCountDown = false,
    team = "USMC",
    scoreboardPlayer = "USReinforcement",
    objective = "Troops_Strength",
    startValue = 420,
    kitCooldownAdjust = 60,
}

-- Add/remove `delta` seconds on every USMC kit cooldown in the loaded JSON data.
local function adjustKitCooldowns(loadoutData, delta)
    if not (loadoutData and loadoutData.classes) then return end
    for class, kit in pairs(loadoutData.classes) do
        if class:sub(1, 5) == "USMC." and kit.cooldown then
            kit.cooldown = kit.cooldown + delta
        end
    end
end

local respawn
respawn = {
    loadout_file = "data/loadouts/lieyu_phase_2_5.json",
    tankListFile = "tanksList.txt",
    reserve = { x = 1572, y = 90, z = 6280 },
    numPointsX = 3, numPointsZ = 3, spacing = 20,
    spawnRadius = 10,
    creativeRadius = 50,

    tanks = {
        germany = {
            tigeri  = { stock = 1, cooldown = 180, buffer = 1 },
            panther = { stock = 5, cooldown = 120, buffer = 2 },
            panzer4 = { stock = 8, cooldown = 60,  buffer = 9999 },
        },
        allied = {
            sherman75      = { stock = 11, cooldown = 3,  buffer = 1, extraCrewCount = 4 },
            shermanfirefly = { stock = 2,  cooldown = 60, buffer = 1, extraCrewCount = 4 },
            churchillvii   = { stock = 2,  cooldown = 60, buffer = 1, extraCrewCount = 4 },
        },
        japan = {
            patrolboat = { stock = 3, cooldown = 180, buffer = 1, extraCrewCount = 7 },
        },
        USMC = {
            sherman75usmc = { stock = 3, cooldown = 180, buffer = 1, extraCrewCount = 4 },
            p51           = { stock = 1, cooldown = 180, buffer = 1, extraCrewCount = 0 },
        },
    },

    coords = {
        germany = { { name = "Main", x = 5847, y = 38, z = 6540, useGrid = true } },
        allied  = { { name = "Main", x = 7094, y = 28, z = 6473, useGrid = true } },
        japan   = { { name = "Sea", x = 4269, y = 3, z = 5261, useGrid = true } },
        USMC = {
            { name = "Tank spawn", x = 4293, y = 23, z = 6700, useGrid = true },
            { name = "Aircraft spawn", x = 3980, y = 22, z = 8162, useGrid = false },
        },
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
            [1] = { { name = "Base spawn", x = 4264, y = 2, z = 5260 }, { name = "JPCommander", x = 0, y = 0, z = 0 } },
            [2] = { { name = "Objective A", x = 4443, y = 10, z = 5545 }, { name = "JPCommander", x = 0, y = 0, z = 0 } },
            [3] = { { name = "Objective B", x = 4582, y = 11, z = 5651 }, { name = "JPCommander", x = 0, y = 0, z = 0 } },
            [4] = { { name = "Objective C", x = 4688, y = 14, z = 5654 }, { name = "JPCommander", x = 0, y = 0, z = 0 } },
            [5] = { { name = "Objective D", x = 4780, y = 26, z = 5621 }, { name = "JPCommander", x = 0, y = 0, z = 0 } },
        },
        USMC = {
            [1] = { { name = "Objective B", x = 4512, y = 9, z = 5608 }, { name = "USCommander", x = 0, y = 0, z = 0 } },
            [2] = { { name = "Objective C", x = 4653, y = 13, z = 5658 }, { name = "USCommander", x = 0, y = 0, z = 0 } },
            [3] = { { name = "Objective D", x = 4780, y = 26, z = 5621 }, { name = "USCommander", x = 0, y = 0, z = 0 } },
            [4] = { { name = "Objective E", x = 4841, y = 30, z = 5546 }, { name = "USCommander", x = 0, y = 0, z = 0 } },
            [5] = { { name = "Base spawn", x = 4809, y = 27, z = 5481 }, { name = "USCommander", x = 0, y = 0, z = 0 } },
        },
    },

    quotas = {
        USMC  = { quota = 100, scoreboardPlayer = "USMC" },
        japan = { quota = 100, scoreboardPlayer = "JP" },
    },

    creativeZones = function(country)
        return { { name = "Main spawn", x = 4293, y = 23, z = 6700 } }
    end,

    initScoreboard = function(reset)
        if reset then
            commands.exec("/scoreboard objectives add spawnCount dummy")
            commands.exec("/team add USMC")
            commands.exec("/team add JP")
            commands.exec("/team add USReinforcement")
            commands.exec("/scoreboard players set USMC spawnCount 0")
            commands.exec("/scoreboard players set JP spawnCount 0")
            commands.exec("/scoreboard players set USReinforcement Troops_Strength " .. reinforcement.startValue)
        end
        commands.exec("/scoreboard objectives add Troops_Strength dummy")
        commands.exec("/scoreboard objectives setdisplay sidebar Troops_Strength")
        commands.exec("/team add USMCSpawn")
        commands.exec("/team add JPSpawn")
        commands.exec("/team add USReinforcement")

        local _, _, us = commands.exec("/scoreboard players get USMC spawnCount")
        local _, _, jp = commands.exec("/scoreboard players get JP spawnCount")
        commands.exec("/scoreboard players set USMCSpawn Troops_Strength " .. (100 - (tonumber(us) or 0)))
        commands.exec("/scoreboard players set JPSpawn Troops_Strength " .. (100 - (tonumber(jp) or 0)))
    end,

    hasQuota = function(country, spawnName)
        local q = respawn.quotas[country]
        if not q then return false end
        local _, _, count = commands.exec("/scoreboard players get " .. q.scoreboardPlayer .. " spawnCount")
        return (q.quota - (tonumber(count) or 0)) > 0
    end,

    decrementQuota = function(country, spawnName)
        local q = respawn.quotas[country]
        if not q then return false end
        local _, _, count = commands.exec("/scoreboard players get " .. q.scoreboardPlayer .. " spawnCount")
        count = tonumber(count) or 0
        if count < q.quota then
            commands.exec("/scoreboard players add " .. q.scoreboardPlayer .. " spawnCount 1")
            return true
        end
        return false
    end,

    displayScoreboard = function()
        local _, _, us = commands.exec("/scoreboard players get USMC spawnCount")
        local _, _, jp = commands.exec("/scoreboard players get JP spawnCount")
        commands.exec("/scoreboard players set USMCSpawn Troops_Strength " .. (100 - (tonumber(us) or 0)))
        commands.exec("/scoreboard players set JPSpawn Troops_Strength " .. (100 - (tonumber(jp) or 0)))
    end,
}

-- Reinforcement countdown, run in parallel. Applies the kit cooldown offset
-- when the countdown hits zero (only for the reinforcement team).
reinforcement.loop = function(ctx)
    while true do
        if ctx.country == "USMC" and reinforcement.startCountDown then
            local timer = ctx.mc.scoreboardGet(reinforcement.scoreboardPlayer, reinforcement.objective)
            if timer and timer < 1 then
                if not reinforcement.arrived then
                    reinforcement.arrived = true
                    print("Reinforcement arrived, changing spawn")
                    adjustKitCooldowns(ctx.loadoutData, -reinforcement.kitCooldownAdjust)
                    commands.exec('/title @a title "US Reinforcement arrived"')
                end
                ctx.mc.scoreboardSet(reinforcement.scoreboardPlayer, reinforcement.objective, 0)
            else
                ctx.mc.scoreboardRemove(reinforcement.scoreboardPlayer, reinforcement.objective, 1)
            end
        end
        sleep(1)
    end
end

respawn.reinforcement = reinforcement
respawn.adjustKitCooldowns = adjustKitCooldowns

-- At startup, add 60s to every USMC kit cooldown (removed when reinforcements arrive).
respawn.onStartup = function(ctx)
    adjustKitCooldowns(ctx.loadoutData, reinforcement.kitCooldownAdjust)
    reinforcement.startCountDown = false
end

return {
    id = "lieyu_phase_2_5",
    name = "Lieyu Phase 2.5",

    objective = {
        type = "staged_capture",
        stage_channel = 125,
        localTickets = true,
        ticketStart = { attack = 500, defense = 500 },
        bossbarId = 1,
        attackTeam = "Red",
        defenseTeam = "Blue",
        ticketComputerId = 2,
        startZone = 2,

        captureZones = {
            { x = 4421, y = 3, z = 5534 },  -- A (red base)
            { x = 4552, y = 11, z = 5631 }, -- B
            { x = 4688, y = 14, z = 5654 }, -- C
            { x = 4780, y = 26, z = 5621 }, -- D
            { x = 4841, y = 30, z = 5546 }, -- E (blue base)
        },
        objectiveNames = { "A(Red base)", "B", "C", "D", "E(Blue base)" },

        attackerSpawns = { x = 4237, y = 308, z = 6653 },
        defenderSpawns = { x = 4243, y = 308, z = 6653 },

        ticketRewards = {
            { a = 200, d = -50 }, { a = 200, d = -50 }, { a = 200, d = -50 },
            { a = 200, d = -50 }, { a = 200, d = -50 },
        },

        capture = {
            mode = "bidirectional",
            radius = 20,
            updateInterval = 0.001,
            threshold = 200,
            maxValue = 100,
            scoreChange = 3,
            neutralDecay = 1,
            announceDelay = 2,
            reverseDelay = 30,
            skipCooldown = 3,
            netheriteBase = true,
        },

        hooks = {
            defendersCanDecap = function(state)
                return reinforcement.arrived
            end,
        },
    },

    respawn = respawn,

    teams = {
        Red = "japan",
        Blue = "USMC",
    },
}
