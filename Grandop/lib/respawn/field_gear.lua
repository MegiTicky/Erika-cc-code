-- Grandop field gear.
-- Watches two player-carried items on the same ~1s poll cadence as the
-- vehicle destruction marker, re-issuing them whenever they are lost:
--
--   Squad Refill (goat horn): right-click spends one infantry deployment
--   ticket and calls in a standard NPC squad ~50 blocks from the player,
--   in the direction away from the nearest enemy. Detection is a per-player
--   score on the item's use criterion (gpsquadrefill).
--
--   Reset Menu (written book): the page's button runs /trigger g_tagreset,
--   which hard-resets a stuck respawn session (missing or frozen chat menu,
--   stale grandop_* tags — typically after a relog) without admin help.
--
-- Missions opt in per item by defining respawn.squadRefill and/or
-- respawn.sessionReset.

local stevesArmy = grandopRequire("lib.steves_army")

local field_gear = {}

local REFILL_OBJECTIVE = "gpsquadrefill" -- minecraft.used:minecraft.goat_horn
local REFILL_DEFAULT_LABEL = "Squad Refill"
local DEFAULT_DISTANCE = 50 -- blocks between the player and the squad center
local REFILL_RING_RADIUS = 3
local RESET_OBJECTIVE = "g_tagreset" -- trigger, set by the book's button
local RESET_DEFAULT_LABEL = "Reset Menu"
local SCAN_CACHE_SECONDS = 5
local COMMANDER_SUFFIX = "Commander$"

-- Fallback session sweep for when the book service is not running (the
-- standalone terminal): mirrors book.lua's session state.
local SESSION_TAGS = {
    "grandop_book", "grandop_resp_red", "grandop_resp_blue",
    "grandop_wait_mode", "grandop_wait_class", "grandop_wait_spawn",
    "grandop_wait_tank", "grandop_wait_tank_spawn", "grandop_processing",
}
local SESSION_TRIGGERS = {
    "g_resp_mode", "g_resp_class", "g_resp_spawn",
    "g_resp_tank", "g_resp_tspawn", "g_resp_reset",
}

local function refillItemSpec(label)
    -- Byte-identical between give and clear so the NBT filter matches.
    return ("minecraft:goat_horn{instrument:\"minecraft:ponder_goat_horn\",display:{Name:'{\"text\":\"%s\",\"color\":\"gold\",\"italic\":false}'}}")
        :format(label or REFILL_DEFAULT_LABEL)
end

local function radioItemSpec(label)
    -- Byte-identical between give and clear so the NBT filter matches. The
    -- page button uses the same /trigger mechanism as the chat menus.
    label = label or RESET_DEFAULT_LABEL
    local page = '{"text":"' .. label .. '\\n\\nStuck or missing respawn menu? Press the button for a fresh one.\\n\\n","color":"dark_aqua","extra":[{"text":"[ RESET MENU ]","color":"red","bold":true,"clickEvent":{"action":"run_command","value":"/trigger ' .. RESET_OBJECTIVE .. ' set 1"}}]}'
    return ("minecraft:written_book{title:\"%s\",author:\"GHQ\",display:{Name:'{\"text\":\"%s\",\"color\":\"aqua\",\"italic\":false}'},pages:['%s']}")
        :format(label, label, page)
end

-- Remove every copy of an item from an inventory and zero the matching
-- score, so a stale click can never fire for a player who no longer
-- carries the item.
local function stripItem(owner, objective, itemSpec)
    commands.exec(("scoreboard players set %s %s 0"):format(owner, objective))
    commands.exec("clear " .. owner .. " " .. itemSpec)
end

-- Exactly one copy in the inventory: clear every matching copy (NBT-exact,
-- lookalikes are untouched) then hand out one.
local function ensureItem(owner, objective, itemSpec)
    stripItem(owner, objective, itemSpec)
    commands.exec(("give %s %s 1"):format(owner, itemSpec))
end

-- Non-destructive presence check. Reuses the give spec's NBT so only OUR
-- item counts, never a lookalike.
local function hasItem(owner, itemId, itemSpec)
    local nbt = itemSpec:match("{.*}$")
    if not nbt then return false end
    return commands.exec(("execute if data entity %s Inventory[{id:\"%s\",tag:%s}]")
        :format(owner, itemId, nbt)) == true
end

local function useCount(owner, objective)
    local ok, out = commands.exec(("scoreboard players get %s %s"):format(owner, objective))
    if not ok or type(out) ~= "table" then return 0 end
    local n = tostring(out[1] or ""):match("has%s+(-?%d+)")
    return tonumber(n) or 0
end

-- Scan cache: the vehicle marker upkeep already polls the radar, so keep our
-- own list for a few seconds instead of hitting the peripheral every tick.
local scanCache
local function scanPlayers(radar)
    if not radar then return nil end
    local age = os.epoch("utc") / 1000 - (scanCache and scanCache.at or 0)
    if scanCache and scanCache.list and age < SCAN_CACHE_SECONDS then
        return scanCache.list
    end
    local ok, list = pcall(radar.scanForPlayers, 9999)
    if not ok or type(list) ~= "table" then return scanCache and scanCache.list or nil end
    scanCache = { list = list, at = os.epoch("utc") / 1000 }
    return list
end

-- Resolve a nickname's faction by testing scoreboard team membership for
-- every entry of the mission's teams map (e.g. Red -> japan, Blue -> USMC).
local function factionOf(teams, name)
    for team, faction in pairs(teams or {}) do
        if commands.exec(("execute if entity @a[team=%s,name=\"%s\"]"):format(team, name)) then
            return faction
        end
    end
    return nil
end

local function enemyTeamFor(teams, faction)
    for team, f in pairs(teams or {}) do
        if f ~= faction then return team end
    end
    return nil
end

local function scanPos(players, name)
    for _, p in ipairs(players) do
        if type(p) == "table" and p.nickname == name and type(p.pos) == "table" then
            local x = p.pos[1] or p.pos.x
            local z = p.pos[3] or p.pos.z
            if x and z then return x, z end
        end
    end
    return nil, nil
end

-- Nearest infantry spawn for the faction that still has quota at the current
-- stage. Commander entries (teleport-to-a-player spawns) hold no pool and
-- are skipped.
local function nearestSpawnWithQuota(respawn, faction, stage, px, pz)
    local byFaction = respawn.infantrySpawns and respawn.infantrySpawns[faction]
    local list = byFaction and byFaction[(stage and stage.current) or 1] or {}
    local best, bestD
    for _, spawn in ipairs(list) do
        if type(spawn) == "table" and spawn.name
            and not spawn.name:find(COMMANDER_SUFFIX)
            and (not respawn.canDeploy or respawn.canDeploy(faction, "infantry", spawn.name)) then
            local d = 0
            if px and pz then
                d = (spawn.x - px) * (spawn.x - px) + (spawn.z - pz) * (spawn.z - pz)
            end
            if not bestD or d < bestD then
                best, bestD = spawn, d
            end
        end
    end
    return best
end

-- X/Z offsets from the player at which the squad materializes: `distance`
-- blocks in the direction away from the nearest enemy on the given team.
-- Without a known enemy (or a scan position) the squad rings the player
-- itself.
local function awayOffsets(players, name, enemyTeam, distance, px, pz)
    if not px or not pz or not enemyTeam then return 0, 0 end
    local bestD, ex, ez
    for _, p in ipairs(players) do
        local nick = type(p) == "table" and p.nickname or nil
        if nick and nick ~= name and type(p.pos) == "table"
            and commands.exec(("execute if entity @a[team=%s,name=\"%s\"]"):format(enemyTeam, nick)) then
            local x = p.pos[1] or p.pos.x
            local z = p.pos[3] or p.pos.z
            if x and z then
                local d = (x - px) * (x - px) + (z - pz) * (z - pz)
                if not bestD or d < bestD then
                    bestD, ex, ez = d, x, z
                end
            end
        end
    end
    if not ex then return 0, 0 end
    local dx, dz = ex - px, ez - pz
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 0.001 then return 0, 0 end
    return math.floor(-dx / len * distance + 0.5), math.floor(-dz / len * distance + 0.5)
end

local function handleSquadRefill(rc, cfg, label, faction, name, players)
    local respawn = rc.respawn
    local px, pz = scanPos(players, name)
    local spawn = nearestSpawnWithQuota(respawn, faction, rc.stage, px, pz)
    if not spawn then
        commands.exec(("/tellraw %s {\"text\":\"Respawn quota exhausted\",\"color\":\"red\"}"):format(name))
        return
    end
    local cx, cz = awayOffsets(players, name, enemyTeamFor(rc.teams, faction),
        cfg.distance or DEFAULT_DISTANCE, px, pz)
    local spawned = stevesArmy.spawnSquadmates(name, faction .. ".standard", rc.data,
        REFILL_RING_RADIUS, cx, cz)
    if spawned <= 0 then
        -- The ticket is only spent once soldiers actually appeared.
        if rc.log then rc.log("Squad refill failed for " .. name .. ": no soldiers spawned") end
        commands.exec(("/tellraw %s {\"text\":\"Reinforcement call failed\",\"color\":\"red\"}"):format(name))
        return
    end
    if respawn.consumeDeployment then
        respawn.consumeDeployment(faction, "infantry", spawn.name)
    end
    if rc.checkpoint then rc.checkpoint("squad refill") end
    local dist = math.floor(math.sqrt(cx * cx + cz * cz) + 0.5)
    local where = dist > 0 and (dist .. "m out") or "at your position"
    commands.exec(("/tellraw %s {\"text\":\"Reinforcements inbound: %d soldiers %s\",\"color\":\"green\"}")
        :format(name, spawned, where))
    if rc.log then
        rc.log(("Squad refill: %s (%s) via %s — %d soldiers"):format(name, faction, spawn.name, spawned))
    end
end

-- Unconditional: the target scenario is a player whose session state is
-- broken in a way we cannot classify (missing menu after a relog, stale
-- tags) — wiping everything is always safe here.
local function genericHardReset(name)
    for _, tag in ipairs(SESSION_TAGS) do
        commands.exec("/tag " .. name .. " remove " .. tag)
    end
    for i = 1, 8 do
        commands.exec("/tag " .. name .. " remove grandop_class_" .. i)
        commands.exec("/tag " .. name .. " remove grandop_tank_" .. i)
    end
    for _, objective in ipairs(SESSION_TRIGGERS) do
        commands.exec(("scoreboard players set %s %s 0"):format(name, objective))
        commands.exec(("scoreboard players enable %s %s"):format(name, objective))
    end
    commands.exec(("scoreboard players set %s g_resp_age 0"):format(name))
end

local function processSessionReset(rc, cfg, name)
    local label = cfg.label or RESET_DEFAULT_LABEL
    commands.exec(("scoreboard players enable %s %s"):format(name, RESET_OBJECTIVE))
    if useCount(name, RESET_OBJECTIVE) > 0 then
        commands.exec(("scoreboard players set %s %s 0"):format(name, RESET_OBJECTIVE))
        -- Only honor the click while the book is actually carried.
        if hasItem(name, "minecraft:written_book", radioItemSpec(label)) then
            if rc.hardReset then
                rc.hardReset(name)
            else
                genericHardReset(name)
            end
            commands.exec(("/tellraw %s {\"text\":\"Respawn menu reset\",\"color\":\"green\"}"):format(name))
        end
    elseif not hasItem(name, "minecraft:written_book", radioItemSpec(label)) then
        -- Lost book (death, drop, kit change): strip any stale score and
        -- hand out a fresh copy, like the horn and the tank marker.
        ensureItem(name, RESET_OBJECTIVE, radioItemSpec(label))
    end
end

-- Per-world and safe to re-add.
function field_gear.ensureObjective()
    commands.exec("scoreboard objectives add " .. REFILL_OBJECTIVE
        .. " minecraft.used:minecraft.goat_horn")
    commands.exec("scoreboard objectives add " .. RESET_OBJECTIVE .. " trigger")
end

-- One poll tick (same ~1s cadence as the vehicle marker upkeep): re-issue
-- lost items and turn item use into squad deployments / session resets.
-- Missions opt in by defining respawn.squadRefill and/or respawn.sessionReset.
function field_gear.process(rc)
    if type(rc) ~= "table" or not rc.respawn then return end
    local refillCfg = rc.cfg
    local resetCfg = rc.sessionReset
    if not refillCfg and not resetCfg then return end
    local players = scanPlayers(rc.radar)
    if not players then return end
    for _, p in ipairs(players) do
        local name = type(p) == "table" and p.nickname or nil
        if name then
            local faction = factionOf(rc.teams, name)
            if faction then
                if refillCfg then
                    local label = refillCfg.label or REFILL_DEFAULT_LABEL
                    if useCount(name, REFILL_OBJECTIVE) > 0 then
                        commands.exec(("scoreboard players set %s %s 0"):format(name, REFILL_OBJECTIVE))
                        -- Only honor clicks while the horn is actually
                        -- carried: a click logged just before dying must not
                        -- call a squad.
                        if hasItem(name, "minecraft:goat_horn", refillItemSpec(label)) then
                            handleSquadRefill(rc, refillCfg, label, faction, name, players)
                        end
                    elseif not hasItem(name, "minecraft:goat_horn", refillItemSpec(label)) then
                        -- Lost horn (death, drop, kit change): strip any
                        -- stale score and hand out a fresh copy.
                        ensureItem(name, REFILL_OBJECTIVE, refillItemSpec(label))
                    end
                end
                if resetCfg then
                    processSessionReset(rc, resetCfg, name)
                end
            end
        end
    end
end

return field_gear
