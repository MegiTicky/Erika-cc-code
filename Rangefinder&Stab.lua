cannon = peripheral.find("cbcmodernwarfare:compact_mount") or peripheral.find("createbigcannons:cannon_mount")
raycaster = peripheral.find("raycaster")
camera = peripheral.find("camera")

local cannons = {}
local foundNames = {}
local k = 1

local directions = {"top", "bottom", "left", "right", "front", "back"}
for _, side in ipairs(directions) do
    if peripheral.isPresent(side) then
        local name = peripheral.getType(side)
        if name == "createbigcannons:cannon_mount" or name == "cbcmodernwarfare:compact_mount" then
            local cannon = peripheral.wrap(side)
            if cannon then
                cannons[k] = cannon
                foundNames[peripheral.getName(cannon)] = true
                print("Found direct cannon on side: " .. side)
                k = k + 1
            end
        end
    end
end

local i = 0
local nilCount = 0
local maxNilTolerance = 200

while nilCount < maxNilTolerance do
    local addr1 = "createbigcannons:cannon_mount_" .. i
    local addr2 = "cbcmodernwarfare:compact_mount_" .. i

    local cannon = peripheral.wrap(addr1)
    if not cannon then
        cannon = peripheral.wrap(addr2)
    end

    if cannon then
        local name = peripheral.getName(cannon)
        if not foundNames[name] then
            cannons[k] = cannon
            foundNames[name] = true
            print("Found network cannon: " .. name)
            k = k + 1
        end
        nilCount = 0
    else
        nilCount = nilCount + 1
    end

    i = i + 1
end

print("Total cannons found: " .. #cannons)

local euler_mode = false  -- Set to false for non-euler mode
local max_distance = 1200
local immediate_execution = true

-- Cooldown variables
local cooldownTime = 0.3  -- Cooldown time in seconds
local lastTriggerTime = 0  -- Time when the script was last triggered
local verticalSensitivity = 0.5
redstoneSides = {
    laserRangeFinder = "front",
    horizontalStabInput = "back",
    cannonUpInput = "top",
    cannonDownInput = "bottom",
    cannonLeftOutput = "left",
    cannonRightOutput = "right"
}

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

local function setPitchYaw(targetPitch, targetYaw)
    local tasks = {} -- Table to store each cannon's task

    for index, cannon in pairs(cannons) do
        -- Define the function for this cannon's pitch/yaw adjustment
        local function adjustCannon()
            cannon.setPitch(targetPitch)
            cannon.setYaw(targetYaw)
        end
        -- Add this task to the tasks table
        table.insert(tasks, adjustCannon)
    end

    -- Execute all tasks in parallel
    parallel.waitForAll(table.unpack(tasks))
end

local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

local projectileSpeed = askUser("Enter the projectileSpeed","370")
local g = askUser("Enter the g","0.02")
local cd =askUser("Enter the cd","0.995")
local enableLaserRangeFinder = askUser("Enable laserRangeFinder?","yes")
print("enableVeticalStablizer?")
local enableVerticalStablizer = askUser("Enable vertical stablizer?","yes")
if enableVerticalStablizer == "yes" then
    enableVerticalStablizer = true
else
    enableVerticalStablizer = false
end

if enableVerticalStablizer then
    verticalDriveRPM = askUser("enter the vertical drive maximum RPM","7.4")
    verticalMaxAngularVelocity = verticalDriveRPM / 60 * 360 / 8
end
local vm

cannon.assemble()

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

local function findGlobalAngle(localYaw, localPitch)
    -- Get the ship's current quaternion rotation
    local rot = ship.getQuaternion()
    local rotMatAdj11 = 1 - 2 * (rot.x^2 + rot.y^2)
    local rotMatAdj12 = 2 * (rot.z * rot.x + rot.y * rot.w)
    local rotMatAdj13 = 2 * (rot.z * rot.y - rot.x * rot.w)
    local rotMatAdj21 = 2 * (rot.z * rot.x - rot.y * rot.w)
    local rotMatAdj22 = 1 - 2 * (rot.z^2 + rot.y^2)
    local rotMatAdj23 = 2 * (rot.x * rot.y + rot.z * rot.w)
    local rotMatAdj31 = 2 * (rot.z * rot.y + rot.x * rot.w)
    local rotMatAdj32 = 2 * (rot.x * rot.y - rot.z * rot.w)
    local rotMatAdj33 = 1 - 2 * (rot.z^2 + rot.x^2)
    
    -- Convert local angles to radians and adjust signs
    local cacheYaw = math.pi - math.rad(localYaw)
    local cachePitch = -math.rad(localPitch)
    
    local rotMatLocal11 = math.cos(cacheYaw) * math.cos(cachePitch)
    local rotMatLocal21 = math.sin(cacheYaw) * math.cos(cachePitch)
    local rotMatLocal31 = -math.sin(cachePitch)

    local rotMatGlobal11 = rotMatAdj11 * rotMatLocal11 + rotMatAdj12 * rotMatLocal21 + rotMatAdj13 * rotMatLocal31
    local rotMatGlobal21 = rotMatAdj21 * rotMatLocal11 + rotMatAdj22 * rotMatLocal21 + rotMatAdj23 * rotMatLocal31

    --Somehow pitch considered roll instead, compensating

    local cacheYaw = math.pi - math.rad(localYaw)
    local cachePitch = -math.rad(localPitch)
    local rotMatLocal11 = math.cos(cacheYaw) * math.cos(cachePitch)
    local rotMatLocal21 = math.sin(cacheYaw) * math.cos(cachePitch)
    local rotMatLocal31 = -math.sin(cachePitch)

    local rotMatGlobal31 = rotMatAdj31 * rotMatLocal11 + rotMatAdj32 * rotMatLocal21 + rotMatAdj33 * rotMatLocal31

    local globalYaw = math.atan2(rotMatGlobal21, rotMatGlobal11)
    local globalPitch = math.asin(-rotMatGlobal31)
    
    return math.deg(globalYaw)%360, math.deg(-globalPitch)
end

local function findTargetYawPitch(turretYaw, barrelPitch)
    -- Get ship's quaternion
    rot = ship.getQuaternion()
    
    -- Compute ship's rotation matrix (same as original)
    rotMatAdj11 = 1 - 2 * (rot.x^2 + rot.y^2)
    rotMatAdj12 = 2 * (rot.z * rot.x + rot.y * rot.w)
    rotMatAdj13 = 2 * (rot.z * rot.y - rot.x * rot.w)
    rotMatAdj21 = 2 * (rot.z * rot.x - rot.y * rot.w)
    rotMatAdj22 = 1 - 2 * (rot.z^2 + rot.y^2)
    rotMatAdj23 = 2 * (rot.x * rot.y + rot.z * rot.w)
    rotMatAdj31 = 2 * (rot.z * rot.y + rot.x * rot.w)
    rotMatAdj32 = 2 * (rot.x * rot.y - rot.z * rot.w)
    rotMatAdj33 = 1 - 2 * (rot.z^2 + rot.x^2)
    
    -- Convert turret yaw and pitch to radians (apply sign correction as in original output)
    cacheYaw = -math.rad(turretYaw)
    cachePitch = -math.rad(barrelPitch)
    
    -- Compute turret rotation matrix (same convention as rotMatTGT in original)
    rotMatTurret11 = math.cos(cacheYaw) * math.cos(cachePitch)
    rotMatTurret21 = math.sin(cacheYaw) * math.cos(cachePitch)
    rotMatTurret31 = -math.sin(cachePitch)
    
    -- Compute inverse of ship's rotation matrix
    -- Since rotMatAdj is orthogonal, its inverse is its transpose
    rotMatAdjInv11 = rotMatAdj11
    rotMatAdjInv12 = rotMatAdj21
    rotMatAdjInv13 = rotMatAdj31
    rotMatAdjInv21 = rotMatAdj12
    rotMatAdjInv22 = rotMatAdj22
    rotMatAdjInv23 = rotMatAdj32
    rotMatAdjInv31 = rotMatAdj13
    rotMatAdjInv32 = rotMatAdj23
    rotMatAdjInv33 = rotMatAdj33
    
    -- Compute target rotation matrix: rotMatTGT = rotMatAdjInv * rotMatTurret
    rotMatTGT11 = rotMatAdjInv11 * rotMatTurret11 + rotMatAdjInv12 * rotMatTurret21 + rotMatAdjInv13 * rotMatTurret31
    rotMatTGT21 = rotMatAdjInv21 * rotMatTurret11 + rotMatAdjInv22 * rotMatTurret21 + rotMatAdjInv23 * rotMatTurret31
    rotMatTGT31 = rotMatAdjInv31 * rotMatTurret11 + rotMatAdjInv32 * rotMatTurret21 + rotMatAdjInv33 * rotMatTurret31
    
    -- Extract target yaw and pitch
    targetYaw = math.atan2(rotMatTGT21, rotMatTGT11)
    targetPitch = math.asin(-rotMatTGT31)
    
    -- Convert to degrees and apply sign correction to match original input convention
    return (math.deg(180-targetYaw)) % 360, -math.deg(targetPitch)
end


local function calculateRange(angle, u, cd, g, c_est, projectileSpeed)
    local radians = math.rad(angle)
    local u = projectileSpeed / 20
    local part1 = u * math.cos(radians) / math.log(cd)
    local part2 = ((g * cd) / (g * cd + (1 - cd) * u * math.sin(radians))) ^ (2 + c_est * projectileSpeed * math.sin(radians)) - 1
    local XR = part1 * part2
    return XR
end

local function findBestPitch(distance, initialVelocity, g, cd, c_est, projectileSpeed)
    local bestLowPitch = nil
    local bestHighPitch = nil
    local bestLowDistance = math.huge
    local bestHighDistance = math.huge
    local targetDistance = distance

    for pitch = 0, 65, 0.01 do
        local calculatedRange = calculateRange(pitch, initialVelocity, cd, g, c_est, projectileSpeed)
        local distanceDifference = math.abs(calculatedRange - targetDistance)

        if pitch <= 30 then
            if distanceDifference < bestLowDistance then
                bestLowDistance = distanceDifference
                bestLowPitch = pitch
            end
        elseif pitch > 30 then
            if distanceDifference < bestHighDistance then
                bestHighDistance = distanceDifference
                bestHighPitch = pitch
            end
        end
    end

    if settings.useHighPitch and bestHighPitch and bestHighDistance < 2 then
        return bestHighPitch
    else
        return bestLowPitch
    end
end

local function toRayTarget(camPos, pitch, yaw, distance)
    local radPitch = math.rad(pitch)
    local radYaw = math.rad(yaw)

    local x = camPos.x + distance * -math.sin(radYaw)
    local y = camPos.y + distance * -math.sin(radPitch)
    local z = camPos.z + distance * math.cos(radYaw)
    --[[local dx = -math.sin(radYaw)
    local dy = -math.sin(radPitch)
    local dz = math.cos(radYaw)

    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx = dx / length * distance
    dy = dy / length * distance
    dz = dz / length * distance]]

    return x,y,z--camPos.x + dx, camPos.y + dy, camPos.z + dz
end

local function getRayPoints(origin, direction, distance)
    local norm = math.sqrt(direction.x^2 + direction.y^2 + direction.z^2)
    local dx, dy, dz = direction.x / norm, direction.y / norm, direction.z / norm

    local x = origin.x + dx * distance
    local y = origin.y + dy * distance
    local z = origin.z + dz * distance

    return x,y,z
end

local function vectorToPitchYaw(vec)
    local x, y, z = vec.x, vec.y, vec.z

    -- 计算水平距离（XZ 平面上的长度）
    local horizontalLength = math.sqrt(x * x + z * z)

    -- pitch 是从水平面向上看的角度，范围 -90 到 90
    local pitch = math.deg(math.atan2(-y, horizontalLength))  -- 注意 Minecraft pitch 方向为向上为负

    -- yaw 是从 Z+ 轴开始逆时针旋转的角度，范围 0 到 360
    local yaw = math.deg(math.atan2(-x, z)) % 360

    return pitch, yaw
end


local function aimCannon(targetPos, targetVel, sourceX, sourceY, sourceZ)
    if sourceX and sourceY and sourceZ then
        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        local horizontalDistance = math.sqrt(dx * dx + dz * dz)

        local pitch = math.deg(math.atan2(dy, horizontalDistance))
        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        local cannonPitch = cannon.getPitch()
        local balisticPitch = findBestPitch(targetPos.x, targetPos.y, targetPos.z, sourceX, sourceY, sourceZ, projectileSpeed, g, cd, 0.0028, projectileSpeed)
        pitch = balisticPitch + pitch

        local requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw, pitch)
        cannon.setPitch(requiredRelativePitch)
    end
end

-- Main loop (only showing the camera branch for brevity)
local function laserRangeFinderMain()
    while true do
        if enableLaserRangeFinder then
            local currentTime = os.clock()
            
            if currentTime - lastTriggerTime >= cooldownTime then
                if redstone.getInput(redstoneSides.laserRangeFinder) then
                    local cannonPitch = cannon.getPitch()
                    local cannonYaw = cannon.getYaw()
                    local shipPos = ship.getWorldspacePosition()
                    print("Cannon Pitch: " .. cannonPitch .. ", Yaw: " .. cannonYaw)
                    
                    if raycaster then
                        -- Existing raycaster logic (unchanged)
                        local Y = math.sin(math.rad(cannonPitch))
                        local X = 0
                        local planar_distance = 1
                        result = raycaster.raycast(max_distance, {Y, X, planar_distance}, euler_mode, immediate_execution)
                        
                        if result.is_block and result.block_type ~= "block.minecraft.air" then
                            print("Block hit at: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
                            print("Block type: " .. result.block_type .. ", Distance: " .. result.distance)
                        elseif result.is_entity then
                            print("Entity hit at: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
                            print("Entity ID: " .. result.id .. ", Distance: " .. result.distance)
                        elseif result.ship_id then
                            print("Ship hit at: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
                        else
                            print("No hit detected within " .. max_distance .. " blocks.")
                        end
                        
                        if result and result.hit_pos and result.hit_pos[1] then
                            result.hit_pos = {x = result.hit_pos[1], y = result.hit_pos[2], z = result.hit_pos[3]}
                            balisticPitch = findBestPitch(result.distance, projectileSpeed, g, cd, 0.0028, projectileSpeed)
                            setPitchYaw(cannonPitch + balisticPitch,cannonYaw)
                        end
                    elseif camera then
                        -- Get global yaw and pitch from cannon's orientation
                        local globalYaw, globalPitch = findTargetYawPitch(cannonYaw, cannonPitch)
                        print("Global Yaw: " .. globalYaw .. ", Global Pitch: " .. globalPitch)
                        -- Get camera position
                        local camPos = camera.getCameraPosition()
                        print("Camera Pos: " .. camPos.x .. ", " .. camPos.y .. ", " .. camPos.z)
                        -- Set camera orientation to match cannon
                        camera.forcePitchYaw(-cannonPitch, cannonYaw)
                        camera.setPitch(-cannonPitch)
                        camera.setYaw(cannonYaw)
                        local cameraVec = camera.getAbsViewForward()
                        local cameraPitch, cameraYaw = vectorToPitchYaw(cameraVec)
                        print("cameraPitch: "..cameraPitch.." cameraYaw: "..cameraYaw)
                        local x0, y0, z0 = getRayPoints(camPos, cameraVec, 5) -- Start 0.5 blocks from camera
                        local x1, y1, z1 = getRayPoints(camPos, cameraVec, max_distance) -- End at max distance
                        print("Ray Start: " .. x0 .. ", " .. y0 .. ", " .. z0)
                        print("Ray End: " .. x1 .. ", " .. y1 .. ", " .. z1)

                        local result = camera.raycast(x0, y0, z0, x1, y1, z1)
                        
                        if result and result.hit then
                            print("Hit at: " .. result.hit.x .. ", " .. result.hit.y .. ", " .. result.hit.z)
                            
                            -- Calculate distance from camera to hit point
                            local distance = math.sqrt(
                                (result.hit.x - camPos.x)^2 +
                                (result.hit.y - camPos.y)^2 +
                                (result.hit.z - camPos.z)^2
                            )
                            print("Distance to hit: " .. distance)
                            
                            -- Adjust cannon pitch
                            local balisticPitch = findBestPitch(distance, projectileSpeed, g, cd, 0.0028, projectileSpeed)
                            print("Balistic Pitch: " .. balisticPitch)
                            setPitchYaw(cannonPitch + balisticPitch,cannonYaw)
                        else
                            print("No hit detected")
                        end
                    else
                        print("No raycaster or camera detected")
                    end
                    
                    lastTriggerTime = currentTime
                end
            end
        end
        sleep()
    end
end

local localCannonYaw, localCannonPitch = cannons[1].getYaw(), cannons[1].getPitch()
if localCannonYaw == 0 then
    shipPitch = math.deg(getPitch())
elseif localCannonYaw == 90 then
    shipPitch = -math.deg(getRoll())
elseif localCannonYaw == 180 then
    shipPitch = -math.deg(getPitch())
elseif localCannonYaw == 270 then
    shipPitch = math.deg(getRoll())
else
    error("Yaw offseted, cannon process")
end

lastLoopTime = os.clock()
lastPitch = math.deg(getPitch())
globalPitch = shipPitch + localCannonPitch
local globalYaw, requiredLocalPitch, localCannonYaw
pitchMotor = peripheral.find("Create_RotationSpeedController")
sleep(0.2)
local function verticalStabilizerMain()
    while true do
        if enableVerticalStablizer then
            local currentTime = os.clock()
            local dt = currentTime - lastLoopTime
            if dt < 0.001 then
                dt = 0.001
            end
            lastLoopTime = currentTime

            -- Compute ship pitch angular velocity
            local currentPitch = math.deg(getPitch())
            local pitchAngularVelocity = (currentPitch - lastPitch) / dt
            lastPitch = currentPitch

            -- User input
            local cannonInput = 0
            if redstone.getInput(redstoneSides.cannonUpInput) then
                cannonInput = redstone.getAnalogInput(redstoneSides.cannonUpInput) -- Normalize to 0..1
                --print(cannonInput)
            elseif redstone.getInput(redstoneSides.cannonDownInput) then
                cannonInput = -redstone.getAnalogInput(redstoneSides.cannonDownInput)
                --print(cannonInput)
            end

            -- Stabilizer desired correction
            local desiredCannonSpeed = -pitchAngularVelocity
            local stabilizerOutput = desiredCannonSpeed * 60 / 360 * 8

            -- Combine
            local finalCommand = cannonInput + stabilizerOutput
            finalCommand = math.min(math.max(-finalCommand,-256),256)
            pitchMotor.setTargetSpeed(finalCommand)
            -- Debug print
            print(string.format("PitchVel=%.2f | UserInput=%.2f | StabilizerOut=%.2f | Final=%.2f", pitchAngularVelocity, cannonInput, stabilizerOutput, finalCommand))
        end

        sleep()
    end
end

local currentTargetPitch = 0  -- Initialize once at the top
local maxPitchStepPerFrame = 1  -- degrees max change per frame

local function verticalStabilizerMain()
    while true do
        if enableVerticalStablizer then
            local currentTime = os.clock()
            local dt = currentTime - lastLoopTime
            if dt < 0.001 then dt = 0.001 end
            lastLoopTime = currentTime

            -- Compute ship pitch angular velocity
            local currentPitch = math.deg(getPitch())
            local pitchAngularVelocity = (currentPitch - lastPitch) / dt
            lastPitch = currentPitch

            -- User input
            local cannonInput = 0
            if redstone.getInput(redstoneSides.cannonUpInput) then
                cannonInput = redstone.getAnalogInput(redstoneSides.cannonUpInput) * verticalSensitivity
            elseif redstone.getInput(redstoneSides.cannonDownInput) then
                cannonInput = -redstone.getAnalogInput(redstoneSides.cannonDownInput) * verticalSensitivity
            end

            -- Stabilizer desired correction
            local desiredCannonSpeed = -pitchAngularVelocity
            local stabilizerOutput = desiredCannonSpeed * 60 / 360 * 8

            -- Combine
            local finalCommand = cannonInput + stabilizerOutput
            finalCommand = math.min(math.max(-finalCommand, -256), 256)
            pitchMotor.setTargetSpeed(finalCommand)

            -- Set pitch for accurate but SMOOTH angle
            local localCannonYaw, localCannonPitch = cannons[1].getYaw(), cannons[1].getPitch()
            if localCannonYaw == 0 then
                shipPitch = math.deg(getPitch())
            elseif localCannonYaw == 90 then
                shipPitch = -math.deg(getRoll())
            elseif localCannonYaw == 180 then
                shipPitch = -math.deg(getPitch())
            elseif localCannonYaw == 270 then
                shipPitch = math.deg(getRoll())
            else
                error("Yaw offseted, cannon process")
            end

            deltaPitch = cannonInput/60*360/8*dt
            print("deltaPitch: "..deltaPitch)
            globalPitch = globalPitch + deltaPitch

            _, requiredLocalPitch = findRelativeAngle(localCannonYaw + math.deg(getYaw()), globalPitch)

            -- Smooth the setPitchYaw:
            local pitchError = requiredLocalPitch - currentTargetPitch

            -- Wrap pitch error to -180..180
            if pitchError > 180 then pitchError = pitchError - 360 end
            if pitchError < -180 then pitchError = pitchError + 360 end

            -- Limit step per frame
            local pitchStep = math.max(math.min(pitchError, maxPitchStepPerFrame), -maxPitchStepPerFrame)

            -- Update target pitch gradually
            currentTargetPitch = currentTargetPitch + pitchStep

            -- Finally set it
            --setPitchYaw(currentTargetPitch, localCannonYaw)

            -- Debug print
            print(string.format("PitchVel=%.2f | UserInput=%.2f | StabilizerOut=%.2f | Final=%.2f | currentTargetPitch=%.2f", 
                pitchAngularVelocity, cannonInput, stabilizerOutput, finalCommand, currentTargetPitch))
        end

        sleep()
    end
end

local function PIDController(Kp, Ki, Kd, error, integral, prevError, dt)
    -- Calculate the proportional, integral, and derivative components
    local proportional = Kp * error
    integral = integral + error * dt
    derivative = (error - prevError) / dt
    
    -- Calculate output
    local output = proportional + (Ki * integral) + (Kd * derivative)

    -- Return the PID output and updated integral and previous error
    return output, integral, error
end

local function horizontalStabilizerMain()
    -- PID gains (tune these for best performance!)
    local Kp = 2.0
    local Ki = 0.5
    local Kd = 1.0

    local integral = 0
    local prevError = 0

    local lastHorizontalStabTime = os.clock()
    local lastYaw = math.deg(getYaw())

    while true do
        if enableVerticalStablizer then
            if redstone.getInput(redstoneSides.horizontalStabInput) then
                local currentTime = os.clock()
                local dt = currentTime - lastHorizontalStabTime
                print(dt)
                if dt < 0.001 then dt = 0.001 end  -- Prevent division by 0

                lastHorizontalStabTime = currentTime

                -- Get current yaw and compute angular velocity
                local currentYaw = math.deg(getYaw())
                local yawAngularVelocity = (currentYaw - lastYaw) / dt
                lastYaw = currentYaw

                -- Stabilization target: we want 0 angular velocity
                local error = -yawAngularVelocity

                -- Use PID controller to compute correction
                local pidOutput
                pidOutput, integral, prevError = PIDController(Kp, Ki, Kd, error, integral, prevError, dt)

                -- Map PID output to redstone signal [-15 .. 15]
                -- You can adjust maxOutputScale to make it more/less aggressive
                local maxOutputScale = 30  -- Max PID output that maps to 15 signal
                local redstoneSignal = pidOutput / maxOutputScale * 15

                -- Clamp
                if redstoneSignal > 15 then redstoneSignal = 15 end
                if redstoneSignal < -15 then redstoneSignal = -15 end

                -- Apply redstone output
                if redstoneSignal > 0 then
                    redstone.setAnalogOutput(redstoneSides.cannonRightOutput, math.floor(redstoneSignal))
                    redstone.setAnalogOutput(redstoneSides.cannonLeftOutput, 0)
                elseif redstoneSignal < 0 then
                    redstone.setAnalogOutput(redstoneSides.cannonLeftOutput, math.floor(-redstoneSignal))
                    redstone.setAnalogOutput(redstoneSides.cannonRightOutput, 0)
                else
                    redstone.setAnalogOutput(redstoneSides.cannonLeftOutput, 0)
                    redstone.setAnalogOutput(redstoneSides.cannonRightOutput, 0)
                end

                -- Debug print
                print(string.format("YawVel=%.2f | Error=%.2f | PIDOut=%.2f | Redstone=%.2f", yawAngularVelocity, error, pidOutput, redstoneSignal))
            else
                -- Disable output if horizontal stab is not enabled
                redstone.setAnalogOutput(redstoneSides.cannonLeftOutput, 0)
                redstone.setAnalogOutput(redstoneSides.cannonRightOutput, 0)
                lastHorizontalStabTime = os.clock()
            end
        end
        sleep(0.05)  -- ~20Hz update
    end
end


parallel.waitForAny(
    laserRangeFinderMain,
    verticalStabilizerMain,
    horizontalStabilizerMain
)