modem = peripheral.wrap("right")
camera = peripheral.find("camera")
yawMotor = peripheral.wrap("back")
pitchMotor = peripheral.wrap("front")

local controls = {cannonControlMode = "mouseAim"}
local recievedInfo = nil
-----------------
--Configuration--
-----------------
--120mm Green Mace
local MAG_SIZE    = 9999       -- rounds per magazine
local RELOAD_TIME = 0       -- seconds
local FIRE_RPM    = 600       -- rounds per minute
local elevateTraverseSpeed = 20 -- angle per 0.5s
-- spread settings (AREA at convergence plane, in blocks^2)
local spreadArea = 10
-- basllist
local projectileSpeed = 240  -- blocks/sec (set to your gun's muzzle velocity)
local g =  0.05
local cd = 0.995

local cannons = {}
local k = 1
local nilCount = 0
local i = 0
peripheralfindFound = false

local FIRE_SIDE = "left"

yawMotor.setTargetSpeed(0)
pitchMotor.setTargetSpeed(0)
redstone.setOutput(FIRE_SIDE,false)
while nilCount < 200 do
    local cannon = peripheral.wrap("createbigcannons:cannon_mount_"..tostring(i)) or peripheral.wrap("cbcmodernwarfare:compact_mount_"..tostring(i))
    if not(cannon) and not(peripheralfindFound) then
        cannon = peripheral.find("createbigcannons:cannon_mount") or peripheral.find("cbcmodernwarfare:compact_mount")
        peripheralfindFound = true
    end

    if cannon then
        cannon.assemble()
        cannons[k] = cannon
        k = k + 1
        nilCount = 0
        print("found cannon")
    else
        nilCount = nilCount + 1
    end
    i = i + 1
end
print("Found "..#cannons.." cannons")
function askUser(prompt, defaultValue)
    print(prompt .. " (default (press enter to use default): " .. defaultValue .. ")")
    print("Automatically applying default value in 10sec")

    local timer = os.startTimer(10)  -- Set a timer for 10 seconds
    local input = ""
    local isTimedOut = false

    -- Start a loop to capture user input or wait for the timer
    while true do
        local event, param = os.pullEvent()
        if event == "timer" and param == timer then
            -- Timer expired, apply the default value
            isTimedOut = true
            break
        elseif event == "char" then
            print(param)
            -- Capture character input from the user
            input = input .. param
        elseif event == "key" then
            --print(param)
            if param == 257 then  -- Enter key (key code 28)
                -- User pressed Enter
                print("enter pressed")
                break
            end
        end
    end

    -- If the input is empty and timed out, return the default value
    if isTimedOut or input == "" then
        return defaultValue
    else
        return input
    end
end



function errorCheck()
    while not(modem) do
        print("Modem not connected, retrying")
        modem = peripheral.find("modem")
        sleep(0.5)
    end
end
errorCheck()

gunCommunicaitonChannel = tonumber(askUser("Input the gun communication channel",1021))
AntiAirChannel = askUser("Input the channel number",1020)
AntiAirChannel = tonumber(AntiAirChannel)
print("Used anti air channel: "..AntiAirChannel)
modem.open(AntiAirChannel)
modem.open(gunCommunicaitonChannel)
---------------------
--Finding pitch yaw--
---------------------
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

local function calculateRange(angle, u, cd, g, c_est, projectileSpeed)
    local radians = math.rad(angle)
    local u = projectileSpeed/20
    local part1 = u * math.cos(radians) / math.log(cd)
    local part2 = ((g * cd) / (g * cd + (1 - cd) * u * math.sin(radians))) ^ (2 + c_est * projectileSpeed * math.sin(radians)) - 1
    local XR = part1 * part2

    return XR
end

local function findBestPitch(targetX, targetY, targetZ, sourceX, sourceY, sourceZ, initialVelocity, g, cd, c_est, projectileSpeed)
    local bestLowPitch = nil
    local bestHighPitch = nil
    local bestLowDistance = math.huge
    local bestHighDistance = math.huge
    local targetDistance = math.sqrt((targetX - sourceX)^2 + (targetZ - sourceZ)^2)

    for pitch = 0, 70, 0.15 do -- Iterate over pitch angles
        local calculatedRange = calculateRange(pitch, initialVelocity, cd, g, c_est, projectileSpeed)
        local distanceDifference = math.abs(calculatedRange - targetDistance)

        -- Find the low-angle solution
        if pitch <= 30 then
            if distanceDifference < bestLowDistance then
                bestLowDistance = distanceDifference
                bestLowPitch = pitch
            end
        -- Find the high-angle solution
        elseif pitch > 30 then
            if distanceDifference < bestHighDistance then
                bestHighDistance = distanceDifference
                bestHighPitch = pitch
            end
        end
    end

    --prioritize the low-angle solution
    return bestLowPitch
end

local requiredRelativeYaw, requiredRelativePitch, absYaw, absPitch
local function aimCannonDirect(targetPos, source)
    local dx = targetPos.x - source.x
    local dy = targetPos.y - source.y
    local dz = targetPos.z - source.z

    local x = math.sqrt(dx*dx + dz*dz)  -- horizontal distance
    local y = dy                         -- vertical difference

    -- yaw geometric
    local yaw = math.deg(math.atan2(-dx, dz))
    yaw = (yaw + 180) % 360
    --geometric pitch
    local horizontalDistance = math.sqrt(dx * dx + dz * dz)
    local pitch = math.deg(math.atan2(dy, horizontalDistance))
    -- ballistic pitch
    local ballisticPitch = findBestPitch(targetPos.x, targetPos.y, targetPos.z, source.x, source.y, source.z, projectileSpeed, g, cd, 0.0028, projectileSpeed)
    --print("ballisticPitch: "..ballisticPitch)
    if pitch > 60 then
        pitch = pitch
    else
        pitch = pitch + ballisticPitch
    end

    requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw, pitch)
    return requiredRelativeYaw, requiredRelativePitch, yaw, pitch
end

--------------------
--Cannon operation--
--------------------
math.randomseed(os.epoch("utc"))
local wasFiring = false

local function wrap180(a)
    a = (a + 180) % 360 - 180
    return a
end


local function PIDController(Kp, Ki, Kd, error, integral, derivative, prevError, dt)
    -- Calculate the proportional, integral, and derivative components
    local proportional = Kp * error
    integral = integral + error * dt
    derivative = (error - prevError) / dt
    
    -- Calculate output
    local output = proportional + (Ki * integral) + (Kd * derivative)

    -- Return the PID output and updated integral and previous error
    return output, integral, error
end

local lastYawTime = os.clock()
local yawIntegral, yawPrevError, yawSpeed = 0,0,0
local Kp_yaw, Ki_yaw, Kd_yaw = 0.5, 0, 0.01
-- Yaw control function using PID
local function yawControl(deltaYaw)
    local now = os.clock()
    local dtThisFrame = now - lastYawTime
    lastYawTime = now
    if dtThisFrame <= 0 then
        dtThisFrame = 0.05
    end

    --print(dtThisFrame)
    yawSpeed, newIntegral, newPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, deltaYaw, yawIntegral, (deltaYaw-yawPrevError),yawPrevError, dtThisFrame)

    -- Constrain the yaw speed to prevent runaway spinning
    yawSpeed = math.max(-18, math.min(18, yawSpeed))

    -- Set motor speed based on PID output
    yawMotor.setTargetSpeed(-yawSpeed)
end

local lastYawTime = os.clock()
local pitchIntegral, pitchPrevError, pitchSpeed = 0,0,0
local Kp_pitch, Ki_pitch, Kd_pitch = 0.7, 0, 0.08
-- Yaw control function using PID
local function pitchControl(deltaPitch)
    local now = os.clock()
    local dtThisFrame = now - lastYawTime
    lastYawTime = now
    if dtThisFrame <= 0 then
        dtThisFrame = 0.05
    end

    --print(dtThisFrame)
    pitchSpeed, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, deltaPitch, pitchIntegral, (deltaPitch-pitchPrevError),pitchPrevError, dtThisFrame)

    
    -- Constrain the yaw speed to prevent runaway spinning
    pitchSpeed = math.max(-18, math.min(18, pitchSpeed))

    -- Set motor speed based on PID output
    pitchMotor.setTargetSpeed(-pitchSpeed)
end

local function moveBearingCannon(yaw, pitch, firing, convDist, sourceInfo)
    local deltaYaw = wrap180(yaw - math.deg(sourceInfo.yaw))
    local deltaPitch = wrap180(pitch - math.deg(-sourceInfo.pitch))
    print("deltaYaw: "..deltaYaw.." deltaPitch: "..deltaPitch)
    yawControl(deltaYaw)
    pitchControl(deltaPitch)
end

-- Function to simulate random reload time
local function getRandomReloadTime(baseReloadTime)
    local randomOffset = math.random() * 1 - 0.5  -- Random value between -0.5 and 0.5
    return baseReloadTime + randomOffset
end
-- Internal fire state
local roundsLeft = MAG_SIZE
local nextShotAt = 0          -- ms epoch when the next shot is allowed
local reloadUntil = 0         -- ms epoch when reload completes
local lastReloadTime = RELOAD_TIME
local function nowMs()
    return os.epoch("utc")
end

-- state
local magEndAt = 0        -- ms epoch when current magazine "runs out"
local reloadUntil = 0     -- ms epoch when reload completes
local wasTrigger = false
-- Function to handle firing
local function fireCannons(trigger)
    trigger = (trigger == true)
    local t = nowMs()

    -- map desired FIRE_RPM to analog strength (your mechanic)
    local redstoneSignal = math.floor(15 * (FIRE_RPM / 300))
    if redstoneSignal < 1 then redstoneSignal = 1 end
    if redstoneSignal > 15 then redstoneSignal = 15 end

    -- trigger released: stop firing + reset state
    if not trigger then
        redstone.setAnalogOutput(FIRE_SIDE, 0)
        wasTrigger = false
        magEndAt = 0
        return
    end

    -- if currently reloading, keep output off
    if t < reloadUntil then
        redstone.setAnalogOutput(FIRE_SIDE, 0)
        return
    end

    -- start a new magazine timing when trigger is first pressed
    if not wasTrigger then
        local magDurationMs = math.floor((MAG_SIZE / FIRE_RPM) * 60000)
        if magDurationMs < 1 then magDurationMs = 1 end
        magEndAt = t + magDurationMs
        wasTrigger = true
    end

    -- magazine empty -> start reload, output off
    if t >= magEndAt then
        -- Use random reload time variation
        reloadUntil = t + math.floor(getRandomReloadTime(RELOAD_TIME) * 1000)
        redstone.setAnalogOutput(FIRE_SIDE, 0)
        wasTrigger = false
        magEndAt = 0
        return
    end

    -- FIRE: hold analog output; gun handles actual ROF based on strength
    redstone.setAnalogOutput(FIRE_SIDE, redstoneSignal)
end

local gunInfo = {}
local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == AntiAirChannel then
                recievedInfo = message
            elseif channel == gunCommunicaitonChannel then
                gunInfo = message
            end
        else
            sleep()
        end
    end
end

parallel.waitForAny(
    function()
        while true do
            print(textutils.serialize(recievedInfo))
            if recievedInfo and recievedInfo.pausing then
                sleep()
                yawMotor.setTargetSpeed(0)
                pitchMotor.setTargetSpeed(0)
            elseif recievedInfo and recievedInfo.target and recievedInfo.target.x and not recievedInfo.pausing and gunInfo and gunInfo.pos then
                print("aiming")
                local computerPos = gunInfo.pos

                requiredRelativeYaw, requiredRelativePitch, absYaw, absPitch = aimCannonDirect(recievedInfo.target, computerPos)

                moveBearingCannon(absYaw, absPitch, recievedInfo.isFiring, recievedInfo.convergenceDist, gunInfo)

                fireCannons(recievedInfo.isFiring)
            else
                -- print("No targetInfo")
            end
            sleep()
        end
    end,
    modemMessage
)