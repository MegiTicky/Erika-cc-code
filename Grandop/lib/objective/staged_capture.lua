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

local mc   = require("lib.minecraft")
local stage = require("lib.stage_channel")
local tickets = require("lib.tickets")

local engine = {}

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
    local skipDelay = capture.skipCooldown or 3
    local announceDelay = capture.announceDelay or 2
    local reverseDelay = capture.reverseDelay or 30

    local zones = mcfg.captureZones
    local hub = mcfg.stage_channel and stage.new(mcfg.stage_channel) or nil
    if hub then stage.open(hub) end

    local state = {
        zone = mcfg.startZone or 1,
        score = 0,
        ended = false,
        mission = mcfg,
    }
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
            color = "blue"
            value = -value
        elseif value > 0 then
            color = "red"
        end
        commands.exec("/bossbar set " .. barId .. " value " .. tostring(value / 2))
        commands.exec("/bossbar set " .. barId .. " color " .. color)

        if mode == "bidirectional" and mcfg.objectiveNames then
            local name = mcfg.objectiveNames[state.zone]
            commands.exec('/bossbar set ' .. barId .. ' name "Objective ' .. tostring(name) .. '"')
        elseif mcfg.capture.bossbarName then
            commands.exec('/bossbar set ' .. barId .. ' name "' .. tostring(mcfg.capture.bossbarName) .. '"')
        end
    end

    local function sendTickets(zoneIndex)
        local reward = mcfg.ticketRewards and mcfg.ticketRewards[zoneIndex]
        if reward then
            if mcfg.ticketComputerId then
                rednet.send(mcfg.ticketComputerId, tickets.format(reward.a, reward.d))
            end
        end
    end

    local function gameEnd()
        state.ended = true
        if hooks.onGameEnd then hooks.onGameEnd(state) end
        if mode == "bidirectional" then
            -- Frontline ends with a title; hold until the server restarts.
            while true do sleep(2) end
        end
        while true do
            if mcfg.ticketComputerId then
                rednet.send(mcfg.ticketComputerId, tickets.format(0, -10))
            end
            sleep(2)
            print("Game Ended")
        end
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
                    mc.title('{"text":"' .. tostring(mcfg.attackTeam) .. ' wins","color":"red"}')
                else
                    mc.title('{"text":"' .. tostring(mcfg.defenseTeam) .. ' wins","color":"blue"}')
                end
                return gameEnd()
            end
            if hub then stage.broadcast(hub, nextZone) end
            sleep(announceDelay)
            mc.title('{"text":"Next Objective unlocked in ' .. reverseDelay .. 's"}')
            sleep(reverseDelay)
            mc.title('{"text":"Objective unlocked"}')
            state.zone = nextZone
        else
            sendTickets(state.zone)

            if state.zone == #zones then
                -- final zone captured
                redstone.setAnalogOutput("right", 15)
                sleep(0.1)
                redstone.setAnalogOutput("right", 0)
                return gameEnd()
            elseif state.zone == #zones - 1 then
                redstone.setAnalogOutput("left", 15)
                sleep(0.1)
                redstone.setAnalogOutput("left", 0)
            end

            state.zone = state.zone + 1
            if hub then stage.broadcast(hub, state.zone) end
        end

        setBeacon(currentZone())
        if hooks.onStageChange then hooks.onStageChange(state, state.zone) end
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
    if hub then stage.broadcast(hub, state.zone) end

    local skipCooldown = 0

    -- Main loop
    while not state.ended do
        local zone = currentZone()
        local attackerDetected = mc.playersInRange(mcfg.attackTeam, zone.x, zone.y, zone.z, radius)
        local defenderDetected = mc.playersInRange(mcfg.defenseTeam, zone.x, zone.y, zone.z, radius)

        if mode == "bidirectional" then
            local defendersCanDecap = true
            if hooks.defendersCanDecap then
                defendersCanDecap = hooks.defendersCanDecap(state)
            end

            if defenderDetected and defendersCanDecap then
                state.score = state.score - (capture.scoreChange or 3)
            end
            if attackerDetected then
                state.score = state.score + (capture.scoreChange or 3)
            end
            if not defenderDetected and not attackerDetected then
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
            if defenderDetected then
                state.score = state.score + (capture.defenseScore or -1)
            elseif attackerDetected then
                state.score = state.score + (capture.attackScore or 1)
            else
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

        setBeacon(currentZone())
        updateBossbar()
        refreshSpawns()

        sleep(interval)
    end
end

return engine
