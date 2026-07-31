-- targetPractice.lua
-- Engine-controller driven target drone for testing a gunner ship.
--
-- Requirements:
--   * This computer must be on the target/practice ship.
--   * A Some Peripherals radar ("sp_radar") must be attached.
--   * A CCVS/VoidPower engine controller ("EngineController") must be attached,
--     or the ship API must expose applyInvariantForce.
--
-- Adding a new mode:
--   1. Copy one of the registerMode({...}) blocks near the bottom.
--   2. Give it a unique key/name.
--   3. Implement askConfig(optional), init(optional), and update(ctx, state, cfg).
--      update receives the gunner radar object in ctx.gunner and should call
--      applyForce(ctx, {x=..., y=..., z=...}).

local radar = peripheral.find("sp_radar")
local engine = peripheral.find("EngineController")

if not radar then error("No sp_radar peripheral found") end
if not ship then error("No CCVS ship API found. Put this computer on the target ship.") end
if not engine then
    if ship.applyInvariantForce then
        engine = ship
        print("No EngineController found; using ship.applyInvariantForce fallback.")
    else
        error("No EngineController peripheral found")
    end
end

math.randomseed(os.epoch and os.epoch("utc") or os.time())

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local quickStart = false
local programArgs = { ... }

local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. tostring(defaultValue) .. ")")
    local input = io.read()
    if input == nil or input == "" then return defaultValue end
    return input
end

local function askNumber(prompt, defaultValue)
    local n = tonumber(askUser(prompt, defaultValue))
    if n == nil then return defaultValue end
    return n
end

local function askBoolean(prompt, defaultValue)
    local defaultText = defaultValue and "yes" or "no"
    local value = tostring(askUser(prompt, defaultText)):lower()
    return value == "yes" or value == "y" or value == "true" or value == "1" or value == "on"
end

local function maybeAskNumber(prompt, defaultValue)
    if quickStart then return defaultValue end
    return askNumber(prompt, defaultValue)
end

local function maybeAskBoolean(prompt, defaultValue)
    if quickStart then return defaultValue end
    return askBoolean(prompt, defaultValue)
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function sign(value)
    if value > 0 then return 1 end
    if value < 0 then return -1 end
    return 0
end

local function vec(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
local function lerpVec3(a, b, t) return vec(lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t)) end
local function vadd(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
local function vsub(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
local function vmul(a, s) return vec(a.x * s, a.y * s, a.z * s) end
local function vdot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function vlen(a) return math.sqrt(vdot(a, a)) end
local function vnorm(a)
    local l = vlen(a)
    if l < 0.000001 then return vec(0, 0, 0), 0 end
    return vmul(a, 1 / l), l
end
local function vhorizontal(a) return vec(a.x, 0, a.z) end

local function limitVec(a, maxLen)
    local l = vlen(a)
    if maxLen <= 0 or l <= maxLen or l < 0.000001 then return a end
    return vmul(a, maxLen / l)
end

local function safeVelocity(object)
    return (object and object.velocity) or vec(0, 0, 0)
end

local function distance(a, b) return vlen(vsub(a, b)) end

local function formatVec(a)
    return string.format("%.1f %.1f %.1f", a.x or 0, a.y or 0, a.z or 0)
end

local function getShipMass()
    if ship.getMass then
        local ok, mass = pcall(ship.getMass)
        if ok and tonumber(mass) and mass > 0 then return mass end
    end
    return 10000
end

local function applyForce(ctx, force)
    force = limitVec(force, ctx.forceLimit)
    engine.applyInvariantForce(force.x, force.y, force.z)
    ctx.lastForce = force
end

local function brakeTowardVelocity(ctx, desiredVelocity, strength)
    desiredVelocity = desiredVelocity or vec(0, 0, 0)
    strength = (strength or 2.0) * (ctx.accelScale or 1)
    local velErr = vsub(desiredVelocity, ctx.myVel)
    applyForce(ctx, limitVec(vmul(velErr, ctx.mass * strength), ctx.forceLimit))
end

local function scanForShip(id, scanRange)
    local results = radar.scanForShips(scanRange) or {}
    for _, object in ipairs(results) do
        if tonumber(object.id) == tonumber(id) then
            return object
        end
    end
    return nil
end

local function randomHorizontalUnit()
    local a = math.random() * math.pi * 2
    return vec(math.cos(a), 0, math.sin(a))
end

local function horizontalUnitFrom(fromPos, toPos)
    local h = vhorizontal(vsub(toPos, fromPos))
    local u, l = vnorm(h)
    if l < 0.001 then return randomHorizontalUnit(), 0 end
    return u, l
end

local function forceToMovingPoint(ctx, targetPos, targetVel, maxSpeed, posGain, velGain)
    local accelScale = ctx.accelScale or 1
    local err = vsub(targetPos, ctx.myPos)
    local dir, distToPoint = vnorm(err)
    local desiredSpeed = clamp(distToPoint * 0.8, 0, maxSpeed)
    local desiredVel = vadd(targetVel or vec(0, 0, 0), vmul(dir, desiredSpeed))
    local velErr = vsub(desiredVel, ctx.myVel)
    local accel = vadd(vmul(err, (posGain or 0.25) * accelScale), vmul(velErr, (velGain or 2.5) * accelScale))
    applyForce(ctx, vmul(accel, ctx.mass))
    return distToPoint
end

local function computeRangeStatus(ctx)
    if not ctx.gunner then return "NO RADAR" end
    if ctx.range < ctx.minRange then return "INSIDE MIN" end
    if ctx.range > ctx.maxRange then return "OUTSIDE MAX" end
    return "IN RANGE"
end

local modes = {}
local modeOrder = {}

local function registerMode(mode)
    table.insert(modeOrder, mode)
    modes[mode.key] = mode
end

-- Mode 1: stay inside the effective range and strafe around the gunner.
registerMode({
    key = "strafe",
    name = "Constant velocity strafe",
    description = "Holds range and moves sideways at a mostly constant relative speed.",

    askConfig = function(common)
        local defaultRange = common.minRange + (common.maxRange - common.minRange) * 0.75
        if common.minRange <= 0 then defaultRange = common.maxRange * 0.75 end
        return {
            desiredRange = clamp(maybeAskNumber("Strafe hold range", math.floor(defaultRange)), common.minRange + 2, common.maxRange - 2),
            strafeSpeed = maybeAskNumber("Strafe relative speed in blocks/s", 25),
            heightOffset = maybeAskNumber("Height offset above gunner", 0),
            direction = maybeAskNumber("Direction: 1 clockwise, -1 counterclockwise, 0 random", 0),
        }
    end,

    init = function(ctx, state, cfg)
        if cfg.direction == 0 then
            state.direction = (math.random(0, 1) == 0) and 1 or -1
        else
            state.direction = sign(cfg.direction)
            if state.direction == 0 then state.direction = 1 end
        end
    end,

    update = function(ctx, state, cfg)
        local accelScale = ctx.accelScale or 1
        local gunnerPos = ctx.gunner.pos
        local gunnerVel = safeVelocity(ctx.gunner)

        local horizontal = vhorizontal(vsub(ctx.myPos, gunnerPos))
        local outward, horizontalDist = vnorm(horizontal)
        if horizontalDist < 0.001 then outward = randomHorizontalUnit() end

        local tangent = vec(-outward.z * state.direction, 0, outward.x * state.direction)
        local relVel = vsub(ctx.myVel, gunnerVel)
        local radialSpeed = vdot(relVel, outward)
        local tangentSpeed = vdot(relVel, tangent)

        local desiredRange = clamp(cfg.desiredRange, ctx.minRange + 1, ctx.maxRange - 1)
        local rangeError = horizontalDist - desiredRange

        -- outwards is positive.  Too far -> negative accel; too close -> positive accel.
        local radialAccel = (-1.20 * rangeError - 2.20 * radialSpeed) * accelScale

        -- Hard guards so the drone prioritizes staying in the configured effective range.
        if ctx.range > ctx.maxRange then
            radialAccel = radialAccel - (ctx.range - ctx.maxRange) * 3.0 * accelScale
        elseif ctx.range < ctx.minRange then
            radialAccel = radialAccel + (ctx.minRange - ctx.range) * 3.0 * accelScale
        end

        local tangentAccel = (cfg.strafeSpeed - tangentSpeed) * 1.40 * accelScale
        local wantedY = gunnerPos.y + cfg.heightOffset
        local yAccel = ((wantedY - ctx.myPos.y) * 1.00 + (gunnerVel.y - ctx.myVel.y) * 2.00) * accelScale

        radialAccel = clamp(radialAccel, -90 * accelScale, 90 * accelScale)
        tangentAccel = clamp(tangentAccel, -70 * accelScale, 70 * accelScale)
        yAccel = clamp(yAccel, -50 * accelScale, 50 * accelScale)

        local accel = vadd(vadd(vmul(outward, radialAccel), vmul(tangent, tangentAccel)), vec(0, yAccel, 0))
        applyForce(ctx, vmul(accel, ctx.mass))
    end,
})

-- Mode 2: random strafe.  Mostly flies a straight relative line with a small
-- lateral curve.  It only picks a new line every ~10s, so it is less "snap
-- dodge" and more like a realistic target making gentle course changes.
registerMode({
    key = "random",
    name = "Random strafe",
    description = "Mostly straight strafe with gentle lateral drift and slow course changes.",

    askConfig = function(common)
        return {
            baseSpeed = maybeAskNumber("Random strafe base speed in blocks/s", 30),
            speedJitter = maybeAskNumber("Random extra speed range", 6),
            directionChangeTimeMin = maybeAskNumber("Min seconds before changing course", 9.0),
            directionChangeTimeMax = maybeAskNumber("Max seconds before changing course", 12.0),
            turnBlendTime = maybeAskNumber("Seconds to blend into new course", 2.5),
            lateralAccel = maybeAskNumber("Gentle lateral acceleration", 3.5),
            heightJitter = maybeAskNumber("Random height jitter", 6),
            heightOffset = maybeAskNumber("Base height offset above gunner", 0),
            directionFlipChance = maybeAskNumber("Reverse course chance each change 0-1", 0.05),
        }
    end,

    init = function(ctx, state, cfg)
        local toDrone = vhorizontal(vsub(ctx.myPos, ctx.gunner.pos))
        local outward, horizontalDist = vnorm(toDrone)
        if horizontalDist < 0.001 then outward = randomHorizontalUnit() end
        state.direction = (math.random(0, 1) == 0) and 1 or -1
        state.travelDir = vec(-outward.z * state.direction, 0, outward.x * state.direction)
        state.targetDir = state.travelDir
        state.nextChange = 0
        state.desiredRange = (ctx.minRange + ctx.maxRange) * 0.5
        state.targetRange = state.desiredRange
        state.speed = cfg.baseSpeed
        state.height = cfg.heightOffset
        state.sideAccel = 0
    end,

    update = function(ctx, state, cfg)
        local accelScale = ctx.accelScale or 1
        local gunnerPos = ctx.gunner.pos
        local gunnerVel = safeVelocity(ctx.gunner)

        local now = ctx.now or os.clock()
        if now >= (state.nextChange or 0) then
            local minT = cfg.directionChangeTimeMin or 9
            local maxT = cfg.directionChangeTimeMax or 12
            local interval = minT + math.random() * math.max(0.1, maxT - minT)
            state.nextChange = now + interval

            local safeMin = ctx.minRange + math.max(8, (ctx.maxRange - ctx.minRange) * 0.12)
            local safeMax = ctx.maxRange - math.max(8, (ctx.maxRange - ctx.minRange) * 0.12)
            if safeMax <= safeMin then safeMin, safeMax = ctx.minRange, ctx.maxRange end
            state.targetRange = safeMin + math.random() * math.max(1, safeMax - safeMin)
            state.speed = cfg.baseSpeed + (math.random() * 2 - 1) * cfg.speedJitter
            state.speed = math.max(8, state.speed)
            state.height = cfg.heightOffset + (math.random() * 2 - 1) * cfg.heightJitter

            if math.random() < cfg.directionFlipChance then state.direction = -state.direction end

            -- New target course is still generally tangent to the gunner, but
            -- is rotated by a small angle.  The actual course blends toward it
            -- over turnBlendTime instead of snapping instantly.
            local horizontal = vhorizontal(vsub(ctx.myPos, gunnerPos))
            local outward, horizontalDist = vnorm(horizontal)
            if horizontalDist < 0.001 then outward = randomHorizontalUnit() end
            local tangent = vec(-outward.z * state.direction, 0, outward.x * state.direction)
            local angle = (math.random() * 2 - 1) * math.rad(18)
            local ca, sa = math.cos(angle), math.sin(angle)
            state.targetDir = vec(tangent.x * ca - tangent.z * sa, 0, tangent.x * sa + tangent.z * ca)
            local targetUnit, targetLen = vnorm(state.targetDir)
            if targetLen < 0.001 then targetUnit = tangent end
            state.targetDir = targetUnit
            state.sideAccel = (math.random() * 2 - 1) * cfg.lateralAccel
        end

        local horizontal = vhorizontal(vsub(ctx.myPos, gunnerPos))
        local outward, horizontalDist = vnorm(horizontal)
        if horizontalDist < 0.001 then outward = randomHorizontalUnit() end

        local blend = clamp((ctx.dt or 0.05) / math.max(0.1, cfg.turnBlendTime or 2.5), 0, 1)
        local mixedDir = lerpVec3(state.travelDir or state.targetDir, state.targetDir or randomHorizontalUnit(), blend)
        local mixedUnit, mixedLen = vnorm(mixedDir)
        if mixedLen < 0.001 then mixedUnit = state.targetDir or randomHorizontalUnit() end
        state.travelDir = mixedUnit
        local tangent = state.travelDir
        local side = vec(-tangent.z, 0, tangent.x)
        local relVel = vsub(ctx.myVel, gunnerVel)
        local radialSpeed = vdot(relVel, outward)
        local alongSpeed = vdot(relVel, tangent)

        state.desiredRange = lerp(state.desiredRange or state.targetRange or horizontalDist, state.targetRange or horizontalDist, blend * 0.35)
        local desiredRange = clamp(state.desiredRange, ctx.minRange + 2, ctx.maxRange - 2)
        local rangeError = horizontalDist - desiredRange

        -- Soft range hold keeps the target valid without forcing a hard circular
        -- strafe.  The main motion is the straight-line velocity controller.
        local radialAccel = (-0.45 * rangeError - 1.10 * radialSpeed) * accelScale
        if ctx.range > ctx.maxRange then
            radialAccel = radialAccel - (ctx.range - ctx.maxRange) * 3.0 * accelScale
        elseif ctx.range < ctx.minRange then
            radialAccel = radialAccel + (ctx.minRange - ctx.range) * 3.0 * accelScale
        end

        local forwardAccel = (state.speed - alongSpeed) * 0.45 * accelScale
        local sideSpeed = vdot(relVel, side)
        local sideAccel = ((state.sideAccel or 0) - sideSpeed * 0.35) * accelScale
        local wantedY = gunnerPos.y + state.height
        local yAccel = ((wantedY - ctx.myPos.y) * 0.45 + (gunnerVel.y - ctx.myVel.y) * 1.10) * accelScale

        radialAccel = clamp(radialAccel, -55 * accelScale, 55 * accelScale)
        forwardAccel = clamp(forwardAccel, -30 * accelScale, 30 * accelScale)
        sideAccel = clamp(sideAccel, -10 * accelScale, 10 * accelScale)
        yAccel = clamp(yAccel, -28 * accelScale, 28 * accelScale)

        local accel = vadd(vadd(vmul(outward, radialAccel), vmul(tangent, forwardAccel)), vmul(side, sideAccel))
        accel = vadd(accel, vec(0, yAccel, 0))
        applyForce(ctx, vmul(accel, ctx.mass))
    end,
})

-- Mode 3: stage just outside the effective range, then dive at the gunner.
registerMode({
    key = "missile",
    name = "Incoming missile",
    description = "Moves to a start point just beyond max effective range, then dives inward.",

    askConfig = function(common)
        return {
            startOffset = maybeAskNumber("Start offset beyond max effective range", math.max(25, math.floor(common.maxRange * 0.15))),
            stageSpeed = maybeAskNumber("Staging travel speed in blocks/s", 35),
            diveSpeed = maybeAskNumber("Incoming dive relative speed in blocks/s", 95),
            heightOffset = maybeAskNumber("Staging height offset above gunner", 15),
            stagingTolerance = maybeAskNumber("Distance from staging point before diving", 18),
            breakOffRange = maybeAskNumber("Break/recycle range from gunner", math.max(12, common.minRange + 5)),
            diveTimeLimit = maybeAskNumber("Max seconds per dive before recycling", 15),
            repeatRuns = maybeAskBoolean("Repeat missile runs?", true),
            leadTime = maybeAskNumber("Lead gunner movement by seconds while diving", 0.4),
        }
    end,

    init = function(ctx, state, cfg)
        state.phase = "staging"
        state.approachDir = nil
        state.diveStart = nil
        state.completed = false
    end,

    update = function(ctx, state, cfg)
        local gunnerPos = ctx.gunner.pos
        local gunnerVel = safeVelocity(ctx.gunner)

        if state.completed then
            brakeTowardVelocity(ctx, gunnerVel, 2.5)
            return
        end

        if not state.approachDir then
            local dir = horizontalUnitFrom(gunnerPos, ctx.myPos)
            -- Add a small random rotation so repeated runs are not identical.
            local angle = (math.random() - 0.5) * 0.9
            local ca, sa = math.cos(angle), math.sin(angle)
            state.approachDir = vec(dir.x * ca - dir.z * sa, 0, dir.x * sa + dir.z * ca)
        end

        local startDistance = ctx.maxRange + cfg.startOffset

        if state.phase == "staging" then
            local stagingPos = vadd(gunnerPos, vmul(state.approachDir, startDistance))
            stagingPos.y = gunnerPos.y + cfg.heightOffset

            local d = forceToMovingPoint(ctx, stagingPos, gunnerVel, cfg.stageSpeed, 0.18, 2.4)
            if d <= cfg.stagingTolerance then
                state.phase = "diving"
                state.diveStart = os.clock()
                state.diveDir = nil
                print("Missile run: diving")
            end
            return
        end

        if state.phase == "diving" then
            local accelScale = ctx.accelScale or 1
            local aimPoint = vadd(gunnerPos, vmul(gunnerVel, cfg.leadTime))
            local toGunner = vsub(aimPoint, ctx.myPos)
            local dir, distToAim = vnorm(toGunner)
            if distToAim < 0.001 then dir = vmul(state.approachDir, -1) end

            if not state.diveDir then state.diveDir = dir end

            local relVel = vsub(ctx.myVel, gunnerVel)
            local closingSpeed = vdot(relVel, dir)
            local lateralVel = vsub(relVel, vmul(dir, closingSpeed))

            local speedAccel = (cfg.diveSpeed - closingSpeed) * 2.2 * accelScale
            local lateralDamp = vmul(lateralVel, -1.1 * accelScale)
            local accel = vadd(vmul(dir, clamp(speedAccel, -120 * accelScale, 120 * accelScale)), lateralDamp)
            applyForce(ctx, vmul(accel, ctx.mass))

            local diveAge = os.clock() - (state.diveStart or os.clock())
            local passedGunner = state.diveDir and vdot(vsub(gunnerPos, ctx.myPos), state.diveDir) < -cfg.breakOffRange
            if ctx.range <= cfg.breakOffRange or passedGunner or diveAge > cfg.diveTimeLimit then
                if cfg.repeatRuns then
                    state.phase = "staging"
                    state.approachDir = nil
                    state.diveStart = nil
                    state.diveDir = nil
                    print("Missile run: recycling to a new start point")
                else
                    state.completed = true
                    print("Missile run complete; braking relative to gunner")
                end
            end
        end
    end,
})

local function chooseMode()
    print("")
    print("Select target practice mode:")
    for i, mode in ipairs(modeOrder) do
        print(string.format("  %d) %s - %s", i, mode.name, mode.description))
    end
    while true do
        local choice = askUser("Mode number or key", "1")
        local n = tonumber(choice)
        if n and modeOrder[n] then return modeOrder[n] end
        if modes[choice] then return modes[choice] end
        print("Invalid mode.")
    end
end

term.clear()
term.setCursorPos(1, 1)
print("Target Practice Drone")
print("=====================")
print("Run this on the ship that should act as the target.")
print("Tip: run 'targetPractice advanced' to show all tuning prompts.")
print("")

quickStart = not (tostring(programArgs[1] or ""):lower() == "advanced" or tostring(programArgs[1] or ""):lower() == "adv")

local gunnerId = askNumber("Enter gunner ship ID to test", 0)
if gunnerId == 0 then error("A non-zero gunner ship ID is required") end

local minRange = maybeAskNumber("Minimum effective range", 0)
local maxRange = askNumber("Maximum effective range", 300)
if maxRange <= minRange + 5 then
    maxRange = minRange + 5
    print("Adjusted maximum effective range to " .. maxRange)
end

local mass = getShipMass()
local scanRange = maybeAskNumber("Radar scan range", math.max(maxRange + 1000, 1500))
local forceLimit = maybeAskNumber("Maximum total engine force", math.floor(mass * 2500))
local accelScale = maybeAskNumber("Maneuver acceleration multiplier", 4)
local statusInterval = maybeAskNumber("Status print interval seconds", 0.5)

local common = {
    gunnerId = gunnerId,
    minRange = minRange,
    maxRange = maxRange,
    scanRange = scanRange,
    forceLimit = forceLimit,
    accelScale = accelScale,
    statusInterval = statusInterval,
}

local mode = chooseMode()
local modeConfig = mode.askConfig and mode.askConfig(common) or {}
local modeState = {}

print("")
print("Starting mode: " .. mode.name)
print("Gunner ID: " .. tostring(gunnerId))
print("Effective range: " .. tostring(minRange) .. " - " .. tostring(maxRange))
print("Force limit: " .. tostring(forceLimit) .. "  Accel multiplier: " .. tostring(accelScale))
print("Press Ctrl+T to stop.")
sleep(1)

local lastStatus = -999
local lastTime = os.clock()

while true do
    local now = os.clock()
    local dt = now - lastTime
    lastTime = now
    if dt <= 0 or dt > 1 then dt = 0.05 end

    local myPos = ship.getWorldspacePosition()
    local myVel = ship.getVelocity and ship.getVelocity() or vec(0, 0, 0)
    local gunner = scanForShip(gunnerId, scanRange)

    local ctx = {
        dt = dt,
        now = now,
        myPos = myPos,
        myVel = myVel,
        gunner = gunner,
        mass = mass,
        minRange = minRange,
        maxRange = maxRange,
        scanRange = scanRange,
        forceLimit = forceLimit,
        accelScale = accelScale,
        lastForce = vec(0, 0, 0),
    }

    if gunner and gunner.pos then
        ctx.range = distance(myPos, gunner.pos)
        if not modeState.initialized then
            if mode.init then mode.init(ctx, modeState, modeConfig) end
            modeState.initialized = true
        end
        mode.update(ctx, modeState, modeConfig)
    else
        ctx.range = 0
        brakeTowardVelocity(ctx, vec(0, 0, 0), 1.5)
    end

    if now - lastStatus >= statusInterval then
        lastStatus = now
        term.clear()
        term.setCursorPos(1, 1)
        print("Target Practice Drone")
        print("Mode: " .. mode.name)
        print("Gunner ID: " .. tostring(gunnerId))
        if gunner and gunner.pos then
            print(string.format("Range: %.1f  [%s]", ctx.range, computeRangeStatus(ctx)))
            print("My pos: " .. formatVec(myPos))
            print("Gunner pos: " .. formatVec(gunner.pos))
            if modeState.phase then print("Phase: " .. tostring(modeState.phase)) end
            print("Force: " .. formatVec(ctx.lastForce))
            print("Force limit: " .. tostring(forceLimit) .. "  Accel x" .. tostring(accelScale))
        else
            print("Gunner not found on radar.")
            print("Scan range: " .. tostring(scanRange))
            print("My pos: " .. formatVec(myPos))
        end
        print("")
        print("Press Ctrl+T to stop.")
    end

    sleep(0.05)
end
