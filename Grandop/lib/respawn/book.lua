-- Grandop chat-menu respawn service.
-- Players choose class and spawn with tellraw buttons. Privileged actions are
-- still performed by the command computer.

local loadout = grandopRequire("lib.loadout")
local stevesArmy = grandopRequire("lib.steves_army")

local book = {}
local MODE_TRIGGER = "g_resp_mode"
local CLASS_TRIGGER = "g_resp_class"
local SPAWN_TRIGGER = "g_resp_spawn"
local TANK_TRIGGER = "g_resp_tank"
local TANK_SPAWN_TRIGGER = "g_resp_tspawn"
local RESET_TRIGGER = "g_resp_reset"
local SESSION_AGE_OBJECTIVE = "g_resp_age"
local SESSION_TIMEOUT = 30
local TRIGGER_OBJECTIVES = {
    MODE_TRIGGER,
    CLASS_TRIGGER,
    SPAWN_TRIGGER,
    TANK_TRIGGER,
    TANK_SPAWN_TRIGGER,
    RESET_TRIGGER,
}

local function json(value)
    return textutils.serialiseJSON(value)
end

local function selectorForTeam(team, area, extra)
    local s = "@a[team=" .. team .. ",x=" .. area.x .. ",y=" .. area.y .. ",z=" .. area.z .. ",distance=.." .. area.radius
    if extra then s = s .. "," .. extra end
    return s .. "]"
end

local function waitingSelector(team, tag)
    return "@a[team=" .. team .. ",tag=" .. tag .. "]"
end

local function page(title, entries)
    local result = {
        { text = title .. "\n\n", color = "gold", bold = true },
    }
    for _, entry in ipairs(entries) do
        table.insert(result, {
            text = "[ " .. entry.label .. " ]\n",
            color = entry.color or "green",
            clickEvent = { action = "run_command", value = entry.command },
        })
    end
    table.insert(result, {
        text = "[ Reset menu ]\n",
        color = "red",
        clickEvent = { action = "run_command", value = "/trigger " .. RESET_TRIGGER .. " set 1" },
    })
    return result
end

local function sendMenu(target, title, entries)
    local ok, reason = commands.exec("/tellraw " .. target .. " " .. json(page(title, entries)))
    if not ok then
        print("Chat menu delivery failed (" .. title .. "): " .. textutils.serialise(reason))
    end
    return ok
end

local function teamForFaction(cfg, faction)
    for team, value in pairs(cfg.teams or {}) do
        if value == faction then return team end
    end
    return faction == "USMC" and "Blue" or "Red"
end

local function factionForTeam(cfg, team)
    return (cfg.teams and cfg.teams[team]) or (team == "Blue" and "USMC" or "japan")
end

local function factionClasses(data, faction)
    local result = {}
    local prefix = faction .. "."
    for name in pairs(data.classes or {}) do
        if name:sub(1, #prefix) == prefix then
            table.insert(result, name)
        end
    end
    table.sort(result)
    return result
end

local function stagingArea(respawn, faction, stage)
    local areas = respawn.stagingAreas[faction]
    return areas and (areas[stage.current] or areas.default)
end

local function factionBook(target, faction, allowTanks)
    local mode = {
        { label = "Infantry", command = "/trigger " .. MODE_TRIGGER .. " set 1", color = "green" },
    }
    if allowTanks then
        table.insert(mode, { label = "Tank", command = "/trigger " .. MODE_TRIGGER .. " set 2", color = "gray" })
    end
    return sendMenu(target, faction .. " Respawn", mode)
end

local function classBook(area, data, faction, team, target)
    local entries = {}
    for i, className in ipairs(factionClasses(data, faction)) do
        local short = className:sub(#faction + 2)
        table.insert(entries, { label = short, command = "/trigger " .. CLASS_TRIGGER .. " set " .. i })
    end
    if #entries > 0 then
        return sendMenu(target or waitingSelector(team, "grandop_wait_class"), "Choose " .. faction .. " Class", entries)
    end
    return false
end

local function tankBook(area, faction, team, tanks, target)
    local entries = {}
    local list = tanks[faction] or {}
    local names = {}
    for name, value in pairs(list) do
        if (value.stock or 0) > 0 then table.insert(names, name) end
    end
    table.sort(names)
    for i, name in ipairs(names) do
        table.insert(entries, { label = name .. " (" .. list[name].stock .. ")", command = "/trigger " .. TANK_TRIGGER .. " set " .. i })
    end
    if #entries > 0 then
        return sendMenu(target or waitingSelector(team, "grandop_wait_tank"), "Choose " .. faction .. " Tank", entries)
    end
    return false
end

local function spawnBook(area, respawn, faction, team, stage, target)
    local entries = {}
    local list = respawn.infantrySpawns[faction] and respawn.infantrySpawns[faction][stage.current] or {}
    for i, spawn in ipairs(list) do
        if not respawn.canDeploy or respawn.canDeploy(faction, "infantry", spawn.name) then
            table.insert(entries, { label = spawn.name, command = "/trigger " .. SPAWN_TRIGGER .. " set " .. i })
        end
    end
    if #entries > 0 then
        return sendMenu(target or waitingSelector(team, "grandop_wait_spawn"), "Choose " .. faction .. " Spawn", entries)
    end
    return false
end

local function tankSpawnBook(area, respawn, faction, team, target)
    local entries = {}
    local list = respawn.vehicleSpawns[faction] or {}
    for i, spawn in ipairs(list) do
        table.insert(entries, { label = spawn.name, command = "/trigger " .. TANK_SPAWN_TRIGGER .. " set " .. i })
    end
    if #entries > 0 then
        return sendMenu(target or waitingSelector(team, "grandop_wait_tank_spawn"), "Choose " .. faction .. " Tank Spawn", entries)
    end
    return false
end

local function processingSelector(team)
    return "@a[team=" .. team .. ",tag=grandop_processing,limit=1]"
end

local function triggerSelector(team, waitTag, objective, value, savedTag)
    local selector = "@a[team=" .. team .. ",tag=" .. waitTag .. ",scores={" .. objective .. "=" .. value .. "}"
    if savedTag then selector = selector .. ",tag=" .. savedTag end
    return selector .. ",limit=1]"
end

local function randomTeleport(target, spawn, radius)
    if spawn.name == "USCommander" then
        commands.exec("/tp " .. target .. " @a[tag=USCom,limit=1]")
    elseif spawn.name == "JPCommander" then
        commands.exec("/tp " .. target .. " @a[tag=JPCom,limit=1]")
    else
        radius = radius or 10
        local dx = math.random(-radius, radius)
        local dz = math.random(-radius, radius)
        local x = math.floor(spawn.x + dx + 0.5)
        local z = math.floor(spawn.z + dz + 0.5)
        commands.exec(("/tp %s %d %d %d"):format(target, x, spawn.y, z))
    end
end

function book.run(ctx)
    local mission = ctx.mission
    local respawn = ctx.respawn
    local data = ctx.loadoutData
    local state = ctx.state
    local teams = ctx.teams
    local features = ctx.features
    local stagingStatus = {}
    local log = ctx.log or print

    local function resetTrigger(target, objective)
        commands.exec("/scoreboard players set " .. target .. " " .. objective .. " 0")
    end

    local function enableTrigger(target, objective)
        commands.exec("/scoreboard players enable " .. target .. " " .. objective)
        resetTrigger(target, objective)
    end

    local function initializeTriggers()
        for _, objective in ipairs(TRIGGER_OBJECTIVES) do
            commands.exec("/scoreboard objectives add " .. objective .. " trigger")
            commands.exec("/scoreboard players set @a " .. objective .. " 0")
        end
        commands.exec("/scoreboard objectives add " .. SESSION_AGE_OBJECTIVE .. " dummy")
        commands.exec("/scoreboard players set @a " .. SESSION_AGE_OBJECTIVE .. " 0")
    end

    log("Book respawn service started")
    initializeTriggers()

    local function clearSession(target)
        for _, objective in ipairs(TRIGGER_OBJECTIVES) do
            resetTrigger(target, objective)
        end
        resetTrigger(target, SESSION_AGE_OBJECTIVE)
        commands.exec("/tag " .. target .. " remove grandop_book")
        commands.exec("/tag " .. target .. " remove grandop_resp_red")
        commands.exec("/tag " .. target .. " remove grandop_resp_blue")
        commands.exec("/tag " .. target .. " remove grandop_wait_mode")
        commands.exec("/tag " .. target .. " remove grandop_wait_class")
        commands.exec("/tag " .. target .. " remove grandop_wait_spawn")
        commands.exec("/tag " .. target .. " remove grandop_wait_tank")
        commands.exec("/tag " .. target .. " remove grandop_wait_tank_spawn")
        commands.exec("/tag " .. target .. " remove grandop_processing")
        local maxClasses = 0
        local maxTanks = 0
        for _, faction in pairs(teams) do
            maxClasses = math.max(maxClasses, #factionClasses(data, faction))
            local tankCount = 0
            for _ in pairs((respawn.tanks or {})[faction] or {}) do tankCount = tankCount + 1 end
            maxTanks = math.max(maxTanks, tankCount)
        end
        for i = 1, maxClasses do
            commands.exec("/tag " .. target .. " remove grandop_class_" .. i)
        end
        for i = 1, maxTanks do
            commands.exec("/tag " .. target .. " remove grandop_tank_" .. i)
        end
    end

    local function startModeSession(target, faction, team)
        if not factionBook(target, faction, features.tanks and ctx.radar) then return false end
        enableTrigger(target, MODE_TRIGGER)
        enableTrigger(target, RESET_TRIGGER)
        resetTrigger(target, SESSION_AGE_OBJECTIVE)
        commands.exec("/tag " .. target .. " add grandop_resp_" .. team:lower())
        commands.exec("/tag " .. target .. " add grandop_wait_mode")
        commands.exec("/tag " .. target .. " add grandop_book")
        return true
    end

    local function restartSession(target, faction, team, reason)
        clearSession(target)
        if startModeSession(target, faction, team) then
            log("Reset respawn session for " .. team .. ": " .. reason)
        end
    end

    local function recoverStaleSession(team, area)
        local prefix = "@a[team=" .. team .. ",x=" .. area.x .. ",y=" .. area.y .. ",z=" .. area.z .. ",distance=.." .. area.radius .. ",tag=grandop_book"
        local expected = "grandop_resp_" .. team:lower()
        local invalid = prefix .. ",tag=!" .. expected .. "]"
        local processing = prefix .. ",tag=grandop_processing]"
        local timedOut = prefix .. ",scores={" .. SESSION_AGE_OBJECTIVE .. "=" .. SESSION_TIMEOUT .. "..}]"
        local validMode = prefix .. ",tag=" .. expected .. ",tag=grandop_wait_mode,tag=!grandop_wait_class,tag=!grandop_wait_spawn,tag=!grandop_wait_tank,tag=!grandop_wait_tank_spawn,tag=!grandop_processing]"
        local validClass = prefix .. ",tag=" .. expected .. ",tag=!grandop_wait_mode,tag=grandop_wait_class,tag=!grandop_wait_spawn,tag=!grandop_wait_tank,tag=!grandop_wait_tank_spawn,tag=!grandop_processing]"
        local validSpawn = prefix .. ",tag=" .. expected .. ",tag=!grandop_wait_mode,tag=!grandop_wait_class,tag=grandop_wait_spawn,tag=!grandop_wait_tank,tag=!grandop_wait_tank_spawn,tag=!grandop_processing]"
        local validTank = prefix .. ",tag=" .. expected .. ",tag=!grandop_wait_mode,tag=!grandop_wait_class,tag=!grandop_wait_spawn,tag=grandop_wait_tank,tag=!grandop_wait_tank_spawn,tag=!grandop_processing]"
        local validTankSpawn = prefix .. ",tag=" .. expected .. ",tag=!grandop_wait_mode,tag=!grandop_wait_class,tag=!grandop_wait_spawn,tag=!grandop_wait_tank,tag=grandop_wait_tank_spawn,tag=!grandop_processing]"
        local knownValid = prefix .. ",tag=" .. expected .. ",tag=!grandop_processing]"

        if commands.exec("execute if entity " .. invalid) then
            restartSession(invalid, factionForTeam(mission, team), team, "team marker mismatch")
        elseif commands.exec("execute if entity " .. processing) then
            restartSession(processing, factionForTeam(mission, team), team, "abandoned processing state")
        elseif commands.exec("execute if entity " .. timedOut) then
            restartSession(timedOut, factionForTeam(mission, team), team, "session timeout")
        elseif commands.exec("execute if entity " .. knownValid) and not (
            commands.exec("execute if entity " .. validMode) or
            commands.exec("execute if entity " .. validClass) or
            commands.exec("execute if entity " .. validSpawn) or
            commands.exec("execute if entity " .. validTank) or
            commands.exec("execute if entity " .. validTankSpawn)
        ) then
            restartSession(knownValid, factionForTeam(mission, team), team, "invalid phase tags")
        end
    end

    -- A restarted controller must not inherit stale session tags from the
    -- previous run for players already standing in a staging room.
    for team in pairs(teams) do
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if area then clearSession(selectorForTeam(team, area)) end
    end

    local function initializePlayer(team)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        recoverStaleSession(team, area)
        local selector = selectorForTeam(team, area, "tag=!grandop_book")
        local present = commands.exec("execute if entity " .. selector)
        if stagingStatus[team] ~= present then
            stagingStatus[team] = present
            log("Staging scan " .. team .. " at " .. area.x .. "," .. area.y .. "," .. area.z .. ": " .. tostring(present))
        end
        if not present then return end
        startModeSession(selector, faction, team)
    end

    local function processMode(team, mode)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local selector = triggerSelector(team, "grandop_wait_mode", MODE_TRIGGER, mode)
        if not commands.exec("execute if entity " .. selector) then return end
        commands.exec("/tag " .. selector .. " add grandop_processing")
        local target = processingSelector(team)
        resetTrigger(target, MODE_TRIGGER)
        resetTrigger(target, SESSION_AGE_OBJECTIVE)
        if mode == 1 then
            log("Mode selected: " .. faction .. " infantry")
            if classBook(area, data, faction, team, target) then
                commands.exec("/tag " .. target .. " add grandop_wait_class")
                commands.exec("/tag " .. target .. " remove grandop_wait_mode")
                enableTrigger(target, CLASS_TRIGGER)
            else
                commands.exec("/tellraw " .. target .. " {\"text\":\"No infantry classes are available\",\"color\":\"red\"}")
                restartSession(target, faction, team, "no infantry classes")
            end
        elseif features.tanks then
            log("Mode selected: " .. faction .. " tank")
            if tankBook(area, faction, team, respawn.tanks, target) then
                commands.exec("/tag " .. target .. " add grandop_wait_tank")
                commands.exec("/tag " .. target .. " remove grandop_wait_mode")
                enableTrigger(target, TANK_TRIGGER)
            else
                commands.exec("/tellraw " .. target .. " {\"text\":\"No tanks are available\",\"color\":\"red\"}")
                restartSession(target, faction, team, "no tanks")
            end
        end
        commands.exec("/tag " .. target .. " remove grandop_processing")
    end

    local function processClass(team, classIndex)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local classes = factionClasses(data, faction)
        local className = classes[classIndex]
        if not className then return end
        local selector = triggerSelector(team, "grandop_wait_class", CLASS_TRIGGER, classIndex)
        if not commands.exec("execute if entity " .. selector) then return end
        commands.exec("/tag " .. selector .. " add grandop_processing")
        local target = processingSelector(team)
        resetTrigger(target, CLASS_TRIGGER)
        resetTrigger(target, SESSION_AGE_OBJECTIVE)
        log("Class selected: " .. className)
        if spawnBook(area, respawn, faction, team, ctx.stage, target) then
            commands.exec("/tag " .. target .. " add grandop_class_" .. classIndex)
            commands.exec("/tag " .. target .. " add grandop_wait_spawn")
            commands.exec("/tag " .. target .. " remove grandop_wait_class")
            enableTrigger(target, SPAWN_TRIGGER)
        else
            commands.exec("/tellraw " .. target .. " {\"text\":\"No infantry spawns are available\",\"color\":\"red\"}")
            restartSession(target, faction, team, "no infantry spawns")
        end
        commands.exec("/tag " .. target .. " remove grandop_processing")
    end

    local function processSpawn(team, classIndex, spawnIndex)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local classes = factionClasses(data, faction)
        local className = classes[classIndex]
        local spawnList = respawn.infantrySpawns[faction] and respawn.infantrySpawns[faction][ctx.stage.current] or {}
        local spawn = spawnList[spawnIndex]
        if not className or not spawn then return end
        local selector = triggerSelector(team, "grandop_wait_spawn", SPAWN_TRIGGER, spawnIndex, "grandop_class_" .. classIndex)
        if not commands.exec("execute if entity " .. selector) then return end
        log("Infantry spawn selected: " .. faction .. " " .. spawn.name)
        if respawn.canDeploy and not respawn.canDeploy(faction, "infantry", spawn.name) then
            resetTrigger(selector, SPAWN_TRIGGER)
            enableTrigger(selector, SPAWN_TRIGGER)
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Respawn quota exhausted\",\"color\":\"red\"}")
            return
        end
        commands.exec("/tag " .. selector .. " add grandop_processing")
        local target = processingSelector(team)
        resetTrigger(target, SPAWN_TRIGGER)
        resetTrigger(target, SESSION_AGE_OBJECTIVE)
        commands.exec("/gamemode survival " .. target)
        loadout.applyClass(data, className, target)
        randomTeleport(target, spawn, respawn.spawnRadius)
        local spawned = stevesArmy.spawnSquadmates(target, className, data)
        if spawned > 0 then log("Spawned " .. spawned .. " squadmates for " .. faction .. " " .. className) end
        if respawn.consumeDeployment then respawn.consumeDeployment(faction, "infantry", spawn.name) end
        if ctx.checkpoint then ctx.checkpoint("infantry deployment") end
        if respawn.displayScoreboard then respawn.displayScoreboard() end
        commands.exec("/effect give " .. target .. " minecraft:resistance 4 10")
        clearSession(target)
    end

    local function tankNamesForFaction(faction)
        local names = {}
        for name, config in pairs(respawn.tanks[faction] or {}) do
            if (config.stock or 0) > 0 then table.insert(names, name) end
        end
        table.sort(names)
        return names
    end

    local vehicles
    local v
    if features.tanks then
        vehicles = grandopRequire("lib.respawn.vehicles")
        v = vehicles.newState(respawn.tanks or {})
    end

    local function processTank(team, tankIndex)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local tankName = tankNamesForFaction(faction)[tankIndex]
        local selector = triggerSelector(team, "grandop_wait_tank", TANK_TRIGGER, tankIndex)
        if not tankName or not commands.exec("execute if entity " .. selector) then return end
        log("Tank selected: " .. faction .. " " .. tankName)
        commands.exec("/tag " .. selector .. " add grandop_processing")
        local target = processingSelector(team)
        resetTrigger(target, TANK_TRIGGER)
        resetTrigger(target, SESSION_AGE_OBJECTIVE)
        commands.exec("/tag " .. target .. " add grandop_tank_" .. tankIndex)
        commands.exec("/tag " .. target .. " add grandop_wait_tank_spawn")
        commands.exec("/tag " .. target .. " remove grandop_wait_tank")
        if tankSpawnBook(area, respawn, faction, team, target) then
            enableTrigger(target, TANK_SPAWN_TRIGGER)
        else
            commands.exec("/tellraw " .. target .. " {\"text\":\"No tank spawns are available\",\"color\":\"red\"}")
            restartSession(target, faction, team, "no tank spawns")
        end
        commands.exec("/tag " .. target .. " remove grandop_processing")
    end

    local function processTankSpawn(team, tankIndex, spawnIndex)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local tankName = tankNamesForFaction(faction)[tankIndex]
        local spawn = respawn.vehicleSpawns[faction] and respawn.vehicleSpawns[faction][spawnIndex]
        local selector = triggerSelector(team, "grandop_wait_tank_spawn", TANK_SPAWN_TRIGGER, spawnIndex, "grandop_tank_" .. tankIndex)
        if not tankName or not spawn or not commands.exec("execute if entity " .. selector) then return end
        log("Tank spawn selected: " .. faction .. " " .. tankName .. " -> " .. spawn.name)
        if vehicles.timeToNext(v, faction, tankName) > 0 then
            resetTrigger(selector, TANK_SPAWN_TRIGGER)
            enableTrigger(selector, TANK_SPAWN_TRIGGER)
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Tank cooldown active\",\"color\":\"red\"}")
            return
        end
        if respawn.canDeploy and not respawn.canDeploy(faction, "tank") then
            resetTrigger(selector, TANK_SPAWN_TRIGGER)
            enableTrigger(selector, TANK_SPAWN_TRIGGER)
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Respawn quota exhausted\",\"color\":\"red\"}")
            return
        end
        commands.exec("/tag " .. selector .. " add grandop_processing")
        local target = processingSelector(team)
        resetTrigger(target, TANK_SPAWN_TRIGGER)
        resetTrigger(target, SESSION_AGE_OBJECTIVE)
        local deployed = vehicles.spawnTank({
            v = v,
            country = faction,
            monitor = ctx.monitor,
            radar = ctx.radar,
            player = target,
            mission = respawn,
            spawnPoint = spawn,
            tankName = tankName,
            playerTankMap = state.playerTankMap,
            tankslugtoID = state.tankslugtoID,
            repairKits = data.repair_kits or {},
            tankListFile = respawn.tankListFile or "tanksList.txt",
            checkpoint = ctx.checkpoint,
        })
        if deployed then
            vehicles.tryConsume(v, faction, tankName)
            if respawn.consumeDeployment then respawn.consumeDeployment(faction, "tank") end
            if ctx.checkpoint then ctx.checkpoint("tank deployment") end
            if respawn.displayScoreboard then respawn.displayScoreboard() end
            clearSession(target)
        else
            commands.exec("/tellraw " .. target .. " {\"text\":\"Tank deployment failed\",\"color\":\"red\"}")
            clearSession(target)
            startModeSession(target, faction, team)
        end
    end

    local nextCleanup = 0
    local nextStagingScan = 0
    local observedStage = ctx.stage.current
    local function hasWaiting(team, tag)
        return commands.exec("execute if entity @a[team=" .. team .. ",tag=" .. tag .. "]")
    end

    while true do
        if os.clock() >= nextCleanup then
            if observedStage ~= ctx.stage.current then
                clearSession("@a[tag=grandop_book]")
                observedStage = ctx.stage.current
                log("Cleared respawn sessions after stage change")
            end
            commands.exec("/scoreboard players add @a[tag=grandop_book] " .. SESSION_AGE_OBJECTIVE .. " 1")
            for team in pairs(teams) do
                local faction = factionForTeam(mission, team)
                local area = stagingArea(respawn, faction, ctx.stage)
                local outside = area and "@a[team=" .. team .. ",x=" .. area.x .. ",y=" .. area.y .. ",z=" .. area.z .. ",distance=" .. (area.radius + 1) .. "..]"
                if outside and commands.exec("execute if entity " .. outside) then
                    clearSession(outside)
                end
            end
            nextCleanup = os.clock() + 1
        end
        if os.clock() >= nextStagingScan then
            for team in pairs(teams) do initializePlayer(team) end
            nextStagingScan = os.clock() + 0.5
        end
        for team in pairs(teams) do
            local faction = factionForTeam(mission, team)
            local area = stagingArea(respawn, faction, ctx.stage)
            local reset = area and selectorForTeam(team, area, "scores={" .. RESET_TRIGGER .. "=1..}")
            if reset and commands.exec("execute if entity " .. reset) then
                restartSession(reset, faction, team, "player requested reset")
            end
        end
        for team in pairs(teams) do
            processMode(team, 1)
            if features.tanks then processMode(team, 2) end
            if hasWaiting(team, "grandop_wait_class") then
                for i = 1, #(factionClasses(data, factionForTeam(mission, team))) do
                    processClass(team, i)
                end
            end
            if hasWaiting(team, "grandop_wait_spawn") then
                for i = 1, #(factionClasses(data, factionForTeam(mission, team))) do
                    for s = 1, #(respawn.infantrySpawns[factionForTeam(mission, team)] and respawn.infantrySpawns[factionForTeam(mission, team)][ctx.stage.current] or {}) do
                        processSpawn(team, i, s)
                    end
                end
            end
            if features.tanks then
                if hasWaiting(team, "grandop_wait_tank") then
                    for i = 1, #tankNamesForFaction(factionForTeam(mission, team)) do
                        processTank(team, i)
                    end
                end
                if hasWaiting(team, "grandop_wait_tank_spawn") then
                    for i = 1, #tankNamesForFaction(factionForTeam(mission, team)) do
                        for s = 1, #(respawn.vehicleSpawns[factionForTeam(mission, team)] or {}) do
                            processTankSpawn(team, i, s)
                        end
                    end
                end
            end
        end
        sleep(0.05)
    end
end

return book
