local modem = peripheral.wrap("right")

local cannons = {}
local controls = {cannonControlMode = "mouseAim"}
local targetInfo = {}

local cannons = {}
local k = 1
local nilCount = 0
local i = 0
while nilCount < 200 do
    local cannon = peripheral.wrap("createbigcannons:cannon_mount_"..tostring(i))
    if not(cannon) then
        cannon = peripheral.wrap("cbcmodernwarfare:compact_mount_"..tostring(i))
    end
    if cannon then
        cannons[k] = cannon
        k = k + 1
        nilCount = 0
        print("found cannon")
    else
        nilCount = nilCount + 1
    end
    i = i + 1
end
print("Found "..#cannons.." cannons")

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
    settings.controlsChannel = askForInput("Input the controlChannel number",500)
    settings.cannonChannel = askForInput("Input the cannonChannel number",900)
    settings.projectileSpeed = askForInput("Input the muzzle velocity number", 344)
    settings.g = askForInput("Input the gravity acceleration per tick", 0.04)
    settings.cd = askForInput("Input the drag per tick", 0.99)
    settings.autoSpread = askForInput("Enable automatic spread, yes/no", "yes") == "yes"
    settings.useHighPitch = askForInput("Use high pitch?", "yes") == "yes"
    settings.lengthCorrection = askForInput("Enter cannon source ship length correction", 35)
    settings.heightCorrection = askForInput("Enter cannon source ship height correction", 5)
    settings.widthCorrection = askForInput("Enter the cannon source ship width correction, positive if the ship is at the right side",0)
    settings.limitor = askForInput("Enable pitch yaw limiter, yes/no", "no") == "no"
    settings.pitchLowerLimit = askForInput("Ignore the follwing if no limitr. Input the pitch lower limit, default: -10",-10)
    settings.pitchUpperLimit = askForInput("Input the pitch lower limit, default: 90",90)
    settings.yawLowerLimit = askForInput("Input the yaw lower limit, default: -120",-120)
    settings.yawUpperLimit = askForInput("Input the pitch lower limit, default: 120",120)
    return settings
end

local function createPresetSettings()
    local presets = {
        {
            filename = "HX3SPA_settings.txt",
            settings = {
                controlsChannel = 500,
                cannonChannel = 900,
                projectileSpeed = 344,
                g = 0.04,
                cd = 0.99,
                autoSpread = true,
                useHighPitch = true,
                lengthCorrection = 0,
                heightCorrection = 2.5,
                widthCorrection = 3.5,
                limitor = false,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = -150,
                yawUpperLimit = 0,
            }
        },
        {
            filename = "ussNJPort_settings.txt",
            settings = {
                controlsChannel = 500,
                cannonChannel = 900,
                projectileSpeed = 240,
                g = 0.05,
                cd = 0.995,
                autoSpread = true,
                useHighPitch = false,
                lengthCorrection = 0,
                heightCorrection = 1.5,
                widthCorrection = 0,
                limitor = false,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = -150,
                yawUpperLimit = 0,
            }
        },
        {
            filename = "ussNJStarboard_settings.txt",
            settings = {
                controlsChannel = 500,
                cannonChannel = 901,
                projectileSpeed = 240,
                g = 0.05,
                cd = 0.995,
                autoSpread = true,
                useHighPitch = false,
                lengthCorrection = 0,
                heightCorrection = 1.5,
                widthCorrection = 0,
                limitor = false,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = -150,
                yawUpperLimit = 0,
            }
        },
        {
            filename = "IJNSKAutocannon_settings.txt",
            settings = {
                controlsChannel = 500,
                cannonChannel = 900,
                projectileSpeed = 240,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                useHighPitch = false,
                lengthCorrection = 0,
                heightCorrection = 6,
                widthCorrection = 0,
                limitor = false,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = -150,
                yawUpperLimit = 0,
            }
        },
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

-- Main execution
local settings = handleSettings()

print("Using settings:")
print(textutils.serialize(settings))
sleep(0.2)

print(settings.cannonChannel)

if modem then
    modem.open(tonumber(settings.cannonChannel))
    modem.open(tonumber(settings.controlsChannel))
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

local function setPitchYaw(targetPitch, targetYaw)
    local tasks = {} -- Table to store each cannon's task

    for index, cannon in pairs(cannons) do
        -- Define the function for this cannon's pitch/yaw adjustment
        local function adjustCannon()
            if index == 1 then
                -- No spread for the first cannon
                cannon.setPitch(targetPitch)
                cannon.setYaw(targetYaw)
                print("Cannon " .. index .. " (Primary) set to pitch: " .. targetPitch .. " and yaw: " .. targetYaw)
            else
                -- Spread logic for other cannons
                local spreadConstant
                if targetPitch < 30 then
                    spreadConstant = 0.5
                else
                    spreadConstant = 0.5
                end

                local pitchVariation = math.random(-2, 2) * spreadConstant -- Adjust the range to control the spread
                local yawVariation = math.random(-2, 2) * spreadConstant -- Adjust the range to control the spread

                local adjustedPitch = targetPitch + pitchVariation
                local adjustedYaw = targetYaw + yawVariation

                if settings.autoSpread then
                    cannon.setPitch(adjustedPitch)
                    cannon.setYaw(adjustedYaw)
                    print("Cannon " .. index .. " set to pitch: " .. adjustedPitch .. " and yaw: " .. adjustedYaw)
                else
                    cannon.setPitch(targetPitch)
                    cannon.setYaw(targetYaw)
                    print("Cannon " .. index .. " set to uniform pitch: " .. targetPitch .. " and yaw: " .. targetYaw)
                end
            end
        end

        -- Add this task to the tasks table
        table.insert(tasks, adjustCannon)
    end

    -- Execute all tasks in parallel
    parallel.waitForAll(table.unpack(tasks))
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

    for pitch = 0, 65, 0.01 do -- Iterate over pitch angles
        local calculatedRange = calculateRange(pitch, initialVelocity, settings.cd, settings.g, c_est, settings.projectileSpeed)
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

    -- Prioritize the high-angle solution if the range difference is smaller than 5
    if settings.useHighPitch and bestHighPitch and bestHighDistance < 2 then
        return bestHighPitch
    else
        return bestLowPitch
    end

    -- Fallback to bestLowPitch if bestHighPitch is not suitable
end

local function aimCannon(targetPos, targetVel, sourceX, sourceY, sourceZ)
    if sourceX and sourceY and sourceZ then
        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local estimateTime = distance / (settings.projectileSpeed)
        local estimateX = targetPos.x + targetVel.x * estimateTime
        local estimateY = targetPos.y + targetVel.y * estimateTime
        local estimateZ = targetPos.z + targetVel.z * estimateTime

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360 -- normalize yaw
        balisticPitch = findBestPitch(estimateX, estimateY, estimateZ, sourceX, sourceY, sourceZ, settings.projectileSpeed, settings.g, settings.cd, 0.0028, settings.projectileSpeed)
        if balisticPitch > 30 then
            pitch = balisticPitch
        else
            pitch = pitch + balisticPitch
        end

        local requiredRelativeYaw,requiredRelativePitch = findRelativeAngle(yaw,pitch)
        if pitchLimit then
            setPitchYaw(math.min(requiredRelativePitch,pitchUpperLimit),requiredRelativeYaw)
        else
            setPitchYaw(requiredRelativePitch,requiredRelativeYaw)
        end
    end
end

local function manualCannonControl()
    while true do
        if controls.cannonControlMode == "manual" then
            if controls then
                local pitch = cannons[1].getPitch()
                local yaw = cannons[1].getYaw()
                -- Control yaw and pitch manually with arrow keys
                if controls.cannonUp then
                    -- Increase pitch
                    setPitchYaw(pitch + 2, yaw)
                elseif controls.cannonDown then
                    -- Decrease pitch
                    setPitchYaw(pitch - 2, yaw)
                else
                    
                end
                if controls.cannonLeft then
                    -- Turn left
                    setPitchYaw(pitch, yaw - 2)
                elseif controls.cannonRight then
                    -- Turn right
                    setPitchYaw(pitch, yaw + 2)
                else

                end
            else

            end
            sleep()
        else
            sleep() -- Sleep for a short time if not in manual mode
        end
    end
end

local function firing()
    while true do
        if controls then
            if controls.fireCannon then
                local fireTasks = {} -- Table to store firing tasks

                -- Add each cannon's fire task to the table
                for index, cannon in pairs(cannons) do
                    table.insert(fireTasks, function()
                        cannon.fire()
                        print("Cannon " .. index .. " FIRING")
                    end)
                end

                -- Execute all tasks simultaneously
                parallel.waitForAll(table.unpack(fireTasks))

                redstone.setOutput("top", true)
                sleep(0.1)
                redstone.setOutput("top", false)
            else
                redstone.setOutput("top", false)
            end
        end
        sleep()
    end
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == settings.cannonChannel then
                targetInfo = message
            elseif channel == settings.controlsChannel then
                controls = message
            end
        else
            sleep()
        end
    end
end

local function main()
    while true do
        local source = ship.getWorldspacePosition()
        local sourceX = source.x + settings.lengthCorrection * math.cos(getYaw()  - math.pi/2) + settings.widthCorrection * math.cos(getYaw())
        local sourceY = source.y + settings.heightCorrection
        local sourceZ = source.z + settings.lengthCorrection * math.sin(getYaw()  - math.pi/2) + settings.widthCorrection * math.sin(getYaw())
        if targetInfo and targetInfo.targetPos and targetInfo.targetVel and controls.cannonControlMode == "mouseAim" then
            aimCannon(targetInfo.targetPos,targetInfo.targetVel,sourceX,sourceY,sourceZ)
        end
        sleep()
    end
end

parallel.waitForAny(
    manualCannonControl,
    modemMessage,
    firing,
    main
)
