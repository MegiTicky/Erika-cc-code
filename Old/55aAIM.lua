local modem = peripheral.wrap("right")
local speaker = peripheral.find("speaker")
local pitchMotor = peripheral.wrap("back")
local yawMotor = peripheral.wrap("front")

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

local Kp_yaw = 1
local Ki_yaw = 0.1
local Kd_yaw = -0.06
local Kp_pitch = 0.8
local Ki_pitch = 0.1
local Kd_pitch = -0.06
local dt = 0.1

print("Input the controlChannel number, default: 500")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 500
end
controlChannel = tonumber(controlChannel)

print("Input the cannon channel number, default: 1900")
local cannonChannel = io.read()
if cannonChannel == "" then
    cannonChannel = 1900
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

print("Enter the yaw adjustment, default: 180(for 55a), 90 for HX3")
local yawAdjustment = io.read()
if yawAdjustment == "" then
    yawAdjustment = 180
end
local yawAdjustment = tonumber(yawAdjustment)

print("Do you want to use pitch, default: yes(for 55a), no for HX3")
local usePitch = io.read()
if usePitch == "no" then
    usePitch = false
else 
    usePitch = true
end

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
local function yawControl(deltaYaw, currentYaw)
    if math.abs(deltaYaw) then  -- Only adjust if yaw error is significant
        -- PID controller for yaw
        local yawSpeed, yawIntegral, yawPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, deltaYaw, yawIntegral, yawPrevError, dt)

        -- Constrain the yaw speed to prevent runaway spinning
        yawSpeed = math.max(-128, math.min(128, yawSpeed))

        print("deltaYaw: " .. deltaYaw)
        print("yawSpeed: " .. yawSpeed)
        print("currentYaw: "..currentYaw)

        -- Set motor speed based on PID output
        yawMotor.setTargetSpeed(-yawSpeed)
    else
        yawMotor.setTargetSpeed(0)  -- Stop motor if error is too small
    end
end

local function pitchControl(deltaPitch, currentYaw)
    if math.abs(deltaPitch) then  -- Only adjust if yaw error is significant
        -- PID controller for yaw
        local pitchSpeed, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, deltaPitch, pitchIntegral, pitchPrevError, dt)

        -- Constrain the yaw speed to prevent runaway spinning
        pitchSpeed = math.max(-128, math.min(128, pitchSpeed))

        print("deltaPitch: " .. deltaPitch)
        print("pitchSpeed: " .. pitchSpeed)

        -- Set motor speed based on PID output
        pitchMotor.setTargetSpeed(pitchSpeed) 
    else
        pitchMotor.setTargetSpeed(0)  -- Stop motor if error is too small
    end
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

        local estimateTime = 0.8  -- for combating PID latency
        local estimateX = targetPos.x + targetVel.x * estimateTime
        local estimateY = targetPos.y + targetVel.y * estimateTime
        local estimateZ = targetPos.z + targetVel.z * estimateTime

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        local currentYaw = math.deg(getYaw())+yawAdjustment
        if usePitch then
            currentPitch = math.deg(-getPitch())
        else
            currentPitch = math.deg(getRoll())
        end

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
            local sourceY = source.y
            local sourceZ = source.z

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
