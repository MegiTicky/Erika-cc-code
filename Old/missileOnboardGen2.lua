local modem = peripheral.wrap("top")
local router = peripheral.find("redrouter")
local radar = peripheral.find("sp_radar")
local motor = peripheral.find("electric_motor")

-- Channels for transmitting data
print("Enter the missile number")
local missile = read() * 10
local Xchannel = missile
local Ychannel = missile + 1
local Zchannel = missile + 2
local pitchChannel = missile + 3
local yawChannel = missile + 4
local speedChannel = missile + 5
local idChannel = missile + 6
local launchChannel = missile + 7

print("X Channel:", Xchannel)
print("Y Channel:", Ychannel)
print("Z Channel:", Zchannel)
print("Pitch Channel:", pitchChannel)
print("Yaw Channel:", yawChannel)
print("Speed Channel:", speedChannel)
print("ID Channel:", idChannel)
print("Launch Channel:", launchChannel)
os.sleep(2)

local secretKey = "YourSecretKey123"
local function isValidMessage(message)
    local key, msg = message:match("^(%w+)%:(.+)$")
    return key == secretKey, msg
end

function stringToBoolean(str)
    local trueValues = {["true"] = true}
    local falseValues = {["false"] = false}

    -- Normalize the string to lower case to make the function case-insensitive
    str = string.lower(str)

    -- Check if the string is a known true value
    if trueValues[str] then
        return true
    elseif falseValues[str] ~= nil then
        return false
    else
        -- Handle other strings that are not explicitly true or false
        -- You can choose to return `false` or handle it as an error
        return false
    end
end

-- Make sure the modem is open on the channels you want to use
modem.open(yawChannel)
modem.open(Xchannel)
modem.open(Ychannel)
modem.open(Zchannel)
modem.open(pitchChannel)
modem.open(speedChannel)
modem.open(idChannel)
modem.open(launchChannel)

-- Function to convert radians to degrees
local function toDegrees(radians)
    return radians * (180 / math.pi)
end

-- Function to convert degrees to a bearing
local function toBearing(degrees)
    local bearing = degrees % 360
    bearing = bearing - 270
    if bearing < 0 then
        bearing = 360 + bearing
    end
    return bearing
end

local function listenForCoordinates()
    while true do
        local event, side, senderChannel, replyChannel, message, senderDistance = os.pullEvent("modem_message")
        local valid, validatedMessage = isValidMessage(message)
        if valid then
            if senderChannel == launchChannel then
                launched = stringToBoolean(validatedMessage)
            elseif senderChannel == idChannel then
                targetID = tonumber(validatedMessage)
            end
        end
    end
end

function serializeTable(t)
    local serializedValues = {}
    for k, v in pairs(t) do
        k = tostring(k)
        if type(v) == "number" or type(v) == "string" then
            table.insert(serializedValues, k .. "=" .. tostring(v))
        elseif type(v) == "table" then
            table.insert(serializedValues, k .. "={" .. serializeTable(v) .. "}")
        else
            error("Cannot serialize value of type " .. type(v))
        end
    end
    return table.concat(serializedValues, ",")
end

-- Main loop to constantly transmit the yaw, pitch, and position data
router.setOutput("top",false)
router.setOutput("bottom",false)
router.setOutput("left",false)
router.setOutput("right",false)

local function round(num)
    return math.floor(num + 0.5)
end

local lockedTarget = {}
local firstTime = true

parallel.waitForAny(listenForCoordinates,function()
while true do
    -- Yaw data
    local matrix = ship.getRotationMatrix()
    local forwardX = matrix[1][3]
    local forwardZ = matrix[3][3]
    local yawRadians = math.atan2(-forwardX, forwardZ)
    local yawDegrees = toDegrees(yawRadians)
    local currentYaw = toBearing(yawDegrees) - 90
    if currentYaw < 0 then
        currentYaw = currentYaw +360
    end

    modem.transmit(yawChannel, 0, secretKey..":"..currentYaw)
    
    -- Position data
    local pos = ship.getWorldspacePosition()
    local sourceX = pos.x
    local sourceY = pos.y
    local sourceZ = pos.z
    local velocity = ship.getVelocity()
    local speed = math.sqrt(velocity.x ^ 2 + velocity.y ^ 2 + velocity.z ^ 2)
    modem.transmit(Xchannel, 0, secretKey..":"..sourceX)
    modem.transmit(Ychannel, 0, secretKey..":"..sourceY)
    modem.transmit(Zchannel, 0, secretKey..":"..sourceZ)
    
    modem.transmit(speedChannel, 0, secretKey .. ":" .. serializeTable(velocity))
    

    --pitch
    currentPitch = toDegrees(-math.asin(ship.getRotationMatrix()[2][3])) * (90/28.6478)
    
    modem.transmit(pitchChannel, 0, secretKey..":"..currentPitch)

    --radar scan
    
    if targetID then
        requiredID = targetID
    end
    local results = radar.scanForShips(5000)
    local possibleTargets = {}

    if requiredID then
        if not results or #results == 0 then
            table.insert(possibleTargets, "No objects detected.")
        else
            for i, object in ipairs(results) do
                local x = object.pos.x - sourceX
                local y = object.pos.y - sourceY
                local z = object.pos.z - sourceZ
                local distance = math.sqrt(x^2 + y^2 + z^2)

                if object.mass > 20000 and distance > 5 and object.id == requiredID then
                    local objectInfo = {
                        id = object.id,
                        mass = object.mass,
                        pos = object.pos,
                        velocity = object.velocity,
                        distance = distance
                    }
                    table.insert(possibleTargets, objectInfo)
                end
            end

        end
        lockedTarget = possibleTargets[1]
    end
    

    --detonation

    redstone.setOutput("left",false)
    redstone.setOutput("back",false)
    redstone.setOutput("right",false)

    print("targetID: ",requiredID)
    print("launched: ",launched)
    print("firstTime: "..tostring(firstTime))
    print("missile number: "..tostring(missile / 10))
    print("lockedTarget: ", lockedTarget.id)
    print("missileID: ", ship.getId())
    print("target distnace", lockedTarget.distance)
    modem.transmit(idChannel,0 ,secretKey..":"..ship.getId())
    print("Transmitting Yaw: " .. currentYaw)
    print("Transmitting X: " .. sourceX)
    print("Transmitting Y: " .. sourceY)
    print("Transmitting Z: " .. sourceZ)
    print("Transmitting pitch:",currentPitch)
    print("speed: ",speed)

    if lockedTarget.id then
        print("id: ",lockedTarget.id," pos: ", round(lockedTarget.pos.x), round(lockedTarget.pos.y), round(lockedTarget.pos.z))
        local estimateX = lockedTarget.pos.x + lockedTarget.velocity.x * (lockedTarget.distance/speed)
        local estimateY = lockedTarget.pos.y + lockedTarget.velocity.y * (lockedTarget.distance/speed)
        local estimateZ = lockedTarget.pos.z + lockedTarget.velocity.z * (lockedTarget.distance/speed)

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        -- Calculate the required yaw and pitch to hit the target
        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = yaw + 180
        print("dy: ",dy," Hdistance: ",horizontalDistance)
        print("pitch: ",pitch," yaw: ",yaw)
    
        -- Adjust the missile's orientation based on the target's positio,
        if lockedTarget.pos.y < 130 then
            yaw_tolerance = 5
            pitch_tolerance = 5
        elseif lockedTarget.pos.y > 130 then
            yaw_tolerance = 0.5
            pitch_tolerance = 0.5
        end
        local deltaYaw = yaw - currentYaw
        local deltaYaw = (deltaYaw + 180) % 360 - 180

        --initial launch
        
        if launched == true then
            if firstTime == true then
                motor.setSpeed(-256)
                sleep(2)
                firstTime = false
            end
        else
            firstTime = true
        end

        -- Flight control
        if launched == true then
            print("dyaw:",deltaYaw)
            if math.abs(deltaYaw) > yaw_tolerance then
                if deltaYaw < 0 then
                    print("Turning left")
                    router.setOutput("right",true)
                    router.setOutput("left",false)
                elseif deltaYaw > 0 then
                    print("Turning right")
                    router.setOutput("right",false)
                    router.setOutput("left",true)
                end
            else
                router.setOutput("right",false)
                router.setOutput("left",false)
            end

            local control = "stopPitch"
            if math.abs(pitch - currentPitch) > pitch_tolerance then
                if pitch > currentPitch and sourceY < 1500 then
                    print("Turning up")
                    control = "up"
                elseif pitch > currentPitch  and sourceY > 115 then
                    print("Turning down")
                    control = "down"
                else
                end
            else 
                control = "stopPitch"
            end
            if velocity.y > 5 then
                print("turning down")
                control = "down"
            elseif velocity.y < -5 then
                print("turning up")
                control = "up"
            end
            if sourceY < 120 and lockedTarget.distance > 100 then
                print("Turning up")
                control = "up"
            end

            if control == "up" then
                router.setOutput("bottom",true)
                router.setOutput("top",false)
            elseif control == "down" then
                router.setOutput("bottom",false)
                router.setOutput("top",true)
            else
                router.setOutput("bottom",false)
                router.setOutput("top",false)
            end
        else
            router.setOutput("bottom",false)
            router.setOutput("top",false)
            router.setOutput("right",false)
            router.setOutput("left",false)
            motor.setSpeed(0)
        end

        if launched == true then
            if sourceY - lockedTarget.pos.y > 10 and sourceY > 118 then
                motor.setSpeed(-32)
            elseif math.abs(deltaYaw) > 15 and speed > 30 then
                motor.setSpeed(-32)
            elseif lockedTarget.pos.y < 130 and lockedTarget.distance < 100 and sourceY - lockedTarget.pos.y > 10 and sourceY > 110 then
                motor.setSpeed(-4)
            else
                motor.setSpeed(-256)
            end
        else 
            motor.setSpeed(0)
        end
        --detonation
        if launched and lockedTarget.distance < 120 and lockedTarget.pos.y < 130 and speed < 5 then --anti ship
            redstone.setOutput("left",true)
            redstone.setOutput("right",true)
        elseif launched and lockedTarget.distance < 10 and lockedTarget.pos.y > 130 then --anti air
            redstone.setOutput("left",true)
            redstone.setOutput("right",true)
        else
            redstone.setOutput("left",false)
            redstone.setOutput("right",false)
        end
    
    end
    sleep(0.01)
end
end)