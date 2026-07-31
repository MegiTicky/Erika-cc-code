local reader = peripheral.find("blockReader")
local modem = peripheral.find("modem")

local g = 0.04
local cd = 0.99

local c_est = 0.0028
local vm = 340 --muzzle velocity, medium cannon = 60 + 20*barrel length
local u = vm/20 --speed per tick maybe, idk

print("Input the y height compensation (how far the center of gravity of this ship is to the cannon), default = -10")
local yLevelCompensation = io.read()
if yLevelCompensation == "" then
    yLevelCompensation = -10
end
yLevelCompensation = tonumber(yLevelCompensation)

print("Input the yaw compensation. (test 0,90,180,270 until the yaw is correct), default = 90")
local yawCompensate = io.read()
if yawCompensate == "" then
    yawCompensate = 90
end
yawCompensate = tonumber(yawCompensate)

print("Input the muzzle velocity (default: 340)")
local vm = io.read()
if vm == "" then
    vm = 340
end
vm = tonumber(vm)

print("Input ship pitch cannon pitch compensation, type(-pitch,+pitch,-roll,+roll,none), default: -pitch")
local cannonPitchCom = io.read()
if cannonPitchCom == "" then
    cannonPitchCom = "-pitch"
end

print("Input the cannon data transmition channel (default: 900)")
local cannonDataChannel = io.read()
if cannonDataChannel == "" then
    cannonDataChannel = 900
end
cannonDataChannel = tonumber(cannonDataChannel)


if modem then
    modem.open(cannonDataChannel)
end

function calculateRange(a)
    local radians = math.rad(a)

    local part1 = u * math.cos(radians) / math.log(cd)
    local part2 = ((g * cd) / (g * cd + (1 - cd) * u * math.sin(radians))) ^ (2 + c_est * vm * math.sin(radians)) - 1
    local XR = part1 * part2

    return XR
end

function calculateHitPosition(shipPosition, cannonYaw, cannonPitch)
    local range = calculateRange(cannonPitch)
    local yawRadians = math.rad(cannonYaw)
    local deltaX = range * math.sin(yawRadians)  -- Change in the x-direction
    local deltaZ = -range * math.cos(yawRadians)  -- Change in the z-direction

    local targetX = shipPosition.x + deltaX
    local targetZ = shipPosition.z + deltaZ

    return {x = targetX, z = targetZ}
end

local pitch = 40
local range = calculateRange(pitch)
print("The calculated range for a pitch of " .. pitch .. " degrees is: " .. range)

while true do
    cannonData = reader.getBlockData()
    cannonPitch = cannonData.CannonPitch
    if cannonPitchCom == "-pitch" then
        cannonPitch = cannonPitch - math.deg(ship.getPitch())
        print("adjusted pitch with -pitch: "..cannonPitch)
    elseif cannonPitchCom == "+pitch" then
        cannonPitch = cannonPitch + math.deg(ship.getPitch())
        print("adjusted pitch with +pitch: "..cannonPitch)
    elseif cannonPitchCom == "-roll" then
        cannonPitch = cannonPitch - math.deg(ship.getRoll())
        print("adjusted pitch with -roll: "..cannonPitch)
    elseif cannonPitchCom == "+roll" then
        cannonPitch = cannonPitch + math.deg(ship.getRoll())
        print("adjusted pitch with +roll: "..cannonPitch)
    else
        print("Not adjusting pitch with ship pitch")
    end

    cannonYaw = math.deg(ship.getYaw()) + yawCompensate
    data = {}

    if cannonYaw<0 then
        cannonYaw = cannonYaw + 360
    end
    print(cannonYaw)
    
    pos = ship.getWorldspacePosition()
    pos.y = pos.y + yLevelCompensation --fire control radar posistion compensation
    if cannonPitch > 0 then
        distance = calculateRange(cannonPitch)
        hitPos = calculateHitPosition(pos,cannonYaw,cannonPitch)
        print("hit posisiton: "..hitPos.x.." Y: "..pos.y.." ,Z: "..hitPos.z)
        data = {
            x = hitPos.x,
            y = hitPos.y,
            z = hitPos.z,
            cannonPitch = cannonPitch,
            cannonYaw = cannonYaw,
            source = pos
        }
        modem.transmit(cannonDataChannel,0,data)
    else
        data = {
            cannonPitch = cannonPitch,
            cannonYaw = cannonYaw,
            source = pos
        }
        modem.transmit(cannonDataChannel,0,data)
    end
    print("cannonPitch: "..cannonPitch)
    print("cannonYaw: "..cannonYaw)

    sleep()
end