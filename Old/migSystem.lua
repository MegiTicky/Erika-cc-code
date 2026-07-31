local radar = peripheral.find("sp_radar")
local ar = peripheral.find("arController")
local raycaster = peripheral.find("raycaster")

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
local projectionDistance = 30
local currentPitch, currentYaw = 0,0
local lockedTarget = nil
local elements = {}
local pInfo = {}
--Bombsight
local euler_mode = true
local max_distance = 2000
local immediate_execution = true
local check_for_blocks_in_world = true
local gravity = 10
local time_step = 0.1 -- seconds, time step for simulation
local max_simulation_time = 100 -- seconds, max time for the simulation

local Kp = 0.3  -- Proportional gain
local Ki = 0.1  -- Integral gain
local Kd = 0.05  -- Derivative gain

local controls = {cannonControlMode = "mouseAim"}


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

-- Update the main function to remove target locking and aiming
local function main()
    while true do
        local playerList = radar.scanForPlayers(1000)
        if cannonHitPos then

        end
        
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

        end

        if ship.getVelocity() then
            local velocity = ship.getVelocity()
            local speed = math.floor(math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)) * 1.94384449

            ar.drawStringWithId("AimCrossHair","speed: "..speed.." knots", 100, 500, 0xFFFFFF)
        end


        sleep(0.05) -- Adjust the sleep time as needed to balance performance and responsiveness
    end
end

local function calculateBombLandingPosition(ship_pos, ship_velocity, release_height)
    local time = 0
    local bomb_pos = {ship_pos.x, ship_pos.y, ship_pos.z} -- Starting at ship's position
    local bomb_velocity = {ship_velocity.x, ship_velocity.y, ship_velocity.z} -- Initial velocity same as the ship's velocity

    while time < max_simulation_time do
        -- Update the bomb's position based on current velocity
        bomb_pos[1] = bomb_pos[1] + bomb_velocity[1] * time_step -- X position
        bomb_pos[2] = bomb_pos[2] + bomb_velocity[2] * time_step -- Y position (height)
        bomb_pos[3] = bomb_pos[3] + bomb_velocity[3] * time_step -- Z position

        -- Update the bomb's vertical velocity due to gravity
        bomb_velocity[1] = bomb_velocity[1] * 0.975
        bomb_velocity[2] = bomb_velocity[2] - gravity * time_step -- Y velocity decreases due to gravity
        bomb_velocity[3] = bomb_velocity[3] * 0.975

        -- Check if bomb hits the ground (Y position <= 0)
        if bomb_pos[2] <= 0 then
            break
        end

        time = time + time_step
    end

    return bomb_pos -- The final position where the bomb hits the ground
end

local function hitMark()
    while true do
        if raycaster then
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

            local result = {}
            local shipPitch = math.deg(ship.getRoll())
            local shipLocation = ship.getWorldspacePosition()
            local shipVelocity = ship.getVelocity()
            var1 = 0
            var2 = math.rad(-shipPitch)
            result = raycaster.raycast(max_distance, {var1, var2}, true, true)

            if result.is_block and result.block_type ~= "block.minecraft.air" then
                print("Block hit at:")
                print("Hit position: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
                print("Block type: " .. result.block_type)
                print("Distance: " .. result.distance)
            elseif result.is_entity then
                print("Entity hit at:")
                print("Hit position: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
                print("Entity ID: " .. result.id)
                print("Entity type: " .. result.descriptionId)
                print("Distance: " .. result.distance)
            elseif result.ship_id then
                print("No hit detected within " .. max_distance .. " blocks.")
                print("Hit position: "..result.hit_pos[1].." , "..result.hit_pos[2].." , "..result.hit_pos[3])
            end

            if result.hitpos and result.hit_pos[2] < 0 then
                result.hit_pos[2] = 0
                result.distance = shipLocation.y - 0
            end
            
            local bombLandingPos = calculateBombLandingPosition(shipLocation, shipVelocity, result.distance)

            if bombLandingPos then
                objX, objY, objZ = bombLandingPos[1], bombLandingPos[2], bombLandingPos[3]
            end
            if objX and objY and objZ then
                local screenX, screenY = projectToScreen(objX, objY, objZ, pInfo.pos, pInfo.lookVector)
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
    hitMark
)
