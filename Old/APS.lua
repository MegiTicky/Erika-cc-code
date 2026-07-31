local radar = peripheral.find("sp_radar")
local cannon = peripheral.find("cbcmf_compact_cannon_mount")
if not(cannon) then cannon = peripheral.find("cbc_cannon_mount") end

local projectileSpeed = 120
local g = 0.05
local vm
local shipPos
local pInfo
local scanInterval = 0.08
local locked = false

local friendlyIDs
local friendlyIDFile = "friendly_ids.txt"

print("Do you want to enable auto fire, 'yes' or 'no', default: yes")
local auto = io.read()

if auto == "yes" then
    auto = true
elseif auto == "no" then
    auto = false
else
    auto = true
end

local function readFriendlyIDs(filename)
    if not fs.exists(filename) then
        print("Friendly IDs file '" .. filename .. "' does not exist. Creating it.")
        local file = fs.open(filename, "w")
        print("Input friendly IDs (player names) separated by commas:")
        local ids = io.read()
        file.write(ids)
        file.close()
    else
        print("Do you want to edit the config? (yes/no),press enter to skip")
        local editChoice = io.read()
        if editChoice == "" then
            editChoice = "no"
        end
        if editChoice:lower() == "yes" then
            if fs.exists(filename) then
                fs.delete(filename)
                print("Friendly IDs file '" .. filename .. "' does not exist. Creating it.")
                local file = fs.open(filename, "w")
                print("Input friendly IDs (player names) separated by commas:")
                local ids = io.read()
                file.write(ids)
                file.close()
            end
        end

        
    end

    
    local file = fs.open(filename, "r")
    local friendlyIDs = {}
    if file then
        local line = file.readLine()
        while line do
            print("Line read: " .. line)  -- Debug print for the line

            -- Split the line by commas and insert each name into the friendlyIDs table
            for name in string.gmatch(line, '([^,]+)') do
                print("Friendly ID (Name): " .. name)  -- Debug print for each name
                table.insert(friendlyIDs, name)  -- Store the player name
            end
            line = file.readLine()  -- Read the next line
        end
        file.close()
    end
    return friendlyIDs
end

-- Function to check if a player ID is friendly
local function isFriendly(playerID)
    for _, friendlyID in ipairs(friendlyIDs) do
        if playerID == friendlyID then
            return true
        end
    end
    return false
end

-- Read friendly IDs from the file
friendlyIDs = readFriendlyIDs(friendlyIDFile)
print("Friendly IDs: " .. textutils.serialize(friendlyIDs)) -- Debug print

print("Press enter to assemble cannon")
io.read()
cannon.assemble()


local function calculateVelocity(pos1, pos2, dt)
    local vx = (pos2[1] - pos1[1]) / dt
    local vy = (pos2[2] - pos1[2]) / dt
    local vz = (pos2[3] - pos1[3]) / dt
    return {x=vx, y=0, z=vz}
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
--pitch = math.deg(math.asin(ship.getTransformationMatrix()[2][3]))
-- Get the yaw of the ship
local function getYaw()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return math.atan2(-normalizedMatrix[3][1], -normalizedMatrix[3][3]) + 180 -- Extract yaw from the matrix
end

-- Get the roll of the ship
local function getRoll()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return math.atan2(normalizedMatrix[2][1], normalizedMatrix[2][2]) -- Extract roll from the matrix
end

local function normalizeQuaternion(q)
    -- Calculate the magnitude of the quaternion
    local magnitude = math.sqrt(q.x^2 + q.y^2 + q.z^2 + q.w^2)

    -- Normalize each component of the quaternion by dividing it by the magnitude
    return {
        x = q.x / magnitude,
        y = q.y / magnitude,
        z = q.z / magnitude,
        w = q.w / magnitude
    }
end

local function findRelativeAngle(targetYaw,targetPitch)
    local rot = ship.getQuaternion()
    rot = normalizeQuaternion(rot)
    
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

    for pitch = 0, 70, 0.01 do -- Iterate over pitch angles
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
    if targetDistance <= 830 then
        return bestLowPitch or bestLowPitch
    else
        return bestHighPitch or bestLowPitch
    end
end

local function aimCannon(targetPos, targetVel, sourceX, sourceY, sourceZ)
    if sourceX and sourceY and sourceZ then
        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local estimateTime = distance / (projectileSpeed)  -- assuming velocity units and time units need adjustment
        local estimateX = targetPos.x + targetVel.x * 0.5
        local estimateY = targetPos.y + targetVel.y * 0.5
        local estimateZ = targetPos.z + targetVel.z * 0.5
 
        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        local shipRoll = math.deg(getRoll())
        local shipYaw = math.deg(getYaw())
        if shipYaw < 0 then shipYaw = shipYaw + 360 end
        local shipPitch = math.deg(getPitch())

        local requiredRelativeYaw = yaw - shipYaw
        if requiredRelativeYaw > 180 then
            requiredRelativeYaw = requiredRelativeYaw - 360
        elseif requiredRelativeYaw < -180 then
            requiredRelativeYaw = requiredRelativeYaw + 360
        end

        local requiredRelativeYaw,requiredRelativePitch = findRelativeAngle(yaw,pitch)
        if requiredRelativePitch then
            cannon.setPitch(requiredRelativePitch)
        end
        if requiredRelativeYaw then
            cannon.setYaw(requiredRelativeYaw)
        end
    end
end

local function main()
    while true do
        shipPos = ship.getWorldspacePosition()

        -- First scan for players and ships
        local targetScan1 = radar.scanForPlayers(100)
        local shipScan1 = radar.scanForShips(1000) -- Scan for ships (e.g., missiles) within 1000 units

        -- Variables to hold the closest target data
        local closestTarget = nil
        local closestDistance = math.huge
        local targetPos1 = nil
        local targetInfo = nil
        local highestSpeed = 0

        -- Loop through each player detected in the first scan
        for _, player in pairs(targetScan1) do
            if player and player.pos then
                local dx = player.pos[1] - shipPos.x
                local dy = player.pos[2] - shipPos.y
                local dz = player.pos[3] - shipPos.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                -- If this player is closer than the current closest, update the closest target
                if not isFriendly(player.nickname) and distance < closestDistance then
                    closestDistance = distance
                    targetPos1 = player.pos
                    targetInfo = {
                        id = player.id,
                        nickname = player.nickname,
                        pos = targetPos1,
                        distance = distance,
                        type = "player"
                    }
                end
            end
        end

        -- Loop through each ship detected in the first ship scan
        for _, ship in pairs(shipScan1) do
            if ship and ship.pos then
                local dx = ship.pos.x - shipPos.x
                local dy = ship.pos.y - shipPos.y
                local dz = ship.pos.z - shipPos.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                -- Calculate speed of the ship
                local shipSpeed = math.sqrt(ship.velocity.x ^ 2, ship.velocity.y ^ 2, ship.velocity.z ^ 2)

                -- If the ship is moving fast (e.g., a missile), prioritize it
                if shipSpeed > 5 and not isFriendly(ship.id) and distance > 10 then
                    highestSpeed = shipSpeed
                    targetPos1 = ship.pos
                    targetInfo = {
                        id = ship.id,
                        pos = targetPos1,
                        distance = distance,
                        velocity = ship.velocity,
                        speed = shipSpeed,
                        type = "ship"
                    }
                end
            end
        end

        if targetInfo and targetPos1 then
            -- Perform second scan for both players and ships
            if targetInfo.type == "player" then
                targetInfo.velocity = {x=0, y=0, z=0}
            elseif targetInfo.type == "ship" then
                local shipScan2 = radar.scanForShips(1000)
                local shipPos2 = nil
                local shipVelocity2 = nil

                if targetInfo.velocity and targetPos1 then
                    -- Aim the cannon at the estimated position
                    aimCannon(targetPos1, targetInfo.velocity, shipPos.x, shipPos.y, shipPos.z)
                    if targetInfo.distance < 25 then
                        redstone.setOutput("back",true)
                        sleep(0.1)
                        redstone.setOutput("back",false)
                    end
                end
            end
        end
        os.sleep()
    end
end

parallel.waitForAll(
    main,
    main,
    main,
    main,
    main,
    main,
    main,
    main
)