radar = peripheral.find("sp_radar")

local cannons = {}
local foundNames = {}
local k = 1

local directions = {"top", "bottom", "left", "right", "front", "back"}
for _, side in ipairs(directions) do
    if peripheral.isPresent(side) then
        local name = peripheral.getType(side)
        if name == "createbigcannons:cannon_mount" or name == "cbcmodernwarfare:compact_mount" then
            local cannon = peripheral.wrap(side)
            if cannon then
                cannons[k] = cannon
                foundNames[peripheral.getName(cannon)] = true
                print("Found direct cannon on side: " .. side)
                k = k + 1
            end
        end
    end
end

local i = 0
local nilCount = 0
local maxNilTolerance = 200

while nilCount < maxNilTolerance do
    local addr1 = "createbigcannons:cannon_mount_" .. i
    local addr2 = "cbcmodernwarfare:compact_mount_" .. i

    local cannon = peripheral.wrap(addr1)
    if not cannon then
        cannon = peripheral.wrap(addr2)
    end

    if cannon then
        local name = peripheral.getName(cannon)
        if not foundNames[name] then
            cannons[k] = cannon
            foundNames[name] = true
            print("Found network cannon: " .. name)
            k = k + 1
        end
        nilCount = 0
    else
        nilCount = nilCount + 1
    end

    i = i + 1
end

print("Total cannons found: " .. #cannons)
cannons[1].assemble()

-- Cooldown variables
local cooldownTime = 0.3  -- Cooldown time in seconds
local lastTriggerTime = 0  -- Time when the script was last triggered
local verticalSensitivity = 0.5
redstoneSides = {
    laserRangeFinder = "front",
    cannonUpInput = "top",
    cannonDownInput = "bottom",
    cannonLeftOutput = "left",
    cannonRightOutput = "right"
}

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

local function yawPitchToLookVec(yawDeg, pitchDeg)
    local yaw = math.rad(yawDeg)
    local pitch = math.rad(pitchDeg)

    local x = math.sin(yaw) * math.cos(pitch)
    local y = math.sin(pitch)
    local z = -math.cos(yaw) * math.cos(pitch)

    return { x = x, y = y, z = z }
end

local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

local projectileSpeed = askUser("Enter the projectileSpeed","240")
local g = askUser("Enter the g","0.02")
local cd =askUser("Enter the cd","0.995")
local enableLaserRangeFinder = askUser("Enable laserRangeFinder?","yes")
print("enableVeticalStablizer?")
local enableVerticalStablizer = askUser("Enable vertical stablizer?","yes")
if enableVerticalStablizer == "yes" then
    enableVerticalStablizer = true
else
    enableVerticalStablizer = false
end
if enableVerticalStablizer and pitchMotor then
    print("pitch motor operational, vertical stab on")
else
    print("pitch motor offline, vertical stab are off")
    enableVerticalStablizer = false
end

if enableVerticalStablizer then
    verticalDriveRPM = askUser("enter the vertical drive maximum RPM","7.4")
    verticalMaxAngularVelocity = verticalDriveRPM / 60 * 360 / 8
end
local vm

local localCannonYaw, localCannonPitch = cannons[1].getYaw(), cannons[1].getPitch()
if localCannonYaw == 0 then
    shipPitch = math.deg(getPitch())
elseif localCannonYaw == 90 then
    shipPitch = -math.deg(getRoll())
elseif localCannonYaw == 180 then
    shipPitch = -math.deg(getPitch())
elseif localCannonYaw == 270 then
    shipPitch = math.deg(getRoll())
else
    error("Yaw offseted, cannon process")
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

local function findBestPitch(distance, initialVelocity, g, cd, c_est, projectileSpeed)
    function calculateRange(angle, u, cd, g, c_est, projectileSpeed)
        local radians = math.rad(angle)
        local u = projectileSpeed / 20
        local part1 = u * math.cos(radians) / math.log(cd)
        local part2 = ((g * cd) / (g * cd + (1 - cd) * u * math.sin(radians))) ^ (2 + c_est * projectileSpeed * math.sin(radians)) - 1
        local XR = part1 * part2
        return XR
    end
    local bestLowPitch = nil
    local bestHighPitch = nil
    local bestLowDistance = math.huge
    local bestHighDistance = math.huge
    local targetDistance = distance

    for pitch = 0, 30, 0.01 do
        local calculatedRange = calculateRange(pitch, initialVelocity, cd, g, c_est, projectileSpeed)
        local distanceDifference = math.abs(calculatedRange - targetDistance)

        if pitch <= 30 then
            if distanceDifference < bestLowDistance then
                bestLowDistance = distanceDifference
                bestLowPitch = pitch
            end
        elseif pitch > 30 then
            if distanceDifference < bestHighDistance then
                bestHighDistance = distanceDifference
                bestHighPitch = pitch
            end
        end
    end

    if settings.useHighPitch and bestHighPitch and bestHighDistance < 2 then
        return bestHighPitch
    else
        return bestLowPitch
    end
end

-- =========================
-- Fast velocity-only lead prediction with drag + gravity
-- Replace your current "Stable velocity-only lead prediction" block
-- AND replace aimCannonWithLead() with the version below.
-- =========================

local smoothedFuturePos = nil
local previousPredictionTargetID = nil

local lastCompTargetPos = nil
local lastCompTime = os.clock()
local velocityCompensation = 1

-- Tuning
local futurePosSmoothing = 1     -- higher = faster response, lower = smoother
local velocityCompSmoothing = 0.25   -- higher = faster velocity compensation update
local minVelocityCompensation = 0.5
local maxVelocityCompensation = 1.15

local leadTimeScale = 1
local leadTimeBias = 0.5

local maxLeadTime = 10              -- seconds; prevents crazy lead at extreme range
local leadIterations = 3             -- 2 is usually enough

-- Pitch solver tuning
local pitchLowLimit = -20            -- degrees
local pitchHighLimit = 75            -- degrees
local pitchSolveIterations = 14      -- cheap; no simulation loop

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end
    return value
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerpVec3(a, b, t)
    return {
        x = lerp(a.x, b.x, t),
        y = lerp(a.y, b.y, t),
        z = lerp(a.z, b.z, t)
    }
end

local function vecDistance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getNumber(value, fallback)
    local n = tonumber(value)
    if n == nil then
        return fallback
    end
    return n
end

-- Closed-form horizontal drag time.
-- t is returned in ticks.
-- horizontalDistance is blocks.
-- muzzleVelocity is blocks/second.
-- pitchDeg is launch pitch in degrees.
local function getFlightTimeTicksHorizontal(horizontalDistance, muzzleVelocity, pitchDeg)
    local r = getNumber(cd, 0.995)
    local v0 = getNumber(muzzleVelocity, 260) / 20 -- blocks/tick
    local pitchRad = math.rad(pitchDeg)

    local vx0 = v0 * math.cos(pitchRad)

    if vx0 <= 0.0001 then
        return nil
    end

    local lnR = math.log(r)

    -- Continuous closed form matching your Desmos style:
    -- x(t) = vx0 * (r^t - 1) / ln(r)
    -- solve:
    -- r^t = 1 + x * ln(r) / vx0
    local inside = 1 + horizontalDistance * lnR / vx0

    if inside <= 0 then
        return nil
    end

    return math.log(inside) / lnR
end

-- Closed-form vertical displacement after t ticks.
-- Uses the same style as your Desmos equation:
-- vy(t) = v0y*r^t - (g*r/(1-r))*(1-r^t)
-- Y(t) = integral of vy(t)
local function getProjectileYAtTicks(ticks, muzzleVelocity, pitchDeg)
    local r = getNumber(cd, 0.995)
    local gravity = getNumber(g, 0.02)
    local v0 = getNumber(muzzleVelocity, 260) / 20 -- blocks/tick
    local pitchRad = math.rad(pitchDeg)

    local vy0 = v0 * math.sin(pitchRad)
    local lnR = math.log(r)
    local rPowT = r ^ ticks

    local dragIntegral = (rPowT - 1) / lnR
    local gravityTerm = gravity * r / (1 - r)

    local y = vy0 * dragIntegral - gravityTerm * (ticks - dragIntegral)

    return y
end

-- Cheap gravity-aware pitch solver.
-- Finds pitch that makes projectile vertical displacement match verticalDistance
-- at the horizontal distance.

local barrelLength = 10 -- meters / blocks
local function solvePitchAndFlightTime(horizontalDistanceFromPivot, verticalDistanceFromPivot, muzzleVelocity)

    if horizontalDistanceFromPivot < 0.001 then
        local directPitch = 90
        return directPitch, 0
    end

    local low = pitchLowLimit
    local high = pitchHighLimit

    local bestPitch = nil
    local bestTicks = nil
    local bestError = math.huge

    for i = 1, pitchSolveIterations do
        local mid = (low + high) * 0.5
        local midRad = math.rad(mid)

        -- Muzzle is barrelLength meters forward along the barrel.
        -- So the projectile does NOT need to travel the full pivot-to-target distance.
        local muzzleHorizontalOffset = barrelLength * math.cos(midRad)
        local muzzleVerticalOffset = barrelLength * math.sin(midRad)

        local horizontalDistanceFromMuzzle =
            horizontalDistanceFromPivot - muzzleHorizontalOffset

        local verticalDistanceFromMuzzle =
            verticalDistanceFromPivot - muzzleVerticalOffset

        -- If target is closer than the muzzle horizontally, avoid invalid math.
        if horizontalDistanceFromMuzzle < 0.001 then
            horizontalDistanceFromMuzzle = 0.001
        end

        local ticks = getFlightTimeTicksHorizontal(
            horizontalDistanceFromMuzzle,
            muzzleVelocity,
            mid
        )

        if ticks == nil then
            high = mid
        else
            local y = getProjectileYAtTicks(
                ticks,
                muzzleVelocity,
                mid
            )

            local errorY = y - verticalDistanceFromMuzzle
            local absError = math.abs(errorY)

            if absError < bestError then
                bestError = absError
                bestPitch = mid
                bestTicks = ticks
            end

            if errorY < 0 then
                -- Projectile is too low, aim higher.
                low = mid
            else
                -- Projectile is too high, aim lower.
                high = mid
            end
        end
    end

    if bestPitch == nil or bestTicks == nil then
        local fallbackPitch = math.deg(
            math.atan2(verticalDistanceFromPivot, horizontalDistanceFromPivot)
        )

        local distance = math.sqrt(
            horizontalDistanceFromPivot * horizontalDistanceFromPivot +
            verticalDistanceFromPivot * verticalDistanceFromPivot
        )

        local fallbackTime = distance / muzzleVelocity
        return fallbackPitch, fallbackTime
    end

    return bestPitch, bestTicks / 20
end

local function updateVelocityCompensation(targetPos, targetVel, targetID)
    local currentTime = os.clock()

    if previousPredictionTargetID ~= targetID or lastCompTargetPos == nil then
        lastCompTargetPos = {
            x = targetPos.x,
            y = targetPos.y,
            z = targetPos.z
        }

        lastCompTime = currentTime
        velocityCompensation = 1
        return velocityCompensation
    end

    local dt = currentTime - lastCompTime

    -- Use a longer interval so physics lag/noise averages out.
    if dt >= 0.5 then
        local actualDistance = vecDistance(targetPos, lastCompTargetPos)

        local reportedSpeed = math.sqrt(
            targetVel.x * targetVel.x +
            targetVel.y * targetVel.y +
            targetVel.z * targetVel.z
        )

        local reportedDistance = reportedSpeed * dt

        if reportedDistance > 0.01 then
            local rawCompensation = actualDistance / reportedDistance

            rawCompensation = clamp(
                rawCompensation,
                minVelocityCompensation,
                maxVelocityCompensation
            )

            velocityCompensation = lerp(
                velocityCompensation,
                rawCompensation,
                velocityCompSmoothing
            )
        end

        lastCompTargetPos = {
            x = targetPos.x,
            y = targetPos.y,
            z = targetPos.z
        }

        lastCompTime = currentTime
    end

    return velocityCompensation
end

function predictFuturePosition(targetPos, targetVel, source, targetID)
    local shipVelocity = ship.getVelocity()

    local targetSpeed = math.sqrt(
        targetVel.x * targetVel.x +
        targetVel.y * targetVel.y +
        targetVel.z * targetVel.z
    )

    if targetSpeed < 1 then
        smoothedFuturePos = {
            x = targetPos.x,
            y = targetPos.y,
            z = targetPos.z
        }

        return smoothedFuturePos, 0
    end

    local compensation = updateVelocityCompensation(
        targetPos,
        targetVel,
        targetID
    )

    local compensatedTargetVel = {
        x = targetVel.x * compensation,
        y = targetVel.y * compensation,
        z = targetVel.z * compensation
    }

    local relativeVelocity = {
        x = compensatedTargetVel.x - shipVelocity.x,
        y = compensatedTargetVel.y - shipVelocity.y,
        z = compensatedTargetVel.z - shipVelocity.z
    }

    if previousPredictionTargetID ~= targetID then
        previousPredictionTargetID = targetID
        smoothedFuturePos = {
            x = targetPos.x,
            y = targetPos.y,
            z = targetPos.z
        }
    end

    local futurePos = {
        x = targetPos.x,
        y = targetPos.y,
        z = targetPos.z
    }

    local flightTime = 0

    for i = 1, leadIterations do
        local dx = futurePos.x - source.x
        local dy = futurePos.y - source.y
        local dz = futurePos.z - source.z

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)

        local pitchGuess
        pitchGuess, flightTime = solvePitchAndFlightTime(
            horizontalDistance,
            dy,
            projectileSpeed
        )

        if flightTime == nil or flightTime ~= flightTime or flightTime < 0 then
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            flightTime = distance / getNumber(projectileSpeed, 260)
        end

        flightTime = flightTime * leadTimeScale + leadTimeBias
        flightTime = clamp(flightTime, 0, maxLeadTime)

        futurePos = {
            x = targetPos.x + relativeVelocity.x * flightTime,
            y = targetPos.y + relativeVelocity.y * flightTime,
            z = targetPos.z + relativeVelocity.z * flightTime
        }
    end

    smoothedFuturePos = lerpVec3(
        smoothedFuturePos,
        futurePos,
        futurePosSmoothing
    )

    print("velocityCompensation: " .. compensation)
    print("targetSpeed: " .. targetSpeed)
    print("leadTime: " .. flightTime)
    print("leadDistance: " .. targetSpeed * flightTime)

    return smoothedFuturePos, flightTime
end

local pitchCalibration = 0
local function aimCannonWithLead(targetPos, targetVel, source, targetID)
    local futurePos, flightTime = predictFuturePosition(
        targetPos,
        targetVel,
        source,
        targetID
    )
    source.y = source.y +0.5
    local dx = futurePos.x - source.x
    local dy = futurePos.y - source.y
    local dz = futurePos.z - source.z

    -- Yaw to predicted future position
    local yaw = math.deg(math.atan2(-dx, dz))
    yaw = (yaw + 180) % 360

    local horizontalDistance = math.sqrt(dx * dx + dz * dz)

    -- Gravity + drag aware pitch
    local _, finalFlightTime = solvePitchAndFlightTime(
        horizontalDistance,
        dy,
        projectileSpeed
    )
    pitch = math.deg(math.atan2(dy, horizontalDistance)) + findBestPitch(horizontalDistance, projectileSpeed, g, cd, 0.028, projectileSpeed)
    pitch = math.deg(math.atan2(dy, horizontalDistance)) + findBestPitch(horizontalDistance-barrelLength * math.cos(math.rad(pitch)), projectileSpeed, g, cd, 0.028, projectileSpeed)
    --pitch = pitch + pitchCalibration
    -- Fallback if solver fails
    if pitch == nil then
        pitch = math.deg(math.atan2(dy, horizontalDistance))
    end
    pitch = clamp(pitch, pitchLowLimit, pitchHighLimit)

    requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw, pitch)

    print("leadPitch: " .. pitch)
    print("leadYaw: " .. yaw)
    print("leadTime: " .. (finalFlightTime or flightTime or 0))

    return requiredRelativeYaw, requiredRelativePitch, yaw, pitch
end

local function setPitchYaw(targetPitch, targetYaw)
    local tasks = {} -- Table to store each cannon's task

    for index, cannon in pairs(cannons) do
        -- Define the function for this cannon's pitch/yaw adjustment
        local function adjustCannon()
            cannon.setPitch(targetPitch)
            cannon.setYaw(targetYaw)
        end
        -- Add this task to the tasks table
        table.insert(tasks, adjustCannon)
    end

    -- Execute all tasks in parallel
    parallel.waitForAll(table.unpack(tasks))
end

local function PIDController(Kp, Ki, Kd, error, integral, prevError, dt)
    -- Calculate the proportional, integral, and derivative components
    local proportional = Kp * error
    integral = integral + error * dt
    derivative = (error - prevError) / dt
    
    -- Calculate output
    local output = proportional + (Ki * integral) + (Kd * derivative)

    -- Return the PID output and updated integral and previous error
    return output, integral, error
end

-- =========================
-- Turret yaw PID + absolute-target-yaw feed-forward
-- =========================

local yawIntegral = 0
local previousYawError = 0
local previousTargetYaw = nil
local previousRotateTime = os.clock()

-- Tune these
local yawKp = 2.5
local yawKi = 0
local yawKd = 0.4

-- Feed-forward from absolute target yaw rate.
-- Increase if still lagging behind moving targets.
-- Decrease if it leads too much or oscillates.
local yawFeedForwardGain = 2

-- Minimum redstone signal to overcome motor deadband/friction.
local yawMinPower = 0

-- Stop jitter near zero error.
local yawDeadzone = 0.25

local yawIntegralLimit = 20

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end
    return value
end

local function sign(value)
    if value > 0 then
        return 1
    elseif value < 0 then
        return -1
    else
        return 0
    end
end

local function normalizeAngle(angle)
    while angle > 180 do
        angle = angle - 360
    end

    while angle < -180 do
        angle = angle + 360
    end

    return angle
end

local function setYawMotor(output)
    output = clamp(output, -15, 15)

    local signal = math.floor(math.abs(output) + 0.5)
    signal = clamp(signal, 0, 15)

    if output < 0 then
        redstone.setAnalogOutput(redstoneSides.cannonLeftOutput, signal)
        redstone.setAnalogOutput(redstoneSides.cannonRightOutput, 0)
    elseif output > 0 then
        redstone.setAnalogOutput(redstoneSides.cannonRightOutput, signal)
        redstone.setAnalogOutput(redstoneSides.cannonLeftOutput, 0)
    else
        redstone.setAnalogOutput(redstoneSides.cannonLeftOutput, 0)
        redstone.setAnalogOutput(redstoneSides.cannonRightOutput, 0)
    end

    return signal * sign(output)
end

local function rotateTurret(requiredRelativeYaw, targetYaw)
    local currentTime = os.clock()
    local dt = currentTime - previousRotateTime

    if dt <= 0 or dt > 0.5 then
        dt = 0.1
    end

    previousRotateTime = currentTime

    requiredRelativeYaw = normalizeAngle(requiredRelativeYaw)
    targetYaw = normalizeAngle(targetYaw)

    -- PID feedback from current aiming error
    local rawYawOutput
    rawYawOutput, yawIntegral, previousYawError = PIDController(
        yawKp,
        yawKi,
        yawKd,
        requiredRelativeYaw,
        yawIntegral,
        previousYawError,
        dt
    )

    yawIntegral = clamp(yawIntegral, -yawIntegralLimit, yawIntegralLimit)

    -- Feed-forward from absolute target yaw motion
    local targetYawRate = 0

    if previousTargetYaw ~= nil then
        local deltaTargetYaw = normalizeAngle(targetYaw - previousTargetYaw)
        targetYawRate = deltaTargetYaw / dt

        -- Reject huge spikes from target switching or radar jitter
        if math.abs(deltaTargetYaw) > 45 then
            targetYawRate = 0
            yawIntegral = 0
        end
    end

    previousTargetYaw = targetYaw

    local feedForwardOutput = yawFeedForwardGain * targetYawRate

    local finalOutput = rawYawOutput + feedForwardOutput

    -- Deadzone only if the target is also not moving much
    if math.abs(requiredRelativeYaw) < yawDeadzone and math.abs(targetYawRate) < 1 then
        finalOutput = 0
        yawIntegral = 0
    end

    -- Minimum motor power
    if finalOutput ~= 0 and math.abs(finalOutput) < yawMinPower then
        finalOutput = sign(finalOutput) * yawMinPower
    end

    finalOutput = clamp(finalOutput, -15, 15)

    local normalizedYawOutput = setYawMotor(finalOutput)

    print("targetYaw: " .. targetYaw)
    print("yawError: " .. requiredRelativeYaw)
    print("targetYawRate: " .. targetYawRate)
    print("pidOutput: " .. rawYawOutput)
    print("feedForward: " .. feedForwardOutput)
    print("output: " .. normalizedYawOutput)
end

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end

local function clusterShips(ships)
    local clusters = {}
    shipPosX = ship.getWorldspacePosition()
    for _, ship in ipairs(ships) do
        local added = false
        print(distance(ship.pos, shipPosX))
        for _, cluster in ipairs(clusters) do
            for _, other in ipairs(cluster.members) do
                if distance(ship.pos, other.pos) < 10 then
                    table.insert(cluster.members, ship)

                    -- Update main if more massive
                    if (ship.mass or 0) > (cluster.main.mass or 0) and ship.scale.x == 1 then
                        cluster.main = ship
                    end

                    -- Update total mass and volume
                    cluster.massSum = cluster.massSum + (ship.mass or 0)
                    local sx = (ship.size and ship.size.x or 0)
                    local sy = (ship.size and ship.size.y or 0)
                    local sz = (ship.size and ship.size.z or 0)
                    cluster.volumeSum = cluster.volumeSum + (sx * sy * sz)

                    added = true
                    break
                end
            end
            if added then break end
        end

        if not added then
            local sx = (ship.size and ship.size.x or 0)
            local sy = (ship.size and ship.size.y or 0)
            local sz = (ship.size and ship.size.z or 0)
            local volume = sx * sy * sz

            -- New cluster with one ship
            table.insert(clusters, {
                members = { ship },
                main = ship,
                massSum = ship.mass or 0,
                volumeSum = volume,
            })
        end
    end

    -- Return only main ship data, now including the number of ships in each cluster
    local result = {}
    for _, cluster in ipairs(clusters) do
        local main = cluster.main
        local numShips = #cluster.members  -- Total number of ships in the cluster

        table.insert(result, {
            pos = main.pos,
            id = main.id,
            mass = main.mass,
            volume = cluster.volumeSum,
            numShips = numShips,  -- Add the number of ships in this cluster
            velocity = main.velocity,
            scale = main.scale,
            size = main.size,
            type = "ship",
            color = radarGreen,
        })
    end

    return result
end

local function laserRangeFinderMain()
    while true do
        if enableLaserRangeFinder then
            local currentTime = os.clock()

            --if currentTime - lastTriggerTime >= cooldownTime then
            if redstone.getInput(redstoneSides.laserRangeFinder) then
                local cannonPitch = cannons[1].getPitch()
                local shipPos = ship.getWorldspacePosition()
                local shipYawDeg = math.deg(getYaw())

                print("Cannon Pitch: " .. cannonPitch .. ", Yaw: " .. shipYawDeg)

                if radar then
                    local targets = clusterShips(radar.scanForShips(2000))

                    local lv = yawPitchToLookVec(shipYawDeg, cannonPitch)
                    local lvLen = math.sqrt(lv.x * lv.x + lv.y * lv.y + lv.z * lv.z)

                    local rx, ry, rz = shipPos.x + lv.x * 30, shipPos.y + lv.y * 30, shipPos.z + lv.z * 30
                    --print(rx,ry,rz)

                    if lvLen ~= 0 then
                        local lnx, lny, lnz = lv.x / lvLen, lv.y / lvLen, lv.z / lvLen
                        local coneCos = math.cos(math.rad(15))

                        local bestScore = -math.huge
                        local bestDist = nil
                        local bestTarget = nil

                        for _, target in ipairs(targets) do
                            if target.pos and target.velocity
                                and target.pos.x and target.pos.y and target.pos.z
                                and target.velocity.x and target.velocity.y and target.velocity.z then

                                local dx = target.pos.x - shipPos.x
                                local dy = target.pos.y - shipPos.y
                                local dz = target.pos.z - shipPos.z

                                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

                                if dist > 50 then
                                    local ndx, ndy, ndz = dx / dist, dy / dist, dz / dist
                                    local cosAng = ndx * lnx + ndy * lny + ndz * lnz
                                    --print("Distance > 50")
                                    --print(cosAng)
                                    if cosAng >= coneCos then
                                        local vx, vy, vz = target.velocity.x, target.velocity.y, target.velocity.z
                                        local speed = math.sqrt(vx * vx + vy * vy + vz * vz)

                                        local centered = (cosAng - coneCos) / (1 - coneCos)
                                        local distScore = 1 / (dist + 1)
                                        local speedScore = (speed > 1) and 1 or 0

                                        local score = centered * 3.0 + distScore * 0.5 + speedScore * 1

                                        if score > bestScore then
                                            bestScore = score
                                            bestDist = dist
                                            bestTarget = target
                                        end
                                    end
                                end
                            end
                        end

                        if bestTarget then
                            print("target distance: " .. bestDist)
                            local requiredRelativeYaw, requiredRelativePitch, yaw, pitch = aimCannonWithLead(bestTarget.pos, bestTarget.velocity, shipPos, bestTarget.id)
                            setPitchYaw(requiredRelativePitch, localCannonYaw)
                            rotateTurret(requiredRelativeYaw, yaw)
                        else
                            print("No valid target in cone")
                        end
                    else
                        print("Invalid look vector")
                    end
                else
                    print("No radar detected")
                end

                --lastTriggerTime = currentTime
            else
                redstone.setAnalogOutput(redstoneSides.cannonLeftOutput, 0)
                redstone.setAnalogOutput(redstoneSides.cannonRightOutput, 0)
            end
            --end
        end
        sleep(0.1)
    end
end

laserRangeFinderMain()