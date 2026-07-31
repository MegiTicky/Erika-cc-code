local keyboard = peripheral.find("tm_keyboard")
local monitor = peripheral.find("monitor")
local radar = peripheral.find("sp_radar")

if not keyboard then error("Keyboard not found!") end
if not monitor then error("Monitor not found!") end
if not radar then error("Radar not found!") end

monitor.clear()
monitor.setTextScale(0.5)

-- Tank inventory system
local tanksList = {
    germany = {
        tiger1 = 3,
        panther = 3,
        jagdpanther = 1,
        panzerIV = 2
    },
    allied = {
        M4A3E8 = 1,
        M4A2 = 1,
        T3485 = 1,
        churchillVII = 3,
    },
    japan = {
        chiha = 5,
        chinu = 1,
    },
    USMC = {
        churchillVII = 3,
        M4A2 = 1,
    }
}

local repairKits = {
    tiger1 = {
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
    },

    panther = {
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
    },
    jagdpanther = {
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
    },
    panzerIV = {
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
    },
    churchillVII = {
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
    },
    M3GMC = {
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
    },
    M4A3E8 = {
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
    },
    M4A2 = {
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
    },
    chinu = {
        { id = "trackwork:med_suspension_track", count = 64 },
        { id = "trackwork:med_phys_track", count = 16 },
        { id = "create:wrench", count = 1 },
        { id = "create:copycat_panel", count = 64 },
        { id = "s_a_b:hardsteelblockpanzer", count = 64 },
        { id = "create:shaft", count = 32 },
        { id = "tallyho:scope_block", count = 2 },
        { id = "create:analog_lever", count = 32 },
        { id = "vs_clockwork:gravitron", count = 1 },
        { id = "combatgear:pillsui", count = 1}           
    },
    chiha = {
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
    },
}

-- Reserve area
local reserveCord = {
    x = 1572,
    y = 90,
    z = 6280
}
-- Map of players and their current tank
local playerTankMap = {}

-- Define point grid
local numPointsX = 3  -- adjust how many points in X
local numPointsZ = 3  -- adjust how many points in Z
local spacing = 15    -- distance between points

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

-- Improved readKeyboard with correct cursor
local function readKeyboard(prompt, defaultValue)
    local w, h = monitor.getSize()
    local x, y = monitor.getCursorPos()

    printMonitor(prompt .. " (default: " .. defaultValue .. ")")
    monitor.write("> ")
    local inputStr = ""

    while true do
        local event, kbdName, param1, param2 = os.pullEvent()
        if event == "tm_keyboard_char" and kbdName == peripheral.getName(keyboard) then
            inputStr = inputStr .. param1
        elseif event == "tm_keyboard_key" and kbdName == peripheral.getName(keyboard) then
            if param1 == 257 then -- Enter
                if inputStr == "" then
                    return defaultValue
                else
                    return inputStr
                end
            elseif param1 == 259 then -- Backspace
                inputStr = inputStr:sub(1, -2)
            end
        end

        -- Update cursor and line
        local cx, cy = monitor.getCursorPos()
        monitor.setCursorPos(3, cy)
        monitor.clearLine()
        local displayStr = inputStr
        if #displayStr > (w - 2) then
            displayStr = displayStr:sub(#displayStr - (w - 3))
        end
        monitor.write(displayStr)
    end
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

local function readKeyboardWithPlayer(prompt, defaultValue)
    local w, h = monitor.getSize()
    local startX, startY = monitor.getCursorPos()

    -- Print prompt
    printMonitor(prompt .. " (default: " .. defaultValue .. ")")

    -- Input line start
    local inputY = startY + 1
    local playerY = startY + 2

    -- Write initial
    monitor.setCursorPos(1, inputY)
    monitor.clearLine()
    monitor.write("> ")

    local inputStr = ""
    local currentPlayer = getClosestUserName()

    while true do
        -- Update player name
        local newPlayer = getClosestUserName()
        if newPlayer ~= currentPlayer then
            currentPlayer = newPlayer
            monitor.setCursorPos(1, playerY)
            monitor.clearLine()
            monitor.write("Player: " .. (currentPlayer or "None"))
        end

        local event, kbdName, param1, param2 = os.pullEvent()
        if event then
            if event == "tm_keyboard_char" and kbdName == peripheral.getName(keyboard) then
                inputStr = inputStr .. param1
            elseif event == "tm_keyboard_key" and kbdName == peripheral.getName(keyboard) then
                if param1 == 257 then -- Enter
                    if inputStr == "" then
                        return defaultValue, currentPlayer
                    else
                        return inputStr, currentPlayer
                    end
                elseif param1 == 259 then -- Backspace
                    inputStr = inputStr:sub(1, -2)
                end
            end
        end

        -- Update input display
        monitor.setCursorPos(3, inputY)
        monitor.clearLine()
        local displayStr = inputStr
        if #displayStr > (w - 3) then
            displayStr = displayStr:sub(#displayStr - (w - 4))
        end
        monitor.write(displayStr)
    end
end

-- Setup phase
monitor.clear()
monitor.setCursorPos(1,1)
printMonitor("=== Tank Teleportation System ===")

local country
repeat
    printMonitor("Select your country:")
    printMonitor("1. Germany")
    printMonitor("2. Allied")
    printMonitor("3. Japan")
    printMonitor("4. USMC")


    local input = readKeyboard("Enter 1,2,3 or 4:", "")
    if input == "1" then
        country = "germany"
    elseif input == "2" then
        country = "allied"
    elseif input == "3" then
        country = "japan"
    elseif input == "4" then
        country = "USMC"
    else
        printMonitor("Invalid selection! Please choose 1 or 2")
    end
until country

-- Coordinates
local teleportCord = {
    x = tonumber(readKeyboard("Input x coordinate of destination:", "5847")),
    y = tonumber(readKeyboard("Input y coordinate of destination:", "38")),
    z = tonumber(readKeyboard("Input z coordinate of destination:", "6540"))
}

--For arrayed teleport
local points = {}
for ix = 1, numPointsX do
    for iz = 1, numPointsZ do
        local offsetX = (ix - math.ceil(numPointsX / 2)) * spacing
        local offsetZ = (iz - math.ceil(numPointsZ / 2)) * spacing
        table.insert(points, { x = teleportCord.x + offsetX, z = teleportCord.z + offsetZ })
    end
end

local currentPointIndex = 1

local function manageCreativeArea()
    local insidePlayers = {}
    local radius = 50
    while true do
        local radarResult = radar.scanForPlayers(9999)  -- big enough scan range
        local newInside = {}

        for _, player in ipairs(radarResult) do
            local px, py, pz = player.pos[1], player.pos[2], player.pos[3]
            local dx = px - teleportCord.x
            local dy = py - teleportCord.y
            local dz = pz - teleportCord.z
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

            local name = player.nickname
            if distance <= radius then
                newInside[name] = true

                if not insidePlayers[name] then
                    -- Player just entered area
                    commands.exec("gamemode creative " .. name)
                    print("Set creative: " .. name)
                end
            else
                if insidePlayers[name] then
                    -- Player just left area
                    commands.exec("gamemode survival " .. name)
                    print("Set survival: " .. name)
                end
            end
        end

        -- Update list for next loop
        insidePlayers = newInside

        sleep(1) -- adjust if needed
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
            local availableTanks = {}

            for tankName, count in pairs(tanksList[country]) do
                if count > 0 then
                    table.insert(availableTanks, tankName)
                end
            end

            if #availableTanks == 0 then
                printMonitor("No tanks available!")
                break
            end

            for _, name in ipairs(availableTanks) do
                printMonitor("- " .. name .. " (" .. tanksList[country][name] .. " available)")
            end

            --printMonitor("Current user's name: "..closetPlayerName.."   stand closer if it is not you")
            local selectedTank
            repeat
                selectedTank = readKeyboard("Enter tank name (or 'exit'):", "")
                if selectedTank == "exit" then
                    return
                end
                if not tanksList[country][selectedTank] or tanksList[country][selectedTank] <= 0 then
                    printMonitor("Invalid tank! Available tanks:")
                    for _, name in ipairs(availableTanks) do
                        printMonitor("- " .. name)
                    end
                    selectedTank = nil
                end
            until selectedTank
            printMonitor("Selected tank: "..selectedTank)


            local currentCount = tanksList[country][selectedTank]
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
                    -- Generate random offset for X and Z
                    local offsetX = math.random(-100, 100)
                    local offsetZ = math.random(-100, 100)

                    -- Calculate final coordinates
                    local finalX = reserveCord.x + offsetX
                    local finalZ = reserveCord.z + offsetZ
                    local finalY = reserveCord.y

                    -- Teleport with offset
                    local success, result = commands.exec("vmod teleport " .. tankToTeleport .. " " ..
                        finalX .. " " .. finalY .. " " .. finalZ)
                    printMonitor("Teleporting to X: " .. finalX .. " Y: " .. finalY .. " Z: " .. finalZ)
                    commands.exec("fill "..finalX.." "..finalY.." "..finalY.." "..finalX.." "..finalY.." "..finalY.." vscontrolcraft:chunk_loader")
                    sleep(1.5)
                    commands.exec("vmod teleport " .. oldTank .. " " .. finalX .. " " .. finalY .. " " .. finalZ)
                    sleep(0.5)
                    commands.exec("fill "..finalX.." "..finalY.." "..finalY.." "..finalX.." "..finalY.." "..finalY.." air")
                end

                printMonitor("Teleporting " .. tankToTeleport .. " to X: " .. finalX .. " Y: " .. finalY .. " Z: " .. finalZ)


                local success, result = commands.exec("vmod teleport " .. tankToTeleport .. " " ..
                    finalX .. " " .. finalY .. " " .. finalZ)

                currentPointIndex = currentPointIndex + 1
                if currentPointIndex > #points then
                    currentPointIndex = 1
                end

                local teleportFailed = false
                if type(result) == "table" then
                    if result[1] and tostring(result[1]) == "argument.valkurienskies.ship.no_found" then
                        teleportFailed = true
                    elseif result["argument.valkurienskies.ship.no_found"] then
                        teleportFailed = true
                    end
                end

                if teleportFailed then
                    printMonitor("Tank not found, trying next...")
                    tankNumber = tankNumber - 1
                else
                    teleported = true
                    printMonitor("Teleport successful!")
                    playerTankMap[closetPlayerName] = tankToTeleport  -- Save current tank for player

                    commands.exec("give " .. closetPlayerName .. " create_tweaked_controllers:tweaked_linked_controller{display:{Name:'{\"text\":\"" .. tankToTeleport .. "\"}'}}")

                    local kit = repairKits[selectedTank]
                    if kit then
                        for _, item in ipairs(kit) do
                            commands.exec("give " .. closetPlayerName .. " " .. item.id .. " " .. item.count)
                        end
                        printMonitor("Given " .. selectedTank .. " repair kit!")
                    else
                        printMonitor("No repair kit for " .. selectedTank)
                    end

                    commands.exec("tp " .. closetPlayerName .. " " .. finalX .. " " .. (finalY + 2) .. " " .. finalZ)
                    commands.exec("tellraw " .. closetPlayerName .. " {\"text\":\"Right click controller hub to link\",\"color\":\"yellow\"}")
                    sleep(0.2)
                    commands.exec("kill @e[type=trackwork:wheel_entity]")

                    tanksList[country][selectedTank] = tankNumber - 1
                    printMonitor("Remaining " .. selectedTank .. " tanks: " .. (tankNumber - 1))
                end
            end

            if not teleported then
                printMonitor("No tanks of type " .. selectedTank .. " could be found!")
                tanksList[country][selectedTank] = 0
            end

            sleep(1)
        end
    end,
    getClosestUserName,
    manageCreativeArea
)