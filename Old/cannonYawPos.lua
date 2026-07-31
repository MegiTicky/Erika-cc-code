-- Peripheral setup
local modemSide = "right"  -- The side of the computer where the modem is connected
local shipSide = "bottom"  -- The side of the computer where the ship's peripheral is connected

-- Wrap the modem peripheral
local modem = peripheral.find("modem")
if not modem then
    error("Could not find a modem on the side: " .. modemSide)
end

if not ship then
    error("Could not find a ship on the side: " .. shipSide)
end

-- Wrap the block reader
local reader = peripheral.find("blockReader")

-- Channels for transmitting data
local yawChannel = 300  -- The channel for transmitting the yaw
local Xchannel = 301 -- The channel for transmitting the X coordinate
local Ychannel = 302
local Zchannel = 303  -- The channel for transmitting the Z coordinate
local pitchChannel = 304
local statusChannel = 305

-- Make sure the modem is open on the channels you want to use
modem.open(yawChannel)
modem.open(Xchannel)
modem.open(Ychannel)
modem.open(Zchannel)
modem.open(pitchChannel)
modem.open(statusChannel)

-- Function to convert radians to degrees
local function toDegrees(radians)
    return radians * (180 / math.pi)
end

-- Function to convert degrees to a bearing
local function toBearing(degrees)
    local bearing = degrees % 360
    if bearing < 0 then
        bearing = 360 + bearing
    end
    return bearing
end

-- Main loop to constantly transmit the yaw, pitch, and position data
while true do
    -- Yaw data
    local matrix = ship.getRotationMatrix()

    -- Calculate the yaw from the rotation matrix
    local forwardX = matrix[1][3]  -- Forward vector X (first row, third column)
    local forwardZ = matrix[3][3]  -- Forward vector Z (third row, third column)

    -- Compute yaw in radians
    local yawRadians = math.atan2(-forwardX, forwardZ)  -- atan2 expects (x, z), but x should be negated to adjust for the direction

    -- Convert yaw to degrees and normalize to 0-360 range
    local yawDegrees = toDegrees(yawRadians)
    local yawBearing = toBearing(yawDegrees) - 180
    if yawBearing < 0 then
        yawBearing = yawBearing + 360
    end


    -- Transmit yaw data

    -- Position data
    local pos = ship.getWorldspacePosition()
    local sourceX = pos.x
    local sourceY = pos.y + 2
    local sourceZ = pos.z

    -- Get the ship's rotation matrix
    local matrix = ship.getRotationMatrix()

    -- Pitch data
    local cannonData = reader.getBlockData()
    local cannonPitch = cannonData.CannonPitch
    -- Convert ship's pitch to degrees and apply the sign
    shipPitch = toDegrees(-math.asin(ship.getRotationMatrix()[2][3]))
    print("shipPitch: ",shipPitch)

    -- Adjust cannon pitch with the ship's pitch
    -- If the ship's pitch is negative (nose down), we add it to the cannon pitch
    local trueCannonPitch = cannonPitch + shipPitch

    -- Ensure the true cannon pitch is positive if the cannon is pointing upward
    modem.transmit(yawChannel, 0, yawBearing)
    print("Transmitting Yaw: " .. yawBearing)
    modem.transmit(pitchChannel, 0, trueCannonPitch)
    modem.transmit(Xchannel, 0, sourceX)
    modem.transmit(Ychannel, 0, sourceY)
    modem.transmit(Zchannel, 0, sourceZ)
    modem.transmit(statusChannel, 0, cannonData.Running)
    print("Transmitting X: " .. sourceX)
    print("Transmitting Y: " .. sourceY)
    print("Transmitting Z: " .. sourceZ)
    print("Transmitting True Cannon Pitch: " .. trueCannonPitch)
    print("Running: ",cannonData.Running)

    -- Wait for a short time before next transmission
    sleep(0.05)
end

yawBearing = yawBearing - 90
if yawBearing < 0 then
    yawBearing = yawBearing + 360
end