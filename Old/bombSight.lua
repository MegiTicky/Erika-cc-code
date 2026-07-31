-- Find peripherals
local monitor = peripheral.find("monitor")
local arController = peripheral.find("arController")

-- Utility functions
local function toDegrees(radians)
    return radians * (180 / math.pi)
end

local function toRadians(degrees)
    return degrees * (math.pi / 180)
end

-- Initialize monitor
monitor.setTextScale(0.5)
monitor.clear()
monitor.setCursorPos(1, 1)
arController.clear()
redstone.setOutput("front", true) -- Assuming front controls the bomb drop
sleep(0.5)
redstone.setOutput("front", false)

local function parseCoordinates(input)
    local x, y, z = input:match("([^%s]+)%s+([^%s]+)%s+([^%s]+)")
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

print("Input the target's coordinate (x y z)(space between)")
local inputCoords = read()
local target = parseCoordinates(inputCoords)
print(target.x)
print(target.y)
print(target.z)
local targetX = target.x
local targetY = target.y
local targetZ = target.z

-- Calculate direction vector to the target
local function calculateYawToTarget(targetX, targetY, targetZ)
    local pos = ship.getWorldspacePosition()
    local deltaX = targetX - pos.x
    local deltaZ = targetZ - pos.z
    local yaw = toDegrees(math.atan2(-deltaX, deltaZ))
    local yaw = yaw + 180
    if yaw < 0 then yaw = yaw + 360 end
    return yaw
end

-- Check if yaw is correct
local function isYawCorrect(targetYaw)
    local currentYaw = toRadians(ship.getYaw())
    return math.abs(currentYaw - targetYaw) < math.rad(5) -- within 5 degrees tolerance
end

-- Calculate distance to target
local function calculateDistanceToTarget(targetX, targetY, targetZ)
    local pos = ship.getWorldspacePosition()
    local deltaX = targetX - pos.x
    local deltaY = targetY - pos.y
    local deltaZ = targetZ - pos.z
    return math.sqrt(deltaX^2 + deltaY^2 + deltaZ^2)
end

-- Calculate the drop distance using projectile motion equations
local function calculateDropDistance(targetY)
    local currentPos = ship.getWorldspacePosition()
    local velocity = ship.getVelocity()
    local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
    local gravity = 9.81 -- acceleration due to gravity (m/s^2)
    local height = currentPos.y - targetY
    return speed * math.sqrt(2 * height / gravity)
end

local function clearLine(lineId, x, y, length)
    arController.drawStringWithId(lineId, string.rep(" ", length), x, y, 0x000000) -- Draws a string of spaces to clear the line
end

local function updateARDisplay(targetYaw, targetYawDegrees, isYawCorrect, distanceToTarget, dropDistance)
    -- Define positions and lengths for each line
    local xPos = 300
    local lengths = {40, 40, 40, 40, 40}
    local yPos = {30, 40, 50, 60, 70}
    
    -- Clear each line before rendering new information
    clearLine("targetYawClear", xPos, yPos[1], lengths[1])
    arController.drawStringWithId("targetYaw", "Target Yaw: " .. string.format("%.2f", targetYawDegrees) .. " degrees", xPos, yPos[1], 0xFFFFFF)
    
    clearLine("yawStatusClear", xPos, yPos[2], lengths[2])
    arController.drawStringWithId("yawStatus", isYawCorrect and "Yaw is Correct" or "Adjust Yaw!", xPos, yPos[2], 0xFFFFFF)
    
    clearLine("distanceToTargetClear", xPos, yPos[3], lengths[3])
    arController.drawStringWithId("distanceToTarget", "Distance to Target: " .. string.format("%.2f", distanceToTarget), xPos, yPos[3], 0xFFFFFF)
    
    clearLine("dropDistanceClear", xPos, yPos[4], lengths[4])
    arController.drawStringWithId("dropDistance", "Drop Distance: " .. string.format("%.2f", dropDistance), xPos, yPos[4], 0xFFFFFF)
    local yaw = toDegrees(ship.getYaw()) - 90
    if yaw < 0 then yaw = yaw + 360 end
    clearLine("planeYawClear", xPos, yPos[5], lengths[5])
    arController.drawStringWithId("planeYaw", "Plane Yaw: " .. string.format("%.2f", yaw) .. " degrees", xPos, yPos[5], 0xFFFFFF)
end

-- Main loop
while true do
    local targetYaw = calculateYawToTarget(targetX, targetY, targetZ)
    local targetYawDegrees = targetYaw
    
    -- Display target yaw on the monitor
    monitor.setCursorPos(1, 3)
    monitor.clearLine()
    monitor.write("Target Yaw: " .. string.format("%.2f", targetYawDegrees) .. " degrees")
    
    -- Check if current yaw is correct
    if isYawCorrect(targetYaw) then
        monitor.setCursorPos(1, 4)
        monitor.clearLine()
        monitor.write("Yaw is Correct")
    else
        monitor.setCursorPos(1, 4)
        monitor.clearLine()
        monitor.write("Adjust Yaw!")
    end
    
    -- Arm bomb and open bomb bay when button is pressed
    if redstone.getInput("left") then
        monitor.setCursorPos(1, 5)
        monitor.clearLine()
        monitor.write("Bomb Armed and Bomb Bay Opened")
        break
    end
    
    updateARDisplay(targetYaw, targetYawDegrees, isYawCorrect(targetYaw), calculateDistanceToTarget(targetX, targetY, targetZ), calculateDropDistance(targetY))
    sleep(0.1) -- delay to avoid excessive CPU usage
end

-- Fly to target and drop bomb
while true do
    local distanceToTarget = calculateDistanceToTarget(targetX, targetY, targetZ)
    local dropDistance = calculateDropDistance(targetY)
    local targetYaw = calculateYawToTarget(targetX, targetY, targetZ)
    local targetYawDegrees = targetYaw
    
    monitor.setCursorPos(1, 6)
    monitor.clearLine()
    monitor.write("Distance to Target: " .. string.format("%.2f", distanceToTarget))
    monitor.setCursorPos(1, 7)
    monitor.clearLine()
    monitor.write("Drop Distance: " .. string.format("%.2f", dropDistance))
    
    if distanceToTarget - 20 <= dropDistance then
        redstone.setOutput("front", true) -- Assuming front controls the bomb drop
        monitor.setCursorPos(1, 8)
        monitor.clearLine()
        monitor.write("Bomb Dropped")
        arController.drawStringWithId("bomb", "Bomb dropped", 200, 50, 0xFFFFFF)

        sleep(5)
        redstone.setOutput("front", false)
        break
    end

    updateARDisplay(targetYaw, targetYawDegrees, isYawCorrect(targetYaw), distanceToTarget, dropDistance)
    
    sleep(0.1) -- delay to avoid excessive CPU usage
end
