-- Standalone VMod schematic spawn test.
-- Spawns a tank right next to the command computer (or at explicit
-- coordinates), auto-names the ship, and prints the full command feedback
-- of every load/place attempt so failures are visible instead of silent.
--
-- Usage: test_schematic_spawn [schematicName] [x y z]
--   schematicName defaults to "chinu"; x/y/z default to a spot a few blocks
--   from the computer. VMod 0.1.3 notes (empirically confirmed): the load
--   name must include the .vschem extension, `schem place` REQUIRES the
--   parenthesized rotation argument between position and name, and both
--   commands report FAILED even when they succeed — only the radar
--   detection at the end is authoritative.

local args = { ... }
local schematicName = args[1] or "chinu"
local explicitX, explicitY, explicitZ = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])

local radar = peripheral.find("sp_radar")
if not radar then error("sp_radar not found") end
if not commands.getBlockPosition then error("commands.getBlockPosition unavailable") end

local function printFeedback(label, ok, output)
    print(label .. ": " .. (ok and "ok" or "FAILED"))
    if type(output) == "table" then
        for _, line in ipairs(output) do
            print("  > " .. tostring(line))
        end
    elseif output ~= nil then
        print("  > " .. tostring(output))
    end
end

local function run(label, cmd)
    local ok, output = commands.exec(cmd)
    printFeedback(label .. " [" .. cmd .. "]", ok, output)
    return ok, output
end

--================================================================--
-- Where are we, and is the radar alive?
--================================================================--
local cx, cy, cz = commands.getBlockPosition()
print(("Computer at X:%d Y:%d Z:%d"):format(cx, cy, cz))

local tx = explicitX or (cx + 6)
local ty = explicitY or (cy + 1)
local tz = explicitZ or (cz + 6)
print(("Target: X:%d Y:%d Z:%d"):format(tx, ty, tz))

print("Radar scan 64 range: " .. #(radar.scanForShips(64) or {}) .. " ships")
print("Radar scan 9999 range: " .. #(radar.scanForShips(9999) or {}) .. " ships")

local function shipsNear(ships, x, z, radius)
    local result = {}
    for _, ship in ipairs(ships or {}) do
        local dx, dz = ship.pos.x - x, ship.pos.z - z
        if dx * dx + dz * dz <= radius * radius then
            table.insert(result, ship)
        end
    end
    return result
end

local function newShips(oldList, newList)
    local found = {}
    for _, new in ipairs(newList or {}) do
        local seen = false
        for _, old in ipairs(oldList or {}) do
            if old.id == new.id then seen = true break end
        end
        if not seen then table.insert(found, new) end
    end
    return found
end

--================================================================--
-- Load + place attempts
--================================================================--
-- A multi-island schematic becomes several ships: VMod renames every one of
-- them to <shipName><i> (plain concatenation), so we pass a trailing-dash
-- base ("test-chinu-1-") and expect test-chinu-1-0, test-chinu-1-1, ...
local nameVariants = { schematicName .. ".vschem" }
local counter = 0
local placed = nil

for _, loadName in ipairs(nameVariants) do
    counter = counter + 1
    local baseName = "test-" .. schematicName .. "-" .. counter .. "-"

    print(("\n--- Attempt %d: load '%s' ---"):format(counter, loadName))
    run("load", "vmod schem load-from-sever " .. loadName)

    local oldNear = shipsNear(radar.scanForShips(9999), tx, tz, 20)

    -- A chunk loader keeps the target loaded during placement, then is removed.
    commands.exec(("fill %d %d %d %d %d %d vscontrolcraft:chunk_loader"):format(tx, ty, tz, tx, ty, tz))
    sleep(0.5)

    -- VMod 0.1.3 requires the parenthesized rotation argument between
    -- position and name, e.g. (0 0 0).
    run("place", ("vmod schem place %d %d %d (0 0 0) %s"):format(tx, ty, tz, baseName))

    local found = {}
    local deadline = os.clock() + 6
    while os.clock() < deadline do
        sleep(0.5)
        found = newShips(oldNear, shipsNear(radar.scanForShips(9999), tx, tz, 20))
        if #found > 0 then
            -- Ships unfreeze asynchronously; give sibling islands a moment.
            sleep(2)
            found = newShips(oldNear, shipsNear(radar.scanForShips(9999), tx, tz, 20))
            break
        end
    end

    commands.exec(("fill %d %d %d %d %d %d air"):format(tx, ty, tz, tx, ty, tz))

    if #found > 0 then
        placed = { base = baseName, loadName = loadName, ships = found }
        print(("\nDETECTED %d new ship(s) near target:"):format(#found))
        for i, ship in ipairs(found) do
            print(("  [%d] id %s  mass %s"):format(i, tostring(ship.id), tostring(ship.mass)))
        end
        break
    end
    print("No new ship detected for this attempt.")
end

--================================================================--
-- Result
--================================================================--
if placed then
    local hull = placed.ships[1]
    for _, ship in ipairs(placed.ships) do
        if (tonumber(ship.mass) or 0) > (tonumber(hull.mass) or 0) then hull = ship end
    end
    print(("\nSUCCESS: '%s' spawned %d ship(s) using load name '%s'")
        :format(schematicName, #placed.ships, placed.loadName))
    print(("Heaviest island (hull): id %s mass %s")
        :format(tostring(hull.id), tostring(hull.mass)))
    if #placed.ships > 1 then
        print("Multi-island schematic: ships were renamed by VMod to "
            .. placed.base .. "0, " .. placed.base .. "1, ...")
    else
        print("Single-island schematic: ship kept the bare name " .. placed.base)
    end
    print("To remove the test vehicles later (VMod has no delete command):")
    for i = 0, #placed.ships - 1 do
        print(("  vs set-static %s%d true  (then break/remove it)")
            :format(placed.base, i))
    end
    print(("  vs set-static %s true  (single-island fallback)")
        :format(placed.base))
else
    print("\nAll attempts failed. Available 'schem' subcommands according to the server:")
    run("vmod schem", "vmod schem")
    print("Check logs/latest.log for 'Failed to load file' lines for the exact path tried.")
end
