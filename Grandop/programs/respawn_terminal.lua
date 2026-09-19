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
_G.grandopRequire = rootRequire

local missionFile = "/missions/" .. missionId:gsub("[^%w_%-]", "") .. ".lua"
local missionChunk, missionReason = loadfile(missionFile)
if not missionChunk then error("Cannot load " .. missionFile .. ": " .. tostring(missionReason)) end
local mission = missionChunk()
local respawnCfg = mission.respawn
if not respawnCfg then error("Mission has no respawn config: " .. missionId) end

local mc = grandopRequire("lib.minecraft")
local monitor_ui = grandopRequire("lib.monitor_ui")
local loadout = grandopRequire("lib.loadout")
local stage = grandopRequire("lib.stage_channel")
local vehicles = grandopRequire("lib.respawn.vehicles")
local infantry = grandopRequire("lib.respawn.infantry")
local field_gear = grandopRequire("lib.respawn.field_gear")
local stevesArmy = grandopRequire("lib.steves_army")
local creative_area = grandopRequire("lib.services.creative_area")

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
-- Tank pool source (flat `tanks` table or `vehiclePools.initial`)
--================================================================--
local poolSource = respawnCfg.tanks or (respawnCfg.vehiclePools and respawnCfg.vehiclePools.initial) or nil
if not poolSource then error("Mission has no tank pools: " .. missionId) end

--================================================================--
-- Country selection (override via arg or prompt on the terminal)
--================================================================--
local country = nil
if args[2] then
    country = args[2]
    if not poolSource[country] then error("Unknown country: " .. country) end
else
    local countries = {}
    for c in pairs(poolSource) do table.insert(countries, c) end
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
local resetSpawns = respawnCfg.resetSpawns or false
if respawnCfg.resetSpawns == nil then
    print("Reset the infantry spawn count scoreboard? (y/n): ")
    resetSpawns = io.read():lower() == "y"
end

--================================================================--
-- Vehicle state + tank list
--================================================================--
-- Tank availability lives in memory (per-type maxLive/cooldown); every
-- terminal start begins with a fresh state.
local tanksList = vehicles.mergePoolConfig(poolSource, nil)
local v = vehicles.newState(tanksList, {
    abandonRadius = respawnCfg.abandonRadius,
    abandonSeconds = respawnCfg.abandonSeconds,
    reserve = respawnCfg.reserve,
    markerLabel = respawnCfg.markerLabel,
})
vehicles.ensureMarkerObjective()

-- Field-gear watch (squad refill horn + reset menu book): missions opt in
-- by defining respawn.squadRefill / respawn.sessionReset.
local refillCfg = respawnCfg.squadRefill
local resetCfg = respawnCfg.sessionReset
if refillCfg or resetCfg then field_gear.ensureObjective() end

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
-- Background vehicle lifecycle (destruction/abandonment + marker watch)
--================================================================--
local function vehicleLifecycleLoop()
    while true do
        vehicles.reconcile(v, radar, runtime)
        vehicles.processMarkers(v, runtime)
        sleep(1)
    end
end

--================================================================--
-- Field-gear upkeep (horn + reset-menu book watch; missions opt in)
--================================================================--
local function fieldGearLoop()
    while true do
        field_gear.process({
            cfg = refillCfg,
            sessionReset = resetCfg,
            radar = radar,
            teams = mission.teams,
            respawn = respawnCfg,
            data = loadoutData,
            stage = stageHub,
        })
        sleep(1)
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

    vehicles.reconcile(v, radar, runtime)

    local availableTanks = {}
    for tankName in pairs(tanksList[country] or {}) do
        table.insert(availableTanks, tankName)
    end
    table.sort(availableTanks)

    if #availableTanks == 0 then
        monitor_ui.print(monitor, "No tanks available!")
        sleep(1.2)
        return
    end

    for _, name in ipairs(availableTanks) do
        local ok, info = vehicles.available(v, country, name)
        monitor_ui.print(monitor, ("- %s  %s"):format(name, tostring(info)))
    end

    local selectedTank = vehicles.selectTankTouch(monitor, availableTanks, v, country)
    if not selectedTank then return end

    local ok, info = vehicles.available(v, country, selectedTank)
    if not ok then
        monitor_ui.print(monitor, selectedTank .. " unavailable: " .. tostring(info))
        sleep(1.2)
        return
    end

    local spawnPoint = vehicles.selectSpawnPoint(monitor,
        respawnCfg.coords and respawnCfg.coords[country]
        or (respawnCfg.vehicleSpawns and respawnCfg.vehicleSpawns[country])
        or {})
    if not spawnPoint then return end

    local repairKits = loadoutData.repair_kits or {}
    local player = currentPlayer()
    vehicles.spawnTank({
        v = v,
        country = country,
        monitor = monitor,
        radar = radar,
        player = player,
        mission = respawnCfg,
        spawnPoint = spawnPoint,
        tankName = selectedTank,
        playerTankMap = runtime.playerTankMap,
        tankslugtoID = runtime.tankslugtoID,
        repairKits = repairKits,
    })

    -- Tanker kit follows the infantry classes: armor worn directly, sidearm
    -- in inventory, plus a full rifle squad (9 rifle / 3 MG / 2 AT) on a wide
    -- 20-block ring so soldiers don't spawn on the vehicle deck.
    local tankClass = country .. ".tank"
    if loadout.getClass(loadoutData, tankClass) then
        loadout.applyClass(loadoutData, tankClass, player)
        stevesArmy.spawnSquadmates(player, tankClass, loadoutData, 20)
    end
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
    vehicleLifecycleLoop,
    stage.listener(stageHub),
}

-- Field-gear upkeep is opt-in per mission.
if refillCfg or resetCfg then
    table.insert(tasks, fieldGearLoop)
end

-- Creative staging is optional: only run the zone loop when the mission
-- actually defines creative zones.
local creativeZones = respawnCfg.creativeZones and respawnCfg.creativeZones(country) or nil
if creativeZones and #creativeZones > 0 then
    table.insert(tasks, function()
        creative_area.run(radar, creativeZones, respawnCfg.creativeRadius)
    end)
end

if respawnCfg.reinforcement and respawnCfg.reinforcement.loop then
    table.insert(tasks, function() respawnCfg.reinforcement.loop(ctx) end)
end
if respawnCfg.retreatLoop then
    table.insert(tasks, function() respawnCfg.retreatLoop(ctx) end)
end

parallel.waitForAny(unpack(tasks))
