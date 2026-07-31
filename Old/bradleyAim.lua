local radar = peripheral.find("sp_radar")
local ar = peripheral.find("arController")
local modem = peripheral.wrap("right")
local yawMotor = peripheral.find("Create_RotationSpeedController")
local cannonSourceChannel = 701
local controlChannel = 500
local holo = peripheral.find("hologram")

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
local projectileSpeed = 240
local g = 0.025
local cd = 0.99
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

local Kp_yaw = 0.8
local Ki_yaw = 0
local Kd_yaw = 0.015
local Kp_pitch = 0.25
local Ki_pitch = 0.05
local Kd_pitch = 0.012
local dt = 0.1

local turnFactor = 0

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
        
        userID = askUser("Input your ID", "MegiRicky")
        file.writeLine("userID=" .. userID)

        -- Integrating channel number into the config
        cannonHitPosChannel = askUser("Input the cannon data channel number", "700")
        file.writeLine("cannonHitPosChannel=" .. cannonHitPosChannel)

        controlChannel = askUser("Input the control channel", "500")
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
sleep(0.2)
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

-- Function to render elements
local function renderElements(elements, cannonHitPos, pInfo, lockedTarget)
    if not holo then return end  -- Ensure hologram peripheral is available

    -- Set the background to transparent
    holo.SetClearColor(0x00000000) -- Fully transparent (RGBA: 0,0,0,0)

    local circleRadius = math.min(screenWidth, screenHeight) / 4

    -- Iterate through detected objects and render them on the hologram
    for _, element in ipairs(elements) do
        local color = element.color
        if lockedTarget and element.id == lockedTarget.id then
            color = 0xFF0000FF -- Highlight locked target in red
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

    for pitch = 0, 70, 0.05 do -- Iterate over pitch angles
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

    --prioritize the low-angle solution
    return bestLowPitch
end

local function customProportional(error, Kp)
    -- Nonlinear proportional scaling
    -- Example: Quadratic growth for small errors
    local scaleFactor = 0.3 -- Controls how quickly the value grows for small errors

    local absError = math.abs(error)
    local proportional = Kp * (absError / (1 + scaleFactor * absError)) -- Sigmoid-like growth

    if error < 0 then
        proportional = -proportional -- Preserve the sign of the error
    end

    return math.abs(proportional) * (error < 0 and -1 or 1) -- Cap the value
end

local function PIDController(Kp, Ki, Kd, error, integral, prevError, dt)
    -- Nonlinear proportional term using the custom function
    local proportional = customProportional(error, Kp)

    -- Integral and derivative components
    integral = integral + error * dt
    local derivative = (error - prevError) / dt
    
    -- Calculate the PID output
    local output = proportional + (Ki * integral) + (Kd * derivative)

    -- Return the PID output, updated integral, and current error
    return output, integral, error
end


-- Yaw control function using PID
local function yawControl(deltaYaw, currentYaw)
    if math.abs(deltaYaw) > 0.9 and math.abs(deltaYaw) < 1.2 then
        local yawSpeed, yawIntegral, yawPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, deltaYaw, yawIntegral, yawPrevError, dt)

        if yawSpeed < 0 then
            yawSign = -1
        else
            yawSign = 1
        end
        yawSpeed = 1 * yawSign

        if controls.accelerate or controls.decelerate then
            if controls.turnLeft then
                --turn level -1
                turnFactor = math.min(turnFactor + 5, 42)
            elseif controls.turnRight then
                --turn level 1
                turnFactor = math.max(turnFactor - 5, -42)
            else
                if turnFactor > 3 then 
                   turnFactor = turnFactor - 3
                elseif turnFactor < -3 then
                    turnFactor = turnFactor + 3
                else
                    turnFactor = 0
                end           
            end
        else
            if controls.turnLeft then
                --turn level -2
                turnFactor = math.min(turnFactor + 13, 26)
            elseif controls.turnRight then
                --turn level 2
                turnFactor = math.max(turnFactor - 13, -26)
            else
                if turnFactor > 8 then 
                    turnFactor = turnFactor - 8
                 elseif turnFactor < -8 then
                    turnFactor = turnFactor + 8
                 else
                    turnFactor = 0
                 end        
            end
        end

        if controls.decelerate then
            turnFactor = -turnFactor
        end

        yawSpeed = yawSpeed + turnFactor

        --print("deltaYaw: " .. deltaYaw)
        --print("yawSpeed: " .. yawSpeed)

        -- Set motor speed based on PID output
        yawMotor.setTargetSpeed(-yawSpeed)
    elseif math.abs(deltaYaw) > 0.9 then  -- Only adjust if yaw error is significant
        -- PID controller for yaw
        local yawSpeed, yawIntegral, yawPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, deltaYaw, yawIntegral, yawPrevError, dt)

        -- Constrain the yaw speed to prevent runaway spinning
        yawSpeed = math.max(-32, math.min(32, yawSpeed))

        if controls.accelerate or controls.decelerate then
            if controls.turnLeft then
                --turn level -1
                turnFactor = math.min(turnFactor + 5, 28)
            elseif controls.turnRight then
                --turn level 1
                turnFactor = math.max(turnFactor - 5, -28)
            else
                if turnFactor > 3 then 
                   turnFactor = turnFactor - 3
                elseif turnFactor < -3 then
                    turnFactor = turnFactor + 3
                else
                    turnFactor = 0
                end           
            end
        else
            if controls.turnLeft then
                --turn level -2
                turnFactor = math.min(turnFactor + 13, 26)
            elseif controls.turnRight then
                --turn level 2
                turnFactor = math.max(turnFactor - 13, -26)
            else
                if turnFactor > 8 then 
                    turnFactor = turnFactor - 8
                 elseif turnFactor < -8 then
                    turnFactor = turnFactor + 8
                 else
                    turnFactor = 0
                 end        
            end
        end

        if controls.decelerate then
            turnFactor = -turnFactor
        end

        yawSpeed = yawSpeed + turnFactor

        print("deltaYaw: " .. deltaYaw)
        print("yawSpeed: " .. yawSpeed)

        -- Set motor speed based on PID output
        yawMotor.setTargetSpeed(-yawSpeed)

    else
        yawMotor.setTargetSpeed(0)  -- Stop motor if error is too small
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

        local shipVelocity = ship.getVelocity()

        local estimateTime = distance / (projectileSpeed - 10)  -- assuming velocity units and time units need adjustment
        local estimateX = targetPos.x + (targetVel.x - shipVelocity.x) * estimateTime
        local estimateY = targetPos.y + (targetVel.y - shipVelocity.y) * estimateTime
        local estimateZ = targetPos.z + (targetVel.z - shipVelocity.z) * estimateTime

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        -- Adjust pitch based on distance adjustments

        pitch = pitch + findBestPitch(estimateX, estimateY, estimateZ, sourceX, sourceY, sourceZ, projectileSpeed, g, cd, 0.0028, projectileSpeed)

        local deltaYaw = (yaw - currentYaw + 180) % 360 - 180
        local deltaPitch = pitch - currentPitch

        -- Turning and pitch adjustment logic
        parallel.waitForAll(
            function() yawControl(deltaYaw, currentYaw) end,
            function() 
            modem.transmit(cannonHitPosChannel,0,{pitch = pitch, yaw = yaw}) 
            print("transmiting "..pitch.." at channel "..cannonHitPosChannel)
            end
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
                    if lookTarget then
                        --[[local shipVelocity = ship.getVelocity()
                        source.x = source.x + shipVelocity.x * 0.1
                        source.y = source.y + shipVelocity.y * 0.1
                        source.z = source.z + shipVelocity.z * 0.1]]
                        aimCannon(lookTarget, {x=0, y=0, z=0}, source.x, source.y, source.z, currentPitch, currentYaw)
                    end
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
                print("cannon current pitch"..cannonHitPos[6])
                if controls.cannonUp then
                    -- Increase pitch
                    modem.transmit(cannonHitPosChannel,0,{pitch = cannonHitPos[6] + 1.5, yaw = currentYaw})
                elseif controls.cannonDown then
                    -- Decrease pitch
                    modem.transmit(cannonHitPosChannel,0,{pitch = cannonHitPos[6] - 1.5, yaw = currentYaw})
                else

                end
                if controls.cannonLeft then
                    -- Turn left
                    yawMotor.setTargetSpeed(8)
                elseif controls.cannonRight then
                    -- Turn right
                    yawMotor.setTargetSpeed(-8)
                else
                    yawMotor.setTargetSpeed(0)
                end
            else
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
            --ar.clear()

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
        holo.Flush()
        sleep()
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
                        --ar.clearElement("CrossHair")
                        --ar.drawStringWithId("CrossHair","X", screenX, screenY, 0xFF0000)
                    end
                end
            elseif cannonHitPos[3] == "degree" then
                print("pitch: "..cannonHitPos[1])
                print("yaw: "..cannonHitPos[2])
                local screenX, screenY = angleToScreen(cannonHitPos[1], cannonHitPos[2], pInfo.pos, pInfo.lookVector)
                if screenX and screenY then
                    --ar.clearElement("CrossHair")
                    --ar.drawStringWithId("CrossHair","X", screenX, screenY, 0xFF0000)
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
