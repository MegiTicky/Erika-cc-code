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
local x, y, z = 0, 0, 0
local pitch_tolerance = 1
local yaw_tolerance = 1
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
redstone.setOutput("left",false)
sleep(0.1)
local function mainLoop()
    while true do
        redstone.setOutput("right", true)
        redstone.setOutput("left",true)
        local result = radar.scanForPlayers(10)
        if #result > 0 then
            player = result[1]
            lookAngle = player.look_angle
            x, y, z = lookAngle[1], lookAngle[2], lookAngle[3]

            -- Compute yaw (true bearing)
            yaw = math.deg(math.atan2(-x, z))
            if yaw < 0 then
                yaw = yaw + 360
            end

            -- Compute pitch
            pitch = math.deg(math.asin(y))

            local matrix = ship.getRotationMatrix()
            local forwardX = matrix[1][3]
            local forwardZ = matrix[3][3]
            local yawRadians = math.atan2(-forwardX, forwardZ)
            local yawDegrees = toDegrees(yawRadians)
            local yawBearing = toBearing(yawDegrees) - 180
            if yawBearing < 0 then
                yawBearing = yawBearing + 360
            end

            currentYaw = reader.getBlockData().CannonYaw
            currentYaw = currentYaw - 180 + yawBearing
            shipPitch = toDegrees(-math.asin(ship.getRotationMatrix()[2][3]))
            print("shipPitch: ", shipPitch)
            currentPitch = reader.getBlockData().CannonPitch + shipPitch

            -- Adjust yaw
            print("Player: " .. player.nickname)
            print("Required Yaw (True Bearing): " .. round(yaw) .. " degrees")
            print("Required Pitch: " .. round(pitch) .. " degrees")
            print("current", currentPitch, currentYaw)
            local deltaYaw = (yaw - currentYaw + 180) % 360 - 180
            print("deltaYaw", deltaYaw)
            local yawSpeed = 0
            if math.abs(deltaYaw) > yaw_tolerance then
                if deltaYaw > 0 then
                    print("Turning right")
                    if math.abs(deltaYaw) > 30 then
                        yawSpeed = -80
                    elseif math.abs(deltaYaw) > 5 then
                        yawSpeed = -32
                    elseif math.abs(deltaYaw) < 2 then
                        yawSpeed = -4
                    end
                else
                    print("Turning left")
                    if math.abs(deltaYaw) > 30 then
                        yawSpeed = 80
                    elseif math.abs(deltaYaw) > 5 then
                        yawSpeed = 32
                    elseif math.abs(deltaYaw) < 5 then
                        yawSpeed = 4
                    end
                end
            end
            if yawSpeed ~= lastYawSpeed then
                yawMotor.setSpeed(yawSpeed)
                lastYawSpeed = yawSpeed
            end

            -- Adjust pitch
            local deltaPitch = pitch - currentPitch
            print("deltaPitch: ",deltaPitch)
            local pitchSpeed = 0
            if math.abs(deltaPitch) > pitch_tolerance then
                if deltaPitch > 0 then
                    print("Adjusting pitch up")
                    if math.abs(deltaPitch) > 30 then
                        pitchSpeed = -64
                    elseif math.abs(deltaPitch) > 5 then
                        pitchSpeed = -32
                    elseif math.abs(deltaPitch) < 5 then
                        pitchSpeed = -4
                    end
                else
                    print("Adjusting pitch down")
                    if math.abs(deltaPitch) > 10 then
                        pitchSpeed = 64
                    elseif math.abs(deltaPitch) > 3 then
                        pitchSpeed = 32
                    elseif math.abs(deltaPitch) < 3 then
                        pitchSpeed = 4
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
        sleep(0.2)
        redstone.setOutput("bottom", false)
    end
end

parallel.waitForAny(couple, mainLoop)
redstone.setOutput("right", false)