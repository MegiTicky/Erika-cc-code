local yawChannel = 300
local Xchannel = 301
local Ychannel = 302
local Zchannel = 303
local pitchChannel = 304
local statusChannel = 305

local radar = peripheral.find("sp_radar")
if peripheral.getType("left") == "modem" then
    modem = peripheral.wrap("left")
else
    modem = peripheral.wrap("right")
end
local monitor = peripheral.find("monitor")
local router = peripheral.find("redrouter")
local controller = peripheral.find("tweaked_controller")
local bal = peripheral.find("ballistic_accelerator")

monitor.setTextScale(0.5)

modem.open(yawChannel)
modem.open(Xchannel)
modem.open(Ychannel)
modem.open(Zchannel)
modem.open(pitchChannel)
modem.open(statusChannel)

local currentPitch = 0
local currentYaw = 0
local sourceX = 0
local sourceY = 0
local sourceZ = 0
local projectileSpeed = 400 / 20
local blindStart = 150  -- Start of blind spot
local blindEnd = 210
local yaw_tolerance = 0.5
local pitch_tolerance = 0.12
local yawCompensate = 0
local pitchCompensate = 0
local x,y,z = nil,nil,nil
local hostileIDs = {}

local function toDegrees(radians)
    return radians * (180 / math.pi)
end

local function toBearing(degrees)
    local bearing = degrees % 360
    if bearing < 0 then
        bearing = 360 + bearing
    end
    return bearing
end

function table.contains(table, element)
    for _, value in ipairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

local function round(num)
    return math.floor(num * 100 + 0.5) / 100
end

-- Function to convert a table of numbers into a comma-separated string
local function tableToString(t)
    local list = {}
    for _, v in ipairs(t) do
        table.insert(list, tostring(v))
    end
    return table.concat(list, ", ")
end

local function writeWithBackground(text, color)
    monitor.setBackgroundColor(color)
    monitor.write(text)
    monitor.setBackgroundColor(colors.black)  -- Reset to default or another desired color
end
-- Function to listen for modem messages and update coordinates
local function listenForCoordinates()
    while true do
        local event, side, senderChannel, replyChannel, message, senderDistance = os.pullEvent("modem_message")
        if senderChannel == Xchannel then
            sourceX = tonumber(message)
        elseif senderChannel == Ychannel then
            sourceY = tonumber(message)
        elseif senderChannel == Zchannel then
            sourceZ = tonumber(message)
        elseif senderChannel == pitchChannel then
            currentPitch = tonumber(message)
        elseif senderChannel == yawChannel then
            currentYaw = tonumber(message)
        elseif senderChannel == statusChannel then
            status = tonumber(message)
        end
    end
end

-- Function to normalize yaw values to the range [0, 360)
local function normalizeYaw(yaw)
    return (yaw % 360 + 360) % 360
end

local function isInBlindSpot(angle, shipYaw)
    local relativeYaw = normalizeYaw(angle - shipYaw)
    return relativeYaw >= blindStart and relativeYaw <= blindEnd
end

-- Function to determine the relative position of an object to the ship
local function getRelativePosition(objectYaw, shipYaw)
    local relativeYaw = normalizeYaw(objectYaw - shipYaw)
    if relativeYaw > 180 then
        return "left"
    elseif relativeYaw < 180 then
        return "right"
    else
        return "blindspot"
    end
end

-- Function to determine the pointing direction of the cannon relative to the ship
local function getCannonPointingDirection(cannonYaw, shipYaw)
    local relativeYaw = normalizeYaw(cannonYaw - shipYaw)
    if relativeYaw > 180 then
        return "left"
    elseif relativeYaw < 180 then
        return "right"
    else
        return "aligned"
    end
end

function getTimeInAir(pitch, projectileSpeed, sourceY, targetY)
    -- Convert pitch from degrees to radians for trigonometric calculations
    -- Resolve the initial velocity into its vertical component
    local v_y = projectileSpeed * math.sin(pitch)

    -- Acceleration due to gravity (m/s^2)
    local g = 9.81

    local time = (v_y + math.sqrt(v_y * v_y + 2 * g * (sourceY - targetY))) / g

    return time
end

local lockedTarget = {}
local selectedIndex = 1
local function selectTarget()
    local results = radar.scanForShips(1000)
    local possibleTargets = {}

    if not results or #results == 0 then
        table.insert(possibleTargets, "No objects detected.")
    else
        for i, object in ipairs(results) do
            local position = ship.getWorldspacePosition()
            local x = object.pos.x - sourceX
            local y = object.pos.y - sourceY
            local z = object.pos.z - sourceZ
            local distance = math.sqrt(x^2 + y^2 + z^2)

            local X = object.pos.x - position.x
            local Y = object.pos.y - position.y
            local Z = object.pos.z - position.z
            local radarDistance = math.sqrt(X^2 + Y^2 + Z^2 )
            -- Check if the object's mass is greater than 10,000 before adding it to the display
            if object.mass > 30000 and distance > 5 and radarDistance > 80 then
                
                local objectInfo = {
                    id = object.id,
                    mass = object.mass,
                    pos = object.pos,
                    velocity = object.velocity,
                    distance = distance
                }
                table.insert(possibleTargets, objectInfo)
            end
        end
        -- Check if any objects passed the mass filter, if not, modify the display message
    end

    local maxIndex = #possibleTargets
    
    local yAxis = controller.getAxis(2)
    if yAxis < 0 then
        selectedIndex = selectedIndex - 1
        
    elseif yAxis > 0 then
        selectedIndex = selectedIndex + 1
        
    elseif controller.getButton(11) then

    end
    if selectedIndex < 0 then
        selectedIndex = 0
    elseif selectedIndex > maxIndex then
        selectedIndex = maxIndex
    end
    
    if selectedIndex == 0 then
        
        
        if not(x and y and z) or controller.getButton(1) then
            monitor.clear()
            monitor.setCursorPos(1,1)
            monitor.write("Enter Coordinates by clicking the computer")
            print("Enter X and press enter , leave if blank and press enter 3 times if you want to quit )")
            x = read()
            print("Enter Y and press enter (you need to rstart if you accidentally press enter last time)")
            y = read()
            print("Enter Z and press enter (you need to rstart if you accidentally press enter last time)")
            z = read()
            x = tonumber(x)
            y = tonumber(y)
            z = tonumber(z)         
        end
        if x and y and z then
            local objectInfo = {
                id = "manual",
                mass = "N/A",
                pos = {x = x, y = y, z = z},
                velocity = {x = 0, y = 0, z = 0},
                distance = "N/A"
            }
            lockedTarget = objectInfo
            print(lockedTarget)
            print(lockedTarget.pos.x,lockedTarget.pos.y,lockedTarget.pos.z)
            print("Coordinates locked:", x, y, z)
            stored = true
        else
            selectedIndex = 1
            stored = false
        end
    else
        lockedTarget = possibleTargets[selectedIndex]
    end
    
    print(lockedTarget)

    -- Update the monitor to highlight the selected target
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.write("Position(X,Y,Z): " .. tostring(round(sourceX)) .. ", " .. tostring(round(sourceY)) .. ", " .. tostring(round(sourceZ)))
    
    for i, line in ipairs(displayData) do
        monitor.setCursorPos(1, i + 3)
        if i == selectedIndex + 1 then
            monitor.setBackgroundColor(colors.blue)
        end
        monitor.write(line)
        monitor.setBackgroundColor(colors.black)
    end
end

router.setOutput("front", false)
router.setOutput("back", false)
router.setOutput("right", false)
router.setOutput("left", false)

parallel.waitForAny(listenForCoordinates, function()
    while true do
        
        modem.open(yawChannel)
        modem.open(Xchannel)
        modem.open(Zchannel)
        modem.open(pitchChannel)
        -- radar scan
        results = radar.scanForShips(1000)  -- Scan within a range of 1000; adjust as needed
        displayData = {}  -- Initialize an empty table to store display information
        
        if not results or #results == 0 then
            table.insert(displayData, "No objects detected.")
        else
            table.insert(displayData, "Input coordinate(; to re-enter):")
            for i, object in ipairs(results) do
                local position = ship.getWorldspacePosition()
                local x = object.pos.x - sourceX
                local y = object.pos.y - sourceY
                local z = object.pos.z - sourceZ
                local distance = math.sqrt(x^2 + y^2 + z^2)

                local X = object.pos.x - position.x
                local Y = object.pos.y - position.y
                local Z = object.pos.z - position.z
                local radarDistance = math.sqrt(X^2 + Y^2 + Z^2 )
                -- Check if the object's mass is greater than 10,000 before adding it to the display
                if object.mass > 30000 and distance > 5 and radarDistance > 80 then
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
        if stored then
            monitor.setCursorPos(38, 4)
            monitor.write(x.." "..y.." "..z)
        end
        if lockedTarget.id then
            print("locked id: ",lockedTarget.id)
            print("target position: ",round(lockedTarget.pos.x), round(lockedTarget.pos.y), round(lockedTarget.pos.z))
            print("cannon position: ",round(sourceX), round(sourceY), round(sourceZ))
            print("distance: ",lockedTarget.distance)

            cannonPos = {sourceX, sourceY, sourceZ}
            targetTemp = {lockedTarget.pos.x, lockedTarget.pos.y, lockedTarget.pos.z}
            local preCompensatedPitchTable = bal.calculatePitch(cannonPos, targetTemp, projectileSpeed, 24, -30, 60, 0.05, 0.99, 1, 1000000, 5, 20, false)
            print(textutils.serialize(preCompensatedPitchTable))
            local preCompensatedPitch = preCompensatedPitchTable[2][2]
            
            local ProjectileYSpeed = projectileSpeed * math.sin(preCompensatedPitch)
            if preCompensatedPitch < 0 then
                ProjectileYSpeed = ProjectileYSpeed * -1
            end
            
            local estimateTime = getTimeInAir(preCompensatedPitch, projectileSpeed, sourceY, lockedTarget.pos.y)
            print("estimate time: ",estimateTime)

            local estimateX = lockedTarget.pos.x + lockedTarget.velocity.x * 2
            local estimateY = lockedTarget.pos.y + lockedTarget.velocity.y * 2
            local estimateZ = lockedTarget.pos.z + lockedTarget.velocity.z * 2
            estimate = {estimateX, estimateY, estimateZ}

            local dx = estimateX - sourceX
            local dy = estimateY - sourceY
            local dz = estimateZ - sourceZ

            local horizontalDistance = math.sqrt(dx * dx + dz * dz)
            --Manual Compesation
            local epsilon = 0.0001
            if controller.getButton(12) then
                pitchCompensate = pitchCompensate + 0.1
            end
            if controller.getButton(13) then
                yawCompensate = yawCompensate + 0.1
            end
            if controller.getButton(14) then
                pitchCompensate = pitchCompensate - 0.1
            end
            if controller.getButton(15) then
                yawCompensate = yawCompensate - 0.1
            end
            if not (math.abs(yawCompensate % 0.1) < epsilon or math.abs(yawCompensate % 0.1 - 0.1) < epsilon) then
                yawCompensate = 0
            end
            if not (math.abs(pitchCompensate % 0.1) < epsilon or math.abs(pitchCompensate % 0.1 - 0.1) < epsilon) then
                pitchCompensate = 0
            end
            monitor.setCursorPos(26, 2)
            monitor.write("Compensate yaw:"..yawCompensate.." Pitch:"..pitchCompensate)
            --CALCULATING YAW
            local yaw = math.deg(math.atan2(-dx, dz))
            yaw = yaw + 180  + yawCompensate
            local pitch = preCompensatedPitch + pitchCompensate
            print("non compesated pitch: ",pitch)
            print("current",currentPitch,currentYaw)
            print("pitch,yaw",pitch,yaw)
            local yawBearing = toBearing(toDegrees(math.atan2(-ship.getRotationMatrix()[1][3], ship.getRotationMatrix()[3][3]))) - 180
            print("ship yaw: ",yawBearing )
            local targetPosition = getRelativePosition(yaw, yawBearing)
            print("target is to the",targetPosition)
            local cannonDirection = getCannonPointingDirection(currentYaw, yawBearing)
            print("cannon is pointing to the", cannonDirection)
            local deltaYaw = (yaw - currentYaw + 180) % 360 - 180
            print("deltaYaw",deltaYaw)
            --turning

        
            local targetInBlindSpot = isInBlindSpot((currentYaw + deltaYaw) % 360, yawBearing)
        
            if targetInBlindSpot then
                monitor.setCursorPos(1,3)
                writeWithBackground("Blindspot Warning",colors.red)
                print("blindspot")
                router.setOutput("right", false)
                router.setOutput("left", false)
                monitor.setCursorPos(1, 2)
                writeWithBackground("Yaw: " .. tostring(round(currentYaw)),colors.red)
            else
                if math.abs(deltaYaw) > yaw_tolerance then
                    if (deltaYaw > 0 and targetPosition == cannonDirection) or (targetPosition == "right" and cannonDirection == "left") then
                        print("Turning right")
                        router.setOutput("right", true)
                        router.setOutput("left", false)
                    elseif (deltaYaw < 0 and targetPosition == cannonDirection) or (targetPosition == "left" and cannonDirection == "right") then
                        print("Turning left")
                        router.setOutput("left", true)
                        router.setOutput("right", false)
                    end
                    monitor.setCursorPos(1, 2)
                    writeWithBackground("Yaw: " .. tostring(round(currentYaw)),colors.red)
                else
                    -- Target within tolerance, stop rotation
                    monitor.setCursorPos(1, 2)
                    writeWithBackground("Yaw: " .. tostring(round(currentYaw)),colors.green)
                    router.setOutput("right", false)
                    router.setOutput("left", false)
                end
                monitor.setTextColor(colors.gray)
                monitor.setCursorPos(1, 3)
                monitor.write("Blindspot Warning")
                monitor.setTextColor(colors.white)
            end

            local deltaPitch = pitch - currentPitch
            if math.abs(deltaPitch) > pitch_tolerance then
                if deltaPitch > 0 then
                    print("Adjusting pitch up")
                    router.setOutput("front", true)
                    router.setOutput("back", false)
                else
                    print("Adjusting pitch down")
                    router.setOutput("back", true)
                    router.setOutput("front", false)
                end
                monitor.setCursorPos(13, 2)
                writeWithBackground(" Pitch: " .. tostring(round(currentPitch)),colors.red)
            else
                monitor.setCursorPos(13, 2)
                writeWithBackground(" Pitch: " .. tostring(round(currentPitch)),colors.green)
                router.setOutput("front", false)
                router.setOutput("back", false)
            end

            if  status == 1 then
                monitor.setCursorPos(19,3)
                writeWithBackground("Assembed",colors.green)
            else
                monitor.setCursorPos(19,3)
                writeWithBackground("Not Assembled",colors.red)
            end
            sleep(0.0001)
        
        end
        
    end
end)

