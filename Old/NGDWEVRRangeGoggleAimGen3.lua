local radar = peripheral.find("sp_radar")
local ar = peripheral.find("arController")
local modem = peripheral.wrap("right")
local goggleLinkPort = peripheral.find("goggle_link_port")

local cannonSourceChannel = 701
local controlChannel = 500

print("Input the cannon channel number, default: 900")
local cannonChannel = io.read()
if cannonChannel == "" then
    cannonChannel = 900
end
cannonChannel = tonumber(cannonChannel)

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
        
        resolution = askUser("Input your resolution eg.(1920,1080)", "3440,1440")
        file.writeLine("resolution=" .. resolution)
        
        fov = askUser("Input your FOV eg.(70)", "70")
        file.writeLine("fov=" .. fov)
        
        guiScale = askUser("Input your GUI scale", "4")
        file.writeLine("guiScale=" .. guiScale)
        
        mode = askUser("Input your mode 1:System in world space 2:System on vs ship", "1")
        file.writeLine("mode=" .. mode)
        
        userID = askUser("Input your ID", "MegiRicky")
        file.writeLine("userID=" .. userID)
        
        if mode == "1" then
            local source = askUser("Input the location of the computer (X,Y,Z)", "0,0,0")
            file.writeLine("source=" .. source)
        else
            file.writeLine("source=ship")
        end

        -- Integrating channel number into the config
        cannonHitPosChannel = askUser("Input the cannon data channel number", "700")
        file.writeLine("cannonHitPosChannel=" .. cannonHitPosChannel)

        controlChannel = askUser("Input the control channel", "500")
        file.writeLine("controlChannel=" .. controlChannel)

        file.close()
    end
    sleep(1)
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
sleep(1)
print(textutils.serialize(config))
screenWidth, screenHeight = config.resolution:match("(%d+),(%d+)")
screenWidth = tonumber(screenWidth)
screenHeight = tonumber(screenHeight)
fov = tonumber(config.fov)
GUIscale = tonumber(config.guiScale)
local mode = tonumber(config.mode)
userID = config.userID
friendlyIDs = readFriendlyIDs(friendlyIDFile)
local magicNumber = GUIscale/4
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

print("Source X: " .. sourceX)
print("Source Y: " .. sourceY)
print("Source Z: " .. sourceZ)
print("Resolution: " .. screenWidth .. ", " .. screenHeight)
if screenWidth == 3440 and screenHeight == 1440 then widthMagic = 1.125 else widthMagic = 0.92 end
--ar.setRelativeMode(true, screenWidth*4 , screenHeight*4 )


local function isFriendly(id)
    for _, friendlyID in ipairs(friendlyIDs) do
        if id == friendlyID then
            return true
        end
    end
    return false
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
    local connectedGoggles = goggleLinkPort.getConnected()
    local lookTarget = {}

    for uuid, goggleData in pairs(connectedGoggles) do
        if goggleData.type == "range_goggles" then
            -- Perform raycast
            local result = goggleData.raycast(500, {0, 0, 0}, false, true)
            print(textutils.serialize(result))
            if result and result.is_block and result.block_type == "block.minecraft.air" then
                lookTarget = {}
                local lx, ly, lz = lookVector[1], lookVector[2], lookVector[3]
                local playerYaw = math.deg(math.atan2(lz, lx))
                local playerPitch = math.deg(math.asin(-ly)) - 20
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
            elseif result and result.hit_pos then
                lookTarget = { x = result.hit_pos[1], y = result.hit_pos[2], z = result.hit_pos[3] }
            else
                lookTarget = {}
                local lx, ly, lz = lookVector[1], lookVector[2], lookVector[3]
                local playerYaw = math.deg(math.atan2(lz, lx))
                local playerPitch = math.deg(math.asin(-ly)) - 20
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
            end
        end
    end

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

-- Function to render elements in parallel
local function renderElements(elements, cannonHitPos, pInfo, lockedTarget)
    local tasks = {}
    for _, element in ipairs(elements) do
        table.insert(tasks, function()
            local color = element.color
            if lockedTarget and element.id == lockedTarget.id then
                color = 0xFF0000 -- Red color for locked target
            end
            --[[ar.horizontalLineWithId("frame_top_" .. element.id, element.screenX - element.frameSize, element.screenX + element.frameSize, element.screenY - element.frameSize, color)
            ar.horizontalLineWithId("frame_bottom_" .. element.id, element.screenX - element.frameSize, element.screenX + element.frameSize, element.screenY + element.frameSize, color)
            ar.verticalLineWithId("frame_left_" .. element.id, element.screenX - element.frameSize, element.screenY - element.frameSize, element.screenY + element.frameSize, color)
            ar.verticalLineWithId("frame_right_" .. element.id, element.screenX + element.frameSize, element.screenY - element.frameSize, element.screenY + element.frameSize, color)]]
            if element.renderInfo then
                --[[ar.drawString("dist: " .. element.distance, element.screenX - 15, element.screenY - 200 / GUIscale, color)
                ar.drawString("mass: " .. math.floor(element.mass / 1000) .. "k", element.screenX - 15, element.screenY - 340 / GUIscale, color)
                ar.drawString("speed: " .. element.speed, element.screenX - 15, element.screenY - 480 / GUIscale, color)
                ar.drawString("id: " .. element.id, element.screenX - 15, element.screenY - 620 / GUIscale, color)]]
            end
        end)
    end
    parallel.waitForAll(table.unpack(tasks))
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
                    lookTarget = mouseAim(pInfo.pos, pInfo.lookVector)
                    local targetInfo = {targetPos = lookTarget, targetVel = {x = 0,y = 0,z = 0}}
                    modem.transmit(cannonChannel,0,targetInfo)   
                end
            end
        else
            
        end
        sleep()
    end
end

-- Update the main function to remove target locking and aiming
local function main()
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
        
        if pInfo.nickname then
            local objectList = radar.scanForShips(10000)
            --ar.clear()

            elements = {}
            for _, object in ipairs(objectList) do
                local objX, objY, objZ = object.pos.x, object.pos.y, object.pos.z
                local screenX, screenY = projectToScreen(objX, objY, objZ, pInfo.pos, pInfo.lookVector)
                local distance = math.floor(math.sqrt((object.pos.x - pInfo.pos[1]) ^ 2 + (object.pos.y - pInfo.pos[2]) ^ 2 + (object.pos.z - pInfo.pos[3]) ^ 2))
                local speed = math.floor(math.sqrt(object.velocity.x ^ 2 + object.velocity.y ^ 2 + object.velocity.z ^ 2))
                local color
                if isFriendly(object.id) then
                    color = 0x009cff -- Friendly, blue color
                elseif object.mass < 10000 then
                    color = 0x999999 -- type unknown/low threat
                elseif object.mass < 100000 then
                    if speed > 40 then
                        -- high speed low mass, potential missile

                        local missileVector = {object.velocity.x, object.velocity.y, object.velocity.z}
                        local toPlayerVector = {pInfo.pos[1] - objX, pInfo.pos[2] - objY, pInfo.pos[3] - objZ}
                        local dotProduct = missileVector[1] * toPlayerVector[1] + missileVector[2] * toPlayerVector[2] + missileVector[3] * toPlayerVector[3]
                        if dotProduct > 0 then
                            color = 0xff5600 -- missile coming, high threat
                        else
                            color = 0xFFFF00 -- potential threat
                        end
                    else
                        color = 0x00FF00 -- low mass low speed, low threat
                    end
                elseif object.mass < 1000000 then
                    color = 0xfff700 -- Medium sized vehicle, fighter jet, tanks, helicopter
                else
                    color = 0xffc300 -- Large sized vehicle, ships, strategic bomber
                end

                if distance > 20 then
                    if screenX and screenY and isWithinRenderDistance(screenX, screenY, screenWidth / 2, screenHeight / 2, 4000 / GUIscale, 4800 / GUIscale, 3200 / GUIscale) then
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
            local screenX, screenY = projectToScreen(objX, objY, objZ, pInfo.pos, pInfo.lookVector)
            if screenX and screenY then
                ar.clearElement("CrossHair")
                ar.drawStringWithId("CrossHair","X", screenX, screenY, 0xFF0000)
            end
        elseif cannonHitPos[3] == "degree" then
            print("pitch: "..cannonHitPos[1])
            print("yaw: "..cannonHitPos[2])
            local screenX, screenY = angleToScreen(cannonHitPos[1], cannonHitPos[2], pInfo.pos, pInfo.lookVector)
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
