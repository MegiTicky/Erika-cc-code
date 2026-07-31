-- Variable initialization
local radar = peripheral.find("sp_radar")
local ar = peripheral.find("arController")
local modem = peripheral.find("modem")
local speaker = peripheral.find("speaker")                      

local screenWidth, screenHeight, fov, GUIscale
local sourceX, sourceY, sourceZ = 0,0,0
local source = {}
local userID
local friendlyIDs
local widthMagic = 1.125
local projectionDistance = 100
local currentPitch, currentYaw = 0,0
local lockedTarget = nil
local elements = {}
local pInfo = {}
local cannonHitPos = {}
local pitchAdjustments = "1"

local ciwsData = {
    psBack = { crosshairX = nil, crosshairY = nil, lockedTargetId = nil },
    psFront = { crosshairX = nil, crosshairY = nil, lockedTargetId = nil },
    ssBack = { crosshairX = nil, crosshairY = nil, lockedTargetId = nil },
    ssFront = { crosshairX = nil, crosshairY = nil, lockedTargetId = nil }
}

-- Configuration file paths
local configFile = "ussNJNGDWconfig.txt"
local friendlyIDFile = "friendly_ids.txt"

-- Function to read configuration from a file
local function readConfig(filename)
    if not fs.exists(filename) then
        print("Configuration file '" .. filename .. "' does not exist. Creating it.")
        local file = fs.open(filename, "w")
        
        print("Input your resolution eg.(1920,1080), default: 3440,1440")
        local resolution = io.read()
        resolution = resolution == "" and "3440,1440" or resolution
        file.writeLine("resolution=" .. resolution)
        
        print("Input your FOV eg.(70), default: 70")
        local fov = io.read()
        fov = fov == "" and "70" or fov
        file.writeLine("fov=" .. fov)
        
        print("Input your GUI scale, default: 4")
        local guiScale = io.read()
        guiScale = guiScale == "" and "4" or guiScale
        file.writeLine("guiScale=" .. guiScale)
        
        print("Input your mode 1:System in world space 2:System on vs ship. Default: 1")
        local mode = io.read()
        mode = mode == "" and "1" or mode
        file.writeLine("mode=" .. mode)
        
        print("Input your ID, default: MegiRicky")
        local userID = io.read()
        userID = userID == "" and "MegiRicky" or userID
        file.writeLine("userID=" .. userID)
        
        if mode == "1" then
            print("Input the location of the computer (X,Y,Z)")
            local source = io.read()
            source = source == "" and "0,0,0" or source
            file.writeLine("source=" .. source)
        else
            file.writeLine("source=ship")
        end

        -- Adding channel configuration
        print("Input the Port Side Back CIWS channel, default: 800")
        local psBackChannel = io.read()
        psBackChannel = psBackChannel == "" and "800" or psBackChannel
        file.writeLine("psBackChannel=" .. psBackChannel)

        print("Input the Port Side Front CIWS channel, default: 801")
        local psFrontChannel = io.read()
        psFrontChannel = psFrontChannel == "" and "801" or psFrontChannel
        file.writeLine("psFrontChannel=" .. psFrontChannel)

        print("Input the Starboard Side Back CIWS channel, default: 802")
        local ssBackChannel = io.read()
        ssBackChannel = ssBackChannel == "" and "802" or ssBackChannel
        file.writeLine("ssBackChannel=" .. ssBackChannel)

        print("Input the Starboard Side Front CIWS channel, default: 803")
        local ssFrontChannel = io.read()
        ssFrontChannel = ssFrontChannel == "" and "803" or ssFrontChannel
        file.writeLine("ssFrontChannel=" .. ssFrontChannel)

        file.close()
    end
    
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

-- Load configuration
local config = readConfig(configFile)
screenWidth, screenHeight = config.resolution:match("(%d+),(%d+)")
screenWidth = tonumber(screenWidth)
screenHeight = tonumber(screenHeight)
fov = tonumber(config.fov)
GUIscale = tonumber(config.guiScale)
local mode = tonumber(config.mode)
userID = config.userID
friendlyIDs = readFriendlyIDs(friendlyIDFile)
local magicNumber = GUIscale/4

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
print("Resoultion: "..screenWidth..", "..screenHeight)
if screenWidth == 3440 and screenHeight == 1440 then widthMagic = 1.125 else widthMagic = 0.92 end
ar.setRelativeMode(true,screenWidth * 4,screenHeight*4)

local psBackChannel = tonumber(config.psBackChannel)
local psFrontChannel = tonumber(config.psFrontChannel)
local ssBackChannel = tonumber(config.ssBackChannel)
local ssFrontChannel = tonumber(config.ssFrontChannel)
if modem then
    modem.open(psBackChannel)
    modem.open(psFrontChannel)
    modem.open(ssBackChannel)
    modem.open(ssFrontChannel)
end

-- Function to check if an ID is in the list of friendly IDs
local function isFriendly(id)
    for _, friendlyID in ipairs(friendlyIDs) do
        if id == friendlyID then
            return true
        end
    end
    return false
end

local function calculateSpeed(pos1, pos2, deltaTime)
    if pos1 and pos2 then
        local dx = pos2[1] - pos1[1]
        local dy = pos2[2] - pos1[2]
        local dz = pos2[3] - pos1[3]
        return math.sqrt(dx^2 + dy^2 + dz^2) / deltaTime
    end
    return 0
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

    local screenDepth = screenWidth / 2 * math.tan(math.rad(fov / widthMagic / 2))
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
--Function to display pitch and yaw of a cannon
local function angleToScreen(pitch,yaw,userPos,lookVector)

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
            if dx < 800/GUIscale and dy < 800/GUIscale then
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
local function renderElements(elements, cannonHitPos, pInfo)
    local tasks = {}
    for _, element in ipairs(elements) do
        table.insert(tasks, function()
            local color = element.color  -- Default color

            -- Check if the element's ID matches any locked target ID in the ciwsData
            for ciwsKey, ciwsInfo in pairs(ciwsData) do
                if ciwsInfo.lockedTargetId and element.id == ciwsInfo.lockedTargetId then
                    color = 0xFF0000  -- Red color for locked target
                    break  -- Stop checking further if a match is found
                end
            end

            ar.horizontalLineWithId("frame_top_" .. element.id, element.screenX - element.frameSize, element.screenX + element.frameSize, element.screenY - element.frameSize, color)
            ar.horizontalLineWithId("frame_bottom_" .. element.id, element.screenX - element.frameSize, element.screenX + element.frameSize, element.screenY + element.frameSize, color)
            ar.verticalLineWithId("frame_left_" .. element.id, element.screenX - element.frameSize, element.screenY - element.frameSize, element.screenY + element.frameSize, color)
            ar.verticalLineWithId("frame_right_" .. element.id, element.screenX + element.frameSize, element.screenY - element.frameSize, element.screenY + element.frameSize, color)

            if element.renderInfo then
                ar.drawString("dist: " .. element.distance, element.screenX - 15, element.screenY - 200 / GUIscale, color)
                ar.drawString("mass: " .. math.floor(element.mass / 1000) .. "k", element.screenX - 15, element.screenY - 340 / GUIscale, color)
                ar.drawString("speed: " .. element.speed, element.screenX - 15, element.screenY - 480 / GUIscale, color)
                ar.drawString("id: " .. element.id, element.screenX - 15, element.screenY - 620 / GUIscale, color)
            end
        end)
    end
    parallel.waitForAll(table.unpack(tasks))
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == psBackChannel then
                ciwsData.psBack.lockedTargetId = message.lockedTargetId
                ciwsData.psBack.crosshairX = message.screenX
                ciwsData.psBack.crosshairY = message.screenY
            elseif channel == psFrontChannel then
                ciwsData.psFront.lockedTargetId = message.lockedTargetId
                ciwsData.psFront.crosshairX = message.screenX
                ciwsData.psFront.crosshairY = message.screenY
            elseif channel == ssBackChannel then
                ciwsData.ssBack.lockedTargetId = message.lockedTargetId
                ciwsData.ssBack.crosshairX = message.screenX
                ciwsData.ssBack.crosshairY = message.screenY
            elseif channel == ssFrontChannel then
                ciwsData.ssFront.lockedTargetId = message.lockedTargetId
                ciwsData.ssFront.crosshairX = message.screenX
                ciwsData.ssFront.crosshairY = message.screenY
            end
            -- Add more conditions if crosshair positions are also transmitted
        else
            sleep()
        end
    end
end

local function main()
    local pInfo = {}
    while true do
        local playerList = radar.scanForPlayers(1000)
        if cannonHitPos then
            print("recieved")
        end
        print(textutils.serialize(ciwsData))
        
        for _, player in ipairs(playerList) do
            local playerName = player.nickname
            local playerPosition = player.pos
            local lookVector = player.look_angle  -- Assuming this contains vector information
        
            if player.nickname == userID then
                -- Calculate the camera position
                local lx, ly, lz = lookVector[1], lookVector[2], lookVector[3]
                local radiansYaw = math.atan2(lz, lx)
                local radiansPitch = math.asin(-ly)
                local cameraDistance = 0  -- Distance behind the player for the camera
                local offsetX = cameraDistance * math.cos(radiansPitch) * math.sin(radiansYaw)
                local offsetY = cameraDistance * math.sin(radiansPitch)
                local offsetZ = cameraDistance * math.cos(radiansPitch) * math.cos(radiansYaw)
        
                local cameraPos = {
                    playerPosition[1] + offsetX,
                    playerPosition[2] + offsetY,
                    playerPosition[3] + offsetZ
                }
        
                pInfo = {
                    nickname = player.nickname,
                    pos = cameraPos,  -- Using the calculated third-person camera position
                    lookVector = lookVector  -- Maintaining the original look vector
                }
            end
        end
        
        
        if pInfo.nickname then
            local objectList = radar.scanForShips(10000)
            ar.clear()

            local elements = {}
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
                            color = 0xff5600 --missile coming, high threat
                            if speaker then
                                speaker.playNote("Bit",10,18)
                            end
                        else
                            color = 0xFFFF00 --potential threat
                        end
                    else
                        color = 0x00FF00 --low mass low speed, low threat
                    end
                elseif object.mass < 1000000 then
                    color = 0xfff700 --Medium sized vehicle, fighter jet, tanks, helicopter
                else
                    color = 0xffc300 --Large sized vehicle, ships, strategic bomber
                end
                        

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
                        renderInfo = true
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

            renderElements(filteredElements, cannonHitPos, pInfo)
        end

        sleep(0.05)
    end
end

local function hitMark()
    while true do
        if cannonHitPos and modem then
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
            if cannonHitPos[4] == "coordinate" then
                if cannonHitPos then
                    objX, objY, objZ = cannonHitPos[1], cannonHitPos[2], cannonHitPos[3]
                end
                if objX and objY and objZ then
                    local screenX, screenY = projectToScreen(objX, objY, objZ, pInfo.pos, pInfo.lookVector)
                    if screenX and screenY then
                        ar.clearElement("CrossHair")
                        ar.drawStringWithId("CrossHair","X", screenX, screenY, 0xFF0000)
                    end
                end
            elseif cannonHitPos[3] == "degree" then
                print("pitch: "..cannonHitPos[1])
                print("yaw: "..cannonHitPos[2])
                local screenX, screenY = angleToScreen(cannonHitPos[1],cannonHitPos[2],pInfo.pos,pInfo.lookVector)
                if screenX and screenY then
                    ar.clearElement("CrossHair")
                    ar.drawStringWithId("CrossHair","X", screenX, screenY, 0xFF0000)
                end
            end
        end
        sleep(0.05)
    end
end

local function generateObjectKey(object)
    if not object or not object.pos then
        return nil
    end
    -- Generate a unique key using entity type and position; assumes that no two entities of the same type will have the same position simultaneously.
    return object.entity_type .. ":" .. table.concat(object.pos, ",")
end

local function missileWarning()
    local previousPositions = {}
    while true do
        local objectList = radar.scanForEntities(600)
        -- Initial scan to capture positions
        local initialPositions = {}
        for _, object in ipairs(objectList) do
            if object and (object.entity_type == "entity.tallyho.laser_missile" or object.entity_type == "entity.smallarm.at_rocket") then
                if object.pos and #object.pos == 3 then
                    initialPositions[object.entity_type .. table.concat(object.pos, ":")] = object.pos
                end
            end
        end

        sleep(0.1)  -- Short delay to measure displacement

        objectList = radar.scanForEntities(600)  -- Second scan to calculate speed
        local currentPositions = {}
        for _, object in ipairs(objectList) do
            if object and (object.entity_type == "entity.tallyho.laser_missile" or object.entity_type == "entity.smallarm.at_rocket") then
                if object.pos and #object.pos == 3 then
                    local key = object.entity_type .. table.concat(object.pos, ":")
                    currentPositions[key] = object.pos
                    local previousPos = initialPositions[key]
                    if previousPos then
                        local speed = calculateSpeed(previousPos, object.pos, 0.1)
                        if speed > 10 then  -- Check if speed exceeds threshold
                            local objX, objY, objZ = object.pos[1], object.pos[2], object.pos[3]
                            local missileVector = {x = objX - previousPos[1], y = objY - previousPos[2], z = objZ - previousPos[3]}
                            local toPlayerVector = {x = pInfo.pos[1] - objX, y = pInfo.pos[2] - objY, z = pInfo.pos[3] - objZ}
                            local dotProduct = missileVector.x * toPlayerVector.x + missileVector.y * toPlayerVector.y + missileVector.z * toPlayerVector.z
                            if dotProduct then  -- Missile is moving towards the player
                                local angle = math.deg(math.atan2(missileVector.z, missileVector.x) - math.atan2(toPlayerVector.z, toPlayerVector.x))
                                local direction = ((angle + 360) % 360) / 30
                                local clockDirection = math.floor(direction + 1)
                                if clockDirection == 0 then clockDirection = 12 end
                                ar.drawString("Missile incoming from " .. clockDirection .. " o'clock", screenWidth / 2, screenHeight / 2, 0xFF0000)
                                if speaker then
                                    speaker.playSound("entity.lightning_bolt.thunder", 1.0)
                                end
                            end
                        end
                    end
                end
            end
        end

        previousPositions = currentPositions
        sleep(0.1)  -- Delay before the next round of scanning
    end
end

local function renderCIWSData()
    while true do
        if ciwsData then
            for key, data in pairs(ciwsData) do
                local crosshairId = key .. "_crosshair"
                local targetId = key .. "_target"

                -- Clear previous drawings to avoid overlap and ensure updates are visible
                ar.clearElement(crosshairId)
                ar.clearElement(targetId)

                if data.crosshairX and data.crosshairY then
                    ar.drawStringWithId(crosshairId, "X", data.crosshairX, data.crosshairY, 0xFFFFFF)  -- Assuming white for crosshairs
                end
            end
        end
        sleep(0.05)  -- Update at 20 FPS
    end
end



-- Main loop
parallel.waitForAny(
    modemMessage,
    main,
    hitMark,
    missileWarning,
    renderCIWSData
)
