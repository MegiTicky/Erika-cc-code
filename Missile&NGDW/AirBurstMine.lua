local radar = peripheral.find("sp_radar")
local RS = {detonation = "top", thrust = "bottom"}
local cannon = peripheral.wrap("bottom")
local detectionRadius = 500  -- Define the horizontal radius for detection (in meters or game units)
local maxAltitude = 500  -- Maximum altitude the mine will reach

cannon.assemble()
cannon.setPitch(90)

print("Press enter to arm")
io.read()

local function findRelativeAngle(targetYaw, targetPitch)
    -- This function computes the relative angle of the target to the ship
    -- (same as your current implementation)
    rot = ship.getQuaternion()
    cacheYaw = math.pi - math.rad(targetYaw)
    cachePitch = -math.rad(targetPitch)
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
    return math.deg(-turretYaw), math.deg(-barrelPitch)
end

local function computeLocalYawPitch(targetPos, source)
    -- Calculate the required yaw and pitch to point at the target
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

-- Predict future position of the target based on its velocity
local function predictFuturePosition(targetPos, targetVel, missilePos, missileSpeed)
    local dx = targetPos.x - missilePos.x
    local dy = targetPos.y - missilePos.y
    local dz = targetPos.z - missilePos.z
    local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
    
    -- Estimate time to target
    local timeToTarget = 5

    -- Estimate future position
    local futurePos = {
        x = targetPos.x + targetVel.x * timeToTarget,
        y = targetPos.y + targetVel.y * timeToTarget,
        z = targetPos.z + targetVel.z * timeToTarget
    }

    return futurePos
end

while true do
    local results = radar.scanForShips(detectionRadius)
    local pos = ship.getWorldspacePosition()  -- Get the missile's current position
    local missileX, missileY, missileZ = pos.x, pos.y, pos.z

    local targetDetected = false  -- Flag to check if a target is detected

    -- Loop through the radar scan results
    for i, object in ipairs(results) do
        local targetPos = object.pos
        local dx = targetPos.x - missileX
        local dz = targetPos.z - missileZ
        local horizontalDistance = math.sqrt(dx^2 + dz^2)

        local futurePos = predictFuturePosition(targetPos, object.velocity, pos)

        -- If the target is within the horizontal detection radius
        if horizontalDistance <= detectionRadius then
            targetDetected = true
            print("Target detected within range!")

            -- Activate the thruster (bottom) and fly up to match the altitude
            redstone.setAnalogOutput(RS.thrust, 5)  -- Activate thrust
            local targetAltitude = targetPos.y
            local missileAltitude = missileY

            -- Fly up to match the target's altitude (if not already at the target altitude)
            while math.abs(missileAltitude - targetAltitude) > 5 do
                missileAltitude = ship.getWorldspacePosition().y
                -- Keep flying up until altitude is close to the target
                sleep()
            end

            print("Altitude matched with target!")

            -- Predict future position of the target
            local futurePos = predictFuturePosition(targetPos, object.velocity, pos, missileSpeed)

            -- Check if the target is within 100m horizontally
            local dx = futurePos.x - missileX
            local dz = futurePos.z - missileZ
            local horizontalDistanceToTarget = math.sqrt(dx^2 + dz^2)

            if horizontalDistanceToTarget <= 100 then
                print("Target within 100m, firing cannon!")
                -- Aim and fire the cannon
                local targetYaw, targetPitch = computeLocalYawPitch(futurePos, pos)
                cannon.setYaw(targetYaw)
                cannon.setPitch(targetPitch)
                cannon.fire()
            end
        end
    end

    -- If no target is detected, ensure systems are off
    if not targetDetected then
        redstone.setOutput(RS.thrust, false)
    end

    -- Sleep for a short duration before scanning again
    sleep()
end
