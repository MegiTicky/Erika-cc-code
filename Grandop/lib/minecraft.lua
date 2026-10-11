-- Grandop Minecraft command helpers.
-- Thin wrappers around commands.exec for the operations the systems use most.

local mc = {}

function mc.exec(cmd)
    return commands.exec(cmd)
end

-- Returns true if at least one player of `team` is within `range` of (x, y, z).
function mc.playersInRange(team, x, y, z, range)
    local ok = commands.exec(
        "execute as @a[team=" .. team ..
        ",x=" .. x .. ",y=" .. y .. ",z=" .. z ..
        ",distance=.." .. range .. "] at @s run tag @s add grandop_capture_scan"
    )
    commands.exec("tag @a[tag=grandop_capture_scan] remove grandop_capture_scan")
    return ok
end

-- Returns the number of team members in a capture zone. This includes players
-- and team-assigned entities such as Steve's Army soldiers. The command result
-- is the number of affected entities.
function mc.playersInRangeCount(team, x, y, z, range)
    local ok, _, count = commands.exec(
        "execute as @e[team=" .. team ..
        ",x=" .. x .. ",y=" .. y .. ",z=" .. z ..
        ",distance=.." .. range .. "] at @s run tag @s add grandop_capture_scan"
    )
    commands.exec("tag @e[tag=grandop_capture_scan] remove grandop_capture_scan")
    if not ok then return 0 end
    return tonumber(count) or 0
end

-- Counts only online player entities in a capture zone. Objective diagnostics
-- use this alongside playersInRangeCount to expose non-player team entities.
function mc.playerEntitiesInRangeCount(team, x, y, z, range)
    local ok, _, count = commands.exec(
        "execute as @a[team=" .. team ..
        ",x=" .. x .. ",y=" .. y .. ",z=" .. z ..
        ",distance=.." .. range .. "] at @s run tag @s add grandop_capture_player_scan"
    )
    commands.exec("tag @a[tag=grandop_capture_player_scan] remove grandop_capture_player_scan")
    if not ok then return 0 end
    return tonumber(count) or 0
end

-- Counting helpers. Both accumulate into a hidden fake scoreboard player
-- instead of reading the command result: the result of a forked
-- `execute as <many> run ...` is not a reliable count, and these numbers
-- drive the wave pacing, so correctness matters more than the extra command.
--
-- NOTE: `@e` only matches entities in loaded, ticking chunks — counts
-- silently exclude soldiers in unloaded or non-simulated chunks. Callers
-- that depend on seeing distant entities must forceload their chunks.
local SCAN_OBJECTIVE = "grandop_scan"

function mc.ensureScanObjective()
    commands.exec("/scoreboard objectives add " .. SCAN_OBJECTIVE .. " dummy")
end

local function countBySelector(selector)
    commands.exec("/scoreboard players set #grandop_scan " .. SCAN_OBJECTIVE .. " 0")
    commands.exec("execute as " .. selector
        .. " run scoreboard players add #grandop_scan " .. SCAN_OBJECTIVE .. " 1")
    return mc.scoreboardGet("#grandop_scan", SCAN_OBJECTIVE) or 0
end

-- Counts every living entity on a scoreboard team, world-wide. The siege
-- wave loop uses this as its "no enemy left" check: dead soldiers leave the
-- team with their entity, so the count never includes corpses. Unloaded
-- entities are not counted (see note above).
function mc.entityCount(team)
    return countBySelector("@e[team=" .. team .. "]")
end

-- Same count restricted to a sphere, for the capture zone. Same accumulate
-- pattern so the enemy-count multiplier is trustworthy.
function mc.entitiesNearCount(team, x, y, z, range)
    return countBySelector(("@e[team=%s,x=%d,y=%d,z=%d,distance=..%d]")
        :format(team, x, y, z, range))
end

-- Count living entities matching ANY of the given registry types (e.g.
-- steves_army:enemy_soldier). Unlike team-based counting this never depends
-- on scoreboard team assignment being applied to spawned entities.
local function countBySelectors(selectors)
    commands.exec("/scoreboard players set #grandop_scan " .. SCAN_OBJECTIVE .. " 0")
    for _, selector in ipairs(selectors) do
        commands.exec("execute as " .. selector
            .. " run scoreboard players add #grandop_scan " .. SCAN_OBJECTIVE .. " 1")
    end
    return mc.scoreboardGet("#grandop_scan", SCAN_OBJECTIVE) or 0
end

function mc.entityCountByTypes(types)
    local selectors = {}
    for _, entityType in ipairs(types or {}) do
        table.insert(selectors, "@e[type=" .. entityType .. "]")
    end
    return countBySelectors(selectors)
end

function mc.entitiesNearCountByTypes(types, x, y, z, range)
    local selectors = {}
    for _, entityType in ipairs(types or {}) do
        table.insert(selectors, ("@e[type=%s,x=%d,y=%d,z=%d,distance=..%d]")
            :format(entityType, x, y, z, range))
    end
    return countBySelectors(selectors)
end

-- Returns { {name, x, y, z}, ... } for every player on `team`. Used to aim
-- suppress-area pings at live defender positions.
function mc.playerPositions(team)
    local ok, output = commands.exec(
        "execute as @a[team=" .. team .. "] at @s run data get entity @s Pos"
    )
    if type(output) == "string" then output = { output } end
    local positions = {}
    for _, line in ipairs(output or {}) do
        local name, coords = tostring(line):match("^(%S+) has the following entity data: %[(.-)%]$")
        if name and coords then
            local x, y, z = coords:match("([%-%d%.]+)d*,%s*([%-%d%.]+)d*,%s*([%-%d%.]+)d*")
            if x then
                table.insert(positions, {
                    name = name,
                    x = math.floor(tonumber(x)),
                    y = math.floor(tonumber(y)),
                    z = math.floor(tonumber(z)),
                })
            end
        end
    end
    return positions
end

-- Extra capture units give diminishing returns: 1 unit is normal speed, then
-- the square-root curve applies until the configured multiplier cap.
function mc.captureMultiplier(advantage, maxMultiplier)
    if advantage < 1 then return 0 end
    return math.min(math.sqrt(advantage), maxMultiplier or 2.5)
end

function mc.setSpawnpoint(team, x, y, z)
    commands.exec("/spawnpoint @a[team=" .. team .. "] " .. x .. " " .. y .. " " .. z)
end

function mc.setblock(x, y, z, block)
    commands.exec("/setblock " .. x .. " " .. y .. " " .. z .. " " .. block)
end

function mc.fill(x1, y1, z1, x2, y2, z2, block)
    commands.exec("/fill " .. x1 .. " " .. y1 .. " " .. z1 .. " " .. x2 .. " " .. y2 .. " " .. z2 .. " " .. block)
end

function mc.title(text)
    commands.exec("/title @a title " .. text)
end

function mc.say(text)
    commands.exec("/say " .. text)
end

-- Give an item to a player (or selector).
function mc.give(target, item, count)
    count = count or 1
    if count == 1 then
        commands.exec("/give " .. target .. " " .. item)
    else
        commands.exec("/give " .. target .. " " .. item .. " " .. count)
    end
end

-- Replace a piece of equipment. slot: chest/head/legs/feet. item may include NBT.
function mc.itemReplace(target, slot, item)
    local armorSlot = { chest = "armor.chest", head = "armor.head", legs = "armor.legs", feet = "armor.feet" }
    local s = armorSlot[slot] or slot
    commands.exec("/item replace entity " .. target .. " " .. s .. " with " .. item)
end

function mc.tp(target, x, y, z)
    commands.exec("/tp " .. target .. " " .. x .. " " .. y .. " " .. z)
end

function mc.effect(target, effect, seconds, amplifier)
    commands.exec("/effect give " .. target .. " " .. effect .. " " .. seconds .. " " .. amplifier)
end

-- Scoreboard helpers. get returns nil when the value cannot be read.
function mc.scoreboardGet(player, objective)
    local _, _, value = commands.exec("/scoreboard players get " .. player .. " " .. objective)
    return tonumber(value)
end

function mc.scoreboardSet(player, objective, value)
    commands.exec("/scoreboard players set " .. player .. " " .. objective .. " " .. tostring(value))
end

function mc.scoreboardAdd(player, objective, value)
    commands.exec("/scoreboard players add " .. player .. " " .. objective .. " " .. tostring(value))
end

function mc.scoreboardRemove(player, objective, value)
    commands.exec("/scoreboard players remove " .. player .. " " .. objective .. " " .. tostring(value))
end

return mc
