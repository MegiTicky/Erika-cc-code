-- Function to detect the closest player's name from the entity data
local function getClosestPlayer()
    -- Use the @p selector to get the data of the closest player
    local ok, result = commands.exec("execute at @p run data get entity @p")
    if ok and result and type(result) == "table" then
        -- Parse the first line to extract the player's name
        local firstLine = result[1]
        local playerName = string.match(firstLine, "^(%S+) has the following entity data")
        if playerName then
            return playerName
        end
    end
    return nil
end

-- Function to give the player Resistance 10 for 2 seconds
local function givePlayerResistance(playerName)
    if not playerName then
        print("No player detected to give resistance.")
        return
    end

    -- Apply Resistance 10 effect for 2 seconds (40 ticks)
    local ok, result = commands.exec("effect give " .. playerName .. " minecraft:resistance 2 10 true")
    if ok then
        print("Resistance 10 given to " .. playerName .. " for 2 seconds.")
    else
        print("Failed to give resistance to " .. playerName .. ".")
    end
end

-- Function to kill one of the player's infantry
local function killOneInfantry(crossbowmanName)
    -- Execute the kill command for one infantry entity with the given name
    local ok, result = commands.exec("kill @e[name=\"" .. crossbowmanName .. "\",limit=1]")
    if ok then
        print("One infantry named \"" .. crossbowmanName .. "\" has been killed.")
    else
        print("Failed to kill an infantry named \"" .. crossbowmanName .. "\".")
    end
end

-- Function to teleport the player to their crossbowman
local function teleportPlayerToCrossbowman(playerName)
    if not playerName then
        print("No player detected near the computer.")
        return
    end

    local crossbowmanName = playerName .. "_infantry"
    local ok, result = commands.exec("execute as @a[name=\"" .. playerName .. "\"] run tp @s @e[name=\"" .. crossbowmanName .. "\",limit=1]")

    if ok then
        print(playerName .. " teleported to " .. crossbowmanName)
        -- Kill one of the player's infantry after teleporting
        killOneInfantry(crossbowmanName)
        -- Give the player Resistance 10 for 2 seconds
        givePlayerResistance(playerName)
    else
        print("Failed to teleport " .. playerName .. " to " .. crossbowmanName)
    end
end

-- Function to wait for a button press (one-time activation)
local function waitForButtonPress()
    print("Waiting for button press...")
    local buttonPressed = false

    -- Wait for the redstone signal to turn ON
    while not buttonPressed do
        if redstone.getInput("back") then
            print("Button pressed!")
            buttonPressed = true
        end
        sleep(0.1) -- Check every 0.1 seconds
    end

    -- Wait for the redstone signal to turn OFF
    while redstone.getInput("back") do
        sleep(0.1) -- Wait until the button is released
    end

    print("Button released.")
end

-- Main function
local function main()
    while true do
        -- Wait for the player to press the button
        waitForButtonPress()

        -- Detect the closest player
        local closestPlayer = getClosestPlayer()
        if closestPlayer then
            print("Closest player detected: " .. closestPlayer)
            -- Teleport the player to their crossbowman and kill one infantry
            teleportPlayerToCrossbowman(closestPlayer)
        else
            print("No player detected.")
        end
    end
end

-- Run the main function
main()
