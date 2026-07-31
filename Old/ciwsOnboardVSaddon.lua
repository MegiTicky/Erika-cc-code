local modem = peripheral.find("modem")
local mount = peripheral.find("cbcmf_compact_cannon_mount")

local cannonHitPosChannel = nil
print("Input the channel you want to use, default: 700")
cannonHitPosChannel = io.read()
if cannonHitPosChannel == "" then
    cannonHitPosChannel = 700
end
cannonHitPosChannel = tonumber(cannonHitPosChannel)

if modem then
    modem.open(cannonHitPosChannel)
end

if not mount then
    print("No blockmount found.")
end

local distance = 100

--Main loop
while true do
    redstone.setOutput("back",true)
    local hitPos = {}
    local sourceData = {}

    if mount then
        cannonPitch = mount.getPitch()
    else
        cannonPitch = 0
    end

    local source = ship.getWorldspacePosition()
    local sourceX, sourceY, sourceZ = source.x, source.y, source.z

    local yaw = math.deg(ship.getYaw()) + 90
    if yaw > 360 then yaw = yaw - 360 end
    if yaw < 0 then yaw = yaw + 360 end
    local shipPitch = math.deg(ship.getRoll())
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
    print("transmitting on"..cannonHitPosChannel)
    sleep()
end