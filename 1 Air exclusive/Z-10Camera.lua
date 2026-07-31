local modem = peripheral.wrap("right")
local camera = peripheral.find("camera")
local cannon = peripheral.find("cbc_cannon_mount")
local radar = peripheral.find("sp_radar")
if not(cannon) then
    cannon = peripheral.find("cbcmf_compact_cannon_mount")
end
cannon.assemble()

print("Input the controlChannel, default = 1100")

local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 1100
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel) -- Open a channel to communicate

local missileControlChannel = io.read()
if missileControlChannel == "" then
    missileControlChannel = 1400
end
missileControlChannel = tonumber(missileControlChannel)
modem.open(missileControlChannel) -- Open a channel to communicate

local missileInfoChannel = missileControlChannel + 10
modem.open(missileInfoChannel)

local shipPos = {x=0,y=0,z=0}
local shipVel = {x=0,y=0,z=0}
local hitPos, cameraPos = {x=0,y=0,z=0}, {x=0,y=0,z=0}
local g,cd,projectileSpeed = 0.005, 0.99999999999999, 80
local spreadYawRange = 1 -- Max spread angle for yaw (in degrees)
local spreadPitchRange = 1 -- Max spread angle for pitch (in degrees)

local lockedTarget = {}

local missileId = 1
local missileLaunched = {}
local controls = {
    {cannonControlMode = "manual"},
    fireMissile = {}
}
local LaunchedMissiles = {}
local missileControls = {
    fireMissile = {}
}
local immediateMissileInfo = {}
local AIMInfoList,GBUInfoList,thunderBoltInfoList,AGMInfoList = {},{},{},{}
local AIMCount,GBUCount,thunderboltCount,AGMCount = 0,0,0,0
local missileCoolDown = 20

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
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

local function designation()
    -- Check if camera exists
    if not camera then
        print("Error: Camera peripheral not found")
        return
    end
    camera.setClipRange(200)
    local result = camera.clip()
    --local result = {hit={x=0,y=0,z=0}}
    
    if result and result.hit then
        local hitPos = {
            x = result.hit.x,
            y = result.hit.y,
            z = result.hit.z,
        }
        
        return hitPos
    end
    return
end

local function updateInfo()
    while true do
        shipPos = ship.getWorldspacePosition()
        shipVel = ship.getVelocity()
        cameraPos = camera.getCameraPosition()
        allShips = radar.scanForShips(9999)
        hitPos = designation()
        currentTime = os.clock()
        sleep()
    end
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == cannonHitPosChannel then
                cannonHitPos = message
            elseif channel == controlChannel then
                controls = message
            elseif channel == missileInfoChannel then
                immediateMissileInfo = message
            end
        else
            sleep()
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

local function calculateRange(angle, u, cd, g, c_est, projectileSpeed)
    local radians = math.rad(angle)
    local u = projectileSpeed/20
    local part1 = u * math.cos(radians) / math.log(cd)
    local part2 = ((g * cd) / (g * cd + (1 - cd) * u * math.sin(radians))) ^ (2 + c_est * projectileSpeed * math.sin(radians)) - 1
    local XR = part1 * part2

    return XR
end

local function findBestPitch(targetX, targetY, targetZ, sourceX, sourceY, sourceZ, initialVelocity, g, cd, c_est, projectileSpeed)
    local bestLowPitch = nil
    local bestHighPitch = nil
    local bestLowDistance = math.huge
    local bestHighDistance = math.huge
    local targetDistance = math.sqrt((targetX - sourceX)^2 + (targetZ - sourceZ)^2)

    for pitch = 0, 90, 0.1 do -- Iterate over pitch angles
        local calculatedRange = calculateRange(pitch, initialVelocity, cd, g, c_est, projectileSpeed)
        local distanceDifference = math.abs(calculatedRange - targetDistance)

        -- Find the low-angle solution
        if pitch <= 30 then
            if distanceDifference < bestLowDistance then
                bestLowDistance = distanceDifference
                bestLowPitch = pitch
            end
        -- Find the high-angle solution
        elseif pitch > 30 then
            if distanceDifference < bestHighDistance then
                bestHighDistance = distanceDifference
                bestHighPitch = pitch
            end
        end
    end

    -- If the target is within 400 blocks, prioritize the low-angle solution
    return bestLowPitch
end

local function applySpread(targetYaw, targetPitch, distance)
    -- Avoid division by zero
    if distance < 1 then distance = 1 end

    -- Adjust angle spread inversely with distance (constant spatial spread)
    -- Example: spreadAngle = atan(spreadSize / distance)
    -- Let’s assume a constant spread size of 1 block/metre
    local spatialSpreadSize = 1  -- change as needed
    local effectiveYawSpread = math.deg(math.atan(spatialSpreadSize / distance)) * spreadYawRange
    local effectivePitchSpread = math.deg(math.atan(spatialSpreadSize / distance)) * spreadPitchRange

    -- Apply the adjusted spread
    local yawSpread = (math.random() * 2 - 1) * effectiveYawSpread
    local pitchSpread = (math.random() * 2 - 1) * effectivePitchSpread

    local newYaw = targetYaw + yawSpread
    local newPitch = targetPitch + pitchSpread

    return newYaw, newPitch
end

local lastTargetPos, lastTargetVelocity, predictedTargetVelocity, predictedTargetAcceleration
local lastTargetAqquireTime = os.clock()

local function predictFuturePosition(targetPos, targetVel, source)
    local currentTime = os.clock()
    local dt = currentTime - lastTargetAqquireTime
    --print(textutils.serialize(targetVel))
    local isStaticTarget = targetVel.x == 0 and targetVel.y == 0 and targetVel.z == 0

    if isStaticTarget then
        -- Predict only using ship's velocity (target assumed static)
        local dx = targetPos.x - source.x
        local dy = targetPos.y - source.y
        local dz = targetPos.z - source.z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        local estimateTime = distance / projectileSpeed + 0.5

        return {
            x = targetPos.x - shipVel.x * estimateTime,
            y = targetPos.y - shipVel.y * estimateTime,
            z = targetPos.z - shipVel.z * estimateTime
        }
    end

    -- Dynamic target logic (same as before)
    if not lastTargetPos then
        lastTargetPos = targetPos
        lastTargetVelocity = targetVel
        predictedTargetVelocity = targetVel
        predictedTargetAcceleration = {x = 0, y = 0, z = 0}
        lastTargetAqquireTime = currentTime
    elseif dt >= 0.5 then
        predictedTargetVelocity = {
            x = (targetPos.x - lastTargetPos.x) / dt,
            y = (targetPos.y - lastTargetPos.y) / dt,
            z = (targetPos.z - lastTargetPos.z) / dt
        }

        predictedTargetAcceleration = {
            x = (predictedTargetVelocity.x - lastTargetVelocity.x) / dt,
            y = (predictedTargetVelocity.y - lastTargetVelocity.y) / dt,
            z = (predictedTargetVelocity.z - lastTargetVelocity.z) / dt
        }

        lastTargetPos = targetPos
        lastTargetVelocity = predictedTargetVelocity
        lastTargetAqquireTime = currentTime
    end

    -- Estimate future position (first pass)
    local dx = targetPos.x - source.x
    local dy = targetPos.y - source.y
    local dz = targetPos.z - source.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local estimateTime = distance / projectileSpeed + 0.5

    local ex = targetPos.x
        + (predictedTargetVelocity.x - shipVel.x) * estimateTime
        + 0.5 * predictedTargetAcceleration.x * estimateTime * estimateTime

    local ey = targetPos.y
        + (predictedTargetVelocity.y - shipVel.y) * estimateTime
        + 0.5 * predictedTargetAcceleration.y * estimateTime * estimateTime

    local ez = targetPos.z
        + (predictedTargetVelocity.z - shipVel.z) * estimateTime
        + 0.5 * predictedTargetAcceleration.z * estimateTime * estimateTime

    -- Refine
    dx = ex - source.x; dy = ey - source.y; dz = ez - source.z
    distance = math.sqrt(dx*dx + dy*dy + dz*dz)
    estimateTime = distance / projectileSpeed + 0.2

    ex = targetPos.x
        + (predictedTargetVelocity.x - shipVel.x) * estimateTime
        + 0.5 * predictedTargetAcceleration.x * estimateTime * estimateTime

    ey = targetPos.y
        + (predictedTargetVelocity.y - shipVel.y) * estimateTime
        + 0.5 * predictedTargetAcceleration.y * estimateTime * estimateTime

    ez = targetPos.z
        + (predictedTargetVelocity.z - shipVel.z) * estimateTime
        + 0.5 * predictedTargetAcceleration.z * estimateTime * estimateTime

    return {x = ex, y = ey, z = ez}
end

local requiredRelativePitch,requiredRelativeYaw = 0,180
local function aimCannon(targetPos, targetVel, source)
    if source and source.x then
        futurePos = predictFuturePosition(targetPos, targetVel, source)

        --print(textutils.serialize(futurePos))
        -- Calculate the new dx, dy, dz for the predicted future position
        dx = futurePos.x - source.x
        dy = futurePos.y - source.y
        dz = futurePos.z - source.z

        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        --Adjust pitch based on distance adjustments
        local ballisticPitch = findBestPitch(futurePos.x,futurePos.y,futurePos.z, source.x,source.y,source.z, projectileSpeed, g, cd, 0.0028, projectileSpeed)
        print(ballisticPitch)
        if ballisticPitch then
            pitch = pitch + ballisticPitch
        end

        yaw, pitch = applySpread(yaw, pitch, distance)

        requiredRelativeYaw,requiredRelativePitch = findRelativeAngle(yaw,pitch)
        locked = true        
    end
end

local lengthCorrection = -8.5
local widthCorrection = 0
local heightCorrection = -1.5
local lastRenderTime = os.clock()
local function aimGun()
    while true do
        if controls and controls.cannonControlMode == "mouseAim" then
            adjustedPos = {x=0,y=0,z=0}
            adjustedPos.x = shipPos.x + lengthCorrection * math.cos(getYaw() - math.pi/2) + widthCorrection * math.cos(getYaw())
            adjustedPos.y = shipPos.y + heightCorrection
            adjustedPos.z = shipPos.z + lengthCorrection * math.sin(getYaw() - math.pi/2) + widthCorrection * math.sin(getYaw())

            if lockedTarget and lockedTarget.pos and lockedTarget.pos.x and controls.lockShip then
                --print(textutils.serialize(lockedTarget.velocity))
                aimCannon(lockedTarget.pos,lockedTarget.velocity,cameraPos)
            else
                if currentTime - 0.2 > lastRenderTime then
                    if hitPos and hitPos.x then
                        camera.outlineToUser(
                            hitPos.x, hitPos.y, hitPos.z,
                            "UP",  -- Default direction
                            0xFFFFFF,  -- White
                            "designation"  -- Slot ID
                        )
                    end
                    lastRenderTime = currentTime
                end
                aimCannon(hitPos,{x=0,y=0,z=0},cameraPos)
            end
        end
        if controls and controls.weaponChoosen == "gun" and controls.fire then
            cannon.fire()
        end
        sleep()
    end
end

local rocketSpeed = 60      -- blocks per second (assumed, you can tweak)
-- Convert pitch and yaw to directional unit vector
local function getLaunchVector(pitchDeg, yawDeg)
    local pitchRad = math.rad(pitchDeg)
    local yawRad = math.rad(yawDeg)

    return {
        x = -math.sin(yawRad) * math.cos(pitchRad),
        y = math.sin(pitchRad),
        z = math.cos(yawRad) * math.cos(pitchRad),
    }
end

local function solveQuadratic(a, b, c)
    local discriminant = b*b - 4*a*c
    if discriminant < 0 then return nil end

    local sqrtDisc = math.sqrt(discriminant)
    local t1 = (-b + sqrtDisc) / (2 * a)
    local t2 = (-b - sqrtDisc) / (2 * a)

    -- Return the positive time
    if t1 > 0 and t2 > 0 then
        return math.min(t1, t2)
    elseif t1 > 0 then
        return t1
    elseif t2 > 0 then
        return t2
    else
        return nil
    end
end

local function estimateRocketImpact(launchPos, landPos, pitchDeg, yawDeg)
    local dir = getLaunchVector(pitchDeg, yawDeg)
    local vy = rocketSpeed * dir.y
    local dy = landPos.y - launchPos.y

    -- Kinematic: dy = vy * t - 0.5 * g * t^2
    local a = -0.5 * 10
    local b = vy
    local c = -dy

    local t = solveQuadratic(a, b, c)
    if not t then return nil end

    return {
        x = launchPos.x + rocketSpeed * dir.x * t,
        y = landPos.y,
        z = launchPos.z + rocketSpeed * dir.z * t
    }
end

local function aimRocket()
    while true do
        if controls and controls.weaponChoosen == "rocket" then
            camera.forcePitchYaw(20, 180)
            requiredRelativePitch,requiredRelativeYaw = -20,180
            if currentTime - 0.2 > lastRenderTime then
                if hitPos and hitPos.x then
                    print(math.deg(-getPitch()))
                    estimateLandPos = estimateRocketImpact(shipPos, hitPos, math.deg(-getPitch())-20, math.deg(getYaw()))
                    print(textutils.serialize(estimateLandPos))
                    if estimateLandPos and estimateLandPos.x then
                        camera.outlineToUser(
                            estimateLandPos.x, estimateLandPos.y-1, estimateLandPos.z,
                            "UP",  -- Default direction
                            0xFF0000,  -- Red
                            "designation"  -- Slot ID
                        )
                    end
                end
                lastRenderTime = currentTime
            end

        end
        sleep()
    end
end

local function setGunAngle()
    while true do
        if requiredRelativePitch and requiredRelativeYaw then
            cannon.setPitch(requiredRelativePitch)
            cannon.setYaw(requiredRelativeYaw)
        end
        sleep()
    end
end

local HOLD_THRESH = 1

-- ░░  VECTOR HELPERS  ░░
local function angleBetween(a,b)               -- deg
    local function vecLen(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end
    local function vecDot(a,b) return a.x*b.x + a.y*b.y + a.z*b.z end
    local function vecNorm(v)  local l=vecLen(v); return {x=v.x/l,y=v.y/l,z=v.z/l} end
    return math.deg(math.acos(math.min(1, math.max(-1, vecDot(vecNorm(a),vecNorm(b))))))
end

-- ░░  WORLD → PITCH/YAW  (ship local) ░░
local function vectorToPitchYaw(v)
  local pitch = math.deg(math.asin(v.y))
  local yaw   = -math.deg(math.atan2(-v.x, -v.z))
  return pitch, yaw
end
local lastLocalFwd = camera.getLocViewForward()  -- initial reference
local lockedWorldFwd = camera.getAbsViewForward()
local lockPos = {x=0,y=0,z=0}
local lockedCoordinate
-- ░░  Lock camera  ░░
local function lockCoordinate()
    while true do
        if controls and controls.lockCoordinate then
            local dx = lockPos.x - cameraPos.x
            local dy = lockPos.y - cameraPos.y
            local dz = lockPos.z - cameraPos.z

            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            local horizontalDistance = math.sqrt(dx * dx + dz * dz)
            local pitch = math.deg(math.atan2(dy, horizontalDistance))

            local yaw = math.deg(math.atan2(-dx, dz))
            yaw = (yaw + 180) % 360

            local localYaw, localPitch = findRelativeAngle(yaw,pitch)

            camera.forcePitchYaw(-localPitch, localYaw)

            lockedCoordinate = {
                type = "waypoint",
                pos = lockPos,
                id = 0
            }
            --lastLocalFwd = curlocalFwd
        else
            lockPos = hitPos
            lockedCoordinate = nil
        end
        sleep(0.001)
    end
end

local function lockShip()
    while true do
        if controls and controls.lockShip and lockedTarget and lockedTarget.pos then
            --print("locking ship")
            local dx = lockedTarget.pos.x - cameraPos.x
            local dy = lockedTarget.pos.y - cameraPos.y
            local dz = lockedTarget.pos.z - cameraPos.z

            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            local horizontalDistance = math.sqrt(dx * dx + dz * dz)
            local pitch = math.deg(math.atan2(dy, horizontalDistance))

            local yaw = math.deg(math.atan2(-dx, dz))
            yaw = (yaw + 180) % 360

            local localYaw, localPitch = findRelativeAngle(yaw,pitch)

            camera.forcePitchYaw(-localPitch, localYaw)
        end
        sleep()
    end
end

local function hslToRGB(h, s, l)
    local function hue2rgb(p, q, t)
        if t < 0   then t = t + 1 end
        if t > 1   then t = t - 1 end
        if t < 1/6 then return p + (q - p) * 6 * t end
        if t < 1/2 then return q end
        if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
        return p
    end

    local r, g, b
    if s == 0 then
        r, g, b = l, l, l -- achromatic
    else
        local q = l < 0.5 and l * (1 + s) or l + s - l * s
        local p = 2 * l - q
        r = hue2rgb(p, q, h + 1/3)
        g = hue2rgb(p, q, h)
        b = hue2rgb(p, q, h - 1/3)
    end
    return bit32.lshift(math.floor(r * 255), 16) +
           bit32.lshift(math.floor(g * 255), 8) +
           math.floor(b * 255)
end

local function clusterShips(ships)
    local clusters = {}

    for _, ship in ipairs(ships) do
        local added = false
        for _, cluster in ipairs(clusters) do
            for _, other in ipairs(cluster.members) do
                if distance(ship.pos, other.pos) < 20 then
                    table.insert(cluster.members, ship)
                    cluster.massSum = cluster.massSum + (ship.mass or 0)
                    if (ship.mass or 0) > (cluster.main.mass or 0) then
                        cluster.main = ship
                    end
                    added = true
                    break
                end
            end
            if added then break end
        end

        if not added then
            table.insert(clusters, {
                members = { ship },
                main = ship,
                massSum = ship.mass or 0
            })
        end
    end
    --calculate color
    local result = {}
    local MIN_MASS, MAX_MASS = 10000, 200000
    for _, cluster in ipairs(clusters) do
        local m = math.max(MIN_MASS, math.min(cluster.massSum, MAX_MASS))
        local lightness = 0.85 - ((m - MIN_MASS) / (MAX_MASS - MIN_MASS)) * 0.5  -- 从 0.85 到 0.35
        local color = hslToRGB(0.13, 1.0, lightness)  -- hue 0.13 ≈ 黄橙色

        table.insert(result, {
            pos = cluster.main.pos,
            id = cluster.main.id,
            mass = cluster.massSum,
            velocity = cluster.main.velocity,
            type = "ship",
            color = color
        })
    end

    return result
end

local function renderShips()
    while true do
        lockedTarget = nil
        local validShips = {}

        -- 筛选质量与距离合格的目标
        for _, ship in ipairs(allShips or {}) do
            if ship.mass and ship.mass >= 10000 and distance(ship.pos, cameraPos) >= 20 then
                table.insert(validShips, ship)
            end
        end

        local shipsToRender = clusterShips(validShips)
        local camForward = camera.getAbsViewForward()

        local minAngle = 10
        local bestTarget = nil

        -- 第一遍扫描，寻找最小角度目标
        for _, ship in ipairs(shipsToRender) do
            local dirToShip = {
                x = ship.pos.x - cameraPos.x,
                y = ship.pos.y - cameraPos.y,
                z = ship.pos.z - cameraPos.z,
            }

            local angle = angleBetween(dirToShip, camForward)

            if angle < minAngle then
                minAngle = angle
                bestTarget = ship
            end
        end

        -- 第二遍绘制所有目标，并标注最佳目标
        for _, ship in ipairs(shipsToRender) do
            local outlineColor = ship.color

            if bestTarget and ship.id == bestTarget.id then
                outlineColor = controls and controls.lockShip and 0x882200 or 0xCC5500
                lockedTarget = ship
            end

            camera.outlineToUser(
                ship.pos.x, ship.pos.y - 2, ship.pos.z,
                "UP",
                outlineColor,
                tostring(ship.id)
            )
        end

        sleep(0.5)
    end
end

local function missileListBuilding()
    while true do
        if immediateMissileInfo and immediateMissileInfo.id and immediateMissileInfo.type then
            local foundMissile = false

            -- Update the existing missile state instead of adding duplicates
            for _, missileInfo in ipairs(AIMInfoList) do
                if missileInfo.id == immediateMissileInfo.id then
                    missileInfo.launchState = immediateMissileInfo.launchState
                    foundMissile = true
                    break
                end
            end
            for _, missileInfo in ipairs(GBUInfoList) do
                if missileInfo.id == immediateMissileInfo.id then
                    missileInfo.launchState = immediateMissileInfo.launchState
                    foundMissile = true
                    break
                end
            end
            for _, missileInfo in ipairs(thunderBoltInfoList) do
                if missileInfo.id == immediateMissileInfo.id then
                    missileInfo.launchState = immediateMissileInfo.launchState
                    foundMissile = true
                    break
                end
            end
            for _, missileInfo in ipairs(AGMInfoList) do
                if missileInfo.id == immediateMissileInfo.id then
                    missileInfo.launchState = immediateMissileInfo.launchState
                    foundMissile = true
                    break
                end
            end

            -- If it's a new missile, add it to the list
            if not foundMissile then
                if immediateMissileInfo.type == "AIM-220" then
                    table.insert(AIMInfoList, immediateMissileInfo)
                elseif immediateMissileInfo.type == "GBU-42" then
                    table.insert(GBUInfoList, immediateMissileInfo)
                elseif immediateMissileInfo.type == "thunderBolt" then
                    table.insert(thunderBoltInfoList, immediateMissileInfo)
                elseif immediateMissileInfo.type == "AGM-134" then
                    table.insert(AGMInfoList, immediateMissileInfo)
                end
            end
        end

        -- Remove missiles that have launched
        for i = #AIMInfoList, 1, -1 do
            if AIMInfoList[i].launchState == true then
                table.remove(AIMInfoList, i)
            end
        end
        for i = #GBUInfoList, 1, -1 do
            if GBUInfoList[i].launchState == true then
                table.remove(GBUInfoList, i)
            end
        end
        for i = #thunderBoltInfoList, 1, -1 do
            if thunderBoltInfoList[i].launchState == true then
                table.remove(thunderBoltInfoList, i)
            end
        end
        for i = #AGMInfoList, 1, -1 do
            if AGMInfoList[i].launchState == true then
                table.remove(AGMInfoList, i)
            end
        end

        -- Count unlaunched missiles
        AIMCount, GBUCount, thunderboltCount = 0, 0, 0
        for _, missileInfo in ipairs(AIMInfoList) do
            if not missileInfo.launchState then
                AIMCount = AIMCount + 1
            end
        end
        for _, missileInfo in ipairs(GBUInfoList) do
            if not missileInfo.launchState then
                GBUCount = GBUCount + 1
            end
        end
        for _, missileInfo in ipairs(thunderBoltInfoList) do
            if not missileInfo.launchState then
                thunderboltCount = thunderboltCount + 1
            end
        end
        for _, missileInfo in ipairs(AGMInfoList) do
            if not missileInfo.launchState then
                AGMCount = AGMCount + 1
            end
        end
        sleep()
    end
end

local function launchMissile(targetType, targetId, targetPos, missileType)
    local currentMissile = nil

    -- Function to find and remove the first unlaunched missile from a list
    local function findUnlaunchedMissile(missileList)
        for i = #missileList, 1, -1 do  -- Iterate in reverse to avoid index shifting issues
            local missile = missileList[i]
            if missile.launchState == false then
                missile.launchState = true  -- Mark missile as launched
                table.insert(LaunchedMissiles, missile)  -- Move to launched list
                return table.remove(missileList, i)  -- Remove from available list and return it
            end
        end
        return nil
    end
    

    -- Get the first unlaunched missile of the specified type
    if missileType == "AIM-220" then
        currentMissile = findUnlaunchedMissile(AIMInfoList)
    elseif missileType == "GBU-42" then
        currentMissile = findUnlaunchedMissile(GBUInfoList)
    elseif missileType == "thunderBolt" then
        currentMissile = findUnlaunchedMissile(thunderBoltInfoList)
    elseif missileType == "AGM-134" then
        currentMissile = findUnlaunchedMissile(AGMInfoList)
    end

    -- If no unlaunched missile is found, exit function
    if not currentMissile then
        print("No available unlaunched missile of type:", missileType)
        return
    end

    local currentMissileId = currentMissile.id
    print("Launching missile " .. currentMissileId)

    -- Assign the missile as launched and set target info
    if targetType == "ship" then
        missileControls.fireMissile[currentMissileId] = {launch = true, type = targetType, id = targetId}
    else
        missileControls.fireMissile[currentMissileId] = {launch = true, type = targetType, pos = targetPos}
    end
end

local function missileHandler()
    while true do
        --print(textutils.serialize(AGMInfoList))
        if controls and controls.fire then
            if controls.weaponChoosen == "AIM-220" or controls.weaponChoosen == "GBU-42" or controls.weaponChoosen == "thunderBolt" or controls.weaponChoosen == "AGM-134" then
                print("Firing missile")
                if controls.lockCoordinate then
                    if lockedCoordinate and lockedCoordinate.pos and missileCoolDown == 0 then
                        launchMissile("waypoint",lockedCoordinate.id,lockedCoordinate.pos,controls.weaponChoosen)
                        missileCoolDown = 20
                        modem.transmit(missileControlChannel,missileControlChannel,missileControls)
                    end
                elseif controls.lockShip then
                    if lockedTarget and lockedTarget.id and missileCoolDown == 0 then
                        print("Launching at ship")
                        launchMissile("ship",lockedTarget.id,lockedTarget.pos,controls.weaponChoosen) --target is a ship
                        missileCoolDown = 20
                        modem.transmit(missileControlChannel,missileControlChannel,missileControls)
                    end
                end
            end
        end
        missileCoolDown = math.max(missileCoolDown - 1,0)
        sleep()
    end
end

parallel.waitForAny(
    modemMessage,
    updateInfo,
    aimGun,
    aimRocket,
    setGunAngle,
    lockCoordinate,
    lockShip,
    renderShips,
    missileHandler,
    missileListBuilding
)