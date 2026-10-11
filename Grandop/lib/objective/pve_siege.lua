-- Grandop PVE siege objective engine.
--
-- A single defended zone: enemy soldiers (scoreboard team `attackTeam`,
-- i.e. `steves_army_enemy`) capture it simply by standing inside; player
-- defenders can neither capture nor slow the capture — the only defense is
-- keeping enemies out of the radius. When the zone holds no enemies the
-- progress HOLDS (no decay): players only need to wipe each push.
--
-- The wave spawner (lib/siege/waves.lua) drives the assault and sets
-- `mcfg.siegeCleared` once the last wave is wiped — that is the defender
-- win. Losing works like any capture: score crossing the threshold ends
-- the match for the attackers.
--
-- Skeleton, visuals, and persistence follow lib/objective/staged_capture.lua.

local mc = grandopRequire("lib.minecraft")
local engine = {}

local function validate(mcfg)
    assert(mcfg.captureZones and #mcfg.captureZones > 0, "Mission needs captureZones")
    assert(mcfg.attackTeam, "Mission needs attackTeam")
    assert(mcfg.defenseTeam, "Mission needs defenseTeam")
end

local function initBossbar(mcfg)
    commands.exec("/bossbar remove " .. tostring(mcfg.bossbarId))
    commands.exec('/bossbar add ' .. tostring(mcfg.bossbarId) .. ' "Objective under siege"')
    commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " max " .. tostring(mcfg.capture.maxValue or 100))
    commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " value 0")
    commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " style progress")
    commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " color red")
    commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " players @a")
end

function engine.run(mcfg)
    validate(mcfg)

    local capture = mcfg.capture or {}
    local radius = capture.radius or 40
    local interval = capture.updateInterval or 0.5
    local threshold = capture.threshold or 1000
    local maxCaptureMultiplier = capture.maxCaptureMultiplier or 2.5
    local scoreChange = capture.scoreChange or 3

    local zones = mcfg.captureZones
    local zone = zones[mcfg.startZone or 1]

    local restored = mcfg.runtimeState or {}
    local state = {
        score = restored.score or 0,
        ended = restored.ended or false,
        winner = restored.winner,
        mission = mcfg,
    }

    local function saveRuntimeState()
        mcfg.runtimeState = {
            score = state.score,
            ended = state.ended,
            winner = state.winner,
        }
    end
    saveRuntimeState()
    local hooks = mcfg.hooks or {}

    -- Live enemy strength on the sidebar: a second fake-player row
    -- ("Enemies") in the same objective that already shows the respawn pool
    -- ("SiegeSpawn"), since the sidebar can display only one objective.
    -- Declared here because gameEnd below clears that row; a declaration
    -- after gameEnd would leave the reference bound to a nil global and
    -- crash the whole event the moment a match ends.
    local displayObjective = capture.displayObjective or "Troops_Strength"

    local function updateBossbar()
        local barId = tostring(mcfg.bossbarId)
        local maxValue = capture.maxValue or 100
        local progress = math.floor(math.max(0, math.min(threshold, state.score)) * maxValue / threshold)
        commands.exec("/bossbar set " .. barId .. " value " .. tostring(progress))
        local color = state.contested and "red" or "white"
        commands.exec("/bossbar set " .. barId .. " color " .. color)
    end

    local function gameEnd(winner, reason)
        state.ended = true
        state.winner = winner
        saveRuntimeState()
        if mcfg.checkpoint then mcfg.checkpoint("objective ended") end
        if hooks.onGameEnd then hooks.onGameEnd(state) end
        local color = winner == mcfg.attackTeam and "red" or "blue"
        mc.title('{"text":"' .. tostring(winner) .. ' wins!","color":"' .. color .. '"}')
        commands.exec("/scoreboard players set Enemies "
            .. displayObjective .. " 0")
        print("Game ended: " .. tostring(reason))
    end

    -- Keep every defender's spawnpoint pinned to the waiting room, exactly
    -- like staged_capture does for both teams. Defense team only: the
    -- attack team is the mod's enemy team and must never get a spawnpoint.
    local function refreshSpawns()
        local faction = mcfg.teamFactions and mcfg.teamFactions[mcfg.defenseTeam]
        local areas = faction and mcfg.stagingAreas and mcfg.stagingAreas[faction]
        local area = areas and (areas[1] or areas.default)
        if area then
            mc.setSpawnpoint(mcfg.defenseTeam, area.x, area.y, area.z)
        end
    end

    -- Objective marker
    mc.ensureScanObjective()
    mc.setblock(zone.x, zone.y, zone.z, "air")
    mc.setblock(zone.x, zone.y, zone.z, "minecraft:beacon")
    if capture.netheriteBase then
        mc.fill(zone.x - 1, zone.y - 1, zone.z - 1, zone.x + 1, zone.y - 1, zone.z + 1, "minecraft:netherite_block")
    end

    initBossbar(mcfg)
    updateBossbar()

    -- Live enemy strength on the sidebar: a second fake-player row
    -- ("Enemies") in the same objective that already shows the respawn pool
    -- ("SiegeSpawn"), since the sidebar can display only one objective.
    commands.exec("/scoreboard players set Enemies " .. displayObjective .. " 0")

    local lastBossbarPlayerRefresh = 0
    local nextGlow = 0
    local nextEnemyDisplay = 0

    -- Main loop
    while not state.ended and not (mcfg.operator and mcfg.operator.shutdown) do
        if mcfg.operator and mcfg.operator.paused then
            sleep(0.5)
        else
            if mcfg.siegeCleared then
                return gameEnd(mcfg.defenseTeam, "all assault waves repelled")
            end

            -- Defenders are deliberately not counted: they cannot contest or
            -- slow the capture. Enemy presence is the only driver. Counting
            -- prefers entity types (immune to scoreboard-team assignment
            -- quirks on spawned enemies); the team selector is the fallback.
            local enemyCount
            if mcfg.enemyEntityTypes then
                enemyCount = mc.entitiesNearCountByTypes(mcfg.enemyEntityTypes, zone.x, zone.y, zone.z, radius)
            else
                enemyCount = mc.entitiesNearCount(mcfg.attackTeam, zone.x, zone.y, zone.z, radius)
            end

            if enemyCount > 0 then
                state.score = state.score + mc.captureMultiplier(enemyCount, maxCaptureMultiplier) * scoreChange
                state.contested = true
            else
                -- Zone clear: progress holds, it does not decay.
                state.contested = false
            end

            -- Highlight enemies inside the objective so defenders can spot
            -- them in the town's vertical clutter. Re-applied every 2s with
            -- a 5s duration, so the glow effectively lasts while they stay.
            if mcfg.enemyEntityTypes and os.clock() >= nextGlow then
                for _, entityType in ipairs(mcfg.enemyEntityTypes) do
                    commands.exec(("execute as @e[type=%s,x=%d,y=%d,z=%d,distance=..%d] run effect give @s minecraft:glowing 5")
                        :format(entityType, zone.x, zone.y, zone.z, radius))
                end
                nextGlow = os.clock() + 2
            end

            if state.score > threshold then
                return gameEnd(mcfg.attackTeam, "objective captured")
            end

            saveRuntimeState()
            updateBossbar()
            refreshSpawns()

            -- Sidebar enemy counter, refreshed ~1/s with the world-wide
            -- living-enemy count by type (includes lane ambushers).
            if mcfg.enemyEntityTypes and os.clock() >= nextEnemyDisplay then
                commands.exec("/scoreboard players set Enemies " .. displayObjective
                    .. " " .. tostring(mc.entityCountByTypes(mcfg.enemyEntityTypes)))
                nextEnemyDisplay = os.clock() + 1
            end

            if os.clock() >= lastBossbarPlayerRefresh then
                commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " players @a")
                lastBossbarPlayerRefresh = os.clock() + 1
            end
        end

        sleep(interval)
    end
    if mcfg.checkpoint then mcfg.checkpoint("objective stopped") end
end

return engine
