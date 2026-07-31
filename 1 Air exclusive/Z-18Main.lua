local engine = peripheral.wrap("left")
local rotor = peripheral.find("Create_RotationSpeedController")
local tailRotor = peripheral.find("Tail_RotorController")  -- Assuming tail rotor is controlled separately
local modem = peripheral.wrap("right")

redstone.setOutput("left",false)
redstone.setOutput("front",false)
redstone.setOutput("right",false)

print("Input the controlChannel, default = 1100")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 1100
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel) -- Open a channel to communicate
AuxControlChannel = controlChannel + 1
modem.open(AuxControlChannel)

local controls = {}
local AuxControls = {}
local desiredYVel,desiredPitch
local currentRotorSpeed = 0
local currentTailRotorSpeed = 0
local newRotorSpeed = 0
local speed = 0

local Kp_rotor, Ki_rotor, Kd_rotor = 0.4, 1, 0.5
local Kp_yaw, Ki_yaw, Kd_yaw = 0.5, 0.01, 0.1 -- Yaw PID values
local yVelError = 0
local yVelIntegral = 0
local yVelPrevError = 0
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0
local prevYaw = 0  -- To store the previous yaw value
local currentYaw = 0
local Kp_pitch, Ki_pitch, Kd_pitch = 0.1, 0.2, 0.01 -- Pitch PID values
local pitchError = 0
local pitchIntegral = 0
local pitchPrevError = 0
local currentPitch = 0
local dt = 0.1 -- Time step for PID

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
    return -math.asin(normalizedMatrix[2][3]) -- Extract pitch from the matrix
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

local function pullFuel()
    while true do
        engine.pullFluid("back", 20, "createdieselgenerators:biodiesel")
        print("fuelPulled")
        sleep(1)
    end
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

-- Y Velocity stabilization using the main rotor
local function yVelStabilize(desiredYVel)
    local currentVel = ship.getVelocity() -- Get current velocity of the helicopter

    -- Calculate the error between desired and current Y velocity
    local yVelError = desiredYVel - currentVel.y

    -- Use PID controller to calculate rotor speed adjustment
    local rotorAdjustment, yVelIntegral, yVelPrevError = PIDController(Kp_rotor, Ki_rotor, Kd_rotor, yVelError, yVelIntegral, (yVelError - yVelPrevError), yVelPrevError, dt)

    -- Get the current rotor speed and adjust it based on PID output
    local getRotorSpeed = rotor.getTargetSpeed()
    if getRotorSpeed then
        currentRotorSpeed = getRotorSpeed
    end

    -- Adjust rotor speed based on whether we're going too fast upward or downward
    if currentVel.y > desiredYVel then
        -- If we're going up too fast, reduce rotor speed
        newRotorSpeed = math.abs(currentRotorSpeed) - math.abs(rotorAdjustment) -- Reduce speed
        if newRotorSpeed < 0 then
            newRotorSpeed = 0
        end
    elseif currentVel.y < desiredYVel then
        -- If we're going down too fast, increase rotor speed
        newRotorSpeed = math.abs(currentRotorSpeed) + math.abs(rotorAdjustment) -- Increase speed
    else
        -- If close to desired Y velocity, maintain the speed or apply minor adjustments
        newRotorSpeed = currentRotorSpeed
    end

    -- Set the new rotor speed to stabilize Y velocity
    rotor.setTargetSpeed(newRotorSpeed)

    -- Sleep for dt (time step)
    sleep(dt)
end

local function pitchStabilizer(desiredPitch)
    -- Get the current pitch from the helicopter
    local currentPitch = -math.deg(getPitch())

    -- Calculate the error between the desired pitch and the current pitch
    local pitchError = desiredPitch - currentPitch

    local pitchAdjustment, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchError, pitchIntegral, (pitchError - pitchPrevError), pitchPrevError, dt)
    pitchAdjustment = pitchAdjustment
    -- Adjust the rotor speed or control surfaces based on the PID output
    AuxControls.pitch = pitchAdjustment

    -- Sleep for dt (time step)
    sleep(dt)
end

local function main()
    while true do
        local desiredYVel = 0
        if controls.rotorUp then
            desiredYVel = 20
        elseif controls.rotorDown then
            desiredYVel = -20
        end
        yVelStabilize(desiredYVel)

        if math.abs(newRotorSpeed) < 128 then 
            AuxControls.tailSpeed = newRotorSpeed * 1
        else
            AuxControls.tailSpeed = newRotorSpeed * 0.085
        end

        if controls.yawLeft then
            AuxControls.tailSpeed = AuxControls.tailSpeed + 256
        elseif controls.yawRight then
            AuxControls.tailSpeed = AuxControls.tailSpeed - 256
        end

        if AuxControls.tailSpeed < -256 then AuxControls.tailSpeed = -256 end
        if AuxControls.tailSpeed > 256 then AuxControls.tailSpeed = 256 end

        local velocity = ship.getVelocity()
        local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
        if controls.pitchUp then
            desiredPitch = 30
        elseif controls.pitchDown then
            desiredPitch = -30
            if speed < 30 then
                AuxControls.throttle = 15
            else
                AuxControls.throttle = 0
            end
        else
            desiredPitch = 0
            AuxControls.throttle = 0
        end
        pitchStabilizer(desiredPitch)
        print("Throttle: "..AuxControls.throttle)

        if controls.rollLeft then
            redstone.setOutput("right",true)
            redstone.setOutput("front",false)
        elseif controls.rollRight then
            redstone.setOutput("front",true)
            redstone.setOutput("right",false)
        else
            redstone.setOutput("front",false)
            redstone.setOutput("right",false)
        end

        modem.transmit(AuxControlChannel,0,AuxControls)
    end
end

parallel.waitForAny(
    pullFuel,
    main,
    modemMessage
)