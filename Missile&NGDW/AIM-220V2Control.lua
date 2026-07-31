local radar = peripheral.find("sp_radar")
local modem = peripheral.wrap("right")
local topFlap = peripheral.wrap("top")
local bottomFlap = peripheral.wrap("bottom")
local leftFlap = peripheral.wrap("back")
local rightFlap = peripheral.wrap("front")

while not radar do
    print("Radar not connected, reset needed")
    radar = peripheral.find("sp_radar")
    sleep(0.5)
end

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
local Kp_yaw, Ki_yaw, Kd_yaw = 0.15, 0, 0.005
local Kp_pitch, Ki_pitch, Kd_pitch = 0.18, 0, 0.005
local Kp_roll, Ki_roll,Kd_roll = 0.02,0,0
local Kp_throttle, Ki_throttle, Kd_throttle = 0.2, 0.1, 0.02
local K_pitchDiff, k_heightDiff = 1,0
local projectedMissileY,yLevelDiff,initialDistance,targetAltitude
local closestDistance = math.huge

local highThrust = 15

-- Initialize error, integral, and derivative terms for yaw and pitch
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0

local pitchError = 0
local pitchIntegral = 0
local pitchPrevError = 0

local rollError,rollIntegral,rollPrevError = 0,0,0

local dt = 0.1

local deltaDistance = 0
local lastDistance = 0
local lastTime = os.clock()

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
        local missileInfo = {id = id, type = "AIM-220", launchState = false}
        modem.transmit(missileInfoChannel,0,missileInfo)
        print("Broadcasting missile info at channel: "..missileInfoChannel)
        print("Radar ready, ready for launch")
        sleep()
    end
end

parallel.waitForAny(
    function()
        while true do
            --print("controls: "..textutils.serialize(controls))
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
        local missileInfo = {id = id, type = "AIM-220", launchState = true}
        modem.transmit(missileInfoChannel,0,missileInfo)
        sleep()
    end
end

--lock on
local results = radar.scanForShips(4000)
local displayData = {}
print(textutils.serialize(target))

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

redstone.setAnalogOutput("top",highThrust)
redstone.setOutput("bottom",true)
sleep(0.3)
redstone.setAnalogOutput("top",0)
redstone.setOutput("bottom",false)

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
                local dy = targetPos.y - pos.y + 50
                local dz = targetPos.z - pos.z
                local immediateDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
                missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
                if missileSpeed < 0.1 then missileSpeed = 0.1 end

                -- Update pitch, yaw, and distance
                local estimateTime = immediateDistance/missileSpeed
                local estimateX = targetPos.x + targetVel.x * math.min(estimateTime,1)
                local estimateY = targetPos.y + 50
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
                rollError = math.deg(getRoll())

                pitchHeightDiff = pitchError * K_pitchDiff + yLevelDiff * k_heightDiff
            end
        end
    elseif target.type == "waypoint" then
        targetPos = target.pos

        local dx = targetPos.x - pos.x
        local dy = targetPos.y - pos.y + 100
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
    yawOutput = -math.min(math.max(yawOutput, -45), 45) / (1+math.abs(rollError)*0.1)

    local pitchOutput, pitchIntegral, pitchHeightPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchHeightDiff, pitchIntegral, (pitchHeightDiff - pitchHeightPrevError), pitchHeightPrevError, dt)
    pitchOutput = -math.min(math.max(pitchOutput, -30), 30)  / (1+math.abs(rollError)*0.1)

    local rollOutput,rollIntegral,rollPrevError = PIDController(Kp_roll, Ki_roll, Kd_roll, rollError, rollIntegral, (rollError - rollPrevError), rollPrevError, dt)
    rollOutput = -math.min(math.max(rollOutput, -10), 10)

    --yaw and pitch flight control
    if missileSpeed < 40 then --adjustment for yaw propeller bug
        yawOutput = yawOutput
        pitchOutput = pitchOutput * 2.3
        rollOutput = rollOutput
    end

    
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

    if missileSpeed < 60 then
        print("Speed below optimal, accelerating")
        redstone.setAnalogOutput("top",highThrust)
    else
        if yawOutput > 8 or pitchOutput > 8 or missileSpeed then
            redstone.setAnalogOutput("top",0)
        end
    end
end

local lastTargetPos, lastTargetVelocity, predictedTargetVelocity, predictedTargetAcceleration
local lastTargetAqquireTime = os.clock()

local function clampVectorMagnitude(vec, maxMag)
    local mag = math.sqrt(vec.x^2 + vec.y^2 + vec.z^2)
    if mag > maxMag then
        local scale = maxMag / mag
        return {
            x = vec.x * scale,
            y = vec.y * scale,
            z = vec.z * scale
        }
    end
    return vec
end

local lastTargetPos, lastTargetVelocity, predictedTargetVelocity, predictedTargetAcceleration
local lastTargetAqquireTime = os.clock()

local function predictFuturePosition(targetPos, targetVel, sourceX, sourceY, sourceZ, missileSpeed)
    local currentTime = os.clock()
    local dt = currentTime - lastTargetAqquireTime

    --[[ Initialize predictedVelocity & predictedAcceleration if needed
    if not lastTargetPos then
        lastTargetPos = targetPos
        lastTargetVelocity = targetVel
        predictedTargetVelocity = targetVel
        predictedTargetAcceleration = {x = 0, y = 0, z = 0}
        lastTargetAqquireTime = currentTime
    elseif dt >= 0.5 then
        -- Estimate velocity
        predictedTargetVelocity = {
            x = (targetPos.x - lastTargetPos.x) / dt,
            y = (targetPos.y - lastTargetPos.y) / dt,
            z = (targetPos.z - lastTargetPos.z) / dt
        }

        -- Estimate acceleration
        predictedTargetAcceleration = {
            x = (predictedTargetVelocity.x - lastTargetVelocity.x) / dt,
            y = (predictedTargetVelocity.y - lastTargetVelocity.y) / dt,
            z = (predictedTargetVelocity.z - lastTargetVelocity.z) / dt
        }
        predictedTargetAcceleration = {x = 0, y = 0, z = 0}
        -- Update previous values
        lastTargetPos = targetPos
        lastTargetVelocity = predictedTargetVelocity
        lastTargetAqquireTime = currentTime
    end]]

    -- Compute initial distance to target
    local dx = targetPos.x - sourceX
    local dy = targetPos.y - sourceY
    local dz = targetPos.z - sourceZ
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    -- Get ship's velocity
    local shipVelocity = ship.getVelocity()
    predictedTargetAcceleration = {x = 0, y = 0, z = 0}
    -- Initial estimate for travel time
    local estimateTime = distance / missileSpeed
    estimateTime = math.min(math.max(estimateTime,0.01),100)

    -- Predict future position using velocity and acceleration
    local estimateX = targetPos.x
        + (targetVel.x) * estimateTime
        + 0.5 * predictedTargetAcceleration.x * estimateTime * estimateTime

    local estimateY = targetPos.y
        + (targetVel.y) * estimateTime
        + 0.5 * predictedTargetAcceleration.y * estimateTime * estimateTime

    local estimateZ = targetPos.z
        + (targetVel.z - shipVelocity.z) * estimateTime
        + 0.5 * predictedTargetAcceleration.z * estimateTime * estimateTime

    -- Recalculate distance after initial estimate
    dx = estimateX - sourceX
    dy = estimateY - sourceY
    dz = estimateZ - sourceZ
    distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    --Refine estimateTime
    estimateTime = distance / missileSpeed
    estimateTime = math.min(math.max(estimateTime,0.01),8)

    -- Recompute future position with refined time
    estimateX = targetPos.x
        + (targetVel.x) * estimateTime
        + 0.5 * predictedTargetAcceleration.x * estimateTime * estimateTime

    estimateY = targetPos.y
        + (targetVel.y) * estimateTime
        + 0.5 * predictedTargetAcceleration.y * estimateTime * estimateTime

    estimateZ = targetPos.z
        + (targetVel.z) * estimateTime
        + 0.5 * predictedTargetAcceleration.z * estimateTime * estimateTime

    return {x = estimateX, y = estimateY, z = estimateZ}
end

local function terminal()
    local now = os.clock()
    dt = now - lastTime
    lastTime = now
    if dt <= 0 then dt = 0.001 end
    --print(textutils.serialize(target))
    local results = radar.scanForShips(8000)
    pos = ship.getWorldspacePosition()
    local yaw = math.deg(getYaw())
    if yaw>360 then yaw = yaw - 360 end
    missileVelocity = ship.getVelocity()
    missileSpeed = math.sqrt(missileVelocity.x ^ 2 + missileVelocity.y ^ 2 + missileVelocity.z ^ 2)
    pitch = math.deg(getPitch())
    
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

                --[[if not lastDistance then
                    lastDistance = immediateDistance
                else
                    deltaDistance = lastDistance - immediateDistance
                    rateOfClosure = math.min(deltaDistance / (dt + 0.0001))    
                end
                lastDistance = immediateDistance
                rateOfClosure = math.max(math.min(rateOfClosure,400),10)]]
                -- Calculate LOS unit vector
                local losLength = math.sqrt(dx^2 + dy^2 + dz^2)
                local losUnit = {
                    x = dx / losLength,
                    y = dy / losLength,
                    z = dz / losLength
                }
                if missileSpeed < 200 then rateOfChase = 200 else rateOfChase = missileSpeed end
                -- Compute rate of escape using dot product
                local rateOfEscape = targetVel.x * losUnit.x + targetVel.y * losUnit.y + targetVel.z * losUnit.z
                rateOfClosure = rateOfChase - rateOfEscape
                rateOfClosure = math.max(math.min(rateOfClosure,400),10)

                -- Update pitch, yaw, and distance
                local estimatePos = predictFuturePosition(targetPos,targetVel,pos.x,pos.y,pos.z,rateOfClosure)

                local dx = estimatePos.x - pos.x
                
                local dy = estimatePos.y - pos.y
                local dz = estimatePos.z - pos.z

                --[[ Old lead pursuit
                local estimateTime = immediateDistance/missileSpeed
                local estimateX = targetPos.x + targetVel.x * math.min(estimateTime)
                local estimateY = targetPos.y + targetVel.y * math.min(estimateTime)
                local estimateZ = targetPos.z + targetVel.z * math.min(estimateTime)

                local dx = estimateX - pos.x
                local dy = estimateY - pos.y
                local dz = estimateZ - pos.z
                local immediateDistance2nd = math.sqrt(dx * dx + dy * dy + dz * dz)

                local estimateTime2nd = math.min(immediateDistance/missileSpeed,8)
                local estimateX = targetPos.x + targetVel.x * math.min(estimateTime2nd)
                local estimateY = targetPos.y + targetVel.y * math.min(estimateTime2nd)
                local estimateZ = targetPos.z + targetVel.z * math.min(estimateTime2nd)

                local dx = estimateX - pos.x
                local dy = estimateY - pos.y
                local dz = estimateZ - pos.z
                --Old lead pursuit]]

                local targetHorizontalDistance = math.sqrt(dx * dx + dz * dz)
                
                TargetYaw = math.deg(math.atan2(-dx, dz))
                TargetYaw = (TargetYaw + 180) % 360

                TargetPitch = math.deg(math.atan2(dy, targetHorizontalDistance))

                yawError = TargetYaw - yaw
                pitchError = TargetPitch - (-pitch)
                rollError = math.deg(getRoll())
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
        rollError = math.deg(getRoll())

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
    yawOutput = -math.min(math.max(yawOutput, -10), 10)  / (1+math.abs(rollError)*0.1)

    -- PID control for pitch
    local pitchOutput, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchError, pitchIntegral, (pitchError - pitchPrevError), pitchPrevError, dt)
    pitchOutput = -math.min(math.max(pitchOutput, -10), 10)  / (1+math.abs(rollError)*0.1)
  

    -- PIDcontrol for roll
    local rollOutput,rollIntegral,rollPrevError = PIDController(Kp_roll, Ki_roll, Kd_roll, rollError, rollIntegral, (rollError - rollPrevError), rollPrevError, dt)
    rollOutput = -math.min(math.max(rollOutput, -10), 10)

    --yaw and pitch flight control
    if yawOutput > 0 then
        topFlap.setAngle(yawOutput - rollOutput)
        bottomFlap.setAngle(yawOutput + rollOutput)
    elseif yawOutput < 0 then
        topFlap.setAngle(yawOutput - rollOutput)
        bottomFlap.setAngle(yawOutput + rollOutput)
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

    print("yawOutput: "..yawOutput)
    print("pitchOutput: "..pitchOutput)
    print("rollOutput: "..rollOutput)
    print("missileSpeed: "..missileSpeed)
    print("rate of closure: "..rateOfClosure)
    if missileSpeed > fastestSpeed then fastestSpeed = missileSpeed end
    print("fastestSpeed: ",fastestSpeed)

    if missileSpeed < 60 then
        print("Speed below optimal, accelerating")
        redstone.setAnalogOutput("top",highThrust)
    else
        if yawOutput > 8 or pitchOutput > 8 or missileSpeed > 240 then
            redstone.setAnalogOutput("top",0)
        end
    end
end

--[[ ========== IMPROVED GUIDANCE SECTION ==========
local PN_GAIN = 4.0  -- Proportional Navigation constant (3-5 typical)
local MAX_G_LOAD = 30  -- Maximum g-load missile can handle
local MIN_G_LOAD = 1   -- Minimum g-load for control

-- Calculate line-of-sight rate and apply PN guidance
local function proportionalNavigation(targetPos, targetVel)
    local missilePos = ship.getWorldspacePosition()
    local missileVel = ship.getVelocity()
    
    -- Calculate relative position and velocity
    local relPos = {
        x = targetPos.x - missilePos.x,
        y = targetPos.y - missilePos.y,
        z = targetPos.z - missilePos.z
    }
    
    local relVel = {
        x = targetVel.x - missileVel.x,
        y = targetVel.y - missileVel.y,
        z = targetVel.z - missileVel.z
    }
    
    -- Calculate range and line-of-sight vector
    local range = math.sqrt(relPos.x^2 + relPos.y^2 + relPos.z^2)
    if range < 1 then range = 1 end  -- Avoid division by zero
    
    local los = {
        x = relPos.x / range,
        y = relPos.y / range,
        z = relPos.z / range
    }
    
    -- Calculate closing velocity
    local closingVel = -(relVel.x*los.x + relVel.y*los.y + relVel.z*los.z)
    
    -- Calculate line-of-sight rate
    local losRate = {
        x = (relVel.x + closingVel*los.x) / range,
        y = (relVel.y + closingVel*los.y) / range,
        z = (relVel.z + closingVel*los.z) / range
    }
    
    -- Calculate commanded acceleration using PN
    local cmdAccel = {
        x = PN_GAIN * closingVel * losRate.x,
        y = PN_GAIN * closingVel * losRate.y,
        z = PN_GAIN * closingVel * losRate.z
    }
    
    return cmdAccel
end

-- Convert acceleration commands to body-frame angles
local function accelToBodyAngles(cmdAccel, missileSpeed)
    local yawAccel = cmdAccel.x
    local pitchAccel = cmdAccel.y
    
    -- Convert to g-loads (1g = 9.8 m/s²)
    local yawG = yawAccel / 9.8
    local pitchG = pitchAccel / 9.8
    
    -- Constrain to missile capabilities
    yawG = math.min(math.max(yawG, -MAX_G_LOAD), MAX_G_LOAD)
    pitchG = math.min(math.max(pitchG, -MAX_G_LOAD), MAX_G_LOAD)
    
    -- Convert to control angles (more effective at higher speeds)
    local yawAngle = yawG * 2.0 * (60 / math.max(missileSpeed, 60))
    local pitchAngle = pitchG * 2.0 * (60 / math.max(missileSpeed, 60))
    
    return yawAngle, pitchAngle
end
local Kp_yaw, Ki_yaw, Kd_yaw = 0.24, 0, 0.005
-- ========== MODIFIED TERMINAL FUNCTION ==========
local function terminal()
    local now = os.clock()
    dt = now - lastTime
    lastTime = now
    if dt <= 0 then dt = 0.001 end
    
    local results = radar.scanForShips(8000)
    pos = ship.getWorldspacePosition()
    local yaw = math.deg(getYaw())
    if yaw > 360 then yaw = yaw - 360 end
    missileVelocity = ship.getVelocity()
    missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
    local pitch = math.deg(getPitch())
    
    local targetSpeed = 0
    local targetPos, targetVel

    if target.type == "ship" then
        for i, object in ipairs(results) do
            if object.id == lockedId then
                targetPos = object.pos
                targetVel = object.velocity
                targetSpeed = math.sqrt(targetVel.x^2 + targetVel.y^2 + targetVel.z^2)
                
                -- Calculate PN guidance
                local cmdAccel = proportionalNavigation(targetPos, targetVel)
                local yawAngle, pitchAngle = accelToBodyAngles(cmdAccel, missileSpeed)
                
                -- Convert to error signals
                yawError = -yawAngle  -- Invert for control surface direction
                pitchError = -pitchAngle
                
                -- Keep roll under control
                rollError = math.deg(getRoll())
            end
        end
    elseif target.type == "waypoint" then
        targetPos = target.pos
        targetVel = {x=0, y=0, z=0}
        
        -- Calculate PN guidance for waypoint
        local cmdAccel = proportionalNavigation(targetPos, targetVel)
        local yawAngle, pitchAngle = accelToBodyAngles(cmdAccel, missileSpeed)
        
        yawError = -yawAngle
        pitchError = -pitchAngle
        rollError = math.deg(getRoll())
    end

    -- Ensure yaw is between -180 and 180 for error
    if yawError > 180 then
        yawError = yawError - 360
    elseif yawError < -180 then
        yawError = yawError + 360
    end

    -- PID control for yaw (with PN guidance)
    local yawOutput, yawIntegral, yawPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, yawError, yawIntegral, (yawError - yawPrevError), yawPrevError, dt)
    yawOutput = - math.min(math.max(yawOutput, -10), 10) / (1 + math.abs(rollError)*0.1)

    -- PID control for pitch (with PN guidance)
    local pitchOutput, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchError, pitchIntegral, (pitchError - pitchPrevError), pitchPrevError, dt)
    pitchOutput = math.min(math.max(pitchOutput, -10), 10) / (1 + math.abs(rollError)*0.1)

    -- PID control for roll
    local rollOutput, rollIntegral, rollPrevError = PIDController(Kp_roll, Ki_roll, Kd_roll, rollError, rollIntegral, (rollError - rollPrevError), rollPrevError, dt)
    rollOutput = -math.min(math.max(rollOutput, -10), 10)

    -- Control surfaces
    topFlap.setAngle(yawOutput - rollOutput)
    bottomFlap.setAngle(yawOutput + rollOutput)
    leftFlap.setAngle(pitchOutput + rollOutput)
    rightFlap.setAngle(pitchOutput - rollOutput)

    -- Thrust management
    if missileSpeed < 60 then
        redstone.setAnalogOutput("top", highThrust)
    else
        if missileSpeed > 240 or math.abs(yawOutput) > 8 or math.abs(pitchOutput) > 8 then
            redstone.setAnalogOutput("top", 0)
        end
    end
end]]

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
                local dy = targetPos.y - pos.y
                local dz = targetPos.z - pos.z

                targetSpeed = math.sqrt(targetVel.x^2 + targetVel.y^2 + targetVel.z^2)
                distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            end
        end
    elseif target.type == "waypoint" then
        local dx = target.pos.x - pos.x
        local dy = target.pos.y - pos.y
        local dz = target.pos.z - pos.z
        distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        targetSpeed = 0
    end

    -- **Calculate Rate of Change of Distance Using Delta Time**
    local deltaDistance = lastDistance - distance
    local rateOfClosure = math.min(deltaDistance / (dt + 0.0001),200)

    -- **Proximity Fuze Logic**
    local timeToHit = distance / (rateOfClosure + 0.0001)

    if timeToHit < 0.4 and deltaDistance > 0 and distance < 50 then
        sleep(math.max(timeToHit - 0.05, 0)) -- Prevent negative sleep time
        print("Proximity fuze detonating!")
        redstone.setOutput("left", true)
        sleep(0.1)
        
        -- Reset all outputs
        local outputs = {"front", "left", "bottom", "right", "back", "top"}
        for _, output in ipairs(outputs) do
            redstone.setOutput(output, false)
        end

        print("Fastest speed: " .. missileSpeed)
        error("Proximity fuze detonated")
    end

    -- **Impact Fuze Logic**
    if redstone.getInput("right") and distance < 70 then
        print("Impact fuze detonating!")
        redstone.setOutput("left", true)
        sleep(0.1)

        -- Reset all outputs
        local outputs = {"front", "left", "bottom", "right", "back", "top"}
        for _, output in ipairs(outputs) do
            redstone.setOutput(output, false)
        end

        print("Fastest speed: " .. missileSpeed)
        error("Impact fuze detonated")
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
            if horizontalDistance < 200 then
                --print("terminal phrase")
                parallel.waitForAll(
                    terminal,
                    fuze
                )
            else
                --print("initial phrase")
                terminal()
            end
        end
    end,
    broadCastid
)