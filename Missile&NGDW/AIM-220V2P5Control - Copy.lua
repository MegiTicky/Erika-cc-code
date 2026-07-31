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

local function computerRateOfClosure(missilePos, missileVel, targetPos, targetVel)
  local rx = targetPos.x - missilePos.x
  local ry = targetPos.y - missilePos.y
  local rz = targetPos.z - missilePos.z
  local rmag = math.sqrt(rx*rx + ry*ry + rz*rz)
  if rmag < 1e-6 then return 0 end

  local ux, uy, uz = rx/rmag, ry/rmag, rz/rmag -- LOS unit (missile->target)

  local vx = missileVel.x - targetVel.x
  local vy = missileVel.y - targetVel.y
  local vz = missileVel.z - targetVel.z

  return vx*ux + vy*uy + vz*uz  -- >0 closing, <0 opening
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
        --[[predictedTargetVelocity = {
            x = (targetPos.x - lastTargetPos.x) / dt,
            y = (targetPos.y - lastTargetPos.y) / dt,
            z = (targetPos.z - lastTargetPos.z) / dt
        }]]
        predictedTargetVelocity = targetVel

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
        + 0.5 * predictedTargetAcceleration.x * estimateTime * estimateTime

    local estimateY = targetPos.y
        + (predictedTargetVelocity.y) * estimateTime
        + 0.5 * predictedTargetAcceleration.y * estimateTime * estimateTime

    local estimateZ = targetPos.z
        + (predictedTargetVelocity.z) * estimateTime
        + 0.5 * predictedTargetAcceleration.z * estimateTime * estimateTime

    return {x = estimateX, y = estimateY, z = estimateZ}
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

local function computeLocalYawPitch(targetPos, source)
    local dx = targetPos.x - source.x
    local dy = targetPos.y - source.y
    local dz = targetPos.z - source.z

    local x = math.sqrt(dx*dx + dz*dz)  -- horizontal distance
    local y = dy                         -- vertical difference

    -- yaw geometric
    local yaw = math.deg(math.atan2(-dx, dz))
    yaw = (yaw + 180) % 360
    --geometric pitch
    local horizontalDistance = math.sqrt(dx * dx + dz * dz)
    local pitch = math.deg(math.atan2(dy, horizontalDistance))

    requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw, pitch)
    return requiredRelativeYaw, requiredRelativePitch, yaw, pitch
end

local Kp_yaw, Ki_yaw, Kd_yaw = 0.22, 0, 0.001
local Kp_pitch, Ki_pitch, Kd_pitch = 0.22, 0, 0.001
local Kp_roll, Ki_roll,Kd_roll = 0.005,0,0.0002
local roll_integral,roll_prev_error=0,0
local maxAngle = 15
local lastYawOutput, lastPitchOutput = nil, nil
local rateOfClosure = 150

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

                
                
                
                -- use constant rate of closure if missile is still turning or accelerating
                if lastYawOutput and lastPitchOutput and math.abs(lastYawOutput) < 8 and math.abs(lastPitchOutput) < 8 and missileSpeed > 50 then
                    rateOfClosure = computerRateOfClosure(pos, missileVelocity, targetPos, targetVel)
                    rateOfClosure = math.max(math.min(rateOfClosure,400),150)
                else
                    rateOfClosure = 150
                end

                estimatePos = predictFuturePosition(targetPos,targetVel,pos.x,pos.y,pos.z,rateOfClosure)
            end
        end
    elseif target.type == "waypoint" then
        -- Update position and targetVel
        estimatePos = target.pos
    end

    local requiredRelativeYaw, requiredRelativePitch, targetYaw, targetPitch = computeLocalYawPitch(estimatePos, pos)


    --cannon.setPitch(requiredRelativePitch)
    --cannon.setYaw(requiredRelativeYaw)
    -- PID control for yaw
    local yawError = requiredRelativeYaw
    local yawOutput, yawIntegral, yawPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, yawError, yawIntegral, (yawError - yawPrevError), yawPrevError, dt)
    yawOutput = -yawOutput

    -- PID control for pitch
    local pitchError = requiredRelativePitch
    local pitchOutput, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchError, pitchIntegral, (pitchError - pitchPrevError), pitchPrevError, dt)
    pitchOutput = -pitchOutput

    -- PIDcontrol for roll
    local rollError = roll
    local rollOutput,rollIntegral,rollPrevError = PIDController(Kp_roll, Ki_roll, Kd_roll, rollError, rollIntegral, (rollError - rollPrevError), rollPrevError, dt)
    rollOutput = 0--math.min(math.max(rollOutput, -2), 2)

    -- If either output exceeds the max limit, scale both proportionally
    local maxOutput = math.max(math.abs(pitchOutput), math.abs(yawOutput))
    if maxOutput > maxAngle then
        local scaleFactor = maxAngle / maxOutput
        pitchOutput = pitchOutput * scaleFactor
        yawOutput = yawOutput * scaleFactor
    end

    lastYawOutput, lastPitchOutput = yawOutput, pitchOutput
    topFlap.setAngle(yawOutput + rollOutput)
    leftFlap.setAngle(pitchOutput - rollOutput)
    bottomFlap.setAngle(yawOutput - rollOutput)
    rightFlap.setAngle(pitchOutput + rollOutput)

    --print(textutils.serialize(forceVector))
    --print("dt: "..dt)
    --print("rollAngle: "..rollAngle)
    print("targetYaw: "..math.deg(targetYaw).." targetPitch: "..math.deg(targetPitch))
    print("requiredRelativeYaw: "..requiredRelativeYaw)
    print("requiredRelativePitch: "..requiredRelativePitch)
    print("pitchOutput: "..pitchOutput)
    print("yawOutput: "..yawOutput)
    --print("missileSpeed: "..missileSpeed)
    print("rate of closure: "..rateOfClosure)

    if missileSpeed < 60 then
        --print("Speed below optimal, accelerating")
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
