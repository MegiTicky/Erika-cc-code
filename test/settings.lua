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
    settings.velocityFactor = askForInput("Input the velocityFactor", 1)
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
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = 17,
                heightCorrection = 20,
                widthCorrection = -8,
                limitor = true,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = -150,
                yawUpperLimit = 0,
                auto = true
            }
        },
        {
            filename = "ussNJport2CIWS_settings.txt",
            settings = {
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = -15,
                heightCorrection = 18,
                widthCorrection = -8,
                limitor = true,
                pitchLowerLimit = -10,
                pitchUpperLimit = 90,
                yawLowerLimit = -180,
                yawUpperLimit = 0,
                auto = true
            }
        },
        {
            filename = "ussNJstarboard1CIWS_settings.txt",
            settings = {
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.03,
                cd = 0.98,
                autoSpread = false,
                lengthCorrection = 40,
                heightCorrection = 6,
                widthCorrection = -10,
                limitor = true,
                auto = false
            }
        },
        {
            filename = "type55BowCIWS_settings.txt",
            settings = {
                velocityFactor = 1,
                projectileSpeed = 160,
                g = 0.025,
                cd = 0.99,
                autoSpread = true,
                lengthCorrection = 35,
                heightCorrection = 5,
                widthCorrection = 0,
                limitor = true,
                auto = false
            }
        },
        {
            filename = "CIWStruck_settings.txt",
            settings = {
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
        for i, file in ipairs(settingsFilesList) do
            print(i .. ". " .. file)
        end

        local selection = askForInput("Select an existing setting to load or create a new one (1-" .. #settingsFilesList .. " or new)", "new")

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