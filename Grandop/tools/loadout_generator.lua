-- Grandop loadout generator.
--
-- Scans a single inventory peripheral (e.g. a chest) and writes its contents
-- as a class loadout in the per-mission JSON format used by lib/loadout.lua.
--
-- Usage:
--   loadout_generator [output_path] [side]
--
-- The tool is interactive: it prompts for a class name and cooldown, reads the
-- chest contents, and appends the class. Repeat for several classes. Use the
-- special class name "__repair__" to write the repair kit list instead. Items
-- with NBT keep their NBT string so enchantments/special data are preserved
-- when available from getItemDetail.
--
-- Chest contents only record item id + count; the NBT of complex items depends
-- on the inventory API and mod, so verify generated loadouts in game.

package.path = "/?.lua;/?/init.lua;" .. package.path

local json = require("lib.json")

local function ask(prompt, default)
    if default then print(prompt .. " (default: " .. tostring(default) .. ")")
    else print(prompt) end
    local input = io.read()
    if input == "" and default ~= nil then return default end
    return input
end

local function scanChest(inv)
    local entries = {}
    local slots = inv.list()
    local slotNums = {}
    for slot in pairs(slots) do table.insert(slotNums, slot) end
    table.sort(slotNums)

    for _, slot in ipairs(slotNums) do
        local detail = inv.getItemDetail(slot, true)
        if detail and detail.name then
            local entry = { item = detail.name }
            if detail.count and detail.count > 1 then entry.count = detail.count end
            if type(detail.nbt) == "string" and #detail.nbt > 0 then
                entry.nbt = detail.nbt
            end
            table.insert(entries, entry)
        end
    end
    return entries
end

local outputPath = arg[1] or "data/loadouts/generated.json"
local side = arg[2]

local inv
if side then
    inv = peripheral.wrap(side)
    if not inv then error("No inventory on side: " .. side) end
else
    inv = peripheral.find("inventory")
    if not inv then error("No chest/inventory peripheral found!") end
end

local data = json.load(outputPath) or { classes = {}, repair_kits = {} }

while true do
    print("\n=== Loadout generator ===")
    print("Current output: " .. outputPath)
    print("Enter class name, '__repair__' for the repair kit, or 'done' to save and quit.")
    io.write("Class name: ")
    local className = io.read()
    if className == "done" or className == "quit" then break end

    local items = scanChest(inv)
    print("Read " .. #items .. " item entries from the chest.")

    if className == "__repair__" then
        data.repair_kits = items
        print("Repair kit updated.")
    else
        local cooldown = tonumber(ask("Cooldown (seconds)", "0")) or 0
        data.classes[className] = { cooldown = cooldown, items = items }
        print("Class '" .. className .. "' updated with cooldown " .. cooldown .. "s.")
    end
end

if json.save(outputPath, data) then
    print("\nSaved loadout to " .. outputPath)
else
    print("\nFailed to save " .. outputPath)
end
