-- Define default base channel
local defaultBaseChannel = 200

-- Prompt user for base channel input
print("Enter base channel (press Enter to use default: " .. defaultBaseChannel .. "):")
local inputChannel = read()
if inputChannel == "" then
    inputChannel = 200
end
inputChannel = tonumber(inputChannel)

local statusChannel = inputChannel
local controlChannel = inputChannel + 1

-- Initialize peripherals
local modem = peripheral.wrap("back")
local controller = peripheral.find("tweaked_controller")

if not modem then
    error("modem not found")
end

-- Open modem channel
modem.open(statusChannel)

-- Initialize variables
local stressCapacity, stressUsed, fuelUsed, fuelCapacity, energyCurrent, energyCapacity = 0, 0, 0, 0, 0, 0
local turnLevel, rpm = 0, 0
local shipYaw, shipSpeed = 0, 0
local desiredYlevel = 0
local waypoints = {}
local mode = "display"

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
        if senderChannel == statusChannel then
            local data = textutils.unserialize(message)
            if data then
                stressUsed = data.stress and data.stress.usedSU or stressUsed
                stressCapacity = data.stress and data.stress.SUCapacity or stressCapacity
                fuelUsed = data.fuel and data.fuel.totalBlazeCakes or fuelUsed
                fuelCapacity = data.fuel and data.fuel.total or fuelCapacity
                energyCurrent = data.accumulator and data.accumulator.accEnergy or energyCurrent
                energyCapacity = data.accumulator and data.accumulator.accCapacity or energyCapacity
                shipYaw = data.yaw or shipYaw
                shipSpeed = data.speed or shipSpeed
            end
        end
    end
end

-- Display the data in text form
local function displayData()
    while true do
        if mode == "display" then
            term.clear()
            term.setCursorPos(1, 1)
            
            -- Display Stress Data
            if stressUsed and stressCapacity then
                print("Stress: " .. stressUsed .. "/" .. stressCapacity)
            else
                print("Stress: Not connected")
            end
            
            -- Display Fuel Data
            if fuelUsed and fuelCapacity then
                print("Fuel: " .. fuelUsed .. "/" .. fuelCapacity)
            else
                print("Fuel: Not connected")
            end
            
            -- Display Energy Data
            if energyCurrent and energyCapacity then
                print("Energy: " .. energyCurrent .. "/" .. energyCapacity)
            else
                print("Energy: Not connected")
            end
            
            -- Display Speed and Heading
            print("Speed: " .. shipSpeed .. " knots")
            print("Heading: " .. shipYaw)
            
            -- Display Turn Level and RPM
            print("Turn Level: " .. turnLevel)
            print("RPM: " .. rpm)
            print("desiredYlevel: "..desiredYlevel)
            print("statusChannel: "..statusChannel)
            print("controlChannel"..controlChannel)

            -- Display Waypoints
            if #waypoints > 0 then
                print("Waypoints:")
                for i, waypoint in ipairs(waypoints) do
                    print("W" .. i .. ": (" .. waypoint.x .. ", " .. waypoint.z .. ")")
                end
            else
                print("No waypoints")
            end
        end
            
        sleep()  -- Update every second
    end
end

-- Update the RPM and transmit control signals
-- Update the RPM and transmit control signals
local function updateControlSignals()
    local controlData = {
        engineRPM = rpm,
        turnLevel = turnLevel,
        desiredYlevel = desiredYlevel
    }
    modem.transmit(controlChannel, controlChannel, controlData)
end


-- Handle key events for WASD controls and adding waypoints
local function handleKeyPress()
    while true do
        local event, key = os.pullEvent("key")

        if key == keys.w then
            rpm = rpm + 16
            if rpm > 256 then rpm = 256 end
        elseif key == keys.s then
            rpm = rpm - 16
            if rpm < -256 then rpm = -256 end
        elseif key == keys.a then
            turnLevel = turnLevel - 1
            if turnLevel < -3 then turnLevel = -3 end
        elseif key == keys.d then
            turnLevel = turnLevel + 1
            if turnLevel > 3 then turnLevel = 3 end
        elseif key == keys.space then
            desiredYlevel = desiredYlevel + 1 -- Decrease depth (move up)
        elseif key == keys.leftCtrl then
            desiredYlevel = desiredYlevel - 1 -- Increase depth (move down)
        elseif key == keys.r then
            mode = "waypoint"
            print("Enter waypoint coordinates (x, z):")
            local input = read()
            local x, z = input:match("([^,]+),([^,]+)")
            x = tonumber(x)
            z = tonumber(z)
            if x and z then
                table.insert(waypoints, {x = x, z = z})
                print("Waypoint added: (" .. x .. ", " .. z .. ")")
            else
                print("Invalid input. Please enter coordinates as 'x, z'")
            end
            mode = "display"
        elseif key == keys.q then
            if rpm > 0 then
                rpm = rpm - 16
            elseif rpm < 0 then
                rpm = rpm + 16
            end

            if turnLevel < 0 then
                turnLevel = turnLevel + 1
            elseif turnLevel > 0 then
                turnLevel = turnLevel - 1
            end
        end

        updateControlSignals()
    end
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

    -- Calculate deltaYaw
    local deltaYaw = trueBearing - shipYaw
    if deltaYaw > 180 then
        deltaYaw = deltaYaw - 360
    elseif deltaYaw < -180 then
        deltaYaw = deltaYaw + 360
    end

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
    updateRPMAndTurn(rpm, turnLevel) -- Update turning with the calculated turn level
end


local modem = peripheral.find("modem") or error("No modem attached", 0)

print("Input the controlChannel, default = 500")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 500
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel) -- Open a channel to communicate

print("Remote control started. Use WASD keys to control movement, e(up) q(down) for suspension, Space for cannon, Shift for autocannon, T for smoke grenades, Tab to switch cannon control mode.")

--[[local controls = {
    accelerate = false,
    decelerate = false,
    turnLeft = false,
    turnRight = false,
    suspensionUp = false,
    suspensionDown = false,
    fireCannon = false,
    fireAutocannon = false,
    launchSmokeGrenade = false,
    cannonControlMode = "manual",
    cannonUp = false,
    cannonDown = false,
    cannonLeft = false,
    cannonRight = false
}

local keyMap = {
    w = "accelerate",
    s = "decelerate",
    a = "turnLeft",
    d = "turnRight",
    e = "suspensionUp",
    q = "suspensionDown",
    space = "fireCannon",
    leftShift = "fireAutocannon",
    t = "launchSmokeGrenade",
    tab = "switchMode",
    up = "cannonUp",
    down = "cannonDown",
    left = "cannonLeft",
    right = "cannonRight"
}

local function sendControls()
    modem.transmit(controlChannel, controlChannel, controls)
end

local function VLScontrol()
    while true do
        local event, param1, param2 = os.pullEvent()
        
        if event == "key" then
            -- Key press event
            for k, control in pairs(keyMap) do
                if param1 == keys[k] then
                    if control == "switchMode" then
                        -- Switch cannon control mode when Tab is pressed
                        if controls.cannonControlMode == "manual" then
                            controls.cannonControlMode = "mouseAim"
                            print("Switched to Mouse Aim mode")
                        else
                            controls.cannonControlMode = "manual"
                            print("Switched to Manual Control mode")
                        end
                    else
                        controls[control] = true
                    end
                    sendControls()
                    print("Key pressed:", k, control)
                end
            end

        elseif event == "key_up" then
            -- Key release event
            for k, control in pairs(keyMap) do
                if param1 == keys[k] then
                    if control ~= "switchMode" then
                        controls[control] = false
                        sendControls()
                        print("Key released:", k, control)
                    end
                end
            end
        end
    end
end]]

-- Main control loop
parallel.waitForAny(
    function()
        -- Main loop
        while true do
            calculateBearingAndAdjustTurning() -- Adjust turning based on waypoint
            sleep()
        end
    end,
    displayData,
    listenForCoordinates,
    handleKeyPress
)
