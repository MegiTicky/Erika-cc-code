local modem = peripheral.wrap("right")
local tailRotor = peripheral.find("Create_RotationSpeedController")
local redrouter = peripheral.find("redrouter")
local controls = { rotorRPM = 5}

print("Input the controlChannel, default = 1100")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 1100
end
controlChannel = tonumber(controlChannel)
flightInfoChannel = controlChannel + 2
modem.open(controlChannel) -- Open a channel to communicate
modem.open(flightInfoChannel)


redstone.setOutput("top",false)
tailRotor.setTargetSpeed(0)

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

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == cannonHitPosChannel then
                cannonHitPos = message
            elseif channel == controlChannel then
                controls = message
            end
        else
            sleep()
        end
    end
end

local function informationSending()
    local currentVel = ship.getVelocity()
    local currentPitch = getPitch()
    local currentYaw = math.deg(getYaw())
    currentYaw = math.rad((currentYaw + 180) % 360)
    local currentRoll = getRoll()
    local currentPosition = ship.getWorldspacePosition()
    flightInfo = {velocity = currentVel, pos = currentPosition, pitch = currentPitch, yaw = currentYaw, roll = currentRoll}
    modem.transmit(flightInfoChannel,flightInfoChannel,flightInfo)
end

local function mainRotorControl()
    if controls and controls.rotorRPM then
        if controls.engine == "on" then
            redstone.setAnalogOutput("top",controls.rotorRPM)
            --print("setting rpm to "..cointrols.rotorRPM)
        elseif controls.engine == "off" then
            redstone.setAnalogOutput("top",0)
        end
    end
end

local function tailRotorControl()
    if controls then
        if controls.yawLeft then
            tailRotor.setTargetSpeed(86)
        elseif controls.yawRight then
            tailRotor.setTargetSpeed(-86)
        else
            --if manualControl then
                tailRotor.setTargetSpeed(0)
            --end
        end
    end
end

local function rocketControl()
    while true do
        local vel = ship.getVelocity()
        local speed = math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)

        if controls and controls.weaponChoosen == "rocket" then
            if controls.fire and speed <= 15 then
                redrouter.setOutput("top", true)
            else
                redrouter.setOutput("top", false)
            end
        else
            redrouter.setOutput("top", false)
        end

        sleep()
    end
end


local lastTime = os.clock()
local dt = 0.1 -- inistial time step

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

local Kp_yaw, Ki_yaw, Kd_yaw = 0.8, 0, 0.15
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0
local yawControlCooldown = 0 -- last time of manual input
local desiredYaw = nil

local function yawStablizer()
    while true do
        if flightInfo then
            local currentTime = os.clock()
            local currentYawDeg = math.deg(flightInfo.yaw)

            -- Set desiredYaw if not initialized
            if not desiredYaw then
                desiredYaw = currentYawDeg
            end

            -- Detect manual control and reset cooldown
            if controls.yawLeft or controls.yawRight or controls.rollLeft or controls.rollRight then
                yawControlCooldown = currentTime
                desiredYaw = currentYawDeg
                manualControl = true
            elseif (currentTime - yawControlCooldown) > 3 then
                -- If no manual input for over 1 second, engage PID yaw stabilization
                manualControl = false
                yawError = desiredYaw - currentYawDeg
                yawAdjustment, yawIntegral, yawPrevError = PIDController(
                    Kp_yaw, Ki_yaw, Kd_yaw,
                    yawError, yawIntegral,
                    (yawError - yawPrevError), yawPrevError, dt
                )
                tailRotor.setTargetSpeed(-yawAdjustment)
            end
        end
        sleep()
    end
end


local function main()
    while true do
        local now = os.clock()
        dt = now - lastTime
        lastTime = now
        if dt <= 0 then dt = 0.001 end

        informationSending()
        mainRotorControl()
        tailRotorControl()
        sleep()
    end
end

parallel.waitForAny(
    main,
    modemMessage,
    rocketControl
)