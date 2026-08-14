-- Grandop staged capture objective engine.
--
-- Drives a sequence of capture zones with a bossbar, beacons, ticket updates,
-- stage broadcasts, and spawnpoint refreshes. Two scoring modes are supported:
--
--   mode = "forward"       -- attackers advance one way (breakthrough).
--   mode = "bidirectional" -- score can go positive or negative; attackers
--                            and defenders can each push the line (frontline).
--
-- The mission configuration supplies all map data and optional hooks so the
-- engine stays mission-agnostic.

local mc   = grandopRequire("lib.minecraft")
local stage = grandopRequire("lib.stage_channel")
local engine = {}

local function teamColor(team)
    return team == "Blue" and "blue" or "red"
end

local function validate(mcfg)
    assert(mcfg.captureZones and #mcfg.captureZones > 0, "Mission needs captureZones")
    assert(mcfg.attackTeam, "Mission needs attackTeam")
    assert(mcfg.defenseTeam, "Mission needs defenseTeam")
end

local function initBossbar(mcfg, total)
    commands.exec("/bossbar remove " .. tostring(mcfg.bossbarId))
    commands.exec('/bossbar add ' .. tostring(mcfg.bossbarId) .. ' "Stage 1 of ' .. total .. '"')
    commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " max " .. tostring(mcfg.capture.maxValue or 100))
    commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " value 0")
    commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " style progress")
    commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " players @a")
end

function engine.run(mcfg)
    validate(mcfg)

    local capture = mcfg.capture or {}
    local radius = capture.radius or 20
    local interval = capture.updateInterval or 0.001
    local threshold = capture.threshold or 200
    local mode = capture.mode or "forward"
    local maxCaptureMultiplier = capture.maxCaptureMultiplier or 2.5
    local skipDelay = capture.skipCooldown or 3
    local announceDelay = capture.announceDelay or 2
    local reverseDelay = capture.reverseDelay or 30

    local zones = mcfg.captureZones
    local hub = (mcfg.stage_channel and not mcfg.stageState) and stage.new(mcfg.stage_channel) or nil
    if hub then stage.open(hub) end

    local restored = mcfg.runtimeState or {}
    local state = {
        zone = restored.zone or mcfg.startZone or 1,
        score = restored.score or 0,
        ended = restored.ended or false,
        winner = restored.winner,
        mission = mcfg,
    }
    if state.zone < 1 or state.zone > #mcfg.captureZones then
        error("Saved objective zone is outside this mission's capture zones")
    end
    local function saveRuntimeState()
        mcfg.runtimeState = {
            zone = state.zone,
            score = state.score,
            ended = state.ended,
            winner = state.winner,
        }
    end
    saveRuntimeState()
    local hooks = mcfg.hooks or {}

    local function currentZone()
        return zones[state.zone]
    end

    local function clearBeacon(zone)
        mc.setblock(zone.x, zone.y, zone.z, "air")
    end

    local function setBeacon(zone)
        mc.setblock(zone.x, zone.y, zone.z, "minecraft:beacon")
        if capture.netheriteBase then
            mc.fill(zone.x - 1, zone.y - 1, zone.z - 1, zone.x + 1, zone.y - 1, zone.z + 1, "minecraft:netherite_block")
        end
    end

    local function pulse()
        redstone.setAnalogOutput("top", 15)
        sleep(0)
        redstone.setAnalogOutput("top", 0)
    end

    local function refreshSpawns()
        if mcfg.stagingAreas and mcfg.teamFactions then
            for team, faction in pairs(mcfg.teamFactions) do
                local areas = mcfg.stagingAreas[faction]
                local area = areas and (areas[state.zone] or areas.default)
                if area then mc.setSpawnpoint(team, area.x, area.y, area.z) end
            end
            return
        end
        local atkSpawns = mcfg.attackerSpawns or {}
        local defSpawns = mcfg.defenderSpawns or {}
        local atk = atkSpawns[state.zone] or atkSpawns
        local def = defSpawns[state.zone] or defSpawns
        if atk then mc.setSpawnpoint(mcfg.attackTeam, atk.x, atk.y, atk.z) end
        if def then mc.setSpawnpoint(mcfg.defenseTeam, def.x, def.y, def.z) end
    end

    local function updateBossbar()
        local barId = tostring(mcfg.bossbarId)
        local color = "white"
        local value = state.score
        if value < 0 then
            color = teamColor(mcfg.defenseTeam)
            value = -value
        elseif value > 0 then
            color = teamColor(mcfg.attackTeam)
        end
        local maxValue = capture.maxValue or 100
        local progress = math.floor(math.max(0, math.min(threshold, value)) * maxValue / threshold)
        commands.exec("/bossbar set " .. barId .. " value " .. tostring(progress))
        commands.exec("/bossbar set " .. barId .. " color " .. color)

        if mode == "bidirectional" and mcfg.objectiveNames then
            local name = mcfg.objectiveNames[state.zone]
            commands.exec('/bossbar set ' .. barId .. ' name "Objective ' .. tostring(name) .. '"')
        elseif mode == "forward" then
            commands.exec('/bossbar set ' .. barId .. ' name "Stage ' .. state.zone .. ' of ' .. #zones .. '"')
        elseif mcfg.capture.bossbarName then
            commands.exec('/bossbar set ' .. barId .. ' name "' .. tostring(mcfg.capture.bossbarName) .. '"')
        end
    end

    local function gameEnd(winner, reason)
        state.ended = true
        state.winner = winner
        saveRuntimeState()
        if mcfg.checkpoint then mcfg.checkpoint("objective ended") end
        if hooks.onGameEnd then hooks.onGameEnd(state) end
        mc.title('{"text":"' .. tostring(winner) .. ' wins!","color":"' .. teamColor(winner) .. '"}')
        print("Game ended: " .. tostring(reason))
    end

    -- Complete the current zone and move the line.
    local function advance(nextZone)
        state.score = 0
        local zone = currentZone()
        clearBeacon(zone)
        pulse()

        if hooks.onCapture then hooks.onCapture(state, state.zone) end

        if mode == "bidirectional" then
            local name = mcfg.objectiveNames and mcfg.objectiveNames[state.zone] or tostring(state.zone)
            mc.title('{"text":"Objective ' .. tostring(name) .. ' captured!","color":"green"}')
            if nextZone > #zones or nextZone < 1 then
                if nextZone > #zones then
                    return gameEnd(mcfg.attackTeam, "enemy base captured")
                else
                    return gameEnd(mcfg.defenseTeam, "enemy base captured")
                end
            end
            if hub then stage.broadcast(hub, nextZone) end
            sleep(announceDelay)
            mc.title('{"text":"Next Objective unlocked in ' .. reverseDelay .. 's"}')
            sleep(reverseDelay)
            mc.title('{"text":"Objective unlocked"}')
            state.zone = nextZone
            if mcfg.stageState then mcfg.stageState.current = state.zone end
        else
            mc.title('{"text":"Objective Captured! Stage ' .. state.zone .. ' Completed!","color":"green"}')

            if state.zone == #zones then
                -- final zone captured
                redstone.setAnalogOutput("right", 15)
                sleep(0.1)
                redstone.setAnalogOutput("right", 0)
                return gameEnd(mcfg.attackTeam, "all objectives captured")
            elseif state.zone == #zones - 1 then
                redstone.setAnalogOutput("left", 15)
                sleep(0.1)
                redstone.setAnalogOutput("left", 0)
            end

            state.zone = state.zone + 1
            if mcfg.stageState then mcfg.stageState.current = state.zone end
            if hub then stage.broadcast(hub, state.zone) end
        end

        setBeacon(currentZone())
        if hooks.onStageChange then hooks.onStageChange(state, state.zone) end
        saveRuntimeState()
        if mcfg.checkpoint then mcfg.checkpoint("stage advanced") end
    end

    local function selectStage(stageNumber)
        clearBeacon(currentZone())
        state.zone = stageNumber
        state.score = 0
        if mcfg.stageState then mcfg.stageState.current = state.zone end
        if hub then stage.broadcast(hub, state.zone) end
        setBeacon(currentZone())
        refreshSpawns()
        updateBossbar()
        saveRuntimeState()
        if mcfg.checkpoint then mcfg.checkpoint("operator stage change") end
        print("Operator selected stage " .. state.zone)
    end

    -- Initial setup
    initBossbar(mcfg, #zones)
    redstone.setOutput("back", false)
    sleep(0.1)
    redstone.setOutput("back", true)

    for i = 1, #zones do
        mc.setblock(zones[i].x, zones[i].y, zones[i].z, "air")
    end
    setBeacon(currentZone())
    if mcfg.stageState then mcfg.stageState.current = state.zone end
    if hub then stage.broadcast(hub, state.zone) end

    local skipCooldown = 0
    local lastBossbarPlayerRefresh = 0

    -- Main loop
    while not state.ended and not (mcfg.operator and mcfg.operator.shutdown) do
        if mcfg.operator and mcfg.operator.stageRequest then
            local requested = mcfg.operator.stageRequest
            mcfg.operator.stageRequest = nil
            selectStage(requested)
        end
        if mcfg.operator and mcfg.operator.paused then sleep(0.1) else
        if mcfg.attackerDepleted and mcfg.attackerDepleted() then
            return gameEnd(mcfg.defenseTeam, "attacker reinforcements depleted")
        end
        local zone = currentZone()
        local attackerCount = mc.playersInRangeCount(mcfg.attackTeam, zone.x, zone.y, zone.z, radius)
        local defenderCount = mc.playersInRangeCount(mcfg.defenseTeam, zone.x, zone.y, zone.z, radius)

        if mode == "bidirectional" then
            local defendersCanDecap = true
            if hooks.defendersCanDecap then
                defendersCanDecap = hooks.defendersCanDecap(state)
            end

            if not defendersCanDecap then defenderCount = 0 end
            local advantage = attackerCount - defenderCount
            if advantage > 0 then
                state.score = state.score + mc.captureMultiplier(advantage, maxCaptureMultiplier) * (capture.scoreChange or 3)
            elseif advantage < 0 then
                state.score = state.score - mc.captureMultiplier(math.abs(advantage), maxCaptureMultiplier) * (capture.scoreChange or 3)
            elseif attackerCount == 0 then
                if state.score > 0 then
                    state.score = math.max(0, state.score - (capture.neutralDecay or 1))
                elseif state.score < 0 then
                    state.score = math.min(0, state.score + (capture.neutralDecay or 1))
                end
            end

            if redstone.getInput("front") and os.clock() > skipCooldown then
                state.score = threshold + 1
                skipCooldown = os.clock() + skipDelay
            elseif redstone.getInput("back") and os.clock() > skipCooldown then
                state.score = -threshold - 1
                skipCooldown = os.clock() + skipDelay
            end

            if state.score > threshold then
                advance(state.zone + 1)
            elseif state.score < -threshold then
                advance(state.zone - 1)
            end
        else
            -- forward mode
            local advantage = attackerCount - defenderCount
            if advantage > 0 then
                state.score = state.score + mc.captureMultiplier(advantage, maxCaptureMultiplier) * (capture.attackScore or 1)
            elseif advantage < 0 then
                state.score = state.score + mc.captureMultiplier(math.abs(advantage), maxCaptureMultiplier) * (capture.defenseScore or -1)
            elseif attackerCount == 0 then
                state.score = state.score + (capture.neutralScore or -1)
            end
            if state.score < 0 then state.score = 0 end

            if redstone.getInput("front") and os.clock() > skipCooldown then
                print("Zone skipped by button press")
                state.score = threshold + 1
                skipCooldown = os.clock() + skipDelay
            end

            if state.score > threshold then
                advance(state.zone + 1)
            end
        end

        if state.ended then break end

        saveRuntimeState()
        setBeacon(currentZone())
        updateBossbar()
        if os.clock() >= lastBossbarPlayerRefresh then
            commands.exec("/bossbar set " .. tostring(mcfg.bossbarId) .. " players @a")
            lastBossbarPlayerRefresh = os.clock() + 1
        end
        refreshSpawns()

        sleep(interval)
        end
    end
    if mcfg.checkpoint then mcfg.checkpoint("objective stopped") end
end

return engine
