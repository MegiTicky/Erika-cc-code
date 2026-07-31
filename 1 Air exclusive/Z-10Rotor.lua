local blade1 = peripheral.wrap("front")
local blade2 = peripheral.wrap("left")
local blade3 = peripheral.wrap("back")
local blade4 = peripheral.wrap("right")
local modem = peripheral.find("modem")

blade1.assemble()
blade2.assemble()
blade3.assemble()
blade4.assemble()

print("Input the controlChannel, default = 1100")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 1100
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel) -- Open a channel to communicate
AuxControlChannel = controlChannel + 1
flightInfoChannel = controlChannel + 2
modem.open(AuxControlChannel)
modem.open(flightInfoChannel)

local controls = {}
local AuxControls = {}
local desiredYVel,desiredPitch
local currentRotorSpeed = 0
local currentTailRotorSpeed = 0
local newRotorSpeed = 0
local speed = 0

local Kp_rotor, Ki_rotor, Kd_rotor = 0.08, 0, 0.05
local Kp_yaw, Ki_yaw, Kd_yaw = 0.2, 0, 0.05 -- Yaw PID values
local yVelError = 0
local yVelIntegral = 0
local yVelPrevError = 0
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0
local prevYaw = 0  -- To store the previous yaw value
local currentYaw = 0
local Kp_pitch, Ki_pitch, Kd_pitch = 0.2, 0, 0 -- Pitch PID values
local pitchError = 0
local pitchIntegral = 0
local pitchPrevError = 0
local currentPitch = 0
local lastTime = os.clock()
local dt = 0.1 -- inistial time step

local flightInfo

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

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == cannonHitPosChannel then
                cannonHitPos = message
            elseif channel == controlChannel then
                controls = message
            elseif channel == flightInfoChannel then
                flightInfo = message
            end
        else
            sleep()
        end
    end
end

local bladeCol = 0
local bladeColAdjustment = 0
-- Y Velocity stabilization using blade collective angle (bladeCol)
local function yVelStabilize(desiredYVel)
    local currentVel = flightInfo.velocity

    -- Calculate the error between desired and current Y velocity
    local yVelError = desiredYVel - currentVel.y

    -- Use PID controller to calculate bladeCol (collective pitch) adjustment
    bladeColAdjustment, yVelIntegral, yVelPrevError = PIDController(
        Kp_rotor, Ki_rotor, Kd_rotor,
        yVelError, yVelIntegral,
        (yVelError - yVelPrevError), yVelPrevError,
        dt
    )
    bladeCol = bladeCol + bladeColAdjustment
    bladeCol = math.max(-5, math.min(20, bladeCol))

    -- Clamp bladeCol between -10 (negative lift) and 30 (max positive lift)
    --local bladeCol = math.max(-10, math.min(30, bladeColAdjustment))
    --return bladeCol
end

local function pitchStabilizer(desiredPitch)
    -- Get the current pitch from the helicopter
    currentPitch = math.deg(flightInfo.pitch)

    -- Calculate the error between the desired pitch and the current pitch
    pitchError = desiredPitch - currentPitch

    pitchAdjustment, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, pitchError, pitchIntegral, (pitchError - pitchPrevError), pitchPrevError, dt)
    pitchAdjustment = pitchAdjustment
    -- Adjust the rotor speed or control surfaces based on the PID output
    return pitchAdjustment
end


local Kp_roll, Ki_roll, Kd_roll = 0.2, 0, 0
local rollError = 0
local rollIntegral = 0
local rollPrevError = 0
local function rollStabilizer(desiredRoll)
    -- Get the current pitch from the helicopter
    currentRoll = math.deg(flightInfo.roll)

    -- Calculate the error between the desired pitch and the current pitch
    rollError = desiredRoll - currentRoll

    rollAdjustment, rollIntegral, rollPrevError = PIDController(Kp_roll, Ki_roll, Kd_roll, rollError, rollIntegral, (rollError - rollPrevError), rollPrevError, dt)
    -- Adjust the rotor speed or control surfaces based on the PID output
    return rollAdjustment
end

-- Normalize angle to 0–360 degrees
local function normalizeAngleRad(rad)
    local deg = math.deg(rad) % 360
    if deg < 0 then deg = deg + 360 end
    return deg
end

local function getBladeQuadrant(bladeYawDeg, shipYawDeg)
    local relativeYaw = (bladeYawDeg - shipYawDeg + 360) % 360
    if relativeYaw >= 0 and relativeYaw < 90 then
        return 1 -- Front
    elseif relativeYaw >= 90 and relativeYaw < 180 then
        return 2 -- Right
    elseif relativeYaw >= 180 and relativeYaw < 270 then
        return 3 -- Back
    elseif relativeYaw >= 270 and relativeYaw < 360 then
        return 4 -- Left
    end
end

local shipYaw = 0
--[[ Inside main loop, after computing bladeCol and pitchAdjustment
local function applyBladeControl(blade, bladeYaw, baseCol, pitchAdj, rollAdj, bladeName)
    local bladeYawDeg = normalizeAngleRad(bladeYaw)
    if bladeName == "1" then
        bladeYawDeg = bladeYawDeg
    elseif bladeName == "2" then
        bladeYawDeg = bladeYawDeg + 90
    elseif bladeName == "3" then
        bladeYawDeg = bladeYawDeg + 180
    elseif bladeName == "4" then
        bladeYawDeg = bladeYawDeg + 270
    end
    bladeYawDeg = bladeYawDeg % 360
    local quadrant = getBladeQuadrant(bladeYawDeg, shipYaw)

    print(string.format("Blade %s Yaw: %.1f | ShipYaw: %.1f | Quadrant: %d", bladeName, bladeYawDeg, shipYaw, quadrant))

    local finalCol = baseCol
    if quadrant == 2 then
        finalCol = baseCol - pitchAdj
    elseif quadrant == 4 then
        finalCol = baseCol + pitchAdj
    end
    if quadrant == 1 then
        finalCol = finalCol - rollAdj
    elseif quadrant == 3 then
        finalCol = finalCol + rollAdj
    end
    -- 1 3: roll
    --print("finalCol: "..finalCol)
    if bladeName == "1" or bladeName == "4" then 
        flapAdjustedCol = -finalCol
    else
        flapAdjustedCol = finalCol
    end
    --print("flapAdjustedCol: "..flapAdjustedCol)
    blade.setAngle(flapAdjustedCol)
end]]

--------------------------------------------------------------------
-- 1. 预先给每片桨叶一个 0-360° 的固定相位（以机头方向 = 0° 为基准）
--------------------------------------------------------------------
local bladePhaseDeg = {   -- bladeName → 角度
  ["1"] = 0,     -- front
  ["2"] = 90,   -- left
  ["3"] = 180,   -- back
  ["4"] = 270     -- right
}

--------------------------------------------------------------------
-- 2.   连续循环控制函数
--------------------------------------------------------------------
local function applyBladeControl(blade, bladeYawRad, baseCol, pitchAdj, rollAdj, bladeName)
    ------------------------------------------------------------
    -- (a) 计算该桨叶的绝对方位角（世界坐标，°）
    ------------------------------------------------------------
    local shipYawDeg = math.deg(flightInfo.yaw)
    local bladeYawDeg = (math.deg(bladeYawRad) + bladePhaseDeg[bladeName]) % 360

    ------------------------------------------------------------
    -- (b) 相对相位   rel = bladeYaw – shipYaw   （-180°～+180°）
    ------------------------------------------------------------
    local relDeg = ((bladeYawDeg - shipYawDeg - 60) % 360) - 180
    local relRad = math.rad(relDeg)

    ------------------------------------------------------------
    -- (c) 计算连续攻角
    ------------------------------------------------------------
    local finalCol =
        baseCol
        + pitchAdj * math.sin(relRad)   -- 纵向 (sin)
        + rollAdj  * math.cos(relRad)   -- 横向 (cos)

    -- 安全限幅
    --finalCol = math.max(-10, math.min(30, finalCol))

    if bladeName == "4" or bladeName == "1" then 
        flapAdjustedCol = -finalCol
    else
        flapAdjustedCol = finalCol
    end

     blade.setAngle(flapAdjustedCol)
end

local function main()
    while true do
        if flightInfo and flightInfo.velocity then --and controls.engine == "on"
            local now = os.clock()
            dt = now - lastTime
            lastTime = now

            if controls.rotorUp then
                bladeCol = 15
            elseif controls.rotorDown then
                yVelStabilize(-10)
            else
                yVelStabilize(0)
            end
            

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

            AuxControls.tailSpeed = math.max(-256, math.min(256, AuxControls.tailSpeed))

            local velocity = ship.getVelocity()
            local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
            if controls.pitchUp then
                desiredPitch = -30
            elseif controls.pitchDown then
                desiredPitch = 30
            else
                desiredPitch = 0
            end

            if controls.rollLeft then
                desiredRoll = 20
            elseif controls.rollRight then
                desiredRoll = -20
            else
                desiredRoll = 0
            end

            --local pitchAdjustment = pitchStabilizer(desiredPitch)

            if controls.pitchUp then
                pitchAdjustment = -20
            elseif controls.pitchDown then
                pitchAdjustment = 20
            else
                pitchAdjustment = 0
            end
            if controls.rollLeft then
                rollAdjustment = 15
            elseif controls.rollRight then
                rollAdjustment = -15
            else
                rollAdjustment = rollStabilizer(desiredRoll)
            end


            if controls.rotorDown then 
                pitchAdjustment = -pitchAdjustment
                rollAdjustment = -rollAdjustment
            end
            
            shipYaw = normalizeAngleRad(flightInfo.yaw)

            applyBladeControl(blade1, getYaw(), bladeCol, pitchAdjustment, rollAdjustment, "1")
            applyBladeControl(blade2, getYaw(), bladeCol, pitchAdjustment, rollAdjustment, "2")
            applyBladeControl(blade3, getYaw(), bladeCol, pitchAdjustment, rollAdjustment, "3")
            applyBladeControl(blade4, getYaw(), bladeCol, pitchAdjustment, rollAdjustment, "4")
        end
        sleep()
    end
end

parallel.waitForAny(
    main,
    modemMessage
)