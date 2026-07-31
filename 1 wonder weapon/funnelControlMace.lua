radar = peripheral.find("sp_radar")
engine = peripheral.find("EngineController")
modem = peripheral.find("modem")

lockedTarget = {}

RS = {fire = "right"}

sleep(0.2)
muzzleVelocity = 180

local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

funnelControlChannel = askUser("Enter the funnel control channel",1400)
modem.open(funnelControlChannel)

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

local function clampAngle180(angle)
    angle = (angle + 180) % 360 - 180
    return angle
end

function scanForTarget(lockedId)
    local results = radar.scanForShips(4000)
    pos = ship.getWorldspacePosition()
    local targetSpeed = 0

    for i, object in ipairs(results) do
        if object.id == lockedId then
            return object
        end
    end
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

local function predictFuturePosition(targetPos, targetVel, sourcePos, sourceVel, projectileSpeed)
    -- relative velocity: how target moves as seen from the shooter
    local relVel = {
        x = targetVel.x - sourceVel.x,
        y = targetVel.y - sourceVel.y,
        z = targetVel.z - sourceVel.z
    }

    -- distance now
    local dx = targetPos.x - sourcePos.x
    local dy = targetPos.y - sourcePos.y
    local dz = targetPos.z - sourcePos.z
    local distance = math.sqrt(dx*dx + dy*dy + dz*dz)

    if projectileSpeed <= 0.001 then
        return targetPos, 0
    end

    -- time-to-hit (straight-line approx)
    local t = distance / projectileSpeed
    t = math.max(0, t)

    -- lead using constant relative velocity
    local estimate = {
        x = targetPos.x + relVel.x * t,
        y = targetPos.y + relVel.y * t,
        z = targetPos.z + relVel.z * t
    }

    return estimate, t
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

local yawError = 0
local yawIntegral = 0
local yawPrevError = 0

local pitchError = 0
local pitchIntegral = 0
local pitchPrevError = 0
Kp_torque, Ki_torque, Kd_torque = 1500000, 0, 5000
function aimShip(targetInfo)
    if not targetInfo then return end
    shipPos = ship.getWorldspacePosition()
    shipVelocity = ship.getVelocity()
    estimatePos, time = predictFuturePosition(targetInfo.pos, targetInfo.velocity, shipPos, shipVelocity, muzzleVelocity)
    requiredRelativeYaw, requiredRelativePitch, globalTargetYaw, globalTargetPitch = computeLocalYawPitch(estimatePos, shipPos)

    currentYaw = clampAngle180(math.deg(getYaw()) - 180)
    currentPitch = math.deg(getPitch())

    --print("deltaYaw: "..requiredRelativeYaw)
    --print("deltaPitch: "..requiredRelativePitch)

    local yawError = requiredRelativeYaw
    local yawOutput, yawIntegral, yawPrevError = PIDController(Kp_torque, Ki_torque, Kd_torque, yawError, yawIntegral, (yawError - yawPrevError), yawPrevError, 0.05)
    yawOutput = -math.max(math.min(yawOutput,200000000),-200000000)

    -- PID control for pitch
    local pitchError = requiredRelativePitch
    local pitchOutput, pitchIntegral, pitchPrevError = PIDController(Kp_torque, Ki_torque, Kd_torque, pitchError, pitchIntegral, (pitchError - pitchPrevError), pitchPrevError, 0.05)
    pitchOutput = -math.max(math.min(pitchOutput,200000000),-200000000)

    engine.applyRotDependentTorque(pitchOutput, yawOutput, 0)
end

-- Orbit params (tune these)
local orbitRadius = 120
local minAboveTarget = 8          -- keep at least this much above target.y (upper hemisphere)
local tangentialForceMag = 8000000 * math.random(1,1.4)  -- how hard you "push sideways" to keep orbiting

local Kp_radial, Kd_radial = 400000, 20000
local Kp_vert,   Kd_vert   = 800000, 20000

-- random orbit "wander" state
local nextWanderT = 0
local orbitRadiusCur = orbitRadius
local tangentialCur = tangentialForceMag
local jitterX, jitterZ = 0, 0

-- extra vertical wander state
local vertOffsetCur = minAboveTarget
local jitterY = 0

local funnelAvoidR = 20          -- how close funnels can get before pushing away
local funnelAvoidF = 80000       -- repulsion strength

-- Introduce a random factor for orbit direction
local randomDirection = math.random(0, 1) == 0 and 1 or -1  -- 1 for clockwise, -1 for counterclockwise

local function rotateAroundTarget(targetInfo)
    if not targetInfo or not targetInfo.pos then return end

    local now = os.clock()
    if now > nextWanderT then
        nextWanderT = now + 1.2 + math.random() * 1.5
        orbitRadiusCur = orbitRadius
        tangentialCur  = tangentialForceMag * (0.6 + math.random() * 0.8)

        jitterX = (math.random() * 2 - 1) * (tangentialForceMag * 0.15)
        jitterZ = (math.random() * 2 - 1) * (tangentialForceMag * 0.15)

        -- NEW: random vertical bobbing (always stays above target)
        vertOffsetCur = minAboveTarget + math.random() * 25   -- 8..33m above target
        jitterY = (math.random() * 2 - 1) * 8000              -- small vertical force jitter
    end

    local myPos = ship.getWorldspacePosition()
    local myVel = ship.getVelocity()
    local tgtPos = targetInfo.pos
    local tgtVel = targetInfo.velocity or {x=0,y=0,z=0}

    local rx = myPos.x - tgtPos.x
    local ry = myPos.y - tgtPos.y
    local rz = myPos.z - tgtPos.z
    local dist = math.sqrt(rx*rx + ry*ry + rz*rz)
    if dist < 0.001 then return end

    local rix, riy, riz = rx/dist, ry/dist, rz/dist

    local rvx = myVel.x - tgtVel.x
    local rvy = myVel.y - tgtVel.y
    local rvz = myVel.z - tgtVel.z

    local radialSpeed = rvx*rix + rvy*riy + rvz*riz
    local radialErr = dist - orbitRadiusCur
    local Fr = (-Kp_radial * radialErr) - (Kd_radial * radialSpeed)

    local tx, tz = riz, -rix
    local tmag = math.sqrt(tx*tx + tz*tz)
    if tmag < 1e-4 then return end
    tx, tz = tx/tmag, tz/tmag

    local sx, sz = -tz, tx

    -- Flip the direction of the tangential force based on random direction
    local Fx = Fr * rix + tangentialCur * randomDirection * tx + jitterX * sx
    local Fz = Fr * riz + tangentialCur * randomDirection * tz + jitterZ * sz

    -- UPDATED: target vertical position includes vertical wander
    local yTarget = tgtPos.y + vertOffsetCur
    local yErr = yTarget - myPos.y
    local Fy = (Kp_vert * yErr) - (Kd_vert * rvy) + jitterY

    -- repel other funnels WITHOUT slowing orbit: remove tangential component
    local neighbors = radar.scanForShips(funnelAvoidR) or {}
    for _, o in ipairs(neighbors) do
        if o.scale and o.scale.x == 0.5 then
            local dx = myPos.x - o.pos.x
            local dy = myPos.y - o.pos.y
            local dz = myPos.z - o.pos.z
            local d2 = dx*dx + dy*dy + dz*dz
            if d2 > 0.01 then
                local d = math.sqrt(d2)
                if d < funnelAvoidR then
                    local ux, uy, uz = dx/d, dy/d, dz/d
                    local s = (1 - d/funnelAvoidR)           -- 0..1
                    local F = funnelAvoidF * s

                    -- remove tangential part (so it won't brake orbit)
                    local dotT = ux*tx + uz*tz               -- tangential component along orbit direction
                    local ax = ux - dotT*tx
                    local az = uz - dotT*tz

                    Fx = Fx + ax * F
                    Fz = Fz + az * F
                    Fy = Fy + uy * F * 0.3                   -- small vertical push only
                end
            end
        end
    end

    -- Apply forces
    engine.applyInvariantForce(Fx, Fy, Fz)
end

local desiredDist = 0
local Kp_dist, Ki_dist, Kd_dist = 700000, 0.0, 100
local distIntegral, distPrevError = 0, 0
local lastMoveT = os.clock()

function closeInitiate(targetInfo, direction)
    if not targetInfo or not targetInfo.pos then return end

    local dt = 0.05

    local myPos = ship.getWorldspacePosition()
    local dx = targetInfo.pos.x - myPos.x
    local dy = targetInfo.pos.y - myPos.y
    local dz = targetInfo.pos.z - myPos.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    if dist < 0.001 then return end

    -- distance error: positive means "we are too far" => push forward (+z)
    local distError = desiredDist - dist  -- NOTE: negative when too far
    distError = -distError                -- flip so: too far => positive

    distIntegral = newI
    distPrevError = newPrev

    local thrustZ
    -- clamp force (tune these)
    if direction == -1 then
        thrustZ = 200000
    elseif direction == 1 then 
        thrustZ = 9000000
    end


    -- Calculate the direction to the target
    local directionX = dx / dist * direction
    local directionY = dy / dist * direction
    local directionZ = dz / dist * direction

    -- Apply the force in the direction of the target using invariant force
    engine.applyInvariantForce(directionX * thrustZ, directionY * thrustZ, directionZ * thrustZ)
end

function closeExecute(targetInfo, direction)
    if not targetInfo or not targetInfo.pos then return end

    local dt = 0.05

    local myPos = ship.getWorldspacePosition()
    local dx = targetInfo.pos.x - myPos.x
    local dy = targetInfo.pos.y - myPos.y
    local dz = targetInfo.pos.z - myPos.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    if dist < 0.001 then return end

    -- distance error: positive means "we are too far" => push forward (+z)
    local distError = desiredDist - dist  -- NOTE: negative when too far
    distError = -distError                -- flip so: too far => positive

    distIntegral = newI
    distPrevError = newPrev

    local thrustZ
    -- clamp force (tune these)
    if direction == -1 then
        thrustZ = 200000
    elseif direction == 1 then 
        thrustZ = 900000000
    end


    -- Calculate the direction to the target
    local directionX = dx / dist * direction
    local directionY = dy / dist * direction
    local directionZ = dz / dist * direction

    -- Apply the force in the direction of the target using invariant force
    engine.applyInvariantForce(0, -900000000, 0)
end

function handleFiring()
    local lastFireTime = 0  -- Stores when we last fired
    local fireCooldown = 4  -- Cooldown in seconds
    
    while true do
        -- Get current time in seconds
        local currentTime = os.clock()
        
        -- Check if we can fire: target exists AND fire command is true AND cooldown has passed
        if lockedTarget and lockedTarget.fire and (currentTime - lastFireTime >= fireCooldown) then
            redstone.setOutput(RS.fire, true)
            lastFireTime = currentTime  -- Update last fire time
            print("Fired at time: " .. currentTime)
            
            -- Keep signal active briefly (optional, for visual/mechanical effect)
            sleep(0.1)
            redstone.setOutput(RS.fire, false)
        else
            redstone.setOutput(RS.fire, false)
        end
        
        sleep()  -- Small delay to prevent CPU overload
    end
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == funnelControlChannel then
                lockedTarget = message
            end
        else
            sleep()
        end
    end
end

parallel.waitForAny(
    function ()
        notLocked = true
        iterationSinceCloseIniation = 0
        while true do
            if lockedTarget and lockedTarget.id then
                print(textutils.serialize(lockedTarget))

                if lockedTarget.type == "enemy" and notLocked then
                    sleep(math.random(0,2))
                    randomDirection = math.random(0, 1) == 0 and 1 or -1
                    notLocked = false
                end
                
                targetInfo = scanForTarget(lockedTarget.id)
                if lockedTarget.type == "enemy" then
                    aimShip(targetInfo)
                    rotateAroundTarget(targetInfo)
                    iterationSinceCloseIniation = 0
                elseif lockedTarget.type == "recall" and lockedTarget.pos then
                    aimShip({pos = lockedTarget.pos, velocity = {x=0,y=0,z=0}})
                    rotateAroundTarget(targetInfo)
                    notLocked = true
                    iterationSinceCloseIniation = 0
                elseif lockedTarget.type == "closeInitiate" then
                    if iterationSinceCloseIniation < 20 then
                        closeInitiate(targetInfo, -1)
                        iterationSinceCloseIniation = iterationSinceCloseIniation + 1
                    else
                        closeInitiate(targetInfo, 1)
                    end
                    aimShip(targetInfo)
                elseif lockedTarget.type == "closeExecute" then
                    closeExecute(targetInfo, 1)
                end
            end
            sleep()
        end
    end,
    handleFiring,
    modemMessage
)