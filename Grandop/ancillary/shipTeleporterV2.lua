local monitor = peripheral.find("monitor")
local radar = peripheral.find("sp_radar")

if not monitor then error("Monitor not found!") end
if not radar then error("Radar not found!") end

monitor.clear()
monitor.setTextScale(0.5)

-- Tank inventory system
local tanksList = {
    germany = {
        tigeri   = { stock = 1, cooldown = 180, buffer = 1 },
        panther  = { stock = 5, cooldown = 120, buffer = 2 }, -- 2x burst
        panzer4 = { stock = 8, cooldown = 60,  buffer = 9999 }
    },
    allied = {
        sherman75     = { stock = 11, cooldown = 3, buffer = 1 },
        shermanfirefly       = { stock = 2, cooldown = 60, buffer = 1 },
        churchillvii = { stock = 2, cooldown = 60, buffer = 1 }
    },
    japan = {
        chiha  = { stock = 10, cooldown = 45,  buffer = 3 },
        chinu  = { stock = 2,  cooldown = 120, buffer = 2 },
        chihalg= { stock = 1,  cooldown = 180, buffer = 1 },
        horo   = { stock = 1,  cooldown = 150, buffer = 1 }
    },
    USMC = {
        m3gmc         = { stock = 4, cooldown = 60,  buffer = 3 },
        sherman75     = { stock = 4, cooldown = 90,  buffer = 2 },
        sherman75deco = { stock = 7, cooldown = 90,  buffer = 2 },
        sherman75usmc = { stock = 4, cooldown = 90,  buffer = 2 }
    }
}
local repairKits = {
    { id = "trackwork:suspension_track", count = 64 },
    { id = "trackwork:phys_track", count = 16 },
    { id = "create:wrench", count = 1 },
    { id = "create:copycat_panel", count = 64 },
    { id = "s_a_b:hardsteelblockpanzer", count = 64 },
    { id = "create:shaft", count = 32 },
    { id = "tallyho:scope_block", count = 2 },
    { id = "create:analog_lever", count = 32 },
    { id = "vs_clockwork:gravitron", count = 1 },
    { id = "combatgear:pillsui", count = 1}    
}

-- Reserve area
local reserveCord = {
    x = 1572,
    y = 90,
    z = 6280
}
-- Map of players and their current tank
local playerTankMap = {}
local availableTanks = {}

-- Define point grid
local numPointsX = 3  -- adjust how many points in X
local numPointsZ = 3  -- adjust how many points in Z
local spacing = 20    -- distance between points

local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

-- Improved printMonitor with wrapping
local function printMonitor(text)
    local w, h = monitor.getSize()
    local x, y = monitor.getCursorPos()

    while #text > 0 do
        local line = text
        if #line > w then
            line = text:sub(1, w)
            text = text:sub(w + 1)
        else
            text = ""
        end

        monitor.setCursorPos(1, y)
        monitor.clearLine()
        monitor.write(line)
        y = y + 1
        if y > h then
            monitor.clear()
            y = 1
        end
    end

    monitor.setCursorPos(1, y)
end

local closetPlayerName = "Not detected"
local function getClosestUserName()
    while true do
        local radarResult = radar.scanForPlayers(20)
        local closestDistance = math.huge
        local closetPlayerPos
        local computerPosX ,computerPosY,computerPosZ = commands.getBlockPosition()
        for _, player in pairs(radarResult) do
            if player and player.pos then
                local dx = player.pos[1] - computerPosX
                local dy = player.pos[2] - computerPosY
                local dz = player.pos[3] - computerPosZ
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                -- If this player is closer than the current closest, update the closest target
                if distance < closestDistance then
                    closestDistance = distance
                    closetPlayerPos = player.pos
                    closetPlayerName = player.nickname
                end
            end
        end
        if not closetPlayerName then
            print("Increase radar scan distance in config, cannot detect players")
        end
        --print(closetPlayerName)
        sleep(0.2)
    end
end

-- Setup phase (Terminal Input)
print("=== Tank Teleportation System ===")

local country
repeat
    print("Select your country:")
    print("1. Germany")
    print("2. Allied")
    print("3. Japan")
    print("4. USMC")
    io.write("Enter 1, 2, 3 or 4: ")
    local input = io.read()

    if input == "1" then
        country = "germany"
    elseif input == "2" then
        country = "allied"
    elseif input == "3" then
        country = "japan"
    elseif input == "4" then
        country = "USMC"
    else                                                                
        print("Invalid selection! Please choose 1, 2, 3, or 4.")
    end
until country

local defaultCoords = {
    germany = {
        { name = "Main", x = 5847, y = 38, z = 6540 }
    },
    allied = {
        { name = "Main", x = 7094, y = 28, z = 6473 }
    },
    japan = {
        { name = "S1 Town Spawn", x = 6068, y = 27, z = 5417 },
        { name = "S2 Hill Top", x = 5401, y = 62, z = 4658 },
        { name = "S3 West Plane", x = 4747, y = 21, z = 4602 }
    },
    USMC = {
        { name = "Main spawn", x = 4293, y = 23, z = 6700 }
    }
}

local function generateGridPoints(centerX, centerY, centerZ)
    local result = {}
    for ix = 1, numPointsX do
        for iz = 1, numPointsZ do
            local offsetX = (ix - math.ceil(numPointsX / 2)) * spacing
            local offsetZ = (iz - math.ceil(numPointsZ / 2)) * spacing
            table.insert(result, {
                x = centerX + offsetX,
                y = centerY,
                z = centerZ + offsetZ
            })
        end
    end
    return result
end

local currentPointIndex = 1

-- Create spawn point selection function:
local function selectSpawnPoint()
    monitor.clear()
    monitor.setCursorPos(1,1)
    printMonitor("Select Spawn Location:")

    local spawnPoints = defaultCoords[country]
    local y = 2
    local buttonMap = {}

    for i, point in ipairs(spawnPoints) do
        monitor.setCursorPos(2, y)
        monitor.write("[" .. point.name .. "]")
        buttonMap[y] = point
        y = y + 2
    end

    monitor.setCursorPos(2, y)
    monitor.write("[ Cancel ]")
    buttonMap[y] = "cancel"

    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        local selection = buttonMap[y]
        if selection == "cancel" then
            return nil
        elseif selection then
            return selection
        end
    end
end

local function confirmSelection(tankName)
    monitor.clear()
    printMonitor("You selected: " .. tankName)
    printMonitor("")
    printMonitor("Touch one of the options below:")

    local confirmY = 6
    local cancelY = 8

    monitor.setCursorPos(2, confirmY)
    monitor.write("[ Confirm ]")

    monitor.setCursorPos(2, cancelY)
    monitor.write("[ Cancel ]")

    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        if y == confirmY then
            return true
        elseif y == cancelY then
            return false
        end
    end
end

local function manageCreativeArea()
    local insidePlayers = {}
    local radius = 50

    -- Build a flat list of all possible creative areas
    local creativeZones = {}
    for _, point in ipairs(defaultCoords[country]) do
        table.insert(creativeZones, {
            name = point.name,
            x = point.x,
            y = point.y,
            z = point.z
        })
    end

    while true do
        local radarResult = radar.scanForPlayers(9999)
        local newInside = {}

        for _, player in ipairs(radarResult) do
            local px, py, pz = player.pos[1], player.pos[2], player.pos[3]
            local name = player.nickname
            local isInsideAny = false

            for _, zone in ipairs(creativeZones) do
                local dx = px - zone.x
                local dy = py - zone.y
                local dz = pz - zone.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                if distance <= radius then
                    isInsideAny = true
                    break
                end
            end

            if isInsideAny then
                newInside[name] = true
                if not insidePlayers[name] then
                    commands.exec("gamemode creative " .. name)
                    print("Set creative: " .. name)
                end
            else
                if insidePlayers[name] then
                    commands.exec("gamemode survival " .. name)
                    print("Set survival: " .. name)
                end
            end
        end

        insidePlayers = newInside
        sleep(1)
    end
end

--============--
--Cooldown--
--========--
local tankState = { germany = {}, allied = {}, japan = {}, USMC = {} }
local function now()
    return os.epoch("utc") / 1000  -- seconds
end

local function ensureState(country, tankName)
    local cfg = tanksList[country][tankName]
    local st  = tankState[country][tankName]
    if not st then
        st = { tokens = cfg.buffer, lastRefill = now() }
        tankState[country][tankName] = st
    end
    return cfg, st
end

-- Refill tokens based on elapsed time and cooldown
local function refillTokens(country, tankName)
    local cfg, st = ensureState(country, tankName)
    local t = now()
    local elapsed = t - st.lastRefill
    if elapsed >= cfg.cooldown then
        local add = math.floor(elapsed / cfg.cooldown)
        if add > 0 then
            st.tokens = math.min(cfg.buffer, st.tokens + add)
            st.lastRefill = st.lastRefill + add * cfg.cooldown
        end
    end
    return cfg, st
end

local function timeToNext(country, tankName)
    local cfg, st = refillTokens(country, tankName)
    if st.tokens > 0 then return 0 end
    local remain = cfg.cooldown - (now() - st.lastRefill)
    return math.max(1, math.ceil(remain))
end

-- Try to consume one token. Returns (true) if allowed; (false, secondsLeft) if blocked
local function tryConsume(country, tankName)
    local cfg, st = refillTokens(country, tankName)
    if st.tokens > 0 then
        local wasFull = (st.tokens == cfg.buffer)
        st.tokens = st.tokens - 1
        -- If we were full and just spent one, start the refill timer now
        if wasFull then st.lastRefill = now() end
        return true
    else
        return false, timeToNext(country, tankName)
    end
end

-- Convenience wrappers so the rest of your code can read/write stock easily
local function getStock(country, tankName)
    return tanksList[country][tankName].stock
end
local function setStock(country, tankName, value)
    tanksList[country][tankName].stock = math.max(0, value)
end

-- Display and wait for tank selection via touch (live cooldown)
local function selectTankTouch(availableTanks)
    local buttonX   = 38           -- where the first button starts
    local xSpacing  = 5            -- distance between button starts
    local labels    = { "+2", "+1", "-1", "-2" }
    local deltas    = {  2,    1,   -1,   -2  }
    local refreshMs = 0.5          -- seconds between UI refreshes

    local rowMap        = {}       -- [y] = tankName
    local buttonRegions = {}       -- { y, xStart, xEnd, tank, delta }

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
            local cfg = tanksList[country][name] or { stock = 0, buffer = 0 }
            local _, st = ensureState(country, name)
            refillTokens(country, name)

            local cd = timeToNext(country, name)
            local cdText = (st.tokens > 0) and "Ready" or (tostring(cd) .. "s")

            monitor.setCursorPos(2, y)
            monitor.write(("- %s (%d)  cooldown:%s"):format(name, cfg.stock or 0, cdText))
            rowMap[y] = name

            -- draw buttons using buttonX/xSpacing; record clickable regions
            for i, label in ipairs(labels) do
                local x = buttonX + (i - 1) * xSpacing
                local btnText = "[" .. label .. "]"
                monitor.setCursorPos(x, y)
                monitor.write(btnText)

                table.insert(buttonRegions, {
                    y      = y,
                    xStart = x,
                    xEnd   = x + #btnText - 1, -- inclusive
                    tank   = name,
                    delta  = deltas[i]
                })
            end

            y = y + 1
        end
    end

    -- initial draw + start refresh timer
    render()
    local timer = os.startTimer(refreshMs)

    while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "monitor_touch" then
            local x, ty = b, c

            -- check +/- buttons first
            for _, btn in ipairs(buttonRegions) do
                if ty == btn.y and x >= btn.xStart and x <= btn.xEnd then
                    -- admin confirm in terminal
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
                        local cfg = tanksList[country][btn.tank]
                        cfg.stock = math.max(0, (cfg.stock or 0) + btn.delta)
                        print("Change applied. New stock for " .. btn.tank .. ": " .. cfg.stock)
                    end

                    -- redraw immediately and reset refresh timer
                    render()
                    timer = os.startTimer(refreshMs)
                    goto continue_event_loop
                end
            end

            -- if not a button, check row selection (left side of row)
            local selectedTank = rowMap[ty]
            if selectedTank and x < (buttonX - 2) then
                return selectedTank
            end
        elseif ev == "timer" and a == timer then
            -- periodic refresh to update cooldowns
            render()
            timer = os.startTimer(refreshMs)
        end
        ::continue_event_loop::
    end
end

-- Main loop
parallel.waitForAny(
    function()
        while true do
            ::continue_loop::
            monitor.clear()
            monitor.setCursorPos(1,1)
            printMonitor("=== Available Tanks ===")
            availableTanks = {}

            -- Build list of tanks with stock > 0
            for tankName, cfg in pairs(tanksList[country]) do
                if cfg.stock and cfg.stock > 0 then
                    table.insert(availableTanks, tankName)
                end
            end

            if #availableTanks == 0 then
                printMonitor("No tanks available!")
                break
            end

            -- Show stock + token status (and cooldown if empty)
            for _, name in ipairs(availableTanks) do
                local cfg = tanksList[country][name]
                local _, st = ensureState(country, name)
                refillTokens(country, name)
                local cdNote = (st.tokens == 0) and (" [CD " .. timeToNext(country, name) .. "s]") or ""
                printMonitor("- " .. name .. " (" .. cfg.stock .. ")  tokens:" .. st.tokens .. "/" .. cfg.buffer .. cdNote)
            end

            ::tank_selection::
            local selectedTank = selectTankTouch(availableTanks)

            if not selectedTank then
                printMonitor("No tank selected.")
                sleep(1)
                goto continue_loop
            end

            -- Cooldown gate: consume a token or show remaining time
            local ok, waitSec = tryConsume(country, selectedTank)
            if not ok then
                printMonitor(selectedTank .. " is on cooldown. Ready in ~" .. waitSec .. "s.")
                sleep(1.2)
                goto continue_loop
            end

            local spawnPoint = selectSpawnPoint()
            if not spawnPoint then
                printMonitor("Spawn cancelled.")
                sleep(1)
                goto continue_loop
            end

            local teleportCord = spawnPoint
            local points = generateGridPoints(teleportCord.x, teleportCord.y, teleportCord.z)

            --[[local confirmed = confirmSelection(selectedTank)
            if not confirmed then
                printMonitor("Selection cancelled.")
                sleep(1)
                goto continue_loop
            end]]

            local currentCount = getStock(country, selectedTank)
            local teleported = false
            local tankNumber = currentCount

            while tankNumber > 0 and not teleported do
                local tankToTeleport = selectedTank .. "-" .. tankNumber
                local point = points[currentPointIndex]
                local finalX = point.x
                local finalZ = point.z
                local finalY = teleportCord.y

                -- Move old tank to reserve if exists
                local oldTank = playerTankMap[closetPlayerName]
                if oldTank then
                    printMonitor("Moving old tank " .. oldTank .. " to reserve area...")
                    -- Random offset for reserve drop
                    local offsetX = math.random(-100, 100)
                    local offsetZ = math.random(-100, 100)
                    local rX = reserveCord.x + offsetX
                    local rZ = reserveCord.z + offsetZ
                    local rY = reserveCord.y

                    -- set static (kept your original call)
                    commands.exec("vs set-static " .. tankToTeleport .. " true")
                    sleep(0.5)

                    -- chunkload, move, un-chunkload (kept your original sequence)
                    local success1, result1 = commands.exec("vmod teleport " .. tankToTeleport .. " " .. rX .. " " .. rY .. " " .. rZ)
                    printMonitor("Teleporting to X: " .. rX .. " Y: " .. rY .. " Z: " .. rZ)
                    commands.exec("fill " .. rX .. " " .. rY .. " " .. rY .. " " .. rX .. " " .. rY .. " " .. rY .. " vscontrolcraft:chunk_loader")
                    sleep(1.5)
                    commands.exec("vmod teleport " .. oldTank .. " " .. rX .. " " .. rY .. " " .. rZ)
                    sleep(0.5)
                    commands.exec("fill " .. rX .. " " .. rY .. " " .. rY .. " " .. rX .. " " .. rY .. " " .. rY .. " air")
                end

                printMonitor("Teleporting " .. tankToTeleport .. " to X: " .. finalX .. " Y: " .. finalY .. " Z: " .. finalZ)
                print("Teleporting " .. tankToTeleport .. " to X: " .. finalX .. " Y: " .. finalY .. " Z: " .. finalZ)

                -- set static before moving the chosen tank
                commands.exec("vs set-static " .. tankToTeleport .. " true")
                sleep(0.3)

                local success, result = commands.exec("vmod teleport " .. tankToTeleport .. " " .. finalX .. " " .. finalY .. " " .. finalZ)

                currentPointIndex = currentPointIndex + 1
                if currentPointIndex > #points then
                    currentPointIndex = 1
                end

                print(textutils.serialize(result))
                print(result and result[1])

                local teleportFailed = true
                if result and result[1] == nil then
                    teleportFailed = false
                end

                if teleportFailed then
                    printMonitor("Tank not found, trying next...")
                    print("Tank not found, trying next...")
                    tankNumber = tankNumber - 1
                else
                    teleported = true
                    printMonitor("Teleport successful!")
                    print("Teleport successful")
                    playerTankMap[closetPlayerName] = tankToTeleport  -- Save current tank for player

                    commands.exec("give " .. closetPlayerName .. " create_tweaked_controllers:tweaked_linked_controller{display:{Name:'{\"text\":\"" .. tankToTeleport .. "\"}'}}")

                    for _, item in ipairs(repairKits) do
                        commands.exec("give " .. closetPlayerName .. " " .. item.id .. " " .. item.count)
                    end
                    printMonitor("Given " .. selectedTank .. " repair kit!")

                    commands.exec("tp " .. closetPlayerName .. " " .. finalX .. " " .. (finalY + 2) .. " " .. finalZ)
                    commands.exec("tellraw " .. closetPlayerName .. " {\"text\":\"Right click controller hub to link\",\"color\":\"yellow\"}")
                    sleep(1)
                    commands.exec("kill @e[type=trackwork:wheel_entity]")
                    commands.exec("vs set-static " .. tankToTeleport .. " false")

                    setStock(country, selectedTank, tankNumber - 1)
                    printMonitor("Remaining " .. selectedTank .. " tanks: " .. getStock(country, selectedTank))
                end
            end

            if not teleported then
                printMonitor("No tanks of type " .. selectedTank .. " could be found!")
                setStock(country, selectedTank, 0)
            end

            sleep(1)
        end
    end,
    getClosestUserName,
    manageCreativeArea
)
