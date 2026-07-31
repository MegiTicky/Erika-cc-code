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
local Xchannel = 20
local Ychannel = 21
local Zchannel = 22
local pitchChannel = 23
local yawChannel = 24

-- Make sure the modem is open on the channels you want to use
modem.open(yawChannel)
modem.open(Xchannel)
modem.open(Ychannel)
modem.open(Zchannel)
modem.open(pitchChannel)

-- Function to convert radians to degrees
local function toDegrees(radians)
    return radians * (180 / math.pi)
end

-- Function to convert degrees to a bearing
local function toBearing(degrees)
    local bearing = degrees % 360
    bearing = bearing - 270
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
    local yawBearing = toBearing(yawDegrees)
    if yawBearing < 0 then
        yawBearing = yawBearing +360
    end


    -- Transmit yaw data
    modem.transmit(yawChannel, 0, yawBearing)
    

    -- Position data
    local pos = ship.getWorldspacePosition()
    local sourceX = pos.x
    local sourceY = pos.y
    local sourceZ = pos.z
    modem.transmit(Xchannel, 0, sourceX)
    modem.transmit(Ychannel, 0, sourceY)
    modem.transmit(Zchannel, 0, sourceZ)
    

    -- Get the ship's rotation matrix
    local matrix = ship.getRotationMatrix()

    -- Pitch data
    local cannonData = reader.getBlockData()
    local cannonPitch = cannonData.CannonPitch

    -- Calculate the ship's pitch from the rotation matrix
    local shipPitchCos = matrix[2][2]  -- Cosine of the ship's pitch angle
    local shipPitch = math.acos(shipPitchCos)  -- Ship's pitch in radians
    local shipPitchSign = matrix[3][2] >= 0 and 1 or -1

    -- Convert ship's pitch to degrees and apply the sign
    shipPitch = shipPitchSign * math.deg(ship.getRoll())

    -- Adjust cannon pitch with the ship's pitch
    -- If the ship's pitch is negative (nose down), we add it to the cannon pitch
    local trueCannonPitch = cannonPitch

    -- Ensure the true cannon pitch is positive if the cannon is pointing upward
    print("Transmitting Yaw: " .. yawBearing)
    print("Transmitting X: " .. sourceX)
    print("Transmitting Y: " .. sourceY)
    print("Transmitting Z: " .. sourceZ)
    trueCannonPitch = trueCannonPitch
    print("Canonpitch:",cannonPitch)
    print("shipPitch: ",shipPitch)
    modem.transmit(pitchChannel, 0, trueCannonPitch)
    print("Transmitting True Cannon Pitch: " .. trueCannonPitch)

    -- Wait for a short time before next transmission
    sleep(0.01)
end

yawBearing = yawBearing - 90
if yawBearing < 0 then
    yawBearing = yawBearing + 360
end