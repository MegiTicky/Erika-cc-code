radar = peripheral.find("sp_radar")
modem = peripheral.find("modem")
camera = peripheral.find("camera")

targetInfo = { x=0, y=0, z=0 }
convergenceDist = 300
userID = "MegiRicky"
closestPlayerID = nil
pInfo = {}
isFiring = false
pausing = false

-- Auto-convergence settings
local AUTO_SCAN_RANGE = 1500
local AUTO_CONE_DEG   = 6      -- half-angle of lock cone
local AUTO_MIN_DIST   = 100
local AUTO_MAX_DIST   = 1500

--Input sides
--front: fire | left: pause and reset | top/bottom: increase/decrease convergence distance | right: auto convergence & rangefinding | back: update users

function errorCheck()
    while not(radar) do
        print("Radar not connected, retrying, please make sure all peripherals are connected")
        radar = peripheral.find("sp_radar")
        sleep(0.5)
    end
    while not(modem) do
        print("Modem not connected, retrying, please make sure all peripherals are")
        modem = peripheral.find("modem")
        sleep(0.5)
    end
    while not(camera) do
        print("Camera not connected, retrying, please make sure all peripherals are connected")
        camera = peripheral.find("camera")
        sleep(0.5)
    end
    ccvsCorrect = ship and ship.getQuaternion()
    if not ccvsCorrect then
        print("Use mod cc_vs-1.20.1-forge-0.2.2")
        error("Use mod cc_vs-1.20.1-forge-0.2.2")
    end
    local configInfo = radar.getConfigInfo()
    if configInfo.max_entity_search_radius < 1 then
        print("Max player scan search distance is: "..math.floor(configInfo.max_entity_search_radius))
        print("Max ship scan search distance is: "..math.floor(configInfo.max_ship_search_radius))
        print("You might need to increase it in the some peripheral config")
        error("read log")
    end
end
errorCheck()
------------K K 
--Ultility--
------------
function calDistance(x0,y0,z0,x1,y1,z1)
    return math.sqrt( (x0-x1)^2 + (y0-y1)^2 + (z0-z1)^2 )
end
function askUser(prompt, defaultValue)
    print(prompt .. " (default(press enter to use default): " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

AntiAirChannel = askUser("Input the channel number, use 950 for Bogue, 960 Shimakaze, 1020: FV1020",950)
AntiAirChannel = tonumber(AntiAirChannel)
modem.open(AntiAirChannel)

-----------------
--Main function--
-----------------
function scanAndCalTargetCoordinate()
    local playerList = radar.scanForPlayers(200)
    local computerPos = camera.getCameraPosition()

    local minDistance = math.huge
    closestPlayerID = nil
    pInfo = {}

    for _, player in ipairs(playerList) do
        local name = player.nickname
        local pos  = {x=player.pos[1],y=player.pos[2],z=player.pos[3]}
        local lv   = {x=player.look_angle[1], y=player.look_angle[2], z=player.look_angle[3]}

        -- distance ship -> player
        local dx, dy, dz = computerPos.x - pos.x, computerPos.y - pos.y, computerPos.z - pos.z
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

        if dist < minDistance then
            minDistance = dist
            closestPlayerID = name
        end

        if name == userID then
            -- store player info
            pInfo = { nickname = name, pos = pos, lookVector = lv }

            -- normalize look vector
            local len = math.sqrt(lv.x*lv.x + lv.y*lv.y + lv.z*lv.z)
            if len == 0 then len = 1 end  -- avoid divide-by-zero

            local nx, ny, nz = lv.x/len, lv.y/len, lv.z/len

            -- target coordinate at convergence distance
            targetInfo = {
                x = pos.x + nx * convergenceDist,
                y = pos.y + ny * convergenceDist,
                z = pos.z + nz * convergenceDist
            }
        end
    end

    local modemPackage = {
        type = "target_info",
        user = userID,
        target = targetInfo,
        convergenceDist = convergenceDist,
        isFiring = isFiring,
        pausing = pausing
    }
    print(textutils.serialize(modemPackage))
    modem.transmit(AntiAirChannel, 0, modemPackage)
end

local projectileSpeed = 120 -- blocks/sec (assume 1 block = 1 m)
local velocityFactor = 1
local lastTargetPos, lastTargetVelocity, predictedTargetVelocity, predictedTargetAcceleration
local lastTargetAqquireTime = os.clock()
function predictFuturePosition(targetPos, targetVel, sourceX, sourceY, sourceZ)
    local currentTime = os.clock()
    local dt = currentTime - lastTargetAqquireTime

    -- Initialize predictedVelocity & predictedAcceleration if needed
    if not lastTargetPos then
        lastTargetPos = targetPos
        lastTargetVelocity = targetVel
        predictedTargetVelocity = targetVel
        predictedTargetAcceleration = {x = 0, y = 0, z = 0}
        lastTargetAqquireTime = currentTime
    elseif dt >= 0.5 then
        -- Estimate velocity
        predictedTargetVelocity = {
            x = (targetPos.x - lastTargetPos.x) / dt,
            y = (targetPos.y - lastTargetPos.y) / dt,
            z = (targetPos.z - lastTargetPos.z) / dt
        }

        -- Estimate acceleration
        predictedTargetAcceleration = {
            x = (predictedTargetVelocity.x - lastTargetVelocity.x) / dt,
            y = (predictedTargetVelocity.y - lastTargetVelocity.y) / dt,
            z = (predictedTargetVelocity.z - lastTargetVelocity.z) / dt
        }

        -- Update previous values
        lastTargetPos = targetPos
        lastTargetVelocity = predictedTargetVelocity
        lastTargetAqquireTime = currentTime
    end

    -- Compute initial distance to target
    local dx = targetPos.x - sourceX
    local dy = targetPos.y - sourceY
    local dz = targetPos.z - sourceZ
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    local losLength = math.sqrt(dx^2 + dy^2 + dz^2)
    local losUnit = {
        x = dx / losLength,
        y = dy / losLength,
        z = dz / losLength
    }

    -- Compute rate of escape using dot product
    local rateOfEscape = predictedTargetVelocity.x * losUnit.x + predictedTargetVelocity.y * losUnit.y + predictedTargetVelocity.z * losUnit.z
    rateOfClosure = projectileSpeed - rateOfEscape

    -- Get ship's velocity
    local shipVelocity = ship.getVelocity()

    -- Initial estimate for travel time
    local estimateTime = distance / rateOfClosure + 1

    -- Predict future position using velocity and acceleration
    local estimateX = targetPos.x
        + (predictedTargetVelocity.x * velocityFactor - shipVelocity.x) * estimateTime
        + 0.5 * predictedTargetAcceleration.x * estimateTime * estimateTime

    local estimateY = targetPos.y
        + (predictedTargetVelocity.y * velocityFactor - shipVelocity.y) * estimateTime
        + 0.5 * predictedTargetAcceleration.y * estimateTime * estimateTime

    local estimateZ = targetPos.z
        + (predictedTargetVelocity.z * velocityFactor - shipVelocity.z) * estimateTime
        + 0.5 * predictedTargetAcceleration.z * estimateTime * estimateTime

    -- Recalculate distance after initial estimate
    dx = estimateX - sourceX
    dy = estimateY - sourceY
    dz = estimateZ - sourceZ
    distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    -- Refine estimateTime
    estimateTime = distance / rateOfClosure + 0.5

    -- Recompute future position with refined time
    estimateX = targetPos.x
        + (predictedTargetVelocity.x * velocityFactor - shipVelocity.x) * estimateTime
        + 0.5 * predictedTargetAcceleration.x * estimateTime * estimateTime

    estimateY = targetPos.y
        + (predictedTargetVelocity.y * velocityFactor - shipVelocity.y) * estimateTime
        + 0.5 * predictedTargetAcceleration.y * estimateTime * estimateTime

    estimateZ = targetPos.z
        + (predictedTargetVelocity.z * velocityFactor - shipVelocity.z) * estimateTime
        + 0.5 * predictedTargetAcceleration.z * estimateTime * estimateTime

    return {x = estimateX, y = estimateY, z = estimateZ}
end

function autoConvergenceDistLock()
    if not redstone.getInput("right") then return end
    if not (pInfo and pInfo.pos and pInfo.lookVector) then return end

    local ships = radar.scanForShips(AUTO_SCAN_RANGE)
    if not ships or #ships == 0 then return end

    -- normalize player look vector
    local lv = pInfo.lookVector
    local lvLen = math.sqrt(lv.x*lv.x + lv.y*lv.y + lv.z*lv.z)
    if lvLen == 0 then return end
    local lnx, lny, lnz = lv.x/lvLen, lv.y/lvLen, lv.z/lvLen

    local px, py, pz = pInfo.pos.x, pInfo.pos.y, pInfo.pos.z
    local coneCos = math.cos(math.rad(AUTO_CONE_DEG))

    local bestScore = -math.huge
    local bestLeadDist = nil

    for _, ship in ipairs(ships) do
        if ship.pos and ship.velocity
           and ship.pos.x and ship.pos.y and ship.pos.z
           and ship.velocity.x and ship.velocity.y and ship.velocity.z then

            -- current relative vector
            local dx, dy, dz = ship.pos.x - px, ship.pos.y - py, ship.pos.z - pz
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist > 0.001 then
                local ndx, ndy, ndz = dx/dist, dy/dist, dz/dist
                local cosAng = ndx*lnx + ndy*lny + ndz*lnz

                if cosAng >= coneCos then
                    local vx, vy, vz = ship.velocity.x, ship.velocity.y, ship.velocity.z
                    local speed = math.sqrt(vx*vx + vy*vy + vz*vz)

                    -- ----- lead distance -----
                    local t = dist / projectileSpeed
                    local leadPosition = predictFuturePosition(ship.pos, ship.velocity, px, py, pz)

                    local ldx, ldy, ldz = leadPosition.x - px, leadPosition.y- py, leadPosition.z - pz
                    
                    local leadDist = math.sqrt(ldx*ldx + ldy*ldy + ldz*ldz)
                    -- -------------------------

                    -- scoring (same idea, but use leadDist for distance score)
                    local centered = (cosAng - coneCos) / (1 - coneCos)   -- 0..1
                    local distScore = 1 / (leadDist + 1)
                    local speedScore = (speed > 1) and 1 or 0

                    local score = centered * 3.0 + distScore * 2.0 + speedScore * 1.5

                    if score > bestScore then
                        bestScore = score
                        bestLeadDist = leadDist
                    end
                end
            end
        end
    end

    if bestLeadDist then
        convergenceDist = math.floor(bestLeadDist + 0.5)
        convergenceDist = math.max(math.min(convergenceDist, AUTO_MAX_DIST), AUTO_MIN_DIST)
        print("Auto convergenceDist (lead) =", convergenceDist)
    end
end

--------------------
--Controls handler--
--------------------
function updateUser()
    while true do
        if redstone.getInput("back") then
            if closestPlayerID then
                userID = closestPlayerID
            end
        end
        sleep()
    end
end

function updateConvergenceDist()
    local buttonCooldown = false
    while true do
        if buttonCooldown == false then
            if redstone.getInput("top") then
                convergenceDist = convergenceDist + 80
                buttonCooldown = true
            elseif redstone.getInput("bottom") then
                convergenceDist = convergenceDist - 80
                buttonCooldown = true
            end
            convergenceDist = math.max(math.min(convergenceDist,AUTO_MAX_DIST),AUTO_MIN_DIST)
        else
            if not(redstone.getInput("top")) and not(redstone.getInput("bottom")) then
                buttonCooldown = false
            end
        end
        sleep()
    end
end

function pauseAndReset()
    local buttonCooldown = false
    while true do
        if buttonCooldown == false then
            if redstone.getInput("left") then
                if pausing then
                    pausing = false
                else
                    pausing = true
                end
                buttonCooldown = true
            end
            convergenceDist = math.max(math.min(convergenceDist,AUTO_MAX_DIST),AUTO_MIN_DIST)
        else
            if not(redstone.getInput("left")) then
                buttonCooldown = false
            end
        end
        sleep()
    end
end

function firing()
    while true do 
        if redstone.getInput("front") then
            isFiring = true
        else
            isFiring = false
        end
        sleep()
    end
end
--debug
function printing()
    while true do
        --print(textutils.serialize(targetInfo))
        sleep(0.5)
    end
end 

parallel.waitForAny(
    function()
        while true do
            if not pause then
                scanAndCalTargetCoordinate()
            end
            autoConvergenceDistLock()
            sleep()
        end
    end,
    printing,
    updateUser,
    updateConvergenceDist,
    firing,
    pauseAndReset
)