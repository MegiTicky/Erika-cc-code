local radar = peripheral.find("sp_radar")
local modem = peripheral.find("modem")
local topFlap = peripheral.wrap("top")
local bottomFlap = peripheral.wrap("bottom")
local leftFlap = peripheral.wrap("back")
local rightFlap = peripheral.wrap("front")

redstone.setOutput("front",false)
redstone.setOutput("left",false)
redstone.setOutput("bottom",false)
redstone.setOutput("right",false)
redstone.setOutput("back",false)

local controls = {}
local target = {}
local lockedId = nil
local targetPos, targetVel, TargetYaw, TargetPitch
local Kp_yaw, Ki_yaw, Kd_yaw = 0.4, 0.005, 0.009
local Kp_pitch, Ki_pitch, Kd_pitch = 0.24, 0.065, 0.0052
local Kp_roll, Ki_roll,Kd_roll = 0.16,0,0.0035
local Kp_throttle, Ki_throttle, Kd_throttle = 0.2, 0.1, 0.02
local K_pitchDiff, k_heightDiff = 1,0
local projectedMissileY,yLevelDiff,initialDistance,targetAltitude
local closestDistance = math.huge

local highThrust = 24000

-- Initialize error, integral, and derivative terms for yaw and pitch
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0

local pitchError = 0
local pitchIntegral = 0
local pitchHeightPrevError = 0

local rollError,rollIntegral,rollPrevError = 0,0,0

local dt = 0.1

local deltaDistance = 0
local lastDistance = 0
local lastTime = os.clock()

local detonationHeight = 70

local controlsChannel = 1400
local missileInfoChannel = controlsChannel + 10

if modem then 
    modem.open(controlsChannel)
    modem.open(missileInfoChannel)
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
    return -math.asin(normalizedMatrix[2][3]) -- Extract pitch from the matrix
end

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

local function broadCastid()
    while true do
        local id = ship.getId()
        local missileInfo = {id = id, type = "GBU-42", launchState = false}
        modem.transmit(missileInfoChannel,0,missileInfo)
        sleep()
    end
end

parallel.waitForAny(
    function()
        while true do
            print("controls: "..textutils.serialize(controls))
            missileId = ship.getId()
            if controls and controls.fireMissile and controls.fireMissile[missileId] and controls.fireMissile[missileId].launch == true then
                target = controls.fireMissile[missileId]
                print("launching")
                break
            end
            sleep()
        end
    end,
    modemMessage,
    broadCastid
)
print("Scaning for target")

local function broadCastid()
    while true do
        local id = ship.getId()
        local missileInfo = {id = id, type = "GBU-42", launchState = true}
        print()
        modem.transmit(missileInfoChannel,0,missileInfo)
        sleep()
    end
end

--lock on
local targetPos = ship.getWorldspacePosition()
sleep(0.01)
local targetVel = ship.getVelocity()
targetPos.x = targetPos.x + targetVel.x * 2
targetPos.z = targetPos.z + targetVel.y * 2

local yaw = math.deg(getYaw())
local pitch = math.deg(getPitch()) * (90/28.6478)

local results = radar.scanForShips(4000)
local displayData = {}
print(results)
sleep(0.1)

local fastestSpeed = 0

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
        local yaw = math.deg(getYaw()) + 180
        if yaw > 360 then yaw = yaw - 360 end
        local pitch = math.deg(getPitch())

        for i, object in ipairs(results) do
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
        
        if lockedId and intialPosition then
            print("Closest Object ID:", lockedId)
            print("X: "..intialPosition.x.." Y: "..intialPosition.y.." Z: "..intialPosition.z)
            print("initialDistance: "..initialDistance)
        else
            print("Target not dectected")
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

print("Locked Target:", lockedId)
print("X: "..intialPosition.x.." Y: "..intialPosition.y.." Z: "..intialPosition.z)
topFlap.assemble()
bottomFlap.assemble()
leftFlap.assemble()
rightFlap.assemble()

redstone.setOutput("left",true)
sleep(0.3)
redstone.setOutput("left",false)


local function initial()
    local results = radar.scanForShips(4000)
    pos = ship.getWorldspacePosition()
    local yaw = math.deg(getYaw())
    if yaw>360 then yaw = yaw - 360 end
    local missileVelocity = ship.getVelocity()
    local misisleSpeed = math.sqrt(missileVelocity.x ^ 2 + missileVelocity.y ^ 2 + missileVelocity.z ^ 2)
    local pitch = math.deg(getPitch())
    local flightControl = {
        pitchUp = nil, pitchDown, yawLeft = nil, yawRight = nil, throttle = nil
    }
    
    if target.type == "ship" then
        for i, object in ipairs(results) do
            if object.id == lockedId then
                targetPos = object.pos
                targetVel = object.velocity
                local dx = targetPos.x - pos.x
                local dy = targetPos.y - pos.y + detonationHeight
                local dz = targetPos.z - pos.z
                local immediateDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
                missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
                if missileSpeed < 0.1 then missileSpeed = 0.1 end

                -- Update pitch, yaw, and distance
                local estimateTime = immediateDistance/missileSpeed
                local estimateX = targetPos.x + targetVel.x * math.min(estimateTime,1)
                local estimateY = targetPos.y + detonationHeight
                local estimateZ = targetPos.z + targetVel.z * math.min(estimateTime,1)

                local dx = estimateX - pos.x
                local dy = estimateY - pos.y
                local dz = estimateZ - pos.z

                local targetHorizontalDistance = math.max(math.sqrt(dx * dx + dz * dz) - detonationHeight,0)
                
                TargetYaw = math.deg(math.atan2(-dx, dz))
                TargetYaw = (TargetYaw + 180) % 360

                projectedMissileY = pos.y + missileVelocity.y * estimateTime
                yLevelDiff = targetPos.y - projectedMissileY
                TargetPitch = math.deg(math.atan2(dy, targetHorizontalDistance))

                targetAltitude = targetPos.y

                yawError = TargetYaw - yaw
                pitchError = TargetPitch - (-pitch)
                rollError = math.deg(getRoll())

                pitchHeightDiff = pitchError * K_pitchDiff + yLevelDiff * k_heightDiff
            end
        end
    elseif target.type == "waypoint" then
        targetPos = target.pos

        local dx = targetPos.x - pos.x
        local dy = targetPos.y - pos.y + detonationHeight
        local dz = targetPos.z - pos.z
        local immediateDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
        missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
        if missileSpeed < 0.1 then missileSpeed = 0.1 end

        local estimateTime = immediateDistance/missileSpeed

        local targetHorizontalDistance = math.max(math.sqrt(dx * dx + dz * dz) - detonationHeight,0)
        
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
    yawOutput = -math.min(math.max(yawOutput, -45), 45) / (1+math.abs(rollError)*0.1)

    local pitchOutput, pitchIntegral, pitchHeightPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchHeightDiff, pitchIntegral, (pitchHeightDiff - pitchHeightPrevError), pitchHeightPrevError, dt)
    pitchOutput = -math.min(math.max(pitchOutput, -30), 30)  / (1+math.abs(rollError)*0.1)

    local rollOutput,rollIntegral,rollPrevError = PIDController(Kp_roll, Ki_roll, Kd_roll, rollError, rollIntegral, (rollError - rollPrevError), rollPrevError, dt)
    rollOutput = -math.min(math.max(rollOutput, -10), 10)

    
    if yawOutput > 0 then
        topFlap.setAngle(yawOutput)
        bottomFlap.setAngle(yawOutput)
    elseif yawOutput < 0 then
        topFlap.setAngle(yawOutput)
        bottomFlap.setAngle(yawOutput)
    else
        topFlap.setAngle(0)
        bottomFlap.setAngle(0)
    end

     if pitchOutput > 0.1 then
        leftFlap.setAngle(pitchOutput + rollOutput)
        rightFlap.setAngle(pitchOutput - rollOutput)
    elseif pitchOutput < -0.1 then
        leftFlap.setAngle(pitchOutput + rollOutput)
        rightFlap.setAngle(pitchOutput - rollOutput)
    else
        leftFlap.setAngle(0)
        rightFlap.setAngle(0)
    end
end

local function terminal()
    local results = radar.scanForShips(4000)
    pos = ship.getWorldspacePosition()
    local yaw = math.deg(getYaw())
    if yaw>360 then yaw = yaw - 360 end
    local missileVelocity = ship.getVelocity()
    local misisleSpeed = math.sqrt(missileVelocity.x ^ 2 + missileVelocity.y ^ 2 + missileVelocity.z ^ 2)
    local pitch = math.deg(getPitch())
    
    local targetSpeed = 0

    if target.type == "ship" then
        for i, object in ipairs(results) do
            if object.id == lockedId then
                -- Update position and targetVel
                targetPos = object.pos
                targetVel = object.velocity
                targetSpeed = math.sqrt(targetVel.x^2 + targetVel.y^2 + targetVel.z^2)
                local dx = targetPos.x - pos.x
                local dy = targetPos.y + detonationHeight/1.8 - pos.y
                local dz = targetPos.z - pos.z
                local immediateDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
                missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
                if missileSpeed < 0.1 then missileSpeed = 0.1 end

                -- Update pitch, yaw, and distance
                local estimateTime = immediateDistance/missileSpeed

                local targetHorizontalDistance = math.max(math.sqrt(dx * dx + dz * dz),0)
                
                TargetYaw = math.deg(math.atan2(-dx, dz))
                TargetYaw = (TargetYaw + 180) % 360

                projectedMissileY = pos.y + missileVelocity.y * estimateTime
                yLevelDiff = targetPos.y - projectedMissileY
                TargetPitch = math.deg(math.atan2(dy, targetHorizontalDistance))

                yawError = TargetYaw - yaw
                pitchError = TargetPitch - (-pitch)
                rollError = math.deg(getRoll())

                pitchHeightDiff = pitchError * K_pitchDiff + yLevelDiff * k_heightDiff
                -- Output diagnostics
            end
        end
    elseif target.type == "waypoint" then
        -- Update position and targetVel
        targetPos = target.pos

        local dx = targetPos.x - pos.x
        local dy = targetPos.y + detonationHeight/1.8 - pos.y
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
        rollError = math.deg(getRoll())

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
    yawOutput = -math.min(math.max(yawOutput, -30), 30)  / (1+math.abs(rollError)*0.1)

    -- PID control for pitch
    local pitchOutput, pitchIntegral, pitchHeightPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchHeightDiff, pitchIntegral, (pitchHeightDiff - pitchHeightPrevError), pitchHeightPrevError, dt)
    pitchOutput = -math.min(math.max(pitchOutput, -30), 30)  / (1+math.abs(rollError)*0.1)
  

    -- PIDcontrol for roll
    local rollOutput,rollIntegral,rollPrevError = PIDController(Kp_roll, Ki_roll, Kd_roll, rollError, rollIntegral, (rollError - rollPrevError), rollPrevError, dt)
    rollOutput = -math.min(math.max(rollOutput, -10), 10)

    --yaw and pitch flight control
    if yawOutput > 0 then
        topFlap.setAngle(yawOutput)
        bottomFlap.setAngle(yawOutput)
    elseif yawOutput < 0 then
        topFlap.setAngle(yawOutput)
        bottomFlap.setAngle(yawOutput)
    else
        topFlap.setAngle(0)
        bottomFlap.setAngle(0)
    end

    if pitchOutput > 0.1 then
        leftFlap.setAngle(pitchOutput + rollOutput)
        rightFlap.setAngle(pitchOutput - rollOutput)
    elseif pitchOutput < -0.1 then
        leftFlap.setAngle(pitchOutput + rollOutput)
        rightFlap.setAngle(pitchOutput - rollOutput)
    else
        leftFlap.setAngle(0)
        rightFlap.setAngle(0)
    end

end

local function fuze()
    local results = radar.scanForShips(2000)
    pos = ship.getWorldspacePosition()
    local distance
    local missileVelocity = ship.getVelocity()
    local missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)

    if target.type == "ship" then
        for i, object in ipairs(results) do
            if object.id == lockedId then
                targetPos = object.pos
                local dx = targetPos.x - pos.x
                local dy = targetPos.y + detonationHeight/2 - pos.y
                local dz = targetPos.z - pos.z

                targetSpeed = math.sqrt(targetVel.x^2 + targetVel.y^2 + targetVel.z^2)
                distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                horizontalDistance = math.sqrt(dx * dx + dz * dz)
            end
        end
    elseif target.type == "waypoint" then
        local dx = target.pos.x - pos.x
        local dy = target.pos.y + detonationHeight - pos.y
        local dz = target.pos.z - pos.z
        distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        horizontalDistance = math.sqrt(dx * dx + dz * dz)
        targetSpeed = 0
    end

    -- **Calculate Rate of Change of Distance Using Delta Time**
    local deltaDistance = lastDistance - distance
    local rateOfClosure = math.min(deltaDistance / (dt + 0.0001),200)

    -- **Proximity Fuze Logic**
    local timeToHit = distance / (rateOfClosure + 0.0001)

    if horizontalDistance < 30 then
        print("Proximity fuze detonating!")
        redstone.setOutput("right", true)
        sleep(0.1)
        
        -- Reset all outputs
        local outputs = {"front", "left", "bottom", "right", "back", "top"}
        for _, output in ipairs(outputs) do
            redstone.setOutput(output, false)
        end

        print("Fastest speed: " .. missileSpeed)
        error("Proximity fuze detonated")
    end

    lastDistance = distance
end

parallel.waitForAny(
    function()
        while true do
            local results = radar.scanForShips(4000)
            pos = ship.getWorldspacePosition()
            local targetSpeed = 0

            if target.type == "ship" then
                for i, object in ipairs(results) do
                    if object.id == lockedId then
                        targetPos = object.pos
                        targetVel = object.velocity
                        targetSpeed = math.sqrt(targetVel.x^2 + targetVel.y^2 + targetVel.z^2)

                        local dx = targetPos.x - pos.x
                        local dy = targetPos.y - pos.y
                        local dz = targetPos.z - pos.z
                        horizontalDistance = math.sqrt(dx * dx + dz * dz)
                    end
                end
            elseif target.type == "waypoint" then
                local dx = target.pos.x - pos.x
                local dy = target.pos.y - pos.y
                local dz = target.pos.z - pos.z
                horizontalDistance = math.sqrt(dx * dx + dz * dz)
            end

            --print("horizontalDistance: "..horizontalDistance)
            --print("targetSpeed: "..targetSpeed)

            -- Check conditions for terminal phase

            --record speed
            local missileVelocity = ship.getVelocity()
            local missileSpeed = math.sqrt(missileVelocity.x ^ 2 + missileVelocity.y ^ 2 + missileVelocity.z ^ 2)
            if missileSpeed > fastestSpeed then fastestSpeed = missileSpeed end
            print("fastestSpeed: ",fastestSpeed)
            if horizontalDistance < detonationHeight then
                --print("terminal phrase")
                parallel.waitForAll(
                    terminal,
                    fuze
                )
            else
                initial()
            end
        end
    end,
    broadCastid
)