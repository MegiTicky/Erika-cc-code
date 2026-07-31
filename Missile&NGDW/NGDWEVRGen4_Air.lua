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

local screenWidth, screenHeight, fov, GUIscale
local sourceX, sourceY, sourceZ = 0,0,0
local source = {}
local userID
local friendlyIDs
local friendlyIDFile = "friendly_ids.txt"
local widthMagic = 1.125
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

-- Configuration file paths
local function readConfig(filename)
    if not fs.exists(filename) then
        print("Configuration file '" .. filename .. "' does not exist. Creating it.")
        file = fs.open(filename, "w")
        
        resolution = askUser("Input your IRL monitor's resolution eg.(1920,1080)", "3440,1440")
        file.writeLine("resolution=" .. resolution)
        
        fov = askUser("Input your FOV eg.(70) Actually it only works with 70 FOV", "70")
        file.writeLine("fov=" .. fov)
        
        userID = askUser("Input your in game ID(name)", "MegiRicky")
        file.writeLine("userID=" .. userID)

        cannonHitPosChannel = askUser("Input the cannon data channel number(For guiding cannon, NGDWEVROnboard required)", "700")
        file.writeLine("cannonHitPosChannel=" .. cannonHitPosChannel)

        missileControlChannel = askUser("Input the missile launch channel","1400")
        file.writeLine("missileControlChannel="..missileControlChannel)

        controlChannel = askUser("Input the control channel", "1420")
        file.writeLine("controlChannel=" .. controlChannel)

        pitchCompensation = askUser("Input the pitchCompensation.(for when the plane and the computer is not on the same ship)","48.24")
        file.writeLine("pitchCompensation="..pitchCompensation)

        file.close()
    end
    sleep(0.2)
    local file = fs.open(filename, "r")
    local config = {}
    local line = file.readLine()
    while line do
        local key, value = line:match("^(%w+)=(.*)$")
        config[key] = value
        line = file.readLine()
    end
    file.close()
    return config
end

-- Function to edit configuration
local function editConfig(filename)
    print("Do you want to edit the config? (yes/no),press enter to skip")
    local editChoice = io.read()
    if editChoice == "" then
        editChoice = "no"
    end
    if editChoice:lower() == "yes" then
        if fs.exists(filename) then
            fs.delete(filename)
        end
        return readConfig(filename)
    else
        return nil
    end
end

-- Function to select or create config
local function loadOrCreateConfig()
    print("Which player's config do you want to load?")
    local selectedID = io.read()

    local configFile = selectedID .. "config.txt"

    if fs.exists(configFile) then
        print("Config file for " .. selectedID .. " exists. Loading it.")
        local config = readConfig(configFile)
        
        -- Ask if user wants to edit config
        editConfig(configFile)
        
        return config
    else
        print("No config file found for " .. selectedID .. ". Creating a new one.")
        return readConfig(configFile)
    end
end

-- Function to read friendly IDs from a file
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

local function sign(x)
    return x > 0 and 1 or x < 0 and -1 or 0
end

-- Load configuration

local config = loadOrCreateConfig()
sleep(0.5)
print(textutils.serialize(config))
screenWidth, screenHeight = config.resolution:match("(%d+),(%d+)")
screenWidth = tonumber(screenWidth)
screenHeight = tonumber(screenHeight)
fov = tonumber(config.fov)
GUIscale = 4
local mode = tonumber(config.mode)
userID = config.userID
friendlyIDs = readFriendlyIDs(friendlyIDFile)
local magicNumber = GUIscale/4
local cannonHitPosChannel = tonumber(config.cannonHitPosChannel)
local controlChannel = tonumber(config.controlChannel) 
local missileControlChannel = tonumber(config.missileControlChannel)
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
if screenWidth == 3440 and screenHeight == 1440 then widthMagic = 1.125 else widthMagic = 0.92 end
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

--[[local graphics_3d = require("graphics_3d")
local camera = graphics_3d.camera().create(70, screenWidth/screenSizeScale, screenHeight/screenSizeScale, 0.1, 1000)

-- Replace the original projection logic
local function projectToScreen(x, y, z, userPos, lookVector)
    -- Update the camera position and orientation
    ccVectorLook = vector.new(lookVector[1],lookVector[2],lookVector[3])
    print(userPos[1],userPos[2],userPos[3])
    ccVectorPos = vector.new(userPos[1],userPos[2],userPos[3])

    graphics_3d.camera().update(ccVectorPos, ccVectorLook)
    -- Project the 3D point onto the screen
    ccVectorTargetPos = vector.new(x,y,z)

    local screenX, screenY = graphics_3d.project(ccVectorTargetPos, camera)
    screenX = math.abs(screenX)

    return screenX, screenY
end]]

-- Function to display pitch and yaw of a cannon
local function angleToScreen(pitch, yaw, userPos, lookVector)
    local lx, ly, lz = lookVector[1], lookVector[2], lookVector[3]
    local playerYaw = math.deg(math.atan2(lz, lx))
    local playerPitch = math.deg(math.asin(-ly))
    playerYaw = playerYaw + 90
    if playerYaw < 0 then
        playerYaw = playerYaw + 360
    end

    -- Calculate yaw difference
    local yawDiff = yaw - playerYaw
    if yawDiff > 180 then
        yawDiff = yawDiff - 360
    elseif yawDiff < -180 then
        yawDiff = yawDiff + 360
    end

    if math.abs(yawDiff) > 90 then
        return nil, nil
    end

    -- Calculate pitch difference
    local pitchDiff = -pitch + playerPitch

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
    local dx = projectedX - centerX / magicNumber
    local dy = projectedY - centerY / magicNumber

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
        if holoX >= 0 and holoX < screenWidth / 4 and holoY >= 0 and holoY < screenHeight / 4 and element.renderBox then
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
        else
            -- Draw an edge indicator for objects outside the display bounds
            --drawEdgeIndicator(holo, element.screenX, element.screenY, screenWidth / 4, screenHeight / 4, circleRadius)
        end
    end
end

local function lockHighestThreatTarget(elements, centerX, centerY, radius)
    local closestTarget = nil
    local closestDistance = math.huge  -- Initialize to a large number

    for _, element in ipairs(elements) do
        if element.id then
            local dx = element.screenX - centerX / magicNumber
            local dy = element.screenY - centerY / magicNumber
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

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == cannonHitPosChannel then
                cannonHitPos = message
            elseif channel == controlChannel then
                controls = message
            elseif channel == waypointChannel then
                waypoints = message
            elseif channel == missileInfoChannel then
                immediateMissileInfo = message
            end
        else
            sleep()
        end
    end
end

local function getAngularVelocity(currentYaw, currentTime)
    if lastYaw and lastYawTime then
        local deltaTime = currentTime - lastYawTime
        local deltaYaw = (currentYaw - lastYaw + math.pi) % (2 * math.pi) - math.pi
        return deltaYaw / deltaTime  -- Radians per second
    end
    return 0
end

local function launchMissile(targetType,targetId,targetPos)
    if type(controls.fireMissile) ~= "table" then
        controls.fireMissile = {}
    end

    local currentMissileId = missileId
    -- Assign a table to this missile's ID in fireMissile, marking it as launched
    if targetType == "ship" then
        controls.fireMissile[currentMissileId] = {launch = true, type = targetType, id = targetId}
    else
        controls.fireMissile[currentMissileId] = {launch = true, type = targetType, pos = targetPos}
    end
    missileLaunched[currentMissileId] = true -- Mark this missile as launched
    print("Launching missile:", currentMissileId)
    
    missileId = missileId + 1 -- Increment missile ID for next launch
end

local function targetLockAndAim()
    while true do
        source = cannonHitPos[5]
        cannonChannel = 0
        source = ship.getWorldspacePosition()
        source.y = source.y + 1
        if pInfo.nickname then
            lockedTarget = lockHighestThreatTarget(elements, screenWidth / 2, screenHeight / 2, 1000)
            if lockedTarget then
                lockedTargetScan = radar.scanForShips(10000)
                for _, object in ipairs(lockedTargetScan) do
                    if object.id == lockedTarget.id then
                        -- Update the locked target information
                        lockedTarget.pos = object.pos
                        lockedTarget.velocity = object.velocity
                        break
                    end
                end
                if lockedTarget.pos then
                    local targetInfo = {targetPos = lockedTarget.pos, targetVel = lockedTarget.velocity}
                    modem.transmit(cannonHitPosChannel,0,targetInfo)
                end
            else
                lookTarget = mouseAim(pInfo.pos, pInfo.lookVector)
                local targetInfo = {targetPos = lookTarget, targetVel = {x = 0,y = 0,z = 0}}
                modem.transmit(cannonHitPosChannel,0,targetInfo)
            end
            local launch = redstone.getInput("front") or redstone.getInput("back") or redstone.getInput("left") or redstone.getInput("right")

            if lockedTarget and lockedTarget.id and launch then
                if type(lockedTarget.id) == "number" then
                    launchMissile("ship",lockedTarget.id,lockedTarget.pos) --target is a ship
                else
                    launchMissile("waypoint",lockedTarget.id,lockedTarget.pos)
                    modem.transmit(missileControlChannel, missileControlChannel, controls)
                end
            end
        end
        sleep()
    end
end

local function drawPitchLadder()
    local pitch = getPitch()
    local roll = -getRoll()
    local screenWidth,screenHeight = screenWidth/4, screenHeight/4

    local centerX = screenWidth / 2
    local centerY = screenHeight / 2

    local pitchStep = 10 -- Degrees per pitch line
    local maxPitch = 90 -- Maximum pitch levels to render (both positive and negative)
    local lineLength = screenWidth / 10 -- Length of the angled pitch lines

    -- Loop through each pitch level to render the ladder
    for i = -maxPitch, maxPitch, pitchStep do
        local pitchOffset = math.tan(math.rad(i - (math.deg(pitch) + config.pitchCompensation))) * (screenHeight / 2)
        local ladderY = centerY - pitchOffset

        -- Rotate the pitch lines based on roll
        local rollRadians = roll * 0.9
        local halfLineLength = lineLength / 2
        local startX = centerX - halfLineLength * math.cos(rollRadians)
        local startY = ladderY - halfLineLength * math.sin(rollRadians)
        local endX = centerX + halfLineLength * math.cos(rollRadians)
        local endY = ladderY + halfLineLength * math.sin(rollRadians)

        -- Draw the pitch line
        if ladderY >= 1 and ladderY <= screenHeight then
            holo.DrawLine(
                math.floor(startX), math.floor(startY),
                math.floor(endX), math.floor(endY),
                0x00FF0055, -- Green color (RGBA format)
                1           -- Mode: Blending
            )

            -- Draw pitch labels at both ends of the line
            local labelColor = 0x00FF0088 -- Green color for labels
            if i == 0 then 
                holo.Text(math.floor(startX - 10), math.floor(startY - 8), "00", labelColor, 0) -- Start label
                holo.Text(math.floor(endX), math.floor(endY - 8), "00", labelColor,0) -- End label
            else
                holo.Text(math.floor(startX - 10), math.floor(startY - 8), tostring(math.abs(i)), labelColor, 0) -- Start label
                holo.Text(math.floor(endX), math.floor(endY - 8), tostring(math.abs(i)), labelColor, 0) -- End label
            end
        end
    end
end

local function drawFlightInfo()
    local pitch = getPitch()
    local roll = -getRoll()
    local adjustedPitch = math.deg(pitch + math.rad(config.pitchCompensation))

    local screenWidth = screenWidth / 4
    local screenHeight = screenHeight / 4

    local centerX = screenWidth / 2
    local centerY = screenHeight / 2

    -- Get the ship's position and velocity
    local shipPos = ship.getWorldspacePosition()
    local velocity = ship.getVelocity()

    -- Calculate the speed in m/s
    local speed = math.floor(math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2))

    -- Calculate altitude (assuming altitude is based on the Y position)
    local altitude = math.floor(shipPos.y)

    -- Define positions for speed and altitude boxes
    local boxWidth = 40  -- Increased box width for better fit
    local boxHeight = 14 -- Increased box height
    local boxPadding = 4
    local speedBoxX = centerX - screenWidth / 6 + boxPadding
    local altitudeBoxX = centerX + screenWidth / 6 - boxWidth - boxPadding
    local boxY = centerY - boxHeight - boxPadding - 30 -- Slightly higher than before

    local labelColor = 0x00FF0088 -- Green color for labels
    -- Draw the speed box
    holo.DrawLine(speedBoxX, boxY, speedBoxX + boxWidth, boxY, labelColor, 1) -- Top
    holo.DrawLine(speedBoxX, boxY + boxHeight, speedBoxX + boxWidth, boxY + boxHeight, labelColor, 1) -- Bottom
    holo.DrawLine(speedBoxX, boxY, speedBoxX, boxY + boxHeight, labelColor, 1) -- Left
    holo.DrawLine(speedBoxX + boxWidth, boxY, speedBoxX + boxWidth, boxY + boxHeight, labelColor, 1) -- Right
    holo.Text(speedBoxX + 2, boxY, tostring(speed) .. "m/s", labelColor, 0) -- Adjusted text position

    -- Draw the altitude box
    holo.DrawLine(altitudeBoxX, boxY, altitudeBoxX + boxWidth, boxY, labelColor, 1) -- Top
    holo.DrawLine(altitudeBoxX, boxY + boxHeight, altitudeBoxX + boxWidth, boxY + boxHeight, labelColor, 1) -- Bottom
    holo.DrawLine(altitudeBoxX, boxY, altitudeBoxX, boxY + boxHeight, labelColor, 1) -- Left
    holo.DrawLine(altitudeBoxX + boxWidth, boxY, altitudeBoxX + boxWidth, boxY + boxHeight, labelColor, 1) -- Right
    holo.Text(altitudeBoxX + 2, boxY, tostring(altitude) .. "m", labelColor, 0) -- Adjusted text position

    -- Display weapon count
    local AIMcolor,GBUcolor,TBColor = labelColor,labelColor,labelColor
    if weaponChoosen == "AIM-220" then
        if missileCoolDown == 0 then
            AIMcolor = 0xFF9900FF
        else
            AIMcolor = 0xFF000088
        end
    elseif weaponChoosen == "GBU-42" then
        if missileCoolDown == 0 then
            GBUcolor = 0xFF9900FF
        else
            GBUcolor = 0xFF000088
        end
    elseif weaponChoosen == "thunderBolt" then
        if missileCoolDown == 0 then
            TBColor = 0xFF9900FF
        else
            TBColor = 0xFF000088
        end
    end
    holo.Text(speedBoxX + 2, 35, "AIM-220:" .. AIMCount, AIMcolor, 0)
    holo.Text(speedBoxX + 2, 50, "GBU-42:" .. GBUCount, GBUcolor, 0)
    holo.Text(speedBoxX + 2, 65, "TB:" .. thunderboltCount, TBColor, 0)
end

local function drawCompass()
    local yaw = math.deg(getYaw())
    if yaw < 0 then
        yaw = yaw + 360 -- Ensure yaw is within 0-360
    end

    local screenHeight = screenHeight / screenSizeScale
    local screenWidth = screenWidth / screenSizeScale

    -- Define compass settings
    local compassWidth = screenWidth / 2 -- Width of the compass bar
    local compassHeight = 8 -- Height for tick marks
    local compassY = 10 -- Y position of the compass (top of the screen)
    local centerX = screenWidth / 2 -- Center of the screen
    local tickSpacing = compassWidth / 36 -- Spacing between ticks (10 degrees per tick)
    local labelColor = 0x00FF00FF -- Green color for labels

    -- Render major directions (N, E, S, W) and tick marks
    for angle = -180, 180, 10 do
        local relativeAngle = (angle - yaw + 360) % 360 -- Adjust for yaw
        local normalizedAngle = relativeAngle > 180 and relativeAngle - 360 or relativeAngle -- Normalize to -180 to 180

        local posX = math.floor(centerX + (normalizedAngle / 180) * (compassWidth / 2)) -- Map angle to screen

        if posX >= 0 and posX <= screenWidth then
            if angle % 90 == 0 then
                -- Major directions (N, E, S, W)
                local dir = ({ [0] = "N", [90] = "E", [180] = "S", [-90] = "W", [-180] = "S" })[angle]
                holo.Text(posX - 3, compassY + 5, dir, labelColor, 0) -- Label the major directions
                holo.DrawLine(posX, compassY, posX, compassY + compassHeight, labelColor, 1) -- Long tick
            else
                -- Minor tick marks (every 10 degrees)
                local tickHeight = compassHeight / 2
                holo.DrawLine(posX, compassY, posX, compassY + tickHeight, labelColor, 1)
            end
        end
    end

    local triangleSize = 3
    holo.DrawLine(centerX - triangleSize, compassY, centerX, compassY - compassHeight - 5, labelColor, 1) -- Left edge
    holo.DrawLine(centerX, compassY - compassHeight - 5, centerX + triangleSize, compassY, labelColor, 1) -- Right edge
    holo.DrawLine(centerX - triangleSize, compassY, centerX + triangleSize, compassY, labelColor, 1) -- Base
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
        parallel.waitForAll(
            function()
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
                                    renderBox = isWithinRenderDistance(screenX, screenY, screenWidth / 2, screenHeight / 2, 4000 / GUIscale, 4800 / GUIscale, 3200 / GUIscale)
                                })
                            end
                        end
                    end

                    --waypoint render
                    for i,waypoint in ipairs(waypoints) do
                        local screenX, screenY = projectToScreen(waypoint.x, waypoint.y, waypoint.z, pInfo.pos, pInfo.lookVector)
                        local distance = math.floor(math.sqrt((waypoint.x - pInfo.pos[1]) ^ 2 + (waypoint.y - pInfo.pos[2]) ^ 2 + (waypoint.z - pInfo.pos[3]) ^ 2))
                        local color = tonumber(string.format("0x%X",colorMap[waypoint.color]))
                        if screenX and screenY then
                            table.insert(elements, {
                                id = "W"..i,
                                pos = waypoint,
                                screenX = screenX,
                                screenY = screenY,
                                frameSize = 20,
                                color = color,
                                distance = distance,
                                mass = 0,
                                speed = 0,
                                velocity = {0,0,0},
                                renderInfo = true,
                                renderBox = isWithinRenderDistance(screenX, screenY, screenWidth / 2, screenHeight / 2, 4000 / GUIscale, 4800 / GUIscale, 3200 / GUIscale)
                            })
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
                end

                if pInfo then
                    local AimTarget = mouseAim(pInfo.pos, pInfo.lookVector)
                    local screenX, screenY = projectToScreen(AimTarget.x, AimTarget.y, AimTarget.z, pInfo.pos, pInfo.lookVector)
                    if screenX and screenY then
                        --ar.drawStringWithId("AimCrossHair","X", screenX+20, screenY+80, 0xFFFFFF)
                    end
                end

                if ship.getVelocity() then
                    local velocity = ship.getVelocity()
                    local speed = math.floor(math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2))
                end
            end,
            drawPitchLadder,
            drawFlightInfo,
            drawCompass,
            renderLockOnArea
        )
        holo.Flush()
        sleep() -- Adjust the sleep time as needed to balance performance and responsiveness
    end
end

local function hitMark()
    while true do
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

        local shipRoll = math.deg(ship.getRoll())
        local shipYaw = math.deg(ship.getYaw()) - 90
        if shipYaw < 0 then shipYaw = shipYaw + 360 end
        local shipPitch = math.deg(ship.getPitch())

        local currentPitch = shipPitch + cannons[1].getPitch()
        local currentYaw = shipYaw + cannons[1].getYaw() - 90
        if currentYaw < 0 then currentYaw = currentYaw + 360 end
        source = ship.getWorldspacePosition()
        if source and currentYaw and currentPitch then
            local dx = projectionDistance * math.cos(math.rad(currentPitch)) * math.sin(math.rad(currentYaw))
            local dz = -projectionDistance * math.cos(math.rad(currentPitch)) * math.cos(math.rad(currentYaw))
            local dy = projectionDistance * math.sin(math.rad(currentPitch))
            objX = source.x + dx
            objY = source.y+2 + dy
            objZ = source.z + dz
        end

        if objX and objY and objZ then
            local screenX, screenY = projectToScreen(objX, objY, objZ, pInfo.pos, pInfo.lookVector)
            if screenX and screenY then
                ar.clearElement("CrossHair")
                ar.drawStringWithId("CrossHair","X", screenX, screenY, 0xFF0000)
            end
        elseif cannonHitPos[3] == "degree" then
            local screenX, screenY = angleToScreen(cannonHitPos[1], cannonHitPos[2], pInfo.pos, pInfo.lookVector)
            if screenX and screenY then
                ar.clearElement("CrossHair")
                ar.drawStringWithId("CrossHair","X", screenX, screenY, 0xFF0000)
            end
        end
        sleep()
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

            -- If it's a new missile, add it to the list
            if not foundMissile then
                if immediateMissileInfo.type == "AIM-220" then
                    table.insert(AIMInfoList, immediateMissileInfo)
                elseif immediateMissileInfo.type == "GBU-42" then
                    table.insert(GBUInfoList, immediateMissileInfo)
                elseif immediateMissileInfo.type == "thunderBolt" then
                    table.insert(thunderBoltInfoList, immediateMissileInfo)
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
        if controls.switchToAIM220 then
            weaponChoosen = "AIM-220"
        elseif controls.switchToGBU then
            weaponChoosen = "GBU-42"
        elseif controls.switchToThunderbolt then
            weaponChoosen = "thunderBolt"
        elseif controls.switchToAIM9 then
            weaponChoosen = "AIM-9"
        elseif controls.switchToGun then
            weaponChoosen = "Gun"
        end
        if controls.fire then
            if weaponChoosen == "AIM-220" or weaponChoosen == "GBU-42" or weaponChoosen == "thunderBolt" then
                if lockedTarget and lockedTarget.id and missileCoolDown == 0 then
                    if type(lockedTarget.id) == "number" then
                        launchMissile("ship",lockedTarget.id,lockedTarget.pos,weaponChoosen) --target is a ship
                    else
                        launchMissile("waypoint",lockedTarget.id,lockedTarget.pos,weaponChoosen)
                    end
                    missileCoolDown = 20
                    modem.transmit(missileControlChannel,missileControlChannel,missileControls)
                end
            elseif weaponChoosen == "AIM-9" then

            elseif weaponChoosen == "Gun" then

            end
        end
        missileCoolDown = math.max(missileCoolDown - 1,0)
        sleep()
    end
end

local function printOutput()
    while true do
        --print(textutils.serialize(AIMInfoList))
        --print(textutils.serialize(GBUInfoList))
        --print(textutils.serialize(thunderBoltInfoList))
        --print(textutils.serialize(controls))
        --print(textutils.serialize(missileControls))
        print(textutils.serialize(missileControls))
        print(waypointChannel)
        --print("controlsChannel: "..controlChannel)
        --print("weaponChoosen: "..weaponChoosen)
        sleep(0.5)
    end
end

-- Main loop
parallel.waitForAny(
    modemMessage,
    main,
    targetLockAndAim,
    missileListBuilding,
    printOutput,
    missileHandler
)