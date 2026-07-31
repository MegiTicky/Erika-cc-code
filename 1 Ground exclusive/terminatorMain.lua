radar = peripheral.find("sp_radar")
raycaster = peripheral.find("raycaster")
yawMotor = peripheral.find("Create_RotationSpeedController")
cannon = peripheral.find("cbcmodernwarfare:compact_mount")
modem = peripheral.wrap("right")

--=======================--
--Variable initialization--
--=======================--
--==ballstiic data==--
local projectileSpeed = 220
local g = 0.02
local cd = 0.995
--==PID value==--

--===============--
--Utlity function--
--===============--
local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

-- Normalize a vector
local function normalizeVector(v)
    local length = math.sqrt(v[1]^2 + v[2]^2 + v[3]^2)
    if length == 0 then
        return {0, 0, 0}
    end
    return {v[1] / length, v[2] / length, v[3] / length}
end

-- Normalize the rotation matrix
local function normalizeRotationMatrix(rotMatrix)
    local normalizedMatrix = {}
    for i = 1, #rotMatrix do
        normalizedMatrix[i] = normalizeVector(rotMatrix[i])
    end
    return normalizedMatrix
end

-- Get the pitch of the ship
local function getPitch()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return math.asin(normalizedMatrix[2][3]) -- Extract pitch from the matrix
end
--pitch = math.deg(math.asin(ship.getTransformationMatrix()[2][3]))
-- Get the yaw of the ship
local function getYaw()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return math.atan2(-normalizedMatrix[3][1], -normalizedMatrix[3][3]) -- Extract yaw from the matrix
end

-- Get the roll of the ship
local function getRoll()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return math.atan2(normalizedMatrix[2][1], normalizedMatrix[2][2]) -- Extract roll from the matrix
end

targetShipId = tonumber(askUser("What ship do you want to target",3495))
mainToDriveChannel = tonumber(askUser("What communication channel do you want to use for main to drive computer?",2600))
driveToMainChannel = mainToDriveChannel + 1

modem.open(mainToDriveChannel)
modem.open(driveToMainChannel)

cannon.assemble()
yawCompensation = cannon.getYaw()
yawCompensation = math.floor((yawCompensation + 45) / 90) * 90 % 360

local targetInfo = {}
local function updateInfo()
    while true do
        shipPos = ship.getWorldspacePosition()
        shipVelocity = ship.getVelocity()
        shipYaw = getYaw()
        shipPitch = getPitch()
        radarShipResult = radar.scanForShips(9999)
        if radarShipResult then
            for _, object in ipairs(radarShipResult) do
                if tostring(object.id) == tostring(targetShipId) then
                    targetInfo = {
                        id = object.id,
                        name = object.name,
                        pos = object.pos,
                        velocity = object.velocity,
                        type = "targetShip",
                        distance = math.sqrt((object.pos.x - shipPos.x)^2 + (object.pos.y - shipPos.y)^2 + (object.pos.z - shipPos.z)^2),
                        yawCompensation = yawCompensation
                    }
                    break
                end
            end
        end

        sleep()
    end
end

local function sendTargetInfo()
    while true do
        modem.transmit(mainToDriveChannel, 0, targetInfo)
        --print("Sent target ship info:", textutils.serialize(targetInfo))
        sleep()
    end
end

--=================--
--Aim lock function--
--=================--
local yawErrorSum = 0
local lastYawError = 0
local pitchErrorSum = 0
local lastPitchError = 0
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0
local pitchError = 0
local pitchIntegral = 0
local pitchPrevError = 0
local lastTime = os.clock()

local Kp_yaw = 0.45
local Ki_yaw = 0
local Kd_yaw = 0.02
local Kp_pitch = 0.25
local Ki_pitch = 0.05
local Kd_pitch = 0.012
local dt = 0.1

local function calculateRange(angle, u, cd, g, c_est, projectileSpeed)
    local radians = math.rad(angle)
    local u = projectileSpeed/20
    local part1 = u * math.cos(radians) / math.log(cd)
    local part2 = ((g * cd) / (g * cd + (1 - cd) * u * math.sin(radians))) ^ (2 + c_est * projectileSpeed * math.sin(radians)) - 1
    local XR = part1 * part2

    return XR
end

local function findBestPitch(targetX, targetY, targetZ, sourceX, sourceY, sourceZ, initialVelocity, g, cd, c_est, projectileSpeed)
    local bestLowPitch = nil
    local bestHighPitch = nil
    local bestLowDistance = math.huge
    local bestHighDistance = math.huge
    local targetDistance = math.sqrt((targetX - sourceX)^2 + (targetZ - sourceZ)^2)

    for pitch = 0, 70, 0.15 do -- Iterate over pitch angles
        local calculatedRange = calculateRange(pitch, initialVelocity, cd, g, c_est, projectileSpeed)
        local distanceDifference = math.abs(calculatedRange - targetDistance)

        -- Find the low-angle solution
        if pitch <= 30 then
            if distanceDifference < bestLowDistance then
                bestLowDistance = distanceDifference
                bestLowPitch = pitch
            end
        -- Find the high-angle solution
        elseif pitch > 30 then
            if distanceDifference < bestHighDistance then
                bestHighDistance = distanceDifference
                bestHighPitch = pitch
            end
        end
    end

    --prioritize the low-angle solution
    return bestLowPitch
end

local function customProportional(error, Kp)
    -- Nonlinear proportional scaling
    -- Example: Quadratic growth for small errors
    local scaleFactor = 0 -- Controls how quickly the value grows for small errors

    local absError = math.abs(error)
    local proportional = Kp * (absError / (1 + scaleFactor * absError)) -- Sigmoid-like growth

    if error < 0 then
        proportional = -proportional -- Preserve the sign of the error
    end

    return math.abs(proportional) * (error < 0 and -1 or 1) -- Cap the value
end

local function PIDController(Kp, Ki, Kd, error, integral, prevError, dt)
    -- Nonlinear proportional term using the custom function
    local proportional = customProportional(error, Kp)

    -- Integral and derivative components
    integral = integral + error * dt
    local derivative = (error - prevError) / dt
    
    -- Calculate the PID output
    local output = proportional + (Ki * integral) + (Kd * derivative)

    -- Return the PID output, updated integral, and current error
    return output, integral, error
end

local lastYawTime = os.clock()
-- Yaw control function using PID
local function yawControl(deltaYaw, currentYaw)
    local now = os.clock()
    local dtThisFrame = now - lastYawTime
    lastYawTime = now
    if dtThisFrame <= 0 then
        dtThisFrame = 0.05
    end
    -- PID controller for yaw
    --print(dtThisFrame)
    local yawSpeed, newIntegral, newPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, deltaYaw, yawIntegral, yawPrevError, dtThisFrame)

    -- 2) Update global PID state
    yawIntegral = newIntegral
    yawPrevError = newPrevError

    -- Constrain the yaw speed to prevent runaway spinning
    yawSpeed = math.max(-36, math.min(36, yawSpeed))

    --print("deltaYaw: " .. deltaYaw)
    --print("yawSpeed: " .. yawSpeed)

    -- Set motor speed based on PID output
    yawMotor.setTargetSpeed(-yawSpeed)
end

local function findRelativeAngle(targetYaw,targetPitch)
    rot = ship.getQuaternion()
    cacheYaw = math.pi - math.rad(targetYaw)
    cachePitch = - math.rad(targetPitch)
    rotMatAdj11 = 1 - 2*(rot.x^2 + rot.y^2)
    rotMatAdj12 = 2*(rot.z * rot.x + rot.y * rot.w)
    rotMatAdj13 = 2*(rot.z * rot.y - rot.x * rot.w)
    rotMatAdj21 = 2*(rot.z * rot.x - rot.y * rot.w)
    rotMatAdj22 = 1 - 2*(rot.z^2 + rot.y^2)
    rotMatAdj23 = 2*(rot.x * rot.y + rot.z * rot.w)
    rotMatAdj31 = 2*(rot.z * rot.y + rot.x * rot.w)
    rotMatAdj32 = 2*(rot.x * rot.y - rot.z * rot.w)
    rotMatAdj33 = 1 - 2*(rot.z^2 + rot.x^2)

    rotMatTGT11 = math.cos(cacheYaw) * math.cos(cachePitch)
    rotMatTGT21 = math.sin(cacheYaw) * math.cos(cachePitch)
    rotMatTGT31 = - math.sin(cachePitch)
    
    rotMatRSLT11 = rotMatAdj11 * rotMatTGT11 + rotMatAdj12 * rotMatTGT21 + rotMatAdj13 * rotMatTGT31
    rotMatRSLT21 = rotMatAdj21 * rotMatTGT11 + rotMatAdj22 * rotMatTGT21 + rotMatAdj23 * rotMatTGT31
    rotMatRSLT31 = rotMatAdj31 * rotMatTGT11 + rotMatAdj32 * rotMatTGT21 + rotMatAdj33 * rotMatTGT31

    turretYaw = math.atan2(rotMatRSLT21, rotMatRSLT11)
    barrelPitch = math.asin(-rotMatRSLT31)
    return math.deg(-turretYaw),math.deg(-barrelPitch)
end

local requiredRelativePitch,requiredRelativeYaw = 0,0
local function aimCannon(targetPos, targetVel, sourceX, sourceY, sourceZ, currentPitch, currentYaw)
    if sourceX and sourceY and sourceZ and currentPitch and currentYaw then
        local currentTime = os.clock()
        local dt = currentTime - lastTime
        if dt == 0 then return end  -- Prevent division by zero
        lastTime = currentTime

        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local shipVelocity = ship.getVelocity()

        local estimateTime = distance / (projectileSpeed)
        local estimateX = targetPos.x + (targetVel.x - shipVelocity.x) * estimateTime
        local estimateY = targetPos.y + (targetVel.y - shipVelocity.y) * estimateTime
        local estimateZ = targetPos.z + (targetVel.z - shipVelocity.z) * estimateTime

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local estimateTime = distance / (projectileSpeed)
        local estimateX = targetPos.x + (targetVel.x - shipVelocity.x) * estimateTime
        local estimateY = targetPos.y + (targetVel.y - shipVelocity.y) * estimateTime
        local estimateZ = targetPos.z + (targetVel.z - shipVelocity.z) * estimateTime

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        -- Adjust pitch based on distance adjustments

        pitch = pitch + findBestPitch(estimateX, estimateY, estimateZ, sourceX, sourceY, sourceZ, projectileSpeed, g, cd, 0.0028, projectileSpeed)

        local deltaYaw = (yaw - currentYaw + 180) % 360 - 180
        local deltaPitch = pitch - currentPitch

        -- Turning and pitch adjustment logic
        yawControl(deltaYaw, currentYaw)
        -- Using vs addition to turn cannon
        requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw,pitch)

        lastCurrentYaw = currentYaw
        lastCurrentPitch = currentPitch
    end
end

local function setPitchYaw()
    while true do
        if targetInfo and requiredRelativePitch and requiredRelativeYaw then
            cannon.setPitch(math.max(requiredRelativePitch,-10))
            cannon.setYaw(math.min(math.max(requiredRelativeYaw,yawCompensation-6),yawCompensation+6))
        end
        sleep()
    end
end

local function lockOnTarget()
    local lineOfSightConfirmed = false  -- To track if line of sight was confirmed
    local timeoutDuration = 2  -- Timeout period in seconds
    local lastFailureTime = nil  -- To track the last time the raycast failed
    local timeoutTimer = 0  -- Timer to count failure duration

    while true do
        if targetInfo and targetInfo.pos and targetInfo.pos.x then
            aimCannon(targetInfo.pos, targetInfo.velocity, shipPos.x, shipPos.y, shipPos.z, math.deg(shipPitch), math.deg(shipYaw) + yawCompensation)

            local cannonPitch = cannon.getPitch()
            local cannonYaw = cannon.getYaw()
            
            -- Detecting if line of sight is achieved
            local Y = math.sin(math.rad(cannonPitch))
            local X = math.cos(math.rad(cannonYaw + 180)) * math.sin(math.rad(cannonYaw + 180))
            local planar_distance = 1
            local max_distance = targetInfo.distance + 100
            local result = raycaster.raycast(max_distance, {Y, X, planar_distance}, false, true)
            
            -- Handle raycast results
            if result.is_block and result.block_type ~= "block.minecraft.air" then
                print("Block hit at: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
                print("Block type: " .. result.block_type .. ", Distance: " .. result.distance)
            elseif result.is_entity then
                print("Entity hit at: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
                print("Entity ID: " .. result.id .. ", Distance: " .. result.distance)
            elseif result.ship_id then
                print("Ship hit at: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
            else
                print("No hit detected within " .. max_distance .. " blocks.")
            end

            -- If line of sight is confirmed
            if result and result.distance and result.ship_id and math.abs(result.distance - targetInfo.distance) < 8 then
                lineOfSightConfirmed = true
                targetInfo.lineOfSight = true
                cannon.fire()
                print("Line of sight achieved, firing")
                -- Reset the timeout timer if line of sight is confirmed
                lastFailureTime = nil
                timeoutTimer = 0
            else
                -- If the raycast fails, check the timeout
                if lineOfSightConfirmed then
                    -- Line of sight was confirmed before, now checking for timeout
                    if lastFailureTime == nil then
                        lastFailureTime = os.clock()  -- Start the timeout timer
                    end

                    -- Check if the raycast has failed for the timeout duration
                    if os.clock() - lastFailureTime >= timeoutDuration then
                        targetInfo.lineOfSight = false
                        lineOfSightConfirmed = false
                        print("Line of sight not achieved, timeout occurred")
                    else
                        print("Line of sight failed temporarily, waiting...")
                    end
                else
                    print("Line of sight not achieved")
                end
            end
        end

        sleep()
    end
end


parallel.waitForAny(
    updateInfo,
    sendTargetInfo,
    lockOnTarget,
    setPitchYaw
)