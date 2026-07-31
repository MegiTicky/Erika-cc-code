local modem = peripheral.wrap("right")

local cannons = {}
local controls = {cannonControlMode = "mouseAim"}
local targetInfo = {}

local cannons[1] = peripheral.wrap("back")
local cannons[2] = peripheral.wrap("front")

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

print("Input the muzzle velocity number, default: 350")
local projectileSpeed = io.read()
if projectileSpeed == "" then
    projectileSpeed = 350
end
projectileSpeed = tonumber(projectileSpeed)

print("Input the gravity acceleration per tick, default: 0.04")
local g = io.read()
if g == "" then
    g = 0.04
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
if autoSpread == "no" then
    autoSpread = false
else
    autoSpread = true
end

print("Enable Pitch limiter, yes/no, default: no")
local pitchLimit = io.read()
if pitchLimit == "yes" then
    pitchLimit = true
else
    pitchLimit = false
end
local pitchUpperLimit = -6

cannons[1].assemble()
cannons[2].assemble()

if modem then
    modem.open(cannonChannel)
    modem.open(controlChannel)
end

local function setPitchYaw(targetPitch, targetYaw)
    for index, cannon in pairs(cannons) do
        local spreadConstant
        if targetPitch < 30 then
            spreadConstant = 0.5
        else
            spreadConstant = 0.5
        end
        local pitchVariation = math.random(-2, 2) * spreadConstant  -- Adjust the range to control the spread
        local yawVariation = math.random(-2, 2) * spreadConstant  -- Adjust the range to control the spread

        local adjustedPitch = targetPitch + pitchVariation
        local adjustedYaw = targetYaw + yawVariation

        if autoSpread then
            cannon.setPitch(adjustedPitch)
            cannon.setYaw(adjustedYaw)
            print("Cannon " .. index .. " set to pitch: " .. adjustedPitch .. " and yaw: " .. adjustedYaw)
        else
            cannon.setPitch(targetPitch)
            cannon.setYaw(targetYaw)
            print("Cannon " .. index .. " set to uniform pitch: " .. targetPitch .. " and yaw: " .. targetYaw)
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

    -- If the target is within 830 blocks, prioritize the low-angle solution
    if targetDistance <= 830 then
        return bestLowPitch or bestLowPitch
    else
        return bestHighPitch or bestLowPitch
    end
end

local function aimCannon(targetPos, targetVel, sourceX, sourceY, sourceZ)
    if sourceX and sourceY and sourceZ then
        local dx = targetPos.x - sourceX
        local dy = targetPos.y - sourceY
        local dz = targetPos.z - sourceZ
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)


        local estimateTime = distance / (120)  -- assuming velocity units and time units need adjustment
        local estimateX = targetPos.x + targetVel.x * estimateTime
        local estimateY = targetPos.y + targetVel.y * estimateTime
        local estimateZ = targetPos.z + targetVel.z * estimateTime

        local dx = estimateX - sourceX
        local dy = estimateY - sourceY
        local dz = estimateZ - sourceZ

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360
        pitch = pitch + findBestPitch(estimateX, estimateY, estimateZ, sourceX, sourceY, sourceZ, projectileSpeed, g, cd, 0.0028, projectileSpeed)

        local shipRoll = math.deg(ship.getRoll())
        local shipYaw = math.deg(ship.getYaw()) - 90
        if shipYaw < 0 then shipYaw = shipYaw + 360 end
        local shipPitch = math.deg(ship.getPitch())

        local requiredRelativeYaw = yaw - shipYaw
        if requiredRelativeYaw > 180 then
            requiredRelativeYaw = requiredRelativeYaw - 360
        elseif requiredRelativeYaw < -180 then
            requiredRelativeYaw = requiredRelativeYaw + 360
        end
        local requiredRelativeYaw,requiredRelativePitch = findRelativeAngle(yaw,pitch)
        if pitchLimit then
            setPitchYaw(math.min(requiredRelativePitch,pitchUpperLimit),requiredRelativeYaw)
        else
            setPitchYaw(requiredRelativePitch,requiredRelativeYaw)
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
                    cannons[1].setPitch(pitch + 2)
                    cannons[2].setPitch(pitch + 2)
                elseif controls.cannonDown then
                    -- Decrease pitch
                    cannons[1].setPitch(pitch - 2)
                    cannons[2].setPitch(pitch - 2)
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

local function firing()
    while true do
        if controls then
            if controls.fireCannon then
                for index, cannon in pairs(cannons) do
                    cannon.fire()
					redstone.setOutput("top",true)
                    print("Cannon " .. index .. " FIRING ")
                end
			else
				redstone.setOutput("top",false)
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
        local source = ship.getWorldspacePosition()
        local sourceX = source.x
        local sourceY = source.y + 1.5
        local sourceZ = source.z
        if targetInfo and targetInfo.targetPos and targetInfo.targetVel and controls.cannonControlMode == "mouseAim" then
            aimCannon(targetInfo.targetPos,targetInfo.targetVel,sourceX,sourceY,sourceZ)
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
