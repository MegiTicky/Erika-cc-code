local leftRouter = peripheral.wrap("left")
local rightRouter = peripheral.wrap("right")
local modem = peripheral.find("modem")

local throttle = 0
local maintainHeight = 200


local Kp_hover, Ki_hover, Kd_hover = 0.6, 1, 0.5
local yVelError = 0
local yVelIntegral = 0
local yVelPrevError = 0

print("Input the controlChannel, default = 1200")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 1200
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel)

redstone.setOutput("top", false)
redstone.setOutput("front",false)
leftRouter.setOutput("top", false)
leftRouter.setOutput("front",false)
rightRouter.setOutput("top", false)
rightRouter.setOutput("front",false)
redstone.setAnalogOutput("back",0)

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

local function manualControlPitch()
    while true do
        if controls and not (controls.hoverMode) then
            if controls.pitchUp then
                redstone.setOutput("top", true)
            elseif controls.pitchDown then
                redstone.setOutput("front", true)
            else
                redstone.setOutput("top", false)
                redstone.setOutput("front", false)
            end
        end
        sleep(0.05) -- Reduce sleep time for higher responsiveness
    end
end

local function manualControlYaw()
    while true do
        if controls and not (controls.hoverMode) then
            if controls.yawLeft then
                leftRouter.setOutput("top", true)
            elseif controls.yawRight then
                leftRouter.setOutput("front", true)
            else
                leftRouter.setOutput("top", false)
                leftRouter.setOutput("front", false)
            end
        end
        sleep(0.05) -- Reduce sleep time for higher responsiveness
    end
end

local function manualControlRoll()
    while true do
        if controls and not (controls.hoverMode) then
            if controls.rollLeft then
                rightRouter.setOutput("top", true)
            elseif controls.rollRight then
                rightRouter.setOutput("front", true)
            else
                rightRouter.setOutput("top", false)
                rightRouter.setOutput("front", false)
            end
        end
        sleep(0.05) -- Reduce sleep time for higher responsiveness
    end
end

local function manualThrottle()
    while true do
        if controls and not (controls.hoverMode) then
            if controls.throttleUp then
                throttle = throttle + 1
            elseif controls.throttleDown then
                throttle = throttle - 1
            end
            if throttle < 0 then throttle = 0 end
            if throttle > 15 then throttle = 15 end
            redstone.setAnalogOutput("back", math.floor(throttle))
        end
        sleep(0.05) -- Reduce sleep time for higher responsiveness
    end
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

local function yVelStabilize(desiredYVel)
    local currentVel = ship.getVelocity()

    local yVelError = desiredYVel - currentVel.y

    local rotorAdjustment, yVelIntegral, yVelPrevError = PIDController(Kp_rotor, Ki_rotor, Kd_rotor, yVelError, yVelIntegral, (yVelError - yVelPrevError), yVelPrevError, dt)

    local getRotorSpeed = rotor.getTargetSpeed()
    if getRotorSpeed then
        currentRotorSpeed = getRotorSpeed
    end

    if currentVel.y > desiredYVel then
        -- If we're going up too fast, reduce rotor speed
        newRotorSpeed = math.abs(currentRotorSpeed) - math.abs(rotorAdjustment) -- Reduce speed
        if newRotorSpeed < 0 then
            newRotorSpeed = 0
        end
    elseif currentVel.y < desiredYVel then
        newRotorSpeed = math.abs(currentRotorSpeed) + math.abs(rotorAdjustment) -- Increase speed
    else
        newRotorSpeed = currentRotorSpeed
    end

    rotor.setTargetSpeed(newRotorSpeed)

    sleep(dt)
end

local function hoverMode()
    if controls then
        if controls.hoverMode then
            velocity = ship.getVelocity()
            position = ship.getWorldspacePosition()
            local roll = math.deg(ship.getRoll())
            redstone.setAnalogOutput("back",3)

            if roll > -10 then
                leftRouter.setAnalogOutput("top",15)
                if velocity.y > 0 then
                    redstone.setAnalogOutput("top", 0)
                    rightRouter.setAnalogOutput("top",15)
                else
                    redstone.setAnalogOutput("top", 10)
                    redstone.setAnalogOutput("front",0)
                end
            else
                leftRouter.setOutput("top",true)
                if  position.y > maintainHeight and velocity.y > -5 then
                    redstone.setAnalogOutput("top",7)
                    heightError = position.y - maintainHeight
                    local rollPropotional = math.abs(heightError) * Kp_hover
                    redstone.setAnalogOutput("back",2)
                    if roll > -35 then
                        rightRouter.setAnalogOutput("top",math.min(math.abs(rollPropotional),15))
                        rightRouter.setAnalogOutput("front",0)
                    else
                        rightRouter.setAnalogOutput("top",0)
                        rightRouter.setAnalogOutput("front",5)
                    end
                else
                    redstone.setAnalogOutput("top",13)
                    redstone.setAnalogOutput("back",5)
                    if roll < -25 then
                        rightRouter.setAnalogOutput("top",0)
                        rightRouter.setAnalogOutput("front",2)
                    else
                        rightRouter.setAnalogOutput("front",0)
                    end
                end
            end
        end
    end
    sleep()
end

local function main()
    while true do
        if controls and controls.hoverMode then
            hoverMode()
        else
            maintainHeight = ship.getWorldspacePosition().y -- Update maintainHeight based on the ship's current position
        end
        sleep()
    end
end

-- Use parallel to run modem messages and all controls in their own threads
parallel.waitForAny(
    modemMessage,
    manualControlPitch,
    manualControlRoll,
    manualControlYaw,
    manualThrottle,
    main
)