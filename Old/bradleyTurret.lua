local modem = peripheral.find("modem")
local cannon = peripheral.find("cbcmodernwarfare:compact_mount")

local cannonHitPosChannel = nil
print("Input the channel you want to use, default: 700")
cannonHitPosChannel = io.read()
if cannonHitPosChannel == "" then
    cannonHitPosChannel = 700
end
cannonHitPosChannel = tonumber(cannonHitPosChannel)

print("Input the channel you want to use, default: 500")
controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 500
end
controlChannel = tonumber(controlChannel)

print("Do you want to disassemble cannon, yes or no, press enter to skip")
disassemble = io.read()
if disassemble == "yes" then
    cannon.disassemble()
    error("disassebled")
end

print("Input the yaw compensation you want to use, default: 270")
yawCompensation = io.read()
if yawCompensation == "" then
    yawCompensation = 270
end
yawCompensation = tonumber(yawCompensation)

cannon.assemble()

if modem then
    modem.open(cannonHitPosChannel)
    modem.open(controlChannel)
end

local distance = 100
local setToPitch, controls

-- Normalize a vector
local function normalizeVector(v)
    local length = math.sqrt(v[1]^2 + v[2]^2 + v[3]^2)
    if length == 0 then
        return {0, 0, 0}
    end
    return {v[1] / length, v[2] / length, v[3] / length}
end

-- Normalize the rotation matrix
local function normalizeRotationMatrix(rotMatrix)
    local normalizedMatrix = {}
    for i = 1, #rotMatrix do
        normalizedMatrix[i] = normalizeVector(rotMatrix[i])
    end
    return normalizedMatrix
end

-- Get the pitch of the ship
local function getPitch()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return math.asin(normalizedMatrix[2][3]) -- Extract pitch from the matrix
end
--pitch = math.deg(math.asin(ship.getTransformationMatrix()[2][3]))
-- Get the yaw of the ship
local function getYaw()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return math.atan2(-normalizedMatrix[3][1], -normalizedMatrix[3][3]) -- Extract yaw from the matrix
end

-- Get the roll of the ship
local function getRoll()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return math.atan2(normalizedMatrix[2][1], normalizedMatrix[2][2]) -- Extract roll from the matrix
end

--Main loop
local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == cannonHitPosChannel then
                setToPitch = message
            elseif channel == controlChannel then
                controls = message
            end
        else
            sleep()
        end
    end
end

local function findRelativeAngle(targetYaw,targetPitch)
    rot = ship.getQuaternion()
    cacheYaw = math.pi - math.rad(targetYaw)
    cachePitch = - math.rad(targetPitch)
    rotMatAdj11 = 1 - 2*(rot.x^2 + rot.y^2)
    rotMatAdj12 = 2*(rot.z * rot.x + rot.y * rot.w)
    rotMatAdj13 = 2*(rot.z * rot.y - rot.x * rot.w)
    rotMatAdj21 = 2*(rot.z * rot.x - rot.y * rot.w)
    rotMatAdj22 = 1 - 2*(rot.z^2 + rot.y^2)
    rotMatAdj23 = 2*(rot.x * rot.y + rot.z * rot.w)
    rotMatAdj31 = 2*(rot.z * rot.y + rot.x * rot.w)
    rotMatAdj32 = 2*(rot.x * rot.y - rot.z * rot.w)
    rotMatAdj33 = 1 - 2*(rot.z^2 + rot.x^2)

    rotMatTGT11 = math.cos(cacheYaw) * math.cos(cachePitch)
    rotMatTGT21 = math.sin(cacheYaw) * math.cos(cachePitch)
    rotMatTGT31 = - math.sin(cachePitch)
    
    rotMatRSLT11 = rotMatAdj11 * rotMatTGT11 + rotMatAdj12 * rotMatTGT21 + rotMatAdj13 * rotMatTGT31
    rotMatRSLT21 = rotMatAdj21 * rotMatTGT11 + rotMatAdj22 * rotMatTGT21 + rotMatAdj23 * rotMatTGT31
    rotMatRSLT31 = rotMatAdj31 * rotMatTGT11 + rotMatAdj32 * rotMatTGT21 + rotMatAdj33 * rotMatTGT31

    turretYaw = math.atan2(rotMatRSLT21, rotMatRSLT11)
    barrelPitch = math.asin(-rotMatRSLT31)
    return math.deg(-turretYaw),math.deg(-barrelPitch)
end


local function setPitch()
    while true do
        if cannon and setToPitch and setToPitch.yaw and setToPitch.pitch then
            print(textutils.serialize(setToPitch))
            local requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(setToPitch.yaw,setToPitch.pitch)
            cannon.setPitch(math.max(requiredRelativePitch,-10))
            cannon.setYaw(math.min(math.max(requiredRelativeYaw,yawCompensation-360-3),yawCompensation-360+3))
        end
        sleep()
    end
end

local function fire()
    while true do
        if controls and controls.fireCannon then
            print("firing")
            cannon.fire()
			redstone.setOutput("back",true)
        else
			redstone.setOutput("back",false)
        end
        if controls and controls.fireAutocannon then
            print("firing autocannon")
            redstone.setOutput("bottom",true)
        else
            redstone.setOutput("bottom",false)
        end
        sleep()
    end
end

parallel.waitForAny(
    function() 
        while true do
            local hitPos = {}
            local sourceData = {}
        
            cannonPitch = cannon.getPitch()
        
            local source = ship.getWorldspacePosition()
            local sourceX, sourceY, sourceZ = source.x, source.y, source.z
        
            local yaw = math.deg(getYaw()) + yawCompensation
            
            local shipPitch = math.deg(getRoll())
            local shipRoll = math.deg(getPitch())
            --print("cannonPitch: "..cannonPitch)
            --print(" shipPitch: "..shipPitch)
            --print("shipRoll: "..shipRoll)
            local pitch = cannonPitch * math.sin(math.rad(90-shipRoll)) + shipPitch
            local yawAdjust = cannonPitch * math.cos(math.rad(90 - shipRoll))
            --print("yawAd: "..yawAdjust)
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
        
            --print("targetX: "..targetX.." targetY: "..targetY.." targetZ: "..targetZ)
        
            --print(" pitch: "..pitch)
            --print(" yaw: "..yaw)
        
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
    end,
    setPitch,
    modemMessage,
    fire
)
