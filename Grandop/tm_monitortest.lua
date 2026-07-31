leftTrack = peripheral.wrap("left")
rightTrack = peripheral.wrap("right")
raycaster = peripheral.find("raycaster")
modem = peripheral.wrap("front")
camera = peripheral.find("camera")
cannon = peripheral.wrap("back")
gpu = peripheral.find("tm_gpu")

gpu.refreshSize()
gpu.newBuffer()
--gpu.createWindow(1, 1, 64, 64)
gpu.setSize(64,64)
gpu.filledRectangle(1,1,1,1,0xFFFFFFFF)
gpu.sync()


local fireworkType = "minecraft:firework_rocket"
local function summonParticleAt(pos)
    local cmd = string.format(
        "/summon %s %.2f %.2f %.2f",
        fireworkType, pos.x, pos.y, pos.z
    )
    commands.exec(cmd)
end
--[[while true do
    summonParticleAt({x=6403,y=27,z=6446})
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

        local currentYaw = (math.deg(getYaw()))%360
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

local shipPos = ship.getWorldspacePosition()
path = {{x=6363,z=6391},{x=6363,z=6391}}
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
                    print(yawError, yawAdjustment)
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

                    sleep()
                end

                leftTrack.setTargetSpeed(0)
                rightTrack.setTargetSpeed(0)

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
    end,
    function()
        while true do
            for _, waypoint in ipairs(path) do
                summonParticleAt({x=waypoint.x, y=shipPos.y+2, z=waypoint.z})
            end
        end
    end
)


--raycaster.raycast(max_distance, {Y, X, planar_distance}, euler_mode, immediate_execution)
local function navigateToTarget()
    while true do
        if mainToDriveMessage and mainToDriveMessage.pos then
            local selfPos = ship.getWorldspacePosition()
            selfPos = camera.getCameraPosition()
            local targetPos = mainToDriveMessage.pos

            --print("targetPos: x: "..targetPos.x.." y: "..targetPos.y.." z: "..targetPos.z)

            local targetDistance = math.sqrt((targetPos.x - selfPos.x) ^ 2 + (targetPos.y - selfPos.y) ^ 2 + (targetPos.z - selfPos.z) ^ 2)
            local dirVec = {targetPos.x - selfPos.x, targetPos.y- selfPos.y, targetPos.z - selfPos.z}
            dirVec = normalizeVector(dirVec)

            local targetYaw = (math.deg(math.atan2(-dirVec[1], dirVec[3]))+180) % 360
            local selfYaw = (math.deg(getYaw())+mainToDriveMessage.yawCompensation) % 360
            local yawDiff = (targetYaw - selfYaw + 180) % 360 - 180
            --print("yawDiff: "..yawDiff)
            --print("targetYaw: "..targetYaw)
            --print("selfYaw: "..selfYaw)

            local horizontalDistance = math.sqrt(dirVec[1] * dirVec[1] + dirVec[3] * dirVec[3])
            local pitch = math.deg(math.atan2(dirVec[2], horizontalDistance))
            if mainToDriveMessage.lineOfSight then
                print("Cannon ready to fire, stoping navigation")
                break
            end
            if math.abs(yawDiff) > 45 then
                print("Yaw difference too large, turning")
                turnTowardsPID(targetYaw)
            else
                sleep(0.2)
                local relativeYaw, relativePitch = findRelativeAngle(targetYaw, math.deg(math.asin(dirVec[2])))
                relativeYaw = relativeYaw
                --print("relativeYaw: "..relativeYaw.." relativePitch: "..relativePitch)
                --cannon.setPitch(relativePitch)
                --cannon.setYaw(relativeYaw)

                camera.forcePitchYaw(-relativePitch, relativeYaw)
                sleep()
                hitPos = designation()
                print(textutils.serialize(hitPos))
                hitDistance = math.sqrt((hitPos.x - selfPos.x)^2+(hitPos.y - selfPos.y)^2+(hitPos.z - selfPos.z)^2)
                result = {distance = hitDistance}
                

                --[[local Y = -math.sin(math.rad(0))
                local X = math.cos(math.rad(relativePitch+180)) * math.sin(math.rad(relativeYaw+180))
                local planar_distance = 1

                local max_distance = targetDistance + 100
                local result = raycaster.raycast(max_distance, { Y, X, planar_distance}, false, true)
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
                end]]
                print(hitDistance, targetDistance)

                if result and math.abs(hitDistance - targetDistance) < 5 then
                    -- Direct line of sight achieved
                    leftTrack.setTargetSpeed(0)
                    rightTrack.setTargetSpeed(0)
                    print("Target in sight, stopping.")
                    break
                elseif result and hitDistance > targetDistance + 10 then
                    leftTrack.setTargetSpeed(0)
                    rightTrack.setTargetSpeed(0)
                    print("Target in sight, stopping.")
                end

                local obstacleFirstDistance = hitDistance
                local obstacleFirstPos = hitPos
                print("obstacleFirstDistance: "..obstacleFirstDistance)

                if obstacleFirstDistance < 5 then
                    -- go back if obstacle too close
                    leftTrack.setTargetSpeed(-128)
                    rightTrack.setTargetSpeed(-128)
                    sleep(3)
                    leftTrack.setTargetSpeed(0)
                    rightTrack.setTargetSpeed(0)
                end

                -- Obstacle detected, start fanning out rays
                local foundOpening = false
                local fannedAngles = {}
                local openingDistance = 0
                while not foundOpening do
                    for angle = 0, 45, 5 do
                        -- right check
                        local rightYawCheck = relativeYaw + angle
                        camera.forcePitchYaw(relativePitch, rightYawCheck)
                        sleep(0.04)
                        local hitPos = designation()
                        local hitDistance = math.sqrt((hitPos.x - selfPos.x)^2+(hitPos.y - selfPos.y)^2+(hitPos.z - selfPos.z)^2)
                        if hitDistance > obstacleFirstDistance+5 then
                            table.insert(fannedAngles, angle)
                            foundOpening = true
                            openingDistance = hitDistance
                            openingAngle = angle

                            local wallOpeningVec = {hitPos.x - selfPos.x, hitPos.y- selfPos.y, hitPos.z - selfPos.z}
                            wallOpeningVec = normalizeVector(wallOpeningVec)
                            local targetYaw = (math.deg(math.atan2(-wallOpeningVec[1], wallOpeningVec[3]))+180) % 360

                            print("Opening found to the right.")
                            turnTowardsPID(targetYaw + 30)
                            -- Store wall edges in a table if needed
                            break
                        end

                        --[[left check
                        local leftYawCheck = relativeYaw - angle
                        camera.forcePitchYaw(relativePitch, leftYawCheck)
                        sleep(0.04)
                        local hitPos = designation()
                        local hitDistance = math.sqrt((hitPos.x - selfPos.x)^2+(hitPos.y - selfPos.y)^2+(hitPos.z - selfPos.z)^2)
                        if hitDistance > obstacleFirstDistance+10 then
                            table.insert(fannedAngles, angle)
                            foundOpening = true
                            openingDistance = hitDistance
                            openingAngle = -angle

                            local wallOpeningVec = {hitPos.x - selfPos.x, hitPos.y- selfPos.y, hitPos.z - selfPos.z}
                            wallOpeningVec = normalizeVector(wallOpeningVec)
                            local targetYaw = (math.deg(math.atan2(-wallOpeningVec[1], wallOpeningVec[3]))+180) % 360

                            print("Opening found to the left.")
                            turnTowardsPID(targetYaw - 30)

                            -- Store wall edges in a table if needed
                            break
                        end]]
                    end
                    if not foundOpening then
                        local selfYaw = (math.deg(getYaw())+mainToDriveMessage.yawCompensation) % 360
                        print("No clear opening found, rotating further.")
                        turnTowardsPID(selfYaw+45)
                    end
                end

                openingDistance = obstacleFirstDistance / math.cos(math.rad(openingAngle))
                -- Move forward to the 
                leftTrack.setTargetSpeed(128)
                rightTrack.setTargetSpeed(128)
                print(openingDistance)
                local sleepTime = openingDistance/6.7 + 3
                if sleepTime > 6 then sleepTime = sleepTime/2 end
                sleep(sleepTime)
                leftTrack.setTargetSpeed(0)
                rightTrack.setTargetSpeed(0)
            end
        end
        sleep()
    end
end