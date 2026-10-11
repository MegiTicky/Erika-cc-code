-- Grandop siege wave spawner.
--
-- Spawns enemy assault squads at lane positions generated around the
-- objective (distance + bearing, snapped to the surface with the heightmap,
-- same trick as lib/steves_army spawnRing) and orders each squad to attack
-- the objective. Squad kits are lifted verbatim from a loadout JSON's
-- spawn-egg entries, so no NBT is authored here.
--
-- Wave pacing keys off "no enemy left": every enemy soldier — callsign
-- squads and squad-less ambushers alike — is auto-assigned to the enemy
-- scoreboard team by the mod at spawn, so mc.entityCount(enemyTeam) is the
-- number of living attackers. A wave is cleared when it reaches 0; a
-- stuck-enemy timeout keeps one wedged soldier from stalling the match.
--
-- The assault director (lib/siege/director.lua) consumes `siege.activeSquads`
-- to run attack/goto-charge/suppress behavior on the squads spawned here.

local mc = grandopRequire("lib.minecraft")
local loadout = grandopRequire("lib.loadout")
local director = grandopRequire("lib.siege.director")

local waves = {}

-- Diagnostics go through ctx.log, not bare print: the event controller wraps
-- print only in its own chunk environment, so print from this loadfile-loaded
-- module reaches the terminal but never the log file (waves produced zero
-- log lines for a full day of sessions). waves.run rebinds this to ctx.log.
local log = print

-- Squad egg item ids the loadout JSON may use (same set as lib/steves_army).
local EGG_ITEM_IDS = {
    ["steves_army:soldier_spawn_egg"] = true,
    ["steves_army:support_spawn_egg"] = true,
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

-- Build role -> {Items:[...]} kit SNBT from the configured loadout class.
local function buildKits(kitCfg)
    local data = loadout.load(kitCfg.source)
    assert(data, "Siege kits: cannot load loadout file " .. tostring(kitCfg.source))
    local cls = loadout.getClass(data, kitCfg.class)
    assert(cls, "Siege kits: loadout class " .. tostring(kitCfg.class) .. " missing")
    local kits = {}
    for _, entry in ipairs(cls.items or {}) do
        if type(entry) == "table" and EGG_ITEM_IDS[entry.item] then
            local itemsSnbt = extractItems(entry.nbt or "")
            if itemsSnbt then
                local role = entry.soldier
                if not role then
                    role = "rifleman"
                    for gun in pairs(MG_GUNS) do
                        if itemsSnbt:find(gun, 1, true) then role = "machine_gunner" break end
                    end
                end
                if not kits[role] then kits[role] = itemsSnbt end
            end
        end
    end
    return kits
end

-- Bearing (degrees clockwise from north) of a lane point relative to the
-- objective, matching the old generated-lane convention (0 = north/-Z,
-- 90 = east/+X). Used for the sector spread and the compass announcements.
local function computeBearing(objective, point)
    local dx = point.x - objective.x
    local dz = point.z - objective.z
    return math.deg(math.atan2(dx, -dz)) % 360
end

local function bearingToCompass(bearingDeg)
    local names = { "north", "north-east", "east", "south-east",
        "south", "south-west", "west", "north-west" }
    local octant = math.floor(((bearingDeg % 360) / 45) + 0.5) % 8
    return names[octant + 1]
end

-- Spawn one soldier at (x, z), snapped to the surface. The heightmap is
-- motion_blocking_no_leaves: plain motion_blocking counts tree leaves as
-- ground and lands soldiers on canopies. `positioned over` refuses unloaded
-- chunks, so failed spawns are retried a few times before the soldier is
-- skipped (trunks still count, so a rare trunk-top spawn remains).
local function spawnAt(cfg, x, z, itemsSnbt, callsign, role)
    local cmd
    if callsign and role == "anti_tank" then
        -- Squad anti-tank: same callsign enrollment as infantry, via the
        -- dedicated enemy-AT squad branch (mod needs the AT-squad patch,
        -- steves_army 0.5.2+; on older jars this syntax is unknown and the
        -- spawn retries fail, so only deploy this with the patch live).
        cmd = ("execute positioned %d 100 %d positioned over motion_blocking_no_leaves run " ..
            "stevesarmy spawn enemy anti_tank squad %s ~ ~ ~ 0 0 %s")
            :format(x, z, callsign, itemsSnbt)
    elseif callsign then
        cmd = ("execute positioned %d 100 %d positioned over motion_blocking_no_leaves run " ..
            "stevesarmy spawn enemy squad %s ~ ~ ~ 0 0 %s")
            :format(x, z, callsign, itemsSnbt)
    else
        -- Ambushers: squad-less on purpose, so they stay excluded from the
        -- squad-based wave-clear check.
        cmd = ("execute positioned %d 100 %d positioned over motion_blocking_no_leaves run " ..
            "stevesarmy spawn enemy anti_tank ~ ~ ~ 0 0 %s")
            :format(x, z, itemsSnbt)
    end
    for attempt = 1, (cfg.spawnRetries or 5) do
        if commands.exec(cmd) then return true end
        sleep(1)
    end
    return false
end

-- Flatten the configured squad composition into a shuffled role list.
local function squadRoles(composition)
    local roles = {}
    for role, count in pairs(composition) do
        for _ = 1, count do table.insert(roles, role) end
    end
    for i = #roles, 2, -1 do
        local j = math.random(i)
        roles[i], roles[j] = roles[j], roles[i]
    end
    return roles
end

-- Pick the lanes a wave attacks from. "sector" concentrates the wave inside
-- one random arc of the lane ring (per-wave width from `widthByWave`,
-- default 180 degrees); "full" uses every lane.
-- Exposed for the desktop unit harness.
function waves.selectLanes(lanes, waveIndex, spreadByWave, widthByWave)
    local spread = (spreadByWave or {})[waveIndex] or "full"
    if spread == "sector" then
        local width = (widthByWave or {})[waveIndex] or 180
        local center = lanes[math.random(#lanes)].bearing
        local picked = {}
        for _, lane in ipairs(lanes) do
            local delta = math.abs((lane.bearing - center + 540) % 360 - 180)
            if delta <= width / 2 then table.insert(picked, lane) end
        end
        return picked, center
    end
    return lanes, nil
end

-- Spawn one squad as a two-rank firing line facing the objective, order it
-- to attack, and register it for the assault director.
--
-- Formation mirrors cc_scripts/cc_battle_deploy.lua: soldiers spaced 3
-- blocks apart along a line perpendicular to the approach axis (with ranks
-- behind for squads larger than one line). The old tight spawn ring jammed
-- 14 soldiers into a couple of blocks, which is where the mod's cover/spacing
-- AI jams at spawn.
local function spawnSquad(cfg, kits, zone, waveIndex, squadIndex, lane)
    local callsign = ("w%d-%d"):format(waveIndex, squadIndex)
    -- Explicit squad creation first, same as the reference script (auto-
    -- create on spawn also works, but the reference is the proven path).
    commands.exec("stevesarmy squad create " .. callsign .. " enemy")
    local laneX, laneZ = lane.x, lane.z
    local roles = squadRoles(cfg.squad)
    local spacing = cfg.spawnSpacing or 3
    local perRank = cfg.spawnPerRank or 7
    -- Axis vectors: (toObj) points from the lane toward the objective,
    -- (along) runs along the firing line; ranks step back along -(toObj).
    local rad = math.rad(lane.bearing)
    local toObjX, toObjZ = -math.sin(rad), math.cos(rad)
    local alongX, alongZ = math.cos(rad), math.sin(rad)
    local spawned = 0
    local idx = 0
    local rankCount = math.ceil(#roles / perRank)
    for rank = 0, rankCount - 1 do
        local inRank = math.min(perRank, #roles - rank * perRank)
        for slot = 0, inRank - 1 do
            idx = idx + 1
            local role = roles[idx]
            local kit = kits[role]
            if not kit then
                log("Siege: no kit for role " .. role .. ", skipping")
            else
                local along = (slot - (inRank - 1) / 2) * spacing
                local x = laneX + alongX * along - toObjX * spacing * rank
                local z = laneZ + alongZ * along - toObjZ * spacing * rank
                if spawnAt(cfg, math.floor(x + 0.5), math.floor(z + 0.5), kit, callsign, role) then
                    spawned = spawned + 1
                end
            end
        end
    end
    -- Let the squad settle before the order, same timing as the reference.
    sleep(1)
    commands.exec(("stevesarmy squad order %s attack %d %d %d")
        :format(callsign, zone.x, zone.y, zone.z))
    log(("Siege: squad %s spawned %d/%d soldiers from lane %s")
        :format(callsign, spawned, #roles, bearingToCompass(lane.bearing)))
    return callsign, spawned
end

local function waitForActive(ctx)
    while ctx.operator.paused and not ctx.operator.shutdown do
        sleep(1)
    end
end

-- Start horn: every defender carries a named goat horn and the FIRST use by
-- anyone starts wave 1. Item tracking follows the proven pattern from
-- lib/respawn/field_gear: byte-identical NBT between give and clear, and a
-- use-count score on a stats criterion.
local START_HORN_OBJECTIVE = "gsiegestart" -- minecraft.used:minecraft.goat_horn
local START_HORN_DEFAULT_LABEL = "Start Wave 1"
local FORCE_HORN_OBJECTIVE = "gsiegenext" -- minecraft.used:minecraft.firework_rocket
local FORCE_HORN_DEFAULT_LABEL = "Force Next Wave"
-- Assigned below; waitForStartHorn strips stale force horns at phase start.
local forceHornSpec

local function startHornSpec(label)
    -- Byte-identical between give and clear so the NBT filter matches.
    return ("minecraft:goat_horn{instrument:\"minecraft:call_goat_horn\",display:{Name:'{\"text\":\"%s\",\"color\":\"gold\",\"italic\":false}'}}")
        :format(label or START_HORN_DEFAULT_LABEL)
end

-- Force-order flare: a plain firework rocket (no explosion NBT, so firing it
-- is a harmless pop) whose use stat rides its own criterion. Deliberately NOT
-- a goat horn: the start horn and the squad-refill horn already share the
-- goat-horn use stat, and two carried horns cannot be told apart by the
-- scoreboard. (The item shipped as a written book with a /trigger button
-- first; the flare rides the same stats-criterion mechanics as the start
-- horn instead. forceHornSpec below is the retired seek-goat-horn, kept only
-- to strip copies from earlier deployments.)
local function forceFlareSpec(label)
    -- Byte-identical between give and clear so the NBT filter matches.
    return ("minecraft:firework_rocket{display:{Name:'{\"text\":\"%s\",\"color\":\"light_purple\",\"italic\":false}',Lore:['{\"text\":\"Fire to call the next wave early\",\"color\":\"gray\",\"italic\":false}']}}")
        :format(label or FORCE_HORN_DEFAULT_LABEL)
end

local function hornUseCount(name, objective)
    local ok, out = commands.exec(("scoreboard players get %s %s"):format(name, objective))
    if not ok or type(out) ~= "table" then return 0 end
    local n = tostring(out[1] or ""):match("has%s+(-?%d+)")
    return tonumber(n) or 0
end

-- Non-destructive presence check; reuses the give spec's NBT so only OUR
-- item counts, never a lookalike (e.g. the squad-refill horn).
local function hasItem(name, itemId, spec)
    local nbt = spec:match("{.*}$")
    if not nbt then return false end
    return commands.exec(("execute if data entity %s Inventory[{id:\"%s\",tag:%s}]")
        :format(name, itemId, nbt)) == true
end

-- Exactly one copy in the inventory: clear every matching copy (NBT-exact,
-- lookalikes are untouched) then hand out one.
local function ensureItem(name, spec)
    commands.exec("clear " .. name .. " " .. spec)
    commands.exec(("give %s %s 1"):format(name, spec))
end

-- Horn blows and flare fires both leave counts behind across phases, so
-- every wait phase starts by zeroing both objectives.
local function zeroHornScores()
    commands.exec("scoreboard players set @a " .. START_HORN_OBJECTIVE .. " 0")
    commands.exec("scoreboard players set @a " .. FORCE_HORN_OBJECTIVE .. " 0")
end

-- Blocks until any defender blows the horn, keeping horns topped up for
-- everyone on the defender team along the way.
local function waitForStartHorn(cfg, ctx)
    local label = cfg.startHorn.label or START_HORN_DEFAULT_LABEL
    local spec = startHornSpec(label)
    local flareSpec = cfg.forceHorn and forceFlareSpec(cfg.forceHorn.label)
    commands.exec("scoreboard objectives add " .. START_HORN_OBJECTIVE
        .. " minecraft.used:minecraft.goat_horn")
    -- Zero stale use scores and strip every horn (copies from previous
    -- sessions and the old label included) so the pre-start inventory holds
    -- exactly one horn: the start horn. Any goat-horn use then means start,
    -- and neither the squad-refill horn nor the retired force horn can
    -- pre-fire the siege.
    zeroHornScores()
    commands.exec("clear @a " .. startHornSpec("Begin the Siege"))
    commands.exec("clear @a " .. spec)
    -- Legacy seek-goat-horn from earlier deployments.
    commands.exec("clear @a " .. forceHornSpec(cfg.forceHorn and cfg.forceHorn.label))
    -- Retired force-order book from earlier deployments.
    commands.exec("clear @a minecraft:written_book{title:\"Force Next Wave\"}")
    mc.title('{"text":"Blow the horn to start wave 1","color":"gold"}')
    log("Siege: waiting for a start horn (" .. label .. ")")
    while not ctx.operator.shutdown do
        waitForActive(ctx)
        if ctx.operator.shutdown then return end
        local players = mc.playerPositions(cfg.defenderTeam)
        for _, p in ipairs(players) do
            if hornUseCount(p.name, START_HORN_OBJECTIVE) > 0 then
                zeroHornScores()
                -- Opens the squad-refill horn (respawn.squadRefill gates on
                -- it) and retires the start horn: its job is done, and it
                -- must never be the horn that skips a wave.
                if cfg.flags then cfg.flags.siegeStarted = true end
                commands.exec("clear @a " .. spec)
                mc.title('{"text":"The siege begins!","color":"red"}')
                log("Siege: start horn blown by " .. p.name)
                return
            elseif not hasItem(p.name, "minecraft:goat_horn", spec) then
                -- Lost horn (death, drop, kit change): strip any stale score
                -- and hand out a fresh copy.
                ensureItem(p.name, spec)
            end
            -- The force flare gets the same top-up as the start horn, so
            -- defenders hold it before wave 1 even begins.
            if flareSpec and not hasItem(p.name, "minecraft:firework_rocket", flareSpec) then
                ensureItem(p.name, flareSpec)
            end
        end
        sleep(1)
    end
end

function forceHornSpec(label)
    return ("minecraft:goat_horn{instrument:\"minecraft:seek_goat_horn\",display:{Name:'{\"text\":\"%s\",\"color\":\"light_purple\",\"italic\":false}'}}")
        :format(label or FORCE_HORN_DEFAULT_LABEL)
end

-- Polls for a force-order flare fired since the wait began, re-issuing lost
-- flares along the way. Returns true when the current wait should be cut
-- short. The flare rides a stats criterion, so unlike a /trigger objective
-- there is nothing to enable — but a flare fired outside a wait also leaves
-- a count behind, which is why each wait zeroes the scores on entry.
local function forceHornReady(cfg, ctx)
    if not cfg.forceHorn then return false end
    local spec = forceFlareSpec(cfg.forceHorn.label)
    local forced = false
    local players = mc.playerPositions(cfg.defenderTeam)
    for _, p in ipairs(players) do
        if hornUseCount(p.name, FORCE_HORN_OBJECTIVE) > 0 then
            forced = true
        elseif not hasItem(p.name, "minecraft:firework_rocket", spec) then
            ensureItem(p.name, spec)
        end
    end
    if forced then
        zeroHornScores()
        mc.title('{"text":"Next wave forced!","color":"gold"}')
        log("Siege: next wave forced")
    end
    return forced
end

local function ensureForceHornObjective(cfg)
    if not cfg.forceHorn then return end
    -- Remove + add: gsiegenext shipped as a goat-horn criterion, then as a
    -- /trigger objective, in earlier deployments. Scores are transient.
    commands.exec("scoreboard objectives remove " .. FORCE_HORN_OBJECTIVE)
    commands.exec("scoreboard objectives add "
        .. FORCE_HORN_OBJECTIVE .. " minecraft.used:minecraft.firework_rocket")
    commands.exec("scoreboard players set @a " .. FORCE_HORN_OBJECTIVE .. " 0")
end

-- Defenders drive the per-wave squad scaling. The mission supplies either a
-- fixed number or a function (lieyu_siege prompts on the computer terminal);
-- with neither, fall back to counting online defenders at wave time.
local function defenderHeadcount(cfg)
    local n = cfg.defenderCount
    if type(n) == "function" then n = n() end
    if type(n) ~= "number" then n = #mc.playerPositions(cfg.defenderTeam) end
    if n < 1 then n = 1 end
    return math.floor(n)
end

-- Forward declaration: runWaves holds the whole wave loop; waves.run wraps
-- it with lane forceloading and cleanup.
local runWaves

function waves.run(siege, ctx)
    log = (ctx and ctx.log) or print
    -- Keep the lane chunks loaded for the whole match: the heightmap snap
    -- (`positioned over`) refuses unloaded chunks, soldiers outside loaded
    -- chunks never tick, and the wipe count cannot see unloaded entities.
    local zone = siege.objective.captureZones[siege.objective.startZone or 1]
    -- Hand-picked lane points (mission config): random generation used to
    -- drop soldiers on roofs and canopies. Bearings for the sector spread
    -- are computed from the objective at startup.
    local lanes = {}
    for _, point in ipairs(siege.lanePoints or {}) do
        table.insert(lanes, {
            x = point.x, z = point.z,
            bearing = computeBearing(zone, point),
        })
    end
    local laneChunks = {}
    for _, lane in ipairs(lanes) do
        table.insert(laneChunks, { x = lane.x, z = lane.z })
        commands.exec(("forceload add %d %d"):format(lane.x, lane.z))
    end
    ensureForceHornObjective(siege)
    sleep(1)

    -- pcall so the forceloads are removed even when a wave errors out;
    -- yielding inside pcall is safe in ComputerCraft (Cobalt).
    local ok, err = pcall(runWaves, siege, ctx, zone, lanes)
    for _, c in ipairs(laneChunks) do
        commands.exec(("forceload remove %d %d"):format(c.x, c.z))
    end
    if not ok then error(err, 0) end
end

function runWaves(siege, ctx, zone, lanes)
    local cfg = siege
    local objective = cfg.objective
    local totalWaves = #(cfg.waveMultiplier or {})
    assert(totalWaves > 0, "Siege config needs waveMultiplier")
    assert(#lanes > 0, "Siege config needs lanePoints")
    local kits = buildKits(cfg.kits)
    for role in pairs(cfg.squad) do
        assert(kits[role], "Siege kits: no " .. role .. " kit found in " .. cfg.kits.class)
    end

    -- A restart after the final wave was already spawned still owes the
    -- defenders their victory.
    local nextWave = ctx.state.flags.siegeNextWave or 1
    if nextWave > totalWaves then
        objective.siegeCleared = true
        return
    end
    -- A restart past wave 1 means the siege already started: reopen the
    -- squad-refill gate without re-running the start horn.
    if nextWave > 1 and cfg.flags then cfg.flags.siegeStarted = true end

    -- Squad counts scale off the defender headcount, resolved by the event
    -- controller before the parallel loops boot (that is where the mission's
    -- terminal prompt fires, with nothing else printing over it).
    local headcount = defenderHeadcount(cfg)
    log(("Siege: scaling waves for %d defenders (squads = defenders x wave multiplier)")
        :format(headcount))

    -- Wave 1 waits for a defender to blow the start horn (mission config
    -- `startHorn`); later waves keep the wipe + breather pacing.
    if nextWave == 1 and cfg.startHorn then
        waitForStartHorn(cfg, ctx)
        if ctx.operator.shutdown then return end
    end

    for wave = nextWave, totalWaves do
        waitForActive(ctx)
        if ctx.operator.shutdown then return end

        -- Pick the attack lanes BEFORE the breather so defenders learn the
        -- direction with the countdown, not when the enemies appear.
        local waveLanes, center = waves.selectLanes(lanes, wave, cfg.spread, cfg.sectorWidth)
        local squadCount = math.ceil(headcount * ((cfg.waveMultiplier or {})[wave] or 1))
        local approach = center
            and ("hostiles massing in the " .. bearingToCompass(center) .. " sector")
            or "hostiles surrounding the objective on all sides"
        -- ASCII dash only: /say sends raw bytes and the server mangles
        -- multi-byte UTF-8 (an em-dash shows as a-umlaut garbage).
        approach = approach .. (squadCount == 1 and " - 1 squad"
            or (" - %d squads"):format(squadCount))

        -- Inter-wave breather with a chat countdown. The "incoming" title
        -- only fires when spawning actually starts (it used to precede the
        -- whole breather, which read like a broken gap).
        local delay = (wave == 1)
            and (cfg.startHorn and 0 or (cfg.graceDelay or 90))
            or (cfg.waveDelay or 30)
        if delay > 0 then
            commands.exec(("/say Wave %d in %d seconds: %s"):format(wave, delay, approach))
            -- A flare fired during the previous wave leaves a stale count;
            -- only flares fired inside a wait may cut it short.
            zeroHornScores()
            local milestones = { [15] = true, [10] = true, [5] = true }
            local deadline = os.epoch("utc") / 1000 + delay
            while true do
                waitForActive(ctx)
                if ctx.operator.shutdown then return end
                if forceHornReady(cfg, ctx) then break end
                local remaining = math.ceil(deadline - os.epoch("utc") / 1000)
                if remaining <= 0 then break end
                if milestones[remaining] then
                    commands.exec(("/say Next wave in %d seconds"):format(remaining))
                end
                sleep(1)
            end
        else
            -- No breather (wave 1 right after the start horn): the approach
            -- line would otherwise never be said.
            commands.exec("/say " .. approach)
        end

        mc.title(('{"text":"Wave %d of %d incoming","color":"gold"}'):format(wave, totalWaves))

        -- Spawn the wave. A squad that spawned nobody is not registered:
        -- ordering a dead callsign only feeds the director noise. Squads
        -- trickle in on `squadSpawnInterval` so defenders fight them as
        -- they arrive instead of facing the whole wave at once.
        local spawned = 0
        local waveSquads = {}
        for j = 1, squadCount do
            waitForActive(ctx)
            local lane = waveLanes[((j - 1) % #waveLanes) + 1]
            local callsign, squadSpawned = spawnSquad(cfg, kits, zone, wave, j, lane)
            spawned = spawned + squadSpawned
            if squadSpawned > 0 then
                table.insert(waveSquads, { callsign = callsign, bearing = lane.bearing })
                table.insert(cfg.activeSquads, { callsign = callsign, bearing = lane.bearing })
            end
            sleep(cfg.squadSpawnInterval or 0.5)
        end
        for _, lane in ipairs(waveLanes) do
            for _ = 1, (cfg.ambushersPerLane or 0) do
                if spawnAt(cfg, lane.x, lane.z, kits.anti_tank, nil) then spawned = spawned + 1 end
            end
        end
        ctx.state.flags.siegeNextWave = wave + 1
        if ctx.checkpoint then ctx.checkpoint("siege wave " .. wave .. " spawned") end
        if spawned == 0 then
            log("Siege: WARNING — wave " .. wave
                .. " spawned no soldiers; check forceload/lane chunks on the server")
        end

        -- Post-spawn verification, counted two independent ways: by entity
        -- type (never depends on scoreboard team assignment) and by team. A
        -- type count of 0 with a non-zero spawn count means the configured
        -- types are wrong; a team count of 0 with a non-zero type count
        -- proves team assignment is not matching spawned enemies.
        local aliveByType = mc.entityCountByTypes(cfg.enemyEntityTypes)
        local aliveByTeam = mc.entityCount(cfg.enemyTeam)
        log(("Siege: wave %d — spawned %d soldiers, alive by type %d, by team %d")
            :format(wave, spawned, aliveByType, aliveByTeam))
        commands.exec(("/say Wave %d deployed: %d hostiles counted"):format(wave, aliveByType))

        -- Wave-clear means the ASSAULT is repelled: every squad registered
        -- for this wave has no living members (parsed from squad info).
        -- Ambushers are deliberately excluded — they are static lane
        -- defenders that never advance, so counting them would block every
        -- wave until defenders hike out to 150m and hunt them down.
        if #waveSquads > 0 then
            local wipeDeadline = os.epoch("utc") / 1000 + (cfg.stuckTimeout or 240)
            zeroHornScores()
            local lastCountLog = 0
            local advanceReason, remaining = "all assault squads wiped", 0
            while true do
                waitForActive(ctx)
                if ctx.operator.shutdown then return end
                if objective.runtimeState and objective.runtimeState.ended then return end
                if forceHornReady(cfg, ctx) then
                    advanceReason = "forced by horn"
                    break
                end
                local squadsAlive = 0
                for _, entry in ipairs(waveSquads) do
                    local _, alive = director.squadSnapshot(entry.callsign)
                    squadsAlive = squadsAlive + alive
                end
                if squadsAlive == 0 then break end
                local now = os.epoch("utc") / 1000
                if now > wipeDeadline then
                    advanceReason = "stuck timeout"
                    remaining = squadsAlive
                    break
                end
                if now >= lastCountLog + 10 then
                    log(("Siege: wave %d pending — %d squad soldiers alive (%d enemies by type)")
                        :format(wave, squadsAlive, mc.entityCountByTypes(cfg.enemyEntityTypes)))
                    lastCountLog = now
                end
                sleep(2)
            end
            if advanceReason == "all assault squads wiped" then
                log("Siege: wave " .. wave .. " advance reason: " .. advanceReason)
            else
                log("Siege: wave " .. wave .. " advance reason: " .. advanceReason
                    .. " — " .. remaining .. " squad soldiers still alive ("
                    .. mc.entityCountByTypes(cfg.enemyEntityTypes) .. " enemies by type)")
                commands.exec(("/say Wave %d advancing early (%s)")
                    :format(wave, advanceReason))
            end
        elseif spawned > 0 then
            log("Siege: WARNING — wave " .. wave .. " spawned " .. spawned
                .. " soldiers but no squads registered (enrollment failed); "
                .. "wave pacing cannot work until this is fixed")
        end

        if wave == totalWaves then
            objective.siegeCleared = true
            mc.title('{"text":"All waves repelled!","color":"green"}')
            if ctx.checkpoint then ctx.checkpoint("siege cleared") end
            return
        end
        mc.title(('{"text":"Wave %d cleared","color":"green"}'):format(wave))
    end
end

return waves
