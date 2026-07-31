modem = peripheral.wrap("right")
camera = peripheral.find("camera")

local cannons = {}
local controls = {cannonControlMode = "mouseAim"}
local recievedInfo = nil
-----------------
--Configuration--
-----------------
--japanese 25mm autocannon
local MAG_SIZE    = 15       -- rounds per magazine
local RELOAD_TIME = 2       -- seconds
local FIRE_RPM    = 140       -- rounds per minute
FIRE_RPM = FIRE_RPM * 2
local elevateTraverseSpeed = 20 -- angle per 0.5s
-- spread settings (AREA at convergence plane, in blocks^2)
local spreadArea = 20
-- basllist
local projectileSpeed = 120  -- blocks/sec (set to your gun's muzzle velocity)
local g = 0.005
local cd = 0.999999

local cannons = {}
local k = 1
local nilCount = 0
local i = 0
peripheralfindFound = false
while nilCount < 200 do
    local cannon = peripheral.wrap("createbigcannons:cannon_mount_"..tostring(i)) or peripheral.wrap("cbcmodernwarfare:compact_mount_"..tostring(i))
    if not(cannon) and not(peripheralfindFound) then
        cannon = peripheral.find("createbigcannons:cannon_mount") or peripheral.find("cbcmodernwarfare:compact_mount")
        peripheralfindFound = true
    end

    if cannon then
        cannon.assemble()
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

function askUser(prompt, defaultValue)
    print(prompt .. " (default (press enter to use default): " .. defaultValue .. ")")
    print("Automatically applying default value in 10sec")

    local timer = os.startTimer(10)  -- Set a timer for 10 seconds
    local input = ""
    local isTimedOut = false

    -- Start a loop to capture user input or wait for the timer
    while true do
        local event, param = os.pullEvent()
        if event == "timer" and param == timer then
            -- Timer expired, apply the default value
            isTimedOut = true
            break
        elseif event == "char" then
            print(param)
            -- Capture character input from the user
            input = input .. param
        elseif event == "key" then
            --print(param)
            if param == 257 then  -- Enter key (key code 28)
                -- User pressed Enter
                print("enter pressed")
                break
            end
        end
    end

    -- If the input is empty and timed out, return the default value
    if isTimedOut or input == "" then
        return defaultValue
    else
        return input
    end
end

AntiAirChannel = askUser("Input the channel number. 960 is for port side of shimakaze",960)
AntiAirChannel = tonumber(AntiAirChannel)

function errorCheck()
    while not(modem) do
        print("Modem not connected, retrying")
        modem = peripheral.find("modem")
        sleep(0.5)
    end
    while not(camera) do
        print("Camera not connected")
        camera = peripheral.find("camera")
        sleep(0.5)
    end
end
errorCheck()

modem.open(AntiAirChannel)

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

    for pitch = 0, 70, 0.15 do -- Iterate over pitch angles
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

    --prioritize the low-angle solution
    return bestLowPitch
end

local requiredRelativeYaw, requiredRelativePitch, absYaw, absPitch
local function aimCannonDirect(targetPos, source)
    local dx = targetPos.x - source.x
    local dy = targetPos.y - source.y
    local dz = targetPos.z - source.z

    local x = math.sqrt(dx*dx + dz*dz)  -- horizontal distance
    local y = dy                         -- vertical difference

    -- yaw geometric
    local yaw = math.deg(math.atan2(-dx, dz))
    yaw = (yaw + 180) % 360
    --geometric pitch
    local horizontalDistance = math.sqrt(dx * dx + dz * dz)
    local pitch = math.deg(math.atan2(dy, horizontalDistance))
    -- ballistic pitch
    local ballisticPitch = findBestPitch(targetPos.x, targetPos.y, targetPos.z, source.x, source.y, source.z, projectileSpeed, g, cd, 0.0028, projectileSpeed)
    --print("ballisticPitch: "..ballisticPitch)
    if pitch > 60 then
        pitch = pitch
    else
        pitch = pitch + ballisticPitch
    end

    requiredRelativeYaw, requiredRelativePitch = findRelativeAngle(yaw, pitch)
    return requiredRelativeYaw, requiredRelativePitch, yaw, pitch
end


math.randomseed(os.epoch("utc"))
local wasFiring = false
local cannonSpread = {} -- [i] = {yawOff=..., pitchOff=...}

local function moveCannon(yaw, pitch, firing, convDist)
    firing = (firing == true)
    convDist = convDist or 300
    if convDist < 1 then convDist = 1 end

    -- roll per-cannon spread ONCE when firing starts
    if firing then
        local r = math.sqrt(spreadArea / math.pi)
        for i = 1, #cannons do
            local a = math.random() * 2 * math.pi
            local rr = r * math.sqrt(math.random())
            local ox = rr * math.cos(a)
            local oy = rr * math.sin(a)
            cannonSpread[i] = {
                yawOff   = math.deg(ox / convDist),
                pitchOff = math.deg(oy / convDist)
            }
        end
    elseif not firing then
        cannonSpread = {}
    end

    local tasks = {}  -- Table to store tasks for parallel execution

    for i, cannon in ipairs(cannons) do
        local task = function()
            local cy = cannon.getYaw()
            local cp = cannon.getPitch()

            local off = cannonSpread[i]
            local targetYaw   = yaw   + ((firing and off) and off.yawOff or 0)
            local targetPitch = pitch + ((firing and off) and off.pitchOff or 0)

            -- delta yaw (wrap to -180..180 so it turns the short way)
            local dy = (targetYaw - cy + 180) % 360 - 180
            local dp = targetPitch - cp

            -- clamp each move to max 20 degrees
            if dy > elevateTraverseSpeed then dy = elevateTraverseSpeed elseif dy < -elevateTraverseSpeed then dy = -elevateTraverseSpeed end
            if dp > elevateTraverseSpeed then dp = elevateTraverseSpeed elseif dp < -elevateTraverseSpeed then dp = -elevateTraverseSpeed end

            cannon.setYaw(cy + dy)
            cannon.setPitch(cp + dp)
        end

        -- Add the task to the tasks table
        table.insert(tasks, task)
    end

    -- Run all cannon movement tasks in parallel
    parallel.waitForAny(table.unpack(tasks))
end

-- Function to simulate random reload time
local function getRandomReloadTime(baseReloadTime)
    local randomOffset = math.random() * 1 - 0.5  -- Random value between -0.5 and 0.5
    return baseReloadTime + randomOffset
end

-- Internal fire state
local roundsLeft = MAG_SIZE
local nextShotAt = 0          -- ms epoch when the next shot is allowed
local reloadUntil = 0         -- ms epoch when reload completes
local lastReloadTime = RELOAD_TIME

local function nowMs()
    return os.epoch("utc")
end

local FIRE_SIDE = "front"
-- state
local magEndAt = 0        -- ms epoch when current magazine "runs out"
local reloadUntil = 0     -- ms epoch when reload completes
local wasTrigger = false

-- Function to handle firing
local function fireCannons(trigger)
    trigger = (trigger == true)
    local t = nowMs()

    -- map desired FIRE_RPM to analog strength (your mechanic)
    local redstoneSignal = math.floor(15 * (FIRE_RPM / 300))
    if redstoneSignal < 1 then redstoneSignal = 1 end
    if redstoneSignal > 15 then redstoneSignal = 15 end

    -- trigger released: stop firing + reset state
    if not trigger then
        redstone.setAnalogOutput(FIRE_SIDE, 0)
        wasTrigger = false
        magEndAt = 0
        return
    end

    -- if currently reloading, keep output off
    if t < reloadUntil then
        redstone.setAnalogOutput(FIRE_SIDE, 0)
        return
    end

    -- start a new magazine timing when trigger is first pressed
    if not wasTrigger then
        local magDurationMs = math.floor((MAG_SIZE / FIRE_RPM) * 60000)
        if magDurationMs < 1 then magDurationMs = 1 end
        magEndAt = t + magDurationMs
        wasTrigger = true
    end

    -- magazine empty -> start reload, output off
    if t >= magEndAt then
        -- Use random reload time variation
        reloadUntil = t + math.floor(getRandomReloadTime(RELOAD_TIME) * 1000)
        redstone.setAnalogOutput(FIRE_SIDE, 0)
        wasTrigger = false
        magEndAt = 0
        return
    end

    -- FIRE: hold analog output; gun handles actual ROF based on strength
    redstone.setAnalogOutput(FIRE_SIDE, redstoneSignal)
end
safe = true
local function safetyCheck()
    local MAG = 10
    local gunLength = 2
    local THRESH = MAG - 1  -- your rule
    local notHit = 0
    while true do
        if absYaw and absPitch then
            camera.setClipRange(MAG)
            local cameraPos = camera.getCameraPosition()
            camera.setYaw(requiredRelativeYaw)
            camera.setPitch(requiredRelativePitch)

            -- convert yaw/pitch (degrees) to direction vector of length MAG
            local yawRad   = math.rad(absYaw)
            local pitchRad = math.rad(absPitch)

            local cx = math.cos(pitchRad)
            local vx = math.sin(yawRad) * cx
            local vy = math.sin(pitchRad)
            local vz = -math.cos(yawRad) * cx

            gx, gy, gz = vx * gunLength, vy * gunLength, vz * gunLength
            vx, vy, vz = vx * MAG, vy * MAG, vz * MAG

            local hitResult = camera.raycast(
                cameraPos.x + gx, cameraPos.y + gy + 0 , cameraPos.z + gz,
                cameraPos.x + vx, cameraPos.y + vy + 0, cameraPos.z + vz
            )

            -- default safe unless a close obstacle is hit
            if not hitResult then
                notHit = notHit + 1
                if notHit > 5 then
                    safe = true
                end
            else
                -- expected structure: hitResult.hit.x/y/z
                local hit = hitResult.hit
                if hit and hit.x and hit.y and hit.z then
                    local dx = hit.x - cameraPos.x
                    local dy = hit.y - cameraPos.y
                    local dz = hit.z - cameraPos.z
                    local d = math.sqrt(dx*dx + dy*dy + dz*dz)

                    safe = (d > THRESH)
                else
                    -- if structure differs, be conservative
                    safe = false
                end
                notHit = 0
            end

            --print("safe=", tostring(safe), " hit=", textutils.serialize(hitResult))
        end
        sleep(0.1)
    end
end
reseted = false
local function pauseHandler()
    if not reseted then
        reseted = true

        -- for all cannons
        for _, cannon in ipairs(cannons) do
            local currentYaw = cannon.getYaw()

            -- normalize yaw into [0, 360)
            local yaw = currentYaw % 360

            -- nearest straight angle among 0/90/180/270
            local snapped = math.floor((yaw + 45) / 90) * 90
            if snapped >= 360 then snapped = 0 end

            cannon.setYaw(snapped)
            cannon.setPitch(15)
        end
    end
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == AntiAirChannel then
                recievedInfo = message
            end
        else
            sleep()
        end
    end
end

parallel.waitForAny(
    function()
        while true do
            if recievedInfo and recievedInfo.pausing then
                pauseHandler()
                redstone.setAnalogOutput(FIRE_SIDE, 0)
            elseif recievedInfo and recievedInfo.target and recievedInfo.target.x and not recievedInfo.pausing then
                local computerPos = camera.getCameraPosition()
                requiredRelativeYaw, requiredRelativePitch, absYaw, absPitch = aimCannonDirect(recievedInfo.target, computerPos)

                moveCannon(requiredRelativeYaw, requiredRelativePitch, recievedInfo.isFiring, recievedInfo.convergenceDist)

                if safe then
                    fireCannons(recievedInfo.isFiring)
                else
                    redstone.setAnalogOutput(FIRE_SIDE, 0) -- better than setOutput if you're using analog firing
                end
                reseted = false
            else
                redstone.setAnalogOutput(FIRE_SIDE, 0)
                -- print("No targetInfo")
            end
            sleep()
        end
    end,
    modemMessage,
    safetyCheck
)