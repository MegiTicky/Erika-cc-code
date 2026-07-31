local modem = peripheral.find("modem")
local reader = peripheral.find("blockReader")

local cannonHitPosChannel = 700
local cannonSourceChannel = 701
if modem then
    modem.open(cannonHitPosChannel)
end

if not reader then
    print("No blockReader found.")
end

local distance = 100

--Main loop
while true do
    local hitPos = {}
    local sourceData = {}

    cannonPitch = 0

    local source = ship.getWorldspacePosition()
    local sourceX, sourceY, sourceZ = source.x, source.y, source.z

    local yaw = math.deg(ship.getYaw())
    if yaw < 0 then yaw = yaw + 360 end
    local matrix = ship.getRotationMatrix()
    local shipPitchCos = matrix[2][2]  -- Cosine of the ship's pitch angle
    local shipPitch = math.acos(shipPitchCos)  -- Ship's pitch in radians

    print(" shipPitch: "..shipPitch)
    local pitch = shipPitch + cannonPitch
    local yawRad = math.rad(yaw)
    local pitchRad = math.rad(pitch)

    local dx = distance * math.cos(pitchRad) * math.sin(yawRad)
    local dz = -distance * math.cos(pitchRad) * math.cos(yawRad)
    local dy = distance * math.sin(pitchRad)

    local targetX = sourceX + dx
    local targetY = sourceY + dy
    local targetZ = sourceZ + dz

    print("targetX: "..targetX.." targetY: "..targetY.." targetZ: "..targetZ)

    print(" pitch: "..pitch)
    print(" yaw: "..yaw)

    table.insert(sourceData, 1, targetX)
    table.insert(sourceData, 2, targetY)
    table.insert(sourceData, 3, targetZ)
    table.insert(sourceData, 4, "coordinate")
    table.insert(sourceData, 5, source)
    table.insert(sourceData, 6, pitch)
    table.insert(sourceData, 7, yaw)
    modem.transmit(cannonHitPosChannel,0,sourceData)
    
    print(textutils.serialize(sourceData))
    sleep()
end