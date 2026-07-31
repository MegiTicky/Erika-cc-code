local radar = peripheral.find("sp_radar")
local modem = peripheral.wrap("right")
local holo = peripheral.find("hologram")

local cannonSourceChannel = 701
local controlChannel = 500

local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

local screenWidth, screenHeight, fov = 3440, 1440, 70
local userID = "MegiRicky"

local pInfo

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end

function filterPlayerInfo(playerList, userID)
    for _, player in ipairs(playerList) do
        if player.nickname == userID then
            return player
        end
    end
end

function clusterShips(ships)
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

function getTargetType(object)
    if not object.size or not object.scale then return "default" end

    -- Scale the dimensions
    local sx = (object.size.x or 0) --/ object.scale.x
    local sy = (object.size.y or 0) --/ object.scale.y
    local sz = (object.size.z or 0) --/ object.scale.z

    -- Volume calculation
    if object.volume == 0 then return "default" end  -- Avoid division by zero

    -- Density calculation
    local density = object.mass / object.volume
    object._calculatedDensity = density  -- Optional: store for debugging or later use

    -- Icon classification based on size and mass (can now be extended to use density)
    local sizeSum = sx + sy + sz
    if object.scale.x < 0.6 and object.mass > 5000 and object.mass < 20000 and object.numShips < 2 then
        return "missile"
    elseif sizeSum < 50 and object.mass < 200000 then
        if density > 100 then
            return "tank"
        elseif density > 50 then
            return "default"
        else
            return "plane"
        end
    elseif sizeSum < 50 and object.mass >= 200000 then
        return "tank"
    elseif sizeSum > 100 and object.mass > 500000 then
        return "ship"
    end

    return "default"
end
colorType = {
    tank = 0xfff70088,
    plane = 0xFFFF00ff,
    missile = 0xFFFF00ff,
    ship = 0xffc300ff,
    default = 0x00FF0088
}

-- Normalize a vector
function normalize(v)
    local length = math.sqrt(v[1]^2 + v[2]^2 + v[3]^2)
    return {v[1] / length, v[2] / length, v[3] / length}
end

function clampAngle(angle)
    -- Normalize angle to [-180, 180]
    angle = angle % 360  -- Normalize to [0, 360]
    if angle > 180 then
        angle = angle - 360  -- Convert to [-180, 180]
    end
    return angle
end


-- Create a quaternion from pitch and yaw
function quaternionFromVector(v)
    -- Normalize the vector to get the direction
    v = normalize(v)
    
    -- Calculate yaw and pitch
    local yaw = math.deg(math.atan2(v[3], v[1])) - 90  -- -90 to correct the direction
    local pitch = math.deg(math.asin(v[2]))
    
    -- Convert yaw and pitch to radians
    yaw = math.rad(yaw)
    pitch = math.rad(pitch)
    
    -- Calculate quaternion components for yaw and pitch
    local qYaw = {math.cos(yaw / 2), 0, math.sin(yaw / 2), 0}  -- No roll, so the x and y components are 0
    local qPitch = {math.cos(pitch / 2), math.sin(pitch / 2), 0, 0}
    
    -- Multiply the quaternions (qYaw * qPitch)
    local q = {
        w = qYaw[1] * qPitch[1] - qYaw[2] * qPitch[2] - qYaw[3] * qPitch[3] - qYaw[4] * qPitch[4],  -- w
        x = qYaw[1] * qPitch[2] + qYaw[2] * qPitch[1] + qYaw[3] * qPitch[4] - qYaw[4] * qPitch[3],  -- x
        y = qYaw[1] * qPitch[3] - qYaw[2] * qPitch[4] + qYaw[3] * qPitch[1] + qYaw[4] * qPitch[2],  -- y
        z = qYaw[1] * qPitch[4] + qYaw[2] * qPitch[3] - qYaw[3] * qPitch[2] + qYaw[4] * qPitch[1]   -- z
    }

    return q
end

local function findRelativeAngle(targetYaw,targetPitch,quaternion)
    rot = quaternion
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

-- Function to project 3D coordinates to 2D screen coordinates
local function projectToScreen(point, player)
    --print(textutils.serialize(player.look_angle))
    lookQuaternion = quaternionFromVector(player.look_angle)
    yaw = math.atan2(2 * (lookQuaternion.y * lookQuaternion.z + lookQuaternion.w * lookQuaternion.x), lookQuaternion.w * lookQuaternion.w + lookQuaternion.x * lookQuaternion.x - lookQuaternion.y * lookQuaternion.y - lookQuaternion.z * lookQuaternion.z)
    print(math.deg(yaw))
    
    local dx = point.x - player.pos[1]
    local dy = point.y - player.pos[2]
    local dz = point.z - player.pos[3]

    -- yaw geometric
    local globalYaw = math.deg(math.atan2(-dx, dz))
    --geometric pitch
    local horizontalDistance = math.sqrt(dx * dx + dz * dz)
    local globalPitch = math.deg(math.atan2(dy, horizontalDistance))

    relativeYaw,relativePitch = findRelativeAngle(globalYaw, globalPitch, lookQuaternion)
    relativeYaw = clampAngle(relativeYaw)
    print(relativeYaw, relativePitch)

    return --projectedX, projectedY
end

-- Function to project 3D coordinates to 2D screen coordinates
local function projectToScreen(x, y, z, userPos, lookVector)
    local dx = x - userPos[1]
    local dy = -(y - userPos[2])
    local dz = z - userPos[3]

    local lx, ly, lz = lookVector[1], lookVector[2], lookVector[3]
    local playerYaw = math.deg(math.atan2(lz, lx))
    local playerPitch = math.deg(math.asin(-ly))
    playerYaw = playerYaw + 90
    if playerYaw < 0 then
        playerYaw = playerYaw + 360
    end

    -- Calculate yaw difference
    local targetYaw = math.deg(math.atan2(dz, dx)) + 90
    if targetYaw < 0 then
        targetYaw = targetYaw + 360
    end
    
    local yawDiff = targetYaw - playerYaw
    if yawDiff > 180 then
        yawDiff = yawDiff - 360
    elseif yawDiff < -180 then
        yawDiff = yawDiff + 360
    end

    if math.abs(yawDiff) > 90 then
        return nil, nil
    end

    -- Calculate pitch difference
    local distXY = math.sqrt(dx * dx + dz * dz)
    local targetPitch = math.deg(math.atan2(dy, distXY))
    local pitchDiff = targetPitch - playerPitch

    local screenDepth = screenWidth / 2 * math.tan(math.rad(fov / 1.125 / 2))
    local verticalScreenDepth = screenHeight * math.tan(math.rad(fov / 2))

    local projectedX, projectedY

    if yawDiff > 0 then
        projectedX = screenWidth / 2 + screenDepth * math.tan(math.rad(math.abs(yawDiff)))
    else
        projectedX = screenWidth / 2 - screenDepth * math.tan(math.rad(math.abs(yawDiff)))
    end

    if pitchDiff > 0 then
        projectedY = screenHeight / 2 + screenHeight * math.tan(math.rad(fov / 0.95 / 2)) * math.tan(math.rad(math.abs(pitchDiff)))
    else
        projectedY = screenHeight / 2 - screenHeight * math.tan(math.rad(fov / 1.05 / 2)) * math.tan(math.rad(math.abs(pitchDiff)))
    end

    projectedX = math.floor(projectedX / magicNumber)
    projectedY = math.floor(projectedY / magicNumber) + 20

    return projectedX, projectedY
end


function addShipsToRenderQueue(clusterList, pInfo)
    for _, object in ipairs(clusterList) do
        local distance = math.floor(math.sqrt((object.pos.x - pInfo.pos[1]) ^ 2 + (object.pos.y - pInfo.pos[2]) ^ 2 + (object.pos.z - pInfo.pos[3]) ^ 2))
        local targetType = getTargetType(object)
        local targetColor = colorType[targetType]

        if distance > 20 then
            local screenX, screenY = projectToScreen(object.pos, pInfo)

            if screenX and screenY then
                table.insert(elements, {
                    id = object.id,
                    pos = object.pos,
                    screenX = screenX,
                    screenY = screenY,
                    frameSize = 20,
                    color = color,
                    distance = distance,
                    mass = object.mass,
                    speed = speed,
                    velocity = object.velocity,
                    renderInfo = true,
                    renderBox = isWithinRenderDistance(screenX, screenY, screenWidth / 2, screenHeight / 2, 4000 / GUIscale, 4800 / GUIscale, 3200 / GUIscale)
                })
            end
        end
    end
end

local function main()
    while true do
        holo.Clear()

        local playerList = radar.scanForPlayers(1000)
        pInfo = filterPlayerInfo(playerList, userID)

        local rawShipsList = radar.scanForShips(10000)
        clusterList = clusterShips(rawShipsList)

        elements = {}
        
        if pInfo and pInfo.pos and pInfo.pos[1] then
            addShipsToRenderQueue(clusterList, pInfo)
        end

        --renderElements(filteredElements, cannonHitPos, pInfo, lockedTarget)
        holo.Flush()
        sleep() -- Adjust the sleep time as needed to balance performance and responsiveness
    end
end

main()