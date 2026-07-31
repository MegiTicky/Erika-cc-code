local monitor = peripheral.find("monitor")
local radar = peripheral.find("sp_radar")
local modem = peripheral.wrap("right")

-- Ensure all required peripherals are connected
if not monitor or not radar or not ship then
    error("Required peripherals are not attached")
end

monitor.setTextScale(0.5)
monitor.clear()

local radarScale = 500
local friendlyID = {289, 232}
local targetPositions = {}
local waypoints = {}
local displayState = "radar" -- Initial display state
local selectedTarget = nil
local lockedTargetId = nil
local lockedWaypoint = nil -- Variable to store the locked waypoint
local projectileSpeed = 320 --m/s

-- Get channel data for cannons
local function getChannelInput(prompt, default)
    print(prompt .. ", default: " .. default)
    local input = io.read()
    if input == "" then
        input = default
    end
    return tonumber(input)
end

local port5inchChannel = getChannelInput("Input the port side cannon data channel", 900)
local starboard5inchChannel = getChannelInput("Input the starboard side cannon data channel", 901)
local bow15inchChannel = getChannelInput("Input the bow cannon data channel", 902)
local stern15inchChannel = getChannelInput("Input the stern cannon data channel", 903)

if modem then
    modem.open(starboard5inchChannel)
    modem.open(port5inchChannel)
    modem.open(bow15inchChannel)
    modem.open(stern15inchChannel)
end

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

    local segmentLength = radarScale / 2
    local scaleText
    if segmentLength >= 1000 then
        scaleText = string.format("%.1f km", segmentLength / 1000)
    else
        scaleText = string.format("%d m", segmentLength)
    end

    monitor.setCursorPos(1, h)
    monitor.write("Segment Length: " .. scaleText)

    -- Add button to navigate to waypoint page
    monitor.setCursorPos(w-10, h-1)
    monitor.write("Waypoints")

    -- Add button to navigate to the cannon adjustment page
    monitor.setCursorPos(w-18, h-1)
    monitor.write("Adjust Cannon")
end

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
    monitor.setCursorPos(1, 1)
    monitor.write("Cannon Pitch and Yaw Adjustment")

    local cannonNames = {
        {name = "Port 5 inch", data = cannonData.port5inch, target = cannonTarget.port5inch},
        {name = "Starboard 5 inch", data = cannonData.starboard5inch, target = cannonTarget.starboard5inch},
        {name = "Bow 15 inch", data = cannonData.bow15inch, target = cannonTarget.bow15inch},
        {name = "Stern 15 inch", data = cannonData.stern15inch, target = cannonTarget.stern15inch}
    }

    local yOffset = 3

    for _, cannon in ipairs(cannonNames) do
        monitor.setCursorPos(1, yOffset)
        monitor.write(cannon.name .. ":")

        monitor.setCursorPos(1, yOffset + 1)
        monitor.write("Current:     pitch: " .. (cannon.data.pitch and string.format("%.2f", cannon.data.pitch) or "N/A"))
        monitor.setCursorPos(26, yOffset + 1)
        monitor.write("yaw: " .. (cannon.data.yaw and string.format("%.2f", cannon.data.yaw) or "N/A"))

        monitor.setCursorPos(1, yOffset + 2)
        monitor.write("Adjustment:  pitch: " .. (cannon.target.pitchAdjust and string.format("%.2f", cannon.target.pitchAdjust) or "N/A"))
        monitor.setCursorPos(26, yOffset + 2)
        monitor.write("yaw: " .. (cannon.target.yawAdjust and string.format("%.2f", cannon.target.yawAdjust) or "N/A"))

        monitor.setCursorPos(1, yOffset + 3)
        monitor.write("[pitch +] [pitch -]")
        monitor.setCursorPos(w - 30, yOffset + 3)
        monitor.write("[yaw +] [yaw -]")

        yOffset = yOffset + 6  -- Move down for the next cannon
    end

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
    local shipYawRadians = math.atan2(-ship.getRotationMatrix()[1][3], ship.getRotationMatrix()[3][3])
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

    local matrix = ship.getRotationMatrix()
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
    monitor.setCursorPos(1, h-12)
    monitor.write("Target Info")
    monitor.setCursorPos(1, h-11)
    
    local targetPosX, targetPosY, targetPosZ
    if target.type == "waypoint" then
        monitor.write("Type: Waypoint")
        targetPosX, targetPosY, targetPosZ = target.x, target.y, target.z
        monitor.setCursorPos(1, h-7)
        monitor.write("Coordinate: " .. target.x .. ", "..target.y..", ".. target.z)
    else
        monitor.write("ID: " .. target.id)
        targetPosX, targetPosY, targetPosZ = target.pos.x, target.pos.y, target.pos.z
        monitor.setCursorPos(1, h-10)
        monitor.write("Mass: " .. target.mass)
        monitor.setCursorPos(1, h-9)
        monitor.write("Velocity: " .. string.format("%.2f, %.2f, %.2f", target.velocity.x, target.velocity.y, target.velocity.z))
        monitor.setCursorPos(1, h-8)
        monitor.write("Position: " .. string.format("%.2f, %.2f, %.2f", target.pos.x, target.pos.y, target.pos.z))
    end

    local distance = math.sqrt((targetPosX - pos.x)^2 + (targetPosZ - pos.z)^2)
    local dx = targetPosX - pos.x
    local dz = targetPosZ - pos.z
    local bearing = (math.deg(math.atan2(dz, dx)) + 360) % 360 - 270
    if bearing < 0 then
        bearing = bearing + 360
    end

    monitor.setCursorPos(1, h-7)
    monitor.write("Distance: " .. string.format("%.2f", distance) .. " meters")
    monitor.setCursorPos(1, h-6)
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
        monitor.setCursorPos(1, h-5)
        monitor.write("Type: " .. hostile .. " " .. type)
    end

    if target.type == "waypoint" then
        monitor.setCursorPos(1, h-5)
        monitor.write("[Lock Waypoint with port gun]")
        monitor.setCursorPos(1, h-4)
        monitor.write("[Lock Waypoint with starboard gun]")
        monitor.setCursorPos(1, h-3)
        monitor.write("[Lock Waypoint with bow gun]")
        monitor.setCursorPos(1, h-2)
        monitor.write("[Lock Waypoint with stern gun]")
    else
        monitor.setCursorPos(1, h-5)
        monitor.write("[Lock Target with port gun]")
        monitor.setCursorPos(1, h-4)
        monitor.write("[Lock Target with starboard gun]")
        monitor.setCursorPos(1, h-3)
        monitor.write("[Lock Target with bow gun]")
        monitor.setCursorPos(1, h-2)
        monitor.write("[Lock Target with stern gun]")
    end
    monitor.setCursorPos(1, h)
    monitor.write("Back")
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
                print("Enter waypoint coordinates (x, y, z, color), color options: red, yellow, green, blue:")
                local input = read()
                local x, y, z, color = input:match("([^,]+),([^,]+),([^,]+),([^,]*)")
                local colorValue = colors.purple
                if color then
                    local colorMap = {
                        purple = colors.purple,
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
                    colorValue = colorMap[color] or colors.purple
                end
                if x and y and z then
                    addWaypoint(tonumber(x), tonumber(y), tonumber(z), colorValue)
                end
                displayState = "radar"
                monitor.clear()
                drawControls()
                drawRadarDisplay()
            elseif y == 1 and x >= w-13 and x <= w then
                displayState = "adjustCannon"
                monitor.clear()
                drawCannonAdjustmentPage()
            elseif y == h-2 and x < 10 then
                cannonTarget.port5inch = { type = nil, side = "port", id = nil, x = nil, y = nil, z = nil, pitchAdjust = 0, yawAdjust = 0 }
                cannonTarget.starboard5inch = { type = nil, side = "starboard", id = nil, x = nil, y = nil, z = nil, pitchAdjust = 0, yawAdjust = 0 }
                cannonTarget.bow15inch = { type = nil, side = "bow", id = nil, x = nil, y = nil, z = nil, pitchAdjust = 0, yawAdjust = 0 }
                cannonTarget.stern15inch = { type = nil, side = "stern", id = nil, x = nil, y = nil, z = nil, pitchAdjust = 0, yawAdjust = 0 }
                targetInfo = {}
                monitor.setCursorPos(1, 1)
                monitor.clear()
                drawRadarDisplay()
                monitor.write("Locking stopped.")
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
            elseif y == h-5 and x >= 1 and x <= 28 then
                -- Lock with port cannon
                if selectedTarget.type == "waypoint" then
                    cannonTarget.port5inch.type = "waypoint"
                    cannonTarget.port5inch.x = selectedTarget.x
                    cannonTarget.port5inch.y = selectedTarget.y
                    cannonTarget.port5inch.z = selectedTarget.z
                    cannonTarget.port5inch.id = nil
                else
                    cannonTarget.port5inch.id = selectedTarget.id
                    cannonTarget.port5inch.type = "target"
                    cannonTarget.port5inch.x = nil
                    cannonTarget.port5inch.y = nil
                    cannonTarget.port5inch.z = nil
                end
                displayState = "radar"
                monitor.clear()
                drawRadarDisplay()
                monitor.setCursorPos(1, 1)
                monitor.write("Target locked: " .. (selectedTarget.type == "waypoint" and "Waypoint" or selectedTarget.id))
            elseif y == h-4 and x >= 1 and x <= 32 then
                -- Lock with starboard cannon
                if selectedTarget.type == "waypoint" then
                    cannonTarget.starboard5inch.type = "waypoint"
                    cannonTarget.starboard5inch.x = selectedTarget.x
                    cannonTarget.starboard5inch.y = selectedTarget.y
                    cannonTarget.starboard5inch.z = selectedTarget.z
                    cannonTarget.starboard5inch.id = nil
                else
                    cannonTarget.starboard5inch.id = selectedTarget.id
                    cannonTarget.starboard5inch.type = "target"
                    cannonTarget.starboard5inch.x = nil
                    cannonTarget.starboard5inch.y = nil
                    cannonTarget.starboard5inch.z = nil
                end
                displayState = "radar"
                monitor.clear()
                drawRadarDisplay()
                monitor.setCursorPos(1, 1)
                monitor.write("Target locked: " .. (selectedTarget.type == "waypoint" and "Waypoint" or selectedTarget.id))
            elseif y == h-3 and x >= 1 and x <= 22 then
                -- Lock with bow cannon
                if selectedTarget.type == "waypoint" then
                    cannonTarget.bow15inch.type = "waypoint"
                    cannonTarget.bow15inch.x = selectedTarget.x
                    cannonTarget.bow15inch.y = selectedTarget.y
                    cannonTarget.bow15inch.z = selectedTarget.z
                    cannonTarget.bow15inch.id = nil
                else
                    cannonTarget.bow15inch.id = selectedTarget.id
                    cannonTarget.bow15inch.type = "target"
                    cannonTarget.bow15inch.x = nil
                    cannonTarget.bow15inch.y = nil
                    cannonTarget.bow15inch.z = nil
                end
                displayState = "radar"
                monitor.clear()
                drawRadarDisplay()
                monitor.setCursorPos(1, 1)
                monitor.write("Target locked: " .. (selectedTarget.type == "waypoint" and "Waypoint" or selectedTarget.id))
            elseif y == h-2 and x >= 1 and x <= 22 then
                -- Lock with stern cannon
                if selectedTarget.type == "waypoint" then
                    cannonTarget.stern15inch.type = "waypoint"
                    cannonTarget.stern15inch.x = selectedTarget.x
                    cannonTarget.stern15inch.y = selectedTarget.y
                    cannonTarget.stern15inch.z = selectedTarget.z
                    cannonTarget.stern15inch.id = nil
                else
                    cannonTarget.stern15inch.id = selectedTarget.id
                    cannonTarget.stern15inch.type = "target"
                    cannonTarget.stern15inch.x = nil
                    cannonTarget.stern15inch.y = nil
                    cannonTarget.stern15inch.z = nil
                end
                displayState = "radar"
                monitor.clear()
                drawRadarDisplay()
                monitor.setCursorPos(1, 1)
                monitor.write("Target locked: " .. (selectedTarget.type == "waypoint" and "Waypoint" or selectedTarget.id))
            end
        elseif displayState == "adjustCannon" then
            -- Back button
            if y == h and x >= 1 and x <= 4 then
                displayState = "radar"
                monitor.clear()
                drawRadarDisplay()
            end
            
            -- Detect pitch and yaw adjustment button presses
            local yOffset = 3
            local buttonWidth = 10
            for i, cannonName in ipairs({"port5inch", "starboard5inch", "bow15inch", "stern15inch"}) do
                if y == yOffset + 3 then
                    if x >= 1 and x <= 10 then
                        -- Increase pitch
                        cannonTarget[cannonName].pitchAdjust = cannonTarget[cannonName].pitchAdjust + 0.1
                    elseif x >= 11 and x <= 20 then
                        -- Decrease pitch
                        cannonTarget[cannonName].pitchAdjust = cannonTarget[cannonName].pitchAdjust - 0.1
                    elseif x >= w - 30 and x <= w - 20 then
                        -- Increase yaw
                        cannonTarget[cannonName].yawAdjust = cannonTarget[cannonName].yawAdjust + 0.1
                    elseif x >= w - 19 and x <= w - 9 then
                        -- Decrease yaw
                        cannonTarget[cannonName].yawAdjust = cannonTarget[cannonName].yawAdjust - 0.1
                    end
                    monitor.clear()
                    drawCannonAdjustmentPage()
                end
                yOffset = yOffset + 6
            end
        end
    end
end

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
            end
        else
            sleep()
        end
    end
end

local function calculateRange(angle, u, cd, g, c_est, projectileSpeed)
    local radians = math.rad(angle)
    local u = projectileSpeed/20
    local part1 = u * math.cos(radians) / math.log(cd)
    local part2 = ((g * cd) / (g * cd + (1 - cd) * u * math.sin(radians))) ^ (2 + c_est * projectileSpeed * math.sin(radians)) - 1
    local XR = part1 * part2

    return XR
end

local function findBestPitch(targetX, targetY, targetZ, sourceX, sourceY, sourceZ, initialVelocity, g, cd, c_est, projectileSpeed)
    local bestLowPitch = nil
    local bestHighPitch = nil
    local bestLowDistance = math.huge
    local bestHighDistance = math.huge
    local targetDistance = math.sqrt((targetX - sourceX)^2 + (targetZ - sourceZ)^2)

    for pitch = 0, 70, 0.01 do -- Iterate over pitch angles
        local calculatedRange = calculateRange(pitch, initialVelocity, cd, g, c_est, projectileSpeed)
        local distanceDifference = math.abs(calculatedRange - targetDistance)

        -- Find the low-angle solution
        if pitch <= 30 then
            if distanceDifference < bestLowDistance then
                bestLowDistance = distanceDifference
                bestLowPitch = pitch
            end
        -- Find the high-angle solution
        elseif pitch > 30 then
            if distanceDifference < bestHighDistance then
                bestHighDistance = distanceDifference
                bestHighPitch = pitch
            end
        end
    end

    -- If the target is within 400 blocks, prioritize the low-angle solution
    if targetDistance <= 830 then
        return bestLowPitch or bestLowPitch
    else
        return bestHighPitch or bestLowPitch
    end
end

local function aimCannon(targetPos, targetVel, side)
    if targetPos and targetVel then
        -- Determine which channel to use based on side
        local channel
        if side == "port" then
            channel = port5inchChannel
        elseif side == "starboard" then
            channel = starboard5inchChannel
        elseif side == "bow" then
            channel = bow15inchChannel
        elseif side == "stern" then
            channel = stern15inchChannel
        end
        targetInfo = {targetPos = targetPos, targetVel = targetVel}
        --yaw adjustment
        if modem and targetInfo and targetInfo.targetPos and targetInfo.targetVel then
            modem.transmit(channel,0,targetInfo)
        elseif modem then
            targetInfo = {targetPos = nil, targetVel = nil}
            modem.transmit(channel,0,targetInfo)
        end
    end
end

local function aimPortCannonContinuous()
    while true do
        local cannon = cannonTarget.port5inch
        if cannon.type then
            local target
            monitor.setCursorPos(1,3)
            if cannon.type=="waypoint" then
                monitor.write("Port waypoint locked: "..cannon.x.." , "..cannon.y.." , "..cannon.z)
            else
                monitor.write("Port ship locked: "..cannon.id)
            end
            if cannon.type == "waypoint" then
                target = {pos = {x = cannon.x, y = cannon.y, z = cannon.z}, velocity = {x = 0, y = 0, z = 0}}
            else  -- handling target
                local scanResults = radar.scanForShips(5000)
                for _, object in ipairs(scanResults) do
                    if object.id == cannon.id then
                        target = object
                        break
                    end
                end
            end

            if target and target.pos then
                aimCannon(target.pos, target.velocity, "port", 330)
            else
                targetInfo = {targetPos = nil, targetVel = nil}
                modem.transmit(port5inchChannel,port5inchChannel,targetInfo)
            end
        else

        end
        sleep()  -- Adjust sleep duration based on required reaction time
    end
end

local function aimStarboardCannonContinuous()
    while true do
        local cannon = cannonTarget.starboard5inch
        if cannon.type then
            local target
            monitor.setCursorPos(1,4)
            if cannon.type=="waypoint" then
                monitor.write("Starboard waypoint locked: "..cannon.x.." , "..cannon.y.." , "..cannon.z)
            else
                monitor.write("Starboard ship locked: "..cannon.id)
            end
            if cannon.type == "waypoint" then
                target = {pos = {x = cannon.x, y = cannon.y, z = cannon.z}, velocity = {x = 0, y = 0, z = 0}}
            else  -- handling target
                local scanResults = radar.scanForShips(5000)
                for _, object in ipairs(scanResults) do
                    if object.id == cannon.id then
                        target = object
                        break
                    end
                end
            end

            if target and target.pos then
                aimCannon(target.pos, target.velocity, cannonData.starboard5inch.source.x, cannonData.starboard5inch.source.y, cannonData.starboard5inch.source.z, cannonData.starboard5inch.pitch, cannonData.starboard5inch.yaw, "starboard", 330)
            end
        else

        end
        sleep()
    end
end

local function aimBowCannonContinuous()
    while true do
        local cannon = cannonTarget.bow15inch
        if frontRouter then
            if cannon.type then
                local target
                monitor.setCursorPos(1,5)
                if cannon.type=="waypoint" then
                    monitor.write("Bow waypoint locked: "..cannon.x.." , "..cannon.y.." , "..cannon.z)
                else
                    monitor.write("Bow ship locked: "..cannon.id)
                end
                if cannon.type == "waypoint" then
                    target = {pos = {x = cannon.x, y = cannon.y, z = cannon.z}, velocity = {x = 0, y = 0, z = 0}}
                else  -- handling target
                    local scanResults = radar.scanForShips(5000)
                    for _, object in ipairs(scanResults) do
                        if object.id == cannon.id then
                            target = object
                            break
                        end
                    end
                end

                if target and target.pos then
                    aimCannon(target.pos, target.velocity, cannonData.bow15inch.source.x, cannonData.bow15inch.source.y, cannonData.bow15inch.source.z, cannonData.bow15inch.pitch, cannonData.bow15inch.yaw, "bow", 280)
                end
            else

            end
        end
        sleep()
    end
end

local function aimSternCannonContinuous()
    while true do
        local cannon = cannonTarget.stern15inch
        if backRouter then
            if cannon.type then
                local target
                monitor.setCursorPos(1,6)
                if cannon.type=="waypoint" then
                    monitor.write("Stern waypoint locked: "..cannon.x.." , "..cannon.y.." , "..cannon.z)
                else
                    monitor.write("Stern ship locked: "..cannon.id)
                end
                if cannon.type == "waypoint" then
                    target = {pos = {x = cannon.x, y = cannon.y, z = cannon.z}, velocity = {x = 0, y = 0, z = 0}}
                else  -- handling target
                    local scanResults = radar.scanForShips(5000)
                    for _, object in ipairs(scanResults) do
                        if object.id == cannon.id then
                            target = object
                            break
                        end
                    end
                end

                if target and target.pos then
                    aimCannon(target.pos, target.velocity, cannonData.stern15inch.source.x, cannonData.stern15inch.source.y, cannonData.stern15inch.source.z, cannonData.stern15inch.pitch, cannonData.stern15inch.yaw, "stern", 280)
                end
            else

            end
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
    aimPortCannonContinuous,
    aimStarboardCannonContinuous,
    includeBowAndStern and aimBowCannonContinuous or function() while true do sleep(1) end end,
    includeBowAndStern and aimSternCannonContinuous or function() while true do sleep(1) end end
)


