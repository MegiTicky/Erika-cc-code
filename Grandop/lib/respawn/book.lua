-- Grandop written-book respawn service.
-- Players choose class and spawn with trigger objectives. Privileged actions
-- are still performed by the command computer.

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

local function snbtString(value)
    -- Book pages are JSON strings nested inside a quoted SNBT string. Escape
    -- the JSON backslashes once more so Minecraft receives valid page JSON.
    return "'" .. tostring(value):gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end

local function giveBook(target, title, page)
    local pageJson = json(page)
    local item = "minecraft:written_book{title:" .. snbtString(title) ..
        ",author:" .. snbtString("Grand Operation") ..
        ",pages:[" .. snbtString(pageJson) .. "]}"
    local ok, reason, affected = commands.exec("/item replace entity " .. target .. " weapon.mainhand with " .. item)
    if not ok then
        print("Book delivery failed (" .. title .. "): " .. textutils.serialise(reason))
    elseif (affected or 0) > 0 then
        print("Book delivered (" .. title .. "): " .. tostring(affected or 0))
    end
    return ok
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

local function addObjective(name)
    commands.exec("/scoreboard objectives add " .. name .. " trigger")
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
        { label = "Infantry", command = "/trigger grandop_mode set 1", color = "green" },
    }
    if allowTanks then
        table.insert(mode, { label = "Tank", command = "/trigger grandop_mode set 2", color = "gray" })
    end
    return giveBook(target, faction .. " Respawn", page(faction .. " Respawn", mode))
end

local function classBook(area, data, faction, team)
    local entries = {}
    for i, className in ipairs(factionClasses(data, faction)) do
        local short = className:sub(#faction + 2)
        table.insert(entries, { label = short, command = "/trigger grandop_class set " .. i })
    end
    if #entries > 0 then
        giveBook(waitingSelector(team, "grandop_wait_class"), faction .. " Class", page("Choose Class", entries))
    end
end

local function tankBook(area, faction, team, tanks)
    local entries = {}
    local list = tanks[faction] or {}
    local names = {}
    for name, value in pairs(list) do
        if (value.stock or 0) > 0 then table.insert(names, name) end
    end
    table.sort(names)
    for i, name in ipairs(names) do
        table.insert(entries, { label = name .. " (" .. list[name].stock .. ")", command = "/trigger grandop_tank set " .. i })
    end
    if #entries > 0 then
        giveBook(waitingSelector(team, "grandop_wait_tank"), faction .. " Tanks", page("Choose Tank", entries))
    end
end

local function spawnBook(area, respawn, faction, team, stage)
    local entries = {}
    local list = respawn.infantrySpawns[faction] and respawn.infantrySpawns[faction][stage.current] or {}
    for i, spawn in ipairs(list) do
        table.insert(entries, { label = spawn.name, command = "/trigger grandop_spawn set " .. i })
    end
    if #entries > 0 then
        giveBook(waitingSelector(team, "grandop_wait_spawn"), faction .. " Spawn", page("Choose Spawn", entries))
    end
end

local function tankSpawnBook(area, respawn, faction, team)
    local entries = {}
    local list = respawn.vehicleSpawns[faction] or {}
    for i, spawn in ipairs(list) do
        table.insert(entries, { label = spawn.name, command = "/trigger grandop_tank_spawn set " .. i })
    end
    if #entries > 0 then
        giveBook(waitingSelector(team, "grandop_wait_tank_spawn"), faction .. " Tank Spawn", page("Choose Tank Spawn", entries))
    end
end

local function processingSelector(team)
    return "@a[team=" .. team .. ",tag=grandop_processing,limit=1]"
end

local function candidateSelector(team, scoreName, score, tag, secondScoreName, secondScore)
    local scores = scoreName .. "=" .. score
    if secondScoreName then scores = scores .. "," .. secondScoreName .. "=" .. secondScore end
    -- The book click closes the GUI before the next tick. Use the session tag
    -- and score as the authoritative state, not the player's exact location.
    return "@a[team=" .. team .. ",tag=" .. tag .. ",scores={" .. scores .. "},limit=1]"
end

local function randomTeleport(target, spawn, radius)
    if spawn.name == "USCommander" then
        commands.exec("/tp " .. target .. " @a[tag=USCom,limit=1]")
    elseif spawn.name == "JPCommander" then
        commands.exec("/tp " .. target .. " @a[tag=JPCom,limit=1]")
    else
        commands.exec("/spreadplayers " .. spawn.x .. " " .. spawn.z .. " 0 " .. (radius or 10) .. " false " .. target)
        commands.exec("/tp " .. target .. " ~ " .. spawn.y .. " ~")
    end
end

function book.run(ctx)
    local mission = ctx.mission
    local respawn = ctx.respawn
    local data = ctx.loadoutData
    local state = ctx.state
    local teams = ctx.teams
    local features = ctx.features
    local modeObjective = "grandop_mode"
    local classObjective = "grandop_class"
    local spawnObjective = "grandop_spawn"
    local tankObjective = "grandop_tank"
    local tankSpawnObjective = "grandop_tank_spawn"
    local stagingStatus = {}

    print("Book respawn service started")

    addObjective(modeObjective)
    addObjective(classObjective)
    addObjective(spawnObjective)
    if features.tanks then
        addObjective(tankObjective)
        addObjective(tankSpawnObjective)
    end

    local function clearSession(target)
        commands.exec("/tag " .. target .. " remove grandop_book")
        commands.exec("/tag " .. target .. " remove grandop_wait_mode")
        commands.exec("/tag " .. target .. " remove grandop_wait_class")
        commands.exec("/tag " .. target .. " remove grandop_wait_spawn")
        commands.exec("/tag " .. target .. " remove grandop_wait_tank")
        commands.exec("/tag " .. target .. " remove grandop_wait_tank_spawn")
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
            print("Staging scan " .. team .. " at " .. area.x .. "," .. area.y .. "," .. area.z .. ": " .. tostring(present))
        end
        if not present then return end
        if factionBook(selector, faction, features.tanks and ctx.radar) then
            commands.exec("/tag " .. selector .. " add grandop_book")
            commands.exec("/tag " .. selector .. " add grandop_wait_mode")
            commands.exec("/scoreboard players set " .. selector .. " " .. modeObjective .. " 0")
            commands.exec("/scoreboard players set " .. selector .. " " .. classObjective .. " 0")
            commands.exec("/scoreboard players set " .. selector .. " " .. spawnObjective .. " 0")
        end
    end

    local function processMode(team, mode)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local selector = candidateSelector(team, modeObjective, mode, "grandop_wait_mode")
        if not commands.exec("execute if entity " .. selector) then return end
        commands.exec("/tag " .. selector .. " remove grandop_wait_mode")
        if mode == 1 then
            print("Mode selected: " .. faction .. " infantry")
            commands.exec("/tag " .. selector .. " add grandop_wait_class")
            classBook(area, data, faction, team)
        elseif features.tanks then
            print("Mode selected: " .. faction .. " tank")
            commands.exec("/tag " .. selector .. " add grandop_wait_tank")
            tankBook(area, faction, team, respawn.tanks)
        end
        commands.exec("/scoreboard players set " .. selector .. " " .. modeObjective .. " 0")
    end

    local function processClass(team, classIndex)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local classes = factionClasses(data, faction)
        local className = classes[classIndex]
        if not className then return end
        local selector = candidateSelector(team, classObjective, classIndex, "grandop_wait_class")
        if not commands.exec("execute if entity " .. selector) then return end
        print("Class selected: " .. className)
        commands.exec("/tag " .. selector .. " remove grandop_wait_class")
        commands.exec("/tag " .. selector .. " add grandop_wait_spawn")
        spawnBook(area, respawn, faction, team, ctx.stage)
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
        local selector = candidateSelector(team, spawnObjective, spawnIndex, "grandop_wait_spawn", classObjective, classIndex)
        if not commands.exec("execute if entity " .. selector) then return end
        print("Infantry spawn selected: " .. faction .. " " .. spawn.name)
        if respawn.canDeploy and not respawn.canDeploy(faction, "infantry", spawn.name) then
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Respawn quota exhausted\",\"color\":\"red\"}")
            return
        end
        commands.exec("/tag " .. selector .. " add grandop_processing")
        local target = processingSelector(team)
        loadout.applyClass(data, className, target)
        randomTeleport(target, spawn, respawn.spawnRadius)
        if respawn.consumeDeployment then respawn.consumeDeployment(faction, "infantry", spawn.name) end
        commands.exec("/effect give " .. target .. " minecraft:resistance 4 10")
        commands.exec("/clear " .. target .. " minecraft:written_book")
        commands.exec("/scoreboard players set " .. target .. " " .. classObjective .. " 0")
        commands.exec("/scoreboard players set " .. target .. " " .. spawnObjective .. " 0")
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
        local selector = candidateSelector(team, tankObjective, tankIndex, "grandop_wait_tank")
        if not tankName or not commands.exec("execute if entity " .. selector) then return end
        print("Tank selected: " .. faction .. " " .. tankName)
        commands.exec("/tag " .. selector .. " remove grandop_wait_tank")
        commands.exec("/tag " .. selector .. " add grandop_wait_tank_spawn")
        tankSpawnBook(area, respawn, faction, team)
    end

    local function processTankSpawn(team, tankIndex, spawnIndex)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        local tankName = tankNamesForFaction(faction)[tankIndex]
        local spawn = respawn.vehicleSpawns[faction] and respawn.vehicleSpawns[faction][spawnIndex]
        local selector = candidateSelector(team, tankSpawnObjective, spawnIndex, "grandop_wait_tank_spawn", tankObjective, tankIndex)
        if not tankName or not spawn or not commands.exec("execute if entity " .. selector) then return end
        print("Tank spawn selected: " .. faction .. " " .. tankName .. " -> " .. spawn.name)
        if vehicles.timeToNext(v, faction, tankName) > 0 then
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Tank cooldown active\",\"color\":\"red\"}")
            return
        end
        if respawn.canDeploy and not respawn.canDeploy(faction, "tank") then
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Respawn quota exhausted\",\"color\":\"red\"}")
            return
        end
        commands.exec("/tag " .. selector .. " add grandop_processing")
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
        })
        if deployed then
            vehicles.tryConsume(v, faction, tankName)
            if respawn.consumeDeployment then respawn.consumeDeployment(faction, "tank") end
            commands.exec("/clear " .. target .. " minecraft:written_book")
            commands.exec("/scoreboard players set " .. target .. " " .. tankObjective .. " 0")
            commands.exec("/scoreboard players set " .. target .. " " .. tankSpawnObjective .. " 0")
            commands.exec("/tag " .. target .. " remove grandop_wait_tank_spawn")
        else
            commands.exec("/tellraw " .. target .. " {\"text\":\"Tank deployment failed\",\"color\":\"red\"}")
            commands.exec("/clear " .. target .. " minecraft:written_book")
            commands.exec("/scoreboard players set " .. target .. " " .. tankObjective .. " 0")
            commands.exec("/scoreboard players set " .. target .. " " .. tankSpawnObjective .. " 0")
            commands.exec("/tag " .. target .. " remove grandop_wait_tank_spawn")
            commands.exec("/tag " .. target .. " add grandop_wait_mode")
            factionBook(target, faction, features.tanks and ctx.radar)
        end
        commands.exec("/tag " .. target .. " remove grandop_processing")
    end

    local function enableTriggers()
        commands.exec("/scoreboard players enable @a " .. modeObjective)
        commands.exec("/scoreboard players enable @a " .. classObjective)
        commands.exec("/scoreboard players enable @a " .. spawnObjective)
        if features.tanks then
            commands.exec("/scoreboard players enable @a " .. tankObjective)
            commands.exec("/scoreboard players enable @a " .. tankSpawnObjective)
        end
    end

    local function refreshBooks(team)
        local faction = factionForTeam(mission, team)
        local area = stagingArea(respawn, faction, ctx.stage)
        if not area then return end
        factionBook(waitingSelector(team, "grandop_wait_mode"), faction, features.tanks and ctx.radar)
        classBook(area, data, faction, team)
        if features.tanks then
            tankBook(area, faction, team, respawn.tanks)
            tankSpawnBook(area, respawn, faction, team)
        end
        spawnBook(area, respawn, faction, team, ctx.stage)
    end

    while true do
        enableTriggers()
        for team in pairs(teams) do
            local faction = factionForTeam(mission, team)
            local area = stagingArea(respawn, faction, ctx.stage)
            local outside = area and "@a[team=" .. team .. ",x=" .. area.x .. ",y=" .. area.y .. ",z=" .. area.z .. ",distance=" .. (area.radius + 1) .. "..]"
            if outside then
                clearSession(outside)
            end
        end
        for team in pairs(teams) do initializePlayer(team) end
        for team in pairs(teams) do
            processMode(team, 1)
            if features.tanks then processMode(team, 2) end
            for i = 1, #(factionClasses(data, factionForTeam(mission, team))) do
                processClass(team, i)
                for s = 1, #(respawn.infantrySpawns[factionForTeam(mission, team)] and respawn.infantrySpawns[factionForTeam(mission, team)][ctx.stage.current] or {}) do
                    processSpawn(team, i, s)
                end
            end
            if features.tanks then
                for i = 1, #tankNamesForFaction(factionForTeam(mission, team)) do
                    processTank(team, i)
                    for s = 1, #(respawn.vehicleSpawns[factionForTeam(mission, team)] or {}) do
                        processTankSpawn(team, i, s)
                    end
                end
            end
        end
        for team in pairs(teams) do refreshBooks(team) end
        sleep(0.2)
    end
end

return book
