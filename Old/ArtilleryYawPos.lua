local reader = peripheral.find("blockReader")
local monitor = peripheral.find("monitor")
local router = peripheral.find("redrouter")
local bal = peripheral.find("ballistic_accelerator")
local radar = peripheral.find("sp_radar")
local controller = peripheral.find("tweaked_controller")

local function parseCoordinates(input)
    local x, y, z = input:match("([^%s]+)%s+([^%s]+)%s+([^%s]+)")
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

local function directionToBearing(direction)
    local bearings = { N = 0, E = 90, S = 180, W = 270 }
    return bearings[direction]
end

print("Input the cannon mount's coordinate (x y z)(space between)")
local input = read()
local source = parseCoordinates(input)
print(source.x)
print(source.y)
print(source.z)

print("Input the cannon mount's facing (N or E or S or W)")
local facing = read():upper()
local bearing = directionToBearing(facing)

if bearing then
    print("True Bearing: " .. bearing .. " degrees")
else
    print("Invalid direction. Please input N, E, S, or W.")
end

-- Initialize source coordinates
local sourceX = source.x
local sourceY = source.y
local sourceZ = source.z

local currentPitch = 0
local currentYaw = 0
local projectileSpeed = 160 / 20
local yaw_tolerance = 0.5
local pitch_tolerance = 0.12
local yawCompensate = 0
local pitchCompensate = 0
local x, y, z = nil, nil, nil
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
local displayData = {}

local function selectTarget()
    local results = radar.scanForShips(2000)
    local possibleTargets = {}

    if not results or #results == 0 then
        table.insert(possibleTargets, "No objects detected.")
    else
        for i, object in ipairs(results) do
            local x = object.pos.x - source.x
            local y = object.pos.y - source.y
            local z = object.pos.z - source.z
            local distance = math.sqrt(x^2 + y^2 + z^2)

            -- Check if the object's mass is greater than 10,000 before adding it to the display
            if object.mass > 20000 and distance > 10 then
                
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
            print("Enter Y and press enter (you need to restart if you accidentally press enter last time)")
            y = read()
            print("Enter Z and press enter (you need to restart if you accidentally press enter last time)")
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
router.setOutput("top",false)

while true do
    currentPitch = reader.getBlockData().CannonPitch
    currentYaw = bearing + reader.getBlockData().CannonYaw
    monitor.setTextScale(0.5)
    results = radar.scanForShips(1000)  -- Scan within a range of 1000; adjust as needed
    displayData = {}  -- Initialize an empty table to store display information
    
    if not results or #results == 0 then
        table.insert(displayData, "No objects detected.")
    else
        table.insert(displayData, "Input coordinate(; to re-enter):")
        for i, object in ipairs(results) do
            local x = object.pos.x - source.x
            local y = object.pos.y - source.y
            local z = object.pos.z - source.z
            local distance = math.sqrt(x^2 + y^2 + z^2)

            -- Check if the object's mass is greater than 10,000 before adding it to the display
            if object.mass > 20000 and distance > 10 then
                local objectInfo = string.format("ID:%d M:%d X:%.1f Y:%.2f Z:%.1f D:%.1f", 
                object.id, object.mass, object.pos.x, object.pos.y, object.pos.z, distance)
                table.insert(displayData, objectInfo)
            end

        end
        -- Check if any objects passed the mass filter, if not, modify the display message
        if #displayData == 1 then  -- Only the title has been added
            displayData[2] = "No objects above mass threshold detected."
        end
    end
    selectTarget()
    
    if lockedTarget.id and redstone.getInput("right") then
        print("locked id: ",lockedTarget.id)
        print("target position: ",round(lockedTarget.pos.x), round(lockedTarget.pos.y), round(lockedTarget.pos.z))
        print("cannon position: ",round(source.x), round(source.y), round(source.z))
        print("distance: ",lockedTarget.distance)

        cannonPos = {source.x, source.y, source.z}
        targetTemp = {lockedTarget.pos.x, lockedTarget.pos.y, lockedTarget.pos.z}
        local preCompensatedPitchTable = bal.calculatePitch(cannonPos, targetTemp, projectileSpeed, 8, -30, 90, 0.05, 0.99, 1, 1000000, 5, 20, false)
        print(textutils.serialize(preCompensatedPitchTable))
        local preCompensatedPitch = preCompensatedPitchTable[2][2]
        print(preCompensatedPitch)
        local ProjectileYSpeed = projectileSpeed * math.sin(preCompensatedPitch)
        if preCompensatedPitch < 0 then
            ProjectileYSpeed = ProjectileYSpeed * -1
        end
        
        local estimateTime = getTimeInAir(preCompensatedPitch, projectileSpeed, source.y, lockedTarget.pos.y)
        print("estimate time: ",estimateTime)

        local estimateX = lockedTarget.pos.x + lockedTarget.velocity.x * 2
        local estimateY = lockedTarget.pos.y + lockedTarget.velocity.y * 2
        local estimateZ = lockedTarget.pos.z + lockedTarget.velocity.z * 2
        estimate = {estimateX, estimateY, estimateZ}

        local dx = estimateX - source.x
        local dy = estimateY - source.y
        local dz = estimateZ - source.z

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
        local deltaYaw = (yaw - currentYaw + 180) % 360 - 180
        print("deltaYaw",deltaYaw)

        -- Adjust yaw
        if math.abs(deltaYaw) > yaw_tolerance then
            if deltaYaw > 0 then
                print("Turning right")
                router.setOutput("left", false)
                if math.abs(deltaYaw) < 5 then
                    local turnTime = math.abs(deltaYaw) / 6 * 0.99
                    router.setOutput("right", true)
                    sleep(turnTime)
                    router.setOutput("right",false)
                else
                    router.setOutput("right", true)
                end
                
            else
                print("Turning left")
                
                router.setOutput("right", false)
                if math.abs(deltaYaw) < 5 then
                    local turnTime = math.abs(deltaYaw) / 6 * 0.99
                    router.setOutput("left", true)
                    sleep(turnTime)
                    router.setOutput("left",false)
                else
                    router.setOutput("left", true)
                end
            end
            monitor.setCursorPos(1, 2)
            writeWithBackground("Yaw: " .. tostring(round(currentYaw)), colors.red)
        else
            -- Target within tolerance, stop rotation
            monitor.setCursorPos(1, 2)
            writeWithBackground("Yaw: " .. tostring(round(currentYaw)), colors.green)
            router.setOutput("right", false)
            router.setOutput("left", false)
        end

        local deltaPitch = pitch - currentPitch
        if math.abs(deltaPitch) > pitch_tolerance then
            if deltaPitch > 0 then
                print("Adjusting pitch up")
                router.setOutput("front", false)
                if math.abs(deltaPitch) < 3 then
                    local turnTime = math.abs(deltaPitch) / 6 * 0.99
                    router.setOutput("top", true)
                    sleep(turnTime)
                    router.setOutput("top",false)
                else
                    router.setOutput("top", true)
                end
            else
                print("Adjusting pitch down")
                router.setOutput("top", false)
                if math.abs(deltaPitch) < 3 then
                    local turnTime = math.abs(deltaPitch) / 6 * 0.99
                    router.setOutput("front", true)
                    sleep(turnTime)
                    router.setOutput("front",false)
                else
                    router.setOutput("front", true)
                end
            end
            monitor.setCursorPos(13, 2)
            writeWithBackground(" Pitch: " .. tostring(round(currentPitch)), colors.red)
        else
            monitor.setCursorPos(13, 2)
            writeWithBackground(" Pitch: " .. tostring(round(currentPitch)), colors.green)
            router.setOutput("top", false)
            router.setOutput("back", false)
        end
        local status = reader.getBlockData().Running
        if status == 1 then
            monitor.setCursorPos(19, 3)
            writeWithBackground("Assembled", colors.green)
        else
            monitor.setCursorPos(19, 3)
            writeWithBackground("Not Assembled", colors.red)
        end
        sleep(0.0001)

    else
        router.setOutput("front", false)
        router.setOutput("back", false)
        router.setOutput("right", false)
        router.setOutput("left", false)
        router.setOutput("top",false)
    end
    sleep(0.01)
end