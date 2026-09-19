-- Grandop squad refill.
-- Every teamed field player carries a goat horn ("Squad Refill").
-- Right-clicking it spends one infantry deployment ticket and calls in a
-- standard NPC squad ~50 blocks from the player, in the direction away from
-- the nearest enemy. The detection machinery mirrors the vehicle destruction
-- marker in lib.respawn.vehicles: a per-player scoreboard objective on the
-- item's use criterion, polled about once a second, with the horn re-issued
-- whenever it is lost.

local stevesArmy = grandopRequire("lib.steves_army")

local squad_refill = {}

local REFILL_OBJECTIVE = "gpsquadrefill" -- minecraft.used:minecraft.goat_horn
local REFILL_DEFAULT_LABEL = "Squad Refill"
local DEFAULT_DISTANCE = 50 -- blocks between the player and the squad center
local REFILL_RING_RADIUS = 3
local SCAN_CACHE_SECONDS = 5
local COMMANDER_SUFFIX = "Commander$"

local function refillItemSpec(label)
    -- Byte-identical between give and clear so the NBT filter matches.
    return ("minecraft:goat_horn{instrument:\"minecraft:ponder_goat_horn\",display:{Name:'{\"text\":\"%s\",\"color\":\"gold\",\"italic\":false}'}}")
        :format(label or REFILL_DEFAULT_LABEL)
end

-- Remove every horn copy from an inventory and zero the score, so a stale
-- click can never call a squad for a player who no longer carries the item.
local function stripRefill(owner, label)
    commands.exec(("scoreboard players set %s %s 0"):format(owner, REFILL_OBJECTIVE))
    commands.exec("clear " .. owner .. " " .. refillItemSpec(label))
end

-- Exactly one horn in the inventory: clear every matching copy (NBT-exact,
-- real goat horns are untouched) then hand out one.
local function ensureRefillItem(owner, label)
    stripRefill(owner, label)
    commands.exec(("give %s %s 1"):format(owner, refillItemSpec(label)))
end

-- Non-destructive presence check. Reuses the give spec's NBT so only OUR
-- horn counts, never a plain goat horn.
local function hasRefill(owner, label)
    local nbt = refillItemSpec(label):match("{.*}$")
    if not nbt then return false end
    return commands.exec(("execute if data entity %s Inventory[{id:\"minecraft:goat_horn\",tag:%s}]")
        :format(owner, nbt)) == true
end

local function refillUseCount(owner)
    local ok, out = commands.exec(("scoreboard players get %s %s"):format(owner, REFILL_OBJECTIVE))
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

local function handleRefill(rc, cfg, label, faction, name, players)
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

-- Per-world and safe to re-add.
function squad_refill.ensureObjective()
    commands.exec("scoreboard objectives add " .. REFILL_OBJECTIVE
        .. " minecraft.used:minecraft.goat_horn")
end

-- One poll tick (same ~1s cadence as the vehicle marker upkeep): re-issue
-- lost horns and turn horn clicks into squad deployments. Missions opt in by
-- defining respawn.squadRefill.
function squad_refill.process(rc)
    if type(rc) ~= "table" or not rc.respawn then return end
    local cfg = rc.cfg or {}
    local label = cfg.label or REFILL_DEFAULT_LABEL
    local players = scanPlayers(rc.radar)
    if not players then return end
    for _, p in ipairs(players) do
        local name = type(p) == "table" and p.nickname or nil
        if name then
            local faction = factionOf(rc.teams, name)
            if faction then
                if refillUseCount(name) > 0 then
                    commands.exec(("scoreboard players set %s %s 0"):format(name, REFILL_OBJECTIVE))
                    -- Only honor clicks while the horn is actually carried: a
                    -- click logged just before dying must not call a squad.
                    if hasRefill(name, label) then
                        handleRefill(rc, cfg, label, faction, name, players)
                    end
                elseif not hasRefill(name, label) then
                    -- Lost horn (death, drop, kit change): strip any stale
                    -- score and hand out a fresh copy, like the tank marker.
                    ensureRefillItem(name, label)
                end
            end
        end
    end
end

return squad_refill
