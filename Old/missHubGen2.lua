local radar = peripheral.find("sp_radar")
local modem = peripheral.find("modem")
local monitor = peripheral.find("monitor")
local controller = peripheral.find("tweaked_controller")
monitor.setTextScale(0.5)

local secretKey = "YourSecretKey123"
local function isValidMessage(message)
    local key, msg = tostring(message):match("^(%w+)%:(.+)$")
    return key == secretKey, msg
end

local missile = 1
local Xchannel = missile * 10
local Ychannel = missile *10 + 1
local Zchannel = missile *10 + 2
local pitchChannel = missile *10 + 3
local yawChannel = missile *10 + 4
local speedChannel = missile *10 + 5
local idChannel = missile *10 + 6
local launchChannel = missile *10 + 7
print("X Channel:", Xchannel)
print("Y Channel:", Ychannel)
print("Z Channel:", Zchannel)
print("Pitch Channel:", pitchChannel)
print("Yaw Channel:", yawChannel)
print("Speed Channel:", speedChannel)
print("ID Channel:", idChannel)
print("Launch Channel:", launchChannel)
os.sleep(1)
modem.open(yawChannel)
modem.open(Xchannel)
modem.open(Ychannel)
modem.open(Zchannel)
modem.open(pitchChannel)
modem.open(speedChannel)
modem.open(idChannel)
modem.open(launchChannel)



local currentPitch = 0
local currentYaw = 0
local sourceX = 0
local sourceY = 0
local sourceZ = 0
local speed = 0
local hostileIDs = {}
local launched = {}
-- Helper function to check if an element exists in a table
function table.contains(table, element)
    for _, value in ipairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

local function round(num)
    return math.floor(num + 0.5)
end

-- Function to convert a table of numbers into a comma-separated string
local function tableToString(t)
    local list = {}
    for _, v in ipairs(t) do
        table.insert(list, tostring(v))
    end
    return table.concat(list, ", ")
end

function deserializeTable(serializedString)
    local t = {}
    for k, v in string.gmatch(serializedString, "([^=,{]+)=([^,{}]+)") do
        if v:match("^{.*}$") then
            t[k] = deserializeTable(v:sub(2, -2))
        else
            t[k] = tonumber(v) or v
        end
    end
    return t
end

-- Function to listen for modem messages and update coordinates
local function listenForCoordinates()
--update current information
    while true do
        local Xchannel = missile *10
        local Ychannel = missile *10 + 1
        local Zchannel = missile *10 + 2
        local pitchChannel = missile *10 + 3
        local yawChannel = missile *10 + 4
        local speedChannel = missile *10 + 5
        local idChannel = missile *10 + 6
        local launchChannel = missile *10 + 7
        local event, side, senderChannel, replyChannel, message, senderDistance = os.pullEvent("modem_message")
        local valid, validatedMessage = isValidMessage(message)
        if valid then
            if senderChannel == Xchannel then
                sourceX = tonumber(validatedMessage)
            elseif senderChannel == Ychannel then
                sourceY = tonumber(validatedMessage)
            elseif senderChannel == Zchannel then
                sourceZ = tonumber(validatedMessage)
            elseif senderChannel == pitchChannel then
                currentPitch = tonumber(validatedMessage)
            elseif senderChannel == yawChannel then
                currentYaw = tonumber(validatedMessage)
            elseif senderChannel == speedChannel then
                local velocity = deserializeTable(validatedMessage)
                speed = math.sqrt(velocity.x ^ 2 + velocity.y ^ 2 + velocity.z ^ 2)
            elseif senderChannel == idChannel then
                MissileID = validatedMessage
            end
        else
            
        end
    end
end

function indexOf(t, value)
    for i, v in ipairs(t) do
        if v == value then
            return i
        end
    end
    return nil  -- or return -1 to indicate "not found"
end


local selectedIndex = {}
local lockedTarget = {}
local pos
local function selectTarget()
    local results = radar.scanForShips(5000)
    local possibleTargets = {}
    local targetsByID = {}
    
    local pos = ship.getWorldspacePosition()
    

    if not selectedIndex[missile] then
        selectedIndex[missile] = 1
    end

    if not results or #results == 0 then
        table.insert(possibleTargets, "No objects detected.")
    else
        for i, object in ipairs(results) do
            local x = object.pos.x - sourceX
            local y = object.pos.y - sourceY
            local z = object.pos.z - sourceZ
            local distance = math.sqrt(x^2 + y^2 + z^2)

            local X = object.pos.x - pos.x
            local Y = object.pos.y - pos.y
            local Z = object.pos.z - pos.z
            local radarDistance = math.sqrt(X^2 + Y^2 + Z^2)
            -- Check if the object's mass is greater than 10,000 before adding it to the display
            if object.mass > 20000 and distance > 5 and radarDistance > 50 then
                
                local objectInfo = {
                    id = object.id,
                    mass = object.mass,
                    pos = object.pos,
                    velocity = object.velocity,
                    distance = distance
                }
                possibleTargets[#possibleTargets + 1] = objectInfo
                targetsByID[object.id] = objectInfo
            end
        end
    end

    if #possibleTargets == 0 then
        return -- Exit if there are no targets
    end

    local currentTargetID = selectedIndex[missile]
    local targetIDs = {}
    for _, target in pairs(possibleTargets) do
        table.insert(targetIDs, target.id)
    end
    local currentIndex = indexOf(targetIDs, currentTargetID) or 1

    local yAxis = controller.getAxis(2)

    if yAxis < 0 then
        currentIndex = currentIndex - 1
        if currentIndex < 1 then
            currentIndex = #targetIDs -- wrap around to the last item
        end
    elseif yAxis > 0 then
        currentIndex = currentIndex + 1
        if currentIndex > #targetIDs then
            currentIndex = 1 -- wrap around to the first item
        end
    end

    -- Update selected index to new target ID
    selectedIndex[missile] = targetIDs[currentIndex]
    lockedTarget = targetsByID[selectedIndex[missile]]

    -- Update the monitor to highlight the selected target
 
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.write("Position (X, Y, Z): " .. tostring(round(sourceX)) .. ", " .. tostring(round(sourceY)) .. ", " .. tostring(round(sourceZ)))
    monitor.setCursorPos(1, 2)
    monitor.write("Yaw: " .. tostring(round(currentYaw)) .. " Pitch: " .. tostring(round(currentPitch)) .. " Speed: " .. tostring(round(speed)))
    monitor.setCursorPos(1, 3)
    monitor.write("MissileID: " .. tostring(MissileID).." Missile number: "..tostring(missile).." Launched: "..tostring(launched[missile]))


    local selectedLineIndex = indexOf(targetIDs, selectedIndex[missile])
    for i, line in ipairs(displayData) do
        monitor.setCursorPos(1, i + 3)
        if i == selectedLineIndex + 1 then
            monitor.setBackgroundColor(colors.blue)
        else
            monitor.setBackgroundColor(colors.black)
        end
        monitor.write(line)
        monitor.setBackgroundColor(colors.black)
    end
end

parallel.waitForAny(listenForCoordinates, function()
    while true do

        if controller.getButton(11) then --enter
            launched[missile] = true
            --initial phrase
            redstone.setOutput("back", true)
            sleep(2)
            redstone.setOutput("back", false)
        end
        if controller.getButton(10) then  --y
            launched[missile] = false
        end

        if controller.getAxis(1) then
            xAxis = controller.getAxis(1)
            if xAxis > 0 then
                missile = missile + 1
            elseif xAxis < 0 then
                missile = missile - 1
            end
            if missile < 1 then
                missile = 1
            end
            local Xchannel = missile *10
            local Ychannel = missile *10 + 1
            local Zchannel = missile *10 + 2
            local pitchChannel = missile *10 + 3
            local yawChannel = missile *10 + 4
            local speedChannel = missile *10 + 5
            local idChannel = missile *10 + 6
            local launchChannel = missile *10 + 7
            print("X Channel:", Xchannel)
            print("Y Channel:", Ychannel)
            print("Z Channel:", Zchannel)
            print("Pitch Channel:", pitchChannel)
            print("Yaw Channel:", yawChannel)
            print("Speed Channel:", speedChannel)
            print("ID Channel:", idChannel)
            print("Launch Channel:", launchChannel)
            modem.open(yawChannel)
            modem.open(Xchannel)
            modem.open(Ychannel)
            modem.open(Zchannel)
            modem.open(pitchChannel)
            modem.open(speedChannel)
            modem.open(idChannel)
            modem.open(launchChannel)
        end

        sleep(0.05)
        -- radar scan
        results = radar.scanForShips(5000)  -- Scan within a range of 1000; adjust as needed
        displayData = {}  -- Initialize an empty table to store display information
        
        if not results or #results == 0 then
            table.insert(displayData, "No objects detected.")
        else
            table.insert(displayData, "Detected Objects:")
            for i, object in ipairs(results) do
                local pos = ship.getWorldspacePosition()
                
                local x = object.pos.x - sourceX
                local y = object.pos.y - sourceY
                local z = object.pos.z - sourceZ
                local distance = math.sqrt(x^2 + y^2 + z^2)

                local X = object.pos.x - pos.x
                local Y = object.pos.y - pos.y
                local Z = object.pos.z - pos.z
                local radarDistance = math.sqrt(X^2 + Y^2 + Z^2 )
                -- Check if the object's mass is greater than 10,000 before adding it to the display
                if object.mass > 20000 and distance > 5 and radarDistance > 50 then
                    local objectInfo = string.format("ID:%d M:%d X:%.1f Y:%.2f Z:%.1f D:%.1f DR:%.1f", 
                    object.id, object.mass, object.pos.x, object.pos.y, object.pos.z, distance, radarDistance)
                    table.insert(displayData, objectInfo)
                end

            end
            -- Check if any objects passed the mass filter, if not, modify the display message
            if #displayData == 1 then  -- Only the title has been added
                displayData[2] = "No objects above mass threshold detected."
            end
        end
        selectTarget()
        print("launched: ",launched[missile])
        for missile = 1, 16 do
            local launchChannel = missile * 10 + 7
            if launched[missile] == false or launched[missile] == true then
                modem.transmit(launchChannel, 0, secretKey .. ":" .. tostring(launched[missile]))
            end
        end
        print("missile number: ",missile)
        modem.transmit(missile * 10 + 6, 0, secretKey..":"..lockedTarget.id)
        print("missileID: ",MissileID)
        print("TargetID: "..lockedTarget.id)
    end
end)