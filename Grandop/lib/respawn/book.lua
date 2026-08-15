-- Grandop chat-menu respawn service.
-- Players choose class and spawn with tellraw buttons. Privileged actions are
-- still performed by the command computer.

local loadout = grandopRequire("lib.loadout")

local book = {}

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
        { label = "Infantry", command = "/tag @s add grandop_select_mode_infantry", color = "green" },
    }
    if allowTanks then
        table.insert(mode, { label = "Tank", command = "/tag @s add grandop_select_mode_tank", color = "gray" })
    end
    return sendMenu(target, faction .. " Respawn", mode)
end

local function classBook(area, data, faction, team, target)
    local entries = {}
    for i, className in ipairs(factionClasses(data, faction)) do
        local short = className:sub(#faction + 2)
        table.insert(entries, { label = short, command = "/tag @s add grandop_select_class_" .. i })
    end
    if #entries > 0 then
        sendMenu(target or waitingSelector(team, "grandop_wait_class"), "Choose " .. faction .. " Class", entries)
    end
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
        table.insert(entries, { label = name .. " (" .. list[name].stock .. ")", command = "/tag @s add grandop_select_tank_" .. i })
    end
    if #entries > 0 then
        sendMenu(target or waitingSelector(team, "grandop_wait_tank"), "Choose " .. faction .. " Tank", entries)
    end
end

local function spawnBook(area, respawn, faction, team, stage, target)
    local entries = {}
    local list = respawn.infantrySpawns[faction] and respawn.infantrySpawns[faction][stage.current] or {}
    for i, spawn in ipairs(list) do
        if not respawn.canDeploy or respawn.canDeploy(faction, "infantry", spawn.name) then
            table.insert(entries, { label = spawn.name, command = "/tag @s add grandop_select_spawn_" .. i })
        end
    end
    if #entries > 0 then
        sendMenu(target or waitingSelector(team, "grandop_wait_spawn"), "Choose " .. faction .. " Spawn", entries)
    end
end

local function tankSpawnBook(area, respawn, faction, team, target)
    local entries = {}
    local list = respawn.vehicleSpawns[faction] or {}
    for i, spawn in ipairs(list) do
        table.insert(entries, { label = spawn.name, command = "/tag @s add grandop_select_tank_spawn_" .. i })
    end
    if #entries > 0 then
        sendMenu(target or waitingSelector(team, "grandop_wait_tank_spawn"), "Choose " .. faction .. " Tank Spawn", entries)
    end
end

local function processingSelector(team)
    return "@a[team=" .. team .. ",tag=grandop_processing,limit=1]"
end

local function selectionSelector(team, waitTag, selectionTag, savedTag)
    local selector = "@a[team=" .. team .. ",tag=" .. waitTag .. ",tag=" .. selectionTag
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

    log("Book respawn service started")

    local function clearSession(target)
        commands.exec("/tag " .. target .. " remove grandop_book")
        commands.exec("/tag " .. target .. " remove grandop_wait_mode")
        commands.exec("/tag " .. target .. " remove grandop_wait_class")
        commands.exec("/tag " .. target .. " remove grandop_wait_spawn")
        commands.exec("/tag " .. target .. " remove grandop_wait_tank")
        commands.exec("/tag " .. target .. " remove grandop_wait_tank_spawn")
        commands.exec("/tag " .. target .. " remove grandop_select_mode_infantry")
        commands.exec("/tag " .. target .. " remove grandop_select_mode_tank")
        for i = 1, #factionClasses(data, factionForTeam(mission, "Blue")) do
            commands.exec("/tag " .. target .. " remove grandop_select_class_" .. i)
            commands.exec("/tag " .. target .. " remove grandop_class_" .. i)
        end
        for i = 1, 10 do
            commands.exec("/tag " .. target .. " remove grandop_select_spawn_" .. i)
            commands.exec("/tag " .. target .. " remove grandop_select_tank_" .. i)
            commands.exec("/tag " .. target .. " remove grandop_tank_" .. i)
            commands.exec("/tag " .. target .. " remove grandop_select_tank_spawn_" .. i)
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
        local selector = selectorForTeam(team, area, "tag=!grandop_book")
        local present = commands.exec("execute if entity " .. selector)
        if stagingStatus[team] ~= present then
            stagingStatus[team] = present
            log("Staging scan " .. team .. " at " .. area.x .. "," .. area.y .. "," .. area.z .. ": " .. tostring(present))
        end
        if not present then return end
        if factionBook(selector, faction, features.tanks and ctx.radar) then
            commands.exec("/tag " .. selector .. " add grandop_wait_mode")
            commands.exec("/tag " .. selector .. " add grandop_book")
        end
    end

    local function processMode(team, mode)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local selection = mode == 1 and "grandop_select_mode_infantry" or "grandop_select_mode_tank"
        local selector = selectionSelector(team, "grandop_wait_mode", selection)
        if not commands.exec("execute if entity " .. selector) then return end
        if mode == 1 then
            log("Mode selected: " .. faction .. " infantry")
            classBook(area, data, faction, team, selector)
            commands.exec("/tag " .. selector .. " add grandop_wait_class")
            commands.exec("/tag " .. selector .. " remove grandop_wait_mode")
            commands.exec("/tag " .. selector .. " remove " .. selection)
        elseif features.tanks then
            log("Mode selected: " .. faction .. " tank")
            tankBook(area, faction, team, respawn.tanks, selector)
            commands.exec("/tag " .. selector .. " add grandop_wait_tank")
            commands.exec("/tag " .. selector .. " remove grandop_wait_mode")
            commands.exec("/tag " .. selector .. " remove " .. selection)
        end
    end

    local function processClass(team, classIndex)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local classes = factionClasses(data, faction)
        local className = classes[classIndex]
        if not className then return end
        local selector = selectionSelector(team, "grandop_wait_class", "grandop_select_class_" .. classIndex)
        if not commands.exec("execute if entity " .. selector) then return end
        log("Class selected: " .. className)
        spawnBook(area, respawn, faction, team, ctx.stage, selector)
        commands.exec("/tag " .. selector .. " add grandop_class_" .. classIndex)
        commands.exec("/tag " .. selector .. " add grandop_wait_spawn")
        commands.exec("/tag " .. selector .. " remove grandop_wait_class")
        commands.exec("/tag " .. selector .. " remove grandop_select_class_" .. classIndex)
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
        local selector = selectionSelector(team, "grandop_wait_spawn", "grandop_select_spawn_" .. spawnIndex, "grandop_class_" .. classIndex)
        if not commands.exec("execute if entity " .. selector) then return end
        log("Infantry spawn selected: " .. faction .. " " .. spawn.name)
        if respawn.canDeploy and not respawn.canDeploy(faction, "infantry", spawn.name) then
            commands.exec("/tag " .. selector .. " remove grandop_select_spawn_" .. spawnIndex)
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Respawn quota exhausted\",\"color\":\"red\"}")
            return
        end
        commands.exec("/tag " .. selector .. " add grandop_processing")
        commands.exec("/tag " .. selector .. " remove grandop_select_spawn_" .. spawnIndex)
        local target = processingSelector(team)
        commands.exec("/gamemode survival " .. target)
        loadout.applyClass(data, className, target)
        randomTeleport(target, spawn, respawn.spawnRadius)
        if respawn.consumeDeployment then respawn.consumeDeployment(faction, "infantry", spawn.name) end
        if ctx.checkpoint then ctx.checkpoint("infantry deployment") end
        if respawn.displayScoreboard then respawn.displayScoreboard() end
        commands.exec("/effect give " .. target .. " minecraft:resistance 4 10")
        commands.exec("/tag " .. target .. " remove grandop_class_" .. classIndex)
        commands.exec("/tag " .. target .. " remove grandop_processing")
        commands.exec("/tag " .. target .. " remove grandop_wait_spawn")
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
        local selector = selectionSelector(team, "grandop_wait_tank", "grandop_select_tank_" .. tankIndex)
        if not tankName or not commands.exec("execute if entity " .. selector) then return end
        log("Tank selected: " .. faction .. " " .. tankName)
        commands.exec("/tag " .. selector .. " add grandop_tank_" .. tankIndex)
        commands.exec("/tag " .. selector .. " add grandop_wait_tank_spawn")
        commands.exec("/tag " .. selector .. " remove grandop_wait_tank")
        commands.exec("/tag " .. selector .. " remove grandop_select_tank_" .. tankIndex)
        tankSpawnBook(area, respawn, faction, team, selector)
    end

    local function processTankSpawn(team, tankIndex, spawnIndex)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local tankName = tankNamesForFaction(faction)[tankIndex]
        local spawn = respawn.vehicleSpawns[faction] and respawn.vehicleSpawns[faction][spawnIndex]
        local selector = selectionSelector(team, "grandop_wait_tank_spawn", "grandop_select_tank_spawn_" .. spawnIndex, "grandop_tank_" .. tankIndex)
        if not tankName or not spawn or not commands.exec("execute if entity " .. selector) then return end
        log("Tank spawn selected: " .. faction .. " " .. tankName .. " -> " .. spawn.name)
        if vehicles.timeToNext(v, faction, tankName) > 0 then
            commands.exec("/tag " .. selector .. " remove grandop_select_tank_spawn_" .. spawnIndex)
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Tank cooldown active\",\"color\":\"red\"}")
            return
        end
        if respawn.canDeploy and not respawn.canDeploy(faction, "tank") then
            commands.exec("/tag " .. selector .. " remove grandop_select_tank_spawn_" .. spawnIndex)
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Respawn quota exhausted\",\"color\":\"red\"}")
            return
        end
        commands.exec("/tag " .. selector .. " add grandop_processing")
        commands.exec("/tag " .. selector .. " remove grandop_select_tank_spawn_" .. spawnIndex)
        local target = processingSelector(team)
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
            commands.exec("/tag " .. target .. " remove grandop_tank_" .. tankIndex)
            commands.exec("/tag " .. target .. " remove grandop_wait_tank_spawn")
        else
            commands.exec("/tellraw " .. target .. " {\"text\":\"Tank deployment failed\",\"color\":\"red\"}")
            commands.exec("/tag " .. target .. " remove grandop_tank_" .. tankIndex)
            commands.exec("/tag " .. target .. " remove grandop_wait_tank_spawn")
            commands.exec("/tag " .. target .. " add grandop_wait_mode")
            factionBook(target, faction, features.tanks and ctx.radar)
        end
        commands.exec("/tag " .. target .. " remove grandop_processing")
    end

    local nextCleanup = 0
    local nextStagingScan = 0
    local function hasWaiting(team, tag)
        return commands.exec("execute if entity @a[team=" .. team .. ",tag=" .. tag .. "]")
    end

    while true do
        if os.clock() >= nextCleanup then
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
