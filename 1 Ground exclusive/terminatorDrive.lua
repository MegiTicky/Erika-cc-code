leftTrack = peripheral.wrap("left")
rightTrack = peripheral.wrap("right")
raycaster = peripheral.find("raycaster")
modem = peripheral.wrap("front")
camera = peripheral.find("camera")
cannon = peripheral.wrap("back")
gpu = peripheral.find("tm_gpu")

local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

mainToDriveChannel = tonumber(askUser ("What communication channel do you want to use for main to drive computer?",2600))
driveToMainChannel = mainToDriveChannel + 1

modem.open(mainToDriveChannel)
modem.open(driveToMainChannel)
leftTrack.setTargetSpeed(0)
rightTrack.setTargetSpeed(0)

mainToDriveMessage = {yawCompensation = 0}

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

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == mainToDriveChannel then
                mainToDriveMessage = message
            end
        else
            sleep()
        end
    end
end

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end

local function isClose(pos1, pos2, threshold)
    return distance(pos1, pos2) < threshold
end

local shipYaw, shipPitch, shipVelocity, shipPos = 0,0,{x=0,y=0,z=0}, {x=0,y=0,z=0}
local function updateInfo()
    while true do
        shipYaw = getYaw()
        shipPitch = getPitch()
        shipVelocity = ship.getVelocity()
        shipPos = ship.getWorldspacePosition()
        sleep()
    end
end

local function turnTowards(yawDiff)
    if yawDiff > 0 then
        leftTrack.setTargetSpeed(64)
        rightTrack.setTargetSpeed(-64)
        print("turning right")
    else
        leftTrack.setTargetSpeed(-64)
        rightTrack.setTargetSpeed(64)
        print("turning left")
    end
    sleep(0.3)
    leftTrack.setTargetSpeed(0)
    rightTrack.setTargetSpeed(0)
end

local function turnTowardsPID(desiredYaw, forwardRPM)
    local Kp_yaw, Ki_yaw, Kd_yaw = 2, 0, 0.5
    local yawError = 0
    local yawIntegral = 0
    local yawPrevError = 0
    local threshold = 3 -- stop turning when within 1 degree
    local lastTime = os.clock()
    local dt = 0.05 -- loop timestep
    local maxSpeed = 64 -- limit turn speed

    while true do
        local currentTime = os.clock()
        local dt = currentTime - lastTime
        lastTime = currentTime
        if dt < 0.001 then dt = 0.001 end

        local currentYaw = (math.deg(getYaw()) + mainToDriveMessage.yawCompensation)%360
        yawError = desiredYaw - currentYaw

        -- Normalize yawError to [-pi, pi]
        yawError = (yawError + 180) % (2 * 180) - 180
        --print(yawError,desiredYaw,currentYaw)
        -- PID calculation
        local yawAdjustment
        yawAdjustment, yawIntegral, yawPrevError = PIDController(
            Kp_yaw, Ki_yaw, Kd_yaw,
            yawError, yawIntegral,
            (yawError - yawPrevError), yawPrevError, dt
        )

        -- Clamp output to safe range
        yawAdjustment = math.max(-maxSpeed, math.min(maxSpeed, yawAdjustment))

        -- Apply rotation
        if yawAdjustment > 0 then
            --turn right
            leftTrack.setTargetSpeed(yawAdjustment)
            rightTrack.setTargetSpeed(-yawAdjustment)
        else
            --turn left
            leftTrack.setTargetSpeed(yawAdjustment)
            rightTrack.setTargetSpeed(-yawAdjustment)
        end

        -- Stop if aligned
        if math.abs(yawError) < threshold then
            leftTrack.setTargetSpeed(0)
            rightTrack.setTargetSpeed(0)
            break
        end

        sleep()
    end
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

--==================--
--Obstacle map scanning function--
--==================--
-- Add this at the top of your code
local obstacleMap = {}
local GRID_SIZE = 5  -- 5x5 meter grid cells
local MAP_RADIUS = 50 -- meters around the tank
local SCAN_RESOLUTION = 5 -- degrees between rays


-- OLD FUNCTION!! Update the obstacle map with new scan data
local function updateObstacleMap()
    local tankPos = ship.getWorldspacePosition()
    local startX, startZ = worldToGrid(tankPos)
    
    -- Scan in all directions
    for angle = 0, 360, SCAN_RESOLUTION do
        local rad = math.rad(angle)
        local X = math.sin(rad)
        local Y = 0
        local planar_distance = math.cos(rad)
        
        -- Cast ray
        local relativeYaw, relativePitch = findRelativeAngle(angle, 0)
        camera.forcePitchYaw(-relativePitch, relativeYaw)
        local hit_pos = designation(MAP_RADIUS)
        
        if hit_pos and hit_pos.x then
            local hitX, hitZ = worldToGrid({
                x = hit_pos.x,
                z = hit_pos.z
            })
            summonParticleAt({x=waypoint.x,y=selfPos.y+5,z=waypoint.z})
            -- Mark hit cell as obstacle
            OBSTACLE_MAP[hitX] = OBSTACLE_MAP[hitX] or {}
            OBSTACLE_MAP[hitX][hitZ] = true
            
            -- Mark cells along the ray as free (except the hit cell)
            local dx = hitX - startX
            local dz = hitZ - startZ
            local steps = math.max(math.abs(dx), math.abs(dz))
            
            for i = 1, steps - 1 do
                local t = i / steps
                local gridX = math.floor(startX + dx * t)
                local gridZ = math.floor(startZ + dz * t)
                
                OBSTACLE_MAP[gridX] = OBSTACLE_MAP[gridX] or {}
                OBSTACLE_MAP[gridX][gridZ] = OBSTACLE_MAP[gridX][gridZ] or false
            end
        end
    end
end

local function scanSurroundings()
    local SCAN_RESOLUTION = 3  -- Degrees between scan points
    local EXPAND_RADIUS = 2    -- Blocks to expand around detected obstacles (creates 5x5 area)
    local MAX_DISTANCE = 50    -- Maximum scan distance
    
    -- Perform 360-degree scan
    print("Scanning suroudding")
    for angle = 0, 355, SCAN_RESOLUTION do
        camera.forcePitchYaw(0, angle)  -- Look horizontally
        --sleep(0.05)  -- Allow camera adjustment
        
        local hit = designation(MAP_RADIUS)
        --print(textutils.serialize(hit))
        if hit and hit.distance and hit.x then
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
end
--==================--
-- Pathfinding function (Optimized)
--==================--
local PATHFINDING_STEP = 7  -- Blocks per pathfinding step
local MAX_JUMP_DISTANCE = 15 -- Maximum direct jump distance
local HEURISTIC_WEIGHT = 1.2 -- >1 ⇒ greedier, sub-optimality ≤ weight

-- Build a unique hash for a grid cell
local function nodeKey(x, z)
    return x .. "," .. z
end

-- Euclidean distance for more accurate estimation
local function heuristic(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.z - b.z)^2)
end

local function isPositionBlocked(x, z)
    -- Check if any position in 5x5 area is blocked (accounting for tank size)
    for dx = -2, 2 do
        for dz = -2, 2 do
            if obstacleMap[x + dx] and obstacleMap[x + dx][z + dz] == 1 then
                return true
            end
        end
    end
    return false
end

local function hasLineOfSight(startX, startZ, endX, endZ)
    -- Bresenham's line algorithm to check for obstacles
    local dx = math.abs(endX - startX)
    local dz = math.abs(endZ - startZ)
    local sx = startX < endX and 1 or -1
    local sz = startZ < endZ and 1 or -1
    local err = dx - dz

    local x, z = startX, startZ
    while x ~= endX or z ~= endZ do
        if isPositionBlocked(x, z) then
            return false
        end
        local e2 = 2 * err
        if e2 > -dz then
            err = err - dz
            x = x + sx
        end
        if e2 < dx then
            err = err + dx
            z = z + sz
        end
    end

    return true
end

-- Optimized pathfinding: Get neighbors with larger steps
local function getNeighbors(node, goal)
    local neighbors = {}

    -- Try direct jump to goal if possible
    if heuristic(node, goal) <= MAX_JUMP_DISTANCE and hasLineOfSight(node.x, node.z, goal.x, goal.z) then
        table.insert(neighbors, {
            x = goal.x,
            z = goal.z,
            g = heuristic(node, goal),
            h = 0
        })
    end

    -- Directions with larger steps
    local directions = {
        {x = PATHFINDING_STEP, z = 0}, {x = -PATHFINDING_STEP, z = 0},
        {x = 0, z = PATHFINDING_STEP}, {x = 0, z = -PATHFINDING_STEP},
        {x = PATHFINDING_STEP, z = PATHFINDING_STEP},
        {x = PATHFINDING_STEP, z = -PATHFINDING_STEP},
        {x = -PATHFINDING_STEP, z = PATHFINDING_STEP},
        {x = -PATHFINDING_STEP, z = -PATHFINDING_STEP}
    }

    for _, dir in ipairs(directions) do
        local neighbor = {
            x = node.x + dir.x,
            z = node.z + dir.z,
            g = node.g + (dir.x ~= 0 and dir.z ~= 0 and 1.414 or 1),
            h = heuristic({x = node.x + dir.x, z = node.z + dir.z}, goal)
        }
        neighbor.f = neighbor.g + HEURISTIC_WEIGHT * neighbor.h

        -- Only add if position is not blocked
        if not isPositionBlocked(neighbor.x, neighbor.z) then
            table.insert(neighbors, neighbor)
        end
    end

    return neighbors
end

-- Function for priority queue (Optimized Binary Heap)
local function heapPush(heap, value)
    table.insert(heap, value)
    local i = #heap
    while i > 1 do
        local p = math.floor(i / 2)
        if heap[p].f <= heap[i].f then break end
        heap[i], heap[p] = heap[p], heap[i]
        i = p
    end
end

local function heapPop(heap)
    if #heap == 0 then return nil end
    local res = heap[1]
    heap[1] = heap[#heap]
    heap[#heap] = nil
    local i = 1
    while i * 2 <= #heap do
        local j = i * 2
        if j + 1 <= #heap and heap[j].f > heap[j + 1].f then
            j = j + 1
        end
        if heap[i].f <= heap[j].f then break end
        heap[i], heap[j] = heap[j], heap[i]
        i = j
    end
    return res
end

-- Path reconstruction using a key-based approach
local function reconstructPath(cameFrom, nodeStore, currentKey)
    local path, key = {}, currentKey
    while key do
        local n = nodeStore[key]      -- fetch stored node
        table.insert(path, 1, {x = n.x, z = n.z})
        key = cameFrom[key]
    end
    return path
end

-- A* Pathfinding function with performance logging
local function findPath(startPos, goalPos)
    local totalTimer = os.clock()
    print(string.format("\n=== Starting pathfinding from (%.1f, %.1f) to (%.1f, %.1f) ===", startPos.x, startPos.z, goalPos.x, goalPos.z))

    -- Convert to grid coordinates
    local startX, startZ = math.floor(startPos.x), math.floor(startPos.z)
    local goalX, goalZ = math.floor(goalPos.x), math.floor(goalPos.z)

    -- Initialize data structures
    local openSet = {}
    local cameFrom = {}
    local gScore = {}
    local fScore = {}
    local openSetMap = {}
    local closedSet = {}
    local nodeStore = {}

    -- Initialize starting node
    local startKey = nodeKey(startX, startZ)
    local startNode = {
        x = startX, z = startZ,
        g = 0,
        h = heuristic({x = startX, z = startZ}, {x = goalX, z = goalZ})
    }
    startNode.f = startNode.g + HEURISTIC_WEIGHT * startNode.h
    gScore[startKey] = 0
    nodeStore[startKey] = startNode
    heapPush(openSet, startNode)
    openSetMap[startKey] = true

    -- Main pathfinding loop
    while #openSet > 0 do
        local current = heapPop(openSet)
        if not current then break end

        local currentKey = nodeKey(current.x, current.z)
        if closedSet[currentKey] then goto continue end
        openSetMap[currentKey] = nil
        closedSet[currentKey] = true

        -- Check if we've reached the goal
        if current.x == goalX and current.z == goalZ then
            return reconstructPath(cameFrom, nodeStore, currentKey)
        end

        -- Explore neighbors
        local neighbors = getNeighbors(current, {x = goalX, z = goalZ})
        for _, neighbor in ipairs(neighbors) do
            local nKey = nodeKey(neighbor.x, neighbor.z)
            if closedSet[nKey] then goto nextNeighbor end

            local tentative_g = gScore[currentKey] + heuristic(current, neighbor)
            if not gScore[nKey] or tentative_g < gScore[nKey] then
                cameFrom[nKey] = currentKey
                gScore[nKey] = tentative_g

                local node = nodeStore[nKey] or {x = neighbor.x, z = neighbor.z}
                node.g = tentative_g
                node.h = neighbor.h
                node.f = tentative_g + HEURISTIC_WEIGHT * neighbor.h
                nodeStore[nKey] = node

                heapPush(openSet, node)
                openSetMap[nKey] = true
            end
            ::nextNeighbor::
        end
        sleep()
        ::continue::
    end

    return nil -- No path found
end



--=====================--
--Visualizing function--
--=====================--
-- Function to visualize obstacleMap on a monitor
gpu.refreshSize()
gpu.newBuffer()
gpu.setSize(64,64)
-- Modified visualization function with facing indicator
local function visualizeObstacleMap(obstacleMap, tankX, tankZ, range, path)
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
    
    -- Draw path if available (in blue)
    if path and #path > 0 then
        local prevScreenX, prevScreenY = nil, nil
        
        for i, waypoint in ipairs(path) do
            local dx = waypoint.x - tankX
            local dz = waypoint.z - tankZ
            local screenX = centerX + math.floor(dx * width/(2*range))
            local screenY = centerY + math.floor(dz * height/(2*range))
            
            -- Draw waypoint marker
            if screenX > 1 and screenX <= width and screenY > 1 and screenY <= height then
                -- Draw line connecting waypoints
                if prevScreenX and prevScreenY then
                    gpu.lineS(prevScreenX, prevScreenY, screenX, screenY, 0xFF4444FF)  -- Light blue path line
                end
                gpu.filledRectangle(screenX-1, screenY-1, 1, 1, 0xFF0000FF)  -- Blue waypoint
                
                prevScreenX, prevScreenY = screenX, screenY
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

--Visualize waypoint
local fireworkType = "minecraft:firework_rocket"
local function summonParticleAt(pos)
    local cmd = string.format(
        "/summon %s %.2f %.2f %.2f",
        fireworkType, pos.x, pos.y, pos.z
    )
    commands.exec(cmd)
end

--=====================--
--Navigation Main function--
--=====================--
local function navigateToTarget()
    while true do
        -- Ensure that the mainToDriveMessage contains the necessary data
        if mainToDriveMessage and mainToDriveMessage.pos then
            -- Get current and target positions
            local shipPos = ship.getWorldspacePosition()
            local targetPos = mainToDriveMessage.pos

            -- Scan surroundings and update obstacle map
            scanSurroundings()

            -- Find path to target
            local path = findPath(shipPos, targetPos)

            visualizeObstacleMap(obstacleMap, shipPos.x, shipPos.z, 128, path)

            if obstacleMap[math.floor(shipPos.x + 0.5)] and obstacleMap[math.floor(shipPos.x + 0.5)][math.floor(shipPos.z + 0.5)] == 1 then
                print("Stuck in wall, going back")
                leftTrack.setTargetSpeed(-128)
                rightTrack.setTargetSpeed(-128)
                sleep(1)
                leftTrack.setTargetSpeed(0)
                rightTrack.setTargetSpeed(0)
            end
            

            if path then
                print("Path found with " .. #path .. " waypoints")
                needGoBack = false
                -- Follow the path
                parallel.waitForAny(
                    function ()
                        for i, waypoint in ipairs(path) do
                            if i > 1 then -- Skip first point (current position)
                                -- Calculate direction to waypoint
                                local shipPos = ship.getWorldspacePosition()
                                local dirVec = {
                                    x = waypoint.x - shipPos.x,
                                    z = waypoint.z - shipPos.z
                                }
                                local targetYaw = (math.deg(math.atan2(-dirVec.x, dirVec.z)) + 180) % 360

                                -- Turn to face waypoint
                                --turnTowardsPID(targetYaw)

                                -- Move forward
                                local distance = math.sqrt(dirVec.x^2 + dirVec.z^2)
                                local travelTime = distance / 6.7  -- 6.7 m/s speed

                                local startingTime = os.clock()
                                local currentTime = startingTime
                                local Kp_yaw, Ki_yaw, Kd_yaw = 1.5, 0, 0.5
                                local yawError = 0
                                local yawIntegral = 0
                                local yawPrevError = 0
                                local threshold = 3 -- stop turning when within 1 degree
                                local lastTime = os.clock()
                                local dt = 0.05 -- loop timestep
                                local maxSpeed = 128 -- limit turn speed
                                while distance > 4 and currentTime - startingTime < travelTime * 1.2 do
                                    local currentTime = os.clock()
                                    local dt = currentTime - lastTime
                                    lastTime = currentTime
                                    if dt < 0.001 then dt = 0.001 end
                                    shipPos = ship.getWorldspacePosition()
                                    local dirVec = {
                                        x = waypoint.x - shipPos.x,
                                        z = waypoint.z - shipPos.z
                                    }
                                    distance = math.sqrt(dirVec.x^2 + dirVec.z^2)
                                    local desiredYaw = (math.deg(math.atan2(-dirVec.x, dirVec.z)) + 180) % 360

                                    local currentYaw = (math.deg(getYaw()) +0 )%360
                                    yawError = desiredYaw - currentYaw

                                    -- Normalize yawError to [-pi, pi]
                                    yawError = (yawError + 180) % (2 * 180) - 180
                                    --print(yawError,desiredYaw,currentYaw)
                                    -- PID calculation
                                    local yawAdjustment
                                    yawAdjustment, yawIntegral, yawPrevError = PIDController(
                                        Kp_yaw, Ki_yaw, Kd_yaw,
                                        yawError, yawIntegral,
                                        (yawError - yawPrevError), yawPrevError, dt
                                    )

                                    -- Clamp output to safe range
                                    yawAdjustment = math.max(-maxSpeed, math.min(maxSpeed, yawAdjustment))
                                    -- Apply rotation
                                    if yawAdjustment > 0 then
                                        --turn right
                                        leftTrack.setTargetSpeed(128+yawAdjustment)
                                        rightTrack.setTargetSpeed(128-yawAdjustment)
                                    else
                                        --turn left
                                        leftTrack.setTargetSpeed(128+yawAdjustment)
                                        rightTrack.setTargetSpeed(128-yawAdjustment)
                                    end

                                    if needGoBack then
                                        leftTrack.setTargetSpeed(-128)
                                        rightTrack.setTargetSpeed(-128)
                                        sleep(1)
                                        leftTrack.setTargetSpeed(0)
                                        rightTrack.setTargetSpeed(0)
                                        needGoBack = false
                                    end

                                    sleep()
                                end

                                print("Reached waypoint " .. i)
                            end

                            --check if we are crashing into a obstacle
                            cameraPos = camera.getCameraPosition()
                            --[[if obstacleMap[math.floor(cameraPos.x + 0.5)] and obstacleMap[math.floor(cameraPos.x + 0.5)][math.floor(cameraPos.z + 0.5)] == 1 then
                                print("Stuck in wall, going back and repathfinding")
                                leftTrack.setTargetSpeed(-128)
                                rightTrack.setTargetSpeed(-128)
                                sleep(1)
                                leftTrack.setTargetSpeed(0)
                                rightTrack.setTargetSpeed(0)
                                break
                            end]]
                        end
                        leftTrack.setTargetSpeed(0)
                        rightTrack.setTargetSpeed(0)
                    end,
                    function()
                        local SCAN_RESOLUTION = 2  -- Degrees between scan points
                        local EXPAND_RADIUS = 2    -- Blocks to expand around detected obstacles (creates 5x5 area)
                        local MAX_DISTANCE = 10    -- Maximum scan distance
                        local foundNewObstacle = false

                        while not foundNewObstacle do
                            -- Check if the line of sight has been confirmed by the main computer
                            if mainToDriveMessage.lineOfSight then
                                print("Line of sight already obtained, stopping navigation")
                                leftTrack.setTargetSpeed(0)
                                rightTrack.setTargetSpeed(0)
                                return  -- Stop navigating
                            end
                            
                            for angle = -4, 4, SCAN_RESOLUTION do
                                camera.forcePitchYaw(0, angle)  -- Look horizontally
                                
                                local hit = designation(MAX_DISTANCE)
                                -- If an obstacle is detected
                                if hit and hit.distance and hit.x and hit.z then
                                    -- Get obstacle position (convert to integer coordinates)
                                    local x = math.floor(hit.x + 0.5)
                                    local z = math.floor(hit.z + 0.5)

                                    if hit.distance < 2 then
                                        needGoBack = true
                                    end


                                    -- Check if the obstacle already exists in the obstacle map
                                    if not obstacleMap[x] or not obstacleMap[x][z] then
                                        -- Mark the obstacle and expand the obstacle area in the map
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
                                        print("New obstacle found, re-pathfinding")
                                        foundNewObstacle = true
                                        break  -- Stop scanning after the first new obstacle is found
                                    end
                                end
                            end
                        end
                    end,
                    function()
                        while true do
                            for _, waypoint in ipairs(path) do
                                summonParticleAt({x=waypoint.x, y=shipPos.y+2, z=waypoint.z})
                            end
                        end
                    end
                )

                -- Final approach
                local dirVec = {
                    x = targetPos.x - shipPos.x,
                    z = targetPos.z - shipPos.z
                }
                local targetYaw = (math.deg(math.atan2(-dirVec.x, dirVec.z)) + 180) % 360
                --turnTowardsPID(targetYaw)
            else
                print("Stuck, going back")
                leftTrack.setTargetSpeed(-128)
                rightTrack.setTargetSpeed(-128)
                sleep(1)
                leftTrack.setTargetSpeed(0)
                rightTrack.setTargetSpeed(0)
            end
        end
        leftTrack.setTargetSpeed(0)
        rightTrack.setTargetSpeed(0)
        sleep(0.1)
    end
end


local function main()
    while true do
        --Navigate to target if line of sight not archevied
        if mainToDriveMessage and not mainToDriveMessage.lineOfSight then
            navigateToTarget()
        end
        sleep()
    end
end


parallel.waitForAny(
    modemMessage,
    updateInfo,
    main
)