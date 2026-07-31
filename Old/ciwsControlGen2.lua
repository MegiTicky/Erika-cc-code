local monitorSide = "top"
local modemSide = "back"
local Xchannel = 20
local Ychannel = 21
local Zchannel = 22
local pitchChannel = 23
local yawChannel = 24

local radar = peripheral.find("sp_radar")
local modem = peripheral.find("modem")
local monitor = peripheral.find("monitor")
local router = peripheral.find("redrouter")
local controller = peripheral.find("tweaked_controller")
monitor.setTextScale(0.5)

modem.open(yawChannel)
modem.open(Xchannel)
modem.open(Ychannel)
modem.open(Zchannel)
modem.open(pitchChannel)

local currentPitch = 0
local currentYaw = 0
local sourceX = 0
local sourceY = 0
local sourceZ = 0
local speed = 0
local hostileIDs = {}
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
        end
    end
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
            local x = object.pos.x - sourceX
            local y = object.pos.y - sourceY
            local z = object.pos.z - sourceZ
            local distance = math.sqrt(x^2 + y^2 + z^2)

            -- Check if the object's mass is greater than 10,000 before adding it to the display
            if object.mass > 20000 and distance > 50 then
                
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
    if selectedIndex < 1 then
        selectedIndex = 1
    elseif selectedIndex > maxIndex then
        selectedIndex = maxIndex
    end
    lockedTarget = possibleTargets[selectedIndex]
    

    -- Update the monitor to highlight the selected target
 
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.write("Position (X, Y, Z): " .. tostring(round(sourceX)) .. ", " .. tostring(round(sourceY)) .. ", " .. tostring(round(sourceZ)))
    monitor.setCursorPos(1, 2)
    monitor.write("Yaw: " .. tostring(round(currentYaw)) .. " Pitch: " .. tostring(round(currentPitch)))



    for i, line in ipairs(displayData) do
        monitor.setCursorPos(1, i + 3)
        if i == selectedIndex + 1 then
            monitor.setBackgroundColor(colors.blue)
        end
        monitor.write(line)
        monitor.setBackgroundColor(colors.black)
    end
end

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
            table.insert(displayData, "Detected Objects:")
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
        if lockedTarget.id and redstone.getInput("bottom") then
            local results = radar.scanForShips(1000)
            local locked = {}
            print()
            print("locked id: ",lockedTarget.id)
            print("target position: ",lockedTarget.pos.x, lockedTarget.pos.y, lockedTarget.pos.z)
            print("cannon position: ",sourceX, sourceY, sourceZ)
            print("distance: ",lockedTarget.distance)

            local estimateTime = lockedTarget.distance / (6*20)
            local estimateX = lockedTarget.pos.x + lockedTarget.velocity.x * estimateTime
            local estimateY = lockedTarget.pos.y + lockedTarget.velocity.y * estimateTime
            local estimateZ = lockedTarget.pos.z + lockedTarget.velocity.z * estimateTime

            local dx = estimateX - sourceX
            local dy = estimateY - sourceY
            local dz = estimateZ - sourceZ

            print("dx: ",dx," dy: ",dy," dz: ",dz)

            local horizontalDistance = math.sqrt(dx * dx + dz * dz)
            local pitch = math.deg(math.atan2(dy, horizontalDistance))

            local yaw = math.deg(math.atan2(-dx, dz))
            yaw = yaw + 180
    
            print("non compesated pitch: ",pitch)
            local pitchAdjustments = {
                {min = 50, max = 100, increment = 0.5},
                {min = 180, max = 250, increment = 1},
                {min = 250, max = 300, increment = 2},
                {min = 300, max = 350, increment = 3},
                {min = 350, max = 400, increment = 3.7},
                {min = 400, max = 450, increment = 4.3},
                {min = 450, max = 500, increment = 5},
                {min = 500, max = 550, increment = 5.9},
                {min = 550, max = 600, increment = 6.6},
                {min = 600, max = 650, increment = 7.5}
            }

            for _, adjustment in ipairs(pitchAdjustments) do
                if lockedTarget.distance > adjustment.min and lockedTarget.distance <= adjustment.max then
                    pitch = pitch + adjustment.increment
                    break  -- Exit the loop once the correct range is found
                end
            end

            print("current",currentPitch,currentYaw)
            print("pitch,yaw",pitch,yaw)

            local deltaYaw = yaw - currentYaw
            local deltaYaw = (deltaYaw + 180) % 360 - 180
            local deltaPitch = pitch - currentPitch
            --turning
            local yaw_tolerance = 1
            local pitch_tolerance = 1
            if math.abs(deltaYaw) > yaw_tolerance then
                if deltaYaw < 0 then
                    print("Turning left")

                    router.setOutput("left", false)
                    if math.abs(deltaYaw) < 5 then
                        local turnTime = math.abs(deltaYaw) / (4*360/60)* 0.8
                        router.setOutput("top", true)
                        sleep(turnTime)
                        router.setOutput("top",false)
                    else
                        router.setOutput("top", true)
                    end
                elseif deltaYaw > 0 then
                    print("Turning right")
                    router.setOutput("left", true)

                    router.setOutput("top", false)
                    if math.abs(deltaYaw) < 5 then
                        local turnTime = math.abs(deltaYaw) / (4*360/60) * 0.8
                        router.setOutput("left", true)
                        sleep(turnTime)
                        router.setOutput("left",false)
                    else
                        router.setOutput("left", true)
                    end
                end
            else
                router.setOutput("top", false)
                router.setOutput("left", false)
            end

            if math.abs(deltaPitch) > pitch_tolerance then
                if deltaPitch > 0 then
                    print("Adjusting pitch up")
                    router.setOutput("back", false)
                    if math.abs(deltaPitch) < 5 then
                        local turnTime = math.abs(deltaPitch) / (4 * 360 / 60) * 0.8
                        router.setOutput("front", true)
                        sleep(turnTime)
                        router.setOutput("front", false)
                    else
                        router.setOutput("front", true)
                    end
                else
                    print("Adjusting pitch down")
                    router.setOutput("front", false)
                    if math.abs(deltaPitch) < 5 then
                        local turnTime = math.abs(deltaPitch) / (4 * 360 / 60) * 0.8
                        router.setOutput("back", true)
                        sleep(turnTime)
                        router.setOutput("back", false)
                    else
                        router.setOutput("back", true)
                    end
                end
            else
                router.setOutput("front", false)
                router.setOutput("back", false)
            end
            sleep(0.01)
        else
            router.setOutput("front", false)
            router.setOutput("back", false)
            router.setOutput("top", false)
            router.setOutput("left", false)
        end
        
    end
end)