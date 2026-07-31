local monitor = peripheral.find("monitor")
local radar = peripheral.find("sp_radar")

if not monitor or not radar or not ship then
    error("Required peripherals are not attached")
end

monitor.setTextScale(0.5)
monitor.clear()
local radarScale = 100
local friendlyID = {289, 232}
local targetPositions = {}
local waypoints = {}
local displayState = "radar" -- Initial display state
local selectedTarget = nil

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
end

local function addWaypoint(x, z, color)
    local newWaypoint = {
        x = x,
        z = z,
        color = color or colors.purple
    }
    table.insert(waypoints, newWaypoint)
end

local function drawWaypointPage()
    local w, h = monitor.getSize()
    monitor.setCursorPos(1, 1)
    monitor.write("Waypoint Page")
    monitor.setCursorPos(1, 3)
    monitor.write("Colors: purple (default),")
    monitor.setCursorPos(1, 4)
    monitor.write("red, yellow, green, blue")
    monitor.setCursorPos(1, h-1)
    monitor.write("Open the computer terminal")
    monitor.setCursorPos(1, h)
    monitor.write("to enter waypoint coordinates.")
    monitor.setCursorPos(1, h+1)
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

    local pos = ship.getWorldspacePosition()
    local results = radar.scanForShips(10000)
    targetPositions = {}
    for _, object in ipairs(results) do
        local x = object.pos.x - pos.x
        local z = object.pos.z - pos.z
        local distance = math.sqrt(x^2 + z^2)
        local objectAngle = math.atan2(x, z)
        local relativeAngle = objectAngle + shipYawRadians - math.pi
        if (relativeAngle < -math.pi) then
            relativeAngle = relativeAngle + 2 * math.pi
        elseif (relativeAngle >= math.pi) then
            relativeAngle = relativeAngle - 2 * math.pi
        end

        local scaledDistance = (distance / radarScale) * radius
        local relX = centerX + (scaledDistance * math.sin(relativeAngle)) * aspectRatio
        local relY = centerY + scaledDistance * math.cos(relativeAngle)

        relX, relY = drawTargetOnCircle(centerX, centerY, radius, relX, relY, aspectRatio)

        if (object.mass > 20000 and distance > 5) then
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
        local relativeAngle = wpAngle + shipYawRadians - math.pi
        if (relativeAngle < -math.pi) then
            relativeAngle = relativeAngle + 2 * math.pi
        elseif (relativeAngle >= math.pi) then
            relativeAngle = relativeAngle - 2 * math.pi
        end

        local scaledDistance = (distance / radarScale) * radius
        local relX = centerX + (scaledDistance * math.sin(relativeAngle)) * aspectRatio
        local relY = centerY + scaledDistance * math.cos(relativeAngle)

        relX, relY = drawTargetOnCircle(centerX, centerY, radius, relX, relY, aspectRatio)

        monitor.setBackgroundColor(waypoint.color)
        monitor.setCursorPos(math.floor(relX + 0.5), math.floor(relY + 0.5))
        monitor.write("W")
        monitor.setBackgroundColor(colors.black)

        table.insert(targetPositions, {x = math.floor(relX + 0.5), y = math.floor(relY + 0.5), data = {type = "waypoint", x = waypoint.x, z = waypoint.z, index = index}})
    end
end

local function displayTargetInfo(target)
    local w, h = monitor.getSize()
    local pos = ship.getWorldspacePosition()

    monitor.clear()
    monitor.setCursorPos(1, h-9)
    monitor.write("Target Info")
    monitor.setCursorPos(1, h-8)
    
    local targetPosX, targetPosY, targetPosZ
    if target.type == "waypoint" then
        monitor.write("Type: Waypoint")
        targetPosX, targetPosY, targetPosZ = target.x, 0, target.z
        monitor.setCursorPos(1, h-7)
        monitor.write("Coordinate: " .. target.x .. ", " .. target.z)
    else
        monitor.write("ID: " .. target.id)
        targetPosX, targetPosY, targetPosZ = target.pos.x, target.pos.y, target.pos.z
        monitor.setCursorPos(1, h-7)
        monitor.write("Mass: " .. target.mass)
        monitor.setCursorPos(1, h-6)
        monitor.write("Velocity: " .. string.format("%.2f, %.2f, %.2f", target.velocity.x, target.velocity.y, target.velocity.z))
        monitor.setCursorPos(1, h-5)
        monitor.write("Position: " .. string.format("%.2f, %.2f, %.2f", target.pos.x, target.pos.y, target.pos.z))
    end

    local distance = math.sqrt((targetPosX - pos.x)^2 + (targetPosZ - pos.z)^2)
    local dx = targetPosX - pos.x
    local dz = targetPosZ - pos.z
    local bearing = (math.deg(math.atan2(dz, dx)) + 360) % 360 - 270
    if bearing < 0 then
        bearing = bearing + 360
    end

    monitor.setCursorPos(1, h-4)
    monitor.write("Distance: " .. string.format("%.2f", distance) .. " meters")
    monitor.setCursorPos(1, h-3)
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
        monitor.setCursorPos(1, h-2)
        monitor.write("Type: " .. hostile .. " " .. type)
    end

    if target.type == "waypoint" then
        monitor.setCursorPos(1, h-1)
        monitor.write("Delete Waypoint")
    end

    monitor.setCursorPos(1, h)
    monitor.write("Back")
end


local function handleTouch()
    local w, h = monitor.getSize()
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        if displayState == "radar" then
            if y == h-1 and x == 8 then
                radarScale = math.max(100, radarScale - 100)
                drawControls()
            elseif y == h-1 and x == 10 then
                radarScale = math.min(10000, radarScale + 100)
                drawControls()
            elseif y == h-1 and x >= w-10 and x <= w then
                displayState = "waypoints"
                monitor.clear()
                drawWaypointPage()
                -- Prompt for waypoint coordinates
                print("Enter waypoint coordinates (x, z, color), color, red,yellow,green,blue:")
                local input = read()
                local x, z, color = input:match("([^,]+),([^,]+),([^,]*)")
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
                if x and z then
                    addWaypoint(tonumber(x), tonumber(z), colorValue)
                end
                displayState = "radar"
                monitor.clear()
                drawControls()
                drawRadarDisplay()
            else
                for _, target in ipairs(targetPositions) do
                    if x == target.x and y == target.y then
                        selectedTarget = target.data
                        displayState = "targetInfo"
                        break
                    end
                end
            end
        elseif displayState == "targetInfo" then
            if y == h and x >= 1 and x <= 4 then
                displayState = "radar"
                monitor.clear()
                drawControls()
                drawRadarDisplay()
            elseif y == h-5 and x >= 1 and x <= 15 then
                -- Ensure the correct waypoint is identified for deletion
                for i, target in ipairs(targetPositions) do
                    if target.data.type == "waypoint" then
                        table.remove(waypoints, target.data.index)
                        break
                    end
                end
                displayState = "radar"
                monitor.clear()
                drawControls()
                drawRadarDisplay()
            end
        end
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
            end
            sleep(0.1)
        end
    end,
    handleTouch
)
