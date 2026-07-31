local radar = peripheral.find("sp_radar")
local modem = peripheral.find("modem")
local monitor = peripheral.find("monitor")

local userID = io.read("Enter the player id, default: MegiRicky")
if userID = "" then
    userID = "MegiRicky"
end

local function findPointedBlock(transformationMatrix,shipPos)
    -- The negative Z-axis (forward direction in local space)
    local forwardVector = {
        x = -transformationMatrix[3][1],
        y = -transformationMatrix[3][2],
        z = -transformationMatrix[3][3]
    }

    -- Calculate yaw and pitch from the forward vector
    local yaw = math.atan2(forwardVector.x, forwardVector.z) -- Yaw in radians
    local pitch = math.asin(forwardVector.y / math.sqrt(forwardVector.x^2 + forwardVector.y^2 + forwardVector.z^2)) -- Pitch in radians

    -- Get the ship's world position

    print("yaw"..math.deg(yaw))

    -- Calculate the target position 100 blocks away
    local distance = 10
    local horizontalDistance = distance * math.cos(pitch)
    print("horizontalDistance: "..horizontalDistance)
    local dx = -horizontalDistance * math.cos(yaw)
    local dy = distance * math.sin(pitch)
    local dz = horizontalDistance * math.sin(yaw)
    local targetPos = {
        x = shipPos.x + dz,
        y = shipPos.y + dy,
        z = shipPos.z + dx
    }

    return targetPos
end

local function findPlayerInfo()
    local playerList = radar.scanForPlayers(1000)
        
    for _, player in ipairs(playerList) do
        local playerName = player.nickname
        local playerPosition = player.pos
        local lookAngle = player.look_angle

        if player.nickname == userID then
            pInfo = {
                nickname = player.nickname,
                pos = player.pos,
                lookVector = lookAngle
            }
        end
    end

    return pInfo
end

-- Call the function and print the target position
local transformationMatrix = ship.getTransformationMatrix()
local shipPos = ship.getWorldspacePosition()
local targetPos = findPointedBlock(transformationMatrix,shipPos)
if targetPos then
    print("Pointed position: " .. textutils.serialize(targetPos))
else
    print("No block found.")
end

local function findLineEquation(coord1, coord2)
    -- Extract coordinates
    local x1, y1 = coord1.x, coord1.y
    local x2, y2 = coord2.x, coord2.y

    -- Check for a vertical line
    if x1 == x2 then
        return nil, nil, true -- Vertical line, no slope or intercept
    end

    -- Calculate slope (m)
    local m = (y2 - y1) / (x2 - x1)

    -- Calculate y-intercept (b)
    local b = y1 - m * x1

    return m, b, false -- Return slope (m), y-intercept (b), and vertical flag
end

local function worldToScreen(d_player,d_target)
    findLineEquation()



while true do
    pInfo = findPlayerInfo()
    local transformationMatrix = ship.getTransformationMatrix()
    local shipPos = ship.getWorldspacePosition()
    targetPos = findPointedBlock(transformationMatrix,shipPos)
    --finding dx and dz of player and target to the center of gravity of screen
    local d_player.x = player.pos[1] - shipPos.X
    local d_player.y = player.pos[2] - shipPos.y
    local d_player.z = player.pos[3] - shipPos.z
    
    local d_target.x = targetPos.x - shipPos.x
    local d_target.y = targetPos.y - shipPos.y
    local d_target.z = targetPos.z - shipPos.z



