-- Variable initialization
local radar = peripheral.find("sp_radar")
local ar = peripheral.find("arController")
local modem = peripheral.find("modem")
local router = peripheral.find("redrouter")
local bal = peripheral.find("ballistic_accelerator")

local cannonHitPosChannel = nil
local statusChannel = nil
print("Input the channel you want to use, default: 700")
cannonHitPosChannel = io.read()
if cannonHitPosChannel == "" then
    cannonHitPosChannel = 700
end
cannonHitPosChannel = tonumber(cannonHitPosChannel)

print("Input the status channel you want to use, default: 800")
statusChannel = io.read()
if statusChannel == "" then
    statusChannel = 800
end
statusChannel = tonumber(statusChannel)

local cannonSource
if modem then
    modem.open(cannonHitPosChannel)
    modem.open(statusChannel)
end

local screenWidth, screenHeight, fov, GUIscale
local sourceX, sourceY, sourceZ = 0,0,0
local source = {}
local userID
local friendlyIDs
local widthMagic = 1.125
local projectionDistance = 200
local currentPitch, currentYaw = 0,0
local lockedTarget = nil
local elements = {}
local pInfo = {}
local cannonHitPos = {}
local pitchAdjustments = "1"
local projectileSpeed = 120

-- Configuration file paths
local configFile = "ciwsNGDWconfig.txt"
local friendlyIDFile = "friendly_ids.txt"

-- Function to read configuration from a file
local function readConfig(filename)
    if not fs.exists(filename) then
        print("Configuration file '" .. filename .. "' does not exist. Creating it.")
        local file = fs.open(filename, "w")
        
        print("Input your resolution eg.(1920,1080), default: 3440,1440")
        local resolution = io.read()
        if resolution == "" then
            resolution = "3440,1440"
        end
        file.writeLine("resolution=" .. resolution)
        
        print("Input your FOV eg.(70), default: 70")
        local fov = io.read()
        if fov == "" then
            fov = "70"
        end
        file.writeLine("fov=" .. fov)
        
        print("Input your GUI scale, default: 4")
        local guiScale = io.read()
        if guiScale == "" then
            guiScale = "4"
        end
        file.writeLine("guiScale=" .. guiScale)
        
        print("Input your mode 1:System in world space 2:System on vs ship. Default: 1")
        local mode = io.read()
        if mode == "" then
            mode = "1"
        end
        file.writeLine("mode=" .. mode)
        
        print("Input your ID, default: MegiRicky")
        local userID = io.read()
        if userID == "" then
            userID = "MegiRicky"
        end
        file.writeLine("userID=" .. userID)
        
        if mode == "1" then
            print("Input the location of the computer (X,Y,Z)")
            local source = io.read()
            if source == "" then source = "0,0,0" end
            file.writeLine("source=" .. source)
        else
            file.writeLine("source=ship")
        end


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
print("Resolution: " .. screenWidth .. ", " .. screenHeight)
if screenWidth == 3440 and screenHeight == 1440 then widthMagic = 1.125 else widthMagic = 0.92 end
ar.setRelativeMode(true, screenWidth * 4, screenHeight * 4)

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

-- Function to render elements in parallel
local function renderElements(elements, cannonHitPos, pInfo, lockedTarget)
    local tasks = {}
    for _, element in ipairs(elements) do
        table.insert(tasks, function()
            local color = element.color
            if lockedTarget and element.id == lockedTarget.id then
                color = 0xFF0000 -- Red color for locked target
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

local function lockHighestThreatTarget(elements, centerX, centerY, radius)
    local highestThreat = nil
    local highestThreatLevel = -1

    for _, element in ipairs(elements) do
        if element.id then
            local dx = element.screenX - centerX / magicNumber
            local dy = element.screenY - centerY / magicNumber
            local distance = math.sqrt(dx * dx + dy * dy)
            
            if distance <= radius / GUIscale then
                local threatLevel = element.mass -- Use mass as a proxy for threat level
                if isFriendly(element.id) then threatLevel = -1 end
                if threatLevel > highestThreatLevel then
                    highestThreat = element
                    highestThreatLevel = threatLevel
                end
            end
        end
    end

    return highestThreat
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == cannonHitPosChannel then
                cannonHitPos = message
            end
        else
            sleep()
        end
    end
end

local function aimCannon(targetPos,targetVel,sourceX,sourceY,sourceZ,currentPitch,currentYaw)
    if sourceX and sourceY and sourceZ and currentPitch and currentYaw then
        
        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local estimateTime = distance / (6*20) / 2
        local estimateX = targetPos.x + targetVel.x * estimateTime
        local estimateY = targetPos.y + targetVel.y * estimateTime
        local estimateZ = targetPos.z + targetVel.z * estimateTime

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = yaw + 180

        if bal then
            local sourceTemp = {sourceX,sourceY,sourceZ}
            local targetTemp = {estimateX,estimateY,estimateZ}
            preCompensatedPitchTable = bal.calculatePitch(sourceTemp, targetTemp, projectileSpeed, 8, -30, 60, 0.05, 0.99, 1, 1000000, 5, 20, false)
            print(textutils.serialize(preCompensatedPitchTable))
        end

        pitch = pitch + preCompensatedPitchTable[1][3]
        print(" targetPos: "..math.floor(targetPos.x).." , "..math.floor(targetPos.y).." , "..math.floor(targetPos.z))
        print(" source: "..sourceX.." , "..sourceY.." , "..sourceZ.." , ")
        print("Current: "..math.floor(currentPitch).." , "..math.floor(currentYaw))
        print("target: "..math.floor(pitch).." , "..math.floor(yaw))

        local deltaYaw = yaw - currentYaw
        local deltaYaw = (deltaYaw + 180) % 360 - 180
        local deltaPitch = pitch - currentPitch
        --turning
        local yaw_tolerance = 0.5
        local pitch_tolerance = 0.5
        if math.abs(deltaYaw) > yaw_tolerance then
            if deltaYaw < 0 then
                print("Turning left")
                router.setOutput("right", false)
                if math.abs(deltaYaw) < 5 then
                    local turnTime = math.abs(deltaYaw) / 24
                    print("turnTime: "..turnTime)
                    router.setOutput("left", true)
                    sleep(turnTime)
                    router.setOutput("left",false)
                else
                    router.setOutput("left", true)
                end
            elseif deltaYaw > 0 then
                print("Turning right")
                router.setOutput("left", false)
                if math.abs(deltaYaw) < 5 then
                    local turnTime = math.abs(deltaYaw) / 24
                    router.setOutput("right", true)
                    sleep(turnTime)
                    router.setOutput("right",false)
                else
                    router.setOutput("right", true)
                end
            end
        else
            router.setOutput("right", false)
            router.setOutput("left", false)
        end

        if math.abs(deltaPitch) > pitch_tolerance then
            if deltaPitch > 0 then
                print("Adjusting pitch up")
                router.setOutput("front", false)
                if math.abs(deltaPitch) < 5 then
                    local turnTime = math.abs(deltaPitch) / 24
                    router.setOutput("top", true)
                    sleep(turnTime)
                    router.setOutput("top", false)
                else
                    router.setOutput("top", true)
                end
            else
                print("Adjusting pitch down")
                router.setOutput("top", false)
                if math.abs(deltaPitch) < 5 then
                    local turnTime = math.abs(deltaPitch) / 24
                    router.setOutput("front", true)
                    sleep(turnTime)
                    router.setOutput("front", false)
                else
                    router.setOutput("front", true)
                end
            end
        else
            router.setOutput("front", false)
            router.setOutput("top", false)
        end
    end
end

local function targetLockAndAim()
    while true do
        currentPitch,currentYaw = cannonHitPos[6],cannonHitPos[7]
        source = cannonHitPos[5]
        if pInfo.nickname then

            lockedTarget = lockHighestThreatTarget(elements, screenWidth / 2, screenHeight / 2, 1000)
            if lockedTarget then
                print("Locked target ID: " .. lockedTarget.id)
                modem.transmit(statusChannel, statusChannel, {lockedTargetId = lockedTarget.id})
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
                    print(textutils.serialize(lookTarget.pos))
                    aimCannon(lockedTarget.pos,lockedTarget.velocity,source.x, source.y, source.z,currentPitch, currentYaw)
                end
            else
                lookTarget = mouseAim(pInfo.pos, pInfo.lookVector)
                
                print(source)
                aimCannon(lookTarget, {x=0, y=0, z=0}, source.x, source.y, source.z, currentPitch, currentYaw)
            end
        end
        sleep(0.01)
    end
end

-- Update the main function to remove target locking and aiming
local function main()
    while true do
        local playerList = radar.scanForPlayers(1000)

        if cannonHitPos then
            print("received")
        end
        for _, player in ipairs(playerList) do
            local playerName = player.nickname
            local playerPosition = player.pos
            local lookAngle = player.look_angle
            print(player.nickname)
            if player.nickname == userID then
                print(player.nickname)
                pInfo = {
                    nickname = player.nickname,
                    pos = player.pos,
                    lookVector = lookAngle
                }
            end
        end

        if true then
            local objectList = radar.scanForShips(10000)
            ar.clear()

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

        sleep(0.05) -- Adjust the sleep time as needed to balance performance and responsiveness
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
                        if lockedTarget then
                            modem.transmit(statusChannel, statusChannel, {screenX = screenX, screenY = screenY, lockedTargetId = lockedTarget.id})
                        else
                            modem.transmit(statusChannel, statusChannel, {screenX = screenX, screenY = screenY})
                        end
                    end
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
        end
        sleep()
    end
end

-- Main loop
parallel.waitForAny(
    modemMessage,
    main,
    hitMark,
    targetLockAndAim
)
