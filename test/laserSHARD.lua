local radar = peripheral.find("sp_radar")
local modem = peripheral.find("modem")

local friendlyIDs
local friendlyIDFile = "friendly_ids.txt"
local scanInterval = 0.01

local mode = "auto" --Auto targeting mode, target the cloeset target
local redstoneTimeout = 30
local cycleIndex = 1
local lastRedstoneInputTime = os.clock()

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

local Kp_yaw = 7
local Ki_yaw = 0
local Kd_yaw = 0.05
local Kp_pitch = 0.5
local Ki_pitch = 0
local Kd_pitch = 0.01
local dt = 0.1
local dt1,dt2
local accelerationFactor = 0.2
local velocityFactor = 1

local spreadYawRange = 1 -- Max spread angle for yaw (in degrees)
local spreadPitchRange = 1 -- Max spread angle for pitch (in degrees)

local controls = {}

local cannon = peripheral.find("cbc_cannon_mount")
if not(cannon) then
    cannon = peripheral.find("cbcmf_compact_cannon_mount")
end

print("press enter to assemble cannons")
cannon.assemble()

local function readFriendlyIDs(filename)
    if not fs.exists(filename) then
        print("Friendly IDs file '" .. filename .. "' does not exist. Creating it.")
        local file = fs.open(filename, "w")
        print("Input friendly IDs (player names) separated by commas:")
        local ids = io.read()
        file.write(ids)
        file.close()
    else
        print("Do you want to edit the friendly player id config? (yes/no),press enter to skip")
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
local function saveSettingsToFile(filename, settings)
    local file = fs.open(filename, "w")
    if file then
        file.write(textutils.serialize(settings))
        file.close()
        print("Settings saved to '" .. filename .. "'")
    else
        print("Failed to save settings.")
    end
end

local function loadSettingsFromFile(filename)
    if not fs.exists(filename) then
        return nil
    end

    local file = fs.open(filename, "r")
    local settings = textutils.unserialize(file.readAll())
    file.close()
    return settings
end

local function askForInput(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. "):")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return tonumber(input) or input
    end
end

local function createSettings()
    local settings = {}
    settings.auto = askForInput("Enable auto fire, yes/no note that you need redstone input to anyside of the computer (safetly measure)", "yes") == "yes"
    --settings.velocityFactor = askForInput("Input the velocityFactor", 1)
    settings.controlChannel = askForInput("Input the control channel",500)
    settings.projectileSpeed = askForInput("Input the muzzle velocity number", 160)
    settings.g = askForInput("Input the gravity acceleration per tick", 0.025)
    settings.cd = askForInput("Input the drag per tick", 0.99)
    settings.autoSpread = askForInput("Enable automatic spread, yes/no", "yes") == "yes"
    settings.lengthCorrection = askForInput("Enter cannon source ship length correction", 35)
    settings.heightCorrection = askForInput("Enter cannon source ship height correction", 5)
    settings.widthCorrection = askForInput("Enter the cannon source ship width correction, positive if the ship is at the right side",0)
    settings.limitor = askForInput("Enable pitch yaw limiter, yes/no", "yes") == "yes"
    settings.pitchLowerLimit = askForInput("Ignore the follwing if no limitr. Input the pitch lower limit, default: -10",-10)
    settings.pitchUpperLimit = askForInput("Input the pitch lower limit, default: 90",90)
    settings.yawLowerLimit = askForInput("Input the yaw lower limit, default: -120",-120)
    settings.yawUpperLimit = askForInput("Input the pitch lower limit, default: 120",120)

    return settings
end

local function createPresetSettings()
    local presets = {
        {
            filename = "ussNJport1CIWS_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = 17,
                heightCorrection = 24,
                widthCorrection = -7,
                limitor = true,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = -150,
                yawUpperLimit = 0,
                auto = true
            }
        },
        {
            filename = "ussNJstarboard1CIWS_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = 17,
                heightCorrection = 24,
                widthCorrection = 7,
                limitor = true,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = 0,
                yawUpperLimit = 150,
                auto = true
            }
        },
        {
            filename = "ussNJport2CIWS_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = -14,
                heightCorrection = 21,
                widthCorrection = -6,
                limitor = true,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = -180,
                yawUpperLimit = -20,
                auto = true
            }
        },
        {
            filename = "ussNJstarboard2CIWS_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = -14,
                heightCorrection = 21,
                widthCorrection = 6,
                limitor = true,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = 0,
                yawUpperLimit = 200,
                auto = true
            }
        },
        {
            filename = "type55BowCIWS_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 200,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = 34,
                heightCorrection = 9,
                widthCorrection = 0,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = -120,
                yawUpperLimit = 120,
                limitor = true,
                auto = true
            }
        },
        {
            filename = "type55port1_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 200,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = -42,
                heightCorrection = 12,
                widthCorrection = -8,
                pitchLowerLimit = -20,
                pitchUpperLimit = 90,
                yawLowerLimit = -160,
                yawUpperLimit = -20,
                limitor = true,
                auto = true
            }
        },
        {
            filename = "type55port2_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 200,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = -52,
                heightCorrection = 12,
                widthCorrection = -8,
                pitchLowerLimit = -20,
                pitchUpperLimit = 90,
                yawLowerLimit = -200,
                yawUpperLimit = -20,
                limitor = true,
                auto = true
            }
        },
        {
            filename = "type55starboard1_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 200,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = -42,
                heightCorrection = 12,
                widthCorrection = 8,
                pitchLowerLimit = -20,
                pitchUpperLimit = 90,
                yawLowerLimit = 20,
                yawUpperLimit = 160,
                limitor = true,
                auto = true
            }
        },
        {
            filename = "type55starboard2_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 200,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = -52,
                heightCorrection = 12,
                widthCorrection = 8,
                pitchLowerLimit = -20,
                pitchUpperLimit = 90,
                yawLowerLimit = 20,
                yawUpperLimit = 160,
                limitor = true,
                auto = true
            }
        },
        {
            filename = "ZTZ99CIWS_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = -1,
                heightCorrection = 1.5,
                widthCorrection = 1,
                limitor = true,
                pitchLowerLimit = -12,
                pitchUpperLimit = 90,
                yawLowerLimit = -360,
                yawUpperLimit = 360,
                auto = true
            }
        },
        {
            filename = "YunBao_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = 0,
                heightCorrection = 1.2,
                widthCorrection = 1,
                limitor = true,
                pitchLowerLimit = -8,
                pitchUpperLimit = 90,
                yawLowerLimit = -360,
                yawUpperLimit = 360,
                auto = true
            }
        },
        {
            filename = "EMBTCIWS_settings.txt",
            settings = {
                controlsChannel = 2000,
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = -0.5,
                heightCorrection = 1.5,
                widthCorrection = 1,
                limitor = true,
                pitchLowerLimit = -12,
                pitchUpperLimit = 90,
                yawLowerLimit = -360,
                yawUpperLimit = 360,
                auto = true
            }
        },
        {
            filename = "CIWStruck_settings.txt",
            settings = {
                controlsChannel = 500,
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.03,
                cd = 0.98,
                autoSpread = false,
                lengthCorrection = 0,
                heightCorrection = 0,
                widthCorrection = 0,
                limitor = true,
                auto = false
            }
        }
    }

    for _, preset in ipairs(presets) do
        if true then
            saveSettingsToFile(preset.filename, preset.settings)
            print("Created preset settings: " .. preset.filename)
        end
    end
end

local function handleSettings()
    print("Checking for existing settings...")
    createPresetSettings()

    -- List available settings
    local settingsFiles = fs.list("/")
    local settingsFilesFound = false
    local settingsFilesList = {}

    for _, file in ipairs(settingsFiles) do
        if string.match(file, "_settings.txt") then
            table.insert(settingsFilesList, file)
            settingsFilesFound = true
        end
    end

    if not settingsFilesFound then
        print("No settings found. Please create a new one.")
        local filename = askForInput("Enter a name for the new settings file", "example_settings.txt")
        local settings = createSettings()
        saveSettingsToFile(filename, settings)
        return settings
    else
        print("Available settings:")

        local pageSize = 10 -- Number of settings to display per page
        local totalFiles = #settingsFilesList
        local currentPage = 1
        local totalPages = math.ceil(totalFiles / pageSize)

        while currentPage <= totalPages do
            local startIdx = (currentPage - 1) * pageSize + 1
            local endIdx = math.min(startIdx + pageSize - 1, totalFiles)

            -- Display a batch of settings files
            for i = startIdx, endIdx do
                print(i .. ". " .. settingsFilesList[i])
            end

            if currentPage < totalPages then
                print("\nPress Enter to see more settings...")
                io.read() -- Wait for the user to press Enter
            end

            currentPage = currentPage + 1
        end

        local selection = askForInput("Select an existing setting to load or create a new one (1-" .. totalFiles .. " or new)", "new")

        if selection == "new" then
            local filename = askForInput("Enter a name for the new settings file", "settings.txt")
            local settings = createSettings()
            saveSettingsToFile(filename, settings)
            return settings
        else
            local filename = settingsFilesList[tonumber(selection)]
            local settings = loadSettingsFromFile(filename)
            print("Loaded settings from '" .. filename .. "'")

            local editChoice = askForInput("Do you want to edit this setting? (yes/no)", "no")
            if editChoice == "yes" then
                local newSettings = createSettings()
                saveSettingsToFile(filename, newSettings)
                return newSettings
            else
                return settings
            end
        end
    end
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
    return math.asin(normalizedMatrix[2][3]) -- Extract pitch from the matrix
end
--pitch = math.deg(math.asin(ship.getTransformationMatrix()[2][3]))
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

-- Main execution
local settings = handleSettings()

-- Use the settings in your code
print("Using settings:")
print(textutils.serialize(settings))
velocityFactor = tonumber(askForInput("Input the velocity factor (for compensating physic speed lag)",1))
g = tonumber(settings.g)
lengthCorrection = tonumber(settings.lengthCorrection)
heightCorrection = tonumber(settings.heightCorrection)
widthCorrection = tonumber(settings.widthCorrection)
cd = tonumber(settings.cd)
projectileSpeed = tonumber(settings.projectileSpeed)
auto = settings.auto
limitor = settings.limitor
autoSpread = settings.autoSpread

if modem then
    modem.open(settings.controlsChannel)
end

friendlyIDs = readFriendlyIDs(friendlyIDFile)
print("Friendly IDs: " .. textutils.serialize(friendlyIDs)) -- Debug print

if cannon.assemble() then
    print("asseble failed, press enter to contiue")
    io.read()
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

local function calculateVelocity(pos1, pos2, dt)
    local vx = (pos2[1] - pos1[1]) / dt
    local vy = (pos2[2] - pos1[2]) / dt
    local vz = (pos2[3] - pos1[3]) / dt
    return {x=vx, y=0, z=vz}
end

local function calculateAcceleration(vel1, vel2, dt)
    local ax = (vel2.x - vel1.x) / dt
    local ay = (vel2.y - vel1.y) / dt
    local az = (vel2.z - vel1.z) / dt
    return {x = ax, y = ay, z = az}
end

local function estimatePosition(pos, velocity, acceleration, time)
    local shipVelocity = ship.getVelocity()
    local estX = pos.x + (velocity.x - shipVelocity.x) * velocityFactor * time + 0.5 * acceleration.x * time^2
    local estY = pos.y + (velocity.y - shipVelocity.y) * velocityFactor * time + 0.5 * acceleration.y * time^2
    local estZ = pos.z + (velocity.z - shipVelocity.z) * velocityFactor * time + 0.5 * acceleration.z * time^2
    return {x = estX, y = estY, z = estZ}
end

local function findRelativeAngle(targetYaw,targetPitch)
    rot = ship.getQuaternion()
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

    for pitch = 0, 90, 0.1 do -- Iterate over pitch angles
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
    return bestLowPitch
end

local function applySpread(targetYaw, targetPitch)
    -- Randomly generate a spread value for yaw and pitch
    local yawSpread = (math.random() * 2 - 1) * spreadYawRange
    local pitchSpread = (math.random() * 2 - 1) * spreadPitchRange

    -- Apply the spread to the target angles
    local newYaw = targetYaw + yawSpread
    local newPitch = targetPitch + pitchSpread

    return newYaw, newPitch
end

local function aimCannon(targetPos, targetVel, targetAcc, sourceX, sourceY, sourceZ)
    if sourceX and sourceY and sourceZ then
        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ

        local estimateX = targetPos.x + targetVel.x * 0.1
        local estimateY = targetPos.y + targetVel.y * 0.1
        local estimateZ = targetPos.z + targetVel.z * 0.1

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

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

        local currentYaw = cannon.getYaw()
        local currentPitch = cannon.getPitch()

        locked = true
        if limitor then
            if requiredRelativeYaw < settings.yawLowerLimit then
                requiredRelativeYaw = settings.yawLowerLimit
                locked = false
            elseif requiredRelativeYaw > settings.yawUpperLimit then
                requiredRelativeYaw = settings.yawUpperLimit
                locked = false
            end
            if requiredRelativePitch < settings.pitchLowerLimit then 
                requiredRelativePitch = settings.pitchLowerLimit
                locked = false
            elseif requiredRelativePitch > settings.pitchUpperLimit then
                requiredRelativePitch = settings.pitchUpperLimit
                locked = false
            end
        end

        -- Turning and pitch adjustment logic
        parallel.waitForAll(
            function() cannon.setYaw(requiredRelativeYaw) end,
            function() cannon.setPitch(requiredRelativePitch) end
        )
    end
end

local function calculateSpeed(velocity)
    return math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
end

local function calculateAcceleration(vel1, vel2, dt)
    local ax = (vel2.x - vel1.x) / dt * accelerationFactor
    local ay = (vel2.y - vel1.y) / dt * accelerationFactor
    local az = (vel2.z - vel1.z) / dt * accelerationFactor
    return {x = ax, y = ay, z = az}
end

local function estimatePosition(pos, velocity, acceleration, time)
    local estX = pos.x + velocity.x * velocityFactor * time + 0.5 * acceleration.x * time^2
    local estY = pos.y + velocity.y * velocityFactor * time + 0.5 * acceleration.y * time^2
    local estZ = pos.z + velocity.z * velocityFactor * time + 0.5 * acceleration.z * time^2
    return {x = estX, y = estY, z = estZ}
end

local function updateMode()
    if redstone.getInput("top") or (controls and controls.targetSwitch) then
        lastRedstoneInputTime = os.clock()
        mode = "cycle"
    elseif os.clock() - lastRedstoneInputTime > redstoneTimeout then
        mode = "auto"
    end
end

-- Function to get the closest target (players or ships)
local function getClosestTarget()
    local targetScan1 = radar.scanForPlayers(400)
    local shipScan1 = radar.scanForShips(400) -- Scan for ships (e.g., missiles) within 1000 units

    -- Variables to hold the closest target data
    local closestTarget = nil
    local closestDistance = math.huge
    local targetPos1 = nil
    local targetInfo = nil
    local targets = {}
    local highestSpeed = 0

    for _, player in pairs(targetScan1) do
        if player and player.pos then
            local dx = player.pos[1] - shipPos.x
            local dy = player.pos[2] - shipPos.y
            local dz = player.pos[3] - shipPos.z
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

            -- If this player is closer than the current closest, update the closest target
            if not isFriendly(player.nickname) then
                closestDistance = distance
                targetPos1 = player.pos

                table.insert(targets, {type = "player", pos = player.pos, distance = distance, nickname = player.nickname})
            end
        end
    end

    -- Loop through each ship detected in the first ship scan
    local closestDistance = math.huge
    for _, ship in pairs(shipScan1) do
        if ship and ship.pos then
            local dx = ship.pos.x - shipPos.x
            local dy = ship.pos.y - shipPos.y
            local dz = ship.pos.z - shipPos.z
            local CIWSdistance = math.sqrt(dx * dx + dy * dy + dz * dz)

            -- Calculate speed of the ship
            local shipSpeed = calculateSpeed(ship.velocity)

            --calculate distance with ship source

            local dx = ship.pos.x - vesselPos.x
            local dy = ship.pos.y - vesselPos.y
            local dz = ship.pos.z - vesselPos.z
            local shipDistance = math.sqrt(dx * dx + dy * dy + dz * dz)

            --check velocity difference to see if the target is on the same vessel

            local speedError = math.abs(ship.velocity.x - vesselVelocity.x) + math.abs(ship.velocity.y - vesselVelocity.y) + math.abs(ship.velocity.z - vesselVelocity.z)

            -- If the ship is moving fast (e.g., a missile), prioritize it
            --if shipSpeed > 4 and not( isFriendly(ship.id)) and (CIWSdistance > 15 or shipDistance > 15 ) and speedError > 2 then
            if shipSpeed > 4 and not( isFriendly(ship.id)) and (CIWSdistance > 15 or shipDistance > 15 ) and speedError > 2 then
                closestDistance = CIWSdistance
                highestSpeed = shipSpeed
                targetPos1 = ship.pos
                table.insert(targets, {type = "ship", pos = ship.pos, distance = distance, velocity = ship.velocity, id = ship.id})
            end
        end
    end

    table.sort(targets, function(a, b)
        if not a.distance or not b.distance then
            return false -- Safeguard against nil values
        end
    
        if a.type == "ship" and b.type == "player" then
            return true
        elseif a.type == "player" and b.type == "ship" then
            return false
        else
            return a.distance < b.distance
        end
    end)

    return targets
end

local function main()
    while true do
        local startTime = os.clock()
        shipPos = ship.getWorldspacePosition()
        vesselPos = shipPos
        vesselVelocity = ship.getVelocity()

        shipPos.x = shipPos.x + lengthCorrection * math.cos(getYaw() - math.pi/2) + widthCorrection * math.cos(getYaw())
        shipPos.y = shipPos.y + heightCorrection
        shipPos.z = shipPos.z + lengthCorrection * math.sin(getYaw() - math.pi/2) + widthCorrection * math.sin(getYaw())

        updateMode()
        local firstScanEndTime = os.clock()
        local dt1 = firstScanEndTime - startTime

        -- Get all targets
        local targets = getClosestTarget()
        print(textutils.serialize(controls))
        -- Determine the target based on the mode
        local targetInfo
        if mode == "auto" then
            -- In auto mode, lock on to the closest target
            if #targets > 0 then
                targetInfo = targets[1]
            end
            cycleIndex = 1
        elseif mode == "cycle" then
            -- In cycle mode, switch to the next target on redstone input
            if redstone.getInput("top") or (controls and controls.targetSwitch) then
                cycleIndex = cycleIndex + 1 -- Cycle to the next target
                print("Cycling to next target.")
            end
            if cycleIndex > #targets then 
                cycleIndex = 1 
            end
            if #targets > 0 then
                targetInfo = targets[cycleIndex]
            end
        end
        -- Wait for a short period (scanInterval) to perform the second scan
        if targetInfo and targetInfo.pos then
            -- Perform second scan for both players and ships
            if targetInfo.type == "player" then
                sleep(scanInterval)
                local targetScan2 = radar.scanForPlayers(400)
                local targetPos2 = nil

                for _, player in pairs(targetScan2) do
                    if player and player.pos and player.nickname == targetInfo.nickname then
                        targetPos2 = player.pos
                        break
                    end
                end
                
                -- If both positions are available, calculate velocity for the player
                if targetInfo.pos and targetPos2 then
                    targetInfo.velocity = calculateVelocity(targetInfo.pos, targetPos2, scanInterval*4)
                    targetInfo.pos.x = targetPos2[1]
                    targetInfo.pos.y = targetPos2[2]
                    targetInfo.pos.z = targetPos2[3]
                else
                    targetInfo.velocity = {x=0, y=0, z=0}  -- Default velocity if we cannot calculate it
                end

                if targetInfo.pos and targetInfo.pos.x and targetInfo.velocity then
                    print("aiming cannon")
                    aimCannon(targetInfo.pos, targetInfo.velocity, {x=0,y=0,z=0}, shipPos.x, shipPos.y, shipPos.z)
                else
                    locked = false
                    redstone.setOutput("back",false)
                end
            elseif targetInfo.type == "ship" then
                sleep(scanInterval)

                local shipScan2 = radar.scanForShips(400)
                local shipPos2, shipVelocity2 = nil, nil

                -- Find the same ship in the second scan based on its ID
                for _, ship in pairs(shipScan2) do
                    if ship.id == targetInfo.id then
                        shipPos2 = ship.pos
                        shipVelocity2 = ship.velocity
                        break
                    end
                end

                local dt2 = os.clock() - firstScanEndTime
                if targetInfo.velocity and shipVelocity2 then
                    -- Calculate acceleration
                    local acceleration = calculateAcceleration(targetInfo.velocity, shipVelocity2, dt2)
                    -- Update velocity for next scan
                    targetInfo.velocity = shipVelocity2
                    -- Aim the cannon considering acceleration
                    aimCannon(targetInfo.pos, targetInfo.velocity, acceleration, shipPos.x, shipPos.y, shipPos.z)
                else
                    locked = false
                end
            else
                locked = false
                redstone.setOutput("back",false)
            end
        else
            locked = false
            redstone.setOutput("back",false)
        end
        os.sleep()
    end
end

local function autoFire()
    while true do
        safetyOff = redstone.getInput("left") or redstone.getInput("right") or redstone.getInput("bottom") or redstone.getInput("back") or (controls and controls.fireAutocannon)
        if locked and auto and safetyOff then
            cannon.fire()
            cannon.fire()
            cannon.fire()
            cannon.fire()
            redstone.setOutput("front",true)
        else
            redstone.setOutput("front",false)
        end
        sleep()
    end
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == settings.controlsChannel then
                controls = message
            end
        else
            sleep()
        end
    end
end

parallel.waitForAny(
    main,
    autoFire,
    modemMessage
)