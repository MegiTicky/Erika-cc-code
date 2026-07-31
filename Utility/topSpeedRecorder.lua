-- Initialize variables
local highestSpeed = 0  -- Variable to store the highest speed
local currentSpeed = 0  -- Variable to store the current speed
local lastTime = os.clock()  -- Time of the last update
local dt = 0  -- Time difference (delta time)

-- Function to get the current speed of the ship
local function getCurrentSpeed()
    local shipVelocity = ship.getVelocity()  -- Get the ship's velocity as a vector
    currentSpeed = math.sqrt(shipVelocity.x^2 + shipVelocity.y^2 + shipVelocity.z^2)  -- Calculate the speed (magnitude of the velocity vector)
    return currentSpeed
end

-- Function to update and check the highest speed
local function updateHighestSpeed()
    -- Get the current speed
    local speed = getCurrentSpeed()

    -- Compare and update the highest speed if needed
    if speed > highestSpeed then
        highestSpeed = speed
        print("New highest speed: " .. highestSpeed)  -- Print the new highest speed
    end
end

-- Main loop
while true do
    -- Calculate delta time
    local currentTime = os.clock()
    dt = currentTime - lastTime
    lastTime = currentTime

    -- Update the highest speed
    updateHighestSpeed()

    -- Sleep for a short time to reduce CPU usage
    sleep()
end
