--send yaw pitch data
modem = peripheral.find("modem")

function askUser(prompt, defaultValue)
    print(prompt .. " (default (press enter to use default): " .. defaultValue .. ")")
    print("Automatically applying default value in 10sec")

    local timer = os.startTimer(10)  -- Set a timer for 10 seconds
    local input = ""
    local isTimedOut = false

    -- Start a loop to capture user input or wait for the timer
    while true do
        local event, param = os.pullEvent()
        if event == "timer" and param == timer then
            -- Timer expired, apply the default value
            isTimedOut = true
            break
        elseif event == "char" then
            print(param)
            -- Capture character input from the user
            input = input .. param
        elseif event == "key" then
            --print(param)
            if param == 257 then  -- Enter key (key code 28)
                -- User pressed Enter
                print("enter pressed")
                break
            end
        end
    end

    -- If the input is empty and timed out, return the default value
    if isTimedOut or input == "" then
        return defaultValue
    else
        return input
    end
end

gunCommunicaitonChannel = askUser("Input the gun communication channel",1021)
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

while true do
    gunInfo = {
        pos = ship.getWorldspacePosition(),
        pitch = getPitch(),
        yaw = getYaw(),
        roll = getRoll()
    }
    print("sending gun info to "..gunCommunicaitonChannel)
    print(textutils.serialize(gunInfo))
    modem.transmit(gunCommunicaitonChannel,0,gunInfo)
    sleep()
end

