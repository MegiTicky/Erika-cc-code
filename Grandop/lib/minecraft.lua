-- Grandop Minecraft command helpers.
-- Thin wrappers around commands.exec for the operations the systems use most.

local mc = {}

function mc.exec(cmd)
    return commands.exec(cmd)
end

-- Returns true if at least one player of `team` is within `range` of (x, y, z).
-- Also feeds saturation as a side effect (same as the original detection).
function mc.playersInRange(team, x, y, z, range)
    return commands.exec(
        "execute as @a[team=" .. team ..
        ",x=" .. x .. ",y=" .. y .. ",z=" .. z ..
        ",distance=.." .. range .. "] at @s run effect give @s saturation 1"
    )
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
