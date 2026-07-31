-- Rangefinder + Stabilizer V2 autolock
-- Cleaned production script with latest Rangefinder_StabV2_autolock_extracted.lua
-- ballistic solver/tracking, but yaw rotation is driven by redstone thrusters
-- instead of cannon.setYaw().

local radar = peripheral.find("sp_radar")
local camera = peripheral.find("camera")

local CANNON_TYPES = {
    ["createbigcannons:cannon_mount"] = true,
    ["cbcmodernwarfare:compact_mount"] = true,
    ["cbc_cannon_mount"] = true,
    ["cbcmf_compact_cannon_mount"] = true,
}

local redstoneSides = {
    laserRangeFinder = "front",
    cannonLeftOutput = "left",
    cannonRightOutput = "right",
}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function lerp(a, b, t) return a + (b - a) * t end
local function lerpVec3(a, b, t)
    return { x = lerp(a.x, b.x, t), y = lerp(a.y, b.y, t), z = lerp(a.z, b.z, t) }
end
local function vecDistance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function vecLen(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function getNumber(value, fallback) local n = tonumber(value); if n == nil then return fallback end; return n end
local function normalizeAngle(angle)
    while angle > 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    return angle
end
local function sign(value) if value > 0 then return 1 elseif value < 0 then return -1 end; return 0 end

local cannons, foundNames = {}, {}
local function addCannonByName(name)
    if not name or foundNames[name] then return end
    local pType = peripheral.getType and peripheral.getType(name) or nil
    if CANNON_TYPES[pType] then
        local cannon = peripheral.wrap(name)
        if cannon then
            table.insert(cannons, cannon)
            foundNames[name] = true
            print("Found cannon: " .. tostring(name))
        end
    end
end

if peripheral.getNames then
    for _, name in ipairs(peripheral.getNames()) do addCannonByName(name) end
else
    for _, side in ipairs({ "top", "bottom", "left", "right", "front", "back" }) do
        if peripheral.isPresent and peripheral.isPresent(side) then addCannonByName(side) end
    end
    local i, nilCount = 0, 0
    while nilCount < 200 do
        local before = #cannons
        for typeName in pairs(CANNON_TYPES) do addCannonByName(typeName .. "_" .. i) end
        nilCount = (#cannons == before) and (nilCount + 1) or 0
        i = i + 1
    end
end

-- Fallback for environments where only peripheral.find exists.
if #cannons == 0 then
    local cannon = peripheral.find("createbigcannons:cannon_mount")
        or peripheral.find("cbcmodernwarfare:compact_mount")
        or peripheral.find("cbc_cannon_mount")
        or peripheral.find("cbcmf_compact_cannon_mount")
    if cannon then table.insert(cannons, cannon) end
end

if not radar then error("No sp_radar peripheral found") end
if #cannons == 0 then error("No cannon mount peripheral found") end
for _, cannon in ipairs(cannons) do if cannon.assemble then cannon.assemble() end end
print("Total cannons found: " .. #cannons)

local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. tostring(defaultValue) .. ")")
    local input = io.read()
    if input == nil or input == "" then return defaultValue end
    return input
end
local function askNumber(prompt, defaultValue) return tonumber(askUser(prompt, defaultValue)) or defaultValue end
local function askBoolean(prompt, defaultValue)
    local defaultText = defaultValue and "yes" or "no"
    local value = tostring(askUser(prompt, defaultText)):lower()
    return value == "yes" or value == "y" or value == "true" or value == "1" or value == "on"
end

-- Ballistics from latest extracted script.
local projectileSpeed = askNumber("Enter projectile speed (blocks/second)", 250)
local g = askNumber("Enter gravity per tick", 0.02)
local cd = askNumber("Enter drag multiplier per tick", 0.995)
local enableLaserRangeFinder = askBoolean("Enable redstone laser rangefinder tracking?", true)
local enableAlwaysAutolock = askBoolean("Enable always-on radar autolock?", true)

-- 0 is correct when camera/source is muzzle-space. Use barrel length only for pivot-space source.
local barrelLength = askNumber("Enter barrel/source forward offset", 0)
local sourceHeightOffset = askNumber("Enter source height offset", 0)

local scanRadius = 2000
local aimInterval = 0.05
local fireCooldown = 0.18
local autoFire = true
local statusLogInterval = 0.25
local enableYawDebugLog = askBoolean("Enable yaw debug CSV log?", true)
local yawDebugLogPath = askUser("Yaw debug log file", "autolock_yaw_debug.csv")
local clearYawDebugLog = askBoolean("Clear old yaw debug log at startup?", true)
local yawDebugLogInterval = askNumber("Yaw debug log interval seconds", 0.05)
local enableShellDebugLog = askBoolean("Log traveling shell from radar?", true)
local shellEntityName = askUser("Shell entity type to log", "entity.cbcmodernwarfare.he_mediumshell")
local shellScanRadius = askNumber("Shell radar scan radius", 700)
local ticksPerSecond = 20
local futurePosSmoothing = 1
local velocityCompSmoothing = 0.25
local minVelocityCompensation = 0.5
local maxVelocityCompensation = 1.15
local leadTimeScale = 1
local leadTimeBias = 0
local maxLeadTime = 10
local leadIterations = 3
local pitchLowLimit = -20
local pitchHighLimit = 75
local pitchSolveIterations = 14

-- Yaw-thruster PID/feed-forward. Positive output drives right side, negative drives left side.
local yawIntegral, previousYawError, previousTargetYaw = 0, 0, nil
local previousRotateTime = os.clock()
local yawKp, yawKi, yawKd = 3.4, 0, 0.18
-- Gain schedule used near lock.  The old single high Kp stayed aggressive until
-- relYaw was almost zero, so the yaw motor was still driving hard when it
-- should already be braking.  Use high Kp only while acquiring, then blend to
-- a lower P / higher D controller in the capture band.
local yawCaptureBand = 12
local yawFineBand = 4
local yawTrackKp, yawFineKp = 2.1, 1.25
local yawTrackKd, yawFineKd = 0.42, 0.68
local yawDerivativeSmoothing = 0.45
local smoothedYawDerivative = 0
-- The debug log showed the ballistic lead itself is about right:
-- leadYawDelta ~= targetYawRate * flightTime.  The miss/under-lead was coming
-- from yaw control lag: with Ki=0 and yawFeedForwardGain=0 the turret/ship had
-- to stay ~1 degree behind the desired lead angle just to produce the steady
-- motor power needed to follow a target crossing at ~3.2 deg/s.
--
-- Positive feed-forward turns target yaw rate directly into motor output, so a
-- crossing target can be followed without needing a permanent relYaw error.
local yawFeedForwardGain = 2.0
local yawRateSmoothing = 0.35
local smoothedTargetYawRate = 0
local yawOutputSmoothing = 0.60
local yawOutputBrakeSmoothing = 0.85
local yawOutputSlewPerSecond = 40
local yawOutputBrakeSlewPerSecond = 90
local smoothedYawOutput = 0
local yawMinPower = 0
local yawDeadzone = 0.18
local yawIntegralLimit = 20
local yawDebugLast, yawDebugLastWrite = nil, -999
local lastShellPos, lastShellTime = nil, nil
local shellTrackSeq, shellWasVisible = 0, false

local localCannonYaw = cannons[1].getYaw and cannons[1].getYaw() or 0
local smoothedFuturePos, previousPredictionTargetID = nil, nil
local lastCompTargetPos, lastCompTime, velocityCompensation = nil, os.clock(), 1
local lastTargetID, lastStatusLogTime, printedNoTarget = nil, -999, false
local lastFireTime = -999

local yawDebugHeader = table.concat({
    "clock",
    "mode",
    "target_id",
    "dist",
    "source_x", "source_y", "source_z",
    "target_x", "target_y", "target_z",
    "target_vx", "target_vy", "target_vz",
    "ship_vx", "ship_vy", "ship_vz",
    "future_x", "future_y", "future_z",
    "flight_time",
    "present_yaw",
    "lead_yaw_delta",
    "world_yaw",
    "world_pitch",
    "rel_yaw",
    "rel_pitch",
    "yaw_dt",
    "yaw_error",
    "yaw_integral",
    "yaw_derivative",
    "target_yaw_rate",
    "raw_output",
    "final_output",
    "motor_output",
    "motor_signal",
    "motor_left",
    "motor_right",
    "local_cannon_yaw",
    "velocity_compensation",
    "shell_visible",
    "shell_seq",
    "shell_type",
    "shell_x", "shell_y", "shell_z",
    "shell_dt",
    "shell_vx", "shell_vy", "shell_vz",
    "shell_speed",
    "shell_dist_source",
    "shell_dist_target",
    "shell_horizontal_source",
    "shell_vertical_from_source",
    "shell_expected_y_from_pitch",
    "shell_y_error_vs_solver",
}, ",")

local function csvValue(value)
    if value == nil then return "" end
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return "" end
        return string.format("%.6f", value)
    end
    value = tostring(value)
    if string.find(value, '[,"\n]') then value = '"' .. string.gsub(value, '"', '""') .. '"' end
    return value
end

local function appendYawDebug(row)
    if not enableYawDebugLog then return end
    local now = os.clock()
    if now - yawDebugLastWrite < yawDebugLogInterval then return end
    yawDebugLastWrite = now

    local exists = fs and fs.exists and fs.exists(yawDebugLogPath)
    local handle
    if fs and fs.open then
        handle = fs.open(yawDebugLogPath, exists and "a" or "w")
    elseif io and io.open then
        handle = io.open(yawDebugLogPath, exists and "a" or "w")
    end
    if not handle then return end

    if not exists then
        if handle.writeLine then handle.writeLine(yawDebugHeader) else handle:write(yawDebugHeader .. "\n") end
    end

    local line = table.concat({
        csvValue(row.clock),
        csvValue(row.mode),
        csvValue(row.target_id),
        csvValue(row.dist),
        csvValue(row.source_x), csvValue(row.source_y), csvValue(row.source_z),
        csvValue(row.target_x), csvValue(row.target_y), csvValue(row.target_z),
        csvValue(row.target_vx), csvValue(row.target_vy), csvValue(row.target_vz),
        csvValue(row.ship_vx), csvValue(row.ship_vy), csvValue(row.ship_vz),
        csvValue(row.future_x), csvValue(row.future_y), csvValue(row.future_z),
        csvValue(row.flight_time),
        csvValue(row.present_yaw),
        csvValue(row.lead_yaw_delta),
        csvValue(row.world_yaw),
        csvValue(row.world_pitch),
        csvValue(row.rel_yaw),
        csvValue(row.rel_pitch),
        csvValue(row.yaw_dt),
        csvValue(row.yaw_error),
        csvValue(row.yaw_integral),
        csvValue(row.yaw_derivative),
        csvValue(row.target_yaw_rate),
        csvValue(row.raw_output),
        csvValue(row.final_output),
        csvValue(row.motor_output),
        csvValue(row.motor_signal),
        csvValue(row.motor_left),
        csvValue(row.motor_right),
        csvValue(row.local_cannon_yaw),
        csvValue(row.velocity_compensation),
        csvValue(row.shell_visible),
        csvValue(row.shell_seq),
        csvValue(row.shell_type),
        csvValue(row.shell_x), csvValue(row.shell_y), csvValue(row.shell_z),
        csvValue(row.shell_dt),
        csvValue(row.shell_vx), csvValue(row.shell_vy), csvValue(row.shell_vz),
        csvValue(row.shell_speed),
        csvValue(row.shell_dist_source),
        csvValue(row.shell_dist_target),
        csvValue(row.shell_horizontal_source),
        csvValue(row.shell_vertical_from_source),
        csvValue(row.shell_expected_y_from_pitch),
        csvValue(row.shell_y_error_vs_solver),
    }, ",")

    if handle.writeLine then handle.writeLine(line) else handle:write(line .. "\n") end
    if handle.writeLine then handle.close() else handle:close() end
end

if enableYawDebugLog and clearYawDebugLog and fs and fs.exists and fs.exists(yawDebugLogPath) then
    fs.delete(yawDebugLogPath)
end
if enableYawDebugLog then print("Yaw debug CSV: " .. tostring(yawDebugLogPath)) end

local function normalizeVector(v)
    local length = math.sqrt(v[1]^2 + v[2]^2 + v[3]^2)
    if length == 0 then return { 0, 0, 0 } end
    return { v[1] / length, v[2] / length, v[3] / length }
end
local function normalizeRotationMatrix(rotMatrix)
    local normalizedMatrix = {}
    for i = 1, #rotMatrix do normalizedMatrix[i] = normalizeVector(rotMatrix[i]) end
    return normalizedMatrix
end
local function getShipYaw()
    local rotMatrix = ship.getTransformationMatrix()
    local m = normalizeRotationMatrix(rotMatrix)
    return math.atan2(-m[3][1], -m[3][3])
end
local function yawPitchToLookVec(yawDeg, pitchDeg)
    local yaw, pitch = math.rad(yawDeg), math.rad(pitchDeg)
    return { x = math.sin(yaw) * math.cos(pitch), y = math.sin(pitch), z = -math.cos(yaw) * math.cos(pitch) }
end
local function getSourcePosition()
    local source = (camera and camera.getCameraPosition) and camera.getCameraPosition() or ship.getWorldspacePosition()
    return { x = source.x, y = source.y + sourceHeightOffset, z = source.z }
end

local function findRelativeAngle(targetYaw, targetPitch)
    local rot = ship.getQuaternion()
    local cacheYaw = math.pi - math.rad(targetYaw)
    local cachePitch = -math.rad(targetPitch)
    local rotMatAdj11 = 1 - 2 * (rot.x^2 + rot.y^2)
    local rotMatAdj12 = 2 * (rot.z * rot.x + rot.y * rot.w)
    local rotMatAdj13 = 2 * (rot.z * rot.y - rot.x * rot.w)
    local rotMatAdj21 = 2 * (rot.z * rot.x - rot.y * rot.w)
    local rotMatAdj22 = 1 - 2 * (rot.z^2 + rot.y^2)
    local rotMatAdj23 = 2 * (rot.x * rot.y + rot.z * rot.w)
    local rotMatAdj31 = 2 * (rot.z * rot.y + rot.x * rot.w)
    local rotMatAdj32 = 2 * (rot.x * rot.y - rot.z * rot.w)
    local rotMatAdj33 = 1 - 2 * (rot.z^2 + rot.x^2)
    local rotMatTGT11 = math.cos(cacheYaw) * math.cos(cachePitch)
    local rotMatTGT21 = math.sin(cacheYaw) * math.cos(cachePitch)
    local rotMatTGT31 = -math.sin(cachePitch)
    local rotMatRSLT11 = rotMatAdj11 * rotMatTGT11 + rotMatAdj12 * rotMatTGT21 + rotMatAdj13 * rotMatTGT31
    local rotMatRSLT21 = rotMatAdj21 * rotMatTGT11 + rotMatAdj22 * rotMatTGT21 + rotMatAdj23 * rotMatTGT31
    local rotMatRSLT31 = rotMatAdj31 * rotMatTGT11 + rotMatAdj32 * rotMatTGT21 + rotMatAdj33 * rotMatTGT31
    local turretYaw = math.atan2(rotMatRSLT21, rotMatRSLT11)
    local barrelPitch = math.asin(-rotMatRSLT31)
    return math.deg(-turretYaw), math.deg(-barrelPitch)
end

local function getFlightTimeTicksHorizontal(horizontalDistance, muzzleVelocity, pitchDeg)
    local r = getNumber(cd, 0.995)
    local v0 = getNumber(muzzleVelocity, 260) / ticksPerSecond
    local vx0 = v0 * math.cos(math.rad(pitchDeg))
    if vx0 <= 0.0001 then return nil end
    if math.abs(r - 1) < 1e-9 then return horizontalDistance / vx0 end
    local inside = 1 - horizontalDistance * (1 - r) / (vx0 * r)
    if inside <= 0 then return nil end
    return math.log(inside) / math.log(r)
end
local function getProjectileYAtTicks(ticks, muzzleVelocity, pitchDeg)
    local r = getNumber(cd, 0.995)
    local gravity = getNumber(g, 0.02)
    local v0 = getNumber(muzzleVelocity, 260) / ticksPerSecond
    local vy0 = v0 * math.sin(math.rad(pitchDeg))
    if math.abs(r - 1) < 1e-9 then return vy0 * ticks - gravity * ticks * (ticks - 1) * 0.5 end
    local dragSum = r * (1 - r ^ ticks) / (1 - r)
    -- The shell log showed the old gravity term over-predicted drop.  CBC-style
    -- projectiles apply the first tick of gravity after the first movement
    -- sample, and that gravity contribution is also drag-scaled.  The previous
    -- formula behaved like gravity had already acted for one extra tick:
    --   -g * (ticks - dragSum) / (1 - r)
    -- which made the shell appear consistently above the predicted arc.
    return vy0 * dragSum - gravity * r * (ticks - ((1 - r ^ ticks) / (1 - r))) / (1 - r)
end
local function solvePitchAndFlightTime(horizontalDistanceFromPivot, verticalDistanceFromPivot, muzzleVelocity)
    if horizontalDistanceFromPivot < 0.001 then return 90, 0 end
    local low, high = pitchLowLimit, pitchHighLimit
    local bestPitch, bestTicks, bestError = nil, nil, math.huge
    for _ = 1, pitchSolveIterations do
        local mid = (low + high) * 0.5
        local midRad = math.rad(mid)
        local horizontalDistanceFromMuzzle = horizontalDistanceFromPivot - barrelLength * math.cos(midRad)
        local verticalDistanceFromMuzzle = verticalDistanceFromPivot - barrelLength * math.sin(midRad)
        if horizontalDistanceFromMuzzle < 0.001 then horizontalDistanceFromMuzzle = 0.001 end
        local ticks = getFlightTimeTicksHorizontal(horizontalDistanceFromMuzzle, muzzleVelocity, mid)
        if ticks == nil then
            high = mid
        else
            local errorY = getProjectileYAtTicks(ticks, muzzleVelocity, mid) - verticalDistanceFromMuzzle
            local absError = math.abs(errorY)
            if absError < bestError then bestError, bestPitch, bestTicks = absError, mid, ticks end
            if errorY < 0 then low = mid else high = mid end
        end
    end
    if bestPitch == nil or bestTicks == nil then
        local fallbackPitch = math.deg(math.atan2(verticalDistanceFromPivot, horizontalDistanceFromPivot))
        local distance = math.sqrt(horizontalDistanceFromPivot^2 + verticalDistanceFromPivot^2)
        return fallbackPitch, distance / muzzleVelocity
    end
    return bestPitch, bestTicks / ticksPerSecond
end

local function shellPosX(p) return p and (p.x or p[1]) or nil end
local function shellPosY(p) return p and (p.y or p[2]) or nil end
local function shellPosZ(p) return p and (p.z or p[3]) or nil end

local function findShellEntity(source, target)
    if not enableShellDebugLog or not radar.scanForEntities then return nil end
    local results = radar.scanForEntities(shellScanRadius) or {}
    local best, bestScore = nil, math.huge
    for _, e in ipairs(results) do
        if e.pos and (shellEntityName == "" or e.entity_type == shellEntityName) then
            local ex, ey, ez = shellPosX(e.pos), shellPosY(e.pos), shellPosZ(e.pos)
            if ex and ey and ez then
                local dSource = math.sqrt((ex - source.x)^2 + (ey - source.y)^2 + (ez - source.z)^2)
                local dTarget = target and target.pos and math.sqrt((ex - target.pos.x)^2 + (ey - target.pos.y)^2 + (ez - target.pos.z)^2) or 0

                -- Prefer shells that are between/near the firing line, but keep this
                -- loose because the whole point is to catch bad ballistic paths.
                local score = dSource + dTarget * 0.15
                if score < bestScore then
                    best, bestScore = e, score
                end
            end
        end
    end
    return best
end

local function getShellDebugSample(source, target, worldPitch)
    local now = os.clock()
    local e = findShellEntity(source, target)
    if not e or not e.pos then
        shellWasVisible = false
        return { shell_visible = 0 }
    end

    local pos = { x = shellPosX(e.pos), y = shellPosY(e.pos), z = shellPosZ(e.pos) }
    if not pos.x or not pos.y or not pos.z then
        shellWasVisible = false
        return { shell_visible = 0 }
    end

    if not shellWasVisible or not lastShellTime or now - lastShellTime > 0.75 then
        shellTrackSeq = shellTrackSeq + 1
        lastShellPos, lastShellTime = nil, nil
    end
    shellWasVisible = true

    local dt, vx, vy, vz, speed = nil, nil, nil, nil, nil
    if lastShellPos and lastShellTime then
        dt = now - lastShellTime
        if dt > 0.001 then
            vx = (pos.x - lastShellPos.x) / dt
            vy = (pos.y - lastShellPos.y) / dt
            vz = (pos.z - lastShellPos.z) / dt
            speed = math.sqrt(vx*vx + vy*vy + vz*vz)
        end
    end
    lastShellPos, lastShellTime = { x = pos.x, y = pos.y, z = pos.z }, now

    local dx, dy, dz = pos.x - source.x, pos.y - source.y, pos.z - source.z
    local horizontal = math.sqrt(dx*dx + dz*dz)
    local distSource = math.sqrt(dx*dx + dy*dy + dz*dz)
    local distTarget = target and target.pos and vecDistance(pos, target.pos) or nil

    local expectedY, yErr = nil, nil
    local pitchRad = math.rad(worldPitch or 0)
    local horizontalFromMuzzle = horizontal - barrelLength * math.cos(pitchRad)
    if horizontalFromMuzzle < 0.001 then horizontalFromMuzzle = 0.001 end
    local ticks = getFlightTimeTicksHorizontal(horizontalFromMuzzle, projectileSpeed, worldPitch or 0)
    if ticks then
        expectedY = barrelLength * math.sin(pitchRad) + getProjectileYAtTicks(ticks, projectileSpeed, worldPitch or 0)
        yErr = dy - expectedY
    end

    return {
        shell_visible = 1,
        shell_seq = shellTrackSeq,
        shell_type = e.entity_type,
        shell_x = pos.x, shell_y = pos.y, shell_z = pos.z,
        shell_dt = dt,
        shell_vx = vx, shell_vy = vy, shell_vz = vz,
        shell_speed = speed,
        shell_dist_source = distSource,
        shell_dist_target = distTarget,
        shell_horizontal_source = horizontal,
        shell_vertical_from_source = dy,
        shell_expected_y_from_pitch = expectedY,
        shell_y_error_vs_solver = yErr,
    }
end

local function updateVelocityCompensation(targetPos, targetVel, targetID)
    local currentTime = os.clock()
    if previousPredictionTargetID ~= targetID or lastCompTargetPos == nil then
        lastCompTargetPos = { x = targetPos.x, y = targetPos.y, z = targetPos.z }
        lastCompTime, velocityCompensation = currentTime, 1
        return velocityCompensation
    end
    local dt = currentTime - lastCompTime
    if dt >= 0.5 then
        local reportedDistance = vecLen(targetVel) * dt
        if reportedDistance > 0.01 then
            local raw = clamp(vecDistance(targetPos, lastCompTargetPos) / reportedDistance, minVelocityCompensation, maxVelocityCompensation)
            velocityCompensation = lerp(velocityCompensation, raw, velocityCompSmoothing)
        end
        lastCompTargetPos = { x = targetPos.x, y = targetPos.y, z = targetPos.z }
        lastCompTime = currentTime
    end
    return velocityCompensation
end
local function predictFuturePosition(targetPos, targetVel, source, targetID)
    local shipVelocity = ship.getVelocity()
    local targetSpeed = vecLen(targetVel)
    if targetSpeed < 1 then
        smoothedFuturePos = { x = targetPos.x, y = targetPos.y, z = targetPos.z }
        return smoothedFuturePos, 0
    end
    local compensation = updateVelocityCompensation(targetPos, targetVel, targetID)
    local relativeVelocity = {
        x = targetVel.x * compensation - shipVelocity.x,
        y = targetVel.y * compensation - shipVelocity.y,
        z = targetVel.z * compensation - shipVelocity.z,
    }
    if previousPredictionTargetID ~= targetID then
        previousPredictionTargetID = targetID
        smoothedFuturePos = { x = targetPos.x, y = targetPos.y, z = targetPos.z }
    end
    local futurePos = { x = targetPos.x, y = targetPos.y, z = targetPos.z }
    local flightTime = 0
    for _ = 1, leadIterations do
        local dx, dy, dz = futurePos.x - source.x, futurePos.y - source.y, futurePos.z - source.z
        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local _
        _, flightTime = solvePitchAndFlightTime(horizontalDistance, dy, projectileSpeed)
        if flightTime == nil or flightTime ~= flightTime or flightTime < 0 then
            flightTime = vecDistance(futurePos, source) / getNumber(projectileSpeed, 260)
        end
        flightTime = clamp(flightTime * leadTimeScale + leadTimeBias, 0, maxLeadTime)
        futurePos = {
            x = targetPos.x + relativeVelocity.x * flightTime,
            y = targetPos.y + relativeVelocity.y * flightTime,
            z = targetPos.z + relativeVelocity.z * flightTime,
        }
    end
    smoothedFuturePos = lerpVec3(smoothedFuturePos, futurePos, futurePosSmoothing)
    return smoothedFuturePos, flightTime
end
local function aimCannonWithLead(targetPos, targetVel, source, targetID)
    local futurePos, flightTime = predictFuturePosition(targetPos, targetVel, source, targetID)
    local dx, dy, dz = futurePos.x - source.x, futurePos.y - source.y, futurePos.z - source.z
    local yaw = (math.deg(math.atan2(-dx, dz)) + 180) % 360
    local horizontalDistance = math.sqrt(dx * dx + dz * dz)
    local pitch
    pitch, flightTime = solvePitchAndFlightTime(horizontalDistance, dy, projectileSpeed)
    if pitch == nil or pitch ~= pitch then pitch = math.deg(math.atan2(dy, horizontalDistance)) end
    pitch = clamp(pitch, pitchLowLimit, pitchHighLimit)
    local relYaw, relPitch = findRelativeAngle(yaw, pitch)
    return relYaw, relPitch, yaw, pitch, futurePos, flightTime
end

local function setPitchYaw(targetPitch, targetYaw)
    for _, cannon in ipairs(cannons) do
        cannon.setPitch(targetPitch)
        cannon.setYaw(targetYaw)
    end
end
local function setYawMotor(output)
    output = clamp(output, -15, 15)
    local signal = clamp(math.floor(math.abs(output) + 0.5), 0, 15)
    local leftSignal, rightSignal = 0, 0
    if output < 0 then
        leftSignal, rightSignal = signal, 0
    elseif output > 0 then
        leftSignal, rightSignal = 0, signal
    end
    redstone.setAnalogOutput(redstoneSides.cannonLeftOutput, leftSignal)
    redstone.setAnalogOutput(redstoneSides.cannonRightOutput, rightSignal)
    return {
        output = output,
        signal = signal,
        left = leftSignal,
        right = rightSignal,
    }
end
local function rotateTurret(requiredRelativeYaw, targetYaw)
    local currentTime = os.clock()
    local dt = currentTime - previousRotateTime
    if dt <= 0 or dt > 0.5 then dt = 0.1 end
    previousRotateTime = currentTime
    requiredRelativeYaw, targetYaw = normalizeAngle(requiredRelativeYaw), normalizeAngle(targetYaw)
    yawIntegral = clamp(yawIntegral + requiredRelativeYaw * dt, -yawIntegralLimit, yawIntegralLimit)
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
    local rawOutput = effectiveKp * requiredRelativeYaw + yawKi * yawIntegral + effectiveKd * derivative
    local targetYawRate = 0
    if previousTargetYaw ~= nil then
        local deltaTargetYaw = normalizeAngle(targetYaw - previousTargetYaw)
        local measuredTargetYawRate = deltaTargetYaw / dt
        if math.abs(deltaTargetYaw) > 45 then
            measuredTargetYawRate, smoothedTargetYawRate, yawIntegral = 0, 0, 0
        end
        smoothedTargetYawRate = lerp(smoothedTargetYawRate, measuredTargetYawRate, yawRateSmoothing)
        targetYawRate = smoothedTargetYawRate
    end
    previousTargetYaw = targetYaw
    local finalOutput = rawOutput + yawFeedForwardGain * targetYawRate
    if math.abs(requiredRelativeYaw) < yawDeadzone and math.abs(targetYawRate) < 1 then finalOutput, yawIntegral = 0, 0 end
    if finalOutput ~= 0 and math.abs(finalOutput) < yawMinPower then finalOutput = sign(finalOutput) * yawMinPower end
    local commandedOutput = finalOutput

    -- Radar updates are only about every 0.20-0.25s in the debug log.  Near
    -- lock, smooth and slew-limit same-direction changes, but allow fast sign
    -- reversals so the controller can brake before crossing zero instead of
    -- waiting for several over/under cycles.
    if absError > yawCaptureBand then
        smoothedYawOutput = finalOutput
    else
        local previousOutput = yawDebugLast and yawDebugLast.motor_output or smoothedYawOutput
        local reversing = previousOutput ~= 0 and finalOutput ~= 0 and sign(previousOutput) ~= sign(finalOutput)
        local alpha = reversing and yawOutputBrakeSmoothing or yawOutputSmoothing
        smoothedYawOutput = lerp(smoothedYawOutput, finalOutput, alpha)
        local maxStep = (reversing and yawOutputBrakeSlewPerSecond or yawOutputSlewPerSecond) * dt
        local delta = smoothedYawOutput - previousOutput
        if delta > maxStep then
            smoothedYawOutput = previousOutput + maxStep
        elseif delta < -maxStep then
            smoothedYawOutput = previousOutput - maxStep
        end
        finalOutput = smoothedYawOutput
    end

    local motor = setYawMotor(finalOutput)
    yawDebugLast = {
        yaw_dt = dt,
        yaw_error = requiredRelativeYaw,
        yaw_integral = yawIntegral,
        yaw_derivative = derivative,
        target_yaw_rate = targetYawRate,
        raw_output = rawOutput,
        final_output = commandedOutput,
        motor_output = motor.output,
        motor_signal = motor.signal,
        motor_left = motor.left,
        motor_right = motor.right,
    }
end
local function stopYawMotor() setYawMotor(0) end

local function fireCannons()
    if not autoFire then return end
    local now = os.clock()
    if now - lastFireTime < fireCooldown then return end

    for _, cannon in ipairs(cannons) do
        if cannon.fire then cannon.fire() end
    end
    lastFireTime = now
end

local function isValidTarget(target)
    return target and target.pos and target.velocity
        and target.pos.x and target.pos.y and target.pos.z
        and target.velocity.x and target.velocity.y and target.velocity.z
end
local function chooseAutolockTarget(source)
    local bestTarget, bestScore = nil, -math.huge
    for _, target in ipairs(radar.scanForShips(scanRadius) or {}) do
        if isValidTarget(target) then
            local dist = vecDistance(target.pos, source)
            if dist > 20 then
                local speed = vecLen(target.velocity)
                local closing = 0
                if speed > 1 then
                    if dist > 0 then
                        local toGun = { x = source.x - target.pos.x, y = source.y - target.pos.y, z = source.z - target.pos.z }
                        closing = (target.velocity.x * toGun.x + target.velocity.y * toGun.y + target.velocity.z * toGun.z) / dist
                    end
                    local score = (closing * 4) + (speed * 0.5) - (dist * 0.02)
                    if lastTargetID ~= nil and target.id == lastTargetID then score = score + 25 end
                    if score > bestScore then bestScore, bestTarget = score, target end
                end
            end
        end
    end
    return bestTarget
end
local function chooseLaserConeTarget(source)
    local cannonPitch = cannons[1].getPitch and cannons[1].getPitch() or 0
    local shipYawDeg = math.deg(getShipYaw())
    local lookVec = yawPitchToLookVec(shipYawDeg, cannonPitch)
    local lookLen = vecLen(lookVec)
    if lookLen == 0 then return nil end
    local lnx, lny, lnz = lookVec.x / lookLen, lookVec.y / lookLen, lookVec.z / lookLen
    local coneCos = math.cos(math.rad(15))
    local bestTarget, bestScore = nil, -math.huge
    for _, target in ipairs(radar.scanForShips(scanRadius) or {}) do
        if isValidTarget(target) then
            local dx, dy, dz = target.pos.x - source.x, target.pos.y - source.y, target.pos.z - source.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist > 50 then
                local cosAng = (dx / dist) * lnx + (dy / dist) * lny + (dz / dist) * lnz
                if cosAng >= coneCos then
                    local centered = (cosAng - coneCos) / (1 - coneCos)
                    local score = centered * 3.0 + (1 / (dist + 1)) * 0.5 + (vecLen(target.velocity) > 1 and 1 or 0)
                    if lastTargetID ~= nil and target.id == lastTargetID then score = score + 0.5 end
                    if score > bestScore then bestScore, bestTarget = score, target end
                end
            end
        end
    end
    return bestTarget
end
local function clearTracking(reason)
    lastTargetID, previousPredictionTargetID, smoothedFuturePos, lastCompTargetPos = nil, nil, nil, nil
    velocityCompensation, previousTargetYaw, previousYawError, yawIntegral = 1, nil, 0, 0
    smoothedTargetYawRate, smoothedYawOutput, smoothedYawDerivative = 0, 0, 0
    stopYawMotor()
    if not printedNoTarget then print(reason or "LOCK none"); printedNoTarget = true end
end
local function trackTarget(target, modeName)
    if lastTargetID ~= nil and target.id ~= lastTargetID then
        previousTargetYaw, previousYawError, yawIntegral = nil, 0, 0
        smoothedTargetYawRate, smoothedYawOutput, smoothedYawDerivative = 0, 0, 0
        previousRotateTime = os.clock()
        yawDebugLast = nil
    end
    local source = getSourcePosition()
    local relYaw, relPitch, worldYaw, worldPitch, futurePos, flightTime = aimCannonWithLead(target.pos, target.velocity, source, target.id)
    local presentDx, presentDz = target.pos.x - source.x, target.pos.z - source.z
    local presentYaw = (math.deg(math.atan2(-presentDx, presentDz)) + 180) % 360
    local leadYawDelta = normalizeAngle(worldYaw - presentYaw)
    relYaw = normalizeAngle(relYaw)
    setPitchYaw(relPitch, localCannonYaw)
    rotateTurret(relYaw, worldYaw)
    local shipVelocity = ship.getVelocity()
    local yaw = yawDebugLast or {}
    local shellSample = getShellDebugSample(source, target, worldPitch)
    appendYawDebug({
        clock = os.clock(),
        mode = modeName,
        target_id = target.id,
        dist = vecDistance(target.pos, source),
        source_x = source.x, source_y = source.y, source_z = source.z,
        target_x = target.pos.x, target_y = target.pos.y, target_z = target.pos.z,
        target_vx = target.velocity.x, target_vy = target.velocity.y, target_vz = target.velocity.z,
        ship_vx = shipVelocity.x, ship_vy = shipVelocity.y, ship_vz = shipVelocity.z,
        future_x = futurePos.x, future_y = futurePos.y, future_z = futurePos.z,
        flight_time = flightTime or 0,
        present_yaw = presentYaw,
        lead_yaw_delta = leadYawDelta,
        world_yaw = worldYaw,
        world_pitch = worldPitch,
        rel_yaw = relYaw,
        rel_pitch = relPitch,
        yaw_dt = yaw.yaw_dt,
        yaw_error = yaw.yaw_error,
        yaw_integral = yaw.yaw_integral,
        yaw_derivative = yaw.yaw_derivative,
        target_yaw_rate = yaw.target_yaw_rate,
        raw_output = yaw.raw_output,
        final_output = yaw.final_output,
        motor_output = yaw.motor_output,
        motor_signal = yaw.motor_signal,
        motor_left = yaw.motor_left,
        motor_right = yaw.motor_right,
        local_cannon_yaw = localCannonYaw,
        velocity_compensation = velocityCompensation,
        shell_visible = shellSample.shell_visible,
        shell_seq = shellSample.shell_seq,
        shell_type = shellSample.shell_type,
        shell_x = shellSample.shell_x, shell_y = shellSample.shell_y, shell_z = shellSample.shell_z,
        shell_dt = shellSample.shell_dt,
        shell_vx = shellSample.shell_vx, shell_vy = shellSample.shell_vy, shell_vz = shellSample.shell_vz,
        shell_speed = shellSample.shell_speed,
        shell_dist_source = shellSample.shell_dist_source,
        shell_dist_target = shellSample.shell_dist_target,
        shell_horizontal_source = shellSample.shell_horizontal_source,
        shell_vertical_from_source = shellSample.shell_vertical_from_source,
        shell_expected_y_from_pitch = shellSample.shell_expected_y_from_pitch,
        shell_y_error_vs_solver = shellSample.shell_y_error_vs_solver,
    })
    lastTargetID, printedNoTarget = target.id, false
    local now = os.clock()
    if now - lastStatusLogTime >= statusLogInterval then
        print(string.format(
            "%s id=%s dist=%.1f yaw=%.2f leadYaw=%.2f relYaw=%.2f relPitch=%.2f t=%.2f out=%.2f sig=%d L=%d R=%d future=(%.1f,%.1f,%.1f)",
            modeName, tostring(target.id), vecDistance(target.pos, source), worldYaw, leadYawDelta, relYaw, relPitch,
            flightTime or 0, yaw.final_output or 0, yaw.motor_signal or 0, yaw.motor_left or 0, yaw.motor_right or 0,
            futurePos.x, futurePos.y, futurePos.z
        ))
        lastStatusLogTime = now
    end
end

local function main()
    while true do
        local source = getSourcePosition()
        local target, modeName = nil, nil
        if enableLaserRangeFinder and redstone.getInput(redstoneSides.laserRangeFinder) then
            target, modeName = chooseLaserConeTarget(source), "LASER"
        elseif enableAlwaysAutolock then
            target, modeName = chooseAutolockTarget(source), "LOCK"
        end
        if target then trackTarget(target, modeName) else clearTracking("LOCK none") end
        sleep(aimInterval)
    end
end

parallel.waitForAny(main)
