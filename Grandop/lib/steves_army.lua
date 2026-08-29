-- Grandop Steve's Army integration.
-- Spawns squadmates for a deploying player with the /stevesarmy spawn command,
-- replacing manual soldier-spawn-egg placement. The command assigns the player
-- as owner and adds the soldier to their squad and current fire team.

local loadout = grandopRequire("lib.loadout")

local stevesArmy = {}

-- Soldier types accepted by /stevesarmy spawn.
local SOLDIER_TYPES = {
    rifleman = true,
    machine_gunner = true,
}

-- Gun IDs that identify a machine gunner when the egg has no explicit type.
local MG_GUNS = {
    ["ww:m1918a1"] = true, -- BAR
    ["ww:t99"] = true,     -- Type 97 LMG
}

-- Extract the `{Items:[...]}` compound from a spawn egg's NBT string. The egg
-- stores the kit as EntityTag: {Inventory: {Items: [...]}}, which is exactly
-- the SNBT the /stevesarmy spawn [loadout] argument expects.
local function extractItems(nbt)
    local start = nbt:find("{Items:", 1, true)
    if not start then return nil end
    local depth = 0
    local quote
    for i = start, #nbt do
        local c = nbt:sub(i, i)
        if quote then
            if c == quote and nbt:sub(i - 1, i - 1) ~= "\\" then quote = nil end
        elseif c == '"' or c == "'" then
            quote = c
        elseif c == "{" then
            depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then return nbt:sub(start, i) end
        end
    end
    return nil
end

-- Infer the soldier type from its gun when the egg entry has no `soldier` field.
local function inferType(itemsSnbt)
    if not itemsSnbt then return nil end
    for gun in pairs(MG_GUNS) do
        if itemsSnbt:find(gun, 1, true) then return "machine_gunner" end
    end
    return "rifleman"
end

-- Spawn `count` soldiers of `type` in a ring around the target player.
-- Relative coordinates resolve to the player's deployed position, so no
-- explicit coordinates are needed.
local function spawnRing(target, soldierType, itemsSnbt, count)
    local spawned = 0
    for i = 0, count - 1 do
        local angle = (i / count) * 2 * math.pi
        local dx = math.floor(math.cos(angle) * 2 + 0.5)
        local dz = math.floor(math.sin(angle) * 2 + 0.5)
        local cmd = ("execute at %s run stevesarmy spawn %s %s ~%d ~ ~%d 0 0 %s")
            :format(target, soldierType, target, dx, dz, itemsSnbt)
        local ok = commands.exec(cmd)
        if ok then
            spawned = spawned + 1
        else
            print("Squadmate spawn failed: " .. cmd)
        end
    end
    return spawned
end

-- Spawn all squadmates configured in the deploying player's class kit.
-- Returns the number of soldiers spawned.
function stevesArmy.spawnSquadmates(target, className, data)
    local cls = loadout.getClass(data, className)
    if not cls then return 0 end
    local total = 0
    for _, entry in ipairs(cls.items or {}) do
        if type(entry) == "table" and entry.item == "steves_army:soldier_spawn_egg" then
            local itemsSnbt = extractItems(entry.nbt or "")
            if not itemsSnbt then
                print("Squadmate spawn skipped: no Items in egg for " .. className)
            else
                local soldierType = entry.soldier or inferType(itemsSnbt)
                if not SOLDIER_TYPES[soldierType] then soldierType = "rifleman" end
                total = total + spawnRing(target, soldierType, itemsSnbt, entry.count or 1)
            end
        end
    end
    return total
end

return stevesArmy
