local frontRotor = peripheral.wrap("front")
local leftRotor = peripheral.wrap("left")
local rightRotor = peripheral.wrap("right")
local backRotor = peripheral.wrap("back")
local modem = peripheral.wrap("top")

local controls = {}
local AuxControls = {}
local desiredYVel,desiredPitch
local currentRotorSpeed = 0
local currentTailRotorSpeed = 0
local newRotorSpeed = 0
local speed = 0
local standardRotorSpeed = 2

local Kp_rotor, Ki_rotor, Kd_rotor = 1, 0, 0.4
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

frontRotor.setTargetSpeed(0)
leftRotor.setTargetSpeed(0)
rightRotor.setTargetSpeed(0)
backRotor.setTargetSpeed(0)

print("Input the controlChannel, default = 1100")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 1100
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel) -- Open a channel to communicate
AuxControlChannel = controlChannel + 1
modem.open(AuxControlChannel)


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

local function yVelStabilize(desiredYVel)
    local currentVel = ship.getVelocity() -- Get current velocity of the helicopter

    -- Calculate the error between desired and current Y velocity
    local yVelError = desiredYVel - currentVel.y

    -- Use PID controller to calculate rotor speed adjustment
    local rotorAdjustment, yVelIntegral, yVelPrevError = PIDController(Kp_rotor, Ki_rotor, Kd_rotor, yVelError, yVelIntegral, (yVelError - yVelPrevError), yVelPrevError, dt)

    -- Get the current rotor speed and adjust it based on PID output
    local getRotorSpeed = frontRotor.getTargetSpeed()
    if getRotorSpeed then
        currentRotorSpeed = getRotorSpeed
    end
    
    rotorAdjustment = math.min(10,math.abs(rotorAdjustment))

    -- Adjust rotor speed based on whether we're going too fast upward or downward
    if currentVel.y - desiredYVel > 0.2 then
        -- If we're going up too fast, reduce rotor speed
        newRotorSpeed = standardRotorSpeed - math.abs(rotorAdjustment) -- Reduce speed
        if newRotorSpeed < 0 then
            newRotorSpeed = 0
        end
    elseif currentVel.y - desiredYVel < -0.2 then
        -- If we're going down too fast, increase rotor speed
        newRotorSpeed = standardRotorSpeed + math.abs(rotorAdjustment) -- Increase speed
    else
        -- If close to desired Y velocity, maintain the speed or apply minor adjustments
        newRotorSpeed = standardRotorSpeed
    end

    -- Set the new rotor speed to stabilize Y velocity
    frontRotorSpeed = newRotorSpeed
    leftRotorSpeed = newRotorSpeed
    rightRotorSpeed = newRotorSpeed
    backRotorSpeed = newRotorSpeed


    -- Sleep for dt (time step)
    sleep(dt)
    return(newRotorSpeed)
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

local function main()
    while true do
        if autoPilot then
            
        else
            print(textutils.serialize(controls))
            local desiredYVel = 0
            if controls.rotorUp then
                desiredYVel = 20
                print("rotorUp")
            elseif controls.rotorDown then
                desiredYVel = -20
            end
            local newRotorSpeed = yVelStabilize(desiredYVel)
            leftRotorSpeed,backRotorSpeed,rightRotorSpeed,frontRotorSpeed = newRotorSpeed,newRotorSpeed,newRotorSpeed,newRotorSpeed

            if controls.yawLeft then
                rightRotorSpeed = leftRotorSpeed * 0.5
            elseif controls.yawRight then
                frontRotorSpeed = frontRotorSpeed * 0.5
            end

            local velocity = ship.getVelocity()
            local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
            if controls.pitchUp then
                --go backward
                leftRotorSpeed, backRotorSpeed = leftRotorSpeed * 0.5, backRotorSpeed * 0.5
            elseif controls.pitchDown then
                --go forward
                frontRotorSpeed, rightRotorSpeed = frontRotorSpeed * 0.5, rightRotorSpeed * 0.5
            else
                desiredPitch = 0
                AuxControls.throttle = 0
            end

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

            frontRotor.setTargetSpeed(frontRotorSpeed)
            leftRotor.setTargetSpeed(-leftRotorSpeed)
            rightRotor.setTargetSpeed(rightRotorSpeed)
            backRotor.setTargetSpeed(-backRotorSpeed)
        end
        sleep()
    end
end

parallel.waitForAny(
    main,
    modemMessage
)