local radar = peripheral.find("sp_radar")

local function toDegrees(radians)
    return radians * (180 / math.pi)
end

-- Function to convert degrees to a bearing
local function toBearing(degrees)
    local bearing = degrees % 360
    if bearing < 0 then
        bearing = bearing + 360
    end
    return bearing
end

print("Input the water level, default : 0")
local waterLevel = io.read()
if waterLevel == "" then
    waterLevel = 0
end
waterLevel = tonumber(waterLevel)
redstone.setOutput("front",false)
redstone.setOutput("left",false)
redstone.setOutput("right",false)
redstone.setOutput("back",false)
redstone.setOutput("top",false)
while true do
    print("Waiting for redstone")
    if redstone.getInput("bottom") then
        print("armmed, launching")
        break
    end
    sleep()
end

print("armmed")

while true do
    local pos = ship.getWorldspacePosition()
    sleep(0.01)
    local velocity = ship.getVelocity()
    pos.x = pos.x + velocity.x * 2
    pos.z = pos.z + velocity.y * 2

    local yaw = math.deg(ship.getYaw())
    local pitch = math.deg(ship.getPitch())


    -- Guidance control
    if pos.y > waterLevel - 4 then
        redstone.setOutput("back", true)
    else
        redstone.setOutput("back", false)
    end

    --radar
    local results = radar.scanForShips(1000)
    local displayData = {}
    print(results)
    if not results or #results == 0 then
        table.insert(displayData, "No objects detected.")
    else
        table.insert(displayData, "Detected Objects:")
        local smallestYawDiff = 360
        local finalTargetYaw = nil
        local finalDistance = 1000
    
        for i, object in ipairs(results) do

            if object.mass > 100000 then
                print("id:", object.id)
                local dx = object.pos.x - pos.x
                local dz = object.pos.z - pos.z
                local angleFromSouth = math.atan2(dx, dz)
                local bearingFromSouth = math.deg(angleFromSouth)
                local targetYaw = (180 - bearingFromSouth) % 360
                local yawDiff = (targetYaw - yaw + 180) % 360 - 180
                local distance = math.sqrt(dx*dx+dz*dz)
    
                -- Compare and store the smallest yaw difference
                if math.abs(yawDiff) < math.abs(smallestYawDiff) then
                    smallestYawDiff = yawDiff
                    finalTargetYaw = targetYaw
                    finalDistance = distance
                    print("Yaw Difference:", smallestYawDiff)
                end
            end
        end
    
        if finalTargetYaw then
            if smallestYawDiff > 0 and math.abs(smallestYawDiff) > 8 then
                redstone.setOutput("right", true)
                redstone.setOutput("left", false)
                sleep(math.abs(smallestYawDiff)/40)
                redstone.setOutput("right", false)
                print("Turning left")
            elseif smallestYawDiff < 0 and math.abs(smallestYawDiff) > 8 then
                redstone.setOutput("left", true)
                redstone.setOutput("right", false)
                sleep(math.abs(smallestYawDiff)/40)
                redstone.setOutput("left", false)
                print("Turning right")
            else
                redstone.setOutput("left", false)
                redstone.setOutput("right", false)
            end
        end
        print("distance:",finalDistance)
        if finalDistance < 150 and redstone.getInput("front") then 
            print("detonating")

            sleep(0.5)
            redstone.setOutput("top",true)
            sleep(2)
            redstone.setOutput("top",false)
            error("Detonated")
        end
        
        if #displayData == 1 then
            displayData[2] = "No objects above mass threshold detected."
        end
    end
end

local radar = peripheral.find("sp_radar")
while true do
    shipPos = ship.getWorldspacePosition()
    numberOfShips = 0
    radarScanResult = radar.scanForShips(2000)
    longestDistance = 0
    local furtherShipPos

    for i,object in ipairs(radarScanResult) do
        local dx = object.pos.x - shipPos.X
        local dy = object.pos.y - shipPos.y
        local dz = object.pos.z - shipPos.z
        local distance = math.sqrt(dx^2 + dy^2 + dz^2)
        if distance > longestDistance then
            furtherShipPos = object.pos
            longestDistance = distance
        end
    end
    print(textutils.serialize(furtherShipPos))
end

