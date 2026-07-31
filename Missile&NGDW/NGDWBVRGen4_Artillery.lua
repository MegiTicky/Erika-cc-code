local monitor = peripheral.find("monitor")
local radar = peripheral.find("sp_radar")
local modem = peripheral.wrap("right")
local speaker = peripheral.find("speaker")
local yawMotor = peripheral.find("Create_RotationSpeedController")

-- Ensure all required peripherals are connected
if not monitor or not radar or not ship then
    error("Required peripherals are not attached")
end

monitor.setTextScale(0.5)
monitor.clear()
yawMotor.setTargetSpeed(0)

local radarScale = 500
local friendlyID = {289, 232}
local targetPositions = {}
local waypoints = {}
local displayState = "radar" -- Initial display state
local selectedTarget = nil
local lockedTargetId = nil
local lockedWaypoint = nil -- Variable to store the locked waypoint
local projectileSpeed = 320 --m/s
local spreadConstant = 0.5
local requiredRelativeYaw,requiredRelativePitch = 0,0

-- Get channel data for cannons
local function getChannelInput(prompt, default)
    print(prompt .. ", default: " .. default)
    local input = io.read()
    if input == "" then
        input = default
    end
    return tonumber(input)
end

local waypointChannel = getChannelInput("Input the control channel",1421)
modem.open(waypointChannel)

local cannonData = {
    port5inch = {hitPosX = nil, hitPosY = nil, hitPosZ = nil, pitch = nil, yaw = nil, source = {} },
    starboard5inch = {hitPosX = nil, hitPosY = nil, hitPosZ = nil, pitch = nil, yaw = nil, source = {}},
    bow15inch = {hitPosX = nil, hitPosY = nil, hitPosZ = nil, pitch = nil, yaw = nil, source = {}},
    stern15inch = {hitPosX = nil, hitPosY = nil, hitPosZ = nil, pitch = nil, yaw = nil, source = {}},
}

local cannonTarget = {
    port5inch = { type = nil, side = "port", id = nil, x = nil, y = nil, z = nil, yawAdjust = 0, pitchAdjust = 0 },
    starboard5inch = { type = nil, side = "starboard", id = nil, x = nil, y = nil, z = nil, yawAdjust = 0, pitchAdjust = 0 },
    bow15inch = { type = nil, side = "bow", id = nil, x = nil, y = nil, z = nil, yawAdjust = 0, pitchAdjust = 0},
    stern15inch = { type = nil, side = "stern", id = nil, x = nil, y = nil, z = nil, yawAdjust = 0, pitchAdjust = 0},
}

local LaunchedMissiles = {}
local missileControls = {
    fireMissile = {}
}
local immediateMissileInfo = {}
local AIMInfoList,GBUInfoList,thunderBoltInfoList = {},{},{}
local pendingMissileLaunches = {}
local AIMCount,GBUCount,thunderboltCount = 0,0,0

local cannons = {}
local k = 1
local nilCount = 0
local i = 0
while nilCount < 200 do
    local cannon = peripheral.wrap("createbigcannons:cannon_mount_"..tostring(i))
    if not(cannon) then
        cannon = peripheral.wrap("cbcmodernwarfare:compact_mount_"..tostring(i))
    end
    if cannon then
        cannons[k] = cannon
        k = k + 1
        nilCount = 0
        print("found cannon")
    else
        nilCount = nilCount + 1
    end
    i = i + 1
end
print("Found "..#cannons.." cannons")
for _, cannon in ipairs(cannons) do
    cannon.assemble()
end


local function checkFriendly(ID)
    local friendly = false
    for _, id in ipairs(friendlyID) do
        if tonumber(ID) == tonumber(id) then
            friendly = true
            break
        end
    end
    return friendly
end

local w, h = monitor.getSize()

local function drawControls()
    local w, h = monitor.getSize()
    monitor.setCursorPos(1, h-1)
    monitor.write("                          ")
    monitor.setCursorPos(1, h)
    monitor.write("                          ")
    monitor.setCursorPos(1, h-1)
    monitor.write("Scale: ")
    monitor.setCursorPos(8, h-1)
    monitor.write("-")
    monitor.setCursorPos(10, h-1)
    monitor.write("+")
    monitor.setCursorPos(1, h-2)
    monitor.write("Stop locking")
    monitor.setCursorPos(1, h-3)
    monitor.write("Fire Cannons")

    local segmentLength = radarScale / 2
    local scaleText
    if segmentLength >= 1000 then
        scaleText = string.format("%.1f km", segmentLength / 1000)
    else
        scaleText = string.format("%d m", segmentLength)
    end

    monitor.setCursorPos(1, h)
    monitor.write("Segment Length: " .. scaleText)

    -- Add button to navigate to waypoint page at the bottom right corner
    monitor.setCursorPos(w-10, h-1)
    monitor.write("Waypoints")

    -- Add button to navigate to the cannon adjustment page at the top right corner
    monitor.setCursorPos(w-13, 1)
    monitor.write("Adjust Cannon")
end

local function addWaypoint(x, y, z, color)
    local newWaypoint = {
        x = x,
        y = y,
        z = z,
        color = color or colors.purple
    }
    table.insert(waypoints, newWaypoint)
end

local function deleteWaypointByPos(x, y, z)
    for i = #waypoints, 1, -1 do
        local wp = waypoints[i]
        if wp.x == tonumber(x) and wp.y == tonumber(y) and wp.z == tonumber(z) then
            table.remove(waypoints, i)
            return true
        end
    end
    return false
end

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

local function drawWaypointPage()
    local w, h = monitor.getSize()
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.write("Waypoint Page")
    monitor.setCursorPos(1, 3)
    monitor.write("Enter coordinates (x, y, z) and color:")
    monitor.setCursorPos(1, 4)
    monitor.write("Format: x,y,z,color")
    monitor.setCursorPos(1, 5)
    monitor.write("Colors: red, yellow, green, blue, purple")
    monitor.setCursorPos(1, h-1)
    monitor.write("Enter to submit, Back to cancel.")
end

local function drawCannonAdjustmentPage()
    local w, h = monitor.getSize()
    monitor.clear()

    -- 标题
    monitor.setCursorPos(1, 1)
    monitor.write("Cannon Adjustment")

    -- 顶部右上角控制按钮布局起点
    local cx = w - 16

    -- 上移按钮
    monitor.setCursorPos(cx, 1)
    monitor.write("     [     ]")
    monitor.setCursorPos(cx, 2)
    monitor.write("     [  +  ]")
    monitor.setCursorPos(cx, 3)
    monitor.write("     [     ]")

    -- 左右按钮（Yaw）
    monitor.setCursorPos(cx, 4)
    monitor.write("[     ]   [     ]")
    monitor.setCursorPos(cx, 5)
    monitor.write("[  -  ] R [  +  ]")
    monitor.setCursorPos(cx, 6)
    monitor.write("[     ]   [     ]")

    -- 下移按钮
    monitor.setCursorPos(cx, 7)
    monitor.write("     [     ]")
    monitor.setCursorPos(cx, 8)
    monitor.write("     [  -  ]")
    monitor.setCursorPos(cx, 9)
    monitor.write("     [     ]")

    -- Spread 控制（左侧）
    monitor.setCursorPos(1, 3)
    monitor.write("Spread: [-]"..string.sub(string.format("%.2f", spreadConstant), 1, 3).."[+]")

    monitor.setCursorPos(1, 5)
    monitor.write(string.format("Pitch: %.1f", requiredRelativePitch))
    monitor.setCursorPos(1, 6)
    monitor.write(string.format("Yaw: %.0f", math.deg(getYaw())))

    monitor.setCursorPos(1, h-2)
    monitor.write("Stop locking")
    monitor.setCursorPos(1, h-3)
    monitor.write("Fire Cannons")

    -- 返回按钮
    monitor.setCursorPos(1, h)
    monitor.write("Back")
end

local function drawRadarBackground(centerX, centerY, radius, shipYawRadians)
    local aspectRatio = 1.5
    local segmentLength = radarScale / 4
    local pixelPerSegmentX = w / 4
    local pixelPerSegmentY = h / 4

    -- Draw the grid
    for i = 0, w - pixelPerSegmentX, pixelPerSegmentX do
        -- Vertical lines
        for y = 1, h - 2 do  -- Leave space for the scale display at the bottom
            monitor.setCursorPos(i, y)
            monitor.write("|")
        end
    end

    for j = 0, h - pixelPerSegmentY, pixelPerSegmentY do
        -- Horizontal lines
        for x = 1, w do
            monitor.setCursorPos(x, j)
            monitor.write("-")
        end
    end

    -- Draw the circle
    for i = 0, 360, 5 do
        local rad = i * (math.pi / 180)
        local x = centerX + (radius * math.sin(rad)) * aspectRatio
        local y = centerY + radius * math.cos(rad)
        monitor.setCursorPos(math.floor(x + 0.5), math.floor(y + 0.5))
        monitor.write(".")
    end

    -- Draw the crosshair
    for y = centerY - radius, centerY + radius do
        monitor.setCursorPos(centerX, y)
        monitor.write("|")
    end

    local trueBearing = (math.deg(shipYawRadians) + 360) % 360 - 180
    if trueBearing < 0 then
        trueBearing = trueBearing + 360
    end
    local textPos = centerY - radius + 10
    if textPos > 0 then
        monitor.setCursorPos(centerX - (#tostring(math.floor(trueBearing)) + 2) / 2, textPos)
        monitor.write(tostring(math.floor(trueBearing)) .. "°")
    end

    local directions = {"N", "W", "S", "E"}
    local dirAngles = {0, 90, 180, 270}

    for index, dir in ipairs(directions) do
        local dirRad = (dirAngles[index] + math.deg(shipYawRadians)) * (math.pi / 180)
        local dirX = centerX + (radius * math.sin(dirRad)) * aspectRatio
        local dirY = centerY + radius * math.cos(dirRad)
        monitor.setCursorPos(math.floor(dirX + 0.5), math.floor(dirY + 0.5))
        monitor.write(dir)
    end

    -- Display segment length
    monitor.setCursorPos(1, centerY + radius + 2)
    monitor.write("Segment Length: " .. segmentLength .. " meters")
end

local function drawTargetOnCircle(centerX, centerY, radius, relX, relY, aspectRatio)
    local dx = relX - centerX
    local dy = relY - centerY
    local mag = math.sqrt((dx / aspectRatio)^2 + dy^2)
    
    if (mag > radius) then
        local intersectX = centerX + ((dx / mag) * radius) * aspectRatio
        local intersectY = centerY + (dy / mag) * radius
        return intersectX, intersectY
    else
        return relX, relY
    end
end

local function drawCannonCrosshair(centerX, centerY, radius, aspectRatio)
    local pos = ship.getWorldspacePosition()
    local shipYawRadians = math.atan2(-ship.getTransformationMatrix()[1][3], ship.getTransformationMatrix()[3][3])
    if shipYawRadians < 0 then shipYawRadians = shipYawRadians + 2 * math.pi end
    -- Function to calculate relative yaw in degrees from ship's facing
    local function relativeYaw(dx, dz)
        local angle = math.atan2(dx, dz)
        local relativeAngle = angle + shipYawRadians - math.pi
        if relativeAngle < -math.pi then
            relativeAngle = relativeAngle + 2 * math.pi
        elseif relativeAngle >= math.pi then
            relativeAngle = relativeAngle - 2 * math.pi
        end
        return math.deg(relativeAngle)
    end

    local function drawCrosshairForCannon(cannonData, color)
        if cannonData.hitPosX and cannonData.hitPosZ then
            local dx = cannonData.hitPosX - pos.x
            local dz = cannonData.hitPosZ - pos.z
            local cannonYaw = relativeYaw(dx, dz)
            local distance = math.sqrt(dx^2 + dz^2)
            local scaledDistance = (distance / radarScale) * radius
            local relX = centerX + (scaledDistance * math.sin(math.rad(cannonYaw))) * aspectRatio
            local relY = centerY + scaledDistance * math.cos(math.rad(cannonYaw))
            relX, relY = drawTargetOnCircle(centerX, centerY, radius, relX, relY, aspectRatio)
            monitor.setCursorPos(math.floor(relX + 0.5), math.floor(relY + 0.5))
            monitor.setBackgroundColor(color)
            monitor.write("X")
            monitor.setBackgroundColor(colors.black)
            return cannonYaw
        end
        return nil
    end

    -- Draw crosshair and check range for each cannon
    local portYaw = drawCrosshairForCannon(cannonData.port5inch, colors.red)
    if portYaw and not(portYaw > 225 and portYaw < 330) then
        monitor.setCursorPos(1, 1)
        monitor.write("Warning: Port cannon may hit the ship!")
    end

    local starboardYaw = drawCrosshairForCannon(cannonData.starboard5inch, colors.blue)
    if starboardYaw and not(starboardYaw > 30 and starboardYaw < 135) then
        monitor.setCursorPos(1, 2)
        monitor.write("Warning: Starboard cannon may hit the ship!")
    end

    local bowYaw = drawCrosshairForCannon(cannonData.bow15inch, colors.green)
    if bowYaw and not(bowYaw > 120 and bowYaw < 240) then
        monitor.setCursorPos(1, 3)
        monitor.write("Warning: Bow cannon may hit the ship!")
    end

    local sternYaw = drawCrosshairForCannon(cannonData.stern15inch, colors.yellow)
    if sternYaw and not(sternYaw > 300 or sternYaw < 60) then
        monitor.setCursorPos(1, 4)
        monitor.write("Warning: Stern cannon may hit the ship!")
    end
end

local function calculateRelativeAngle(objectAngle, shipYawRadians)
    local relativeAngle = objectAngle + shipYawRadians - math.pi
    if relativeAngle < -math.pi then
        relativeAngle = relativeAngle + 2 * math.pi
    elseif relativeAngle >= math.pi then
        relativeAngle = relativeAngle - 2 * math.pi
    end
    return relativeAngle
end

local function drawRadarDisplay()
    local w, h = monitor.getSize()
    local centerX, centerY = math.floor(w / 2), math.floor(h / 2)
    local radius = math.min(centerX, centerY) - 1
    local aspectRatio = 1.2

    local matrix = ship.getTransformationMatrix()
    local shipYawRadians = math.atan2(-matrix[1][3], matrix[3][3]) 
    if (shipYawRadians < 0) then
        shipYawRadians = shipYawRadians + 2 * math.pi
    end

    drawRadarBackground(centerX, centerY, radius, shipYawRadians)
    monitor.setCursorPos(centerX, centerY)
    monitor.write("+")

    drawCannonCrosshair(centerX, centerY, radius, aspectRatio)

    local pos = ship.getWorldspacePosition()
    local results = radar.scanForShips(10000)
    targetPositions = {}
    for _, object in ipairs(results) do
        local x = object.pos.x - pos.x
        local z = object.pos.z - pos.z
        local distance = math.sqrt(x^2 + z^2)
        local objectAngle = math.atan2(x, z)
        local relativeAngle = calculateRelativeAngle(objectAngle, shipYawRadians)

        local scaledDistance = (distance / radarScale) * radius
        local relX = centerX + (scaledDistance * math.sin(relativeAngle)) * aspectRatio
        local relY = centerY + scaledDistance * math.cos(relativeAngle)

        relX, relY = drawTargetOnCircle(centerX, centerY, radius, relX, relY, aspectRatio)

        if (object.mass > 2000 and distance > 5) then
            if (distance > radarScale) then
                monitor.setTextColor(colors.lightBlue)
            else
                monitor.setTextColor(colors.red)
            end
            if (checkFriendly(object.id)) then
                monitor.setBackgroundColor(colors.blue)
            elseif (object.mass > 1000000) then
                monitor.setBackgroundColor(colors.orange)
            elseif (math.sqrt(object.velocity.x ^ 2 + object.velocity.y ^ 2 + object.velocity.z ^ 2) > 30) then
                monitor.setBackgroundColor(colors.red)
            else
                monitor.setBackgroundColor(colors.yellow)
            end
            monitor.setCursorPos(math.floor(relX + 0.5), math.floor(relY + 0.5))
            monitor.write("o")
            monitor.setTextColor(colors.green)
            monitor.setBackgroundColor(colors.black)

            table.insert(targetPositions, {x = math.floor(relX + 0.5), y = math.floor(relY + 0.5), data = object})
        end
    end

    -- Draw waypoints
    for index, waypoint in ipairs(waypoints) do
        local wpX = waypoint.x - pos.x
        local wpZ = waypoint.z - pos.z
        local distance = math.sqrt(wpX^2 + wpZ^2)
        local wpAngle = math.atan2(wpX, wpZ)
        local relativeAngle = calculateRelativeAngle(wpAngle, shipYawRadians)

        local scaledDistance = (distance / radarScale) * radius
        local relX = centerX + (scaledDistance * math.sin(relativeAngle)) * aspectRatio
        local relY = centerY + scaledDistance * math.cos(relativeAngle)

        relX, relY = drawTargetOnCircle(centerX, centerY, radius, relX, relY, aspectRatio)

        monitor.setBackgroundColor(waypoint.color)
        monitor.setCursorPos(math.floor(relX + 0.5), math.floor(relY + 0.5))
        monitor.write("W")
        monitor.setBackgroundColor(colors.black)

        table.insert(targetPositions, {x = math.floor(relX + 0.5), y = math.floor(relY + 0.5), data = {type = "waypoint", x = waypoint.x,y = waypoint.y, z = waypoint.z, index = index}})
    end    
end

local function displayTargetInfo(target)
    local w, h = monitor.getSize()
    local pos = ship.getWorldspacePosition()

    monitor.clear()
    monitor.setCursorPos(1, h-13)
    monitor.write("Target Info")
    monitor.setCursorPos(1, h-12)
    
    local targetPosX, targetPosY, targetPosZ
    if target.type == "waypoint" then
        monitor.write("Type: Waypoint")
        targetPosX, targetPosY, targetPosZ = target.x, target.y, target.z
        monitor.setCursorPos(1, h-7)
        monitor.write("Coordinate: " .. target.x .. ", "..target.y..", ".. target.z)
    else
        monitor.write("ID: " .. target.id)
        targetPosX, targetPosY, targetPosZ = target.pos.x, target.pos.y, target.pos.z
        monitor.setCursorPos(1, h-11)
        monitor.write("Mass: " .. target.mass)
        monitor.setCursorPos(1, h-10)
        monitor.write("Velocity: " .. string.format("%.2f, %.2f, %.2f", target.velocity.x, target.velocity.y, target.velocity.z))
        monitor.setCursorPos(1, h-9)
        monitor.write("Position: " .. string.format("%.2f, %.2f, %.2f", target.pos.x, target.pos.y, target.pos.z))
    end

    local distance = math.sqrt((targetPosX - pos.x)^2 + (targetPosZ - pos.z)^2)
    local dx = targetPosX - pos.x
    local dz = targetPosZ - pos.z
    local bearing = (math.deg(math.atan2(dz, dx)) + 360) % 360 - 270
    if bearing < 0 then
        bearing = bearing + 360
    end

    monitor.setCursorPos(1, h-8)
    monitor.write("Distance: " .. string.format("%.2f", distance) .. " meters")
    monitor.setCursorPos(1, h-7)
    monitor.write("Bearing: " .. string.format("%.2f", bearing) .. "°")

    if target.type ~= "waypoint" then
        local type = "unknown"
        local hostile = "hostile"
        if target.mass > 1000000 then
            type = "ship"
        elseif math.sqrt(target.velocity.x ^ 2 + target.velocity.y ^ 2 + target.velocity.z ^ 2) > 30 then
            type = "Flying missile / plane"
        else
            type = "unknown"
        end
        if checkFriendly(target.id) then
            hostile = "friendly"
        else
            hostile = "hostile"
        end
        monitor.setCursorPos(1, h-6)
        monitor.write("Type: " .. hostile .. " " .. type)
    end

    monitor.setCursorPos(1, h-5)
    monitor.write("[Direct Fire Lock]")
    monitor.setCursorPos(1, h-4)
    monitor.write("[Indirect Fire Lock]")
    monitor.setCursorPos(1, h-3)
    monitor.write("[MRIS Lock]")

    if target.type == "waypoint" then
        monitor.setCursorPos(1, h-2)
        monitor.write("[Delete Waypoint]")
    end

    monitor.setCursorPos(1, h)
    monitor.write("Back")
end

local function launchMissile(targetType, targetId, targetPos, missileType)
    local currentMissile = nil

    -- Function to find and remove the first unlaunched missile from a list
    local function findUnlaunchedMissile(missileList)
        for i = #missileList, 1, -1 do  -- Iterate in reverse to avoid index shifting issues
            local missile = missileList[i]
            if missile.launchState == false then
                missile.launchState = true  -- Mark missile as launched
                table.insert(LaunchedMissiles, missile)  -- Move to launched list
                return table.remove(missileList, i)  -- Remove from available list and return it
            end
        end
        return nil
    end
    

    -- Get the first unlaunched missile of the specified type
    if missileType == "AIM-220" then
        currentMissile = findUnlaunchedMissile(AIMInfoList)
    elseif missileType == "GBU-42" then
        currentMissile = findUnlaunchedMissile(GBUInfoList)
    elseif missileType == "thunderBolt" then
        currentMissile = findUnlaunchedMissile(thunderBoltInfoList)
    end

    -- If no unlaunched missile is found, exit function
    if not currentMissile then
        print("No available unlaunched missile of type:", missileType)
        return
    end

    local currentMissileId = currentMissile.id
    print("Launching missile " .. currentMissileId)

    -- Assign the missile as launched and set target info
    if targetType == "ship" then
        missileControls.fireMissile[currentMissileId] = {launch = true, type = targetType, id = targetId}
    else
        missileControls.fireMissile[currentMissileId] = {launch = true, type = targetType, pos = targetPos}
    end
end

local yawErrorSum = 0
local lastYawError = 0
local pitchErrorSum = 0
local lastPitchError = 0
local yawError = 0
local yawIntegral = 0
local yawPrevError = 0
local pitchError = 0
local pitchIntegral = 0
local pitchPrevError = 0
local lastTime = os.clock()

local Kp_yaw = 3.5
local Ki_yaw = 0
local Kd_yaw = 0.1
local Kp_pitch = 0.25
local Ki_pitch = 0.05
local Kd_pitch = 0.012
local dt = 0.1
local function customProportional(error, Kp)
    -- Nonlinear proportional scaling
    -- Example: Quadratic growth for small errors
    local scaleFactor = 0 -- Controls how quickly the value grows for small errors

    local absError = math.abs(error)
    local proportional = Kp * (absError / (1 + scaleFactor * absError)) -- Sigmoid-like growth

    if error < 0 then
        proportional = -proportional -- Preserve the sign of the error
    end

    return math.abs(proportional) * (error < 0 and -1 or 1) -- Cap the value
end

local function PIDController(Kp, Ki, Kd, error, integral, prevError, dt)
    -- Nonlinear proportional term using the custom function
    local proportional = customProportional(error, Kp)

    -- Integral and derivative components
    integral = integral + error * dt
    local derivative = (error - prevError) / dt
    
    -- Calculate the PID output
    local output = proportional + (Ki * integral) + (Kd * derivative)

    -- Return the PID output, updated integral, and current error
    return output, integral, error
end

local lastYawTime = os.clock()
-- Yaw control function using PID
local function yawControl(deltaYaw, currentYaw)
    local now = os.clock()
    local dtThisFrame = now - lastYawTime
    lastYawTime = now
    if dtThisFrame <= 0 then
        dtThisFrame = 0.05
    end
    -- PID controller for yaw
    --print(dtThisFrame)
    local yawSpeed, newIntegral, newPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, deltaYaw, yawIntegral, yawPrevError, dtThisFrame)

    -- 2) Update global PID state
    yawIntegral = newIntegral
    yawPrevError = newPrevError

    -- Constrain the yaw speed to prevent runaway spinning
    yawSpeed = math.max(-36, math.min(36, yawSpeed))

    --print("deltaYaw: " .. deltaYaw)
    --print("yawSpeed: " .. yawSpeed)

    -- Set motor speed based on PID output
    yawMotor.setTargetSpeed(-yawSpeed)
end

local function findRelativeAngle(targetYaw,targetPitch)
    rot = ship.getQuaternion()
    cacheYaw = math.pi - math.rad(targetYaw)
    cachePitch = - math.rad(targetPitch)
    rotMatAdj11 = 1 - 2*(rot.x^2 + rot.y^2)
    rotMatAdj12 = 2*(rot.z * rot.x + rot.y * rot.w)
    rotMatAdj13 = 2*(rot.z * rot.y - rot.x * rot.w)
    rotMatAdj21 = 2*(rot.z * rot.x - rot.y * rot.w)
    rotMatAdj22 = 1 - 2*(rot.z^2 + rot.y^2)
    rotMatAdj23 = 2*(rot.x * rot.y + rot.z * rot.w)
    rotMatAdj31 = 2*(rot.z * rot.y + rot.x * rot.w)
    rotMatAdj32 = 2*(rot.x * rot.y - rot.z * rot.w)
    rotMatAdj33 = 1 - 2*(rot.z^2 + rot.x^2)

    rotMatTGT11 = math.cos(cacheYaw) * math.cos(cachePitch)
    rotMatTGT21 = math.sin(cacheYaw) * math.cos(cachePitch)
    rotMatTGT31 = - math.sin(cachePitch)
    
    rotMatRSLT11 = rotMatAdj11 * rotMatTGT11 + rotMatAdj12 * rotMatTGT21 + rotMatAdj13 * rotMatTGT31
    rotMatRSLT21 = rotMatAdj21 * rotMatTGT11 + rotMatAdj22 * rotMatTGT21 + rotMatAdj23 * rotMatTGT31
    rotMatRSLT31 = rotMatAdj31 * rotMatTGT11 + rotMatAdj32 * rotMatTGT21 + rotMatAdj33 * rotMatTGT31

    turretYaw = math.atan2(rotMatRSLT21, rotMatRSLT11)
    barrelPitch = math.asin(-rotMatRSLT31)
    return math.deg(-turretYaw),math.deg(-barrelPitch)
end

local lockedTarget = {pos = {x = nil, y = nil, z = nil}, velocity = {x = nil, y = nil, z = nil}, type = nil, lockMode = nil}
local function setPitchYaw()
    while true do
        if lockedTarget and lockedTarget.lockMode and requiredRelativeYaw and requiredRelativePitch then
            local tasks = {} -- Table to store each cannon's task

            for index, cannon in pairs(cannons) do
                -- Define the function for this cannon's pitch/yaw adjustment
                local function adjustCannon()
                    if false then
                        -- No spread for the first cannon
                        cannon.setPitch(requiredRelativePitch)
                        cannon.setYaw(math.min(3,math.max(-3,requiredRelativeYaw)))
                        --print("Cannon " .. index .. " (Primary) set to pitch: " .. requiredRelativePitch .. " and yaw: " .. requiredRelativeYaw)
                    else
                        -- Spread logic for other cannons
                        local localSpreadConstant = spreadConstant
                        if requiredRelativePitch < 30 then localSpreadConstant=localSpreadConstant/2 end

                        local pitchVariation = math.random(-2, 2) * localSpreadConstant -- Adjust the range to control the spread
                        if requiredRelativePitch > 30 then localSpreadConstant = localSpreadConstant*6 end
                        local yawVariation = math.random(-2, 2) * localSpreadConstant  -- Adjust the range to control the spread

                        local adjustedPitch = requiredRelativePitch + pitchVariation
                        local adjustedYaw = requiredRelativeYaw + yawVariation

                        if lockedTarget.lockMode == "MRSI" or lockedTarget == "indirect" then
                            cannon.setPitch(adjustedPitch)
                            cannon.setYaw(math.min(3,math.max(-3,adjustedYaw)))
                            --print("Cannon " .. index .. " set to pitch: " .. adjustedPitch .. " and yaw: " .. adjustedYaw)
                        else
                            cannon.setPitch(requiredRelativePitch)
                            cannon.setYaw(math.min(3,math.max(-3,requiredRelativeYaw)))
                            --print("Cannon " .. index .. " set to uniform pitch: " .. requiredRelativePitch .. " and yaw: " .. requiredRelativeYaw)
                        end
                    end
                end

                -- Add this task to the tasks table
                table.insert(tasks, adjustCannon)
            end
            -- Execute all tasks in parallel
            parallel.waitForAll(table.unpack(tasks))
        end
        sleep()
    end
end

local barrel = peripheral.find("minecraft:barrel")
local depot_list = { peripheral.find("create:depot") }
-- Finds an item in the barrel that exactly matches the given display name.
local function findItemByDisplayName(displayName)
    -- get a quick list of everything in the barrel
    local items = barrel.list()
    for slot, data in pairs(items) do
        -- get full detail for the item in this slot
        local detail = barrel.getItemDetail(slot)
        if detail and detail.displayName == displayName then
            -- If matched, return slot and quantity
            return true, slot, detail.count
        end
    end
    return false
end

local function pullItemByDisplayName(displayName)
    local found, slot, count = findItemByDisplayName(displayName)
    if found then
        print("Found item '" .. displayName .. "' in slot ".. slot .." (count = "..count..")")
        for _, depot in ipairs(depot_list) do
            local pulled = depot.pullItems(peripheral.getName(barrel), slot, 1)
        end
        print("Pulled 1x '" .. displayName .. "' into deployer.")
    else
        print("No item named '" .. displayName .. "' in the barrel.")
    end
end

charge = "4Charge"
local chargeSpeeds = {
    ["2Charge"] = 113,
    ["3Charge"] = 170,
    ["4Charge"] = 230
}
local function firing(charge)
    local fireTasks = {} -- Table to store firing tasks
    pullItemByDisplayName(charge)
    sleep(1.5)
    -- Add each cannon's fire task to the table
    for index, cannon in pairs(cannons) do
        table.insert(fireTasks, function()
            cannon.fire()
            print("Cannon " .. index .. " FIRING")
        end)
    end
    sleep()

    -- Execute all tasks simultaneously
    parallel.waitForAll(table.unpack(fireTasks))
end

local g,cd,c_est = 0.05,0.995,0.0028
local function calculateRange(angle, u, cd, g, c_est)
    local radians = math.rad(angle)
    local u = u/20
    local part1 = u * math.cos(radians) / math.log(cd)
    local part2 = ((g * cd) / (g * cd + (1 - cd) * u * math.sin(radians))) ^ (2 + c_est * projectileSpeed * math.sin(radians)) - 1
    local XR = part1 * part2

    return XR
end

local function findBestPitch(targetPos, sourcePos, initialVelocity, g, cd, c_est, fireMode)
    local bestLowPitch = nil
    local bestHighPitch = nil
    local bestLowDistance = math.huge
    local bestHighDistance = math.huge
    local targetDistance = math.sqrt((targetPos.x - sourcePos.x)^2 + (targetPos.z - sourcePos.z)^2)

    for pitch = 0, 90, 0.05 do -- Iterate over pitch angles
        local calculatedRange = calculateRange(pitch, initialVelocity, cd, g, c_est)
        local distanceDifference = math.abs(calculatedRange - targetDistance)

        -- Find the low-angle solution
        if pitch <= 30 then
            if distanceDifference < 10 and distanceDifference < bestLowDistance then
                bestLowDistance = distanceDifference
                bestLowPitch = pitch
            end
        -- Find the high-angle solution
        elseif pitch > 30 then
            if distanceDifference < 10 and distanceDifference < bestHighDistance then
                bestHighDistance = distanceDifference
                bestHighPitch = pitch
            end
        end
    end

    if fireMode == "indirect" then
        return bestHighPitch or bestLowPitch
    else
        return bestLowPitch
    end
end

local function estimateFlightTime(initialSpeed, angle, cd, g)
    -- 模拟每 tick 速度衰减，单位 tick = 1/20 秒
    local dt = 1 / 20
    local rad = math.rad(angle)
    
    local vx = initialSpeed/20 * math.cos(rad)
    local vy = initialSpeed/20 * math.sin(rad)

    local x, y = 0, 0
    local t = 0

    while y >= 0 do
        -- 更新位置
        x = x + vx * dt
        y = y + vy * dt

        -- 更新速度（考虑阻力和重力）
        vx = vx * cd
        vy = vy * cd - g

        t = t + dt

        -- 安全终止（避免死循环）
        if t > 60 then break end
    end

    return t
end

local function aimSimpleFire(lockedTargetInfo)
    if lockedTargetInfo then
        local currentTime = os.clock()
        local dt = currentTime - lastTime
        if dt == 0 then return end  -- Prevent division by zero
        lastTime = currentTime
        currentYaw = math.deg(getYaw())

        local currentPosition = ship.getWorldspacePosition()

        local dx = lockedTargetInfo.pos.x - currentPosition.x
        local dy = lockedTargetInfo.pos.y - currentPosition.y
        local dz = lockedTargetInfo.pos.z - currentPosition.z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local shipVelocity = ship.getVelocity()

        local estimate = {}
        local estimateTime = distance / (projectileSpeed)
        estimate.x = lockedTargetInfo.pos.x + lockedTargetInfo.velocity.x * estimateTime
        estimate.y = lockedTargetInfo.pos.y + lockedTargetInfo.velocity.y * estimateTime
        estimate.z = lockedTargetInfo.pos.z + lockedTargetInfo.velocity.z * estimateTime

        local dx = estimate.x - currentPosition.x
        local dy = estimate.y - currentPosition.y
        local dz = estimate.z - currentPosition.z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local estimateTime = distance / (projectileSpeed)
        estimate.x = lockedTargetInfo.pos.x + lockedTargetInfo.velocity.x * estimateTime
        estimate.y = lockedTargetInfo.pos.y + lockedTargetInfo.velocity.y * estimateTime
        estimate.z = lockedTargetInfo.pos.z + lockedTargetInfo.velocity.z * estimateTime

        local dx = estimate.x - currentPosition.x
        local dy = estimate.y - currentPosition.y
        local dz = estimate.z - currentPosition.z

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        -- Adjust pitch based on distance adjustments
        projectileSpeed = 240
        if lockedTarget.lockMode == "direct" then
            pitch = pitch + findBestPitch(estimate,currentPosition, projectileSpeed, g, cd, c_est, "direct")
            charge = "4Charge"
        elseif lockedTarget.lockMode == "indirect" then
            pitch = pitch + findBestPitch(estimate,currentPosition, projectileSpeed, g, cd, c_est, "indirect")
        end
        local deltaYaw = (yaw - currentYaw + 180) % 360 - 180

        -- Turning and pitch adjustment logic
        yawControl(deltaYaw, currentYaw)
        -- Using vs addition to turn cannon
        requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw,pitch)

        lastCurrentYaw = currentYaw
    end
end

local function updateTargetInfo(lockedTarget)
    if lockedTarget.type == "waypoint" then
        return {pos = {x=lockedTarget.x,y=lockedTarget.y,z=lockedTarget.z}, velocity = {x = 0, y = 0, z = 0}, type = "waypoint", lockMode = lockMode}
    else  -- handling ships target
        local scanResults = radar.scanForShips(9999)
        for _, object in ipairs(scanResults) do
            if object.id == lockedTarget.id then
                return {pos = object.pos, velocity = object.velocity, type = "ship", lockMode = lockMode}
            end
        end
    end
end

local deltaYaw = 180
local function aimMRSIFire(lockedTarget)
    local lockedTargetInfo = updateTargetInfo(lockedTarget)
    if not lockedTargetInfo then
        print("No target info available.")
        return
    end

    local currentPosition = ship.getWorldspacePosition()
    local dx = lockedTargetInfo.pos.x - currentPosition.x
    local dz = lockedTargetInfo.pos.z - currentPosition.z
    local distance = math.sqrt(dx * dx + dz * dz)

    local viableCharges = {}

    -- Only collect indirect charges with pitch > 25
    for chargeName, speed in pairs(chargeSpeeds) do
        local indirectPitch = findBestPitch(lockedTargetInfo.pos, currentPosition, speed, g, cd, c_est, "indirect")
        if indirectPitch and indirectPitch > 13 then
            local flightTime = estimateFlightTime(speed, indirectPitch,cd, g)
            print(flightTime)
            table.insert(viableCharges, {
                charge = chargeName,
                speed = speed,
                pitch = indirectPitch,
                flightTime = flightTime
            })
        end
        local directPitch = findBestPitch(lockedTargetInfo.pos, currentPosition, speed, g, cd, c_est, "direct")
        if directPitch and directPitch > 13 then
            local flightTime = estimateFlightTime(speed, directPitch,cd, g)
            print(flightTime)
            table.insert(viableCharges, {
                charge = chargeName,
                speed = speed,
                pitch = directPitch,
                flightTime = flightTime
            })
        end
        print("Charge: "..chargeName.." speed: "..speed)
        print(indirectPitch,directPitch)
    end

    if #viableCharges == 0 then
        print("No viable indirect charges with pitch > 25.")
        return
    end

    -- Sort descending by flightTime
    table.sort(viableCharges, function(a, b) return a.flightTime > b.flightTime end)

    -- Build MRSI sequence
    local mrsiSequence = {}
    local lastTime = viableCharges[1].flightTime
    table.insert(mrsiSequence, viableCharges[1])

    for i = 2, #viableCharges do
        local delta = lastTime - viableCharges[i].flightTime
        if delta >= 3 then  -- allow a small lag, e.g., 4.0 not strict 4.5
            table.insert(mrsiSequence, viableCharges[i])
            lastTime = viableCharges[i].flightTime
        end
    end

    for i, data in ipairs(mrsiSequence) do
        print(string.format("Shot %d: %s | FlightTime: %.2f | Pitch: %.1f", i, data.charge, data.flightTime, data.pitch))
    end
    while deltaYaw > 5 do
        sleep(0.1)
    end
    -- For each charge, aim and fire sequentially
    local lastFlightTime = mrsiSequence[1].flightTime
    parallel.waitForAny(
        function()
             for i, data in ipairs(mrsiSequence) do
                -- Update target info and aim
                pullItemByDisplayName(data.charge) -- load round
                sleep(0.9)                          -- wait for reload
                local delay = math.sqrt(lastFlightTime - data.flightTime -4)  -- how long to wait before firing
                lastFlightTime = data.flightTime
                if delay > 0 then
                    print(string.format("Waiting %.2f s to fire %s", delay, data.charge))
                    sleep(delay)
                end
                lockedTargetInfo = updateTargetInfo(lockedTarget)
                currentPosition = ship.getWorldspacePosition()
                local dx = lockedTargetInfo.pos.x - currentPosition.x
                local dy = lockedTargetInfo.pos.y - currentPosition.y
                local dz = lockedTargetInfo.pos.z - currentPosition.z
                local horizontalDistance = math.sqrt(dx * dx + dz * dz)
                local pitch = math.deg(math.atan2(dy, horizontalDistance))
                local yaw = math.deg(math.atan2(-dx, dz))
                if data.pitch < 30 then
                    pitch = pitch + findBestPitch(lockedTargetInfo.pos, currentPosition, data.speed, g, cd, c_est, "direct")
                else
                    pitch = findBestPitch(lockedTargetInfo.pos, currentPosition, data.speed, g, cd, c_est, "indirect")
                end
                
                yaw = (yaw + 180) % 360
                local currentYaw = math.deg(getYaw())
                if currentYaw < 0 then currentYaw = currentYaw + 360 end
                local deltaYaw = yaw - currentYaw
                if deltaYaw > 180 then
                    deltaYaw = deltaYaw - 360
                elseif deltaYaw < -180 then
                    deltaYaw = deltaYaw + 360
                end
                print(string.format("Firing %s | Pitch: %.2f | Yaw: %.2f", data.charge, pitch, yaw))
                requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw, pitch)
                sleep(0.3)
                -- Fire
                for _, cannon in pairs(cannons) do
                    cannon.fire()
                end
                sleep(0.5)
                for _, cannon in pairs(cannons) do
                    cannon.fire()
                end
                sleep(2.5)     
            end
        end,
        function()
            while true do
                for index, cannon in pairs(cannons) do
                    --cannon.fire()
                end
                sleep(0.1)
            end
        end
    )
end

local function aimCannonContinuous()
    while true do
        if lockedTarget.lockMode then
            local lockedTargetInfo = updateTargetInfo(lockedTarget)
            if lockedTarget.lockMode == "direct" or lockedTarget.lockMode == "indirect" then
                aimSimpleFire(lockedTargetInfo)
            elseif lockedTarget.lockMode == "MRSI" then
                --Lock yaw
                -- Calculate yaw
                local currentPosition = ship.getWorldspacePosition()
                local yaw = math.deg(math.atan2(-(lockedTargetInfo.pos.x - currentPosition.x), lockedTargetInfo.pos.z - currentPosition.z))
                yaw = (yaw + 180) % 360

                -- Calculate requiredRelativeYaw/Pitch (these will be applied by setPitchYaw loop)
                local currentYaw = math.deg(getYaw())
                if currentYaw < 0 then currentYaw = currentYaw + 360 end

                deltaYaw = yaw - currentYaw
                if deltaYaw > 180 then
                    deltaYaw = deltaYaw - 360
                elseif deltaYaw < -180 then
                    deltaYaw = deltaYaw + 360
                end
                yawControl(deltaYaw, currentYaw)
            end
        end
        sleep()
    end
end

local function handleTouch()
    local w, h = monitor.getSize()
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        if displayState == "radar" then
            if y == h-1 and x >= 8 and x <= 9 then
                radarScale = math.max(100, radarScale - 100)
                drawControls()
                drawRadarDisplay()
            elseif y == h-1 and x >= 10 and x <= 11 then
                radarScale = math.min(10000, radarScale + 100)
                drawControls()
                drawRadarDisplay()
            elseif y == h-1 and x >= w-10 and x <= w then
                displayState = "waypoints"
                monitor.clear()
                drawWaypointPage()

                print("Enter waypoint coordinates (x, y, z, color), color options: red, yellow, green, blue (or leave blank for random):")
                local input = read()

                -- Parse input with better error handling
                local x, y, z, color = input:match("([^,]+),([^,]+),([^,]+),?([^,]*)")

                -- Trim whitespace from all values
                x = x and x:match("^%s*(.-)%s*$")
                y = y and y:match("^%s*(.-)%s*$")
                z = z and z:match("^%s*(.-)%s*$")
                color = color and color:match("^%s*(.-)%s*$")

                -- Color handling with random fallback
                local colorMap = {
                    red = colors.red,
                    yellow = colors.yellow,
                    green = colors.green,
                    blue = colors.blue,
                    white = colors.white,
                    orange = colors.orange,
                    lightBlue = colors.lightBlue,
                    lime = colors.lime,
                    pink = colors.pink,
                    gray = colors.gray,
                    lightGray = colors.lightGray,
                    cyan = colors.cyan,
                    purple = colors.purple,
                    brown = colors.brown,
                    black = colors.black
                }

                local colorValue
                if not color or color == "" then
                    -- Generate random color from available options
                    local colorKeys = {}
                    for k in pairs(colorMap) do table.insert(colorKeys, k) end
                    local randomColor = colorKeys[math.random(#colorKeys)]
                    colorValue = colorMap[randomColor]
                    print("Assigned random color: "..randomColor)
                else
                    colorValue = colorMap[color:lower()] or colors.yellow -- Default to yellow if invalid color
                end

                -- Validate coordinates
                if x and y and z then
                    x, y, z = tonumber(x), tonumber(y), tonumber(z)
                    if x and y and z then
                        addWaypoint(x, y, z, colorValue)
                    else
                        print("Error: Invalid coordinates")
                    end
                else
                    print("Error: Missing coordinates")
                end

                -- Return to radar view
                displayState = "radar"
                monitor.clear()
                drawControls()
                drawRadarDisplay()
            elseif y == 1 and x >= w-13 and x <= w then
                displayState = "adjustCannon"
                monitor.clear()
                drawCannonAdjustmentPage()
            elseif y == h-2 and x < 10 then
                lockedTarget = {pos = {x = nil, y = nil, z = nil}, velocity = {x = nil, y = nil, z = nil}, type = nil, lockMode = nil}
                monitor.setCursorPos(1, 1)
                monitor.clear()
                drawRadarDisplay()
                monitor.write("Locking stopped.")
            elseif y == h-3 and x < 13 then
                if lockedTarget.lockMode == "indirect" or lockedTarget.lockMode == "direct" then
                    firing(charge)
                    monitor.setCursorPos(1, 1)
                    monitor.write("Firing!")
                elseif lockedTarget.lockMode == "MRSI" then
                    aimMRSIFire(lockedTarget)
                end
            else
                for _, target in ipairs(targetPositions) do
                    if x == target.x and y == target.y then
                        selectedTarget = target.data
                        displayState = "targetInfo"
                        displayTargetInfo(selectedTarget)
                        break
                    end
                end
            end
        elseif displayState == "targetInfo" then
            if y == h and x >= 1 and x <= 4 then
                -- Back button
                displayState = "radar"
                monitor.clear()
                drawRadarDisplay()
            elseif y == h-5 and x >= 1 and x <= 10 then
                -- Lock with direct fire mode
                lockedTarget = selectedTarget
                lockedTarget.lockMode = "direct"
                displayState = "radar"
                monitor.clear()
                drawRadarDisplay()
                monitor.setCursorPos(1, 1)
                monitor.write("Target locked: " .. (selectedTarget.type == "waypoint" and "Waypoint" or selectedTarget.id))
            elseif y == h-4 and x >= 1 and x <= 18 then
                -- Lock with indirect fire mode
                lockedTarget = selectedTarget
                lockedTarget.lockMode = "indirect"
                displayState = "radar"
                monitor.clear()
                drawRadarDisplay()
                monitor.setCursorPos(1, 1)
                monitor.write("Target locked: " .. (selectedTarget.type == "waypoint" and "Waypoint" or selectedTarget.id))
            elseif y == h-3 and x >= 1 and x <= 10 then
                -- Lock with MIRS mode
                lockedTarget = selectedTarget
                lockedTarget.lockMode = "MRSI"
                displayState = "radar"
                monitor.clear()
                drawRadarDisplay()
                monitor.setCursorPos(1, 1)
                monitor.write("Target locked: " .. (selectedTarget.type == "waypoint" and "Waypoint" or selectedTarget.id))
            elseif selectedTarget.type == "waypoint" and y == h-2 and x>=1 and x <= 17 then
                --delete waypoint
                deleteWaypointByPos(selectedTarget.x,selectedTarget.y,selectedTarget.z)
                drawRadarDisplay()
                displayState = "radar"
                monitor.setCursorPos(1, 1)
                monitor.write("Deleted")
            end
        elseif displayState == "adjustCannon" then
            -- Back button
            if y == h and x >= 1 and x <= 4 then
                displayState = "radar"
                monitor.clear()
                drawRadarDisplay()
            elseif y == 3 and x>= 9 and x <= 11 then
                --decrease spreadConstant
                spreadConstant = spreadConstant - 0.1
            elseif y == 3 and x>=15 and x <= 18 then
                --increase spreadConstant
                spreadConstant = spreadConstant + 0.1
            elseif (y == 1 and x <= w-5 and x >= w - 12) or (y == 2 and x <= w-5 and x >= w - 12) or (y == 3 and x <= w-5 and x >= w - 12)then
                -- increase pitch
                requiredRelativePitch = requiredRelativePitch + 2
                for index, cannon in pairs(cannons) do
                    cannon.setPitch(requiredRelativePitch)
                end
            elseif (y == 7 and x <= w-5 and x >= w - 12) or (y == 8 and x <= w-5 and x >= w - 12) or (y == 9 and x <= w-5 and x >= w - 12)then
                -- decrease pitch
                requiredRelativePitch = requiredRelativePitch - 2
                for index, cannon in pairs(cannons) do
                    cannon.setPitch(requiredRelativePitch)
                end    
            elseif y == 5 and x == w-8 then
                requiredRelativePitch = 0
                for index, cannon in pairs(cannons) do
                    cannon.setPitch(requiredRelativePitch)
                end    
            elseif (y==4 and x <= w-1 and x>=w-8) or (y==5 and x <= w-1 and x>=w-8) or (y==6 and x <= w-1 and x>=w-8) then
                --turn right
                yawMotor.setTargetSpeed(-8)
                sleep(0.1)
                yawMotor.setTargetSpeed(0)
            elseif (y==4 and x <= w-13 and x>=w-20) or (y==5 and x <= w-13 and x>=w-20) or (y==6 and x <= w-13 and x>=w-20) then
                --turn left
                yawMotor.setTargetSpeed(8)
                sleep(0.1)
                yawMotor.setTargetSpeed(0)
            elseif y == h-2 and x < 10 then
                lockedTarget = {pos = {x = nil, y = nil, z = nil}, velocity = {x = nil, y = nil, z = nil}, type = nil, lockMode = nil}
                monitor.setCursorPos(1, 2)
                monitor.clear()
                monitor.write("Locking stopped.")
            elseif y == h-3 and x < 10 then
                firing("4Charge")
                monitor.setCursorPos(1, 2)
                monitor.write("Firing!")
            end
        end
    end
end

local newExternalWaypoint = nil
local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == port5inchChannel then
                cannonData.port5inch.hitPosX = message.x
                cannonData.port5inch.hitPosY = message.y
                cannonData.port5inch.hitPosZ = message.z
                cannonData.port5inch.pitch = message.cannonPitch
                cannonData.port5inch.yaw = message.cannonYaw
                cannonData.port5inch.source = message.source
            elseif channel == starboard5inchChannel then
                cannonData.starboard5inch.hitPosX = message.x
                cannonData.starboard5inch.hitPosY = message.y
                cannonData.starboard5inch.hitPosZ = message.z
                cannonData.starboard5inch.pitch = message.cannonPitch
                cannonData.starboard5inch.yaw = message.cannonYaw
                cannonData.starboard5inch.source = message.source
            elseif channel == bow15inchChannel then
                cannonData.bow15inch.hitPosX = message.x
                cannonData.bow15inch.hitPosY = message.y
                cannonData.bow15inch.hitPosZ = message.z
                cannonData.bow15inch.pitch = message.cannonPitch
                cannonData.bow15inch.yaw = message.cannonYaw
                cannonData.bow15inch.source = message.source
            elseif channel == stern15inchChannel then
                cannonData.stern15inch.hitPosX = message.x
                cannonData.stern15inch.hitPosY = message.y
                cannonData.stern15inch.hitPosZ = message.z
                cannonData.stern15inch.pitch = message.cannonPitch
                cannonData.stern15inch.yaw = message.cannonYaw
                cannonData.stern15inch.source = message.source
            elseif channel == missileInfoChannel then
                immediateMissileInfo = message
            elseif channel == waypointChannel then
                newExternalWaypoint = message
                print("newExternalWaypoin recieved")
            end
        else
            sleep()
        end
    end
end

local function externalWaypointHandler()
    while true do
        if newExternalWaypoint then
            print("Adding waypoint")
            if newExternalWaypoint.x and newExternalWaypoint.y and newExternalWaypoint.z and newExternalWaypoint.color then
                print(textutils.serialize(newExternalWaypoint))
                addWaypoint(newExternalWaypoint.x,newExternalWaypoint.y,newExternalWaypoint.z,newExternalWaypoint.color)
                newExternalWaypoint = nil
            end
        end
        sleep()
    end
end

local function missileWarning()
    local previousPositions = {}
    while true do
        local objectList = radar.scanForEntities(600)
        -- Initial scan to capture positions
        local initialPositions = {}
        local shipPos = ship.getWorldspacePosition()
        for _, object in ipairs(objectList) do
            if object and (object.entity_type == "entity.tallyho.ir_missile" or object.entity_type == "entity.smallarm.at_rocket") then
                if object.pos then
                    initialPositions[object.entity_type .. table.concat(object.pos, ":")] = object.pos
                    print("missile detected")
                end
            end
        end

        sleep(0.1)  -- Short delay to measure displacement

        objectList = radar.scanForEntities(600)  -- Second scan to calculate speed
        local currentPositions = {}
        for _, object in ipairs(objectList) do
            if object and (object.entity_type == "entity.tallyho.ir_missile" or object.entity_type == "entity.smallarm.at_rocket") then
                if object.pos then
                    print("Missile detected for second time")
                    local key = object.entity_type .. table.concat(object.pos, ":")
                    currentPositions[key] = object.pos
                    local previousPos = initialPositions[key]
                    previousPos = nil
                    if previousPos then
                        local speed = calculateSpeed(previousPos, object.pos, 0.1)
                        print(textutils.serialize(previousPos))
                        print(textutils.serialize(object.pos))
                        print("speed: "..speed)
                        if speed > 5 then  -- Check if speed exceeds threshold
                            local objX, objY, objZ = object.pos[1], object.pos[2], object.pos[3]
                            local missileVector = {x = objX - previousPos[1], y = objY - previousPos[2], z = objZ - previousPos[3]}
                            local toPlayerVector = {x = shipPos.x - objX, y = shipPos.y - objY, z = shipPos.z - objZ}
                            local dotProduct = missileVector.x * toPlayerVector.x + missileVector.y * toPlayerVector.y + missileVector.z * toPlayerVector.z
                            print("Missile with speed > 10 detected")
                            if dotProduct then  -- Missile is moving towards the player
                                print("Missile coming for player")
                                local angle = math.deg(math.atan2(missileVector.z, missileVector.x) - math.atan2(toPlayerVector.z, toPlayerVector.x))
                                local direction = ((angle + 360) % 360) / 30
                                local clockDirection = math.floor(direction + 1)
                                if clockDirection == 0 then clockDirection = 12 end
                                monitor.setCursorPos(0,6)
                                monitor.write("Missile incoming from " .. clockDirection .. " o'clock")
                                if speaker then
                                    speaker.playSound("entity.lightning_bolt.thunder", 1.0)
                                end
                            end
                        end
                    end
                end
            end
        end

        previousPositions = currentPositions
        sleep()  -- Delay before the next round of scanning
    end
end

local function broadCastWaypoint()
    while true do
        modem.transmit(waypointChannel,0,waypoints)
        sleep(1)
    end
end

local function controlsSending()
    while true do
        --modem.transmit(missileControlChannel,missileControlChannel,missileControls)
        sleep()
    end
end

local function missileListBuilding()
    while true do
        if immediateMissileInfo and immediateMissileInfo.id and immediateMissileInfo.type then
            local foundMissile = false

            -- Update the existing missile state instead of adding duplicates
            for _, missileInfo in ipairs(AIMInfoList) do
                if missileInfo.id == immediateMissileInfo.id then
                    missileInfo.launchState = immediateMissileInfo.launchState
                    foundMissile = true
                    break
                end
            end
            for _, missileInfo in ipairs(GBUInfoList) do
                if missileInfo.id == immediateMissileInfo.id then
                    missileInfo.launchState = immediateMissileInfo.launchState
                    foundMissile = true
                    break
                end
            end
            for _, missileInfo in ipairs(thunderBoltInfoList) do
                if missileInfo.id == immediateMissileInfo.id then
                    missileInfo.launchState = immediateMissileInfo.launchState
                    foundMissile = true
                    break
                end
            end

            -- If it's a new missile, add it to the list
            if not foundMissile then
                if immediateMissileInfo.type == "AIM-220" then
                    table.insert(AIMInfoList, immediateMissileInfo)
                elseif immediateMissileInfo.type == "GBU-42" then
                    table.insert(GBUInfoList, immediateMissileInfo)
                elseif immediateMissileInfo.type == "thunderBolt" then
                    table.insert(thunderBoltInfoList, immediateMissileInfo)
                end
            end
        end

        -- Remove missiles that have launched
        for i = #AIMInfoList, 1, -1 do
            if AIMInfoList[i].launchState == true then
                table.remove(AIMInfoList, i)
            end
        end
        for i = #GBUInfoList, 1, -1 do
            if GBUInfoList[i].launchState == true then
                table.remove(GBUInfoList, i)
            end
        end
        for i = #thunderBoltInfoList, 1, -1 do
            if thunderBoltInfoList[i].launchState == true then
                table.remove(thunderBoltInfoList, i)
            end
        end

        -- Count unlaunched missiles
        AIMCount, GBUCount, thunderboltCount = 0, 0, 0
        for _, missileInfo in ipairs(AIMInfoList) do
            if not missileInfo.launchState then
                AIMCount = AIMCount + 1
            end
        end
        for _, missileInfo in ipairs(GBUInfoList) do
            if not missileInfo.launchState then
                GBUCount = GBUCount + 1
            end
        end
        for _, missileInfo in ipairs(thunderBoltInfoList) do
            if not missileInfo.launchState then
                thunderboltCount = thunderboltCount + 1
            end
        end
        sleep()
    end
end

local function printOutput()
    while true do
        if displayState == "radar" or displayState == "targetInfo" then
            --print(textutils.serialize(lockedTarget))
            --print(lockedTarget.lockMode)
            --print("Yaw: "..requiredRelativeYaw.." Pitch: "..requiredRelativePitch)
        end
        sleep()
    end
end

parallel.waitForAny(
    function()
        -- Main loop
        while true do
            if displayState == "radar" then
                monitor.clear()
                monitor.setTextScale(0.5)
                drawRadarDisplay()
                drawControls()
            elseif displayState == "targetInfo" and selectedTarget then
                displayTargetInfo(selectedTarget)
            elseif displayState == "adjustCannon" then
                monitor.clear()
                drawCannonAdjustmentPage()
            end
            sleep(0.1)
             -- Adjust this duration if needed
        end
    end,
    handleTouch,
    modemMessage,
    missileWarning,
    broadCastWaypoint,
    missileListBuilding,
    controlsSending,
    printOutput,
    aimCannonContinuous,
    setPitchYaw,
    externalWaypointHandler
)