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

local function readFriendlyIDs(filename)
    if not fs.exists(filename) then
        print("Friendly IDs file '" .. filename .. "' does not exist. Creating it.")
        local file = fs.open(filename, "w")
        print("Input friendly IDs separated by commas:")
        local ids = io.read()
        file.write(ids)
        file.close()
    end
    
    local file = fs.open(filename, "r")
    local friendlyIDs = {}
    if file then
        local line = file.readLine()
        while line do
            for id in string.gmatch(line, "%d+") do
                table.insert(friendlyIDs, tonumber(id))
            end
            line = file.readLine()
        end
        file.close()
    end
    return friendlyIDs
end

local screenWidth, screenHeight, fov, GUIscale
local sourceX, sourceY, sourceZ = 0,0,0
local source = {}
local userID
local friendlyIDs
local friendlyIDFile = "friendly_ids.txt"

local projectionDistance = 100
local currentPitch, currentYaw = 0,0
local lockedTarget = nil
local elements = {}
local pInfo = {}
local cannonHitPos = {}
local pitchAdjustments = "1"
local lastYawUpdateTime = 0
local lastPitchUpdateTime = 0
local updateInterval = 0.05
local projectileSpeed = 240

local maxRayDistance = 500

local yawErrorSum = 0
local lastYawError = 0
local pitchErrorSum = 0
local lastPitchError = 0
local lastTime = os.clock()

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
local AIMInfoList,GBUInfoList,thunderBoltInfoList = {},{},{}
local AIMCount,GBUCount,thunderboltCount = 0,0,0
local weaponChoosen = "AIM-220"
local missileCoolDown = 20

local waypoints = {}

widthMagic = 1.125
screenWidth = 2560
screenHeight = 2560
fov = 70
GUIscale = 4

userID = askUser("Input the player name", "MegiRicky")

friendlyIDs = readFriendlyIDs(friendlyIDFile)

local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

local cannonHitPosChannel = tonumber(askUser("Input the cannon data channel number(For guiding cannon, NGDWEVROnboard required)", "700"))
local missileControlChannel = tonumber(askUser("Input the missile launch channel","1400"))
local controlChannel = tonumber(askUser("Input the control channel", "1420"))
local muzzleVelocity = tonumber(askUser("Input the projectile speed", "180"))
local cd = tonumber(askUser("Input the drag", "0.999"))
pitchCompensation = 0

local missileInfoChannel = missileControlChannel + 10
local waypointChannel = controlChannel + 1

if modem then
    modem.open(cannonHitPosChannel)
    modem.open(controlChannel)
    modem.open(waypointChannel)
    modem.open(missileControlChannel)
    modem.open(missileInfoChannel)
end

local pos = ship.getWorldspacePosition()
sourceX, sourceY, sourceZ = pos.x, pos.y, pos.z

print("Source X: " .. sourceX)
print("Source Y: " .. sourceY)
print("Source Z: " .. sourceZ)
print("Resolution: " .. screenWidth .. ", " .. screenHeight)

holo.Resize(screenWidth/4,screenHeight/4)
local screenSizeScale = 4
holo.SetScale(0,0)


local function isFriendly(id)
    for _, friendlyID in ipairs(friendlyIDs) do
        if id == friendlyID then
            return true
        end
    end
    return false
end

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
        projectedX = screenWidth / 2 + screenDepth * math.tan(math.rad(math.abs(yawDiff))) * 2.35
    else
        projectedX = screenWidth / 2 - screenDepth * math.tan(math.rad(math.abs(yawDiff))) * 2.35
    end

    if pitchDiff > 0 then
        projectedY = screenHeight / 2 + screenHeight * math.tan(math.rad(fov / 2)) * math.tan(math.rad(math.abs(pitchDiff))) * 1
    else
        projectedY = screenHeight / 2 - screenHeight * math.tan(math.rad(fov / 2)) * math.tan(math.rad(math.abs(pitchDiff))) * 1.05
    end

    projectedX = math.floor(projectedX)
    projectedY = math.floor(projectedY) + 20

    return projectedX, projectedY
end

local function mouseAim(userPos, lookVector)
    lookTarget = {}

    local lx, ly, lz = lookVector[1], lookVector[2], lookVector[3]
    local playerYaw = math.deg(math.atan2(lz, lx))
    local playerPitch = math.deg(math.asin(-ly))
    playerYaw = playerYaw + 90
    if playerYaw < 0 then
        playerYaw = playerYaw + 360
    end

    local yawRad = math.rad(playerYaw)
    local pitchRad = math.rad(playerPitch)

    local dx = projectionDistance * math.cos(pitchRad) * math.sin(yawRad)
    local dz = -projectionDistance * math.cos(pitchRad) * math.cos(yawRad)
    local dy = -projectionDistance * math.sin(pitchRad)

    local targetX = userPos[1] + dx
    local targetY = userPos[2] + dy
    local targetZ = userPos[3] + dz
    lookTarget = { x = targetX, y = targetY, z = targetZ }
    return lookTarget
end

local function isWithinRenderDistance(projectedX, projectedY, centerX, centerY, maxdx, maxdy, maxd)
    local dx = projectedX - centerX
    local dy = projectedY - centerY

    if dx < maxdx then
        if dy < maxdy then
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance <= maxd then
                return true
            else
                return false
            end
        else
            return false
        end
    else
        return false
    end
end

-- Function to check for overlap and adjust positions
local function filterElements(elements)
    table.sort(elements, function(a, b) return a.mass > b.mass end) -- Sort by mass
    local filteredElements = {}

    for i, element in ipairs(elements) do
        local overlap = false
        for _, filteredElement in ipairs(filteredElements) do
            local dx = math.abs(element.screenX - filteredElement.screenX)
            local dy = math.abs(element.screenY - filteredElement.screenY)
            if dx < 800 / GUIscale and dy < 800 / GUIscale then
                overlap = true
                element.renderInfo = false
                break
            end
        end

        table.insert(filteredElements, element)
    end

    return filteredElements
end

local function drawEdgeIndicator(holo, screenX, screenY, screenWidth, screenHeight, radius)
    local centerX = screenWidth / 2
    local centerY = screenHeight / 2

    -- Calculate angle and differences
    local dx = screenX - centerX
    local dy = screenY - centerY
    local distance = math.sqrt(dx * dx + dy * dy)
    local yawDiff = math.deg(math.atan2(dx, distance)) -- Yaw difference
    local pitchDiff = math.deg(math.atan2(dy, distance)) -- Pitch difference

    -- Apply compensation for sensitivity differences
    if yawDiff > 0 then
        dy = dy * 2 -- Adjust sensitivity
        dx = dx * 2
    else
        dy = dy * 0.5 -- Adjust sensitivity
        dx = dx * 0.5
    end

    if pitchDiff > 0 then
        dy = dy * 0.5 -- Adjust sensitivity
        dx = dx * 0.5
    else
        dy = dy * 2 -- Adjust sensitivity
        dx = dx * 2
    end

    -- Normalize direction vector to get unit vector
    local normFactor = math.sqrt(dx * dx + dy * dy)
    local unitX = dx / normFactor
    local unitY = dy / normFactor

    -- Calculate arrow position at the edge of the circle
    local edgeX = centerX + unitX * radius / 2
    local edgeY = centerY + unitY * radius / 2

    -- Draw the arrow on the hologram
    holo.DrawLine(
        math.floor(edgeX) - 1, math.floor(edgeY) - 1,
        math.floor(edgeX) + 1, math.floor(edgeY) + 1,
        0xFF00FFFF, 1 -- Cyan arrow for visibility
    )
    holo.DrawLine(
        math.floor(edgeX) + 1, math.floor(edgeY) - 1,
        math.floor(edgeX) - 1, math.floor(edgeY) + 1,
        0xFF00FFFF, 1 -- Cyan arrow for visibility
    )
end

-- Function to render elements
local function renderElements(elements, cannonHitPos, pInfo, lockedTarget)
    if not holo then return end  -- Ensure hologram peripheral is available

    -- Set the background to transparent
    holo.SetClearColor(0x00000000) -- Fully transparent (RGBA: 0,0,0,0)

    local circleRadius = math.min(screenWidth, screenHeight) / 4

    -- Iterate through detected objects and render them on the hologram
    for _, element in ipairs(elements) do
        local color = element.color
        local color = element.color
        if lockedTarget and element.id == lockedTarget.id then
            color = 0xFF0000FF -- Highlight locked target in red
            local screenWidth = screenWidth / screenSizeScale
            local centerX = screenWidth / 2
            local altitudeBoxX = centerX + screenWidth / 6
            -- Define the target information to display
            local targetInfo = {
                "TARGET LOCKED",
                "ID: " .. tostring(element.id),
                "Speed: " .. tostring(element.speed) .. " m/s",
                "Pos: (" ..
                    string.format("%.0f", element.pos.x) .. "," ..
                    string.format("%.0f", element.pos.y) .. "," ..
                    string.format("%.0f", element.pos.z) .. ")",
                "Mass: " .. tostring(element.mass) .. " kg",
                "Dist: " .. tostring(element.distance) .. " m"
            }

            local missileLaunchedAtTarget = false
            if type(controls.fireMissile) == "table" then
                for _, missileData in pairs(controls.fireMissile) do
                    if missileData.type == "ship" and missileData.id == lockedTarget.id then
                        missileLaunchedAtTarget = true
                        break
                    end
                end
            end

            -- Add missile launch status to the target info
            if missileLaunchedAtTarget then
                table.insert(targetInfo, "Missile Launched")
            end

            -- Display each line of the target information
            for i, line in ipairs(targetInfo) do
                holo.Text(altitudeBoxX, 20 + (i * 15), line, 0xFF000088, 1) -- White text
            end
        end
        
        -- Map screen coordinates to hologram coordinates
        local holoX = math.floor(element.screenX / 4) -- Scale down for better fit
        local holoY = math.floor(element.screenY / 4) -- Adjust scaling as needed

        -- Define the size of the box for the target
        local boxSize = 6  -- Increase the box size for better visibility

        -- Ensure the coordinates fit within the hologram display bounds
        if holoX >= 0 and holoX < screenWidth / 4 and holoY >= 0 and holoY < screenHeight / 4 and element.renderBox and lockedTarget and element.id == lockedTarget.id then
            -- Draw a bounding box around the detected object
            holo.DrawLine(holoX - boxSize, holoY - boxSize, holoX + boxSize, holoY - boxSize, color, 1) -- Top
            holo.DrawLine(holoX - boxSize, holoY + boxSize, holoX + boxSize, holoY + boxSize, color, 1) -- Bottom
            holo.DrawLine(holoX - boxSize, holoY - boxSize, holoX - boxSize, holoY + boxSize, color, 1) -- Left
            holo.DrawLine(holoX + boxSize, holoY - boxSize, holoX + boxSize, holoY + boxSize, color, 1) -- Right

            if element.renderInfo then
                -- Display object ID & distance on the hologram (smaller text)
                holo.Text(holoX + boxSize + 2, holoY - boxSize, tostring(element.id), color, 1)  -- Target ID
                holo.Text(holoX + boxSize + 2, holoY + boxSize, tostring(element.distance) .. "m", color, 1)  -- Distance
                holo.Text(holoX + boxSize + 2, holoY + boxSize * 3, tostring(element.speed) .. "m/s", color, 1) -- Speed
            end
        end
    end
end

local function lockHighestThreatTarget(elements, centerX, centerY, radius)
    local closestTarget = nil
    local closestDistance = math.huge  -- Initialize to a large number

    for _, element in ipairs(elements) do
        if element.id then
            local dx = element.screenX - centerX
            local dy = element.screenY - centerY
            local distance = math.sqrt(dx * dx + dy * dy)
            
            -- Check if the target is within the locking radius on screen
            if distance <= radius / GUIscale then
                -- If this target is closer to the center than the current closest target, update
                if distance < closestDistance then
                    closestTarget = element
                    closestDistance = distance
                end
            end
        end
    end

    return closestTarget
end

local function renderLockOnArea()
    -- Define the center and dimensions
    local lockOnRadius = 65 -- Radius of the lock-on circle
    local centerX = screenWidth/screenSizeScale / 2
    local centerY = screenHeight/screenSizeScale / 2
    local color = 0x00FF0088 -- Green color (RGBA format)

    -- Draw the circle for the lock-on area
    for angle = 0, 360, 5 do
        local rad = math.rad(angle)
        local x1 = math.floor(centerX + lockOnRadius * math.cos(rad))
        local y1 = math.floor(centerY + lockOnRadius * math.sin(rad))
        local x2 = math.floor(centerX + lockOnRadius * math.cos(math.rad(angle + 5)))
        local y2 = math.floor(centerY + lockOnRadius * math.sin(math.rad(angle + 5)))
        holo.DrawLine(x1, y1, x2, y2, color, 1)
    end
end

local colorMap = {
    [colors.white]     = 0xF0F0F0FF,  -- White
    [colors.orange]    = 0xF2B233FF,  -- Orange
    [colors.magenta]   = 0xE57FD8FF,  -- Magenta
    [colors.lightBlue] = 0x99B2F2FF,  -- Light Blue
    [colors.yellow]    = 0xDEDE6CFF,  -- Yellow
    [colors.lime]      = 0x7FCC19FF,  -- Lime
    [colors.pink]      = 0xF2B2CCFF,  -- Pink
    [colors.gray]      = 0x4C4C4CFF,  -- Gray
    [colors.lightGray] = 0x999999FF,  -- Light Gray
    [colors.cyan]      = 0x4C99B2FF,  -- Cyan
    [colors.purple]    = 0xB266E5FF,  -- Purple
    [colors.blue]      = 0x3366CCFF,  -- Blue
    [colors.brown]     = 0x7F664CFF,  -- Brown
    [colors.green]     = 0x57A64EFF,  -- Green
    [colors.red]       = 0xCC4C4CFF,  -- Red
    [colors.black]     = 0x111111FF   -- Black
}

-- Update the main function to remove target locking and aiming
local function main()
    while true do
        holo.Clear()
        local playerList = radar.scanForPlayers(1000)

        for _, player in ipairs(playerList) do
            local playerName = player.nickname
            local playerPosition = player.pos
            local lookAngle = player.look_angle

            if player.nickname == userID then
                pInfo = {
                    nickname = player.nickname,
                    pos = player.pos,
                    lookVector = lookAngle
                }
            end
        end
        
        if pInfo.nickname then
            local objectList = radar.scanForShips(10000)
            elements = {}
            for _, object in ipairs(objectList) do
                local objX, objY, objZ = object.pos.x, object.pos.y, object.pos.z
                local screenX, screenY = projectToScreen(objX, objY, objZ, pInfo.pos, pInfo.lookVector)
                local distance = math.floor(math.sqrt((object.pos.x - pInfo.pos[1]) ^ 2 + (object.pos.y - pInfo.pos[2]) ^ 2 + (object.pos.z - pInfo.pos[3]) ^ 2))
                local speed = math.floor(math.sqrt(object.velocity.x ^ 2 + object.velocity.y ^ 2 + object.velocity.z ^ 2))
                local color
                if isFriendly(object.name) then
                    color = 0x009cff88 -- Friendly, blue color
                elseif object.mass < 8000 then
                    color = 0x99999988 -- type unknown/low threat
                elseif object.mass < 30000 then
                    if speed > 40 then
                        -- high speed low mass, potential missile

                        local missileVector = {object.velocity.x, object.velocity.y, object.velocity.z}
                        local toPlayerVector = {pInfo.pos[1] - objX, pInfo.pos[2] - objY, pInfo.pos[3] - objZ}
                        local dotProduct = missileVector[1] * toPlayerVector[1] + missileVector[2] * toPlayerVector[2] + missileVector[3] * toPlayerVector[3]
                        if dotProduct > 0 then
                            color = 0xff5600ff -- missile coming, high threat
                        else
                            color = 0xFFFF00ff -- potential threat
                        end
                    else
                        color = 0x00FF0088 -- low mass low speed, low threat
                    end
                elseif object.mass < 200000 then
                    if speed > 20 then
                        color = 0xFFFF00ff -- jet
                    else
                        color = 0xfff70088 -- Medium sized vehicle, tanks, helicopter
                    end
                else
                    color = 0xffc300ff -- Large sized vehicle, ships, strategic bomber
                end

                if distance > 20 then
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
                            renderBox = isWithinRenderDistance(screenX, screenY, screenWidth / 2, screenHeight / 2, 1500, 1500, 1200)
                        })
                    end
                end
            end

            local filteredElements = filterElements(elements)

            for _, element in ipairs(elements) do
                local found = false
                for _, filteredElement in ipairs(filteredElements) do
                    if element.id == filteredElement.id then
                        found = true
                        break
                    end
                end
                if not found then
                    element.renderInfo = false
                end
            end
            renderElements(filteredElements, cannonHitPos, pInfo, lockedTarget)

            if pInfo then
                local AimTarget = mouseAim(pInfo.pos, pInfo.lookVector)
                local screenX, screenY = projectToScreen(AimTarget.x, AimTarget.y, AimTarget.z, pInfo.pos, pInfo.lookVector)
                if screenX and screenY then
                    --ar.drawStringWithId("AimCrossHair","X", screenX+20, screenY+80, 0xFFFFFF)
                end
            end
            holo.Flush()
            sleep() -- Adjust the sleep time as needed to balance performance and responsiveness
        end
    end
end

local function clamp(value, min, max)
    return math.max(min, math.min(value, max))
end

local function renderFuturePosition(futurePos, lockedTarget, pInfo)
    if futurePos then
        -- Project the future position to screen coords
        local screenX, screenY = projectToScreen(futurePos.x, futurePos.y, futurePos.z, pInfo.pos, pInfo.lookVector)
        
        -- Ensure screenX and screenY are within valid bounds
        if screenX and screenY then
            screenX = screenX / 4
            screenY = screenY / 4
            -- Apply clamping to avoid out-of-bounds coordinates
            screenX = clamp(screenX, 0, screenWidth / 4)  -- Ensure screenX is within the hologram width
            screenY = clamp(screenY, 0, screenHeight / 4) -- Ensure screenY is within the hologram height

            -- Filter out-of-range screen coords (use your logic here)
            if isWithinRenderDistance(
                screenX,
                screenY,
                screenWidth / 8,    -- centerX adjusted for hologram scale
                screenHeight / 8,   -- centerY adjusted for hologram scale
                4000 / GUIscale,    -- maxdx
                4800 / GUIscale,    -- maxdy
                3200 / GUIscale     -- maxd
            ) then
                -- Proceed if within range
                print("screenX:", screenX, "screenY:", screenY)
                local circleRadius = 5  -- Smaller circle for future position
                local color = 0xFF00FF88  -- Purple color

                -- Draw a small circle around predicted position
                holo.DrawLine(screenX - circleRadius, screenY, screenX + circleRadius, screenY, color, 1)
                holo.DrawLine(screenX, screenY - circleRadius, screenX, screenY + circleRadius, color, 1)

                -- Draw a line connecting locked target to predicted position
                if lockedTarget and lockedTarget.pos and pInfo.pos then
                    local targetScreenX, targetScreenY = projectToScreen(
                        lockedTarget.pos.x,
                        lockedTarget.pos.y,
                        lockedTarget.pos.z,
                        pInfo.pos,
                        pInfo.lookVector
                    )
                    if targetScreenX and targetScreenY then
                        -- Apply scaling (divide by 4 to match hologram resolution)
                        targetScreenX = targetScreenX / 4
                        targetScreenY = targetScreenY / 4

                        -- Apply clamping to ensure targetScreenX and targetScreenY are valid
                        targetScreenX = clamp(targetScreenX, 0, screenWidth / 4)
                        targetScreenY = clamp(targetScreenY, 0, screenHeight / 4)

                        if targetScreenX and targetScreenY then
                            -- Also filter locked target's coords
                            if isWithinRenderDistance(
                                targetScreenX,
                                targetScreenY,
                                screenWidth / 8,    -- centerX adjusted for hologram scale
                                screenHeight / 8,   -- centerY adjusted for hologram scale
                                4000 / GUIscale,
                                4800 / GUIscale,
                                3200 / GUIscale
                            ) then
                                holo.DrawLine(targetScreenX, targetScreenY, screenX, screenY, color, 1)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Function to predict the future position of the locked target based on its current velocity and time
local lastTargetPos, predictedTargetVelocity
local lastTargetAqquireTime = os.clock()
local velocityFactor = 1
function predictFuturePosition(targetPos, targetVel, sourceX, sourceY, sourceZ)
    local currentTime = os.clock()
    local dt = currentTime - lastTargetAqquireTime

    -- Initialize predictedVelocity & predictedAcceleration if needed
    if not lastTargetPos then
        lastTargetPos = targetPos
        lastTargetVelocity = targetVel
        predictedTargetVelocity = targetVel
        predictedTargetAcceleration = {x = 0, y = 0, z = 0}
        lastTargetAqquireTime = currentTime
    elseif dt >= 0.5 then
        -- Estimate velocity
        predictedTargetVelocity = {
            x = (targetPos.x - lastTargetPos.x) / dt,
            y = (targetPos.y - lastTargetPos.y) / dt,
            z = (targetPos.z - lastTargetPos.z) / dt
        }

        -- Estimate acceleration
        predictedTargetAcceleration = {
            x = (predictedTargetVelocity.x - lastTargetVelocity.x) / dt,
            y = (predictedTargetVelocity.y - lastTargetVelocity.y) / dt,
            z = (predictedTargetVelocity.z - lastTargetVelocity.z) / dt
        }

        -- Update previous values
        lastTargetPos = targetPos
        lastTargetVelocity = predictedTargetVelocity
        lastTargetAqquireTime = currentTime
    end

    -- Compute initial distance to target
    local dx = targetPos.x - sourceX
    local dy = targetPos.y - sourceY
    local dz = targetPos.z - sourceZ
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    local losLength = math.sqrt(dx^2 + dy^2 + dz^2)
    local losUnit = {
        x = dx / losLength,
        y = dy / losLength,
        z = dz / losLength
    }

    -- Compute rate of escape using dot product
    local rateOfEscape = predictedTargetVelocity.x * losUnit.x + predictedTargetVelocity.y * losUnit.y + predictedTargetVelocity.z * losUnit.z
    rateOfClosure = muzzleVelocity - rateOfEscape

    -- Get ship's velocity
    local shipVelocity = ship.getVelocity()

    -- Initial estimate for travel time
    local estimateTime = distance / rateOfClosure
    local terminalVelocity = muzzleVelocity * cd^(estimateTime*20)
    local averageVelocity = (terminalVelocity + muzzleVelocity) / 2 --assume constant deceleration
    print(averageVelocity)

    rateOfClosure = averageVelocity - rateOfEscape


    -- Predict future position using velocity and acceleration
    local estimateX = targetPos.x
        + (predictedTargetVelocity.x * velocityFactor - shipVelocity.x) * estimateTime
        + 0.5 * predictedTargetAcceleration.x * estimateTime * estimateTime

    local estimateY = targetPos.y
        + (predictedTargetVelocity.y * velocityFactor - shipVelocity.y) * estimateTime
        + 0.5 * predictedTargetAcceleration.y * estimateTime * estimateTime

    local estimateZ = targetPos.z
        + (predictedTargetVelocity.z * velocityFactor - shipVelocity.z) * estimateTime
        + 0.5 * predictedTargetAcceleration.z * estimateTime * estimateTime

    -- Recalculate distance after initial estimate
    dx = estimateX - sourceX
    dy = estimateY - sourceY
    dz = estimateZ - sourceZ
    distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    -- Refine estimateTime
    estimateTime = distance / rateOfClosure

    -- Recompute future position with refined time
    estimateX = targetPos.x
        + (predictedTargetVelocity.x * velocityFactor - shipVelocity.x) * estimateTime
        + 0.5 * predictedTargetAcceleration.x * estimateTime * estimateTime

    estimateY = targetPos.y
        + (predictedTargetVelocity.y * velocityFactor - shipVelocity.y) * estimateTime
        + 0.5 * predictedTargetAcceleration.y * estimateTime * estimateTime

    estimateZ = targetPos.z
        + (predictedTargetVelocity.z * velocityFactor - shipVelocity.z) * estimateTime
        + 0.5 * predictedTargetAcceleration.z * estimateTime * estimateTime

    return {x = estimateX, y = estimateY, z = estimateZ}
end

local function targetLockAndAim()
    while true do
        currentPitch, currentYaw = math.deg(getPitch()), math.deg(getYaw())
        source = ship.getWorldspacePosition()

        if pInfo.nickname and redstone.getInput("top") then
            lockedTarget = lockHighestThreatTarget(elements, screenWidth / 2, screenHeight / 2, 1000)
            print("locking on")
        end

        if lockedTarget then
            lockedTargetScan = radar.scanForShips(5000)
            for _, object in ipairs(lockedTargetScan) do
                if object.id == lockedTarget.id then
                    -- Update the locked target information
                    lockedTarget.pos = object.pos
                    lockedTarget.velocity = object.velocity
                    break
                end
            end
            if lockedTarget.pos then
                -- Predict the future position of the locked target
                local futurePos = predictFuturePosition(lockedTarget.pos, lockedTarget.velocity, pInfo.pos[1], pInfo.pos[2], pInfo.pos[3])

                -- Render the future position with a small circle
                print(textutils.serialize(lockedTarget))
                renderFuturePosition(futurePos, lockedTarget, pInfo)
            end
        end
        sleep()
    end
end

-- Main loop
parallel.waitForAny(
    main,
    targetLockAndAim
)