local radar = peripheral.find("sp_radar")
local modem = peripheral.wrap("right")
local monitor = peripheral.find("monitor")

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

local Kp = 0.3  -- Proportional gain
local Ki = 0.1  -- Integral gain
local Kd = 0.05  -- Derivative gain

local controls = {cannonControlMode = "manual"}


-- Configuration file paths
local function readConfig(filename)
    if not fs.exists(filename) then
        print("Configuration file '" .. filename .. "' does not exist. Creating it.")
        file = fs.open(filename, "w")

        -- Integrating channel number into the config
        cannonHitPosChannel = askUser("Input the cannon data channel number", "700")
        file.writeLine("cannonHitPosChannel=" .. cannonHitPosChannel)

        controlChannel = askUser("Input the control channel", "500")
        file.writeLine("controlChannel=" .. controlChannel)

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
sleep(0.2)
print(textutils.serialize(config))
friendlyIDs = readFriendlyIDs(friendlyIDFile)
local cannonHitPosChannel = tonumber(config.cannonHitPosChannel)
local controlChannel = tonumber(config.controlChannel)

if modem then
    modem.open(cannonHitPosChannel)
    modem.open(controlChannel)
end

if mode == 1 then
    sourceX, sourceY, sourceZ = string.match(config.source, "(%-?%d+),(%-?%d+),(%-?%d+)")
    sourceX = tonumber(sourceX)
    sourceY = tonumber(sourceY)
    sourceZ = tonumber(sourceZ)
else
    local pos = ship.getWorldspacePosition()
    sourceX, sourceY, sourceZ = pos.x, pos.y, pos.z
end

monitor.setTextScale(0.5)
local screenWidth,screenHeight = monitor.getSize()
print("Source X: " .. sourceX)
print("Source Y: " .. sourceY)
print("Source Z: " .. sourceZ)
print("Resolution: " .. screenWidth .. ", " .. screenHeight)
widthMagic = 1.2

local function isFriendly(id)
    for _, friendlyID in ipairs(friendlyIDs) do
        if id == friendlyID then
            return true
        end
    end
    return false
end

local function normalizeVector(v)
    local length = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
    if length == 0 then
        return {0, 0, 0}
    end
    return {v[1] / length, v[2] / length, v[3] / length}
end

-- Function to normalize the rotation matrix
local function normalizeRotationMatrix(rotMatrix)
    local normalizedMatrix = {}
    for i = 1, #rotMatrix do
        normalizedMatrix[i] = normalizeVector(rotMatrix[i])
    end
    return normalizedMatrix
end

local function getPitch()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return -math.asin(normalizedMatrix[2][3])
end

local function getRoll()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)

    -- Extract components from the transformation matrix
    local x1, y1 = normalizedMatrix[1][1], normalizedMatrix[1][2] -- X-axis (right)
    local z1, z3 = normalizedMatrix[1][3], normalizedMatrix[3][3] -- Z-axis (forward)
    local upX, upY = normalizedMatrix[2][1], normalizedMatrix[2][2] -- Y-axis (up)

    -- Calculate yaw from the forward vector
    local forwardX = normalizedMatrix[3][1]
    local forwardZ = normalizedMatrix[3][3]
    local yaw = math.atan2(forwardX, forwardZ)

    -- Calculate pitch using the forward vector
    local pitch = -math.asin(normalizedMatrix[2][3]) -- Y-component of forward vector

    -- Correct roll calculation based on the X and Y components of the right axis
    local roll = math.atan2(upX, upY)

    return -roll
end

-- Function to project 3D coordinates to 2D screen coordinates
local function projectToScreen(x, y, z, userPos, lookVector)
    local dx = x - userPos.x
    local dy = -(y - userPos.y)
    local dz = z - userPos.z

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
    local fov = 150
    local screenDepth = screenWidth / 2 * math.tan(math.rad(fov / 1.125 / 2))
    local verticalScreenDepth = screenHeight * math.tan(math.rad(fov / 2))

    local projectedX, projectedY

    if yawDiff > 0 then
        projectedX = screenWidth / 2 + screenDepth * math.tan(math.rad(math.abs(yawDiff))) / 0.8
    else
        projectedX = screenWidth / 2 - screenDepth * math.tan(math.rad(math.abs(yawDiff))) / 0.8
    end

    if pitchDiff > 0 then
        projectedY = screenHeight / 2 + screenHeight * math.tan(math.rad(fov / 0.95 / 2)) * math.tan(math.rad(math.abs(pitchDiff))) / 3.8
    else
        projectedY = screenHeight / 2 - screenHeight * math.tan(math.rad(fov / 0.95 / 2)) * math.tan(math.rad(math.abs(pitchDiff))) / 3.8
    end

    -- Compensate for monitor roll
    local roll = getRoll()
    local cosRoll = math.cos(roll)
    local sinRoll = math.sin(roll)
 
    -- Rotate the coordinates based on roll
    local centeredX = projectedX - screenWidth / 2
    local centeredY = projectedY - screenHeight / 2
 
    local rolledX = centeredX * cosRoll - centeredY * sinRoll
    local rolledY = centeredX * sinRoll + centeredY * cosRoll
 
    -- Translate back to screen space
    projectedX = rolledX + screenWidth / 2
    projectedY = rolledY + screenHeight / 2
 
    projectedX = math.floor(projectedX)
    projectedY = math.floor(projectedY)

    return projectedX, projectedY - 1
end

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

    local targetX = userPos.x + dx
    local targetY = userPos.y + dy
    local targetZ = userPos.z + dz
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
            if dx < 800 / 4 and dy < 800 / 4 then
                overlap = true
                element.renderInfo = false
                break
            end
        end

        table.insert(filteredElements, element)
    end

    return filteredElements
end

-- Function to determine if a target is outside the monitor bounds
local function isOutOfBounds(screenX, screenY, screenWidth, screenHeight)
    return screenX < 1 or screenX > screenWidth or screenY < 1 or screenY > screenHeight
end

-- Function to draw an arrow or symbol pointing toward the target
local function drawEdgeIndicator(screenX, screenY, screenWidth, screenHeight)
    local centerX = screenWidth / 2
    local centerY = screenHeight / 2

    -- Calculate the angle from the center to the target
    local angle = math.atan2(screenY - centerY, screenX - centerX) -- Angle in radians

    -- Determine the nearest edge and arrow orientation
    local arrow
    if math.abs(angle) <= math.pi / 4 then
        arrow = ">" -- Right
        screenX = screenWidth
        screenY = math.min(math.max(centerY + (screenX - centerX) * math.tan(angle), 1), screenHeight)
    elseif math.abs(angle) > 3 * math.pi / 4 then
        arrow = "<" -- Left
        screenX = 1
        screenY = math.min(math.max(centerY + (screenX - centerX) * math.tan(angle), 1), screenHeight)
    elseif angle > 0 then
        arrow = "v" -- Down
        screenY = screenHeight
        screenX = math.min(math.max(centerX + (screenY - centerY) / math.tan(angle), 1), screenWidth)
    else
        arrow = "^" -- Up
        screenY = 1
        screenX = math.min(math.max(centerX + (screenY - centerY) / math.tan(angle), 1), screenWidth)
    end

    -- Draw the arrow
    monitor.setCursorPos(math.floor(screenX), math.floor(screenY))
    monitor.setTextColor(colors.purple)
    monitor.write(arrow)
end

-- Function to render elements in parallel
local function renderElements(elements, cannonHitPos, pInfo, lockedTarget)
    local tasks = {}
    monitor.setTransparentColor(colors.black)
    for _, element in ipairs(elements) do
        table.insert(tasks, function()
            local color = element.color
            if lockedTarget and element.id == lockedTarget.id then
                color = colors.red -- Red color for locked target
            end

            -- Check if the target is within bounds
            if isOutOfBounds(element.screenX, element.screenY, screenWidth, screenHeight) then
                -- Draw an edge indicator if out of bounds
                drawEdgeIndicator(element.screenX, element.screenY, screenWidth, screenHeight)
            else
                -- Draw the target on the screen
                monitor.setCursorPos(element.screenX, element.screenY)
                monitor.setTextColor(color)
                monitor.write("O")

                if element.renderInfo then
                    monitor.setCursorPos(element.screenX, element.screenY - 1)
                    monitor.write("d:" .. element.distance)
                    monitor.setCursorPos(element.screenX, element.screenY - 2)
                    monitor.write("s: " .. element.speed)
                    monitor.setCursorPos(element.screenX, element.screenY - 3)
                    monitor.write("id: " .. element.id)
                end
            end
        end)
    end
    parallel.waitForAll(table.unpack(tasks))
end

local function drawPitchLadder(centerX, centerY, pitch, roll, screenWidth, screenHeight)
    local pitchStep = 10 -- Degrees per pitch line
    local maxPitch = 30 -- Maximum pitch levels to render (both positive and negative)
    local lineLength = screenWidth / 5 -- Length of the angled pitch lines

    for i = -maxPitch, maxPitch, pitchStep do
        local pitchOffset = math.tan(math.rad(i - pitch)) * (screenHeight / 2)
        local ladderY = centerY - pitchOffset - 2

        -- Rotate the pitch lines based on roll
        local rollRadians = roll
        local halfLineLength = lineLength / 2
        local startX = centerX - halfLineLength * math.cos(rollRadians)
        local startY = ladderY - halfLineLength * math.sin(rollRadians)
        local endX = centerX + halfLineLength * math.cos(rollRadians)
        local endY = ladderY + halfLineLength * math.sin(rollRadians)

        -- Draw the dots for the pitch line
        local numDots = 8 -- Number of dots per line
        for j = 0, numDots do
            local t = j / numDots -- Interpolation factor
            local x = math.floor(startX + t * (endX - startX))
            local y = math.floor(startY + t * (endY - startY))
            if x >= 1 and x <= screenWidth and y >= 1 and y <= screenHeight then
                monitor.setCursorPos(x, y)
                monitor.setTextColor(colors.green) -- Green dots for the pitch ladder
                monitor.write("-")
            end
        end

        -- Draw pitch labels at both ends
        if ladderY >= 1 and ladderY <= screenHeight then
            monitor.setCursorPos(math.floor(startX), math.floor(startY))
            monitor.write(tostring(math.abs(i)))
            monitor.setCursorPos(math.floor(endX), math.floor(endY))
            monitor.write(tostring(math.abs(i)))
        end
    end

    -- Draw the center marker (crosshair or wings)
    monitor.setCursorPos(centerX, centerY - 2)
    monitor.write("+")
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

local function targetLockAndAim()
    while true do
        source = cannonHitPos[5]
        if true then
            source = ship.getWorldspacePosition()
            source.y = source.y + 1
            if pInfo.nickname then
                lockedTarget = lockHighestThreatTarget(elements, screenWidth / 2, screenHeight / 2, 1000)
                if lockedTarget then
                    print("Locked target ID: " .. lockedTarget.id)
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
                        local targetInfo = {targetPos = lockedTarget.pos, targetVel = lockedTarget.velocity}
                        modem.transmit(cannonChannel,0,targetInfo)
                    end
                else
                    lookTarget = mouseAim(shipPos, lookVector)
                    local targetInfo = {targetPos = lookTarget, targetVel = {x = 0,y = 0,z = 0}}
                    modem.transmit(cannonChannel,0,targetInfo)   
                end
            end
        else
            
        end
        sleep()
    end
end

local function displayData()
    -- Get the ship's position and velocity
    local shipPos = ship.getWorldspacePosition()
    local velocity = ship.getVelocity()

    -- Calculate the speed in m/s
    local speed = math.floor(math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2))

    -- Calculate altitude (assuming altitude is based on the Y position)
    local altitude = math.floor(shipPos.y)

    -- Display the information on the monitor
    monitor.setCursorPos(1, 1) -- Top-left corner
    monitor.setTextColor(colors.green)
    monitor.write("Altitude: " .. altitude .. " m")
    monitor.setCursorPos(1, 2) -- Below the altitude
    monitor.write("Speed: " .. speed .. " m/s")
end


-- Update the main function to remove target locking and aiming
local function main()
    while true do
        monitor.clear()
        screenWidth,screenHeight = monitor.getSize()

        local transformationMatrix = ship.getTransformationMatrix()
        local shipPos = ship.getWorldspacePosition()
        local forwardVector = {
            x = -transformationMatrix[3][1],
            y = -transformationMatrix[3][2],
            z = -transformationMatrix[3][3]
        }

        local yaw = math.atan2(forwardVector.x, forwardVector.z)
        local pitch = getPitch()
        local roll = getRoll()

        local centerX = screenWidth / 2
        local centerY = screenHeight / 2
        drawPitchLadder(centerX, centerY, math.deg(pitch), roll, screenWidth, screenHeight)
        displayData()
        --renderHorizonLine(pitch, roll, screenWidth, screenHeight)

        lookVector = {
            math.cos(pitch) * math.sin(yaw), -- X component of the vector
            -math.sin(pitch),                -- Y component of the vector
            -math.cos(pitch) * math.cos(yaw) -- Z component of the vector
        }
        
        -- Normalize the direction vector
        local magnitude = math.sqrt(lookVector[1]^2 + lookVector[2]^2 + lookVector[3]^2)
        lookVector[1] = lookVector[1] / magnitude
        lookVector[2] = lookVector[2] / magnitude
        lookVector[3] = lookVector[3] / magnitude
        
        -- Print the results
        print("Yaw: " .. math.deg(yaw))
        print("Pitch: " .. math.deg(pitch))
        print("Direction Vector: x = " .. lookVector[1] .. ", y = " .. lookVector[2] .. ", z = " .. lookVector[3])
        
        if lookVector then
            local objectList = radar.scanForShips(10000)
            --ar.clear()

            elements = {}
            for _, object in ipairs(objectList) do
                local objX, objY, objZ = object.pos.x, object.pos.y, object.pos.z
                local screenX, screenY = projectToScreen(objX, objY, objZ, shipPos, lookVector)
                local distance = math.floor(math.sqrt((object.pos.x - shipPos.x) ^ 2 + (object.pos.y - shipPos.y) ^ 2 + (object.pos.z - shipPos.z) ^ 2))
                local speed = math.floor(math.sqrt(object.velocity.x ^ 2 + object.velocity.y ^ 2 + object.velocity.z ^ 2))
                local color
                if isFriendly(object.id) then
                    color = colors.blue -- Friendly, blue color
                elseif object.mass < 10000 then
                    color = colors.lightGray -- type unknown/low threat
                elseif object.mass < 100000 then
                    if speed > 40 then
                        -- high speed low mass, potential missile

                        local missileVector = {object.velocity.x, object.velocity.y, object.velocity.z}
                        local toPlayerVector = {shipPos.x - objX, shipPos.y - objY, shipPos.z - objZ}
                        local dotProduct = missileVector[1] * toPlayerVector[1] + missileVector[2] * toPlayerVector[2] + missileVector[3] * toPlayerVector[3]
                        if dotProduct > 0 then
                            color = colors.red -- missile coming, high threat
                        else
                            color = colors.orange -- potential threat
                        end
                    else
                        color = colors.green -- low mass low speed, low threat
                    end
                elseif object.mass < 1000000 then
                    color = colors.yellow -- Medium sized vehicle, fighter jet, tanks, helicopter
                else
                    color = colors.orange -- Large sized vehicle, ships, strategic bomber
                end

                if distance > 20 then
                    if screenX and screenY and isWithinRenderDistance(screenX, screenY, screenWidth / 2, screenHeight / 2, 4000 / 4, 4800 / 4, 3200 / 4) then
                        table.insert(elements, {
                            id = object.id,
                            screenX = screenX,
                            screenY = screenY,
                            frameSize = 20,
                            color = color,
                            distance = distance,
                            mass = object.mass,
                            speed = speed,
                            velocity = object.velocity,
                            renderInfo = true
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
        end

        if ship.getVelocity() then
            local velocity = ship.getVelocity()
            local speed = math.floor(math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2))

            --ar.drawStringWithId("AimCrossHair","speed: "..speed, 100, 500, 0xFFFFFF)
        end


        sleep(0.05) -- Adjust the sleep time as needed to balance performance and responsiveness
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
            local screenX, screenY = projectToScreen(objX, objY, objZ, shipPos, lookVector)
            if screenX and screenY then
                ar.clearElement("CrossHair")
                ar.drawStringWithId("CrossHair","X", screenX, screenY, 0xFF0000)
            end
        elseif cannonHitPos[3] == "degree" then
            print("pitch: "..cannonHitPos[1])
            print("yaw: "..cannonHitPos[2])
            local screenX, screenY = angleToScreen(cannonHitPos[1], cannonHitPos[2], shipPos, lookVector)
            if screenX and screenY then
                ar.clearElement("CrossHair")
                ar.drawStringWithId("CrossHair","X", screenX, screenY, 0xFF0000)
            end
        end
        sleep()
    end
end

-- Main loop
parallel.waitForAny(
    modemMessage,
    main,
    targetLockAndAim
)
