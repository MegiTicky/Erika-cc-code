-- Redstone sides for controlling the plane
redstoneSides = { 
    rollLeft = "left",
    rollRight = "right",
    pitchUp = "top",
    pitchDown = "bottom",
    throttle = "front",
    door = "back"
}
redstone.setOutput(redstoneSides.door, false)
sleep(0.2)

-- Disable redstone output on all sides initially
redstone.setAnalogOutput(redstoneSides.rollLeft, 0)
redstone.setAnalogOutput(redstoneSides.rollRight, 0)
redstone.setOutput(redstoneSides.pitchUp, false)
redstone.setOutput(redstoneSides.pitchDown, false)
redstone.setAnalogOutput(redstoneSides.throttle, 0)
redstone.setOutput(redstoneSides.door, true)

takeOffSpeed = 20
local targetCoord = {x = 4710, y = 16, z = 5924}
--local targetCoord = {x = 3210, y = 22, z = 8203}
print("Press enter to start. Target coordinate:")
print(textutils.serialize(targetCoord))
io.read()

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

local buildDirection = "+x"

local _getYaw   = getYaw
local _getPitch = getPitch
local _getRoll  = getRoll

local yawOffsetDeg = 0

if buildDirection == "+x" then
    -- positive roll is pitching upward
    -- positive pitch is rolling to the left, suppose rolling to the right (clockwise) is positive
    -- and yaw needs +90 deg in worldspace
    yawOffsetDeg = 90

    getRoll = function()
        return -_getPitch() -- roll comes from old pitch
    end

    getPitch = function()
        return _getRoll()  -- pitch comes from old roll
    end

    getYaw = function()
        return _getYaw() + math.rad(yawOffsetDeg) -- getYaw returns radians in your code
    end
end

-- Function to maintain speed within the max speed of the plane
local function adjustThrottle(targetSpeed, currentVelocity)
    local currentSpeed = math.sqrt(currentVelocity.x^2 + currentVelocity.y^2 + currentVelocity.z^2)
    if currentSpeed < targetSpeed then
        redstone.setAnalogOutput(redstoneSides.throttle, 15)  -- Full throttle
        print("Increasing throttle to full (15). Current speed: " .. currentSpeed)
    elseif currentSpeed > targetSpeed then
        redstone.setAnalogOutput(redstoneSides.throttle, 5)   -- Reduce throttle
        print("Reducing throttle to 5. Current speed: " .. currentSpeed)
    else
        redstone.setAnalogOutput(redstoneSides.throttle, 10)  -- Maintain current throttle
        print("Maintaining throttle at 10. Current speed: " .. currentSpeed)
    end
end

-- Adjust pitch to maintain altitude using delta pitch angle
kp_pitch = 1
pitchLimit = 20

local function maintainAltitude(targetAltitude, currentPitch, currentVelocity)
    local currentAltitude = ship.getWorldspacePosition().y
    local altitudeError = targetAltitude - currentAltitude

    -- horizontal speed (ignore vertical)
    local vx = currentVelocity.x
    local vz = currentVelocity.z
    local horizSpeed = math.max(math.sqrt(vx*vx + vz*vz),45)

    -- "lookahead" distance: how far forward we assume we can correct altitude
    -- (tune 1.5~3.0 seconds; larger = gentler)
    local lookahead = horizSpeed * 2.0
    if lookahead < 30 then lookahead = 30 end  -- avoid crazy pitch at low speed

    -- desired pitch angle towards the altitude line (degrees)
    local desiredPitch = math.deg(math.atan2(altitudeError, lookahead))
    if desiredPitch > pitchLimit then desiredPitch = pitchLimit end
    if desiredPitch < -pitchLimit then desiredPitch = -pitchLimit end

    -- delta pitch (degrees)
    local deltaPitch = desiredPitch - currentPitch

    -- command output (signed)
    local pitchOutput = deltaPitch * kp_pitch

    -- clamp to analog range
    if pitchOutput > 15 then pitchOutput = 5 end
    if pitchOutput < -15 then pitchOutput = -15 end

    -- apply analog outputs
    if pitchOutput > 1 then
        redstone.setAnalogOutput(redstoneSides.pitchUp, math.floor(pitchOutput))
        redstone.setAnalogOutput(redstoneSides.pitchDown, 0)
    elseif pitchOutput < -1 then
        redstone.setAnalogOutput(redstoneSides.pitchDown, math.floor(-pitchOutput))
        redstone.setAnalogOutput(redstoneSides.pitchUp, 0)
    else
        redstone.setAnalogOutput(redstoneSides.pitchUp, 0)
        redstone.setAnalogOutput(redstoneSides.pitchDown, 0)
    end

    print(string.format(
        "[ALT] err=%.1f desiredP=%.1f currP=%.1f dP=%.1f out=%.1f look=%.1f",
        altitudeError, desiredPitch, currentPitch, deltaPitch, pitchOutput, lookahead
    ))
end

kp_yaw = 0.7      -- yawError -> desiredRoll (deg/deg). tune ~0.5..2
kp_roll = 0.6     -- deltaRoll -> aileron output. tune ~0.3..1.5
rollLimit = 50

local function adjustHeading(targetYaw)
    local currentYaw = (math.deg(getYaw()) % 360 + 360) % 360
    local targetYawN = (targetYaw % 360 + 360) % 360

    -- yaw error shortest path [-180..180]
    local yawError = (targetYawN - currentYaw + 180) % 360 - 180

    -- current roll in degrees (flip sign if needed)
    local currentRoll = math.deg(getRoll())  -- if reversed: currentRoll = -math.deg(getRoll())

    -- 1) desired roll proportional to yaw error, clamped to rollLimit
    local desiredRoll = yawError * kp_yaw
    if desiredRoll > rollLimit then desiredRoll = rollLimit end
    if desiredRoll < -rollLimit then desiredRoll = -rollLimit end

    -- 2) aileron output proportional to delta roll
    local deltaRoll = desiredRoll - currentRoll
    local aileronOut = deltaRoll * kp_roll

    -- clamp aileron output to analog range, keep sign
    if aileronOut > 15 then aileronOut = 15 end
    if aileronOut < -15 then aileronOut = -15 end

    print(string.format(
        "tYaw=%.1f cYaw=%.1f yErr=%.1f cRoll=%.1f dRoll=%.1f aOut=%.1f",
        targetYawN, currentYaw, yawError, currentRoll, desiredRoll, aileronOut
    ))

    -- APPLY: analog outputs must be 0..15, so split by sign
    if aileronOut > 1 then
        -- positive => roll RIGHT (swap sides if your plane is inverted)
        redstone.setAnalogOutput(redstoneSides.rollRight, math.floor(aileronOut))
        redstone.setAnalogOutput(redstoneSides.rollLeft, 0)
    elseif aileronOut < -1 then
        -- negative => roll LEFT
        redstone.setAnalogOutput(redstoneSides.rollLeft, math.floor(-aileronOut))
        redstone.setAnalogOutput(redstoneSides.rollRight, 0)
    else
        redstone.setAnalogOutput(redstoneSides.rollLeft, 0)
        redstone.setAnalogOutput(redstoneSides.rollRight, 0)
    end
end

-- Main autopilot logic
local function autopilot(targetCoord)
    redstone.setOutput(redstoneSides.door, false)
    -- Takeoff process: Apply throttle and climb
    while true do
        local velocity = ship.getVelocity()
        -- Adjust throttle to take off (accelerate to 30m/s)
        adjustThrottle(takeOffSpeed, velocity)

        -- Check if speed is sufficient to pull up (30m/s)
        if math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2) >= 30 then
            redstone.setOutput(redstoneSides.pitchUp, true)  -- Pull up
            print("Takeoff successful! Pitching up.")
            break
        end
        sleep()
    end

    -- Gain altitude (200 blocks above initial altitude)
    local targetAltitude = targetCoord.y + 200
    local climbCruiseSpeed = 40
    while true do
        -- Limit pitch to avoid stalling (pitch should be between -20 and 20 degrees during climb)
        local pitch = math.deg(getPitch())
        local currentYaw = math.deg(getYaw())
        local velocity = ship.getVelocity()
        print(pitch)
        adjustThrottle(climbCruiseSpeed, velocity)
        maintainAltitude(targetAltitude,pitch,velocity)
        adjustHeading(currentYaw)
        if math.abs(ship.getWorldspacePosition().y - targetAltitude) < 10 then
            print("Altitude reached: " .. targetAltitude)
            break
        end
        sleep()
    end

    math.randomseed(os.epoch("utc"))

    local radius = 200 -- Radius of the circular area
    local wanderYaw = nil
    local inside = false
    local warningNext = true
    while true do
        local pos = ship.getWorldspacePosition()
        local dx = targetCoord.x - pos.x
        local dz = targetCoord.z - pos.z
        local dist = math.sqrt(dx * dx + dz * dz)

        local currentPitch = math.deg(getPitch())
        local currentYaw = math.deg(getYaw())
        local velocity = ship.getVelocity()
        if dist < radius + 300 and warningNext then
            --warning
            redstone.setOutput(redstoneSides.door, true)
            warningNext = false
        end
        if dist < radius + 100 then
            --allow
            redstone.setOutput(redstoneSides.door, true)
            
        else
            redstone.setOutput(redstoneSides.door, false)
        end
        if dist > radius then
            -- OUTSIDE: go back to the center
            if inside then
                print("[LOITER] Left area. Returning to center.")
            end
            inside = false
            wanderYaw = nil  -- Reset wanderYaw when leaving the area

            local targetYaw = -math.deg(math.atan2(dx, dz))

            -- Move straight for 200m before adjusting back to the target
            local targetPosition = {x = pos.x + 200 * math.cos(math.rad(targetYaw)), z = pos.z + 200 * math.sin(math.rad(targetYaw))}
            local dxMove = targetPosition.x - pos.x
            local dzMove = targetPosition.z - pos.z
            local moveDist = math.sqrt(dxMove * dxMove + dzMove * dzMove)
            -- Keep moving straight towards the new position
            adjustHeading(targetYaw) -- Move straight in that direction
            maintainAltitude(targetAltitude, currentPitch, velocity)
            adjustThrottle(climbCruiseSpeed, velocity) -- Keep cruising at max speed

            -- Debug
            print(string.format("[LOITER] Outside target area. Moving straight to position %.1f, %.1f", targetPosition.x, targetPosition.z))

        else
            warningNext = true
            --in radius, fly straight
            adjustHeading(currentYaw)
            -- Maintain the wanderYaw when inside the radius
            maintainAltitude(targetAltitude, currentPitch, velocity)
            adjustThrottle(climbCruiseSpeed, velocity) -- Keep the plane cruising at max speed

            -- Debug
            print("[LOITER] Inside target area. Current yaw:"..currentYaw)

        end

        -- Debug print for the distance and current state
        print(string.format("[LOITER] dist=%.1f inside=%s", dist, tostring(inside)))
        sleep()
    end

end

-- Start the autopilot system
autopilot(targetCoord)
