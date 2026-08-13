-- Grandop respawn terminal.
--
-- Runs the tank/infantry respawn system for a mission. All mission data comes
-- from the mission config module and the per-mission loadout JSON file, so the
-- program itself stays identical across events.
--
-- Usage: respawn_terminal <mission_id> [country]

local monitor = peripheral.find("monitor")
local radar = peripheral.find("sp_radar")

if not monitor then error("Monitor not found!") end
if not radar then error("Radar not found!") end

local args = { ... }
local missionId = args[1]
if not missionId then error("Usage: respawn_terminal <mission> [country]") end

local function rootRequire(name)
    if package.loaded[name] then return package.loaded[name] end
    local chunk, reason = loadfile("/" .. name:gsub("%.", "/") .. ".lua")
    if not chunk then error("Cannot load /" .. name:gsub("%.", "/") .. ".lua: " .. tostring(reason)) end
    local result = chunk()
    package.loaded[name] = result or true
    return package.loaded[name]
end
_G.require = rootRequire

local mission = require("missions." .. missionId)
local respawnCfg = mission.respawn
if not respawnCfg then error("Mission has no respawn config: " .. missionId) end

local mc = require("lib.minecraft")
local monitor_ui = require("lib.monitor_ui")
local loadout = require("lib.loadout")
local stage = require("lib.stage_channel")
local vehicles = require("lib.respawn.vehicles")
local infantry = require("lib.respawn.infantry")
local creative_area = require("lib.services.creative_area")

monitor.clear()
monitor.setTextScale(0.5)

--================================================================--
-- Loadout data (per-mission JSON)
--================================================================--
local loadoutData = loadout.load(respawnCfg.loadout_file)
if not loadoutData then error("Missing loadout file: " .. respawnCfg.loadout_file) end

--================================================================--
-- Stage listener (uses the mission's stage channel)
--================================================================--
local stageChannel = (mission.objective and mission.objective.stage_channel) or 125
local stageHub = stage.new(stageChannel)
stage.open(stageHub)

--================================================================--
-- Country selection (override via arg or prompt on the terminal)
--================================================================--
local country = nil
if args[2] then
    country = args[2]
    if not respawnCfg.tanks[country] then error("Unknown country: " .. country) end
else
    local countries = {}
    for c in pairs(respawnCfg.tanks) do table.insert(countries, c) end
    table.sort(countries)
    print("Select your country:")
    for i, c in ipairs(countries) do print(i .. ". " .. c) end
    io.write("Enter a number from 1 to " .. #countries .. ": ")
    local idx = tonumber(io.read())
    country = countries[idx]
    if not country then error("Invalid selection") end
end
print("You selected " .. country)

--================================================================--
-- Reset prompts (configurable for headless ROM operation)
--================================================================--
local resetTanks = respawnCfg.resetTanks or false
local resetSpawns = respawnCfg.resetSpawns or false
if respawnCfg.resetTanks == nil then
    print("Reset the tank list and overwrite the file? (y/n): ")
    resetTanks = io.read():lower() == "y"
end
if respawnCfg.resetSpawns == nil then
    print("Reset the infantry spawn count scoreboard? (y/n): ")
    resetSpawns = io.read():lower() == "y"
end

--================================================================--
-- Vehicle state + tank list
--================================================================--
local tankListFile = respawnCfg.tankListFile or "tanksList.txt"
if resetTanks then vehicles.saveTankList(tankListFile, respawnCfg.tanks) end
local tanksList = vehicles.loadTankList(tankListFile, respawnCfg.tanks)
local v = vehicles.newState(tanksList)

--================================================================--
-- Scoreboard init + startup hooks
--================================================================--
if respawnCfg.initScoreboard then respawnCfg.initScoreboard(resetSpawns) end

--================================================================--
-- Shared runtime state
--================================================================--
local runtime = {
    player = "Not detected",
    tankslugtoID = {},
    playerTankMap = {},
}

local ctx = {
    monitor = monitor,
    radar = radar,
    mc = mc,
    mission = respawnCfg,
    loadoutData = loadoutData,
    stage = stageHub,
    country = country,
    spawnRadius = respawnCfg.spawnRadius or 10,
    tankslugtoID = runtime.tankslugtoID,
    playerTankMap = runtime.playerTankMap,
    displayScoreboard = respawnCfg.displayScoreboard,
    hasQuota = respawnCfg.hasQuota,
    decrementQuota = respawnCfg.decrementQuota,
}

-- player is used as a plain string by modules; bind it per action.
local function currentPlayer()
    return runtime.player
end

if respawnCfg.onStartup then respawnCfg.onStartup(ctx) end

--================================================================--
-- Closest player detection (keeps runtime.player updated)
--================================================================--
local function closestPlayerLoop()
    while true do
        local radarResult = radar.scanForPlayers(20)
        local closestDistance = math.huge
        local closestPos
        local closestName
        local px, py, pz = commands.getBlockPosition()
        for _, player in pairs(radarResult or {}) do
            if player and player.pos then
                local dx = player.pos[1] - px
                local dy = player.pos[2] - py
                local dz = player.pos[3] - pz
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                if distance < closestDistance then
                    closestDistance = distance
                    closestPos = player.pos
                    closestName = player.nickname
                end
            end
        end
        if closestName then runtime.player = closestName end
        sleep(0.2)
    end
end

--================================================================--
-- Mode selection (Tank / Infantry)
--================================================================--
local function selectMode()
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor_ui.print(monitor, "Select Mode:")
    local yTank, yInf = 3, 5
    monitor.setCursorPos(2, yTank); monitor.write("[ Tank ]")
    monitor.setCursorPos(2, yInf); monitor.write("[ Infantry ]")
    while true do
        local ev, side, x, y = os.pullEvent("monitor_touch")
        if y == yTank and x >= 2 and x <= 9 then return "tank" end
        if y == yInf and x >= 2 and x <= 12 then return "infantry" end
    end
end

--================================================================--
-- Vehicle (tank) respawn flow
--================================================================--
local function updateCrewSpawnLeft(tankName)
    local td = runtime.tankslugtoID[tankName]
    if td and td.crewSpawnLeft > 0 then
        td.crewSpawnLeft = td.crewSpawnLeft - 1
        runtime.tankslugtoID[tankName] = td
    end
end

local function tankFlow()
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor_ui.print(monitor, "=== Available Tanks ===")

    local availableTanks = {}
    for tankName, cfg in pairs(tanksList[country]) do
        if cfg.stock and cfg.stock > 0 then
            table.insert(availableTanks, tankName)
        end
    end

    if #availableTanks == 0 then
        monitor_ui.print(monitor, "No tanks available!")
        sleep(1.2)
        return
    end

    for _, name in ipairs(availableTanks) do
        local cfg = tanksList[country][name]
        vehicles.ensure(v, country, name)
        vehicles.refill(v, country, name)
        local cd = vehicles.timeToNext(v, country, name)
        local st = v.state[country][name]
        local cdText = (st.tokens > 0) and "Ready" or (tostring(cd) .. "s")
        monitor_ui.print(monitor, ("- %s (%d)  cooldown:%s"):format(name, cfg.stock, cdText))
    end

    local selectedTank = vehicles.selectTankTouch(monitor, availableTanks, v, country)
    if not selectedTank then return end

    local ok, waitSec = vehicles.tryConsume(v, country, selectedTank)
    if not ok then
        monitor_ui.print(monitor, selectedTank .. " cooldown. Ready in ~" .. waitSec .. "s.")
        sleep(1.2)
        return
    end

    local spawnPoint = vehicles.selectSpawnPoint(monitor, respawnCfg.coords[country])
    if not spawnPoint then return end

    local repairKits = loadoutData.repair_kits or {}
    vehicles.spawnTank({
        v = v,
        country = country,
        monitor = monitor,
        radar = radar,
        player = currentPlayer(),
        mission = respawnCfg,
        spawnPoint = spawnPoint,
        tankName = selectedTank,
        playerTankMap = runtime.playerTankMap,
        tankslugtoID = runtime.tankslugtoID,
        repairKits = repairKits,
        tankListFile = tankListFile,
    })
end

--================================================================--
-- Infantry respawn flow
--================================================================--
local function infantryFlow()
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor_ui.print(monitor, "Infantry respawn\nStage: " .. tostring(stageHub.current))

    local player = currentPlayer()
    ctx.player = player

    ctx.extraRows = function()
        local rows = {}
        for tankName, tankData in pairs(runtime.tankslugtoID) do
            if tankData.crewSpawnLeft and tankData.crewSpawnLeft > 0 then
                table.insert(rows, {
                    label = ("[%s] %d SpawnLeft"):format(tankName, tankData.crewSpawnLeft),
                    value = { name = tankName, type = "vehicle" },
                })
            end
        end
        return rows
    end
    ctx.onVehicleSelected = updateCrewSpawnLeft

    local class = infantry.selectClass(ctx)
    if not class then return end
    if not infantry.isKitReady(ctx, class) then
        monitor_ui.print(ctx.monitor, class .. " is on cooldown. Please wait.")
        sleep(1.5)
        return
    end

    local spawn = infantry.selectSpawn(ctx)
    if not spawn then return end

    infantry.useKit(ctx, class)
    infantry.respawn(ctx, spawn, class)

    if respawnCfg.reinforcement then
        respawnCfg.reinforcement.startCountDown = true
    end
end

--================================================================--
-- Main interaction loop
--================================================================--
local function mainLoop()
    while true do
        local mode = selectMode()
        if mode == "tank" then
            tankFlow()
        elseif mode == "infantry" then
            infantryFlow()
        end
        if respawnCfg.displayScoreboard then respawnCfg.displayScoreboard() end
        sleep(0.5)
    end
end

--================================================================--
-- Run everything in parallel
--================================================================--
local tasks = {
    mainLoop,
    closestPlayerLoop,
    function() creative_area.run(radar, respawnCfg.creativeZones(country), respawnCfg.creativeRadius) end,
    stage.listener(stageHub),
}

if respawnCfg.reinforcement and respawnCfg.reinforcement.loop then
    table.insert(tasks, function() respawnCfg.reinforcement.loop(ctx) end)
end
if respawnCfg.retreatLoop then
    table.insert(tasks, function() respawnCfg.retreatLoop(ctx) end)
end

parallel.waitForAny(unpack(tasks))
