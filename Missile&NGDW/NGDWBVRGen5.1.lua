local radar = peripheral.find("sp_radar")
local modem = peripheral.wrap("right")
local speaker = peripheral.find("speaker")
local holo = peripheral.find("hologram")

-- Ensure all required peripherals are connected
if not radar or not ship or not holo then
    error("Required peripherals are not attached")
end


local friendlyID = {289, 232}
local targetPositions = {}
local waypoints = {}
local displayState = "radar" -- Initial display state
local selectedTarget = nil
local selectedTargetType = nil
targetTypeIcon = "None"

local lockedTargetId = nil
local lockedWaypoint = nil -- Variable to store the locked waypoint
local projectileSpeed = 320 --m/s

local LaunchedMissiles = {}
local missileControls = {
    fireMissile = {}
}
local immediateMissileInfo = {}
local AIMInfoList,GBUInfoList,thunderBoltInfoList = {},{},{}
local pendingMissileLaunches = {}
local AIMCount,GBUCount,thunderboltCount = 0,0,0

-- Get channel data for cannons
local function getChannelInput(prompt, default)
    print(prompt .. ", default: " .. default)
    local input = io.read()
    if input == "" then
        input = default
    end
    return tonumber(input)
end

local controlChannel = getChannelInput("Input the control channel",500)
local waypointChannel = getChannelInput("Input the control channel",1421)
local port5inchChannel = getChannelInput("Input the port side cannon data channel", 900)
local starboard5inchChannel = getChannelInput("Input the starboard side cannon data channel", 901)
local bow15inchChannel = getChannelInput("Input the bow cannon data channel", 902)
local stern15inchChannel = getChannelInput("Input the stern cannon data channel", 903)
local missileControlChannel = getChannelInput("Input the missile control channel", 1400)
local missileInfoChannel = missileControlChannel + 10

if modem then
    modem.open(waypointChannel)
    modem.open(controlChannel)
    modem.open(starboard5inchChannel)
    modem.open(port5inchChannel)
    modem.open(bow15inchChannel)
    modem.open(stern15inchChannel)
    modem.open(missileInfoChannel)
    modem.open(missileControlChannel)
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

--================--
--Utility function--
--================--
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

local function calculateSpeed(pos1, pos2, deltaTime)
    if pos1 and pos2 then
        local dx = pos2[1] - pos1[1]
        local dy = pos2[2] - pos1[2]
        local dz = pos2[3] - pos1[3]
        return math.sqrt(dx^2 + dy^2 + dz^2) / deltaTime
    end
    return 0
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
            elseif channel == missileInfoChannel then
                immediateMissileInfo = message
            end
        else
            sleep()
        end
    end
end

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end

--================--
--Waypoints function--
--================--
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

--================--
--Display function--
--================--
-- Configuration
local w, h = 640,640
local centerX, centerY = w / 2, h / 2
local radarGreen = 0x00FF00FF
local backgroundColor = 0x000000BB
local labelBackground = 0x222222BB
local inactiveTargetColor = 0x444444CC
local aspectRatio = 1  -- adjust if needed for elliptical compensation
local radarScale = 500

local colorTable = {
    red     = 0xFF0000FF,
    green   = 0x00FF00FF,
    blue    = 0x0000FFFF,
    yellow  = 0xFFFF00FF,
    purple  = 0x8000FFFF,
    orange  = 0xFFA500FF,
    cyan    = 0x00FFFFFF,
    white   = 0xFFFFFFFF,
    gray    = 0x808080FF,
    pink    = 0xFFC0CBFF,
    lime    = 0xBFFF00FF
}

local colorKeys = {}
for name in pairs(colorTable) do
    table.insert(colorKeys, name)
end


-- Setup screen
holo.Resize(w, h)
holo.SetClearColor(backgroundColor)
holo.Clear()
holo.SetScale(0.022, 0.022)
holo.SetRotation(0, 0, 0)
holo.SetTranslation(0, 0, 0)

local function drawControls()
    local buttonPadding = 4  -- Padding around text

    -- Clear bottom section for controls
    --holo.Fill(0, h - 50, w, 50, backgroundColor)

    -- Helper to draw a "button"
    local function drawButton(x, y, label)
        local textWidth = #label * 8
        local textHeight = 10
        local bgX = x - buttonPadding
        local bgY = y + 2
        local bgW = textWidth + buttonPadding * 2
        local bgH = textHeight + 4

        holo.Fill(bgX, bgY, bgW, bgH, labelBackground)
        holo.Text(x, y, label, radarGreen, 0)
    end

    -- Draw scale adjustment
    drawButton(5, h - 45, "Scale:")
    drawButton(70, h - 45, "-")
    drawButton(95, h - 45, "+")

    -- Stop locking and launch buttons
    drawButton(5, h - 70, "Stop Locking")
    drawButton(5, h - 95, "Launch Missile")

    -- Segment length display
    local segmentLength = radarScale / 2
    local scaleText
    if segmentLength >= 1000 then
        scaleText = string.format("Segment Length: %.1f km", segmentLength / 1000)
    else
        scaleText = string.format("Segment Length: %d m", segmentLength)
    end
    holo.Text(5, h - 20, scaleText, radarGreen, 0)

    -- Waypoints button (bottom-right)
    drawButton(w - 100, h - 45, "Waypoints")

    -- Adjust Cannon button (top-right)
    drawButton(w - 130, 5, "Adjust Cannon")
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

local function drawRadarBackground(radius, shipYawRadians, radarScale)
    local segmentLength = radarScale / 4
    local pixelPerSegmentX = w / 4
    local pixelPerSegmentY = h / 4
    -- Grid lines: vertical
    local x = 0
    while x < w do
        if x ~= centerX then
            for y = 0, h - 1, 5 do
                holo.Fill(x, y, 1, 1, radarGreen)
            end
        end
        x = x + pixelPerSegmentX
    end

    -- Grid lines: horizontal
    local y = 0
    while y < h do
        for x2 = 0, w - 1, 5 do
            holo.Fill(x2, y, 1, 1, radarGreen)
        end
        y = y + pixelPerSegmentY
    end

    -- Circle ring: precompute radian steps
    for i = 0, 360, 10 do
        local rad = math.rad(i)
        local sinVal = math.sin(rad)
        local cosVal = math.cos(rad)
        local px = math.floor(centerX + (radius * sinVal) * aspectRatio)
        local py = math.floor(centerY + radius * cosVal)
        holo.Fill(px, py, 1, 1, radarGreen)
    end

    -- Crosshair vertical
    for y = centerY - radius, centerY + radius, 5 do
        holo.Fill(centerX, y, 1, 1, radarGreen)
    end

    -- Bearing text
    local trueBearing = (math.deg(shipYawRadians) + 360) % 360
    local bearingText = string.format("%03d°", trueBearing)
    local bearingX = centerX - (#bearingText * 4)
    local bearingY = centerY - radius + 30
    holo.Text(bearingX, bearingY, bearingText, radarGreen, 0)

    -- Cardinal directions (precomputed)
    local directions = { "N", "W", "S", "E" }
    local angles = { 0, 90, 180, 270 }
    for i = 1, 4 do
        local rad = math.rad(angles[i] + math.deg(shipYawRadians))
        local px = math.floor(centerX + (radius * math.sin(rad)) * aspectRatio)
        local py = math.floor(centerY + radius * math.cos(rad))
        holo.Text(px, py, directions[i], radarGreen, 0)
    end

    -- Segment label
    --holo.Text(10, h - 40, "Segment: " .. math.floor(segmentLength) .. "m", radarGreen, 0)
end

local function drawTargetOnCircle(cx, cy, r, x, y)
    local dx, dy = (x - cx) / aspectRatio, y - cy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > r then
        local scale = r / dist
        return cx + dx * scale * aspectRatio, cy + dy * scale
    else
        return x, y
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

-- Store last seen object positions and timestamps
local objectHistory = {}

local function isActiveObject(id, pos)
    local now = os.epoch("utc")

    -- Get previous data
    local record = objectHistory[id]
    if record then
        local dx = pos.x - record.x
        local dy = pos.y - record.y
        local dz = pos.z - record.z
        local moved = math.sqrt(dx^2 + dy^2 + dz^2) > 0.5  -- consider >0.5 blocks moved
        local age = now - record.time
        if age <= 30000 and moved then
            return true
        end
    end

    -- Save current position and timestamp
    objectHistory[id] = {x = pos.x, y = pos.y, z = pos.z, time = now}
    return false
end

local function bakeBitmap(bitmap, color)
    local data = {}
    for i = 0, #bitmap - 1 do
        data[i] = bitmap[i + 1] == 1 and color or 0x00000000
    end
    return data
end

local ICONS = {
    ["missile"] = {
        width = 4, height = 14,
        bitmap = {
            0,1,1,0,
            0,1,1,0,
            0,1,1,0,
            1,1,1,1,
            1,1,1,1,
            0,1,1,0,
            0,1,1,0,
            0,1,1,0,
            0,1,1,0,
            0,1,1,0,
            0,1,1,0,
            1,1,1,1,
            1,1,1,1,
            0,1,1,0,
        }
    },
    ["plane"] = {
        width = 15, height = 15,
        bitmap = {
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,
            0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,
            0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,
            0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,
            0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,
            0,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
            1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
            1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
            0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,
            0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,
            0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,
            0,0,0,0,1,1,1,0,1,1,1,0,0,0,0,           
            0,0,0,0,1,1,0,0,0,1,1,0,0,0,0
        }
    },
    ["tank"] = {
        width = 11, height = 16,
        bitmap = {
            0,0,0,0,0,1,0,0,0,0,0,
            0,0,0,0,0,1,0,0,0,0,0,
            1,1,0,0,0,1,0,0,0,1,1,
            1,1,0,0,0,1,0,0,0,1,1,
            1,1,0,0,0,1,0,0,0,1,1,
            1,1,0,1,1,1,1,1,0,1,1,
            1,1,0,1,1,1,1,1,0,1,1,
            1,1,0,1,1,1,1,1,0,1,1,
            1,1,0,1,1,1,1,1,0,1,1,
            1,1,0,1,1,1,1,1,0,1,1,
            1,1,0,1,1,1,1,1,0,1,1,
            1,1,0,1,1,1,1,1,0,1,1,
            1,1,0,1,1,1,1,1,0,1,1,
            1,1,0,0,0,0,0,0,0,1,1,
            1,1,1,1,1,1,1,1,1,1,1,
            1,1,1,1,1,1,1,1,1,1,1,
        }
    },
    ["ship"] = {
        width = 15, height = 15,
        bitmap = {
            0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,
            0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,
            0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,
            0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,
            0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,
            0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,
            0,0,1,1,1,1,1,1,1,1,1,1,1,0,0,
            0,0,1,0,0,0,0,0,0,0,0,0,1,0,0,
            0,0,1,0,0,0,0,0,0,0,0,0,1,0,0,
            0,0,1,1,0,0,0,0,0,0,0,1,1,0,0,
            0,0,0,1,1,0,0,0,0,0,1,1,0,0,0,
            0,0,0,0,1,1,0,0,0,1,1,0,0,0,0,
            1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        }
    },
    ["default"] = {
        width = 5, height = 5,
        bitmap = {
            0,0,1,0,0,
            0,1,1,1,0,
            1,1,1,1,1,
            0,1,1,1,0,
        }
    },
    ["waypoint"] ={
        width = 7, height = 7,
        bitmap = {
            1,1,1,1,1,1,1,
            1,1,0,0,0,1,1,
            1,1,0,0,0,1,1,
            1,1,0,0,0,1,1,
            0,1,1,0,1,1,0,
            0,0,1,1,1,0,0,
            0,0,0,1,0,0,0,
        }
    },
    ["entity"] ={
        width = 3, height = 3,
        bitmap = {
            0, 1, 0,
            1, 1, 1,
            0, 1, 0,
        } 
    }
}

local function blitIcon(x, y, icon, color)
    local iconData = ICONS[icon] or ICONS["default"]
    local pixels = bakeBitmap(iconData.bitmap, color)
    holo.Blit(math.floor(x - iconData.width / 2), math.floor(y - iconData.height / 2),
              iconData.width, iconData.height, pixels, 1)
end

local function getTargetIcon(object)
    if not object.size or not object.scale then return "default" end

    -- Scale the dimensions
    local sx = (object.size.x or 0) --/ object.scale.x
    local sy = (object.size.y or 0) --/ object.scale.y
    local sz = (object.size.z or 0) --/ object.scale.z

    -- Volume calculation
    if object.volume == 0 then return "default" end  -- Avoid division by zero

    -- Density calculation
    local density = object.mass / object.volume
    object._calculatedDensity = density  -- Optional: store for debugging or later use

    -- Icon classification based on size and mass (can now be extended to use density)
    local sizeSum = sx + sy + sz
    if object.scale.x < 0.6 and object.mass > 5000 and object.mass < 20000 and object.numShips < 2 then
        return "missile"
    elseif sizeSum < 50 and object.mass < 200000 then
        if density > 100 then
            return "tank"
        elseif density > 50 then
            return "default"
        else
            return "plane"
        end
    elseif sizeSum < 50 and object.mass >= 200000 then
        return "tank"
    elseif sizeSum > 100 and object.mass > 500000 then
        return "ship"
    end

    return "default"
end

local function clusterShips(ships)
    local clusters = {}
    shipPosX = ship.getWorldspacePosition()
    for _, ship in ipairs(ships) do
        local added = false
        --print(distance(ship.pos, shipPosX))
        for _, cluster in ipairs(clusters) do
            for _, other in ipairs(cluster.members) do
                if distance(ship.pos, other.pos) < 10 then
                    table.insert(cluster.members, ship)

                    -- Update main if more massive
                    if (ship.mass or 0) > (cluster.main.mass or 0) and ship.scale.x == 1 then
                        cluster.main = ship
                    end

                    -- Update total mass and volume
                    cluster.massSum = cluster.massSum + (ship.mass or 0)
                    local sx = (ship.size and ship.size.x or 0)
                    local sy = (ship.size and ship.size.y or 0)
                    local sz = (ship.size and ship.size.z or 0)
                    cluster.volumeSum = cluster.volumeSum + (sx * sy * sz)

                    added = true
                    break
                end
            end
            if added then break end
        end

        if not added then
            local sx = (ship.size and ship.size.x or 0)
            local sy = (ship.size and ship.size.y or 0)
            local sz = (ship.size and ship.size.z or 0)
            local volume = sx * sy * sz

            -- New cluster with one ship
            table.insert(clusters, {
                members = { ship },
                main = ship,
                massSum = ship.mass or 0,
                volumeSum = volume,
            })
        end
    end

    -- Return only main ship data, now including the number of ships in each cluster
    local result = {}
    for _, cluster in ipairs(clusters) do
        local main = cluster.main
        local numShips = #cluster.members  -- Total number of ships in the cluster

        table.insert(result, {
            pos = main.pos,
            id = main.id,
            mass = main.mass,
            volume = cluster.volumeSum,
            numShips = numShips,  -- Add the number of ships in this cluster
            velocity = main.velocity,
            scale = main.scale,
            size = main.size,
            type = "ship",
            color = radarGreen,
        })
    end

    return result
end

local function drawBox(x, y, size, color)
    holo.DrawLine(x - size, y - size, x + size, y - size, color,0)
    holo.DrawLine(x + size, y - size, x + size, y + size, color,0)
    holo.DrawLine(x + size, y + size, x - size, y + size, color,0)
    holo.DrawLine(x - size, y + size, x - size, y - size, color,0)
end

local function drawShips(clusters, allEntities, pos, shipYawRadians, radarScale, radius, centerX, centerY)
    for _, object in ipairs(clusters) do
        local x = object.pos.x - pos.x
        local z = object.pos.z - pos.z
        local distance = math.sqrt(x^2 + z^2)
        local objectAngle = math.atan2(x, z)
        local relativeAngle = calculateRelativeAngle(objectAngle, shipYawRadians)

        local scaledDistance = (distance / radarScale) * radius
        local relX = centerX + (scaledDistance * math.sin(relativeAngle))
        local relY = centerY + scaledDistance * math.cos(relativeAngle)

        relX, relY = drawTargetOnCircle(centerX, centerY, radius, relX, relY)

        if object.mass > 900 and distance > 5 then
            local isActive = isActiveObject(object.id, object.pos)

            -- Check for nearby wheel entities to refine tank detection
            local wheelCount = 0
            for _, entity in ipairs(allEntities) do
                if entity.entity_type == "entity.trackwork.wheel_entity" then
                    local dx = entity.pos[1] - object.pos.x
                    local dy = entity.pos[2] - object.pos.y
                    local dz = entity.pos[3] - object.pos.z
                    if (dx * dx + dy * dy + dz * dz) <= 100 then  -- within 10 blocks
                        wheelCount = wheelCount + 1
                        if wheelCount >= 4 then break end
                    end
                end
            end

            -- Set color based on various conditions
            local color = 0xFFFF0080
            if checkFriendly(object.id) then
                color = isActive and 0x4444FFFF or 0x4444FFAA
            elseif object.mass > 1000000 then
                color = isActive and 0xFFA500FF or inactiveTargetColor
            elseif math.sqrt(object.velocity.x^2 + object.velocity.y^2 + object.velocity.z^2) > 30 then
                color = isActive and 0xFF0000FF or inactiveTargetColor
            else
                color = isActive and 0xFFFF00FF or inactiveTargetColor
            end

            -- Determine icon
            local icon = wheelCount >= 4 and "tank" or getTargetIcon(object)

            -- Draw icon
            blitIcon(relX, relY, icon, color)

            -- Vertical arrow indicator
            local dy = object.pos.y - pos.y
            if dy >= 15 then
                holo.Text(math.floor(relX - 4), math.floor(relY) - 12, "^", color, 0)
            elseif dy <= -15 then
                holo.Text(math.floor(relX - 4), math.floor(relY) + 8, "v", color, 0)
            end

            -- Draw velocity arrow
            local vx, vz = object.velocity.x or 0, object.velocity.z or 0
            local vMag = math.sqrt(vx^2 + vz^2)
            if vMag > 1 then
                local vAngle = math.atan2(vx, vz)
                local vRelAngle = calculateRelativeAngle(vAngle, shipYawRadians)

                local arrowLength = math.min(100, vMag * 10)
                local arrowX = relX + arrowLength * math.sin(vRelAngle)
                local arrowY = relY + arrowLength * math.cos(vRelAngle)

                holo.DrawLine(math.floor(relX), math.floor(relY), math.floor(arrowX), math.floor(arrowY), color)
            end

            -- Add to target positions
            table.insert(targetPositions, {
                x = math.floor(relX),
                y = math.floor(relY),
                data = object,
                type = "ship",
                targetIcon = icon
            })
        end
    end
end

local function drawWaypoints(waypoints, pos, shipYawRadians, radarScale, radius, centerX, centerY)
    for index, waypoint in ipairs(waypoints) do
        local wpX = waypoint.x - pos.x
        local wpZ = waypoint.z - pos.z
        local distance = math.sqrt(wpX^2 + wpZ^2)
        local wpAngle = math.atan2(wpX, wpZ)
        local relativeAngle = calculateRelativeAngle(wpAngle, shipYawRadians)

        local scaledDistance = (distance / radarScale) * radius
        local relX = centerX + (scaledDistance * math.sin(relativeAngle))
        local relY = centerY + scaledDistance * math.cos(relativeAngle)

        relX, relY = drawTargetOnCircle(centerX, centerY, radius, relX, relY)

        local wpColor = waypoint.color or 0xFFFF00FF
        blitIcon(math.floor(relX), math.floor(relY), "waypoint", wpColor)

        table.insert(targetPositions, {
            x = math.floor(relX),
            y = math.floor(relY),
            data = waypoint,
            type = "waypoint"
        })
    end
end

local function isValidMod(entity)
    -- List of valid mods to filter entities by mod name
    local validMods = { "tallyho", "createbigcannons", "cbcmodernwarfare", "cbcmoreshells" }

    -- Check if the entity's type contains any of the valid mod names
    for _, mod in ipairs(validMods) do
        if string.find(entity.entity_type, mod) then
            return true
        end
    end
    return false
end

local function drawEntity(objectList, shipPos, shipYawRadians, radarScale, radius, centerX, centerY)
    -- Iterate through the list of entities detected
    for _, object in ipairs(objectList) do
        if object and isValidMod(object) then
            if object.pos then
                -- Calculate the relative position and distance of the object from the ship
                object.pos = {x=object.pos[1], y=object.pos[2], z=object.pos[3]}
                local x = object.pos.x - shipPos.x
                local z = object.pos.z - shipPos.z
                local distance = math.sqrt(x^2 + z^2)  -- Calculate the distance from the ship to the entity
                local objectAngle = math.atan2(x, z)  -- Calculate the angle of the object relative to the ship
                local relativeAngle = calculateRelativeAngle(objectAngle, shipYawRadians)  -- Calculate relative angle

                -- Scale the distance for radar display
                local scaledDistance = (distance / radarScale) * radius
                local relX = centerX + (scaledDistance * math.sin(relativeAngle))
                local relY = centerY + scaledDistance * math.cos(relativeAngle)

                -- Set color based on the status and type of the object
                local color = 0xFF800080  -- Example color

                -- Determine the target icon based on the type of object
                local icon = "entity"  -- You can refine this based on object.entity_type

                -- Draw the icon for the object (missile, rocket, etc.)
                blitIcon(relX, relY, icon, color)

                -- Add this entity's information to the target positions table
                table.insert(targetPositions, {
                    x = math.floor(relX),
                    y = math.floor(relY),
                    data = object,
                    type = "entity",  -- Mark as an entity (missile or rocket)
                    targetIcon = icon
                })
            end
        end
    end
end

local function drawRadarDisplay() 
    local centerX, centerY = math.floor(w / 2), math.floor(h / 2)
    local radius = math.min(centerX, centerY) - 1

    local matrix = ship.getTransformationMatrix()
    local shipYawRadians = math.atan2(-matrix[1][3], matrix[3][3]) 
    if shipYawRadians < 0 then
        shipYawRadians = shipYawRadians + 2 * math.pi
    end

    local pos, rawShips, clusters, allEntities
    parallel.waitForAll(
        function()
            pos = ship.getWorldspacePosition()
            rawShips = radar.scanForShips(20000)
            clusters = clusterShips(rawShips)
        end,
        function()
            allEntities = radar.scanForEntities(2000)
        end,
        function()
            drawRadarBackground(radius, shipYawRadians, radarScale)
        end
    )

    targetPositions = {}

    parallel.waitForAll(
        function()
            -- Call the helper function for drawing entities
            drawEntity(allEntities, pos, shipYawRadians, radarScale, radius, centerX, centerY)
        end,
        function()
            -- Call the helper function for drawing ships
            drawShips(clusters, allEntities, pos, shipYawRadians, radarScale, radius, centerX, centerY)
        end,
        function()
            -- Call the helper function for drawing waypoints
            drawWaypoints(waypoints, pos, shipYawRadians, radarScale, radius, centerX, centerY)
        end
    )
end


function drawWaypointPage()
    local white = 0xFFFFFFFF
    local background = 0x000000FF
    local gray = 0x404040FF
    local titleY = 50
    local instructionY = 100
    local inputY = 300

    holo.Clear()
    holo.SetClearColor(background)

    -- Instruction Text
    holo.Text(10, titleY, "Waypoint Page", white, 0)
    holo.Text(10, instructionY, "Enter coordinates (x, y, z, color):", white, 0)
    holo.Text(10, instructionY + 20, "Format: x,y,z,color", white, 0)
    holo.Text(10, instructionY + 40, "Colors: red, yellow, green, blue, purple", white, 0)
    holo.Text(10, instructionY + 60, "Press Enter to submit. Backspace to edit.", white, 0)
    holo.Flush()
    local inputStr = ""

    local numPadMap = {
        [320] = "0", [321] = "1", [322] = "2", [323] = "3",
        [324] = "4", [325] = "5", [326] = "6",
        [327] = "7", [328] = "8", [329] = "9",
        [330] = ".", [331] = "-", [334] = "+"
    }

    local function drawInput()
        holo.Fill(10, 300, 1000, 20, 0x000000FF)
        holo.Text(10, 300, inputStr .. "_", 0xFFFFFFFF, 0)
        holo.Flush()
    end

    drawInput()

    while true do
        local event, screenName, keyCode = os.pullEvent("vp_key_pressed")
        if screenName ~= holo.GetName() then goto continue end

        local keyName = keys.getName and keys.getName(keyCode) or nil

        if keyName == "enter" then
            local x, y, z, color = inputStr:match("^%s*([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)%s*,?%s*([^,]*)%s*$")
            
            if x and y and z then
                local colorKey = string.lower(color or "")
                local colorCode = colorTable[colorKey]
                
                if not color or color == "" or not colorCode then
                    local randKey = colorKeys[math.random(1, #colorKeys)]
                    colorCode = colorTable[randKey]
                    print("Assigning random color: " .. tostring(colorCode))
                end

                addWaypoint(tonumber(x), tonumber(y), tonumber(z), colorCode)
            else
                print("Invalid format. Expected: x,y,z[,color]")
            end

            displayState = "radar"
            drawControls()
            drawRadarDisplay()
            break
        elseif keyName == "backspace" then
            inputStr = inputStr:sub(1, -2)
            drawInput()

        elseif keyCode >= 32 and keyCode <= 126 then
            inputStr = inputStr .. string.char(keyCode)
            drawInput()

        elseif numPadMap[keyCode] then
            inputStr = inputStr .. numPadMap[keyCode]
            drawInput()
        end
        ::continue::
    end
end

targetInfoButtons = {}

-- Utility function used in onClick for gun locking
function lockCannon(key, target)
    if target.type == "waypoint" then
        cannonTarget[key] = {
            type = "waypoint",
            x = target.x, y = target.y, z = target.z, id = nil
        }
    else
        cannonTarget[key] = {
            type = "target",
            id = target.id, x = nil, y = nil, z = nil
        }
    end
    displayState = "radar"
    drawRadarDisplay()
end

function displayTargetInfo(target, iconType)
    local padding = 4
    local offsetY = -150
    local pos = ship.getWorldspacePosition()

    holo.Clear()
    targetInfoButtons = {}

    local y = h - 250 + offsetY
    local x = 10
    local lines = {}

    table.insert(lines, "Target Info")

    local targetPosX, targetPosY, targetPosZ
    if target.type == "waypoint" then
        table.insert(lines, "Type: Waypoint")
        targetPosX, targetPosY, targetPosZ = target.x, target.y, target.z
        table.insert(lines, "Coordinate: " .. target.x .. ", " .. target.y .. ", " .. target.z)
    elseif target.type == "entity" then
        return
    else
        table.insert(lines, "ID: " .. target.id)
        targetPosX, targetPosY, targetPosZ = target.pos.x, target.pos.y, target.pos.z
        table.insert(lines, "Mass: " .. target.mass)

        -- Compute volume & density
        local sx = (target.size and target.size.x or 0) * (target.scale and target.scale.x or 1)
        local sy = (target.size and target.size.y or 0) * (target.scale and target.scale.y or 1)
        local sz = (target.size and target.size.z or 0) * (target.scale and target.scale.z or 1)
        local volume = sx * sy * sz
        local density = volume > 0 and (target.mass or 0) / volume or 0

        table.insert(lines, string.format("Velocity: %.2f, %.2f, %.2f", target.velocity.x, target.velocity.y, target.velocity.z))
        table.insert(lines, string.format("Position: %.2f, %.2f, %.2f", target.pos.x, target.pos.y, target.pos.z))
        table.insert(lines, string.format("Size: %.2f × %.2f × %.2f", sx, sy, sz))
        table.insert(lines, string.format("Density: %.2f", density))
    end

    local dx = targetPosX - pos.x
    local dz = targetPosZ - pos.z
    local distance = math.sqrt(dx ^ 2 + dz ^ 2)
    local bearing = (math.deg(math.atan2(dz, dx)) + 360) % 360 - 270
    if bearing < 0 then bearing = bearing + 360 end

    table.insert(lines, string.format("Distance: %.2f meters", distance))
    table.insert(lines, string.format("Bearing: %.2f°", bearing))
    table.insert(lines, "Target type: " .. tostring(iconType))

    -- Draw info
    for _, text in ipairs(lines) do
        holo.Text(x, y, text, radarGreen, 0)
        y = y + 20
    end
    sleep(0.1)
    -- Button helper
    local function makeButton(label, x, y, onClick)
        local w = #label * 8 + padding * 2
        local h = 16
        table.insert(targetInfoButtons, {
            label = label, x = x, y = y, w = w, h = h, onClick = onClick
        })
        holo.Fill(x - padding, y + 2, w, h, 0x222222BB)
        holo.Text(x, y, label, radarGreen, 0)
    end

    -- Gun buttons
    local gunX, gunY = 10, y + 10
    makeButton("Port gun", gunX, gunY, function() lockCannon("port5inch", target) end)
    makeButton("Starboard gun", gunX, gunY + 24, function() lockCannon("starboard5inch", target) end)
    makeButton("Bow gun", gunX, gunY + 48, function() lockCannon("bow15inch", target) end)
    makeButton("Stern gun", gunX, gunY + 72, function() lockCannon("stern15inch", target) end)

    -- Missile buttons
    local missileX, missileY = 300, gunY
    makeButton("AIM-220 (Available: " .. AIMCount .. ")", missileX, missileY, function()
        table.insert(pendingMissileLaunches, { type = "AIM-220", target = target })
        displayState = "radar"
        drawRadarDisplay()
    end)
    makeButton("GBU-42 (Available: " .. GBUCount .. ")", missileX, missileY + 24, function()
        table.insert(pendingMissileLaunches, { type = "GBU-42", target = target })
        displayState = "radar"
        drawRadarDisplay()
    end)
    makeButton("Thunderbolt (Available: " .. thunderboltCount .. ")", missileX, missileY + 48, function()
        table.insert(pendingMissileLaunches, { type = "thunderBolt", target = target })
        displayState = "radar"
        drawRadarDisplay()
    end)

    -- Friend Marking Buttons
    local friendX, friendY = 10, missileY + 100

    makeButton("Mark as Friendly", friendX, friendY, function()
        if target.id then
            local alreadyExists = false
            for _, id in ipairs(friendlyID) do
                if id == target.id then
                    alreadyExists = true
                    break
                end
            end
            if not alreadyExists then
                table.insert(friendlyID, target.id)
                displayState = "radar"
                drawRadarDisplay()
            end
        end
    end)

    makeButton("Unmark Friendly", friendX, friendY + 24, function()
        if target.id then
            for i = #friendlyID, 1, -1 do
                if friendlyID[i] == target.id then
                    table.remove(friendlyID, i)
                    displayState = "radar"
                    drawRadarDisplay()
                    break
                end
            end
        end
    end)

    -- Back button
    makeButton("Back", 10, h - 30, function()
        displayState = "radar"
        drawRadarDisplay()
    end)

    holo.Flush()
end

--===================--
--Aim cannon function--
--===================--

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
        print("channel: "..channel)
        print(textutils.serialize(targetInfo))
        --yaw adjustment
        if modem and targetInfo and targetInfo.targetPos and targetInfo.targetVel then
            modem.transmit(channel,0,targetInfo)
        end
    end
end

local function aimPortCannonContinuous()
    while true do
        local cannon = cannonTarget.port5inch
        if cannon.type then
            local target
            --monitor.setCursorPos(1,1)
            if cannon.type=="waypoint" then
                --monitor.write("Port waypoint locked: "..cannon.x.." , "..cannon.y.." , "..cannon.z)
            else
                --monitor.write("Port ship locked: "..cannon.id)
            end
            if cannon.type == "waypoint" then
                target = {pos = {x = cannon.x, y = cannon.y, z = cannon.z}, velocity = {x = 0, y = 0, z = 0}}
            else  -- handling target
                local scanResults = radar.scanForShips(9999)
                for _, object in ipairs(scanResults) do
                    if object.id == cannon.id then
                        target = object
                        break
                    end
                end
            end

            if target and target.pos then
                aimCannon(target.pos, target.velocity, "port")
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
            --monitor.setCursorPos(1,2)
            if cannon.type=="waypoint" then
                --monitor.write("Starboard waypoint locked: "..cannon.x.." , "..cannon.y.." , "..cannon.z)
            else
                --monitor.write("Starboard ship locked: "..cannon.id)
            end
            if cannon.type == "waypoint" then
                target = {pos = {x = cannon.x, y = cannon.y, z = cannon.z}, velocity = {x = 0, y = 0, z = 0}}
            else  -- handling target
                local scanResults = radar.scanForShips(9999)
                for _, object in ipairs(scanResults) do
                    if object.id == cannon.id then
                        target = object
                        break
                    end
                end
            end

            if target and target.pos then
                aimCannon(target.pos, target.velocity, "starboard")
            end
        end
        sleep()
    end
end

local function aimBowCannonContinuous()
    while true do
        local cannon = cannonTarget.bow15inch
        if cannon.type then
            local target
            --monitor.setCursorPos(1,3)
            if cannon.type=="waypoint" then
                --monitor.write("Bow waypoint locked: "..cannon.x.." , "..cannon.y.." , "..cannon.z)
            else
                --monitor.write("Bow ship locked: "..cannon.id)
            end
            if cannon.type == "waypoint" then
                target = {pos = {x = cannon.x, y = cannon.y, z = cannon.z}, velocity = {x = 0, y = 0, z = 0}}
            else  -- handling target
                local scanResults = radar.scanForShips(9999)
                for _, object in ipairs(scanResults) do
                    if object.id == cannon.id then
                        target = object
                        break
                    end
                end
            end

            if target and target.pos then
                aimCannon(target.pos, target.velocity, "bow")
            end
        end
        sleep()
    end
end

local function aimSternCannonContinuous()
    while true do
        local cannon = cannonTarget.stern15inch
        if cannon.type then
            local target
            --monitor.setCursorPos(1,4)
            if cannon.type=="waypoint" then
                --monitor.write("Stern waypoint locked: "..cannon.x.." , "..cannon.y.." , "..cannon.z)
            else
                --monitor.write("Stern ship locked: "..cannon.id)
            end
            if cannon.type == "waypoint" then
                target = {pos = {x = cannon.x, y = cannon.y, z = cannon.z}, velocity = {x = 0, y = 0, z = 0}}
            else  -- handling target
                local scanResults = radar.scanForShips(9999)
                for _, object in ipairs(scanResults) do
                    if object.id == cannon.id then
                        target = object
                        break
                    end
                end
            end

            if target and target.pos then
                aimCannon(target.pos, target.velocity,"stern")
            end
        end
        sleep()
    end
end

--=================--
--Missiles function--
--=================--
local function isMissileLaunchedById(id)
    for _, launched in ipairs(LaunchedMissiles) do
        if launched.id == id then
            return true
        end
    end
    return false
end


missileLaunchOffset = {x=0,y=30,z=0}
maxLaunchOffsetDistance = 5
local function launchMissile(targetType, targetId, targetPos, missileType)
    local currentMissile = nil

    -- Function to find and remove the first unlaunched missile from a list
    local function findUnlaunchedMissile(missileList)
        for i = #missileList, 1, -1 do  -- Iterate in reverse to avoid index shifting issues
            local missile = missileList[i]
            if missile.launchState == false then
                -- Check if this missile is already in LaunchedMissiles
                print(textutils.serialize(LaunchedMissiles))
                print(textutils.serialize(missile))

                if not isMissileLaunchedById(missile.id) then
                    missile.launchState = true  -- Mark missile as launched
                    table.insert(LaunchedMissiles, missile)  -- Move to launched list
                    return table.remove(missileList, i)  -- Remove from available list and return it
                end
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
    print("Teleporting and launching missile " .. currentMissileId)

    -- Assign the missile as launched and set target info
    if targetType == "ship" then
        missileControls.fireMissile[currentMissileId] = {launch = true, type = targetType, id = targetId}
    else
        missileControls.fireMissile[currentMissileId] = {launch = true, type = targetType, pos = targetPos}
    end

    -- Base launch position
    local shipPos = ship.getWorldspacePosition()
    local baseX = shipPos.x + missileLaunchOffset.x
    local baseY = shipPos.y + missileLaunchOffset.y
    local baseZ = shipPos.z + missileLaunchOffset.z

    -- Randomize launch offset within a circle (XZ-plane)
    local angle = math.random() * 2 * math.pi
    local distance = math.random() * maxLaunchOffsetDistance
    local offsetX = math.cos(angle) * distance
    local offsetZ = math.sin(angle) * distance
    local offsetY = math.random(-1, 1)  -- Optional small vertical variation

    local tx = baseX + offsetX
    local ty = baseY + offsetY
    local tz = baseZ + offsetZ

    -- Aim calculation
    local dx = targetPos.x - tx
    local dy = targetPos.y - ty
    local dz = targetPos.z - tz

    local horizontalDistance = math.sqrt(dx * dx + dz * dz)
    local pitch = math.deg(math.atan2(dy, horizontalDistance))
    local yaw = math.deg(math.atan2(dx, dz))

    local teleportMessage = string.format(
        "vs teleport %s %.2f %.2f %.2f (%.2f %.2f 0)",
        currentMissile.slug, tx, ty, tz, -pitch, yaw
    )

    --print(teleportMessage)
    print(commands.exec(teleportMessage))
    commands.exec("/vs set-static "..currentMissile.slug.." false")
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
        modem.transmit(missileControlChannel,missileControlChannel,missileControls)
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
                --Add to friendly id list
                local alreadyExists = false
                for _, id in ipairs(friendlyID) do
                    if id == immediateMissileInfo.id then
                        alreadyExists = true
                        break
                    end
                end
                if not alreadyExists then
                    table.insert(friendlyID, immediateMissileInfo.id)
                end
            end
        end

        -- Remove missiles that have launched or are known by ID to have launched
        for i = #AIMInfoList, 1, -1 do
            local m = AIMInfoList[i]
            if m.launchState == true or isMissileLaunchedById(m.id) then
                table.remove(AIMInfoList, i)
            end
        end

        for i = #GBUInfoList, 1, -1 do
            local m = GBUInfoList[i]
            if m.launchState == true or isMissileLaunchedById(m.id) then
                table.remove(GBUInfoList, i)
            end
        end

        for i = #thunderBoltInfoList, 1, -1 do
            local m = thunderBoltInfoList[i]
            if m.launchState == true or isMissileLaunchedById(m.id) then
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

--==============--
--Touch handling--
--==============--
radarDisplayButtons = {
    {
        label = "Scale:",
        x = 5, y = h - 45,
        w = 50, h = 16,
        onClick = function() end  -- Label only, no action
    },
    {
        label = "-",
        x = 70, y = h - 45,
        w = 20, h = 16,
        onClick = function()
            radarScale = math.max(100, radarScale - 100)
            drawControls()
            drawRadarDisplay()
        end
    },
    {
        label = "+",
        x = 95, y = h - 45,
        w = 20, h = 16,
        onClick = function()
            radarScale = math.min(10000, radarScale + 100)
            drawControls()
            drawRadarDisplay()
        end
    },
    {
        label = "Stop Locking",
        x = 5, y = h - 70,
        w = 110, h = 16,
        onClick = function()
            for _, key in pairs({"port5inch", "starboard5inch", "bow15inch", "stern15inch"}) do
                cannonTarget[key] = { type = nil, side = key, id = nil, x = nil, y = nil, z = nil, pitchAdjust = 0, yawAdjust = 0 }
            end
            pendingMissileLaunches = {}
            drawRadarDisplay()
        end
    },
    {
        label = "Launch Missile",
        x = 5, y = h - 95,
        w = 130, h = 16,
        onClick = function()
            for _, entry in ipairs(pendingMissileLaunches) do
                local target = entry.target
                if target.type == "waypoint" then
                    launchMissile("waypoint", nil, target, entry.type)
                else
                    launchMissile("ship", target.id, target.pos, entry.type)
                end
                modem.transmit(missileControlChannel, missileControlChannel, missileControls)
                sleep(0.5)
            end
            pendingMissileLaunches = {}
            drawRadarDisplay()
        end
    },
    {
        label = "Waypoints",
        x = w - 100, y = h - 45,
        w = 90, h = 16,
        onClick = function()
            displayState = "waypoints"
            drawWaypointPage()
        end
    },
    --[[{
        label = "Adjust Cannon",
        x = w - 130, y = 5,
        w = 120, h = 16,
        onClick = function()
            displayState = "adjustCannon"
            drawCannonAdjustmentPage()
        end
    }]]
}

local function drawRadarDisplayControls()
    local gray = 0x808080FF
    local white = 0xFFFFFFFF
    local buttonPadding = 4

    holo.Fill(0, h - 100, w, 100, backgroundColor)

    for _, btn in ipairs(radarDisplayButtons) do
        local bgX = btn.x - buttonPadding
        local bgY = btn.y + 2
        local bgW = btn.w
        local bgH = btn.h
        holo.Fill(bgX, bgY, bgW, bgH, gray)
        holo.Text(btn.x, btn.y, btn.label, white, 0)
    end

    local segmentLength = radarScale / 2
    local scaleText
    if segmentLength >= 1000 then
        scaleText = string.format("Segment Length: %.1f km", segmentLength / 1000)
    else
        scaleText = string.format("Segment Length: %d m", segmentLength)
    end
    holo.Text(5, h - 20, scaleText, white, 0)
end

local function handleHologramClick()
    while true do
        local event, screenName, button, x, y = os.pullEvent("vp_mouse_clicked")

        x, y = math.floor(x), math.floor(y)

        if displayState == "radar" then
            for _, btn in ipairs(radarDisplayButtons) do
                local bx, by, bw, bh = btn.x, btn.y, btn.w, btn.h
                if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
                    if btn.onClick then btn.onClick() end
                    break
                end
            end

            -- Check target clicks
            for _, target in ipairs(targetPositions) do
                if math.abs(x - target.x) <= 10 and math.abs(y - target.y) <= 10 and target.type ~= "entity"then
                    selectedTarget = target.data
                    selectedTargetType = target.type
                    targetTypeIcon = target.targetIcon
                    displayState = "targetInfo"
                    print(target.type)

                    displayTargetInfo(selectedTarget, targetTypeIcon)

                    break
                end
            end
        elseif displayState == "targetInfo" then
            for _, btn in ipairs(targetInfoButtons) do
                if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                    if btn.onClick then btn.onClick() end
                    break
                end
            end
        end

        ::continue::
    end
end

local function printOutput()
    while true do
        --print(textutils.serialize(missileControls))
        --print(textutils.serialize(AIMInfoList))
        --print(textutils.serialize(GBUInfoList))
        --print(textutils.serialize(immediateMissileInfo))
        --print(missileInfoChannel)
        --print(textutils.serialize(thunderBoltInfoList))
        sleep()
    end
end

parallel.waitForAny(
    function()
        -- Main loop
        while true do
            if displayState == "radar" then
                holo.SetClearColor(backgroundColor)
                holo.Clear()
                --holo.FreeAllFrameBuffer()
                drawRadarDisplay()
                drawControls()
                holo.Flush()        
            elseif displayState == "targetInfo" and selectedTarget then
                displayTargetInfo(selectedTarget, targetTypeIcon)
            elseif displayState == "adjustCannon" then
                --monitor.clear()
                drawCannonAdjustmentPage()
            end
            sleep(0.1)
             -- Adjust this duration if needed
        end
    end,
    handleHologramClick,
    modemMessage,
    aimPortCannonContinuous,
    aimStarboardCannonContinuous,
    aimBowCannonContinuous,
    aimSternCannonContinuous,
    missileWarning,
    broadCastWaypoint,
    missileListBuilding,
    controlsSending,
    printOutput
)