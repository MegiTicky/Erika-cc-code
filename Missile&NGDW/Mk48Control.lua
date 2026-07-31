local radar = peripheral.find("sp_radar")
local modem = peripheral.wrap("right")
local motor = peripheral.find("electric_motor")
local helm = peripheral.find("eureka_ship_helm")
redstone.setOutput("front",false)
redstone.setOutput("left",false)
redstone.setOutput("bottom",false)
redstone.setOutput("right",false)
redstone.setOutput("back",false)
redstone.setOutput("top",false)
motor.setSpeed(0)

local controls = {}
local target = {}
local lockedId = nil
local targetPos, targetVel, TargetYaw, TargetPitch
local Kp_yaw, Ki_yaw, Kd_yaw = 0.11, 0.005, 0.0092
local Kp_pitch, Ki_pitch, Kd_pitch = 0.14, 0.065, 0.0042
local Kp_roll, Ki_roll,Kd_roll = 0.06,0,0.0033
local Kp_throttle, Ki_throttle, Kd_throttle = 0.2, 0.1, 0.02
local K_pitchDiff, k_heightDiff = 1,0
local projectedMissileY,yLevelDiff,initialDistance,targetAltitude
local closestDistance = math.huge

-- Initialize error, integral, and derivative terms for yaw and pitch
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0

local pitchError = 0
local pitchIntegral = 0
local pitchHeightPrevError = 0

local rollError,rollIntegral,rollPrevError = 0,0,0

local speedError, speedIntegral, speedPrevError = 0,0,0

local throttle = 30

local lastMotorSpeed = nil
local lastMotorUpdateTime = os.clock()

local dt = 0.1
print("Input the torpedo id, eg:1, default: 1")
local torpedoid = io.read()
if torpedoid == "" then
    torpedoid = 1
end
torpedoid = tonumber(torpedoid)

print("Input the sea level, 105 for ocean world, 18 for Taiyi. 15 for Silver Gate, 62 for overworld,default: 105")
local seaLevel = io.read()
if seaLevel == "" then
    seaLevel = 105
end
seaLevel = tonumber(seaLevel)

local controlsChannel = 1500
local throttleChannel = controlsChannel + torpedoid
print("throttleChannel: "..throttleChannel)
if modem then 
    modem.open(controlsChannel)
    modem.open(throttleChannel)
end

local function normalizeVector(v)
    local length = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
    if length == 0 then
        return {0, 0, 0}
    end
    return {v[1] / length, v[2] / length, v[3] / length}
end

-- Function to normalize the rotation matrix
local function normalizeRotationMatrix(rotMatrix)
    local normalizedMatrix = {}
    for i = 1, #rotMatrix do
        normalizedMatrix[i] = normalizeVector(rotMatrix[i])
    end
    return normalizedMatrix
end

-- Modified getPitch function to use the normalized rotation matrix
function getPitch()
    local rotMatrix = ship.getRotationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return -math.asin(normalizedMatrix[2][3])
end


local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == controlsChannel then
                controls = message
            end
        else
            sleep()
        end
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

local function calculateProjectedY(currentY, currentPitch, currentVelocity, distance)
    -- Convert pitch to radians for calculation
    local pitchRad = math.rad(currentPitch)
    -- Estimate the change in Y based on the pitch, velocity, and distance
    local projectedY = currentY + math.tan(pitchRad) * distance
    return projectedY
end

local function setMotorSpeedSafe(speed)
    local currentTime = os.clock()
    
    -- Check if 0.2 seconds have passed since the last update
    if (currentTime - lastMotorUpdateTime >= 0.3) or (speed ~= lastMotorSpeed) then
        motor.setSpeed(speed)
        lastMotorSpeed = speed
        lastMotorUpdateTime = currentTime
    end
end

parallel.waitForAny(
    function()
        while true do
            print("controls: "..textutils.serialize(controls))
            if controls and controls.fireMissile and controls.fireMissile[torpedoid] and controls.fireMissile[torpedoid].launch == true then
                target = controls.fireMissile[torpedoid]
                print("launching")
                break
            end
            sleep()
        end
    end,
    modemMessage
)
print("Scaning for target")

--lock on
local targetPos = ship.getWorldspacePosition()
sleep(0.01)
local targetVel = ship.getVelocity()
targetPos.x = targetPos.x + targetVel.x * 2
targetPos.z = targetPos.z + targetVel.y * 2

local yaw = math.deg(ship.getYaw())
local pitch = math.deg(ship.getPitch()) * (90/28.6478)

local results = radar.scanForShips(3000)
local displayData = {}
print(results)

if target.type == "ship" then
    if not results or #results == 0 then
        table.insert(displayData, "No objects detected.")
    else      
        local smallestCombinedDiff = math.huge  -- Initialize with a large value
        local finalTargetYaw = nil
        local finalTargetPitch = nil
        local finalDistance = nil
        local closestDistanceWithSmallDiff = math.huge  -- New variable for closest distance with small combined diff
        
        -- Assuming 'yaw' and 'pitch' are the current ship's yaw and pitch angles
        local pos = ship.getWorldspacePosition()
        local yaw = math.deg(ship.getYaw()) + 180
        if yaw > 360 then yaw = yaw - 360 end
        local pitch = math.deg(getPitch())

        for i, object in ipairs(results) do
            if object.mass > 1000 then
                -- Calculate dx, dy, dz from ship to object
                local dx = object.pos.x - pos.x
                local dy = object.pos.y - pos.y
                local dz = object.pos.z - pos.z

                -- Calculate bearing (yaw) from ship to object
                local angleFromSouth = math.atan2(dx, dz)
                local bearingFromSouth = math.deg(angleFromSouth)
                local targetYaw = (180 - bearingFromSouth) % 360

                -- Calculate yaw difference
                local yawDiff = (targetYaw - yaw + 180) % 360 - 180

                -- Calculate pitch difference
                local horizontalDistance = math.sqrt(dx * dx + dz * dz)
                local targetPitch = math.deg(math.atan2(dy, horizontalDistance))
                local pitchDiff = targetPitch - (-pitch)

                -- Calculate the Euclidean distance (for prioritization)
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                -- Combine yaw and pitch differences into a single score (weighted sum or simply adding)
                local combinedDiff = math.abs(yawDiff) + math.abs(pitchDiff)

                -- Additional logic: If combinedDiff is less than 20, lock onto the closest target
                if object.id == target.id then
                    closestDistanceWithSmallDiff = distance
                    lockedId = object.id
                    intialPosition = object.pos
                    initialDistance = horizontalDistance
                    print("Target with combinedDiff < 20, Distance: ", distance, " Locked target ID: ", object.id)
                end
            end
        end
        
        if lockedId and intialPosition then
            print("Closest Object ID:", lockedId)
            print("X: "..intialPosition.x.." Y: "..intialPosition.y.." Z: "..intialPosition.z)
            print("initialDistance: "..initialDistance)
        else
            print("No large objects detected.")
        end
    end
else
    local pos = ship.getWorldspacePosition()
    local dx = target.pos.x - pos.x
    local dy = target.pos.y - pos.y
    local dz = target.pos.z - pos.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    intialPosition = target.pos
    initialDistance = math.sqrt(dx * dx + dz * dz)
end

print("Locked Target:", lockedId)
print("X: "..intialPosition.x.." Y: "..intialPosition.y.." Z: "..intialPosition.z)
redstone.setOutput("top",true)
setMotorSpeedSafe(-64)
sleep(1)
setMotorSpeedSafe(0)
redstone.setOutput("top",false)

local function tracking()
    local results = radar.scanForShips(2000)
    pos = ship.getWorldspacePosition()
    local yaw = math.deg(ship.getYaw()) + 180
    if yaw>360 then yaw = yaw - 360 end
    local missileVelocity = ship.getVelocity()
    local misisleSpeed = math.sqrt(missileVelocity.x ^ 2 + missileVelocity.y ^ 2 + missileVelocity.z ^ 2)
    local pitch = math.deg(getPitch())
    print("pitch: "..pitch)
    
    if target.type == "ship" then
        for i, object in ipairs(results) do
            if object.id == lockedId then
                targetPos = object.pos
                targetVel = object.velocity
                local dx = targetPos.x - pos.x
                local dy = targetPos.y - pos.y
                local dz = targetPos.z - pos.z
                local immediateDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
                missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
                if missileSpeed < 0.1 then missileSpeed = 0.1 end

                -- Update pitch, yaw, and distance
                local estimateTime = immediateDistance/missileSpeed
                local estimateX = targetPos.x + targetVel.x * math.min(estimateTime,1)
                local estimateY = targetPos.y
                local estimateZ = targetPos.z + targetVel.z * math.min(estimateTime,1)

                local dx = estimateX - pos.x
                local dy = estimateY - pos.y
                local dz = estimateZ - pos.z

                local targetHorizontalDistance = math.sqrt(dx * dx + dz * dz)
                
                TargetYaw = math.deg(math.atan2(-dx, dz))
                TargetYaw = (TargetYaw + 180) % 360

                if targetPos.y > seaLevel - 5 then
                    targetAltitude = seaLevel - 5
                else
                    targetAltitude = targetPos.y
                end

                yLevelDiff = targetAltitude - pos.y

                yawError = TargetYaw - yaw
            end
        end
    elseif target.type == "waypoint" then
        targetPos = target.pos

        local dx = targetPos.x - pos.x
        local dy = targetPos.y - pos.y
        local dz = targetPos.z - pos.z
        local immediateDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
        missileSpeed = math.sqrt(missileVelocity.x^2 + missileVelocity.y^2 + missileVelocity.z^2)
        if missileSpeed < 0.1 then missileSpeed = 0.1 end

        local estimateTime = immediateDistance/missileSpeed

        local targetHorizontalDistance = math.sqrt(dx * dx + dz * dz)
        
        TargetYaw = math.deg(math.atan2(-dx, dz))
        TargetYaw = (TargetYaw + 180) % 360
        if targetPos.y > seaLevel - 5 then
            targetAltitude = seaLevel - 5
        else
            targetAltitude = targetPos.y
        end

        yLevelDiff = targetAltitude - pos.y

        yawError = TargetYaw - yaw
    end

    -- Ensure yaw is between -180 and 180 for error
    if yawError > 180 then
        yawError = yawError - 360
    elseif yawError < -180 then
        yawError = yawError + 360
    end

    -- PID control for yaw
    local yawOutput, yawIntegral, yawPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, yawError, yawIntegral, (yawError - yawPrevError), yawPrevError, dt)
    yawOutput = -math.min(math.max(yawOutput, -45), 45)

    helm.move(yawOutput,0,1)

    neutrallyBouyantOutput = 7
    if math.abs(yLevelDiff) > 1 then
        if yLevelDiff > 0 then --need to go up
            floaterPower = neutrallyBouyantOutput
        else --go down
            floaterPower = neutrallyBouyantOutput + 1
        end
    else
        floaterPower = neutrallyBouyantOutput
    end
    redstone.setAnalogOutput("front",floaterPower)

    local multiplier = 1
    if yaw < 240 and yaw > 120 then multiplier = multiplier + 3 end
    if missileSpeed < 25 then
        setMotorSpeedSafe(-64*multiplier)  -- Increase throttle
    else
        setMotorSpeedSafe(4*multiplier)
    end
end

local function fuze()
    local results = radar.scanForShips(2000)
    pos = ship.getWorldspacePosition()
    local distance
    if target.type == "ship" then
        for i, object in ipairs(results) do
            if object.id == lockedId then
                targetPos = object.pos
                local dx = targetPos.x - pos.x
                local dy = targetPos.y - pos.y
                local dz = targetPos.z - pos.z

                targetSpeed = math.sqrt(targetVel.x^2 + targetVel.y^2 + targetVel.z^2)
                distance = math.sqrt(dx * dx + dy * dy +dz * dz)
                horizontalDistance = math.sqrt(dx * dx +dz * dz)
            end
        end
    elseif target.type == "waypoint" then
        local dx = target.pos.x - pos.x
        local dy = target.pos.y - pos.y
        local dz = target.pos.z - pos.z
        distance = math.sqrt(dx * dx + dy * dy +dz * dz)
        horizontalDistance = math.sqrt(dx * dx +dz * dz)
        targetSpeed = 0
    end
    --proximity fuze
    if horizontalDistance < 10 and closestDistance < distance then
        print("detonating")
        redstone.setOutput("right",true)
        sleep(0.5)
        redstone.setOutput("right",false)
        sleep(0.1)
        redstone.setOutput("front",false)
        redstone.setOutput("left",false)
        redstone.setOutput("bottom",false)
        redstone.setOutput("right",false)
        redstone.setOutput("back",false)
        redstone.setOutput("top",false)
        setMotorSpeedSafe(0)
        helm.move(0,0,0)
        error("detonated")
    else
        closestDistance = distance
    end
    --impact fuze
    if redstone.getInput("left") then
        print("detonating")
        redstone.setOutput("right",true)
        sleep(0.5)
        redstone.setOutput("right",false)
        sleep(0.1)
        redstone.setOutput("front",false)
        redstone.setOutput("left",false)
        redstone.setOutput("bottom",false)
        redstone.setOutput("right",false)
        redstone.setOutput("back",false)
        redstone.setOutput("top",false)
        setMotorSpeedSafe(0)
        helm.move(0,0,0)
        error("detonated")
    end
end

while true do
    local results = radar.scanForShips(2000)
    pos = ship.getWorldspacePosition()
    local targetSpeed = 0

    if target.type == "ship" then
        for i, object in ipairs(results) do
            if object.id == lockedId then
                targetPos = object.pos
                targetVel = object.velocity
                targetSpeed = math.sqrt(targetVel.x^2 + targetVel.y^2 + targetVel.z^2)

                local dx = targetPos.x - pos.x
                local dy = targetPos.y - pos.y
                local dz = targetPos.z - pos.z
                horizontalDistance = math.sqrt(dx * dx + dz * dz)
            end
        end
    elseif target.type == "waypoint" then
        local dx = target.pos.x - pos.x
        local dy = target.pos.y - pos.y
        local dz = target.pos.z - pos.z
        horizontalDistance = math.sqrt(dx * dx + dz * dz)
    end

    --print("horizontalDistance: "..horizontalDistance)
    --print("targetSpeed: "..targetSpeed)

    -- Check conditions for terminal phase
    if horizontalDistance < 100 then
        --print("terminal phrase")
        parallel.waitForAll(
            tracking,
            fuze
        )
    else
        --print("initial phrase")
        tracking()
    end
end




