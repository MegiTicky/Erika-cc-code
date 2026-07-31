local helm = peripheral.find("eureka_ship_helm")
local camera = peripheral.find("camera")
local modem = peripheral.find("modem") or error("No modem attached")

local function getChannelInput(prompt, default)
    print(prompt .. ", default: " .. default)
    local input = io.read()
    if input == "" then
        input = default
    end
    return tonumber(input)
end
local waypointChannel = getChannelInput("Input the waypoint channel",1421)
local droneControlChannel = getChannelInput("Input the droneControlChannel",2020)
modem.open(waypointChannel)
modem.open(droneControlChannel)

local droneControls = {}
local function designation()
    -- Check if camera exists
    if not camera then
        print("Error: Camera peripheral not found")
        return
    end
    
    print("Designating target...")
    local result = camera.clipBlockDetail()
    
    if result and result.hit then
        local newWaypoint = {
            x = result.hit.x,
            y = result.hit.y,
            z = result.hit.z,
            color = colors.white  -- White color in hexadecimal
        }
        
        print(string.format("Adding waypoint at x:%.1f y:%.1f z:%.1f", 
              result.hit.x, result.hit.y, result.hit.z))
              
        -- Optional: Draw outline at target
        camera.outlineToUser(
            result.hit.x, result.hit.y, result.hit.z,
            "UP",  -- Default direction
            0xFFFFFF,  -- White
            "designation"  -- Slot ID
        )
        
        -- Transmit waypoint
        if modem then
            modem.transmit(waypointChannel, waypointChannel, newWaypoint)
        else
            print("Error: Modem not available")
        end
    else
        print("No valid target detected")
    end
end

-- Map controls to redstone outputs
local function applyControls()
    -- Movement controls
    --print(textutils.serialize(droneControls))
    local forward = 0
    if droneControls.forward then
        print("moving forward")
        redstone.setAnalogOutput("top", 1)
        forward = 1
    else
        redstone.setOutput("top",false)
    end

    if droneControls.backward then
        redstone.setAnalogOutput("back", 1)
        forward = -1
    else
        redstone.setOutput("back",false)
    end

    if droneControls.strafeLeft then
        redstone.setAnalogOutput("right", 1)
    else
        redstone.setOutput("right",false)
    end

    if droneControls.strafeRight then
        redstone.setAnalogOutput("left", 1)
    else
        redstone.setOutput("left",false)
    end
    local turning = 0
    local vertical = 0
    if droneControls.turnLeft then
        turning = 1
    elseif droneControls.turnRight then
        turning = -1
    end

    if droneControls.goUp then
        vertical = 1
    elseif droneControls.goDown then
        vertical = -1
    end

    helm.move(turning,vertical,forward)

    if droneControls.designate then
        designation()
    end
end

local function controlLoop()
    while true do
        applyControls()
        sleep() -- 20Hz update rate
    end
end

local function modemHandler()
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if channel == droneControlChannel then
            --print("recieved")
            droneControls = message
        end
    end
end

-- Start all threads
parallel.waitForAll(
    controlLoop,
    modemHandler
)