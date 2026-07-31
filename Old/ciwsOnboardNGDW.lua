local modem = peripheral.find("modem")
local reader = peripheral.find("blockReader")

redstone.setOutput("back",false)
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

if not reader then
    print("No blockReader found.")
end

local distance = 100

--Main loop
while true do
    redstone.setOutput("back",true)
    local hitPos = {}
    local sourceData = {}

    if reader then
        cannonData = reader.getBlockData()
        cannonPitch = cannonData.CannonPitch
    else
        cannonPitch = 0
    end

    local source = ship.getWorldspacePosition()
    local sourceX, sourceY, sourceZ = source.x, source.y, source.z

    local yaw = math.deg(ship.getYaw()) + 90
    
    local shipPitch = math.deg(ship.getRoll())
    local shipRoll = math.deg(ship.getPitch())
    print("cannonPitch: "..cannonPitch)
    print(" shipPitch: "..shipPitch)
    print("shipRoll: "..shipRoll)
    local pitch = cannonPitch * math.sin(math.rad(90-shipRoll)) + shipPitch
    local yawAdjust = cannonPitch * math.cos(math.rad(90 - shipRoll))
    print("yawAd: "..yawAdjust)
    if shipRoll < 0 then
        yaw = yaw + math.abs(yawAdjust)
    else
        yaw = yaw - math.abs(yawAdjust)
    end
    if yaw > 360 then yaw = yaw - 360 end
    if yaw < 0 then yaw = yaw + 360 end
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
    
    sleep()
end