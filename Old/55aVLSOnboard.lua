local modem = peripheral.wrap("right")
local speaker = peripheral.find("speaker")

local cannons = {}
local controls = {cannonControlMode = "mouseAim"}
local targetInfo = {}

local k = 1
local nilCount = 0
local i = 0
while nilCount < 200 do
    local cannon = peripheral.wrap("cbc_cannon_mount_"..tostring(i))
    if not(cannon) then
        cannon = peripheral.wrap("cbcmf_compact_cannon_mount_"..tostring(i))
    end
    if not(cannon) then
        cannon = peripheral.wrap("createbigcannons:cannon_mount_"..tostring(i))
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

print("Input the muzzle velocity number, default: 240")
local projectileSpeed = io.read()
if projectileSpeed == "" then
    projectileSpeed = 230
end
projectileSpeed = tonumber(projectileSpeed)

print("Input the gravity acceleration per tick, default: 0.05")
local g = io.read()
if g == "" then
    g = 0.05
end
g = tonumber(g)

print("Input the drag per tick, default: 0.99")
local cd = io.read()
if cd == "" then
    cd = 0.995
end
cd = tonumber(cd)

print("Enable automatic spread, yes/no, default: yes")
local autoSpread = io.read()
if autoSpread == "no" then
    autoSpread = false
else
    autoSpread = true
end

print("Enable pitch yaw limiter, yes/no, default: yes")
local limitor = io.read()
if limitor == "no" then
    limitor = false
else
    limitor = true
end
local pitchUpperLimit = -6

print("Do you want to hide cannon?yes/no, default: yes")
local hideCannon = io.read()
if hideCannon == "no" then
    hideCannon = false
else
    hideCannon = true
end


if modem then
    modem.open(cannonChannel)
    modem.open(controlChannel)
end

local function setPitchYaw(targetPitch, targetYaw, useLowPitch, targetDistance)
    local tasks = {}  -- Table to store each cannon's task
    local spreadMultiplier = 1

    -- Increase random variation if low-pitch solution is used or the target is fast
    if useLowPitch then
        -- Scale spreadMultiplier inversely with targetDistance
        -- The closer the target, the higher the spread; further targets have lower spread
        spreadMultiplier = math.max(1, 3 / (targetDistance / 100)) -- Adjust scale factor as needed
        print("spreadMultiplier: "..spreadMultiplier)
    end

    for index, cannon in pairs(cannons) do
        local spreadConstant = 0.3 * spreadMultiplier
        local yawVariation

        local pitchVariation = math.random(-2, 2) * spreadConstant  -- Adjust the range to control the spread
        if targetPitch < 20 then
            yawVariation = math.random(-2, 2) * spreadConstant * 6 -- Adjust the range to control the spread
        elseif targetPitch < 30 then
            yawVariation = math.random(-2, 2) * spreadConstant * 4
        else
            yawVariation = math.random(-2, 2) * spreadConstant * 2
        end

        local adjustedPitch = targetPitch + pitchVariation
        local adjustedYaw = targetYaw + yawVariation

        -- Define the function for this cannon's pitch/yaw adjustment
        local function adjustCannon()
            if autoSpread then
                cannon.setPitch(adjustedPitch)
                cannon.setYaw(adjustedYaw)
            else
                cannon.setPitch(targetPitch)
                cannon.setYaw(targetYaw)
            end
        end

        -- Add this task to the tasks table
        table.insert(tasks, adjustCannon)
    end

    -- Execute all tasks in parallel
    parallel.waitForAll(table.unpack(tasks))
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
    for pitch = 0, 90, 0.05 do -- Iterate over pitch angles
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

    return bestLowPitch, bestHighPitch
end

local function aimCannon(targetPos, targetVel, sourceX, sourceY, sourceZ)
    if sourceX and sourceY and sourceZ then
        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local estimateTime = distance / (projectileSpeed)  -- assuming velocity units and time units need adjustment
        local estimateX = targetPos.x + targetVel.x * estimateTime
        local estimateY = targetPos.y + targetVel.y * estimateTime
        local estimateZ = targetPos.z + targetVel.z * estimateTime
        local targetSpeed = math.sqrt(targetVel.x^2 + targetVel.y^2 + targetVel.z^2)

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        local bestLowPitch, bestHighPitch = findBestPitch(estimateX, estimateY, estimateZ, sourceX, sourceY, sourceZ, projectileSpeed, g, cd, 0.0028, projectileSpeed)
        print("pitch: "..pitch)
        print("bestLowPitch: "..bestLowPitch)
        local requiredRelativeYaw, requiredRelativeLowPitch = findRelativeAngle(yaw, bestLowPitch)
        requiredRelativeLowPitch = requiredRelativeLowPitch + pitch
        local lowPitchAllowed = requiredRelativeLowPitch and (requiredRelativeLowPitch >= 20) -- Ensure low pitch is valid
        local selectedPitch = nil
        local useLowPitch = false

        if targetSpeed > 1 and lowPitchAllowed then
            selectedPitch = bestLowPitch + pitch
            useLowPitch = true
            print("Using Low pitch")
        else
            selectedPitch = bestHighPitch or bestLowPitch
            useLowPitch = false
        end

        local requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw, selectedPitch)
        local currentPitch = cannons[1].getPitch()
        local currentYaw = cannons[1].getYaw()
        print("requiredRelativePitch: "..requiredRelativePitch)
        -- Check if the delta yaw and pitch are greater than 0.1
        if math.abs(currentPitch - (90 - requiredRelativePitch)) > 0.05 or math.abs(currentYaw - (requiredRelativeYaw + 180)) > 0.05 then
            if limitor and controls.cannonControlMode == "mouseAim" then
                -- Limit pitch based on yaw
                if requiredRelativeYaw + 180 >= 290 or requiredRelativeYaw <= 60 + 180 then
                    setPitchYaw(math.min(90 - requiredRelativePitch, 70), requiredRelativeYaw + 180, useLowPitch, distance)
                else
                    setPitchYaw(math.min(90 - requiredRelativePitch, 18), requiredRelativeYaw + 180, useLowPitch, distance)
                end
                local pitchLimit = 18
                if yaw >= 290 or yaw <= 60 then
                    pitchLimit = 70
                end
                if (90 - requiredRelativePitch) > pitchLimit then
                    -- Play warning tone if the pitch is not achievable
                    if speaker then
                        speaker.playSound("minecraft:block.note_block.bass", 1.5, 1.0) -- Example warning tone
                    end
                else
                    if speaker then
                        speaker.playSound("minecraft:block.note_block.pling", 1.5, 5.0) -- Locked tone
                    end
                end
            else
                setPitchYaw(90 - requiredRelativePitch, requiredRelativeYaw + 180, useLowPitch, distance)
            end
        end
    end
end


local function manualCannonControl()
    while true do
        if controls.cannonControlMode == "manual" then
            if controls then
                local pitch = cannons[1].getPitch()
                local yaw = cannons[1].getYaw()
                -- Control yaw and pitch manually with arrow keys
                if controls.cannonUp then
                    -- Increase pitch
                    setPitchYaw(pitch + 2, yaw)
                elseif controls.cannonDown then
                    -- Decrease pitch
                    setPitchYaw(pitch - 2, yaw)
                else
                    
                end
                if controls.cannonLeft then
                    -- Turn left
                    setPitchYaw(pitch, yaw - 2)
                elseif controls.cannonRight then
                    -- Turn right
                    setPitchYaw(pitch, yaw + 2)
                else

                end
            else

            end
            sleep()
        else
            sleep() -- Sleep for a short time if not in manual mode
        end
    end
end

local function setHiddenPosition()
    local tasks = {}  -- Table to store each cannon's task for setting to hidden position

    for index, cannon in pairs(cannons) do
        local function hideCannon()
            cannon.setPitch(90)
            cannon.setYaw(180)
        end
        table.insert(tasks, hideCannon)
    end

    -- Execute all tasks in parallel to hide cannons simultaneously
    parallel.waitForAll(table.unpack(tasks))
end

local function firing()
    while true do
        if controls and controls.fireCannon and controls.cannonControlMode == "mouseAim" then
            print("firing")
            local tasks = {}  -- Initialize tasks table to store firing functions
 
            -- Aim each cannon before firing wa 
            if targetInfo and targetInfo.targetPos and targetInfo.targetVel then
                local source = ship.getWorldspacePosition()
                local sourceX = source.x + 42 * math.cos(ship.getYaw() + math.pi / 2)
                local sourceY = source.y + 1.5
                local sourceZ = source.z + 42 * math.sin(ship.getYaw() + math.pi / 2)
                print("sourceX: "..sourceX)
                print("sourceY: "..sourceY)
                print("sourceZ: "..sourceZ)
 
                aimCannon(targetInfo.targetPos, targetInfo.targetVel, sourceX, sourceY, sourceZ)
            end
 
            -- Create a task for each cannon to fire
            for index, cannon in pairs(cannons) do
                local function fireCannon()
                    cannon.fire()
                end
                table.insert(tasks, fireCannon)
            end
            redstone.setOutput("top",true)
 
            --sleep to ensure that all cannon is adjusted
            sleep(0.1)
 
            -- Execute all cannon fire tasks simultaneously
            parallel.waitForAll(table.unpack(tasks))
 
            --sleep again to ensure all cannon fired
            sleep(0.1)
            redstone.setOutput("top",false)

            -- Set cannons back to hidden position after firing
            if hideCannon then
                setHiddenPosition()
            end
        else
            -- If not firing, keep all cannons in hidden position
            if controls.cannonControlMode == "mouseAim" and hideCannon then
                setHiddenPosition()
            end
            if controls and controls.cannonControlMode == "manual" and controls.fireCannon then
                local tasks = {} 
                for index, cannon in pairs(cannons) do
                    local function fireCannon()
                        cannon.fire()
                    end
                    table.insert(tasks, fireCannon)
                end
                parallel.waitForAll(table.unpack(tasks))
            end
            if targetInfo and targetInfo.targetPos and targetInfo.targetVel then
                --print(textutils.serialize(targetInfo))
                local source = ship.getWorldspacePosition()
                local sourceX = source.x + 42 * math.cos(ship.getYaw() + math.pi / 2)
                local sourceY = source.y + 1.5
                local sourceZ = source.z + 42 * math.sin(ship.getYaw() + math.pi / 2)

                local dx = targetInfo.targetPos.x - sourceX
                local dy = targetInfo.targetPos.y - sourceY
                local dz = targetInfo.targetPos.z - sourceZ
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                local estimateTime = distance / (projectileSpeed)  -- assuming velocity units and time units need adjustment
                local estimateX = targetInfo.targetPos.x + targetInfo.targetVel.x * estimateTime
                local estimateY = targetInfo.targetPos.y + targetInfo.targetVel.y * estimateTime
                local estimateZ = targetInfo.targetPos.z + targetInfo.targetVel.z * estimateTime

                local dx = estimateX - sourceX
                local dy = estimateY - sourceY
                local dz = estimateZ - sourceZ

                local horizontalDistance = math.sqrt(dx * dx + dz * dz)
                local pitch = math.deg(math.atan2(dy, horizontalDistance))

                local yaw = math.deg(math.atan2(-dx, dz))
                yaw = (yaw + 180) % 360
                pitch =  findBestPitch(estimateX, estimateY, estimateZ, sourceX, sourceY, sourceZ, projectileSpeed, g, cd, 0.0028, projectileSpeed)

                local shipRoll = math.deg(ship.getRoll())
                local shipYaw = math.deg(ship.getYaw()) - 90
                if shipYaw < 0 then shipYaw = shipYaw + 360 end
                local shipPitch = math.deg(ship.getPitch())

                local requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw, pitch)
                local currentPitch = cannons[1].getPitch()
                local currentYaw = cannons[1].getYaw()

                if limitor and controls.cannonControlMode == "mouseAim" then
                    -- Limit pitch based on yaw
                    local pitchLimit = 18
                    if yaw >= 290 or yaw <= 60 then
                        pitchLimit = 70
                    end
                    if (90 - requiredRelativePitch) > pitchLimit then
                        -- Play warning tone if the pitch is not achievable
                        if speaker and targetInfo and targetInfo.targetPos and targetInfo.targetVel then
                            speaker.playSound("minecraft:block.note_block.bass", 1.5, 1.0) -- Example warning tone
                        end
                    else
                        if speaker and targetInfo and targetInfo.targetPos and targetInfo.targetVel then
                            print("Target locked line 423")
                            speaker.playSound("minecraft:block.note_block.pling", 1.5, 5.0) -- Locked tone
                        end
                    end
                end
            end
        end
        sleep()
    end
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == cannonChannel then
                targetInfo = message
            elseif channel == controlChannel then
                controls = message
            end
        else
            sleep()
        end
    end
end

local function main()
    while true do
        if not(hideCannon) then
            local source = ship.getWorldspacePosition()
            local sourceX = source.x
            local sourceY = source.y + 1.5
            local sourceZ = source.z

            -- Calculate cannon position offset based on ship's yaw
            local yawRadians = ship.getYaw() + 0.5 * math.pi
            local cannonOffsetX = 42 * math.cos(yawRadians)  -- 84 blocks ahead in the x direction
            local cannonOffsetZ = 42 * math.sin(yawRadians)  -- 84 blocks ahead in the z direction

            -- Adjust source coordinates to the actual cannon position
            local adjustedSourceX = sourceX + cannonOffsetX
            local adjustedSourceZ = sourceZ + cannonOffsetZ
            --print("adjustedSourceX: "..adjustedSourceX)
            --print("adjustedSourceZ: "..adjustedSourceZ)

            if targetInfo and targetInfo.targetPos and targetInfo.targetVel and controls.cannonControlMode == "mouseAim" then
                aimCannon(targetInfo.targetPos, targetInfo.targetVel, adjustedSourceX, sourceY, adjustedSourceZ)
            end
        end
        sleep()
    end
end


parallel.waitForAny(
    manualCannonControl,
    modemMessage,
    firing,
    main
)
