-- Grandop chest loadout exporter.
--
-- Scans one inventory and writes only its item array to
-- /generated_loadout_items.json. Directly adjacent chests are also queried by
-- the Command Computer for full item NBT; generic inventory APIs only expose an
-- opaque NBT hash, which is intentionally not exported.
--
-- Usage: loadout_generator [side]

local OUTPUT_PATH = "generated_loadout_items.json"
local side = ...

local function jsonString(value)
    return '"' .. tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t") .. '"'
end

local function writeItems(items)
    local lines = { "[" }
    for index, entry in ipairs(items) do
        local fields = { "\"item\": " .. jsonString(entry.item) }
        if entry.count then table.insert(fields, "\"count\": " .. entry.count) end
        if entry.nbt then table.insert(fields, "\"nbt\": " .. jsonString(entry.nbt)) end
        table.insert(lines, "  { " .. table.concat(fields, ", ") .. " }" .. (index < #items and "," or ""))
    end
    table.insert(lines, "]")
    return table.concat(lines, "\n")
end

local function readValue(text, start)
    while text:sub(start, start):match("%s") do start = start + 1 end
    local first = text:sub(start, start)
    if first == '"' or first == "'" then
        local quote = first
        local index = start + 1
        while index <= #text do
            if text:sub(index, index) == quote and text:sub(index - 1, index - 1) ~= "\\" then
                return text:sub(start, index), index + 1
            end
            index = index + 1
        end
        return nil
    end
    if first == "{" or first == "[" then
        local open, close = first, first == "{" and "}" or "]"
        local depth, quote, index = 0, nil, start
        while index <= #text do
            local character = text:sub(index, index)
            if quote then
                if character == quote and text:sub(index - 1, index - 1) ~= "\\" then quote = nil end
            elseif character == '"' or character == "'" then
                quote = character
            elseif character == open then
                depth = depth + 1
            elseif character == close then
                depth = depth - 1
                if depth == 0 then return text:sub(start, index), index + 1 end
            end
            index = index + 1
        end
        return nil
    end
    local finish = text:find("[,}]", start) or (#text + 1)
    return text:sub(start, finish - 1):gsub("%s+$", ""), finish
end

local function fieldValue(compound, field)
    local start = compound:find(field .. ":")
    if not start then return nil end
    return readValue(compound, start + #field + 1)
end

local function itemCompounds(text)
    local result, depth, quote, start = {}, 0, nil, nil
    for index = 1, #text do
        local character = text:sub(index, index)
        if quote then
            if character == quote and text:sub(index - 1, index - 1) ~= "\\" then quote = nil end
        elseif character == '"' or character == "'" then
            quote = character
        elseif character == "{" then
            depth = depth + 1
            if depth == 1 then start = index end
        elseif character == "}" then
            depth = depth - 1
            if depth == 0 and start then
                table.insert(result, text:sub(start, index))
                start = nil
            end
        end
    end
    return result
end

local function cleanId(value)
    return value and value:gsub('^"', ""):gsub('"$', "")
end

local function directChestNbt(expected)
    if not commands or not commands.getBlockPosition then return {} end
    local x, y, z = commands.getBlockPosition()
    local positions = {
        { x + 1, y, z }, { x - 1, y, z }, { x, y + 1, z },
        { x, y - 1, z }, { x, y, z + 1 }, { x, y, z - 1 },
    }
    local best, bestMatches = {}, 0

    for _, position in ipairs(positions) do
        local ok, output = commands.exec("data get block " .. position[1] .. " " .. position[2] .. " " .. position[3] .. " Items")
        if ok and output then
            local found, matches = {}, 0
            for _, compound in ipairs(itemCompounds(table.concat(output, " "))) do
                local slot = tonumber((fieldValue(compound, "Slot") or ""):match("%-?%d+"))
                local id = cleanId(fieldValue(compound, "id"))
                local tag = fieldValue(compound, "tag")
                if slot and id and expected[slot + 1] and expected[slot + 1].item == id then
                    found[slot + 1] = tag
                    matches = matches + 1
                end
            end
            if matches > bestMatches then best, bestMatches = found, matches end
        end
    end
    return best
end

local function scanInventory(inv)
    local entries, expected = {}, {}
    local slots = inv.list()
    local slotNumbers = {}
    for slot in pairs(slots) do table.insert(slotNumbers, slot) end
    table.sort(slotNumbers)

    for _, slot in ipairs(slotNumbers) do
        local detail = inv.getItemDetail(slot, true)
        if detail and detail.name then
            local entry = { item = detail.name }
            if detail.count and detail.count > 1 then entry.count = detail.count end
            expected[slot] = entry
            table.insert(entries, { slot = slot, entry = entry })
        end
    end

    local nbtBySlot = directChestNbt(expected)
    local result = {}
    for _, value in ipairs(entries) do
        value.entry.nbt = nbtBySlot[value.slot]
        table.insert(result, value.entry)
    end
    return result
end

local inventory
if side and side ~= "" then
    inventory = peripheral.wrap(side)
    if not inventory then error("No inventory on side: " .. side) end
else
    inventory = peripheral.find("inventory")
    if not inventory then error("No chest/inventory peripheral found!") end
end

if type(inventory.list) ~= "function" or type(inventory.getItemDetail) ~= "function" then
    error("Selected peripheral does not support the inventory API.")
end

local items = scanInventory(inventory)
local file = fs.open(OUTPUT_PATH, "w")
if not file then error("Could not write " .. OUTPUT_PATH) end
file.write(writeItems(items))
file.close()

print("Exported " .. #items .. " item entries to /" .. OUTPUT_PATH)
print("Direct-chest NBT is included when the Command Computer can read it.")
