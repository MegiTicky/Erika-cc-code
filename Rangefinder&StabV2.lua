radar = peripheral.find("sp_radar")

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
cannons[1].assemble()

-- Cooldown variables
local cooldownTime = 0.3  -- Cooldown time in seconds
local lastTriggerTime = 0  -- Time when the script was last triggered
local verticalSensitivity = 0.5
redstoneSides = {
    laserRangeFinder = "front",
    cannonUpInput = "top",
    cannonDownInput = "bottom"
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

local function yawPitchToLookVec(yawDeg, pitchDeg)
    local yaw = math.rad(yawDeg)
    local pitch = math.rad(pitchDeg)

    local x = math.sin(yaw) * math.cos(pitch)
    local y = math.sin(pitch)
    local z = -math.cos(yaw) * math.cos(pitch)

    return { x = x, y = y, z = z }
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

local projectileSpeed = askUser("Enter the projectileSpeed","240")
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
if enableVerticalStablizer and pitchMotor then
    print("pitch motor operational, vertical stab on")
else
    print("pitch motor offline, vertical stab are off")
    enableVerticalStablizer = false
end

if enableVerticalStablizer then
    verticalDriveRPM = askUser("enter the vertical drive maximum RPM","7.4")
    verticalMaxAngularVelocity = verticalDriveRPM / 60 * 360 / 8
end
local vm

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

local function findBestPitch(distance, initialVelocity, g, cd, c_est, projectileSpeed)
    function calculateRange(angle, u, cd, g, c_est, projectileSpeed)
        local radians = math.rad(angle)
        local u = projectileSpeed / 20
        local part1 = u * math.cos(radians) / math.log(cd)
        local part2 = ((g * cd) / (g * cd + (1 - cd) * u * math.sin(radians))) ^ (2 + c_est * projectileSpeed * math.sin(radians)) - 1
        local XR = part1 * part2
        return XR
    end
    local bestLowPitch = nil
    local bestHighPitch = nil
    local bestLowDistance = math.huge
    local bestHighDistance = math.huge
    local targetDistance = distance

    for pitch = 0, 30, 0.01 do
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

local function aimCannonDirect(targetPos, source)
    local dx = targetPos.x - source.x
    local dy = targetPos.y - source.y
    local dz = targetPos.z - source.z

    -- yaw geometric
    local yaw = math.deg(math.atan2(-dx, dz))
    yaw = (yaw + 180) % 360
    --geometric pitch
    local horizontalDistance = math.sqrt(dx * dx + dz * dz)
    local pitch = math.deg(math.atan2(dy, horizontalDistance))
    -- ballistic pitch
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local ballisticPitch = findBestPitch(distance, projectileSpeed, g, cd, 0.0028, projectileSpeed)
    --print("ballisticPitch: "..ballisticPitch)
    if pitch > 60 then
        pitch = pitch
    else
        pitch = pitch + ballisticPitch
    end
    print("pitch: "..pitch.." yaw: "..yaw)
    requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw, pitch)

    return requiredRelativeYaw, requiredRelativePitch, yaw, pitch
end

local function laserRangeFinderMain()
    while true do
        if enableLaserRangeFinder then
            local currentTime = os.clock()

            if currentTime - lastTriggerTime >= cooldownTime then
                if redstone.getInput(redstoneSides.laserRangeFinder) then
                    local cannonPitch = cannons[1].getPitch()
                    local shipPos = ship.getWorldspacePosition()
                    local shipYawDeg = math.deg(getYaw())

                    print("Cannon Pitch: " .. cannonPitch .. ", Yaw: " .. shipYawDeg)

                    if radar then
                        local targets = radar.scanForShips(2000)

                        local lv = yawPitchToLookVec(shipYawDeg, cannonPitch)
                        local lvLen = math.sqrt(lv.x * lv.x + lv.y * lv.y + lv.z * lv.z)

                        local rx, ry, rz = shipPos.x + lv.x * 30, shipPos.y + lv.y * 30, shipPos.z + lv.z * 30
                        print(rx,ry,rz)

                        if lvLen ~= 0 then
                            local lnx, lny, lnz = lv.x / lvLen, lv.y / lvLen, lv.z / lvLen
                            local coneCos = math.cos(math.rad(10))

                            local bestScore = -math.huge
                            local bestDist = nil
                            local bestTarget = nil

                            for _, target in ipairs(targets) do
                                if target.pos and target.velocity
                                    and target.pos.x and target.pos.y and target.pos.z
                                    and target.velocity.x and target.velocity.y and target.velocity.z then

                                    local dx = target.pos.x - shipPos.x
                                    local dy = target.pos.y - shipPos.y
                                    local dz = target.pos.z - shipPos.z

                                    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

                                    if dist > 50 then
                                        local ndx, ndy, ndz = dx / dist, dy / dist, dz / dist
                                        local cosAng = ndx * lnx + ndy * lny + ndz * lnz
                                        --print("Distance > 50")
                                        print(cosAng)
                                        if cosAng >= coneCos then
                                            local vx, vy, vz = target.velocity.x, target.velocity.y, target.velocity.z
                                            local speed = math.sqrt(vx * vx + vy * vy + vz * vz)

                                            local centered = (cosAng - coneCos) / (1 - coneCos)
                                            local distScore = 1 / (dist + 1)
                                            local speedScore = (speed > 1) and 1 or 0

                                            local score = centered * 3.0 + distScore * 0.5 + speedScore * 1

                                            if score > bestScore then
                                                bestScore = score
                                                bestDist = dist
                                                bestTarget = target
                                            end
                                        end
                                    end
                                end
                            end

                            if bestTarget then
                                print("target distance: " .. bestDist)
                                local requiredRelativeYaw, requiredRelativePitch, yaw, pitch = aimCannonDirect(bestTarget.pos, shipPos)
                                setPitchYaw(requiredRelativePitch, localCannonYaw)
                            else
                                print("No valid target in cone")
                            end
                        else
                            print("Invalid look vector")
                        end
                    else
                        print("No radar detected")
                    end

                    lastTriggerTime = currentTime
                end
            end
        end
        sleep()
    end
end

--
--Vertical stab
--
lastLoopTime = os.clock()
lastPitch = math.deg(getPitch())
globalPitch = shipPitch + localCannonPitch
local globalYaw, requiredLocalPitch, localCannonYaw
pitchMotor = peripheral.find("Create_RotationSpeedController")
sleep(0.2)

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
            --print("deltaPitch: "..deltaPitch)
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
            --print(string.format("PitchVel=%.2f | UserInput=%.2f | StabilizerOut=%.2f | Final=%.2f | currentTargetPitch=%.2f", 
              --  pitchAngularVelocity, cannonInput, stabilizerOutput, finalCommand, currentTargetPitch))
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

parallel.waitForAny(
    laserRangeFinderMain,
    verticalStabilizerMain
)