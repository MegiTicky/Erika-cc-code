local backRouter = peripheral.wrap("back")
local frontRouter = peripheral.wrap("front")
local topRouter = peripheral.find("redrouter")
local monitor = peripheral.find("monitor")
local modem = peripheral.wrap("right")

topRouter.setOutput("top",true)
local isVTOLMode = false
local Kp_pitch, Ki_pitch, Kd_pitch = 0.0055, 0, 0.0085  -- Pitch PID values
local pitchError = 0
local pitchIntegral = 0
local pitchPrevError = 0
local currentPitch = 0
local Kp_roll, Ki_roll, Kd_roll = 0.1, 0.2, 0.02 -- roll PID values
local rollError = 0
local rollIntegral = 0
local rollPrevError = 0
local currentRoll = 0
local dt = 0.1

local rearThrust,leftThrust,rightThrust =0,0,0

local controls = {}
local weaponChoosen = "AIM-220"

backRouter.setOutput("front", false)
backRouter.setOutput("back", false)
backRouter.setOutput("left", false)
backRouter.setOutput("right", false)
backRouter.setOutput("top", false)
backRouter.setOutput("bottom", false)

frontRouter.setOutput("front", false)
frontRouter.setOutput("back", false)
frontRouter.setOutput("left", false)
frontRouter.setOutput("right", false)
frontRouter.setOutput("top", false)
frontRouter.setOutput("bottom", false)

topRouter.setOutput("front", false)
topRouter.setOutput("back", false)
topRouter.setOutput("left", false)
topRouter.setOutput("right", false)
topRouter.setOutput("top", false)
topRouter.setOutput("bottom", false)

print("Input the controlChannel, default = 1420")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 1420
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel) -- Open a channel to communicate

print("Input the pitchCompensation, default = 48.24")
local pitchCompensation = io.read()
if pitchCompensation == "" then
    pitchCompensation = 48.24
end
pitchCompensation = tonumber(pitchCompensation)

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
    return math.atan2(-normalizedMatrix[3][1], -normalizedMatrix[3][3]) + math.pi -- Extract yaw from the matrix
end

-- Get the roll of the ship
local function getRoll()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return math.atan2(normalizedMatrix[2][1], normalizedMatrix[2][2]) -- Extract roll from the matrix
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

-- Function to handle user click on the button
local function handleClick()
    -- Get touch event from the monitor
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")

        print("x: "..x.." y: "..y)
    end
end

-- **Function to control pitch in VTOL mode**
local function VTOLPitchControl(desiredPitch,baseThrust)
    local currentPitch = math.deg(getPitch()) + pitchCompensation -- Get the current pitch
    local pitchError = desiredPitch - currentPitch
    local pitchOutput, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchError, pitchIntegral, (pitchError - pitchPrevError), pitchPrevError, dt)
    
    local compensationFactor = (15 - baseThrust) * 0.4
    local adjustedFrontThrust = (baseThrust + pitchOutput) * 1.3 + compensationFactor
    local rearThrust = math.min(math.max(baseThrust - pitchOutput, 0), 15)
    local frontThrust = math.min(math.max(adjustedFrontThrust, 0), 15)
    print("currentPitch: "..currentPitch)
    return frontThrust,rearThrust
end

-- **Function to control roll in VTOL mode**
local function VTOLRollControl(desiredRoll, baseThrust)
    local currentRoll = math.deg(getRoll()) -- Get the current roll
    local rollError = desiredRoll - currentRoll
    local rollOutput, rollIntegral, rollPrevError = PIDController(Kp_roll, Ki_roll, Kd_roll, rollError, rollIntegral, (rollError - rollPrevError), rollPrevError, dt)

    -- Calculate thrust values
    local leftThrust = baseThrust + rollOutput
    local rightThrust = baseThrust - rollOutput

    -- Clamp the thrust values between 0 and 15
    leftThrust = math.max(0, math.min(15, leftThrust))
    rightThrust = math.max(0, math.min(15, rightThrust))

    return leftThrust, rightThrust
end

local function VTOLMode()
    while true do
        if controls and controls.hoverMode then
            local baseThrust = controls.throttle

            if controls.pitchDown then
                frontThrust,rearThrust = VTOLPitchControl(-15,baseThrust)
            elseif controls.pitchUp then
                frontThrust,rearThrust = VTOLPitchControl(15,baseThrust)
            else
                frontThrust,rearThrust = VTOLPitchControl(0,baseThrust)
            end
            if controls.rollLeft then
                leftThrust, rightThrust = VTOLRollControl(-15,baseThrust)
            elseif controls.rollRight then
                leftThrust, rightThrust = VTOLRollControl(15,baseThrust)
            else
                leftThrust, rightThrust = VTOLRollControl(0,baseThrust)
            end

            print("frontThrust: "..frontThrust.." rearThrust: "..rearThrust.." leftThrust: "..leftThrust.." rightThrust: "..rightThrust)

            frontRouter.setAnalogOutput("right",rightThrust)
            frontRouter.setAnalogOutput("top",leftThrust)
            frontRouter.setAnalogOutput("front",rearThrust)
            frontRouter.setAnalogOutput("left",frontThrust)
        else
            frontRouter.setAnalogOutput("right",0)
            frontRouter.setAnalogOutput("top",0)
            frontRouter.setAnalogOutput("front",0)
            frontRouter.setAnalogOutput("left",0)
            frontRouter.setOutput("bottom",false)
        end
        sleep()
    end
end

local function handleThrust()
    while true do
        if controls and not controls.hoverMode and controls.throttle then
            topRouter.setAnalogOutput("front", controls.throttle) -- Full thrust
        else
            topRouter.setAnalogOutput("front", 0)
        end
        sleep() -- Reduce processing load
    end
end

local function handleRoll()
    while true do
        if controls and not controls.hoverMode and not controls.autoPilot then
            local rollLeft = controls.rollLeft and 15 or 0
            local rollRight = controls.rollRight and 15 or 0

            topRouter.setAnalogOutput("left", rollLeft)  -- Aileron left down
            topRouter.setAnalogOutput("right", rollRight) -- Aileron right down
        else
            if not controls.autoPilot then
                topRouter.setAnalogOutput("left", 0)
                topRouter.setAnalogOutput("right", 0)
            end
        end
        sleep()
    end
end

local function handlePitch()
    while true do
        if controls and not controls.hoverMode and not controls.autoPilot then
            local pitchUp = controls.pitchUp and 15 or 0
            local pitchDown = controls.pitchDown and 15 or 0

            backRouter.setAnalogOutput("top", pitchUp)  -- Elevator up
            backRouter.setAnalogOutput("front", pitchDown) -- Elevator down
        else
            if not controls.autoPilot then
                backRouter.setAnalogOutput("top", 0)
                backRouter.setAnalogOutput("front", 0)
            end
        end
        sleep()
    end
end

local function handleYaw()
    while true do
        if controls then
            local yawLeft = controls.yawLeft and 15 or 0
            local yawRight = controls.yawRight and 15 or 0

            backRouter.setAnalogOutput("left", yawLeft)
            backRouter.setAnalogOutput("right", yawRight)
        else
            backRouter.setAnalogOutput("right", 0)
            backRouter.setAnalogOutput("right", 0)
        end
        sleep()
    end
end

-- Runs all key handlers in parallel for instant response!
local function normalMode()
    parallel.waitForAny(
        handleThrust,
        handleRoll,
        handlePitch,
        handleYaw
    )
end

local function autoPilot()
    local pitchError, pitchIntegral, pitchPrevError = 0, 0, 0
    local rollError, rollIntegral, rollPrevError = 0, 0, 0
    local altitudeError, altitudeIntegral, altitudePrevError = 0, 0, 0

    -- **PID Constants**
    local Kp_pitch, Ki_pitch, Kd_pitch = 0.25, 0.02, 0.015 -- Pitch PID values
    local Kp_roll, Ki_roll, Kd_roll = 0.05, 0.01, 0.01 -- Roll PID values
    local Kp_alt, Ki_alt, Kd_alt = 0.3, 0.02, 0.02 -- Altitude PID values (used for pitch control)

    local dt = 0.1
    local targetAltitude = nil -- Stores altitude when autopilot is enabled

    while true do
        if controls and controls.autoPilot then
            if not targetAltitude then
                targetAltitude = ship.getWorldspacePosition().y  -- Lock initial altitude
            end

            local currentAltitude = ship.getWorldspacePosition().y
            local currentPitch = math.deg(getPitch()) + pitchCompensation -- Get current pitch angle
            local currentRoll = math.deg(getRoll()) -- Get current roll angle

            -- **Altitude Control (Using Pitch)**

            altitudeError = targetAltitude - currentAltitude
            local altitudePitchCorrection, altitudeIntegral, altitudePrevError =
                PIDController(Kp_alt, Ki_alt, Kd_alt, altitudeError, altitudeIntegral,
                (altitudeError - altitudePrevError), altitudePrevError, dt)

            -- **Total Pitch Correction (Altitude + Level Flight)**
            pitchError = altitudePitchCorrection - currentPitch
            local pitchOutput, pitchIntegral, pitchPrevError = 
                PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchError, pitchIntegral, 
                (pitchError - pitchPrevError), pitchPrevError, dt)

            -- Adjust elevators to control altitude & stabilize pitch
            local pitchUp = math.max(0, math.min(15, pitchOutput))
            local pitchDown = math.max(0, math.min(15, -pitchOutput))
            backRouter.setAnalogOutput("top", pitchUp)  -- Elevator up (nose down)
            backRouter.setAnalogOutput("front", pitchDown) -- Elevator down (nose up)

            -- **Roll Control (Keep Level Wings)**
            rollError = currentRoll -- We want roll = 0
            local rollOutput, rollIntegral, rollPrevError = 
                PIDController(Kp_roll, Ki_roll, Kd_roll, rollError, rollIntegral, 
                (rollError - rollPrevError), rollPrevError, dt)

            -- Adjust ailerons to correct roll
            local rollLeft = math.max(0, math.min(15, rollOutput))
            local rollRight = math.max(0, math.min(15, -rollOutput))
            topRouter.setAnalogOutput("left", rollLeft)  -- Aileron left
            topRouter.setAnalogOutput("right", rollRight) -- Aileron right

            print("AutoPilot: Altitude Error:", altitudeError, "Pitch Correction:", altitudePitchCorrection)
            print("AutoPilot: Pitch Error:", pitchError, "Elevator Up:", pitchUp, "Elevator Down:", pitchDown)
            print("AutoPilot: Roll Error:", rollError, "Left Aileron:", rollLeft, "Right Aileron:", rollRight)

        else
            -- **Reset Values When Autopilot is Off**
            targetAltitude = nil -- Reset altitude lock
        end
        sleep(dt)
    end
end

local function miscControl()
    while true do
        if controls then
            if controls.switchToAIM220 then
                weaponChoosen = "AIM-220"
            elseif controls.switchToGBU then
                weaponChoosen = "GBU-42"
            elseif controls.switchToThunderbolt then
                weaponChoosen = "thunderBolt"
            elseif controls.switchToAIM9 then
                weaponChoosen = "AIM-9"
            elseif controls.switchToGun then
                weaponChoosen = "Gun"
            end
            if weaponChoosen == "AIM-9" and controls.fire then
                topRouter.setOutput("top",true)
            else
                topRouter.setOutput("top",false)
            end
            if weaponChoosen == "Gun" and controls.fire then
                redstone.setOutput("left",true)
            else
                redstone.setOutput("left",false)
            end
        end
        sleep()
    end
end


local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == controlChannel then
                controls = message
            end
        else
            sleep()
        end
    end
end

parallel.waitForAny(
    handleClick,
    modemMessage,
    VTOLMode,
    normalMode,
    autoPilot,
    miscControl
)
