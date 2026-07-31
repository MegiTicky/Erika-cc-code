local modem = peripheral.wrap("right")
local speaker = peripheral.find("speaker")
local pitchMotor = peripheral.wrap("front")
local yawMotor = peripheral.wrap("back")
local cannon = peripheral.find("createbigcannons:cannon_mount")

pitchMotor.setTargetSpeed(0)
yawMotor.setTargetSpeed(0)

local cannons = {}
local targetInfo = {}
local controlMode = "auto"
local turnSpeed = 60  -- degrees per second (16 RPM)
local directTurnThreshold = 16

local k = 1
local nilCount = 0
local i = 0
local yawErrorSum = 0
local lastYawError = 0
local pitchErrorSum = 0
local lastPitchError = 0
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0
local pitchError = 0
local pitchIntegral = 0
local pitchPrevError = 0
local lastTime = os.clock()

local Kp_yaw = 3
local Ki_yaw = 0
local Kd_yaw = 0.05
local Kp_pitch = 4
local Ki_pitch = 0.2
local Kd_pitch = 0.05
local dt = 0.1

print("Input the controlChannel number, default: 500")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 500
end
controlChannel = tonumber(controlChannel)

print("Input the cannon channel number, default: 902")
local cannonChannel = io.read()
if cannonChannel == "" then
    cannonChannel = 902
end
cannonChannel = tonumber(cannonChannel)

print("Enable pitch yaw limiter, yes/no, default: yes")
local limitor = io.read()
if limitor == "no" then
    limitor = false
else
    limitor = true
end
local pitchUpperLimit = -6

print("Enter the yaw adjustment, default: 0 for NJ")
local yawAdjustment = io.read()
if yawAdjustment == "" then
    yawAdjustment = 0
end
local yawAdjustment = tonumber(yawAdjustment)

print("Do you want to use pitch, default: yes(for NJ)")
local usePitch = io.read()
if usePitch == "no" then
    usePitch = false
else 
    usePitch = true
end

print("Input the muzzle velocity number, default: 840")
local projectileSpeed = io.read()
if projectileSpeed == "" then
    projectileSpeed = 840
end
projectileSpeed = tonumber(projectileSpeed)

print("Input the gravity acceleration per tick, default: 0.05")
local g = io.read()
if g == "" then
    g = 0.05
end
g = tonumber(g)

print("Input the drag per tick, default: 0.995")
local cd = io.read()
if cd == "" then
    cd = 0.995
end
cd = tonumber(cd)

print("input the height correction, default: 6")
local heightCorrection = io.read()
if heightCorrection == "" then
    heightCorrection = 6
end
heightCorrection = tonumber(heightCorrection)


if modem then
    modem.open(cannonChannel)
    modem.open(controlChannel)
end

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

local function PIDController(Kp, Ki, Kd, error, integral, prevError, dt)
    -- Calculate the proportional, integral, and derivative components
    local proportional = Kp * error
    integral = integral + error * dt  -- Accumulate the error for the integral term
    local derivative = (error - prevError) / dt
    
    -- Calculate the PID output
    local output = proportional + (Ki * integral) + (Kd * derivative)

    -- Return the PID output, updated integral, and current error
    return output, integral, error
end

-- Yaw control function using PID
local lastYawTime = os.clock()
-- Yaw control function using PID
local function yawControl(deltaYaw, currentYaw)
    local now = os.clock()
    local dtThisFrame = now - lastYawTime
    lastYawTime = now
    if dtThisFrame <= 0 then
        dtThisFrame = 0.05
    end
    -- PID controller for yaw
    print(dtThisFrame)
    local yawSpeed, newIntegral, newPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, deltaYaw, yawIntegral, yawPrevError, dtThisFrame)

    -- 2) Update global PID state
    yawIntegral = newIntegral
    yawPrevError = newPrevError

    -- Constrain the yaw speed to prevent runaway spinning
    yawSpeed = math.max(-10, math.min(10, yawSpeed))

    yawSpeed = yawSpeed

    print("deltaYaw: " .. deltaYaw)
    print("yawSpeed: " .. yawSpeed)

    -- Set motor speed based on PID output
    yawMotor.setTargetSpeed(-yawSpeed)
end

local lastPitchTime = os.clock()
local function pitchControl(deltaPitch, currentPitch)
    local now = os.clock()
    local dtThisFrame = now - lastPitchTime
    lastPitchTime = now
    if dtThisFrame <= 0 then
        dtThisFrame = 0.05
    end
    -- PID controller for yaw
    local pitchSpeed, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, deltaPitch, pitchIntegral, pitchPrevError, dtThisFrame)

    -- Constrain the yaw speed to prevent runaway spinning
    pitchSpeed = math.max(-128, math.min(128, pitchSpeed))

    print("deltaPitch: " .. deltaPitch)
    print("pitchSpeed: " .. pitchSpeed)

    -- Set motor speed based on PID output
    pitchMotor.setTargetSpeed(-pitchSpeed)
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
    for pitch = 0, 70, 0.01 do -- Iterate over pitch angles
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
    return bestLowPitch or bestLowPitch
end

local function aimCannon(targetPos, targetVel, sourceX, sourceY, sourceZ)
    if sourceX and sourceY and sourceZ then
        local currentTime = os.clock()
        local dt = currentTime - lastTime
        if dt == 0 then return end  -- Prevent division by zero
        lastTime = currentTime

        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local estimateX = targetPos.x + targetVel.x * (distance / projectileSpeed)
        local estimateY = targetPos.y + targetVel.y * (distance / projectileSpeed)
        local estimateZ = targetPos.z + targetVel.z * (distance / projectileSpeed)

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))
        balisticPitch = findBestPitch(estimateX, estimateY, estimateZ, sourceX, sourceY, sourceZ, projectileSpeed, g, cd, 0.0028, projectileSpeed)
        print("pitch: "..pitch)
        print("balisticPitch: "..balisticPitch)
        if balisticPitch > 30 then
            pitch = balisticPitch
        else
            pitch = pitch + balisticPitch
        end

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        local currentYaw = math.deg(getYaw()) + yawAdjustment
            
        local shipPitch = math.deg(getPitch())
        local shipRoll = math.deg(getRoll())
        cannonPitch = cannon.getPitch()
        --print("cannonPitch: "..cannonPitch)
        --print(" shipPitch: "..shipPitch)
        --print("shipRoll: "..shipRoll)
        local currentPitch = cannonPitch * math.sin(math.rad(90-shipRoll)) + shipPitch
        local yawAdjust = cannonPitch * math.cos(math.rad(90 - shipRoll))
        --print("yawAd: "..yawAdjust)
        if shipRoll < 0 then
            currentYaw = currentYaw + math.abs(yawAdjust)
        else
            currentYaw = currentYaw - math.abs(yawAdjust)
        end
        if yaw > 360 then yaw = yaw - 360 end
        if yaw < 0 then yaw = yaw + 360 end

        -- Adjust pitch based on distance adjustments
        local deltaYaw = (yaw - currentYaw + 180) % 360 - 180
        local deltaPitch = pitch - currentPitch


        -- Turning and pitch adjustment logic
        parallel.waitForAll(
            function() yawControl(deltaYaw, currentYaw) end,
            function() pitchControl(deltaPitch, currentPitch) end
        )

        lastCurrentYaw = currentYaw
        lastCurrentPitch = currentPitch
    end
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == cannonChannel then
                targetInfo = message
            elseif channel == controlChannel then
                controls = message
            end
        else
            sleep()
        end
    end
end

local function main()
    while true do
        if not(hideCannon) then
            local source = ship.getWorldspacePosition()
            local sourceX = source.x
            local sourceY = source.y + heightCorrection
            local sourceZ = source.z
            print(textutils.serialize(targetInfo))

            if targetInfo and targetInfo.targetPos and targetInfo.targetVel and controlMode == "auto" then
                aimCannon(targetInfo.targetPos, targetInfo.targetVel, sourceX, sourceY, sourceZ)
            end
        end
        sleep()
    end
end

local function modeSwitch()
    while true do
        if redstone.getInput("back") then
            if controlMode == "auto" then
                controlMode = "manual"
                redstone.setOutput("top",false)
                redstone.setOutput("bottom",false)
                redstone.setOutput("left",false)
                redstone.setOutput("right",false)
            else
                controlMode = "auto"
            end
        end
        sleep()
    end
end

parallel.waitForAny(
    modemMessage,
    main,
    modeSwitch
)
