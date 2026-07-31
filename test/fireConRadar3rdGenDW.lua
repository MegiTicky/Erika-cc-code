local leftRC = peripheral.wrap("left")
local rightRC = peripheral.wrap("right")
local topRC = peripheral.wrap("top")
local bottomRC = peripheral.wrap("bottom")
local modem = peripheral.find("modem")
local monitor = peripheral.find("monitor")

print("Input the radarResultChannel, default: 400")
local radarResultChannel = io.read()
if radarResultChannel == "" then
    radarResultChannel = 400
end
radarResultChannel = tonumber(radarResultChannel)

print("Input the shipHeading compensation, default: 0")
local shipHeadingCompensation = io.read()
if shipHeadingCompensation == "" then
    shipHeadingCompensation = 0
end
shipHeadingCompensation = tonumber(shipHeadingCompensation)

print("Input the max distance, default: 800")
local max_distance = io.read()
if max_distance == "" then
    max_distance = 800
end
max_distance = tonumber(max_distance)

local increment = 7 - max_distance * 0.05
if increment < 0 or increment == 0 then
    increment = 0.25
end
if modem then
    modem.open(radarResultChannel)
end

local shipBlock = {}
local lastKnownShipCenters = {}
local detectionCounter = {}  -- Store the count for each ship's detection misses
local detectionThreshold = max_distance/2  -- Threshold for removal after 50 misses
local leftRelativeYaw = 0
local rightRelativeYaw = 0
local backRelativeYaw = 0
local frontRelativeYaw = 0



-- Raycast for the left raycaster
local function castRay(raycasterSide)
    while true do
        local minPitch = -45
        local maxPitch = 45
        local minYaw = -45
        local maxYaw = 45

        local raycaster
        if raycasterSide == "left" then
            raycaster = leftRC
        elseif raycasterSide == "right" then
            raycaster = rightRC
        elseif raycasterSide == "top" then
            raycaster = topRC
        elseif raycasterSide == "bottom" then
            raycaster = bottomRC
        else
            error("Invalid raycaster side: " .. tostring(raycasterSide))
        end

        for yaw = minYaw, maxYaw, increment do
            leftRelativeYaw = yaw
            for pitch = minPitch, maxPitch, increment do
                local result = raycaster.raycast(max_distance, {math.rad(pitch), math.rad(yaw), 1}, false, true)
                if raycasterSide == "left" then
                    leftRelativeYaw = yaw
                elseif raycasterSide == "right" then
                    rightRelativeYaw = yaw
                elseif raycasterSide == "top" then
                    topRelativeYaw = yaw
                elseif raycasterSide == "bottom" then
                    bottomRelativeYaw = yaw
                end
                -- Check if a ship was hit
                if result and result.ship_id then
                    detectionCounter[result.ship_id] = 0

                    if not shipBlock[result.ship_id] then
                        shipBlock[result.ship_id] = {}
                    end
                    -- Add the hit position to the ship's hit positions
                    table.insert(shipBlock[result.ship_id], {
                        x = result.hit_pos[1],
                        y = result.hit_pos[2],
                        z = result.hit_pos[3]
                    })

                end
            end
            sleep()  -- Prevent CPU overloading
        end
        sleep() 
    end
end

-- Function to calculate the ship centers
local function calculateShipCenters()
    local shipCenters = {}

    -- Process the current shipBlock data
    for ship_id, hit_positions in pairs(shipBlock) do
        local total_x, total_y, total_z = 0, 0, 0
        local count = #hit_positions

        for _, pos in ipairs(hit_positions) do
            total_x = total_x + pos.x
            total_y = total_y + pos.y
            total_z = total_z + pos.z
        end

        -- Calculate the average position (center)
        shipCenters[ship_id] = {
            x = total_x / count,
            y = total_y / count,
            z = total_z / count
        }

        -- Update last known position for this ship
        lastKnownShipCenters[ship_id] = shipCenters[ship_id]
    end

    -- If a ship is not detected, use its last known position
    for ship_id, lastPos in pairs(lastKnownShipCenters) do
        if not shipCenters[ship_id] then
            detectionCounter[ship_id] = (detectionCounter[ship_id] or 0) + 1  -- Increment counter
            
            -- Remove the ship if its detection counter reaches the threshold
            if detectionCounter[ship_id] >= detectionThreshold then
                lastKnownShipCenters[ship_id] = nil
                detectionCounter[ship_id] = nil
            else
                -- Use the last known position if the ship hasn't reached the threshold yet
                shipCenters[ship_id] = lastPos
            end
        end
    end

    return shipCenters
end

-- Main function to display data on monitor and send it via modem
local function main()
    while true do
        -- Calculate ship centers based on collected data
        local shipCenters = calculateShipCenters()

        -- Display the results on the monitor
        if monitor then
            monitor.clear()
            monitor.setCursorPos(1, 1)
            monitor.setTextScale(0.5)

            if next(shipCenters) == nil then
                monitor.write("No ships detected.")
            else
                for ship_id, center in pairs(shipCenters) do
                    monitor.write(string.format("Ship ID: %s\nCenter: X: %.2f, Y: %.2f, Z: %.2f\n", ship_id, center.x, center.y, center.z))
                    local x, y = monitor.getCursorPos()
                    monitor.setCursorPos(1, y + 1)
                    monitor.clearLine()
                end
            end
        end

        -- Print to terminal for debugging
        if false then
            print("Completing loop"..os.time())
            print(textutils.serialize(shipCenters))
        end

        -- Send data over modem
        if modem then
            modem.transmit(radarResultChannel, 0, {
                shipCenters = shipCenters,
            })
        end
        shipBlock = {}

        os.sleep()
    end
end

-- Run the left raycasting, right raycasting, and main function in parallel
parallel.waitForAny(
    function() castRay("left") end,
    function() castRay("right") end,
    function() castRay("top") end,
    function() castRay("bottom") end,
    main
)
