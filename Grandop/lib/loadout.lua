-- Grandop loadout module.
-- Loads class kits and repair kits from external per-mission JSON files and
-- applies them through commands. See data/loadouts/*.json for the format.

local json = grandopRequire("lib.json")

local loadout = {}

-- cache of loaded data files
local cache = {}

local ARMOR_SLOTS = {
    chest = "armor.chest",
    head  = "armor.head",
    legs  = "armor.legs",
    feet  = "armor.feet",
}

--- Load (and cache) a loadout data file. Returns the table or nil if missing.
function loadout.load(path)
    if cache[path] then return cache[path] end
    local data = json.load(path)
    if data then cache[path] = data end
    return data
end

function loadout.getClass(data, className)
    return data and data.classes and data.classes[className] or nil
end

function loadout.classNames(data)
    local names = {}
    if data and data.classes then
        for name in pairs(data.classes) do
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

-- Build the full item string (item + NBT) for a structured entry.
local function buildItem(entry)
    local item = entry.item
    if entry.nbt then
        local nbt = entry.nbt
        if nbt:sub(1, 1) ~= "{" then nbt = "{" .. nbt .. "}" end
        return item .. nbt
    end
    return item
end

-- Apply one entry to a target. `target` may be a player name or a selector.
local function applyEntry(target, entry)
    if entry.give == false then return end
    if type(entry) == "string" then
        commands.exec("/give " .. target .. " " .. entry)
        return
    end
    if type(entry) ~= "table" then return end

    if entry.cmd then
        -- Raw command; substitute the player where marked.
        local cmd = entry.cmd
        if target then
            cmd = cmd:gsub("%%s", target):gsub("@p", target)
        end
        commands.exec(cmd)
        return
    end

    if entry.slot then
        local slot = ARMOR_SLOTS[entry.slot]
        if slot then
            commands.exec("/item replace entity " .. target .. " " .. slot .. " with " .. buildItem(entry))
            return
        end
    end

    local count = entry.count or 1
    if count == 1 then
        commands.exec("/give " .. target .. " " .. buildItem(entry))
    else
        commands.exec("/give " .. target .. " " .. buildItem(entry) .. " " .. count)
    end
end

-- Apply every item of a class kit to a target.
function loadout.applyClass(data, className, target)
    local cls = loadout.getClass(data, className)
    if not cls then return false end
    for _, entry in ipairs(cls.items or {}) do
        applyEntry(target, entry)
    end
    return true
end

-- Apply the repair kit to a target.
function loadout.applyRepairKit(data, target)
    for _, entry in ipairs(data.repair_kits or {}) do
        if type(entry) == "table" and entry.item then
            local count = entry.count or 1
            if count == 1 then
                commands.exec("/give " .. target .. " " .. entry.item)
            else
                commands.exec("/give " .. target .. " " .. entry.item .. " " .. count)
            end
        end
    end
end

-- Cooldown tracking (per class, shared across the process).
local cooldowns = {}

function loadout.isReady(data, className, nowSeconds)
    local cls = loadout.getClass(data, className)
    if not cls then return false end
    local last = cooldowns[className] or 0
    return (nowSeconds - last) >= (cls.cooldown or 0)
end

function loadout.markUsed(className, nowSeconds)
    cooldowns[className] = nowSeconds
end

function loadout.secondsLeft(data, className, nowSeconds)
    local cls = loadout.getClass(data, className)
    if not cls then return 0 end
    local last = cooldowns[className] or 0
    return math.max(0, (cls.cooldown or 0) - (nowSeconds - last))
end

return loadout
