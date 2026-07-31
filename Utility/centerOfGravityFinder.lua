local radar = peripheral.find("sp_radar")
local tickInterval = 0.1
local particleType = "minecraft:dust 1 0 0 1" -- 红色粒子

local function getScanDistance(size)
    return math.sqrt(size.x^2 + size.y^2 + size.z^2) * 1.5 + 5
end

local function getNearbyShips()
    local shipPos = ship.getWorldspacePosition()
    local shipSize = ship.getSize()
    local shipMass = ship.getMass()
    local range = getScanDistance(shipSize)
    local detectedShips = radar.scanForShips(range)
    local ships = {}

    -- 自身加入计算
    table.insert(ships, {id = "self", pos = shipPos, mass = shipMass})

    for _, shipData in ipairs(detectedShips) do
        local pos = shipData.pos
        local mass = shipData.mass or 0
        local id = shipData.id or "unknown"
        local dx = math.abs(pos.x - shipPos.x)
        local dy = math.abs(pos.y - shipPos.y)
        local dz = math.abs(pos.z - shipPos.z)
        local distance = math.sqrt(dx^2 + dy^2 + dz^2)
        print("distance: "..distance.." shipSize: "..range)
        -- 放宽边界判断
        if distance <= range and distance >= 0.01 then
            table.insert(ships, {id = id, pos = pos, mass = mass})
        end
    end

    -- 输出调试信息
    print("---- Ships included in CG calculation ----")
    for _, ship in ipairs(ships) do
        print(string.format("ID: %s | Mass: %.1f | Pos: x=%.1f y=%.1f z=%.1f",
            ship.id, ship.mass, ship.pos.x, ship.pos.y, ship.pos.z))
    end

    return ships
end

local function calculateCenterOfGravity(shipList)
    if #shipList == 0 then return nil end

    local sumX, sumY, sumZ, totalMass = 0, 0, 0, 0
    for _, ship in ipairs(shipList) do
        sumX = sumX + ship.pos.x * ship.mass
        sumY = sumY + ship.pos.y * ship.mass
        sumZ = sumZ + ship.pos.z * ship.mass
        totalMass = totalMass + ship.mass
    end

    if totalMass == 0 then return nil end

    return {
        x = sumX / totalMass,
        y = sumY / totalMass,
        z = sumZ / totalMass
    }
end

local function summonParticleAt(pos)
    local cmd = string.format(
        "/particle %s %.2f %.2f %.2f 0 0 0 0 1 force",
        particleType, pos.x, pos.y, pos.z
    )
    commands.exec(cmd)
end

while true do
    local ships = getNearbyShips()
    local cg = calculateCenterOfGravity(ships)
    if cg then
        print(string.format("Resultant CG: x=%.1f y=%.1f z=%.1f", cg.x, cg.y, cg.z))
        summonParticleAt(cg)
    else
        print("No valid ships found")
    end
    sleep(tickInterval)
end
