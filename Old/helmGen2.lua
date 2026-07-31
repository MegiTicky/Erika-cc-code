-- Define default base channel
local defaultBaseChannel = 200

-- Prompt user for base channel input
print("Enter base channel (press Enter to use default: " .. defaultBaseChannel .. "):")
local inputChannel = read()

-- If the user inputs a number, use it as the base channel, otherwise use the default
local baseChannel = tonumber(inputChannel) or defaultBaseChannel

-- Calculate channels based on the base channel
local stressChannel = baseChannel
local leftEngineChannel = baseChannel + 1
local rightEngineChannel = baseChannel + 2
local fuelChannel = baseChannel + 3
local accChannel = baseChannel + 4

-- Initialize peripherals
local monitor = peripheral.find("monitor")
local modem = peripheral.wrap("top")
local controller = peripheral.find("tweaked_controller")

if not monitor then
    error("monitor not found")
elseif not modem then
    error("modem not found")
elseif not controller then
    error("controller not found")
end

-- Open modem channels
modem.open(stressChannel)
modem.open(leftEngineChannel)
modem.open(rightEngineChannel)
modem.open(fuelChannel)
modem.open(accChannel)

-- Define secret key for message validation
local secretKey = "YourSecretKey123"
local function isValidMessage(message)
    local key, msg = tostring(message):match("^(%w+)%:(.+)$")
    return key == secretKey, msg
end

-- Initialize variables
local stressCapacity, stressUsed, stress, fuel, energy, rpm, energyCurrent, energyCapacity, fuelUsed, fuelCapacity = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

local w, h = monitor.getSize()
local turnLevel = 0
local rpm = 0
local displayState = "main"
local shipYaw = 0
local shipSpeed = 0

local function toDegrees(radians)
    return radians * (180 / math.pi)
end

-- Function to convert degrees to a bearing
local function toBearing(degrees)
    local bearing = degrees % 360
    if bearing < 0 then
        bearing = 360 + bearing
    end
    return bearing
end

-- Listen for coordinates
local function listenForCoordinates()
    while true do
        local event, side, senderChannel, replyChannel, message, senderDistance = os.pullEvent("modem_message")
        local valid, validatedMessage = isValidMessage(message)
        if valid then
            if senderChannel == stressChannel then
                stress = validatedMessage
            elseif senderChannel == fuelChannel then
                fuel = validatedMessage
            elseif senderChannel == accChannel then
                energy = validatedMessage
            end
        end
    end
end

-- Draw a progress bar
local function drawProgressBar(x, y, length, currentValue, maxValue, barColor, bgColor)
    local fillLength = math.floor((currentValue / maxValue) * length)
    local fill = string.rep(" ", fillLength)
    local empty = string.rep(" ", length - fillLength)

    monitor.setCursorPos(x, y)
    monitor.setBackgroundColor(barColor or colors.white)
    monitor.write(fill)
    monitor.setBackgroundColor(bgColor or colors.black)
    monitor.write(empty)
end

local function drawTurning(x, y, turnLevel)
    local maxTurnLevel = 3
    local barLength = 10  -- Length of the turning bar

    -- Calculate the position of the turning indicator
    local turnPos = math.floor((turnLevel + maxTurnLevel) / (maxTurnLevel * 2) * barLength)

    -- Draw the turning bar
    for i = 0, barLength do
        monitor.setCursorPos(x + i, y)
        if i == turnPos then
            monitor.setBackgroundColor(colors.black)  -- Background color for the indicator
            monitor.write("=")  -- Turning indicator
        else
            if i > turnPos then
                monitor.setBackgroundColor(colors.red)  -- Background color to the right of the indicator
            else
                monitor.setBackgroundColor(colors.blue)  -- Background color to the left of the indicator
            end
            monitor.write(" ")
        end
    end

    -- Draw the label
    monitor.setCursorPos(x+2, y - 1)
    monitor.setBackgroundColor(colors.lightGray)
    monitor.write("Turning")
    monitor.setCursorPos(x+2, y + 1)
    monitor.write("Level: " .. turnLevel)
    monitor.setCursorPos(x + 3, y + 2)
    monitor.write("- / +")

    -- Reset background color
    monitor.setBackgroundColor(colors.lightGray)
end

-- Round a number to two decimal places
local function round(num)
    return math.floor(num * 100 + 0.5) / 100
end

-- Draw the throttle indicator
local function drawThrottle(x, y, rpm, label)
    local maxRPM = 256
    local minRPM = -256
    local barLength = 10  -- Length of the throttle bar

    -- Calculate the position of the throttle indicator
    local throttlePos = math.floor((rpm - minRPM) / (maxRPM - minRPM) * barLength)

    -- Draw the throttle bar
    for i = 0, barLength do
        monitor.setCursorPos(x, y + i)
        if i == throttlePos then
            monitor.setBackgroundColor(colors.black)  -- Background color for the indicator
            monitor.write("=")  -- Throttle indicator
        else
            if i > throttlePos then
                monitor.setBackgroundColor(colors.red)  -- Background color below the indicator
            else
                monitor.setBackgroundColor(colors.blue)  -- Background color above the indicator
            end
            monitor.write(" ")
        end
    end

    -- Draw the label
    monitor.setCursorPos(x - 3, y - 1)
    monitor.setBackgroundColor(colors.lightGray)
    monitor.write(label)
    monitor.setCursorPos(x - 3, y + barLength + 1)
    monitor.write("RPM: " .. rpm)
    monitor.setCursorPos(x - 2, y + barLength + 2)
    monitor.write("- / +")

    -- Reset background color
    monitor.setBackgroundColor(colors.lightGray)
end

-- Update the RPM based on user input
local function updateRPM(rpm, turnLevel)
    local maxRPM = 256
    local minRPM = -256
    if rpm > maxRPM then
        rpm = maxRPM
    elseif rpm < minRPM then
        rpm = minRPM
    end
    local leftRPM = rpm
    local rightRPM = rpm
    
    if turnLevel > 3 then
        turnLevel = 3
    elseif turnLevel < -3 then
        turnLevel = -3
    end
    if turnLevel == 0 then
        modem.transmit(leftEngineChannel, 0, secretKey .. ":" .. rpm)
        modem.transmit(rightEngineChannel, 0, secretKey .. ":" .. rpm)
        redstone.setOutput("front",false)
        redstone.setOutput("back",false)
    elseif turnLevel < 0 then
        redstone.setOutput("front",false)
        redstone.setOutput("back",true)
        if turnLevel == -2 then
            modem.transmit(leftEngineChannel, 0, secretKey .. ":" .. 0)
            modem.transmit(rightEngineChannel, 0, secretKey .. ":" .. rpm)
        elseif turnLevel == -3 then
            modem.transmit(leftEngineChannel, 0, secretKey .. ":" .. -256)
            modem.transmit(rightEngineChannel, 0, secretKey .. ":" .. 256)
        else
            modem.transmit(leftEngineChannel, 0, secretKey .. ":" .. rpm)
            modem.transmit(rightEngineChannel, 0, secretKey .. ":" .. rpm)
        end
    elseif turnLevel > 0 then
        redstone.setOutput("front",true)
        redstone.setOutput("back",false)
        if turnLevel == 2 then
            modem.transmit(leftEngineChannel, 0, secretKey .. ":" .. rpm)
            modem.transmit(rightEngineChannel, 0, secretKey .. ":" .. 0)
        elseif turnLevel == 3 then
            modem.transmit(leftEngineChannel, 0, secretKey .. ":" .. 256)
            modem.transmit(rightEngineChannel, 0, secretKey .. ":" .. -256)
        else
            modem.transmit(leftEngineChannel, 0, secretKey .. ":" .. rpm)
            modem.transmit(rightEngineChannel, 0, secretKey .. ":" .. rpm)
        end
    end
end

local waypoints = {}
local function addWaypoint(x, z, color)
    local newWaypoint = {
        x = x,
        z = z,
        color = color or colors.purple
    }
    table.insert(waypoints, newWaypoint)
end

local function displayWaypoints()
    local startY = 5
    for i, waypoint in ipairs(waypoints) do
        local pos = ship.getWorldspacePosition() 
        local deltaX = waypoint.x - pos.x
        local deltaZ = waypoint.z - pos.z
        local distance = math.sqrt(deltaX^2 + deltaZ^2)
        monitor.setCursorPos(20, startY + i - 1)
        monitor.write("W" .. i .. ": (" .. waypoint.x .. ", " .. waypoint.z .. ")".." Dist: "..round(distance))
        monitor.write(" Delete")
    end
end

local function drawWaypointPage()
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.write("Open the computer terminal")
    monitor.setCursorPos(1, 2)
    monitor.write("to input waypoint coordinates.")
end

-- Listen for touch events to increase or decrease RPM
local function handleTouch()
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        if y == 22 then  -- Adjust based on the throttle position
            if x == 4 and rpm > -256 then  -- Throttle decrease position
                rpm = rpm - 16  -- Decrease RPM
            elseif x == 8 and rpm < 256 then  -- Throttle increase position
                rpm = rpm + 16  -- Increase RPM
            end
        end
        if y == 7 then  -- Adjust based on the throttle position
            if x == 4 and turnLevel > -3 then  -- Throttle decrease position
                turnLevel = turnLevel - 1  -- Decrease RPM
            elseif x == 8 and turnLevel < 3 then  -- Throttle increase position
                turnLevel = turnLevel + 1  -- Increase RPM
            end
        end
        if y == 4 and x > 20 then
            displayState = "waypoints"
            drawWaypointPage()
            print("Enter waypoint coordinates (x, z)")
            print("Note: Waypoint within 200 blocks will be automatically deleted")
            local input = read()
            local x, z = input:match("([^,]+),([^,]+)")
            x = tonumber(x)
            z = tonumber(z)
            if x and z then
                addWaypoint(x, z)
                displayState = "main"  -- Switch back to main display after adding waypoint
            else
                print("Invalid input. Please enter coordinates as 'x, z'")
            end
        end
        local startY = 5
        for i, waypoint in ipairs(waypoints) do
            if y == startY + i - 1 and x > #("Waypoint " .. i .. ": (" .. waypoint.x .. ", " .. waypoint.z .. ")") then
                table.remove(waypoints, i)
                break
            end
        end
    end
end

-- Listen for controller input to increase or decrease RPM
local function handleController()
    while true do
        local yAxis = controller.getAxis(2)
        if yAxis < 0 and rpm > -256 then
            rpm = rpm - 16
        elseif yAxis > 0 and rpm < 256 then
            rpm = rpm + 16
        end
        sleep(0.1)
        local xAxis = controller.getAxis(1)
        if xAxis < 0 and turnLevel > -3 then
            turnLevel = turnLevel - 1
        elseif xAxis > 0 and turnLevel < 3 then
            turnLevel = turnLevel + 1
        end
    end
end

local function drawMainControls()
    monitor.clear()
    monitor.setTextScale(0.5)
    local matrix = ship.getRotationMatrix()
    shipYaw = toBearing(toDegrees(math.atan2(-matrix[1][3], matrix[3][3]))) - 180
    if shipYaw < 0 then
        shipYaw = shipYaw + 360
    end
    local velocity = ship.getVelocity()
    shipSpeed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2) * 1.94384449
    local pos = ship.getWorldspacePosition() -- ship position table
    
    -- Check if the required variables are updated by the listenForCoordinates function
    if stress and energy and fuel and shipYaw and shipSpeed then
        local stressUsed, stressCapacity = string.match(stress, "(%d+)%:(%d+%.?%d*)")
        local energyCurrent, energyCapacity = string.match(energy, "(%d+)%:(%d+%.?%d*)")
        local fuelUsed, fuelCapacity = string.match(fuel, "(%d+)%:(%d+%.?%d*)") -- Parses "2816 / 46080"

        -- Convert to numbers
        stressUsed = tonumber(stressUsed)
        stressCapacity = tonumber(stressCapacity)
        energyCurrent = tonumber(energyCurrent)
        energyCapacity = tonumber(energyCapacity)
        fuelUsed = tonumber(fuelUsed)
        fuelCapacity = tonumber(fuelCapacity)

        -- Stress progress bar
        if stressUsed and stressCapacity then
            monitor.setCursorPos(1, 1)
            monitor.setTextColor(colors.white)
            monitor.write("Stress: ")
            drawProgressBar(9, 1, 10, stressUsed, stressCapacity, colors.red, colors.lightGray)
            monitor.setCursorPos(20, 1)  -- Adjust as necessary for your display size
            monitor.write(stressUsed .. "/" .. stressCapacity)
        else
            monitor.setCursorPos(1, 1)
            monitor.write("Stress: Not connected")
        end

        -- Fuel progress bar
        if fuelUsed and fuelCapacity then
            monitor.setCursorPos(1, 2)
            monitor.setTextColor(colors.white)
            monitor.write("Fuel: " .. fuelUsed .. "/" .. fuelCapacity .. " will last: " .. round(fuelUsed / (72 / 160)) .. "s")
        else
            monitor.setCursorPos(1, 2)
            monitor.write("Fuel: Not connected")
        end

        -- Energy progress bar
        if energyCurrent and energyCapacity then
            monitor.setCursorPos(1, 3)
            monitor.setTextColor(colors.white)
            monitor.write("Energy: ")
            drawProgressBar(9, 3, 10, energyCurrent, energyCapacity, colors.green, colors.lightGray)
            monitor.setCursorPos(20, 3)  -- Adjust as necessary for your display size
            monitor.write(energyCurrent .. "/" .. energyCapacity)
        else
            monitor.setCursorPos(1, 3)
            monitor.write("Energy: Not connected")
        end

        -- Speed
        monitor.setCursorPos(40, 1)
        print(shipYaw)
        monitor.write("Speed: " .. round(shipSpeed) .. " knots")

        -- Heading
        monitor.setCursorPos(40, 2)
        shipYaw = toBearing(toDegrees(math.atan2(-matrix[1][3], matrix[3][3]))) - 180
        if shipYaw < 0 then
            shipYaw = shipYaw + 360
        end
        monitor.write("Heading: " .. round(shipYaw))
    end

    -- Waypoint
    monitor.setCursorPos(20, 4)
    monitor.write("Add waypoint")

    -- Draw engine throttle
    drawThrottle(6, 10, rpm, "Throttle")
    drawTurning(1, 5, turnLevel)
    displayWaypoints()
    updateRPM(rpm, turnLevel)
end

local function calculateBearingAndAdjustTurning()
    if #waypoints == 0 then
        return -- No waypoints to navigate to
    end
    
    local pos = ship.getWorldspacePosition()
    local waypoint = waypoints[1] -- Assuming navigating to the first waypoint

    -- Calculate the true bearing
    local deltaX = waypoint.x - pos.x
    local deltaZ = waypoint.z - pos.z
    local trueBearing = math.deg(math.atan2(-deltaX, deltaZ)) - 180
    
    if trueBearing < 0 then
        trueBearing = trueBearing + 360
    end
    print("trueBearing: " .. trueBearing)

    -- Calculate deltaYaw
    local deltaYaw = trueBearing - shipYaw
    if deltaYaw > 180 then
        deltaYaw = deltaYaw - 360
    elseif deltaYaw < -180 then
        deltaYaw = deltaYaw + 360
    end
    print("deltaYaw: " .. deltaYaw)

    -- Calculate the distance to the waypoint
    local distance = math.sqrt(deltaX^2 + deltaZ^2)

    -- Check if the ship is within 200 blocks of the waypoint
    if distance <= 200 then
        table.remove(waypoints, 1) -- Remove the first waypoint from the list
        return -- Exit the function early since the waypoint is reached
    end

    -- Adjust turning level based on distance and deltaYaw
    if math.abs(deltaYaw) > 5 then
        if (distance < 500 and math.abs(deltaYaw) > 10) or math.abs(deltaYaw) > 70 then
            turnLevel = -3
        elseif (distance < 1000 and math.abs(deltaYaw) > 10) or math.abs(deltaYaw) > 40 then
            turnLevel = -2
        else
            turnLevel = -1
        end

        if deltaYaw > 0 then
            turnLevel = -turnLevel -- Turn right
        end
    else
        turnLevel = 0
    end
    updateRPM(rpm, turnLevel) -- Update turning with the calculated turn level
end

-- Main control loop
parallel.waitForAny(
    function()
        -- Main loop
        while true do
            if displayState == "main" then
                drawMainControls()
                calculateBearingAndAdjustTurning() -- Adjust turning based on waypoint
            end
            sleep(0.1)
        end
    end,
    handleTouch,
    handleController,
    listenForCoordinates
)
