radar = peripheral.find("sp_radar")

-- Function to calculate the distance between two points
local function distance(pos1, pos2)
    return math.sqrt((pos1.x - pos2.x)^2 + (pos1.y - pos2.y)^2 + (pos1.z - pos2.z)^2)
end

-- Main program to scan and print positions and distances of detected ships
while true do
    -- Scan for ships within 10000 meters
    local ships = radar.scanForShips(2500)
    
    -- Get the current position of the ship
    local myPos = ship.getWorldspacePosition()

    -- Print out information for each detected ship
    for _, ship in ipairs(ships) do
        local shipPos = ship.pos
        local dist = distance(myPos, shipPos)
        print(string.format("Ship ID: %s, Position: (%.2f, %.2f, %.2f), Distance: %.2f meters", ship.id, shipPos.x, shipPos.y, shipPos.z, dist))
    end
    
    -- Sleep for a short time before scanning again
    sleep(1)
end
