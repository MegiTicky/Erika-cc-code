local radar = peripheral.find("sp_radar")
local ar = peripheral.find("arController")
local modem = peripheral.wrap("right")
local yawMotor = peripheral.wrap("back")
for i = 0, 200 do  -- Assuming there are 2 Create_RotationSpeedController peripherals
    pitchMotor = peripheral.wrap("Create_RotationSpeedController_"..tostring(i))
    if pitchMotor then
        break
    end
end
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

local cannonControlMode = "mouseAim"

local screenWidth, screenHeight, fov, GUIscale
local sourceX, sourceY, sourceZ = 0,0,0
local source = {}
local userID
local friendlyIDs
local friendlyIDFile = "friendly_ids.txt"
local widthMagic = 1.125
local projectionDistance = 30
local currentPitch, currentYaw = 0,0
local lastCurrentPitch, lastCurrentYaw = 0,0
local lockedTarget = nil
local elements = {}
local pInfo = {}
local cannonHitPos = {}
local pitchAdjustments = "1"
local lastYawUpdateTime = 0
local lastPitchUpdateTime = 0
local updateInterval = 0.01
local projectileSpeed = 330
local g = 0.04
local vm

local yawErrorSum = 0
local lastYawError = 0
local pitchErrorSum = 0
local lastPitchError = 0
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0
local pitchError = 0
local pitchIntegral = 0
local pitchPrevError = 0
local lastTime = os.clock()

local Kp_yaw = 0.25
local Ki_yaw = 0.05
local Kd_yaw = 0.012
local Kp_pitch = 0.25
local Ki_pitch = 0.05
local Kd_pitch = 0.012
local dt = 0.1

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
sleep(2)
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

local function mouseAim(userPos, lookVector)
    lookTarget = {}

    local lx, ly, lz = lookVector[1], lookVector[2], lookVector[3]
    local playerYaw = math.deg(math.atan2(lz, lx))
    local playerPitch = math.deg(math.asin(-ly)) - 25
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

local function PIDController(Kp, Ki, Kd, error, integral, prevError, dt)
    -- Calculate the proportional, integral, and derivative components
    local proportional = Kp * error
    integral = integral + error * dt  -- Accumulate the error for the integral term
    local derivative = (error - prevError) / dt
    
    -- Calculate the PID output
    local output = proportional + (Ki * integral) + (Kd * derivative)

    -- Return the PID output, updated integral, and current error
    return output, integral, error
end

-- Yaw control function using PID
local function yawControl(deltaYaw, currentYaw)
    if math.abs(deltaYaw) then  -- Only adjust if yaw error is significant
        -- PID controller for yaw
        local yawSpeed, yawIntegral, yawPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, deltaYaw, yawIntegral, yawPrevError, dt)

        -- Constrain the yaw speed to prevent runaway spinning
        yawSpeed = math.max(-128, math.min(128, yawSpeed))

        print("deltaYaw: " .. deltaYaw)
        print("yawSpeed: " .. yawSpeed)

        -- Set motor speed based on PID output
        yawMotor.setTargetSpeed(-yawSpeed)
    else
        yawMotor.setTargetSpeed(0)  -- Stop motor if error is too small
    end
end

local function pitchControl(deltaPitch, currentPitch)
    if math.abs(deltaPitch) then  -- Only adjust if yaw error is significant
        -- PID controller for yaw
        local pitchSpeed, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, deltaPitch, pitchIntegral, pitchPrevError, dt)

        -- Constrain the yaw speed to prevent runaway spinning
        pitchSpeed = math.max(-16, math.min(16, pitchSpeed))

        print("deltaPitch: " .. deltaPitch)
        print("pitchSpeed: " .. pitchSpeed)

        -- Set motor speed based on PID output
        pitchMotor.setTargetSpeed(pitchSpeed*8)
    else
        pitchMotor.setTargetSpeed(0)  -- Stop motor if error is too small
    end
end

local function aimCannon(targetPos, targetVel, sourceX, sourceY, sourceZ, currentPitch, currentYaw)
    if sourceX and sourceY and sourceZ and currentPitch and currentYaw then
        local currentTime = os.clock()
        local dt = currentTime - lastTime
        if dt == 0 then return end  -- Prevent division by zero
        lastTime = currentTime

        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local estimateTime = distance / (340 * 2)  -- assuming velocity units and time units need adjustment
        local estimateX = targetPos.x + targetVel.x * estimateTime
        local estimateY = targetPos.y + targetVel.y * estimateTime
        local estimateZ = targetPos.z + targetVel.z * estimateTime

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        -- Adjust pitch based on distance adjustments

        pitch = pitch + findBestPitch(estimateX, estimateY, estimateZ, sourceX, sourceY, sourceZ, projectileSpeed, g, 0.99, 0.0028, projectileSpeed)
        pitch = math.max(-15, math.min(75, pitch))

        local deltaYaw = (yaw - currentYaw + 180) % 360 - 180
        local deltaPitch = pitch - currentPitch

        -- Turning and pitch adjustment logic
        parallel.waitForAll(
            function() yawControl(deltaYaw, currentYaw) end,
            function() pitchControl(deltaPitch, currentPitch) end
        )

        lastCurrentYaw = currentYaw
        lastCurrentPitch = currentPitch
    end
end

local function targetLockAndAim()
    while true do
        currentPitch,currentYaw = cannonHitPos[6],cannonHitPos[7]
        source = cannonHitPos[5]
        if controls.cannonControlMode == "mouseAim" then
            currentPitch, currentYaw = cannonHitPos[6], cannonHitPos[7]
            source = cannonHitPos[5]
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
                        aimCannon(lockedTarget.pos, lockedTarget.velocity, source.x, source.y, source.z, currentPitch, currentYaw)
                    end
                else
                    lookTarget = mouseAim(pInfo.pos, pInfo.lookVector)
                    if loadout, 
                    aimCannon(lookTarget, {x=0, y=0, z=0}, source.x, source.y, source.z, currentPitch, currentYaw)
                end
            end
        else
            
        end
        sleep()
    end
end

local function manualCannonControl()
    while true do
        if controls.cannonControlMode == "manual" then
            if controls then
                -- Control yaw and pitch manually with arrow keys
                if controls.cannonUp then
                    -- Increase pitch
                    pitchMotor.setTargetSpeed(12)
                elseif controls.cannonDown then
                    -- Decrease pitch
                    pitchMotor.setTargetSpeed(-12)
                else
                    pitchMotor.setTargetSpeed(0)
                end
                if controls.cannonLeft then
                    -- Turn left
                    yawMotor.setTargetSpeed(2)
                elseif controls.cannonRight then
                    -- Turn right
                    yawMotor.setTargetSpeed(-2)
                else
                    yawMotor.setTargetSpeed(0)
                end
            else
                pitchMotor.setTargetSpeed(0)
                yawMotor.setTargetSpeed(0)
            end
            sleep()
        else
            sleep() -- Sleep for a short time if not in manual mode
        end
    end
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
            local AimTarget = mouseAim(pInfo.pos, pInfo.lookVector)
            local screenX, screenY = projectToScreen(AimTarget.x, AimTarget.y, AimTarget.z, pInfo.pos, pInfo.lookVector)
            if screenX and screenY then
                ar.drawStringWithId("AimCrossHair","X", screenX+20, screenY+80, 0xFFFFFF)
            end
        end

        if ship.getVelocity() then
            local velocity = ship.getVelocity()
            local speed = math.floor(math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2))

            ar.drawStringWithId("AimCrossHair","speed: "..speed, 100, 500, 0xFFFFFF)
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
    targetLockAndAim,
    manualCannonControl
)
