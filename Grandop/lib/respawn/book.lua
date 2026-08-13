-- Grandop written-book respawn service.
-- Players choose class and spawn with trigger objectives. Privileged actions
-- are still performed by the command computer.

local loadout = require("lib.loadout")
local vehicles = require("lib.respawn.vehicles")

local book = {}

local function json(value)
    return textutils.serialiseJSON(value)
end

local function selectorForTeam(team, area, extra)
    local s = "@a[team=" .. team .. ",x=" .. area.x .. ",y=" .. area.y .. ",z=" .. area.z .. ",distance=.." .. area.radius
    if extra then s = s .. "," .. extra end
    return s .. "]"
end

local function giveBook(target, title, page)
    local pageJson = json(page)
    local item = "minecraft:written_book{title:" .. json(title) .. ",author:\"Grand Operation\",pages:['" .. pageJson .. "']}"
    commands.exec("/give " .. target .. " " .. item)
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

local function factionBook(cfg, faction, team, allowTanks)
    local mode = {
        { label = "Infantry", command = "/trigger grandop_mode set 1", color = "green" },
    }
    if allowTanks then
        table.insert(mode, { label = "Tank", command = "/trigger grandop_mode set 2", color = "gray" })
    end
    giveBook(selectorForTeam(team, cfg.area, "tag=grandop_wait_mode"), "" .. faction .. " Respawn", page(faction .. " Respawn", mode))
end

local function classBook(cfg, data, faction, team)
    local entries = {}
    for i, className in ipairs(factionClasses(data, faction)) do
        local short = className:sub(#faction + 2)
        table.insert(entries, { label = short, command = "/trigger grandop_class set " .. i })
    end
    if #entries > 0 then
        giveBook(selectorForTeam(team, cfg.area, "tag=grandop_wait_class"), faction .. " Class", page("Choose Class", entries))
    end
end

local function tankBook(cfg, faction, team, tanks)
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
        giveBook(selectorForTeam(team, cfg.area, "tag=grandop_wait_tank"), faction .. " Tanks", page("Choose Tank", entries))
    end
end

local function spawnBook(cfg, respawn, faction, team, stage)
    local entries = {}
    local list = respawn.infantrySpawns[faction] and respawn.infantrySpawns[faction][stage.current] or {}
    for i, spawn in ipairs(list) do
        table.insert(entries, { label = spawn.name, command = "/trigger grandop_spawn set " .. i })
    end
    if #entries > 0 then
        giveBook(selectorForTeam(team, cfg.area, "tag=grandop_wait_spawn"), faction .. " Spawn", page("Choose Spawn", entries))
    end
end

local function tankSpawnBook(cfg, respawn, faction, team)
    local entries = {}
    local list = respawn.coords[faction] or {}
    for i, spawn in ipairs(list) do
        table.insert(entries, { label = spawn.name, command = "/trigger grandop_tank_spawn set " .. i })
    end
    if #entries > 0 then
        giveBook(selectorForTeam(team, cfg.area, "tag=grandop_wait_tank_spawn"), faction .. " Tank Spawn", page("Choose Tank Spawn", entries))
    end
end

local function processingSelector(team)
    return "@a[team=" .. team .. ",tag=grandop_processing,limit=1]"
end

local function candidateSelector(team, scoreName, score, tag, secondScoreName, secondScore)
    local scores = scoreName .. "=" .. score
    if secondScoreName then scores = scores .. "," .. secondScoreName .. "=" .. secondScore end
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
    local respawn = mission.respawn
    local data = ctx.loadoutData
    local state = ctx.state
    local area = respawn.area
    local teams = mission.teams or { Blue = "USMC", Red = "japan" }
    local modeObjective = "grandop_mode"
    local classObjective = "grandop_class"
    local spawnObjective = "grandop_spawn"
    local tankObjective = "grandop_tank"
    local tankSpawnObjective = "grandop_tank_spawn"

    addObjective(modeObjective)
    addObjective(classObjective)
    addObjective(spawnObjective)
    addObjective(tankObjective)
    addObjective(tankSpawnObjective)

    local function initializePlayer(team)
        local faction = factionForTeam(mission, team)
        local selector = selectorForTeam(team, area, "tag=!grandop_book")
        commands.exec("/tag " .. selector .. " add grandop_book")
        commands.exec("/tag " .. selector .. " add grandop_wait_mode")
        commands.exec("/scoreboard players set " .. selector .. " " .. modeObjective .. " 0")
        commands.exec("/scoreboard players set " .. selector .. " " .. classObjective .. " 0")
        commands.exec("/scoreboard players set " .. selector .. " " .. spawnObjective .. " 0")
        factionBook(mission, faction, team, ctx.radar and ctx.monitor)
    end

    local function processMode(team, mode)
        local selector = candidateSelector(team, modeObjective, mode, "grandop_wait_mode")
        if not commands.exec("execute if entity " .. selector) then return end
        local faction = factionForTeam(mission, team)
        commands.exec("/tag " .. selector .. " remove grandop_wait_mode")
        if mode == 1 then
            commands.exec("/tag " .. selector .. " add grandop_wait_class")
            classBook(mission, data, faction, team)
        else
            commands.exec("/tag " .. selector .. " add grandop_wait_tank")
            tankBook(mission, faction, team, respawn.tanks)
        end
        commands.exec("/scoreboard players set " .. selector .. " " .. modeObjective .. " 0")
    end

    local function processClass(team, classIndex)
        local faction = factionForTeam(mission, team)
        local classes = factionClasses(data, faction)
        local className = classes[classIndex]
        if not className then return end
        local selector = candidateSelector(team, classObjective, classIndex, "grandop_wait_class")
        if not commands.exec("execute if entity " .. selector) then return end
        commands.exec("/tag " .. selector .. " remove grandop_wait_class")
        commands.exec("/tag " .. selector .. " add grandop_wait_spawn")
        spawnBook(mission, respawn, faction, team, ctx.stage)
    end

    local function processSpawn(team, classIndex, spawnIndex)
        local faction = factionForTeam(mission, team)
        local classes = factionClasses(data, faction)
        local className = classes[classIndex]
        local spawnList = respawn.infantrySpawns[faction] and respawn.infantrySpawns[faction][ctx.stage.current] or {}
        local spawn = spawnList[spawnIndex]
        if not className or not spawn then return end
        local selector = candidateSelector(team, spawnObjective, spawnIndex, "grandop_wait_spawn", classObjective, classIndex)
        if not commands.exec("execute if entity " .. selector) then return end
        if respawn.hasQuota and not respawn.hasQuota(faction, spawn.name) then
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Respawn quota exhausted\",\"color\":\"red\"}")
            return
        end
        commands.exec("/tag " .. selector .. " add grandop_processing")
        local target = processingSelector(team)
        if respawn.decrementQuota then respawn.decrementQuota(faction, spawn.name) end
        loadout.applyClass(data, className, target)
        randomTeleport(target, spawn, respawn.spawnRadius)
        commands.exec("/effect give " .. target .. " minecraft:resistance 4 10")
        commands.exec("/clear " .. target .. " minecraft:written_book")
        commands.exec("/scoreboard players set " .. target .. " " .. classObjective .. " 0")
        commands.exec("/scoreboard players set " .. target .. " " .. spawnObjective .. " 0")
        commands.exec("/tag " .. target .. " remove grandop_processing")
        commands.exec("/tag " .. target .. " remove grandop_wait_spawn")
    end

    local tankNames = {}
    local tankSpawnNames = {}
    for faction, list in pairs(respawn.tanks) do
        tankNames[faction] = {}
        for name in pairs(list) do table.insert(tankNames[faction], name) end
        table.sort(tankNames[faction])
        tankSpawnNames[faction] = respawn.coords[faction] or {}
    end
    local v = vehicles.newState(respawn.tanks)

    local function processTank(team, tankIndex)
        local faction = factionForTeam(mission, team)
        local tankName = tankNames[faction] and tankNames[faction][tankIndex]
        local selector = candidateSelector(team, tankObjective, tankIndex, "grandop_wait_tank")
        if not tankName or not commands.exec("execute if entity " .. selector) then return end
        commands.exec("/tag " .. selector .. " remove grandop_wait_tank")
        commands.exec("/tag " .. selector .. " add grandop_wait_tank_spawn")
        tankSpawnBook(mission, respawn, faction, team)
    end

    local function processTankSpawn(team, tankIndex, spawnIndex)
        local faction = factionForTeam(mission, team)
        local tankName = tankNames[faction] and tankNames[faction][tankIndex]
        local spawn = respawn.coords[faction] and respawn.coords[faction][spawnIndex]
        local selector = candidateSelector(team, tankSpawnObjective, spawnIndex, "grandop_wait_tank_spawn", tankObjective, tankIndex)
        if not tankName or not spawn or not commands.exec("execute if entity " .. selector) then return end
        local ok = vehicles.tryConsume(v, faction, tankName)
        if not ok then
            commands.exec("/tellraw " .. selector .. " {\"text\":\"Tank cooldown active\",\"color\":\"red\"}")
            return
        end
        commands.exec("/tag " .. selector .. " add grandop_processing")
        local target = processingSelector(team)
        vehicles.spawnTank({
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
        commands.exec("/clear " .. target .. " minecraft:written_book")
        commands.exec("/scoreboard players set " .. target .. " " .. tankObjective .. " 0")
        commands.exec("/scoreboard players set " .. target .. " " .. tankSpawnObjective .. " 0")
        commands.exec("/tag " .. target .. " remove grandop_processing")
        commands.exec("/tag " .. target .. " remove grandop_wait_tank_spawn")
    end

    local function enableTriggers()
        commands.exec("/scoreboard players enable @a " .. modeObjective)
        commands.exec("/scoreboard players enable @a " .. classObjective)
        commands.exec("/scoreboard players enable @a " .. spawnObjective)
        commands.exec("/scoreboard players enable @a " .. tankObjective)
        commands.exec("/scoreboard players enable @a " .. tankSpawnObjective)
    end

    while true do
        enableTriggers()
        for team in pairs(teams) do
            local outside = "@a[team=" .. team .. ",x=" .. respawn.area.x .. ",y=" .. respawn.area.y .. ",z=" .. respawn.area.z .. ",distance=" .. (respawn.area.radius + 1) .. "..]"
            commands.exec("/tag " .. outside .. " remove grandop_book")
            commands.exec("/tag " .. outside .. " remove grandop_wait_mode")
            commands.exec("/tag " .. outside .. " remove grandop_wait_class")
            commands.exec("/tag " .. outside .. " remove grandop_wait_spawn")
            commands.exec("/tag " .. outside .. " remove grandop_wait_tank")
            commands.exec("/tag " .. outside .. " remove grandop_wait_tank_spawn")
        end
        for team in pairs(teams) do initializePlayer(team) end
        for team in pairs(teams) do
            processMode(team, 1)
            processMode(team, 2)
            for i = 1, #(factionClasses(data, factionForTeam(mission, team))) do
                processClass(team, i)
                for s = 1, #(respawn.infantrySpawns[factionForTeam(mission, team)] and respawn.infantrySpawns[factionForTeam(mission, team)][ctx.stage.current] or {}) do
                    processSpawn(team, i, s)
                end
            end
            for i = 1, #(tankNames[factionForTeam(mission, team)] or {}) do
                processTank(team, i)
                for s = 1, #(respawn.coords[factionForTeam(mission, team)] or {}) do
                    processTankSpawn(team, i, s)
                end
            end
        end
        sleep(0.2)
    end
end

return book
