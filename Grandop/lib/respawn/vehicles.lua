-- Grandop vehicle (tank) respawn support.
-- Token-based cooldowns, stock persistence, spawn grids, and the touch UI.

local monitor_ui = grandopRequire("lib.monitor_ui")

local vehicles = {}

local function status(monitor, text)
    if monitor then
        monitor_ui.print(monitor, text)
    else
        print(text)
    end
end

local function now()
    return os.epoch("utc") / 1000
end

--================================================================--
-- Persistence (tanksList <-> file)
--================================================================--
function vehicles.loadTankList(filename, defaultList)
    if fs.exists(filename) then
        local f = fs.open(filename, "r")
        local content = f.readAll()
        f.close()
        local ok, res = pcall(textutils.unserialise, content)
        if ok and res then return res end
    end
    return defaultList
end

function vehicles.saveTankList(filename, list)
    local f = fs.open(filename, "w")
    f.write(textutils.serialize(list))
    f.close()
end

--================================================================--
-- Token cooldown + stock
--================================================================--
function vehicles.newState(tanksList)
    return {
        tanks = tanksList,
        state = {},
        pointIndex = 1,
    }
end

function vehicles.ensure(v, country, tankName)
    local cfg = v.tanks[country][tankName]
    if not cfg then return nil, nil end
    v.state[country] = v.state[country] or {}
    local st = v.state[country][tankName]
    if not st then
        st = { tokens = cfg.buffer, lastRefill = now() }
        v.state[country][tankName] = st
    end
    return cfg, st
end

function vehicles.refill(v, country, tankName)
    local cfg, st = vehicles.ensure(v, country, tankName)
    if not cfg then return end
    local t = now()
    local elapsed = t - st.lastRefill
    if elapsed >= cfg.cooldown then
        local add = math.floor(elapsed / cfg.cooldown)
        if add > 0 then
            st.tokens = math.min(cfg.buffer, st.tokens + add)
            st.lastRefill = st.lastRefill + add * cfg.cooldown
        end
    end
end

function vehicles.timeToNext(v, country, tankName)
    local cfg, st = vehicles.ensure(v, country, tankName)
    if not cfg then return 0 end
    vehicles.refill(v, country, tankName)
    if st.tokens > 0 then return 0 end
    local remain = cfg.cooldown - (now() - st.lastRefill)
    return math.max(1, math.ceil(remain))
end

-- Returns (true) when a token can be spent, (false, secondsLeft) when blocked.
function vehicles.tryConsume(v, country, tankName)
    local cfg, st = vehicles.ensure(v, country, tankName)
    if not cfg then return false, 0 end
    vehicles.refill(v, country, tankName)
    if st.tokens > 0 then
        local wasFull = (st.tokens == cfg.buffer)
        st.tokens = st.tokens - 1
        if wasFull then st.lastRefill = now() end
        return true
    else
        return false, vehicles.timeToNext(v, country, tankName)
    end
end

function vehicles.getStock(v, country, tankName)
    local cfg = v.tanks[country][tankName]
    return cfg and cfg.stock or 0
end

function vehicles.setStock(v, country, tankName, value)
    local cfg = v.tanks[country][tankName]
    if cfg then cfg.stock = math.max(0, value) end
end

--================================================================--
-- Spawn grids
--================================================================--
function vehicles.generateGridPoints(centerX, centerY, centerZ, numX, numZ, spacing)
    local result = {}
    for ix = 1, numX do
        for iz = 1, numZ do
            local offsetX = (ix - math.ceil(numX / 2)) * spacing
            local offsetZ = (iz - math.ceil(numZ / 2)) * spacing
            table.insert(result, { x = centerX + offsetX, y = centerY, z = centerZ + offsetZ })
        end
    end
    return result
end

--================================================================--
-- Radar ship helpers
--================================================================--
function vehicles.tankInSpawnFilter(result, spawnCoord, range)
    local filtered = {}
    for _, ship in ipairs(result or {}) do
        local x, z = ship.pos.x, ship.pos.z
        local horizontal = math.sqrt((spawnCoord.x - x) ^ 2 + (spawnCoord.z - z) ^ 2)
        if horizontal <= range then
            table.insert(filtered, ship)
        end
    end
    return filtered
end

function vehicles.filterNewlySpawnedShip(oldList, newList)
    local function exists(ship, list)
        for _, s in ipairs(list) do
            if s.id == ship.id then return true end
        end
        return false
    end
    local highest = nil
    for _, ship in ipairs(newList or {}) do
        if not exists(ship, oldList or {}) then
            if not highest or ship.mass > highest.mass then
                highest = ship
            end
        end
    end
    return highest
end

--================================================================--
-- Touch UI: spawn point selection
--================================================================--
function vehicles.selectSpawnPoint(monitor, spawnPoints)
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor_ui.print(monitor, "Select Spawn Location:")

    local y = 2
    local buttonMap = {}
    for _, point in ipairs(spawnPoints) do
        monitor.setCursorPos(2, y)
        monitor.write("[" .. point.name .. "]")
        buttonMap[y] = point
        y = y + 2
    end
    monitor.setCursorPos(2, y)
    monitor.write("[ Cancel ]")
    buttonMap[y] = "cancel"

    while true do
        local ev, side, x, ry = os.pullEvent("monitor_touch")
        local selection = buttonMap[ry]
        if selection == "cancel" then return nil end
        if selection then return selection end
    end
end

--================================================================--
-- Touch UI: tank list with live cooldown and admin +/- buttons
--================================================================--
function vehicles.selectTankTouch(monitor, availableTanks, v, country)
    local buttonX   = 38
    local xSpacing  = 5
    local labels    = { "+2", "+1", "-1", "-2" }
    local deltas    = {  2,    1,   -1,   -2  }
    local refreshMs = 0.5

    local cancelButtonY = nil
    local rowMap        = {}
    local buttonRegions = {}

    local function render()
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write("Touch a tank to select or modify:")
        monitor.setCursorPos(1, 2)
        monitor.write("Only admin can press the +/- button")

        rowMap        = {}
        buttonRegions = {}

        local y = 3
        for _, name in ipairs(availableTanks) do
            local cfg = v.tanks[country][name] or { stock = 0, buffer = 0 }
            local _, st = vehicles.ensure(v, country, name)
            vehicles.refill(v, country, name)
            local cd = vehicles.timeToNext(v, country, name)
            local cdText = (st.tokens > 0) and "Ready" or (tostring(cd) .. "s")

            monitor.setCursorPos(2, y)
            monitor.write(("- %s (%d)  cooldown:%s"):format(name, cfg.stock or 0, cdText))
            rowMap[y] = name

            for i, label in ipairs(labels) do
                local x = buttonX + (i - 1) * xSpacing
                local btnText = "[" .. label .. "]"
                monitor.setCursorPos(x, y)
                monitor.write(btnText)
                table.insert(buttonRegions, {
                    y = y, xStart = x, xEnd = x + #btnText - 1, tank = name, delta = deltas[i],
                })
            end
            y = y + 1
        end

        monitor.setCursorPos(2, y)
        monitor.write("[ Cancel ]")
        cancelButtonY = y
    end

    render()
    local timer = os.startTimer(refreshMs)

    while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "monitor_touch" then
            local x, ty = b, c
            if ty == cancelButtonY and x >= 2 and x <= 12 then
                return nil
            end

            local handled = false
            for _, btn in ipairs(buttonRegions) do
                if ty == btn.y and x >= btn.xStart and x <= btn.xEnd then
                    print("\nAdmin modification request:")
                    print("  Tank: " .. btn.tank)
                    print("  Change: " .. (btn.delta >= 0 and "+" or "") .. btn.delta)
                    io.write("Press Enter within 3 seconds to confirm... ")

                    local t = os.startTimer(3)
                    local confirmed = false
                    while true do
                        local ev2, p = os.pullEvent()
                        if ev2 == "timer" and p == t then
                            print(" (timed out)")
                            break
                        elseif ev2 == "key" and p == keys.enter then
                            confirmed = true
                            break
                        end
                    end

                    if confirmed then
                        local cfg = v.tanks[country][btn.tank]
                        cfg.stock = math.max(0, (cfg.stock or 0) + btn.delta)
                        print("Change applied. New stock for " .. btn.tank .. ": " .. cfg.stock)
                    end
                    render()
                    timer = os.startTimer(refreshMs)
                    handled = true
                    break
                end
            end

            if not handled then
                local selectedTank = rowMap[ty]
                if selectedTank and x < (buttonX - 2) then
                    return selectedTank
                end
            end
        elseif ev == "timer" and a == timer then
            render()
            timer = os.startTimer(refreshMs)
        end
    end
end

--================================================================--
-- Full tank spawn flow
--================================================================--
-- ctx = {
--   v, monitor, radar, player, mission, loadoutData,
--   spawnPoint (from selectSpawnPoint), tankName,
--   playerTankMap, tankslugtoID, oldScan, newScan, repairKits,
-- }
-- Returns true when a tank was successfully teleported.
function vehicles.spawnTank(ctx)
    local v = ctx.v
    local country = ctx.country
    local mission = ctx.mission
    local radar = ctx.radar
    local monitor = ctx.monitor
    local player = ctx.player

    local teleportCord = ctx.spawnPoint
    local grid = vehicles.generateGridPoints(
        teleportCord.x, teleportCord.y, teleportCord.z,
        mission.numPointsX or 3, mission.numPointsZ or 3, mission.spacing or 20)

    local currentCount = vehicles.getStock(v, country, ctx.tankName)
    local teleported = false
    local tankNumber = currentCount

    while tankNumber > 0 and not teleported do
        local tankToTeleport = ctx.tankName .. "-" .. tankNumber
        local point = grid[v.pointIndex]
        local finalX, finalY, finalZ
        if teleportCord.useGrid then
            finalX, finalY, finalZ = point.x, teleportCord.y, point.z
        else
            finalX, finalY, finalZ = teleportCord.x, teleportCord.y, teleportCord.z
        end

        local oldScan = radar.scanForShips(9999)
        local oldInSpawn = vehicles.tankInSpawnFilter(oldScan, { x = finalX, y = finalY, z = finalZ }, 10)

        local oldTank = ctx.playerTankMap[player]
        if oldTank then
            status(monitor, "Moving old tank " .. oldTank .. " to reserve area...")
            local offsetX = math.random(-100, 100)
            local offsetZ = math.random(-100, 100)
            local rX = mission.reserve.x + offsetX
            local rY = mission.reserve.y
            local rZ = mission.reserve.z + offsetZ

            commands.exec("vs set-static " .. tankToTeleport .. " true")
            sleep(0.5)
            commands.exec(("vmod teleport %s %d %d %d"):format(tankToTeleport, rX, rY, rZ))
            commands.exec(("fill %d %d %d %d %d %d vscontrolcraft:chunk_loader"):format(rX, rY, rY, rX, rY, rY))
            sleep(1.5)
            commands.exec(("vmod teleport %s %d %d %d"):format(oldTank, rX, rY, rZ))
            sleep(0.5)
            commands.exec(("fill %d %d %d %d %d %d air"):format(rX, rY, rY, rX, rY, rY))
        end

        status(monitor, ("Teleporting %s to X:%d Y:%d Z:%d"):format(tankToTeleport, finalX, finalY, finalZ))
        commands.exec("vs set-static " .. tankToTeleport .. " true")
        sleep(0.3)

        local _, result = commands.exec(("vmod teleport %s %d %d %d"):format(tankToTeleport, finalX, finalY, finalZ))
        v.pointIndex = v.pointIndex + 1
        if v.pointIndex > #grid then v.pointIndex = 1 end

        local teleportFailed = not (result and result[1] == nil)
        if teleportFailed then
            status(monitor, "Tank not found, trying next...")
            tankNumber = tankNumber - 1
        else
            teleported = true
            status(monitor, "Teleport successful!")
            ctx.playerTankMap[player] = tankToTeleport
            commands.exec(("give %s create_tweaked_controllers:tweaked_linked_controller{display:{Name:'{\"text\":\"%s\"}'}}"):format(player, tankToTeleport))

            for _, item in ipairs(ctx.repairKits or {}) do
                commands.exec(("give %s %s %d"):format(player, item.item or item.id, item.count or 1))
            end

            sleep(0.5)
            local newScan = radar.scanForShips(9999)
            local newInSpawn = vehicles.tankInSpawnFilter(newScan, { x = finalX, y = finalY, z = finalZ }, 5)
            local newlySpawnedShip = vehicles.filterNewlySpawnedShip(oldInSpawn, newInSpawn)
            if newlySpawnedShip and newlySpawnedShip.id then
                local extra = (v.tanks[country][ctx.tankName] or {}).extraCrewCount or 0
                ctx.tankslugtoID[tankToTeleport] = { id = newlySpawnedShip.id, crewSpawnLeft = extra, mass = newlySpawnedShip.id }
            end

            commands.exec(("tp %s %d %d %d"):format(player, finalX, finalY + 2, finalZ))
            commands.exec(("tellraw %s {\"text\":\"Right click controller hub to link\",\"color\":\"yellow\"}"):format(player))
            sleep(1)
            commands.exec("kill @e[type=trackwork:wheel_entity]")
            commands.exec("vs set-static " .. tankToTeleport .. " false")

            vehicles.setStock(v, country, ctx.tankName, tankNumber - 1)
            if ctx.checkpoint then ctx.checkpoint("vehicle stock changed") end
        end
    end

    if not teleported then
        status(monitor, "No tanks of type " .. ctx.tankName .. " could be found!")
    end

    return teleported
end

return vehicles
