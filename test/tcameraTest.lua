camera = peripheral.find("camera")
raycaster = peripheral.find("raycaster")
gpu = peripheral.find("tm_gpu")



--[[while true do
    relativePitch = 0
    relativeYaw = 0
    local Y = math.sin(math.rad(relativePitch))
    local X = math.cos(math.rad(relativePitch+180)) * math.sin(math.rad(relativeYaw+180))
    local planar_distance = 1
    --local result = raycaster.raycast(300, { Y, X, planar_distance}, false, true)
    --print(textutils.serialize(result))
    print(camera.getClipDistance())
    camera.forcePitchYaw(relativePitch,relativeYaw)
    sleep(0.1)
    cameraClip = camera.clip()
    print(textutils.serialize(cameraClip))

    sleep()
end]]

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

local function designation(MaxRange)
    -- Check if camera exists
    if not camera then
        print("Error: Camera peripheral not found")
        return
    end
    camera.setClipRange(MaxRange)
    local result = camera.clipBlockDetail()
    local maxClipDistance = camera.getClipDistance()
    local cameraPos = camera.getCameraPosition()

    if result and result.hit then
        local hit_distance = math.sqrt((cameraPos.x - result.hit.x)^2+(cameraPos.y - result.hit.y)^2+(cameraPos.z - result.hit.z)^2)
        if math.abs(hit_distance - MaxRange) < 2 then
            return nil
        end
        local hitPos = {
            x = result.hit.x,
            y = result.hit.y,
            z = result.hit.z,
            distance=hit_distance,
        }
        return hitPos
    end
    return
end

local OBSTACLE_MAP = {}
local GRID_SIZE = 5  -- 5x5 meter grid cells
local MAP_RADIUS = 50 -- meters around the tank
local SCAN_RESOLUTION = 5 -- degrees between rays
local obstacleMap = {}

local function scanSurroundings()
    local SCAN_RESOLUTION = 5  -- Degrees between scan points
    local EXPAND_RADIUS = 2    -- Blocks to expand around detected obstacles (creates 5x5 area)
    local MAX_DISTANCE = 50    -- Maximum scan distance
    
    -- Perform 360-degree scan
    for angle = 0, 355, SCAN_RESOLUTION do
        camera.forcePitchYaw(0, angle)  -- Look horizontally
        --sleep(0.05)  -- Allow camera adjustment
        
        local hit = designation(MAP_RADIUS)
        --print(textutils.serialize(hit))
        if hit and hit.distance then
            -- Get obstacle position (convert to integer coordinates)
            local x = math.floor(hit.x + 0.5)
            local z = math.floor(hit.z + 0.5)

            --print(x,z)
            
            -- Mark 5x5 area around obstacle
            for dx = -EXPAND_RADIUS, EXPAND_RADIUS do
                for dz = -EXPAND_RADIUS, EXPAND_RADIUS do
                    local gridX = x + dx
                    local gridZ = z + dz
                    
                    -- Initialize x-coordinate if needed
                    if not obstacleMap[gridX] then
                        obstacleMap[gridX] = {}
                    end
                    
                    -- Mark as obstacle (1 = blocked)
                    obstacleMap[gridX][gridZ] = 1
                end
            end
        end
    end
    
    return obstacleMap
end

-- Function to visualize obstacleMap on a monitor
gpu.refreshSize()
gpu.newBuffer()
gpu.setSize(64,64)
-- Modified visualization function with facing indicator
local function visualizeObstacleMap(obstacleMap, tankX, tankZ, range)
    -- Get monitor dimensions
    local width, height = gpu.getSize()
    local centerX, centerY = math.floor(width/2), math.floor(height/2)
    
    -- Clear screen
    gpu.fill(0xFF888888)  -- Gray background
    
    -- Get tank facing direction
    local facingRad = getYaw() + math.pi/2
    
    -- Calculate endpoint for facing line (20% of screen size)
    local lineLength = math.min(width, height) * 0.2
    local endX = centerX + math.cos(facingRad) * lineLength
    local endY = centerY - math.sin(facingRad) * lineLength  -- Negative because screen Y increases downward
    
    -- Draw obstacles
    for x, zCols in pairs(obstacleMap) do
        for z, value in pairs(zCols) do
            if value == 1 then
                local dx = x - tankX
                local dz = z - tankZ
                local screenX = centerX + math.floor(dx * width/(2*range))
                local screenY = centerY + math.floor(dz * height/(2*range))
                
                if screenX > 0 and screenX <= width and screenY > 0 and screenY <= height then
                    gpu.filledRectangle(screenX, screenY, 1, 1, 0xFFFF0000)  -- Red obstacles
                end
            end
        end
    end
    
    -- Draw tank position (center)
    gpu.filledRectangle(centerX-1, centerY-1, 3, 3, 0xFF00FF00)  -- Green tank (slightly larger)
    
    -- Draw facing direction line (yellow)
    gpu.lineS(centerX, centerY, endX, endY, 0xFFFFFF00)
    
    -- Draw small arrowhead at end of line
    local arrowSize = 2
    local arrowAngle1 = facingRad + math.rad(135)
    local arrowAngle2 = facingRad - math.rad(135)
    gpu.lineS(endX, endY, endX + math.cos(arrowAngle1)*arrowSize, endY - math.sin(arrowAngle1)*arrowSize, 0xFFFFFF00)
    gpu.lineS(endX, endY, endX + math.cos(arrowAngle2)*arrowSize, endY - math.sin(arrowAngle2)*arrowSize, 0xFFFFFF00)
    
    -- Update display
    gpu.sync()
end

scanSurroundings()
shipPos = ship.getWorldspacePosition()
visualizeObstacleMap(obstacleMap,shipPos.x,shipPos.z, 32)
print(textutils.serialize(obstacleMap))