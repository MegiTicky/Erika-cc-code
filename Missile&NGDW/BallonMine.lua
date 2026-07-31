local radar = peripheral.find("sp_radar")
local RS = {detonation = "bottom", ballon = "top"}
local detonationRadius = 8  -- Define the horizontal radius for detection (in meters or game units)
local detectionRadius = 100  -- Maximum detection radius
local targetAltitude = math.random(100, 300)  -- Random target altitude between 100 and 500
local altitudeProportionalGain = 0.4  -- Proportional gain for altitude control
local maxThrust = 10  -- Maximum thrust value for the balloon

print("Press enter to arm")
io.read()

-- Function to control altitude using a proportional system
local function controlAltitude(currentAltitude)
    -- Calculate the altitude error
    local altitudeError = targetAltitude - currentAltitude
    
    -- Apply the proportional control: thrust is proportional to the altitude error
    local thrust = altitudeError * altitudeProportionalGain
    
    -- Constrain the thrust to be within a safe range (not too high)
    thrust = math.max(-maxThrust, math.min(maxThrust, thrust))
    
    -- Apply the calculated thrust to the balloon (top redstone input)
    redstone.setAnalogOutput(RS.ballon, thrust)
    
    -- Print the status
    print("Current Altitude: " .. currentAltitude)
    print("Target Altitude: " .. targetAltitude)
    print("Thrust: " .. thrust)
end

while true do
    -- Get the current position of the mine
    local pos = ship.getWorldspacePosition()
    local missileX, missileY, missileZ = pos.x, pos.y, pos.z

    -- Check if there are any nearby ships (for detonation logic)
    local results = radar.scanForShips(detectionRadius)
    local targetDetected = false  -- Flag to check if a target is detected

    -- Loop through the radar scan results
    for i, object in ipairs(results) do
        local targetPos = object.pos
        local dx = targetPos.x - missileX
        local dz = targetPos.z - missileZ
        local dy = targetPos.y - missileY
        local distance = math.sqrt(dx^2 + dy^2 + dz^2)
        print(distance)
        if distance <= detonationRadius and distance > 1 then
            -- Detonate if within detonation radius
            
            redstone.setOutput(RS.detonation, true)
            error("detonated")
        else
            redstone.setOutput(RS.detonation, false)
        end
    end

    -- Control the altitude to hover at the desired height
    controlAltitude(missileY)
    
    -- Sleep for a short duration before scanning again
    sleep()
end
