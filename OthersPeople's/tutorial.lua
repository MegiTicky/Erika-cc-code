local radar = peripheral.find("sp_radar")
--[[while true do
    shipPos = ship.getWorldspacePosition()
    numberOfShips = 0
    radarScanResult = radar.scanForShips(2000)
    longestDistance = 0
    local furtherShipPos

    for i,object in ipairs(radarScanResult) do
        local dx = object.pos.x - shipPos.x
        local dy = object.pos.y - shipPos.y
        local dz = object.pos.z - shipPos.z
        local distance = math.sqrt(dx^2 + dy^2 + dz^2)
        if distance > longestDistance then
            furtherShipPos = object.pos
            longestDistance = distance
        end
    end
    print(textutils.serialize(furtherShipPos))
    sleep()
end]]

local furtherShipPos,longestDistance,id = nil,0,nil
shipPos = {x=0,y=0,z=0}
radarScanResult = {
    {x = 50,y = 20, z = 10},
    {x = 30,y = 10, z = 20},
    {x = 20,y = 10, z = 60}
}
for _,pos in ipairs(radarScanResult) do
    local dx = pos.x - shipPos.x
    local dy = pos.y - shipPos.y
    local dz = pos.z - shipPos.z
    local distance = math.sqrt(dx^2 + dy^2 + dz^2)
    if distance > longestDistance then
        furtherShipPos = pos
        longestDistance = distance
        id = _
    end
end
print(textutils.serialize(furtherShipPos))
print(longestDistance)
print(id)

