--engineControl.lua
local defaultBaseChannel = 200

print("Enter base channel (press Enter to use default: " .. defaultBaseChannel .. "):")
local inputChannel = io.read()
if inputChannel == "" then
    inputChannel = 200
end
inputChannel = tonumber(inputChannel)

local statusChannel = inputChannel
local controlChannel = inputChannel + 1

local engine = peripheral.wrap("left")
local floaterPropeller = peripheral.wrap("right")
local fuel = peripheral.find("create_connected:item_silo")
local stress = peripheral.find("Create_Stressometer")
local acc = peripheral.find("modular_accumulator")
local modem = peripheral.wrap("front")
local router = peripheral.find("redrouter")
--local arController = peripheral.find("arController")

--arController.clear()

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

if not engine then
    error("rotation controller not found")
elseif not modem then
    error("modem not found")
end

if stress then
    modem.open(statusChannel)
else
    print("Warning: Stressometer not found. Skipping stress monitoring.")
end

if fuel then
    modem.open(statusChannel)
else
    print("Warning: Fuel silo not found. Skipping fuel monitoring.")
end

if acc then
    modem.open(statusChannel)
else
    print("Warning: Accumulator not found. Skipping accumulator monitoring.")
end

modem.open(statusChannel)
modem.open(controlChannel)

local engineRPM = 0
local messageTable = nil
local turnLevel = 0
local yaw = 0
local desiredYlevel = 0
local floaterPower = 6

local function listenForCoordinates()
    while true do
        local event, side, senderChannel, replyChannel, message, senderDistance = os.pullEvent("modem_message")
        if senderChannel == controlChannel then
            messageTable = message
            engineRPM = message.engineRPM
            turnLevel = message.turnLevel
            desiredYlevel = message.desiredYlevel
        end
    end
end

local function updateSpeed()
    while true do
        if arController and ship then
            velocity = ship.getVelocity()
            speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2) * 1.94384449
            arController.clearElement("speed")
            arController.drawStringWithId("speed", "Speed: " .. (math.floor(speed * 100) / 100) .. " knots", 10, 210, 0xFFFFFF)
        end
        sleep(0.1)
    end
end

local function updateYaw()
    while true do
        if arController and ship then
            local yaw = math.deg(getYaw()) + 270
            if yaw < 0 then yaw = yaw + 360 end
            arController.clearElement("yaw")
            arController.drawStringWithId("yaw", "Heading: " .. (math.floor(yaw * 100) / 100) .. " degree", 10, 220, 0xFFFFFF)
        end
        sleep(0.1)
    end
end

local function updateLeftSpeed()
    while true do
        if arController then
            arController.clearElement("leftSpeed")
            arController.drawStringWithId("leftSpeed", "Left RPM: " .. leftSpeed, 10, 230, 0xFFFFFF)
        end
        sleep(0.1)
    end
end

local function updateRightSpeed()
    while true do
        if arController then
            arController.clearElement("rightSpeed")
            arController.drawStringWithId("rightSpeed", "Right RPM: " .. rightSpeed, 10, 240, 0xFFFFFF)
        end
        sleep(0.1)
    end
end

local function updateTurnLevel()
    while true do
        if arController then
            arController.clearElement("turnLevel")
            arController.drawStringWithId("turnLevel", "Turn Level: " .. turnLevel, 10, 250, 0xFFFFFF)
        end
        sleep(0.1)
    end
end

local Kp_yLevel, Ki_yLevel, Kd_yLevel = 0.8,0.025,1
local dt = 0.1
local yLevelOutput,yLevelIntergral, yLevelPrevError = 0,0,0


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

local function yLevelControl()
    while true do
        local pos = ship.getWorldspacePosition()
        local yLevelError = desiredYlevel - pos.y
        local yLevelOutput,yLevelIntergral, yLevelPrevError = PIDController(Kp_yLevel, Ki_yLevel, Kd_yLevel, yLevelError, yLevelIntergral, (yLevelError - yLevelPrevError), yLevelPrevError, dt)
        local floaterPropellerRPM = -32 --neutrally buoyant RPM
        if turnLevel ~= 0 then
            floaterPropellerRPM = floaterPropellerRPM - 25
        end
        if engineRPM > 80 then
            floaterPropellerRPM = floaterPropellerRPM - 30
        end
        if engineRPM > 80 and turnLevel ~= 0 then
            floaterPropellerRPM = floaterPropellerRPM - 30
        end


        floaterPropellerRPM = math.min(math.max(floaterPropellerRPM + yLevelOutput, -256),256)
        floaterPropeller.setTargetSpeed(floaterPropellerRPM)
        print("desiredYLevel: "..desiredYlevel)
        print("yLevelOutput: "..yLevelOutput)
        print("floaterPower: "..floaterPropellerRPM)
        sleep(0.08)
    end
end

parallel.waitForAny(
    listenForCoordinates,updateSpeed, updateYaw, updateLeftSpeed, updateRightSpeed, updateTurnLevel, yLevelControl,
    function()
        while true do
            local statusData = {}

            -- Fuel monitoring
            if fuel then
                local totalBlazeCakes = 0
                local total = fuel.size() * 64
                local items = fuel.list()
                for slot, itemDetail in pairs(items) do
                    if itemDetail.name == "create:blaze_cake" then
                        totalBlazeCakes = totalBlazeCakes + itemDetail.count
                    end
                end
                statusData.fuel = { totalBlazeCakes = totalBlazeCakes, total = total }
                print("Total number of blaze cakes: ", totalBlazeCakes.." / "..total)
            end

            -- Stress monitoring
            if stress then
                local usedSU = stress.getStress()
                local SUCapacity = stress.getStressCapacity()
                statusData.stress = { usedSU = usedSU, SUCapacity = SUCapacity }
                print("Used SU: ", usedSU)
                print("SU Capacity: ", SUCapacity)
            end

            -- Accumulator monitoring
            if acc then
                local accCapacity = acc.getCapacity()
                local accEnergy = acc.getEnergy()
                statusData.accumulator = { accEnergy = accEnergy, accCapacity = accCapacity }
                print("Accumulator Capacity: ", accCapacity)
                print("Accumulator Energy: ", accEnergy)
            end

            -- Yaw monitoring
            local yaw = math.deg(getYaw())
            if yaw < 0 then yaw = yaw + 360 end
            statusData.yaw = yaw
            print("Yaw: "..yaw)
            velocity = ship.getVelocity()
            statusData.speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2) * 1.94384449
            print(statusData.speed)

            -- Engine speeds
            statusData.leftSpeed = engineRPM
            statusData.rightSpeed = engineRPM
            --[[print(statusData.speed)
            print("Left speed: ", statusData.leftSpeed)
            print("Right speed: ", statusData.rightSpeed)
            print("turnLevel: "..turnLevel)
            print("statusChannel: "..statusChannel)
            print("controlChannel"..controlChannel)
            print("desiredYLevel: "..desiredYlevel)
            print("floaterPower: "..floaterPower)]]

            if turnLevel then
                if turnLevel < 0 then
                    redstone.setOutput("back",true)
                    redstone.setOutput("top",false)
                elseif turnLevel > 0 then
                    redstone.setOutput("back",false)
                    redstone.setOutput("top",true)
                else
                    redstone.setOutput("back",false)
                    redstone.setOutput("top",false)
                end
            end

            local serializedData = textutils.serialize(statusData)
            modem.transmit(statusChannel, 0, serializedData)

            -- Engine control
            engine.setTargetSpeed(engineRPM)

            sleep(0.2)
        end
    end
)
