local radar = peripheral.find("sp_radar")
local modem = peripheral.find("modem")

redstone.setOutput("front",false)
redstone.setOutput("left",false)
redstone.setOutput("bottom",false)
redstone.setOutput("right",false)
redstone.setOutput("back",false)
redstone.setOutput("top",false)

local controls = {}
local target = {}
local lockedId = nil
local targetPos, targetVel, TargetYaw, TargetPitch
local Kp_yaw, Ki_yaw, Kd_yaw = 0.3, 0.035, -0.0012
local Kp_pitch, Ki_pitch, Kd_pitch = 0.26, 0.1, -0.002
local K_pitchDiff, k_heightDiff = 1,0.5
local projectedMissileY,yLevelDiff,initialDistance,targetAltitude
local closestDistance = math.huge

-- Initialize error, integral, and derivative terms for yaw and pitch
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0

local pitchError = 0
local pitchIntegral = 0
local pitchHeightPrevError = 0

local deltaSpeed,missileCurrentSpeed,lastSpeed = 0,0,0
local missileVelocity = {}
local lastVelocity = {x = 0, y = 0, z = 0}

local dt = 0.1
print("Input the missile id, eg:1, default: 1")
local missileId = io.read()
if missileId == "" then
    missileId = 1
end
missileId = tonumber(missileId)

local controlsChannel = 1300
local throttleChannel = controlsChannel + missileId
print("throttleChannel: "..throttleChannel)
if modem then 
    modem.open(controlsChannel)
    modem.open(throttleChannel)
end

local function normalizeVector(v)
    local length = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
    if length == 0 then
        return {0, 0, 0}
    end
    return {v[1] / length, v[2] / length, v[3] / length}
end

-- Function to normalize the rotation matrix
local function normalizeRotationMatrix(rotMatrix)
    local normalizedMatrix = {}
    for i = 1, #rotMatrix do
        normalizedMatrix[i] = normalizeVector(rotMatrix[i])
    end
    return normalizedMatrix
end

-- Modified getPitch function to use the normalized rotation matrix
function getPitch()
    local rotMatrix = ship.getRotationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return -math.asin(normalizedMatrix[2][3])
end


local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == controlsChannel then
                controls = message
            end
        else
            sleep()
        end
    end
end

local function PIDController(Kp, Ki, Kd, error, integral, derivative, prevError, dt)
    -- Calculate the proportional, integral, and derivative components
    local proportional = Kp * error
    integral = integral + error * dt
    derivative = (error - prevError) / dt
    
    -- Calculate output
    local output = proportional + (Ki * integral) + (Kd * derivative)

    -- Return the PID output and updated integral and previous error
    return output, integral, error
end

local function calculateProjectedY(currentY, currentPitch, currentVelocity, distance)
    -- Convert pitch to radians for calculation
    local pitchRad = math.rad(currentPitch)
    -- Estimate the change in Y based on the pitch, velocity, and distance
    local projectedY = currentY + math.tan(pitchRad) * distance
    return projectedY
end

parallel.waitForAny(
    function()
        while true do
            print("controls: "..textutils.serialize(controls).." This is controller of missile ID: "..missileId)
            if controls and controls.fireMissile and controls.fireMissile[missileId] and controls.fireMissile[missileId].launch == true then
                target = controls.fireMissile[missileId]
                print("launching")
                break
            end
            sleep()
        end
    end,
    modemMessage
)
print("Scaning for target")

--lock on
local targetPos = ship.getWorldspacePosition()
sleep(0.01)
local targetVel = ship.getVelocity()
targetPos.x = targetPos.x + targetVel.x * 2
targetPos.z = targetPos.z + targetVel.y * 2

local yaw = math.deg(ship.getYaw())
local pitch = math.deg(ship.getPitch()) * (90/28.6478)

local results = radar.scanForShips(3000)
local displayData = {}
print(results)

if target.type == "ship" then
    if not results or #results == 0 then
        table.insert(displayData, "No objects detected.")
    else      
        local smallestCombinedDiff = math.huge  -- Initialize with a large value
        local finalTargetYaw = nil
        local finalTargetPitch = nil
        local finalDistance = nil
        local closestDistanceWithSmallDiff = math.huge  -- New variable for closest distance with small combined diff
        
        -- Assuming 'yaw' and 'pitch' are the current ship's yaw and pitch angles
        local pos = ship.getWorldspacePosition()
        local yaw = math.deg(ship.getYaw()) + 180
        if yaw > 360 then yaw = yaw - 360 end
        local pitch = math.deg(getPitch())

        for i, object in ipairs(results) do
            if object.mass > 1000 then
                -- Calculate dx, dy, dz from ship to object
                local dx = object.pos.x - pos.x
                local dy = object.pos.y - pos.y
                local dz = object.pos.z - pos.z

                -- Calculate bearing (yaw) from ship to object
                local angleFromSouth = math.atan2(dx, dz)
                local bearingFromSouth = math.deg(angleFromSouth)
                local targetYaw = (180 - bearingFromSouth) % 360

                -- Calculate yaw difference
                local yawDiff = (targetYaw - yaw + 180) % 360 - 180

                -- Calculate pitch difference
                local horizontalDistance = math.sqrt(dx * dx + dz * dz)
                local targetPitch = math.deg(math.atan2(dy, horizontalDistance))
                local pitchDiff = targetPitch - (-pitch)

                -- Calculate the Euclidean distance (for prioritization)
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                -- Combine yaw and pitch differences into a single score (weighted sum or simply adding)
                local combinedDiff = math.abs(yawDiff) + math.abs(pitchDiff)

                -- Additional logic: If combinedDiff is less than 20, lock onto the closest target
                if object.id == target.id then
                    closestDistanceWithSmallDiff = distance
                    lockedId = object.id
                    intialPosition = object.pos
                    initialDistance = horizontalDistance
                    print("Target with combinedDiff < 20, Distance: ", distance, " Locked target ID: ", object.id)
                end
            end
        end
        
        if lockedId and intialPosition then
            print("Closest Object ID:", lockedId)
            print("X: "..intialPosition.x.." Y: "..intialPosition.y.." Z: "..intialPosition.z)
            print("initialDistance: "..initialDistance)
        else
            print("No large objects detected.")
        end
    end
else
    local pos = ship.getWorldspacePosition()
    local dx = target.pos.x - pos.x
    local dy = target.pos.y - pos.y
    local dz = target.pos.z - pos.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    intialPosition = target.pos
    initialDistance = math.sqrt(dx * dx + dz * dz)
end

local function throttleControl(throttle)
    redstone.setAnalogOutput("front",math.min(tonumber(throttle),15))
end

print("Locked Target:", lockedId)
print("X: "..intialPosition.x.." Y: "..intialPosition.y.." Z: "..intialPosition.z)
--[[modem.transmit(throttleChannel, 0, "unlock")
sleep(0.2)
modem.transmit(throttleChannel, 0, 5)
sleep(1.3)
modem.transmit(throttleChannel, 0, 0)]]
throttleControl(5)
sleep(0.8)
throttleControl(0)

local function initial()
    local results = radar.scanForShips(2000)
    pos = ship.getWorldspacePosition()
    local yaw = math.deg(ship.getYaw()) + 180
    if yaw>360 then yaw = yaw - 360 end
    local missileVelocity = ship.getVelocity()
    local misisleSpeed = math.sqrt(missileVelocity.x ^ 2 + missileVelocity.y ^ 2 + missileVelocity.z ^ 2)
    local pitch = math.deg(getPitch())
    local flightControl = {
        pitchUp = nil, pitchDown, yawLeft = nil, yawRight = nil, throttle = nil
    }
    print("pitch: "..pitch)
    
    if target.type == "ship" then
        for i, object in ipairs(results) do
            if object.id == lockedId then
                targetPos = object.pos
                targetVel = object.velocity
                local dx = targetPos.x - pos.x
                local dy = targetPos.y - pos.y
                local dz = targetPos.z - pos.z
                local immediateDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
                missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
                if missileSpeed < 0.1 then missileSpeed = 0.1 end

                -- Update pitch, yaw, and distance
                local estimateTime = immediateDistance/missileSpeed
                local estimateX = targetPos.x + targetVel.x * math.min(estimateTime,1)
                local estimateY = targetPos.y + targetVel.y * math.min(estimateTime,1)
                local estimateZ = targetPos.z + targetVel.z * math.min(estimateTime,1)

                local dx = estimateX - pos.x
                local dy = estimateY - pos.y
                local dz = estimateZ - pos.z

                local targetHorizontalDistance = math.sqrt(dx * dx + dz * dz)
                
                TargetYaw = math.deg(math.atan2(-dx, dz))
                TargetYaw = (TargetYaw + 180) % 360

                projectedMissileY = pos.y + missileVelocity.y * estimateTime
                yLevelDiff = targetPos.y - projectedMissileY
                TargetPitch = math.deg(math.atan2(dy, targetHorizontalDistance))

                targetAltitude = targetPos.y

                yawError = TargetYaw - yaw
                pitchError = TargetPitch - (-pitch)
                pitchHeightDiff = pitchError * K_pitchDiff + yLevelDiff * k_heightDiff

                -- Output diagnostics
            end
        end
    elseif target.type == "waypoint" then
        targetPos = target.pos

        local dx = targetPos.x - pos.x
        local dy = targetPos.y - pos.y
        local dz = targetPos.z - pos.z
        local immediateDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
        missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
        if missileSpeed < 0.1 then missileSpeed = 0.1 end

        local estimateTime = immediateDistance/missileSpeed

        local targetHorizontalDistance = math.sqrt(dx * dx + dz * dz)
        
        TargetYaw = math.deg(math.atan2(-dx, dz))
        TargetYaw = (TargetYaw + 180) % 360

        projectedMissileY = pos.y + missileVelocity.y * estimateTime
        yLevelDiff = targetPos.y - projectedMissileY
        TargetPitch = math.deg(math.atan2(dy, targetHorizontalDistance))

        targetAltitude = targetPos.y

        yawError = TargetYaw - yaw
        pitchError = TargetPitch - (-pitch)
        pitchHeightDiff = pitchError * K_pitchDiff + yLevelDiff * k_heightDiff
        print(pitch)
    end

    -- Ensure yaw is between -180 and 180 for error
    if yawError > 180 then
        yawError = yawError - 360
    elseif yawError < -180 then
        yawError = yawError + 360
    end

    -- PID control for yaw
    local yawOutput, yawIntegral, yawPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, yawError, yawIntegral, (yawError - yawPrevError), yawPrevError, dt)
    yawOutput = math.min(math.max(yawOutput, -5), 5)
    if -pitch > 30 or pos.y - targetAltitude > 35 then
        pitchOutput = -1
    else
        pitchOutput = 3
    end

    --yaw and pitch flight control
    if yawOutput > 0 then
        redstone.setOutput("right", true)
        redstone.setOutput("left", false)
        redstone.setAnalogOutput("right", math.abs(yawOutput))
    elseif yawOutput < 0 then
        redstone.setOutput("left", true)
        redstone.setOutput("right", false)
        redstone.setAnalogOutput("left", math.abs(yawOutput))
    else
        redstone.setOutput("right", false)
        redstone.setOutput("left", false)
    end

    if pitchOutput > 0.1 then
        local adjustedPitchOutput = math.max(math.abs(pitchOutput),1)
        redstone.setOutput("top", true)
        redstone.setOutput("bottom", false)
        redstone.setAnalogOutput("top", math.min(adjustedPitchOutput, 15))
    elseif pitchOutput < -0.1 then
        local adjustedPitchOutput = math.max(math.abs(pitchOutput),1)
        redstone.setOutput("bottom", true)
        redstone.setOutput("top", false)
        redstone.setAnalogOutput("bottom", math.min(adjustedPitchOutput, 15))
    else
        redstone.setOutput("top", false)
        redstone.setOutput("bottom", false)
    end


    --throttle control
    if missileSpeed < 60 then
        --modem.transmit(throttleChannel, 0, 2)  -- Increase throttle
        throttleControl(4)
    else
        throttleControl(0)
    end
end

local function terminal()
    local results = radar.scanForShips(2000)
    pos = ship.getWorldspacePosition()
    local yaw = math.deg(ship.getYaw()) + 180
    if yaw>360 then yaw = yaw - 360 end
    local missileVelocity = ship.getVelocity()
    local misisleSpeed = math.sqrt(missileVelocity.x ^ 2 + missileVelocity.y ^ 2 + missileVelocity.z ^ 2)
    local pitch = math.deg(getPitch())
    local flightControl = {
        pitchUp = nil, pitchDown, yawLeft = nil, yawRight = nil, throttle = nil
    }
    local targetSpeed = 0

    if target.type == "ship" then
        for i, object in ipairs(results) do
            if object.id == lockedId then
                -- Update position and targetVel
                targetPos = object.pos
                targetVel = object.velocity
                targetSpeed = math.sqrt(targetVel.x^2 + targetVel.y^2 + targetVel.z^2)
                local dx = targetPos.x - pos.x
                local dy = targetPos.y - pos.y
                local dz = targetPos.z - pos.z
                local immediateDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
                missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
                if missileSpeed < 0.1 then missileSpeed = 0.1 end

                -- Update pitch, yaw, and distance
                local estimateTime = immediateDistance/70
                local estimateX = targetPos.x + targetVel.x * math.min(estimateTime,8)
                local estimateY = targetPos.y + targetVel.y * math.min(estimateTime,8)
                local estimateZ = targetPos.z + targetVel.z * math.min(estimateTime,8)

                local dx = estimateX - pos.x
                local dy = estimateY - pos.y
                local dz = estimateZ - pos.z

                local targetHorizontalDistance = math.sqrt(dx * dx + dz * dz)
                
                TargetYaw = math.deg(math.atan2(-dx, dz))
                TargetYaw = (TargetYaw + 180) % 360

                projectedMissileY = pos.y + missileVelocity.y * estimateTime
                yLevelDiff = targetPos.y - projectedMissileY
                TargetPitch = math.deg(math.atan2(dy, targetHorizontalDistance))

                yawError = TargetYaw - yaw
                pitchError = TargetPitch - (-pitch)

                pitchHeightDiff = pitchError * K_pitchDiff + yLevelDiff * k_heightDiff
                print(pitch)
                -- Output diagnostics
            end
        end
    elseif target.type == "waypoint" then
        -- Update position and targetVel
        targetPos = target.pos

        local dx = targetPos.x - pos.x
        local dy = targetPos.y - pos.y
        local dz = targetPos.z - pos.z
        local immediateDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
        missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
        if missileSpeed < 0.1 then missileSpeed = 0.1 end

        -- Update pitch, yaw, and distance
        local estimateTime = immediateDistance/missileSpeed

        local targetHorizontalDistance = math.sqrt(dx * dx + dz * dz)
        
        TargetYaw = math.deg(math.atan2(-dx, dz))
        TargetYaw = (TargetYaw + 180) % 360

        projectedMissileY = pos.y + missileVelocity.y * estimateTime
        yLevelDiff = targetPos.y - projectedMissileY
        TargetPitch = math.deg(math.atan2(dy, targetHorizontalDistance))

        yawError = TargetYaw - yaw
        pitchError = TargetPitch - (-pitch)

        pitchHeightDiff = pitchError * K_pitchDiff + yLevelDiff * k_heightDiff
    end

    -- Ensure yaw is between -180 and 180 for error
    if yawError > 180 then
        yawError = yawError - 360
    elseif yawError < -180 then
        yawError = yawError + 360
    end

    if previousDistance then
        deltaDistance = previousDistance - immediateDistance
    else
        deltaDistance = 0 -- Initialize if this is the first frame
    end
    previousDistance = immediateDistance

    -- PID control for yaw
    local yawOutput, yawIntegral, yawPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, yawError, yawIntegral, (yawError - yawPrevError), yawPrevError, dt)
    yawOutput = math.min(math.max(yawOutput, -5), 5)

    -- PID control for pitch
    local pitchOutput, pitchIntegral, pitchHeightPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchHeightDiff, pitchIntegral, (pitchHeightDiff - pitchHeightPrevError), pitchHeightPrevError, dt)
    pitchOutput = math.min(math.max(pitchOutput, -7), 7)
    print("yawOutput: "..yawOutput.." pitchOutput: "..pitchOutput)

    --yaw and pitch flight control
    if yawOutput > 0 then
        redstone.setOutput("right", true)
        redstone.setOutput("left", false)
        redstone.setAnalogOutput("right", math.abs(yawOutput))
    elseif yawOutput < 0 then
        redstone.setOutput("left", true)
        redstone.setOutput("right", false)
        redstone.setAnalogOutput("left", math.abs(yawOutput))
    else
        redstone.setOutput("right", false)
        redstone.setOutput("left", false)
    end

    if pitchOutput > 0.1 then
        local adjustedPitchOutput = math.max(math.abs(pitchOutput),1)
        redstone.setOutput("top", true)
        redstone.setOutput("bottom", false)
        redstone.setAnalogOutput("top", math.min(adjustedPitchOutput, 15))
    elseif pitchOutput < -0.1 then
        local adjustedPitchOutput = math.max(math.abs(pitchOutput),1)
        redstone.setOutput("bottom", true)
        redstone.setOutput("top", false)
        redstone.setAnalogOutput("bottom", math.min(adjustedPitchOutput, 15))
    else
        redstone.setOutput("top", false)
        redstone.setOutput("bottom", false)
    end

    --throttle control
    if (deltaDistance < 1 or missileSpeed < 30) and missileSpeed < 60 then
        --modem.transmit(throttleChannel, 0, 2)  -- Apply throttle to increase speed
        throttleControl(4)
        print("Increasing throttle: Missile speed is less than 2x target speed")
    else
        --modem.transmit(throttleChannel, 0, 0)  -- Maintain current throttle
        throttleControl(0)
        print("Maintaining throttle: Missile speed is sufficient")
    end
end

local function fuze(distance,targetSpeed)
    local results = radar.scanForShips(2000)
    pos = ship.getWorldspacePosition()
    local missileVelocity = ship.getVelocity()
    local missileCurrentSpeed = math.sqrt(missileVelocity.x ^ 2 + missileVelocity.y ^ 2 + missileVelocity.z ^ 2)
    local direction = {x = missileVelocity.x / missileCurrentSpeed, y = missileVelocity.y / missileCurrentSpeed, z = missileVelocity.z / missileCurrentSpeed}


    -- Proximity fuze
    if (distance > closestDistance and distance < 15) or distance < 5 or (targetSpeed < 20 and distance < 15) then
        print("Proximity fuze detonating")
        redstone.setOutput("back", true)
        sleep(0.1)
        redstone.setOutput("front", false)
        redstone.setOutput("left", false)
        redstone.setOutput("bottom", false)
        redstone.setOutput("right", false)
        redstone.setOutput("back", false)
        redstone.setOutput("top", false)
        throttleControl(0)
        error("Proximity fuze detonated")
    else
        closestDistance = distance
    end

    -- Velocity change calculation (delta velocity)
    local deltaVelocity = {
        x = missileVelocity.x - lastVelocity.x,
        y = missileVelocity.y - lastVelocity.y,
        z = missileVelocity.z - lastVelocity.z
    }

    -- Normalize the delta velocity
    local deltaVelocityMagnitude = math.sqrt(deltaVelocity.x^2 + deltaVelocity.y^2 + deltaVelocity.z^2)
    local normalizedDeltaVelocity = {
        x = deltaVelocity.x / deltaVelocityMagnitude,
        y = deltaVelocity.y / deltaVelocityMagnitude,
        z = deltaVelocity.z / deltaVelocityMagnitude
    }

    -- Calculate the dot product to check if the velocity change is opposite to the missile's direction
    local dotProduct = normalizedDeltaVelocity.x * direction.x + normalizedDeltaVelocity.y * direction.y + normalizedDeltaVelocity.z * direction.z

    -- Calculate speed change (magnitude of delta velocity)
    local deltaSpeed = math.abs(missileCurrentSpeed - lastSpeed)
    lastSpeed = missileCurrentSpeed
    lastVelocity = missileVelocity
    -- Handle vertical and horizontal deceleration separately
    local verticalDeltaVelocity = math.abs(deltaVelocity.z)
    local horizontalDeltaVelocity = math.sqrt(deltaVelocity.x^2 + deltaVelocity.y^2)

    -- Detonate if there is significant deceleration in the horizontal direction, ignoring vertical changes (during dives)
    if missileCurrentSpeed > 0 and dotProduct < 0 and horizontalDeltaVelocity > 7 and missileCurrentSpeed < 20 then
        -- Only detonate if horizontal deceleration exceeds threshold, avoid vertical motion influencing fuze
        print("Acceleration impact fuze detonating")
        redstone.setOutput("back", true)
        sleep(0.1)
        redstone.setOutput("front", false)
        redstone.setOutput("left", false)
        redstone.setOutput("bottom", false)
        redstone.setOutput("right", false)
        redstone.setOutput("back", false)
        redstone.setOutput("top", false)
        throttleControl(0)
        error("Acceleration impact fuze detonated")
    end
end

while true do
    local results = radar.scanForShips(2000)
    pos = ship.getWorldspacePosition()
    local targetSpeed = 0
    local horizontalDistance,distance,targetSize

    if target.type == "ship" then
        for i, object in ipairs(results) do
            if object.id == lockedId then
                targetPos = object.pos
                targetVel = object.velocity
                targetSpeed = math.sqrt(targetVel.x^2 + targetVel.y^2 + targetVel.z^2)

                local dx = targetPos.x - pos.x
                local dy = targetPos.y - pos.y
                local dz = targetPos.z - pos.z
                targetSize = object.size
                horizontalDistance = math.sqrt(dx * dx + dz * dz)
                distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            end
        end
    elseif target.type == "waypoint" then
        local dx = target.pos.x - pos.x
        local dy = target.pos.y - pos.y
        local dz = target.pos.z - pos.z
        horizontalDistance = math.sqrt(dx * dx + dz * dz)
        distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    print("horizontalDistance: "..horizontalDistance)
    print("targetSpeed: "..targetSpeed)

    -- Check conditions for terminal phase
    if horizontalDistance < 180 or targetSpeed > 15 then
        print("terminal phrase")
        terminal()
        fuze(distance,targetSpeed)
    else
        print("initial phrase")
        initial()
    end
end




