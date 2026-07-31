local radar = peripheral.find("sp_radar")
local pitchMotor = peripheral.wrap("back")
local yawMotor = peripheral.find("electric_motor")
local reader = peripheral.find("blockReader")

local function round(num)
    return math.floor(num * 100 + 0.5) / 100
end

local function displayInChunks(text, chunkSize)
    local length = #text
    local start = 1
    while start <= length do
        local chunk = text:sub(start, start + chunkSize - 1)
        print(chunk)
        start = start + chunkSize
        if start <= length then
            print("Press any key to continue...")
            os.pullEvent("key")
        end
    end
end

-- Initialize variables
local yaw = 0
local pitch = 0
local player = {}
local lookAngle = {}
local sourceX, sourceY, sourceZ = 0, 0, 0
local x, y, z = 0, 0, 0
local pitch_tolerance = 1.2
local yaw_tolerance = 1.2
local adjustedPitch = 0
yawMotor.setSpeed(0)
pitchMotor.setSpeed(0)

local lastYawSpeed = 0
local lastPitchSpeed = 0

local function toDegrees(radians)
    return radians * (180 / math.pi)
end

-- Function to convert degrees to a bearing
local function toBearing(degrees)
    local bearing = degrees % 360
    if bearing < 0 then
        bearing = 360 + bearing
    end
    return bearing
end

local function couple()
    while true do
        redstone.setOutput("bottom", true)
        sleep(1)
        redstone.setOutput("bottom", false)
        sleep(10)
    end
end
redstone.setOutput("right", false)
redstone.setOutput("left", false)
sleep(0.1)

local function mainLoop()
    while true do
        redstone.setOutput("left", true)
        local result = radar.scanForPlayers(20)
        if #result > 0 then
            player = result[1]
            lookAngle = player.look_angle
            local playerPos = player.pos
            local lookVector = {x = lookAngle[1], y = lookAngle[2], z = lookAngle[3]}

            -- Calculate target position
            local distance = 50 -- Distance to look ahead
            local targetPos = {
                x = playerPos[1] + lookVector.x * distance,
                y = playerPos[2] + lookVector.y * distance,
                z = playerPos[3] + lookVector.z * distance
            }

            -- Get source position
            local sourcePos = ship.getWorldspacePosition()
            sourceX, sourceY, sourceZ = sourcePos.x, sourcePos.y + 2, sourcePos.z

            -- Calculate required yaw and pitch to aim at the target position
            local dx = targetPos.x - sourceX
            local dy = targetPos.y - sourceY
            local dz = targetPos.z - sourceZ

            -- Compute yaw (true bearing)
            yaw = math.deg(math.atan2(-dx, dz))
            if yaw < 0 then
                yaw = yaw + 360
            end

            -- Compute pitch
            pitch = math.deg(math.atan2(dy, math.sqrt(dx * dx + dz * dz)))

            -- Get ship rotation matrix
            local matrix = ship.getRotationMatrix()
            local forwardX = matrix[1][3]
            local forwardZ = matrix[3][3]
            local yawRadians = math.atan2(-forwardX, forwardZ)
            local yawDegrees = toDegrees(yawRadians)
            local yawBearing = toBearing(yawDegrees) - 180
            if yawBearing < 0 then
                yawBearing = yawBearing + 360
            end

            -- Compensate for tank's roll and pitch
            local shipPitch = toDegrees(math.atan2(matrix[2][1], matrix[2][2])) * -1
            local shipRoll = toDegrees(-math.asin(matrix[2][3]))
            
            currentYaw = reader.getBlockData().CannonYaw
            currentYaw = currentYaw - 180 + yawBearing
            currentPitch = reader.getBlockData().CannonPitch + shipPitch

            -- Compensate for roll in pitch adjustment
            local yawTemp = reader.getBlockData().CannonYaw
            if yawTemp < 30 and yawTemp > 330 then
                adjustedPitch = pitch + shipRoll
            elseif yawTemp > 150 and yawTemp < 210 then
                adjustedPitch = pitch - shipRoll
            else
                adjustedPitch = pitch
            end
            

            -- Adjust yaw
            print("Player: " .. player.nickname)
            print("Required Yaw (True Bearing): " .. round(yaw) .. " degrees")
            print("Required Pitch: " .. round(adjustedPitch) .. " degrees")
            print("Current Pitch: " .. round(currentPitch) .. " degrees")
            print("Current Yaw: " .. round(currentYaw) .. " degrees")
            print("Ship Pitch: " .. round(shipPitch) .. " degrees")
            print("Ship Roll: " .. round(shipRoll) .. " degrees")

            local deltaYaw = (yaw - currentYaw + 180) % 360 - 180
            print(deltaYaw)
            local yawSpeed = 0
            if math.abs(deltaYaw) > yaw_tolerance then
                if deltaYaw > 0 then
                    print("Turning right")
                    if math.abs(deltaYaw) > 30 then
                        yawSpeed = -64
                    elseif math.abs(deltaYaw) > 4 then
                        yawSpeed = -32
                    elseif math.abs(deltaYaw) < 4 then
                        yawSpeed = -6
                    end
                else
                    print("Turning left")
                    if math.abs(deltaYaw) > 30 then
                        yawSpeed = 64
                    elseif math.abs(deltaYaw) > 4 then
                        yawSpeed = 32
                    elseif math.abs(deltaYaw) < 4 then
                        yawSpeed = 6
                    end
                end
            end
            if yawSpeed ~= lastYawSpeed then
                yawMotor.setSpeed(yawSpeed)
                lastYawSpeed = yawSpeed
            end

            -- Adjust pitch
            local deltaPitch = adjustedPitch - currentPitch
            local pitchSpeed = 0
            if math.abs(deltaPitch) > pitch_tolerance then
                if deltaPitch > 0 then
                    print("Adjusting pitch up")
                    if math.abs(deltaPitch) > 30 then
                        pitchSpeed = -64
                    elseif math.abs(deltaPitch) > 4 then
                        pitchSpeed = -32
                    elseif math.abs(deltaPitch) < 4 then
                        pitchSpeed = -6
                    end
                else
                    print("Adjusting pitch down")
                    if math.abs(deltaPitch) > 10 then
                        pitchSpeed = 64
                    elseif math.abs(deltaPitch) > 4 then
                        pitchSpeed = 32
                    elseif math.abs(deltaPitch) < 4 then
                        pitchSpeed = 6
                    end
                end
            end
            if pitchSpeed ~= lastPitchSpeed then
                pitchMotor.setSpeed(pitchSpeed)
                lastPitchSpeed = pitchSpeed
            end
        else
            print("No players detected.")
        end
        sleep(0.05)
        redstone.setOutput("bottom", false)
    end
end

parallel.waitForAny(couple, mainLoop)
redstone.setOutput("right", false)
