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

local function askBoolean(prompt, defaultValue)
    local defaultText = defaultValue and "yes" or "no"
    local value = tostring(askUser(prompt, defaultText)):lower()
    return value == "yes" or value == "y" or value == "true" or value == "1" or value == "on"
end

local projectileSpeed = askUser("Enter the projectileSpeed","240")
local g = askUser("Enter the g","0.02")
local cd =askUser("Enter the cd","0.995")
local enableLaserRangeFinder = askBoolean("Enable laserRangeFinder?", true)
local enableVerticalStablizer = askBoolean("Enable vertical stablizer?", true)
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
local leadTimeBias = 0

local maxLeadTime = 10              -- seconds; prevents crazy lead at extreme range
local leadIterations = 3             -- 2 is usually enough
local ticksPerSecond = 20
local scanRadius = 2000
local lastTargetID = nil
local printedNoTarget = false

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
    local v0 = getNumber(muzzleVelocity, 260) / ticksPerSecond -- blocks/tick
    local vx0 = v0 * math.cos(math.rad(pitchDeg))
    if vx0 <= 0.0001 then return nil end
    if math.abs(r - 1) < 1e-9 then return horizontalDistance / vx0 end
    local inside = 1 - horizontalDistance * (1 - r) / (vx0 * r)
    if inside <= 0 then return nil end
    return math.log(inside) / math.log(r)
end

-- Closed-form vertical displacement after t ticks.
-- Uses the same style as your Desmos equation:
-- vy(t) = v0y*r^t - (g*r/(1-r))*(1-r^t)
-- Y(t) = integral of vy(t)
local function getProjectileYAtTicks(ticks, muzzleVelocity, pitchDeg)
    local r = getNumber(cd, 0.995)
    local gravity = getNumber(g, 0.02)
    local v0 = getNumber(muzzleVelocity, 260) / ticksPerSecond -- blocks/tick
    local vy0 = v0 * math.sin(math.rad(pitchDeg))
    if math.abs(r - 1) < 1e-9 then return vy0 * ticks - gravity * ticks * (ticks - 1) * 0.5 end
    local dragSum = r * (1 - r ^ ticks) / (1 - r)
    -- Updated from shell-radar debugging: CBC-style shell gravity starts after
    -- the first movement sample and is drag-scaled.  The old Desmos/continuous
    -- gravity term over-predicted drop, causing pitch to aim too high.
    return vy0 * dragSum - gravity * r * (ticks - ((1 - r ^ ticks) / (1 - r))) / (1 - r)
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

    return bestPitch, bestTicks / ticksPerSecond
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

    -- Gravity + drag aware pitch, using the shell-radar-verified solver.
    local pitch, finalFlightTime = solvePitchAndFlightTime(
        horizontalDistance,
        dy,
        projectileSpeed
    )

    -- Fallback if solver fails
    if pitch == nil or pitch ~= pitch then
        pitch = math.deg(math.atan2(dy, horizontalDistance))
    end
    pitch = clamp(pitch, pitchLowLimit, pitchHighLimit)

    requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw, pitch)

    print("leadPitch: " .. pitch)
    print("leadYaw: " .. yaw)
    print("leadTime: " .. (finalFlightTime or flightTime or 0))

    return requiredRelativeYaw, requiredRelativePitch, yaw, pitch, futurePos
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

-- Tune these.  High gain is only used while acquiring; near lock the scheduled
-- gains below brake earlier to avoid the several-cycle yaw overshoot seen in
-- autolock_yaw_debug.csv.
local yawKp = 3.6
local yawKi = 0
local yawKd = 0.18

local yawCaptureBand = 12
local yawFineBand = 4
local yawTrackKp, yawFineKp = 2.1, 1.25
local yawTrackKd, yawFineKd = 0.42, 0.68
local yawDerivativeSmoothing = 0.45
local smoothedYawDerivative = 0

-- Feed-forward from absolute target yaw rate.
-- Increase if still lagging behind moving targets.
-- Decrease if it leads too much or oscillates.
local yawFeedForwardGain = 2
local yawRateSmoothing = 0.35
local smoothedTargetYawRate = 0
local yawLosRateSmoothing = 0.45
local yawLosFeedForwardBlend = 0.9
local smoothedLosYawRate = 0
local yawOutputSmoothing = 0.60
local yawOutputBrakeSmoothing = 0.85
local yawOutputSlewPerSecond = 40
local yawOutputBrakeSlewPerSecond = 90
local smoothedYawOutput = 0
local previousMotorOutput = 0

-- Minimum redstone signal to overcome motor deadband/friction.
local yawMinPower = 1

-- Stop jitter near zero error.
local yawDeadzone = 0.18

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
    local leftSignal, rightSignal = 0, 0

    if output < 0 then
        leftSignal, rightSignal = signal, 0
    elseif output > 0 then
        leftSignal, rightSignal = 0, signal
    end

    redstone.setAnalogOutput(redstoneSides.cannonLeftOutput, leftSignal)
    redstone.setAnalogOutput(redstoneSides.cannonRightOutput, rightSignal)
    previousMotorOutput = output

    return signal * sign(output)
end

local function estimateHorizontalYawRate(source, aimPos, relativeVelocity)
    local dx = aimPos.x - source.x
    local dz = aimPos.z - source.z
    local denom = dx * dx + dz * dz
    if denom < 0.001 then return 0 end
    return math.deg((dx * relativeVelocity.z - dz * relativeVelocity.x) / denom)
end

local function rotateTurret(requiredRelativeYaw, targetYaw, losYawRate)
    local currentTime = os.clock()
    local dt = currentTime - previousRotateTime

    if dt <= 0 or dt > 0.5 then
        dt = 0.1
    end

    previousRotateTime = currentTime

    requiredRelativeYaw = normalizeAngle(requiredRelativeYaw)
    targetYaw = normalizeAngle(targetYaw)

    -- Scheduled PD feedback from current aiming error.  Filter the derivative
    -- because radar samples are quantized at roughly 0.20-0.25s.
    yawIntegral = yawIntegral + requiredRelativeYaw * dt
    yawIntegral = clamp(yawIntegral, -yawIntegralLimit, yawIntegralLimit)
    local measuredDerivative = 0
    if previousTargetYaw ~= nil then
        measuredDerivative = (requiredRelativeYaw - previousYawError) / dt
    end
    smoothedYawDerivative = lerp(smoothedYawDerivative, measuredDerivative, yawDerivativeSmoothing)
    local derivative = smoothedYawDerivative
    previousYawError = requiredRelativeYaw

    local absError = math.abs(requiredRelativeYaw)
    local effectiveKp, effectiveKd = yawKp, yawKd
    if absError <= yawFineBand then
        effectiveKp, effectiveKd = yawFineKp, yawFineKd
    elseif absError <= yawCaptureBand then
        local t = (absError - yawFineBand) / (yawCaptureBand - yawFineBand)
        effectiveKp = lerp(yawFineKp, yawTrackKp, t)
        effectiveKd = lerp(yawFineKd, yawTrackKd, t)
    end

    local rawYawOutput = effectiveKp * requiredRelativeYaw + yawKi * yawIntegral + effectiveKd * derivative

    -- Feed-forward from absolute target yaw motion
    local targetYawRate = 0

    if previousTargetYaw ~= nil then
        local deltaTargetYaw = normalizeAngle(targetYaw - previousTargetYaw)
        local measuredTargetYawRate = deltaTargetYaw / dt

        -- Reject huge spikes from target switching or radar jitter
        if math.abs(deltaTargetYaw) > 45 then
            measuredTargetYawRate = 0
            smoothedTargetYawRate = 0
            yawIntegral = 0
        end

        smoothedTargetYawRate = lerp(smoothedTargetYawRate, measuredTargetYawRate, yawRateSmoothing)
        targetYawRate = smoothedTargetYawRate
    end

    previousTargetYaw = targetYaw

    if losYawRate ~= nil then
        smoothedLosYawRate = lerp(smoothedLosYawRate, losYawRate, yawLosRateSmoothing)
        if sign(targetYawRate) == 0 then
            targetYawRate = smoothedLosYawRate * yawLosFeedForwardBlend
        elseif sign(smoothedLosYawRate) == sign(targetYawRate) and math.abs(smoothedLosYawRate) > math.abs(targetYawRate) then
            targetYawRate = lerp(targetYawRate, smoothedLosYawRate, yawLosFeedForwardBlend)
        end
    end

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

    -- Smooth and slew-limit near target to avoid fast/slow/fast jerking from
    -- radar update quantization and integer redstone thrust levels.  Allow fast
    -- sign reversals in the capture band so the turret can brake before it
    -- crosses zero instead of oscillating for several samples.
    if absError > yawCaptureBand then
        smoothedYawOutput = finalOutput
    else
        local reversing = previousMotorOutput ~= 0 and finalOutput ~= 0 and sign(previousMotorOutput) ~= sign(finalOutput)
        local alpha = reversing and yawOutputBrakeSmoothing or yawOutputSmoothing
        smoothedYawOutput = lerp(smoothedYawOutput, finalOutput, alpha)
        local maxStep = (reversing and yawOutputBrakeSlewPerSecond or yawOutputSlewPerSecond) * dt
        local delta = smoothedYawOutput - previousMotorOutput
        if delta > maxStep then
            smoothedYawOutput = previousMotorOutput + maxStep
        elseif delta < -maxStep then
            smoothedYawOutput = previousMotorOutput - maxStep
        end
        finalOutput = smoothedYawOutput
    end

    local normalizedYawOutput = setYawMotor(finalOutput)

    print("targetYaw: " .. targetYaw)
    print("yawError: " .. requiredRelativeYaw)
    print("targetYawRate: " .. targetYawRate)
    print("pidOutput: " .. rawYawOutput)
    print("feedForward: " .. feedForwardOutput)
    print("output: " .. normalizedYawOutput)
end

local function stopYawMotor()
    setYawMotor(0)
end

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end

local function clusterShips(ships)
    local clusters = {}
    shipPosX = ship.getWorldspacePosition()
    for _, ship in ipairs(ships) do
        local added = false
        -- print(distance(ship.pos, shipPosX))
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

local function isValidTarget(target)
    return target and target.pos and target.velocity
        and target.pos.x and target.pos.y and target.pos.z
        and target.velocity.x and target.velocity.y and target.velocity.z
end

local function chooseAutolockTarget(source)
    local bestTarget, bestScore = nil, -math.huge
    local targets = clusterShips(radar.scanForShips(scanRadius) or {})
    for _, target in ipairs(targets) do
        if isValidTarget(target) then
            local dist = vecDistance(target.pos, source)
            if dist > 20 then
                local vx, vy, vz = target.velocity.x, target.velocity.y, target.velocity.z
                local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
                if speed > 1 then
                    local closing = 0
                    if dist > 0 then
                        local toGun = {
                            x = source.x - target.pos.x,
                            y = source.y - target.pos.y,
                            z = source.z - target.pos.z
                        }
                        closing = (vx * toGun.x + vy * toGun.y + vz * toGun.z) / dist
                    end
                    local score = (closing * 4) + (speed * 0.5) - (dist * 0.02)
                    if lastTargetID ~= nil and target.id == lastTargetID then score = score + 25 end
                    if score > bestScore then
                        bestScore, bestTarget = score, target
                    end
                end
            end
        end
    end
    return bestTarget
end

local function chooseLaserConeTarget(source)
    local cannonPitch = cannons[1].getPitch()
    local shipYawDeg = math.deg(getYaw())
    local lookVec = yawPitchToLookVec(shipYawDeg, cannonPitch)
    local lookLen = math.sqrt(lookVec.x * lookVec.x + lookVec.y * lookVec.y + lookVec.z * lookVec.z)
    if lookLen == 0 then return nil end

    local lnx, lny, lnz = lookVec.x / lookLen, lookVec.y / lookLen, lookVec.z / lookLen
    local coneCos = math.cos(math.rad(15))
    local bestTarget, bestScore = nil, -math.huge
    local targets = clusterShips(radar.scanForShips(scanRadius) or {})

    for _, target in ipairs(targets) do
        if isValidTarget(target) then
            local dx = target.pos.x - source.x
            local dy = target.pos.y - source.y
            local dz = target.pos.z - source.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist > 50 then
                local cosAng = (dx / dist) * lnx + (dy / dist) * lny + (dz / dist) * lnz
                if cosAng >= coneCos then
                    local speed = math.sqrt(target.velocity.x^2 + target.velocity.y^2 + target.velocity.z^2)
                    local centered = (cosAng - coneCos) / (1 - coneCos)
                    local score = centered * 3.0 + (1 / (dist + 1)) * 0.5 + (speed > 1 and 1 or 0)
                    if lastTargetID ~= nil and target.id == lastTargetID then score = score + 0.5 end
                    if score > bestScore then
                        bestScore, bestTarget = score, target
                    end
                end
            end
        end
    end

    return bestTarget
end

local function clearTracking(reason)
    lastTargetID = nil
    previousPredictionTargetID = nil
    smoothedFuturePos = nil
    lastCompTargetPos = nil
    velocityCompensation = 1
    previousTargetYaw = nil
    previousYawError = 0
    yawIntegral = 0
    smoothedTargetYawRate = 0
    smoothedLosYawRate = 0
    smoothedYawOutput = 0
    smoothedYawDerivative = 0
    previousMotorOutput = 0
    stopYawMotor()
    if not printedNoTarget then
        print(reason or "LOCK none")
        printedNoTarget = true
    end
end

local function resetYawTrackingForNewTarget(targetID)
    if lastTargetID ~= nil and targetID ~= lastTargetID then
        previousTargetYaw = nil
        previousYawError = 0
        yawIntegral = 0
        smoothedTargetYawRate = 0
        smoothedLosYawRate = 0
        smoothedYawOutput = 0
        smoothedYawDerivative = 0
        previousMotorOutput = 0
        previousRotateTime = os.clock()
    end
end

local function trackTarget(target, modeName, source)
    resetYawTrackingForNewTarget(target.id)
    local requiredRelativeYaw, requiredRelativePitch, yaw, pitch, futurePos = aimCannonWithLead(target.pos, target.velocity, source, target.id)
    requiredRelativeYaw = normalizeAngle(requiredRelativeYaw)
    local shipVelocity = ship.getVelocity()
    local relativeVelocity = {
        x = target.velocity.x * velocityCompensation - shipVelocity.x,
        y = target.velocity.y * velocityCompensation - shipVelocity.y,
        z = target.velocity.z * velocityCompensation - shipVelocity.z,
    }
    local losYawRate = estimateHorizontalYawRate(source, futurePos or target.pos, relativeVelocity)
    setPitchYaw(requiredRelativePitch, localCannonYaw)
    rotateTurret(requiredRelativeYaw, yaw, losYawRate)
    lastTargetID = target.id
    printedNoTarget = false
    print(string.format(
        "%s id=%s dist=%.1f yaw=%.2f pitch=%.2f relYaw=%.2f relPitch=%.2f",
        modeName,
        tostring(target.id),
        vecDistance(target.pos, source),
        yaw,
        pitch,
        requiredRelativeYaw,
        requiredRelativePitch
    ))
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
                            resetYawTrackingForNewTarget(bestTarget.id)
                            local requiredRelativeYaw, requiredRelativePitch, yaw, pitch, futurePos = aimCannonWithLead(bestTarget.pos, bestTarget.velocity, shipPos, bestTarget.id)
                            local shipVelocity = ship.getVelocity()
                            local relativeVelocity = {
                                x = bestTarget.velocity.x * velocityCompensation - shipVelocity.x,
                                y = bestTarget.velocity.y * velocityCompensation - shipVelocity.y,
                                z = bestTarget.velocity.z * velocityCompensation - shipVelocity.z,
                            }
                            local losYawRate = estimateHorizontalYawRate(shipPos, futurePos or bestTarget.pos, relativeVelocity)
                            setPitchYaw(requiredRelativePitch, localCannonYaw)
                            rotateTurret(requiredRelativeYaw, yaw, losYawRate)
                            lastTargetID = bestTarget.id
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
                clearTracking("LOCK standby")
            end
            --end
        end
        sleep(0.1)
    end
end

laserRangeFinderMain()
