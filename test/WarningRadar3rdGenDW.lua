local leftRC = peripheral.wrap("left")
local rightRC = peripheral.wrap("right")
local modem = peripheral.find("modem")
local monitor = peripheral.find("monitor")

local startingYaw = 0

local cannonHitPosChannel = 700
if modem then
    modem.open(cannonHitPosChannel)
end

local max_distance = 800
local shipBlock = {}

local function castLeftRay(pitch,yaw)
    local var1 = math.deg(pitch)
    local var2 = math.deg(yaw)
    local var3 = 1
    local euler_mode = false
    local immediate_execution = true
    local check_for_blocks_in_world = true

    local result = leftRC.raycast(max_distance, {var1, var2, var3}, euler_mode, immediate_execution)

    -- Check the result

    if result.ship_id then
        print("No hit detected within " .. max_distance .. " blocks.")
        print("Hit position: "..result.hit_pos[1].." , "..result.hit_pos[2].." , "..result.hit_pos[3])
    end

    -- Insert "coordinate" text into the hit_pos table at the fourth position
    if result.ship_id then

    end
end


local function castRightRay(pitch, yaw)
    local var1 = math.rad(pitch)
    local var2 = math.rad(yaw)
    local var3 = 1
    local euler_mode = false
    local immediate_execution = true
    local check_for_blocks_in_world = true

    local result = rightRC.raycast(max_distance, {var1, var2, var3}, euler_mode, immediate_execution)

    -- Check the result
    if result.ship_id then
        -- Ship detected, record hit position in shipBlock table
        print("Ship hit at position: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
        print("Recording hit position in shipBlock table")
        
        -- Insert the hit position into the shipBlock table
        table.insert(shipBlock, {
            x = result.hit_pos[1],
            y = result.hit_pos[2],
            z = result.hit_pos[3],
            ship_id = result.ship_id
        })

        print("Recorded hit at: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
    end
end



local function main()
    while true do
        monitor.setTextScale(0.5)
        local minPitch = -90 -- Keep the pitch fixed (looking straight ahead)
        local maxPitch = 90
        local pitchIncrement = 5
        local minYaw = -90
        local maxYaw = 90
        local yawIncrement = 5
        local shipResults = {} -- Table to store the results of each ship hit

        -- Clear the monitor
        monitor.clear()
        monitor.setCursorPos(1, 1)
        shipBlock = {}

        -- Scan across 180 degrees
        for yaw = minYaw, maxYaw, yawIncrement do
            for pitch = minPitch, maxPitch, pitchIncrement do
                castRightRay(pitch, yaw)
            end
            sleep()
        end

        -- Print the results to the monitor
        monitor.setCursorPos(1, 1)
        
        if #shipBlock == 0 then
            monitor.write("No ships detected.")
        else
            for i, result in ipairs(shipBlock) do
                monitor.write(string.format("Hit %d: X: %d, Y: %d, Z: %d, Ship ID: %s\n", i, result.x, result.y, result.z, result.ship_id))
                local x, y = monitor.getCursorPos()
                monitor.setCursorPos(1, y + 1)
                monitor.clearLine()
            end
        end

        os.sleep()
    end
end

-- Cast the ray and return the hit coordinates
parallel.waitForAny(
    main
)
