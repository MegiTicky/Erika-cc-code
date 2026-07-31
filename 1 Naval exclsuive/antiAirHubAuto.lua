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
function calculateSpeed(velocity)
    return math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
end

AntiAirChannel = askUser("Input the channel number, use 950 for Bogue, 960 Shimakaze, 1020: FV1020",950)
AntiAirChannel = tonumber(AntiAirChannel)
modem.open(AntiAirChannel)

-----------------
--Main function--
-----------------


local projectileSpeed = 180 -- blocks/sec (assume 1 block = 1 m)
local cd = 1
local velocityFactor = 1
local velocityFactor_max, velocityFactor_min = 1.3, 0.9
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
    local terminalVelocity = projectileSpeed * cd^(estimateTime*20)
    local averageVelocity = (terminalVelocity + projectileSpeed) / 2 --assume constant deceleration
    print(averageVelocity)

    rateOfClosure = averageVelocity - rateOfEscape


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
-- Function to get the closest target (players or ships)
local function getClosestTarget()
    local shipScan1 = radar.scanForShips(700)

    -- Variables to hold the closest target data
    local closestTarget = nil
    local closestDistance = math.huge
    local targetPos1 = nil
    local targetInfo = nil
    local targets = {}
    local highestSpeed = 0

    -- Loop through each ship detected in the first ship scan
    local closestDistance = math.huge
    for _, ship in pairs(shipScan1) do
        if ship and ship.pos then
            local dx = ship.pos.x - shipPos.x
            local dy = ship.pos.y - shipPos.y
            local dz = ship.pos.z - shipPos.z
            local CIWSdistance = math.sqrt(dx * dx + dy * dy + dz * dz)

            -- Calculate speed of the ship
            local shipSpeed = calculateSpeed(ship.velocity)

            --calculate distance with ship source

            local dx = ship.pos.x - vesselPos.x
            local dy = ship.pos.y - vesselPos.y
            local dz = ship.pos.z - vesselPos.z
            local shipDistance = math.sqrt(dx * dx + dy * dy + dz * dz)

            --check velocity difference to see if the target is on the same vessel

            local speedError = math.abs(ship.velocity.x - vesselVelocity.x) + math.abs(ship.velocity.y - vesselVelocity.y) + math.abs(ship.velocity.z - vesselVelocity.z)

            -- If the ship is moving fast (e.g., a missile), prioritize it
            if shipSpeed > 4 and (CIWSdistance > 15 or shipDistance > 15 ) and speedError > 2 then
                closestDistance = CIWSdistance
                highestSpeed = shipSpeed
                targetPos1 = ship.pos
                table.insert(targets, {type = "ship", pos = ship.pos, distance = distance, velocity = ship.velocity, id = ship.id})
            end
        end
    end

    table.sort(targets, function(a, b)
        if not a.distance or not b.distance then
            return false -- Safeguard against nil values
        end
    
        if a.type == "ship" and b.type == "player" then
            return true
        elseif a.type == "player" and b.type == "ship" then
            return false
        else
            return a.distance < b.distance
        end
    end)

    return targets
end

local mode = "auto" --Auto targeting mode, target the cloeset target
local redstoneTimeout = 30
local cycleIndex = 1
local lastRedstoneInputTime = os.clock()

local function updateMode()
    if redstone.getInput("top") or (controls and controls.targetSwitch) then
        lastRedstoneInputTime = os.clock()
        mode = "cycle"
    elseif os.clock() - lastRedstoneInputTime > redstoneTimeout then
        mode = "auto"
    end
end

local deltaFactorCon = 0.03
local deltaFactor = deltaFactorCon
function velocityFactorCycle()
    velocityFactor = velocityFactor + deltaFactor
    if velocityFactor > velocityFactor_max  then
        deltaFactor = -deltaFactorCon
    elseif velocityFactor < velocityFactor_min then
        deltaFactor = deltaFactorCon
    end
end

function autoLockOnTarget()
    local startTime = os.clock()
    shipPos = ship.getWorldspacePosition()
    vesselPos = shipPos
    vesselVelocity = ship.getVelocity()

    updateMode()
    local firstScanEndTime = os.clock()
    local dt1 = firstScanEndTime - startTime

    -- Get all targets
    local targets = getClosestTarget()
    print(textutils.serialize(controls))
    -- Determine the target based on the mode
    local targetInfo
    if mode == "auto" then
        -- In auto mode, lock on to the closest target
        if #targets > 0 then
            targetInfo = targets[1]
        end
        cycleIndex = 1
    elseif mode == "cycle" then
        -- In cycle mode, switch to the next target on redstone input
        if redstone.getInput("top") then
            cycleIndex = cycleIndex + 1 -- Cycle to the next target
            print("Cycling to next target.")
        end
        if cycleIndex > #targets then 
            cycleIndex = 1 
        end
        if #targets > 0 then
            targetInfo = targets[cycleIndex]
        end
    end
    local targetCoordainte, distance
    if targetInfo and targetInfo.pos then
        targetCoordainte = predictFuturePosition(targetInfo.pos, targetInfo.velocity, shipPos.x, shipPos.y, shipPos.z)
        distance = calDistance(targetCoordainte.x, targetCoordainte.y, targetCoordainte.z, shipPos.x, shipPos.y, shipPos.z)
    end
    local modemPackage = {
        type = "target_info",
        user = userID,
        target = targetCoordainte,
        convergenceDist = distance,
        isFiring = isFiring,
        pausing = pausing
    }
    print(velocityFactor)
    print(textutils.serialize(modemPackage))
    modem.transmit(AntiAirChannel, 0, modemPackage)
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
                autoLockOnTarget()
                velocityFactorCycle()
            end
            sleep()
        end
    end,
    printing,
    updateUser,
    firing,
    pauseAndReset
)