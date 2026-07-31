local radar = peripheral.find("sp_radar")
local modem = peripheral.wrap("right")
local pitchMotor = peripheral.wrap("left")
for i = 0, 200 do  -- Assuming there are 2 Create_RotationSpeedController peripherals
    yawMotor = peripheral.wrap("Create_RotationSpeedController_"..tostring(i))
    if yawMotor then
        break
    end
end

local friendlyIDs
local friendlyIDFile = "friendly_ids.txt"
local scanInterval = 0.01

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

local Kp_yaw = 7
local Ki_yaw = 0
local Kd_yaw = 0.05
local Kp_pitch = 0.5
local Ki_pitch = 0
local Kd_pitch = 0.01
local dt = 0.1
local dt1,dt2
local accelerationFactor = 1
local velocityFactor = 1

local spreadYawRange = 2 -- Max spread angle for yaw (in degrees)
local spreadPitchRange = 2 -- Max spread angle for pitch (in degrees)

local cannon = peripheral.find("cbc_cannon_mount")
if not(cannon) then
    cannon = peripheral.find("cbcmf_compact_cannon_mount")
end

print("Input the controlChannel number, default: 500")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 500
end
controlChannel = tonumber(controlChannel)

print("Input the cannon channel number, default: 900")
local cannonChannel = io.read()
if cannonChannel == "" then
    cannonChannel = 900
end
cannonChannel = tonumber(cannonChannel)

print("Input the muzzle velocity number, default: 160")
local projectileSpeed = io.read()
if projectileSpeed == "" then
    projectileSpeed = 160
end
projectileSpeed = tonumber(projectileSpeed)

print("Input the gravity acceleration per tick, default: 0.025")
local g = io.read()
if g == "" then
    g = 0.025
end
g = tonumber(g)

print("Input the drag per tick, default: 0.99")
local cd = io.read()
if cd == "" then
    cd = 0.99
end
cd = tonumber(cd)

print("Enable automatic spread, yes/no, default: yes")
local autoSpread = io.read()
if autoSpread == "yes" then
    autoSpread = true
else
    autoSpread = false
end

print("press enter to assemble cannons")
cannon.assemble()

local function readFriendlyIDs(filename)
    if not fs.exists(filename) then
        print("Friendly IDs file '" .. filename .. "' does not exist. Creating it.")
        local file = fs.open(filename, "w")
        print("Input friendly IDs (player names) separated by commas:")
        local ids = io.read()
        file.write(ids)
        file.close()
    else
        print("Do you want to edit the config? (yes/no),press enter to skip")
        local editChoice = io.read()
        if editChoice == "" then
            editChoice = "no"
        end
        if editChoice:lower() == "yes" then
            if fs.exists(filename) then
                fs.delete(filename)
                print("Friendly IDs file '" .. filename .. "' does not exist. Creating it.")
                local file = fs.open(filename, "w")
                print("Input friendly IDs (player names) separated by commas:")
                local ids = io.read()
                file.write(ids)
                file.close()
            end
        end

        
    end

    
    local file = fs.open(filename, "r")
    local friendlyIDs = {}
    if file then
        local line = file.readLine()
        while line do
            print("Line read: " .. line)  -- Debug print for the line

            -- Split the line by commas and insert each name into the friendlyIDs table
            for name in string.gmatch(line, '([^,]+)') do
                print("Friendly ID (Name): " .. name)  -- Debug print for each name
                table.insert(friendlyIDs, name)  -- Store the player name
            end
            line = file.readLine()  -- Read the next line
        end
        file.close()
    end
    return friendlyIDs
end

-- Function to check if a player ID is friendly
local function isFriendly(playerID)
    for _, friendlyID in ipairs(friendlyIDs) do
        if playerID == friendlyID then
            return true
        end
    end
    return false
end

-- Read friendly IDs from the file
friendlyIDs = readFriendlyIDs(friendlyIDFile)
print("Friendly IDs: " .. textutils.serialize(friendlyIDs)) -- Debug print

if cannon.assemble() then
    print("asseble failed, press enter to contiue")
    io.read()
end

local function PIDController(Kp, Ki, Kd, error, integral, prevError, dt)
    -- Calculate the proportional, integral, and derivative components
    local proportional = Kp * error
    integral = integral + error * dt  -- Accumulate the error for the integral term
    local derivative = (error - prevError) / dt
    
    -- Calculate the PID output
    local output = proportional + (Ki * integral) + (Kd * derivative)

    -- Return the PID output, updated integral, and current error
    return output, integral, error
end

-- Yaw control function using PID
local function yawControl(deltaYaw, currentYaw)
    if math.abs(deltaYaw) then  -- Only adjust if yaw error is significant
        -- PID controller for yaw
        local yawSpeed, yawIntegral, yawPrevError = PIDController(Kp_yaw, Ki_yaw, Kd_yaw, deltaYaw, yawIntegral, yawPrevError, dt)

        -- Constrain the yaw speed to prevent runaway spinning
        yawSpeed = math.max(-256, math.min(256, yawSpeed))

        --print("deltaYaw: " .. deltaYaw)
        --print("yawSpeed: " .. yawSpeed)

        -- Set motor speed based on PID output
        yawMotor.setTargetSpeed(-yawSpeed)
    else
        yawMotor.setTargetSpeed(0)  -- Stop motor if error is too small
    end
end

local function pitchControl(deltaPitch, currentPitch)
    if math.abs(deltaPitch) then  -- Only adjust if yaw error is significant
        -- PID controller for yaw
        local pitchSpeed, pitchIntegral, pitchPrevError = PIDController(Kp_pitch, Ki_pitch, Kd_pitch, deltaPitch, pitchIntegral, pitchPrevError, dt)

        -- Constrain the yaw speed to prevent runaway spinning
        pitchSpeed = math.max(-256, math.min(256, pitchSpeed))

        --print("deltaPitch: " .. deltaPitch)
        --print("pitchSpeed: " .. pitchSpeed)

        -- Set motor speed based on PID output
        pitchMotor.setTargetSpeed(pitchSpeed*8)
    else
        pitchMotor.setTargetSpeed(0)  -- Stop motor if error is too small
    end
end

local function calculateVelocity(pos1, pos2, dt)
    local vx = (pos2[1] - pos1[1]) / dt
    local vy = (pos2[2] - pos1[2]) / dt
    local vz = (pos2[3] - pos1[3]) / dt
    return {x=vx, y=0, z=vz}
end

local function calculateAcceleration(vel1, vel2, dt)
    local ax = (vel2.x - vel1.x) / dt
    local ay = (vel2.y - vel1.y) / dt
    local az = (vel2.z - vel1.z) / dt
    return {x = ax, y = ay, z = az}
end

local function estimatePosition(pos, velocity, acceleration, time)
    local estX = pos.x + velocity.x * velocityFactor * time + 0.5 * acceleration.x * time^2
    local estY = pos.y + velocity.y * velocityFactor * time + 0.5 * acceleration.y * time^2
    local estZ = pos.z + velocity.z * velocityFactor * time + 0.5 * acceleration.z * time^2
    return {x = estX, y = estY, z = estZ}
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

local function applySpread(targetYaw, targetPitch)
    -- Randomly generate a spread value for yaw and pitch
    local yawSpread = (math.random() * 2 - 1) * spreadYawRange
    local pitchSpread = (math.random() * 2 - 1) * spreadPitchRange

    -- Apply the spread to the target angles
    local newYaw = targetYaw + yawSpread
    local newPitch = targetPitch + pitchSpread

    return newYaw, newPitch
end

local function aimCannon(targetPos, targetVel, targetAcc, sourceX, sourceY, sourceZ)
    if sourceX and sourceY and sourceZ then
        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local estimateTime = distance / (projectileSpeed)
        local estimateTime = distance / (projectileSpeed - (10 * estimateTime))
        local estimatedPos = estimatePosition(targetPos, targetVel, targetAcc, estimateTime)

        local dx = estimatedPos.x - sourceX
        local dy = estimatedPos.y - sourceY
        local dz = estimatedPos.z - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        --Adjust pitch based on distance adjustments
        --pitch = pitch + findBestPitch(estimateX, estimateY, estimateZ, sourceX, sourceY, sourceZ, projectileSpeed, g, 0.99, 0.0028, projectileSpeed)

        local shipYaw = math.deg(ship.getYaw())
        if shipYaw < 0 then shipYaw = shipYaw + 360 end
        local shipPitch = math.deg(ship.getPitch())

        local requiredRelativeYaw = yaw - shipYaw
        if requiredRelativeYaw > 180 then
            requiredRelativeYaw = requiredRelativeYaw - 360
        elseif requiredRelativeYaw < -180 then
            requiredRelativeYaw = requiredRelativeYaw + 360
        end

        local yaw, pitch = applySpread(yaw, pitch)

        local requiredRelativeYaw,requiredRelativePitch = findRelativeAngle(yaw,pitch)

        local currentYaw = cannon.getYaw()
        local currentPitch = cannon.getPitch()

        local deltaYaw = (requiredRelativeYaw - currentYaw + 180) % 360 - 180
        local deltaPitch = requiredRelativePitch - currentPitch

        -- Turning and pitch adjustment logic
        parallel.waitForAll(
            function() yawControl(deltaYaw, currentYaw) end,
            function() pitchControl(deltaPitch, currentPitch) end
        )

        lastCurrentYaw = currentYaw
        lastCurrentPitch = currentPitch
    end
end

local function calculateSpeed(velocity)
    return math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
end

local function calculateAcceleration(vel1, vel2, dt)
    local ax = (vel2.x - vel1.x) / dt * accelerationFactor
    local ay = (vel2.y - vel1.y) / dt * accelerationFactor
    local az = (vel2.z - vel1.z) / dt * accelerationFactor
    return {x = ax, y = ay, z = az}
end

local function estimatePosition(pos, velocity, acceleration, time)
    local estX = pos.x + velocity.x * velocityFactor * time + 0.5 * acceleration.x * time^2
    local estY = pos.y + velocity.y * velocityFactor * time + 0.5 * acceleration.y * time^2
    local estZ = pos.z + velocity.z * velocityFactor * time + 0.5 * acceleration.z * time^2
    return {x = estX, y = estY, z = estZ}
end

local function main()
    while true do
        local startTime = os.clock()
        shipPos = ship.getWorldspacePosition()

        -- First scan for players and ships
        local targetScan1 = radar.scanForPlayers(100)
        local shipScan1 = radar.scanForShips(1000) -- Scan for ships (e.g., missiles) within 1000 units

        -- Variables to hold the closest target data
        local closestTarget = nil
        local closestDistance = math.huge
        local targetPos1 = nil
        local targetInfo = nil
        local highestSpeed = 0

        -- Loop through each player detected in the first scan
        for _, player in pairs(targetScan1) do
            if player and player.pos then
                local dx = player.pos[1] - shipPos.x
                local dy = player.pos[2] - shipPos.y
                local dz = player.pos[3] - shipPos.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                -- If this player is closer than the current closest, update the closest target
                if not isFriendly(player.nickname) and distance < closestDistance then
                    closestDistance = distance
                    targetPos1 = player.pos
                    targetInfo = {
                        id = player.id,
                        nickname = player.nickname,
                        pos = targetPos1,
                        distance = distance,
                        type = "player"
                    }
                end
            end
        end

        local firstScanEndTime = os.clock()
        local dt1 = firstScanEndTime - startTime

        -- Loop through each ship detected in the first ship scan
        for _, ship in pairs(shipScan1) do
            if ship and ship.pos then
                local dx = ship.pos.x - shipPos.x
                local dy = ship.pos.y - shipPos.y
                local dz = ship.pos.z - shipPos.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                -- Calculate speed of the ship
                local shipSpeed = calculateSpeed(ship.velocity)

                -- If the ship is moving fast (e.g., a missile), prioritize it
                if shipSpeed > 10 and not isFriendly(ship.id) and distance > 10 then
                    highestSpeed = shipSpeed
                    targetPos1 = ship.pos
                    targetInfo = {
                        id = ship.id,
                        pos = targetPos1,
                        distance = distance,
                        velocity = ship.velocity,
                        speed = shipSpeed,
                        type = "ship"
                    }
                end
            end
        end

        -- Wait for a short period (scanInterval) to perform the second scan


        if targetInfo and targetPos1 then
            -- Perform second scan for both players and ships
            if targetInfo.type == "player" then
                sleep(scanInterval)
                local targetScan2 = radar.scanForPlayers(300)
                local targetPos2 = nil
                for _, player in pairs(targetScan2) do
                    if player and player.pos and player.nickname == targetInfo.nickname then
                        targetPos2 = player.pos
                        break
                    end
                end

                -- If both positions are available, calculate velocity for the player
                if targetPos1 and targetPos2 then
                    targetInfo.pos.x = targetPos2[1]
                    targetInfo.pos.y = targetPos2[2]
                    targetInfo.pos.z = targetPos2[3]
                    targetInfo.velocity = calculateVelocity(targetPos1, targetPos2, scanInterval)
                else
                    targetInfo.velocity = {x=0, y=0, z=0}  -- Default velocity if we cannot calculate it
                end

                if targetInfo.pos and targetInfo.pos.x and targetInfo.velocity then
                    aimCannon(targetInfo.pos, targetInfo.velocity, {x=0,y=0,z=0}, shipPos.x, shipPos.y + 4, shipPos.z)
                else
                    locked = false
                    redstone.setOutput("back",false)
                end
            elseif targetInfo.type == "ship" then
                sleep(scanInterval)

                local shipScan2 = radar.scanForShips(1000)
                local shipPos2, shipVelocity2 = nil, nil

                -- Find the same ship in the second scan based on its ID
                for _, ship in pairs(shipScan2) do
                    if ship.id == targetInfo.id then
                        shipPos2 = ship.pos
                        shipVelocity2 = ship.velocity
                        break
                    end
                end

                local dt2 = os.clock() - firstScanEndTime

                if targetInfo.velocity and shipVelocity2 then
                    -- Calculate acceleration
                    local acceleration = calculateAcceleration(targetInfo.velocity, shipVelocity2, dt2)
                    print("dt2: "..dt2)
                    -- Update velocity for next scan
                    targetInfo.velocity = shipVelocity2

                    -- Aim the cannon considering acceleration
                    aimCannon(targetInfo.pos, targetInfo.velocity, acceleration, shipPos.x, shipPos.y + 4, shipPos.z)
                    locked = true
                else
                    locked = false
                    yawMotor.setTargetSpeed(0)
                    pitchMotor.setTargetSpeed(0)
                end
            else
                locked = false
                redstone.setOutput("back",false)
                yawMotor.setTargetSpeed(0)
                pitchMotor.setTargetSpeed(0)
            end
        else
            locked = false
            redstone.setOutput("back",false)
            yawMotor.setTargetSpeed(0)
            pitchMotor.setTargetSpeed(0)
        end
        os.sleep()
    end
end

local function autoFire()
    while true do
        if locked and auto then
            cannon.fire()
            redstone.setOutput("back",true)
        else
            redstone.setOutput("back",false)
        end
        sleep(0.2)
    end
end

parallel.waitForAny(
    main,
    autoFire
)