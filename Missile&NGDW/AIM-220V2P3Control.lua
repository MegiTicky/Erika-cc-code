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
        local slug = ship.getName()
        local missileInfo = {id = id, type = "AIM-220", launchState = false, slug = slug}
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
        local slug = ship.getName()
        local missileInfo = {id = id, type = "AIM-220", launchState = true, slug = slug}
        modem.transmit(missileInfoChannel,0,missileInfo)
        sleep()
    end
end

--lock on
local results = radar.scanForShips(4000)
local displayData = {}
print(textutils.serialize(target))

local fastestSpeed = 0

if target and target.type == "ship" then
    lockedId = target.id
end

print("Locked Target:", lockedId)

topFlap.assemble()
bottomFlap.assemble()
leftFlap.assemble()
rightFlap.assemble()

redstone.setAnalogOutput("top",highThrust)
redstone.setOutput("bottom",true)
sleep(0.3)
redstone.setAnalogOutput("top",0)
redstone.setOutput("bottom",false)

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

    -- Compute initial distance to target
    local dx = targetPos.x - sourceX
    local dy = targetPos.y - sourceY
    local dz = targetPos.z - sourceZ
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    --Initialize predictedVelocity & predictedAcceleration if needed
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
        print(textutils.serialize(predictedAcceleration))
        --predictedTargetAcceleration = {x = 0, y = 0, z = 0}
        -- Update previous values
        lastTargetPos = targetPos
        lastTargetVelocity = predictedTargetVelocity
        lastTargetAqquireTime = currentTime
    end

    -- Get ship's velocity
    local shipVelocity = ship.getVelocity()
    --predictedTargetAcceleration = {x = 0, y = 0, z = 0}
    -- Initial estimate for travel time
    local estimateTime = distance / missileSpeed
    estimateTime = math.min(math.max(estimateTime,0.01),100)

    -- Predict future position using velocity and acceleration
    local estimateX = targetPos.x
        + (predictedTargetVelocity.x) * estimateTime
        + 0 * predictedTargetAcceleration.x * estimateTime * estimateTime

    local estimateY = targetPos.y
        + (predictedTargetVelocity.y) * estimateTime
        + 0 * predictedTargetAcceleration.y * estimateTime * estimateTime

    local estimateZ = targetPos.z
        + (predictedTargetVelocity.z) * estimateTime
        + 0 * predictedTargetAcceleration.z * estimateTime * estimateTime

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
        + (predictedTargetVelocity.x) * estimateTime
        + 0.5 * predictedTargetAcceleration.x * estimateTime * estimateTime

    estimateY = targetPos.y
        + (predictedTargetVelocity.y) * estimateTime
        + 0.5 * predictedTargetAcceleration.y * estimateTime * estimateTime

    estimateZ = targetPos.z
        + (predictedTargetVelocity.z) * estimateTime
        + 0.5 * predictedTargetAcceleration.z * estimateTime * estimateTime

    return {x = estimateX, y = estimateY, z = estimateZ}
end

local function computerRollPitch(targetPos, missilePos, currentPitchDeg, currentRollDeg, currentYawDeg)
    -- Calculate the vector from the missile to the target
    local function vectorSubtract(v1, v2)
        return {x = v1.x - v2.x, y = v1.y - v2.y, z = v1.z - v2.z}
    end

    -- Compute the dot product of two vectors
    local function dotProduct(v1, v2)
        return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
    end

    -- Compute the cross product of two vectors
    local function crossProduct(v1, v2)
        return {
            x = v1.y * v2.z - v1.z * v2.y,  -- x
            y = v1.z * v2.x - v1.x * v2.z,  -- y
            z = v1.x * v2.y - v1.y * v2.x   -- z
        }
    end

    -- Normalize a vector
    local function normalizeVector(v)
        local mag = math.sqrt(v.x^2 + v.y^2 + v.z^2)
        return {x = v.x / mag, y = v.y / mag, z = v.z / mag}
    end

    -- Calculate the target vector
    local targetVec = vectorSubtract(targetPos, missilePos)

    -- Normalize the target vector (direction to the target)
    local targetDir = normalizeVector(targetVec)

    -- Convert current missile orientation angles to radians
    local pitchRad = math.rad(currentPitchDeg)
    local rollRad = math.rad(currentRollDeg)
    currentYawDeg = currentYawDeg + 180
    if currentYawDeg > 180 then currentYawDeg = currentYawDeg - 360 end
    local yawRad = math.rad(currentYawDeg)

    -- Forward vector (based on pitch and yaw)
    local forward = {
        x = -math.sin(yawRad) * math.cos(pitchRad),
        y = -math.sin(pitchRad),
        z = math.cos(yawRad) * math.cos(pitchRad)
    }

    -- Up vector (initially along the y-axis in missile body space)
    local up = {x = 0, y = 1, z = 0}

    -- Right vector (cross product of forward and up vectors)
    local right = crossProduct(forward, up)

    -- Project the target vector onto the plane formed by the up and right vectors
    local projection = vectorSubtract(targetVec, {
        x = dotProduct(targetVec, forward) * forward.x,
        y = dotProduct(targetVec, forward) * forward.y,
        z = dotProduct(targetVec, forward) * forward.z
    })

    -- Normalize the projection to get the target's position relative to the missile's plane
    local projectedTarget = normalizeVector(projection)

    -- Calculate the roll angle (angle between up and projected target)
    local rollAngleRad = math.acos(dotProduct(up, projectedTarget))
    local rollAngleDeg = rollAngleRad * 180 / math.pi

    -- Calculate the angle between projected target vector and the right vector
    local projectedRightError = math.acos(dotProduct(right, projectedTarget))
    print(projectedRightError)
    if projectedRightError > math.rad(90) then
        --target at left side of up vector
        rollAngleDeg = -rollAngleDeg
    else
        rollAngleDeg = rollAngleDeg
    end

    -- Calculate the sign of the roll using the cross product of the up vector and the projected target vector
    local crossSign = crossProduct(up, projectedTarget)

    -- If the z-component of the cross product is positive, the roll is counterclockwise
    -- If it's negative, the roll is clockwise
    if crossSign.z < 0 then
        rollAngleDeg = rollAngleDeg
    end

    -- Calculate the pitch angle (angle between forward and target direction)
    local pitchAngleRadError = math.acos(dotProduct(forward, targetDir))
    local pitchAngleDegError = pitchAngleRadError * 180 / math.pi

    -- Output the computed roll and pitch angles
    return rollAngleDeg, pitchAngleDegError
end

local function findSmallestDeltaAngle(requiredRoll, roll)
    -- Find flaps angle
    local flapsAngle = {
        top = roll,
        left = roll + 90,
        bottom = roll + 180,
        right = roll + 270
    }

    -- Axis names
    local axisNames = {
        "topLeftQua",
        "leftBottomQua",
        "bottomRightQua",
        "rightTopQua"
    }

    -- Initialize variables for smallest delta and closest axis
    local smallestDelta = math.huge
    local closestAxis = nil
    local closestAxisName = nil

    -- Iterate through axis angles and find smallest delta
    local axisAngles = {
        flapsAngle.top + 45, 
        flapsAngle.left + 45, 
        flapsAngle.bottom + 45, 
        flapsAngle.right + 45
    }

    -- Loop over axisAngles and axisNames together
    for i, angle in ipairs(axisAngles) do
        -- Normalize angle to the range -180 to 180
        local normalizedAngle = angle
        while normalizedAngle > 180 do normalizedAngle = normalizedAngle - 360 end
        while normalizedAngle < -180 do normalizedAngle = normalizedAngle + 360 end

        -- Calculate delta angle and normalize
        local deltaAngle = requiredRoll - normalizedAngle
        if deltaAngle > 180 then deltaAngle = deltaAngle - 360 end
        if deltaAngle < -180 then deltaAngle = deltaAngle + 360 end
        --print("deltaAngle: "..deltaAngle)
        -- Check if this delta is the smallest
        if math.abs(deltaAngle) < math.abs(smallestDelta) then
            smallestDelta = deltaAngle
            closestAxis = normalizedAngle
            closestAxisName = axisNames[i]  -- Get the name of the axis
            --print(axisNames[i])
        end
    end
    --print(closestAxisName)
    return smallestDelta, closestAxis, closestAxisName
end

local function PID(Kp, Ki, Kd, error, integral, prev_error, dt, min_out, max_out)
    -- Safety check for dt
    if dt <= 0 then dt = 0.05 end
    
    -- Proportional term
    local P = Kp * error
    
    -- Integral term (accumulate)
    integral = integral + error * dt
    local I = Ki * integral
    
    -- Derivative term
    local derivative = (error - prev_error) / dt
    local D = Kd * derivative
    
    -- Total output
    local output = P + I + D
    
    -- Clamp output if limits are provided
    if min_out and max_out then
        output = math.max(min_out, math.min(max_out, output))
    end
    
    -- Return output and updated state for next call
    return output, integral, error
end

local Kp_yaw, Ki_yaw, Kd_yaw = 0.15, 0, 0.005
local Kp_pitch, Ki_pitch, Kd_pitch = 0.18, 0, 0.0001
local Kp_roll, Ki_roll,Kd_roll = 0.022,0,0.00
local roll_integral,roll_prev_error=0,0

local function terminal()
    local now = os.clock()
    dt = now - lastTime
    lastTime = now
    if dt <= 0 then dt = 0.001 end
    dt = 0.05
    --print(textutils.serialize(target))
    local results = radar.scanForShips(8000)
    pos = ship.getWorldspacePosition()
    local yaw = math.deg(getYaw())
    if yaw>360 then yaw = yaw - 360 end
    missileVelocity = ship.getVelocity()
    missileSpeed = math.sqrt(missileVelocity.x ^ 2 + missileVelocity.y ^ 2 + missileVelocity.z ^ 2)
    pitch = math.deg(getPitch())
    roll = math.deg(getRoll())
    
    local targetSpeed = 0
    local estimatePos
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

                estimatePos = predictFuturePosition(targetPos,targetVel,pos.x,pos.y,pos.z,rateOfClosure)
            end
        end
    elseif target.type == "waypoint" then
        -- Update position and targetVel
        estimatePos = target.pos
    end

    requiredRoll, deltaPitch = computerRollPitch(estimatePos, pos, pitch, roll, yaw)
    --the requiredRoll -ne is clockwise, i actually want it to be positive when clockwise
    requiredRoll = requiredRoll
    print("requiredRoll: "..requiredRoll.." deltaPitch: "..deltaPitch)
    local deltaRoll, axis, axisName = findSmallestDeltaAngle(requiredRoll, roll)

    print("smallestDelta: "..deltaRoll.." closestAxisName: "..axisName)

    --PID for roll
    rollError = deltaRoll
    local rollOutput,rollIntegral,rollPrevError = PIDController(Kp_roll, Ki_roll, Kd_roll, rollError, rollIntegral, (rollError - rollPrevError), rollPrevError, dt)
    rollOutput = -math.min(math.max(rollOutput, -15), 15)


    --PID for pitch (how hard to pull to sides)
    pitchError = deltaPitch
    rollFactor = math.cos(math.rad(math.abs(deltaRoll)))
    local pitchOutput, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchError, pitchIntegral, (pitchError - pitchPrevError), pitchPrevError, dt)
    pitchOutput = math.abs(math.min(math.max(pitchOutput, -20), 20)) --* rollFactor --smaller pitch when not perfectly aligned

    --TopLeftAxis
    --top flap: +ve = left
    --left flap: +ve = down
    -- bottom" +ve = left
    -- right flap: +ve = down
    local topAngle, leftAngle, bottomAngle, rightAngle = 0,0,0,0
    if axisName == "topLeftQua" then
        topAngle, leftAngle, bottomAngle, rightAngle = -pitchOutput, -pitchOutput, -pitchOutput, -pitchOutput
    elseif axisName == "leftBottomQua" then
        topAngle, leftAngle, bottomAngle, rightAngle = -pitchOutput, pitchOutput, -pitchOutput, pitchOutput
    elseif axisName == "bottomRightQua" then
        topAngle, leftAngle, bottomAngle, rightAngle = pitchOutput, pitchOutput, pitchOutput, pitchOutput
    elseif axisName == "rightTopQua" then
        topAngle, leftAngle, bottomAngle, rightAngle = pitchOutput, -pitchOutput, pitchOutput, -pitchOutput
    end
    topAngle, leftAngle, bottomAngle, rightAngle = topAngle + rollOutput, leftAngle - rollOutput, bottomAngle - rollOutput, rightAngle + rollOutput 
    --print("Angle: "..topAngle.." | "..leftAngle.." | "..bottomAngle.." | "..rightAngle)
    topFlap.setAngle(topAngle)
    leftFlap.setAngle(leftAngle)
    bottomFlap.setAngle(bottomAngle)
    rightFlap.setAngle(rightAngle)
    print("Rollfactor: "..rollFactor)
    --[[print("dt: "..dt)
    print("pitchOutput: "..pitchOutput)
    print("rollOutput: "..rollOutput)
    print("missileSpeed: "..missileSpeed)
    print("rate of closure: "..rateOfClosure)]]

    if missileSpeed < 60 then
        print("Speed below optimal, accelerating")
        redstone.setAnalogOutput("top",highThrust)
    else
        if pitchOutput > 10 or missileSpeed > 240 then
            redstone.setAnalogOutput("top",0)
        end
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

    if timeToHit < 0.1 and deltaDistance > 0 and distance < 25 then
        sleep(math.max(timeToHit - 0.02, 0)) -- Prevent negative sleep time
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
