-- Grandop siege assault director.
--
-- Makes the enemy assault less predictable. Squads default to `attack` on
-- the objective (the mod's cover-to-cover advance); the director interrupts
-- that with short `go_to` charges to offset points — a partial advance plus
-- a lateral drift, never the objective itself — and then re-pings `attack`
-- so the squad resumes its assault. Attack pings are also refreshed
-- periodically because the mod expires attack orders after 60 s
-- (SoldierEntity ATTACK_MEMORY_MS). On a separate randomized schedule a
-- squad is ordered to `suppress` a live defender's position: riflemen and
-- machine-gunners rake the area and RPG carriers rain rockets into it.
--
-- Squad positions come from parsing `stevesarmy squad info` output, which
-- also doubles as the dead-squad prune: a squad with no living, loaded
-- members is dropped.

local mc = grandopRequire("lib.minecraft")

local director = {}

local function randBetween(min, max)
    return min + math.random() * (max - min)
end

-- Parse `stevesarmy squad info <cs>`: returns the position of the first
-- living loaded member, the alive-member count, and the unloaded-member
-- count. alive==0 with unloaded>0 means the squad exists but is entirely
-- chunk-unloaded — NOT the same as dead. Also used by the wave loop for
-- its squad-based wipe check.
function director.squadSnapshot(callsign)
    local ok, output = commands.exec("stevesarmy squad info " .. callsign)
    if not ok then return nil, 0, 0 end
    local pos, alive, unloaded = nil, 0, 0
    for _, line in ipairs(output or {}) do
        local text = tostring(line)
        if text:find("<unloaded>", 1, true) then
            unloaded = unloaded + 1
        elseif text:find("pos ", 1, true) and not text:find("DEAD", 1, true) then
            local x, y, z = text:match("pos%s+([%-%d]+),%s*([%-%d]+),%s*([%-%d]+)")
            if x and not pos then
                pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
            end
            alive = alive + 1
        end
    end
    if alive == 0 then return nil, 0, unloaded end
    return pos, alive, unloaded
end

-- Charge target: `dist` blocks from the squad toward the objective (never
-- into the objective radius) plus a perpendicular lateral drift, so charges
-- vary between direct sprints and flanking hooks. Exposed for the desktop
-- unit harness.
function director.chargePoint(squadPos, zone, dist, lateral, objectiveRadius)
    local dx = zone.x - squadPos.x
    local dz = zone.z - squadPos.z
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 1 then return nil end
    local ux, uz = dx / len, dz / len
    -- Keep the charge point outside the objective radius: if the straight
    -- charge would land inside it, stop at the edge instead.
    local travel = math.min(dist, math.max(0, len - (objectiveRadius + 5)))
    if travel < 5 then return nil end
    local side = math.random() < 0.5 and -1 or 1
    local px = squadPos.x + ux * travel - uz * lateral * side
    local pz = squadPos.z + uz * travel + ux * lateral * side
    -- Ground-level y is not needed: squad orders take block positions and
    -- the mod's navigation resolves terrain on its own.
    return math.floor(px + 0.5), math.floor(pz + 0.5)
end

function director.run(siege, ctx)
    local cfg = siege.director or {}
    local zone = siege.objective.captureZones[siege.objective.startZone or 1]
    local objectiveRadius = (siege.objective.capture and siege.objective.capture.radius) or 40
    local tick = cfg.tick or 2
    local chargeEveryMin, chargeEveryMax = cfg.chargeEveryMin or 20, cfg.chargeEveryMax or 45
    local chargeDistMin, chargeDistMax = cfg.chargeDistMin or 15, cfg.chargeDistMax or 30
    local lateralMin, lateralMax = cfg.lateralMin or 10, cfg.lateralMax or 25
    local chargeSecsMin, chargeSecsMax = cfg.chargeDurationMin or 5, cfg.chargeDurationMax or 8
    local attackRefresh = cfg.attackRefresh or 45
    local suppressEveryMin, suppressEveryMax = cfg.suppressEveryMin or 30, cfg.suppressEveryMax or 60
    local suppressSecsMin, suppressSecsMax = cfg.suppressDurationMin or 8, cfg.suppressDurationMax or 10
    local suppressRange = cfg.suppressRange or 150

    -- callsign -> { mode = attack|charge|suppress, chargeUntil, suppressUntil,
    --               lastAttack, nextChargeAt }
    local squads = {}
    local now = os.epoch("utc") / 1000
    local nextSuppressAt = now + randBetween(suppressEveryMin, suppressEveryMax)
    local nextPruneAt = now + 30

    local function orderAttack(callsign, st)
        commands.exec(("stevesarmy squad order %s attack %d %d %d")
            :format(callsign, zone.x, zone.y, zone.z))
        st.mode = "attack"
        st.lastAttack = os.epoch("utc") / 1000
        st.nextChargeAt = st.lastAttack + randBetween(chargeEveryMin, chargeEveryMax)
    end

    local function orderCharge(callsign, st, squadPos)
        local px, pz = director.chargePoint(squadPos, zone,
            randBetween(chargeDistMin, chargeDistMax),
            randBetween(lateralMin, lateralMax), objectiveRadius)
        if not px then return false end
        commands.exec(("stevesarmy squad order %s go_to %d %d %d")
            :format(callsign, px, squadPos.y, pz))
        st.mode = "charge"
        st.chargeUntil = os.epoch("utc") / 1000 + randBetween(chargeSecsMin, chargeSecsMax)
        return true
    end

    local function orderSuppress(callsign, st, target)
        commands.exec(("stevesarmy squad order %s suppress %d %d %d")
            :format(callsign, target.x, target.y, target.z))
        st.mode = "suppress"
        st.suppressUntil = os.epoch("utc") / 1000 + randBetween(suppressSecsMin, suppressSecsMax)
    end

    while not ctx.operator.shutdown do
        sleep(tick)
        while ctx.operator.paused and not ctx.operator.shutdown do sleep(1) end
        if ctx.operator.shutdown then return end
        if siege.objective.runtimeState and siege.objective.runtimeState.ended then return end
        local now = os.epoch("utc") / 1000

        -- Adopt squads registered by the wave spawner.
        for _, entry in ipairs(siege.activeSquads or {}) do
            if not squads[entry.callsign] then
                squads[entry.callsign] = {
                    mode = "attack",
                    lastAttack = 0,
                    nextChargeAt = now + randBetween(chargeEveryMin, chargeEveryMax),
                }
            end
        end

        -- Periodic prune: drop squads whose members are all dead. A squad
        -- whose members are merely chunk-unloaded stays adopted — pruning
        -- it would orphan the soldiers (their in-memory attack order dies
        -- with an unload/reload, and they would hold position forever).
        if now >= nextPruneAt then
            nextPruneAt = now + 30
            for callsign in pairs(squads) do
                local _, alive, unloaded = director.squadSnapshot(callsign)
                if alive == 0 and unloaded == 0 then
                    squads[callsign] = nil
                end
            end
        end

        -- Per-squad state machine.
        for callsign, st in pairs(squads) do
            if st.mode == "attack" then
                if now - st.lastAttack >= attackRefresh then
                    orderAttack(callsign, st)
                elseif now >= st.nextChargeAt then
                    local squadPos = director.squadSnapshot(callsign)
                    if squadPos and not orderCharge(callsign, st, squadPos) then
                        st.nextChargeAt = now + 10
                    end
                end
            elseif st.mode == "charge" and now >= st.chargeUntil then
                orderAttack(callsign, st)
            elseif st.mode == "suppress" and now >= st.suppressUntil then
                orderAttack(callsign, st)
            end
        end

        -- Suppression fire on defenders: pick an attacking squad and a live
        -- defender position, preferring defenders near the objective.
        if now >= nextSuppressAt then
            nextSuppressAt = now + randBetween(suppressEveryMin, suppressEveryMax)
            local candidates = {}
            for callsign, st in pairs(squads) do
                if st.mode == "attack" then table.insert(candidates, callsign) end
            end
            local players = mc.playerPositions(ctx.teams and ctx.mission.siege.defenderTeam or "Blue")
            local near, far = {}, {}
            for _, p in ipairs(players) do
                local dx, dz = p.x - zone.x, p.z - zone.z
                if math.sqrt(dx * dx + dz * dz) <= suppressRange then
                    table.insert(near, p)
                else
                    table.insert(far, p)
                end
            end
            local pool = #near > 0 and near or far
            if #candidates > 0 and #pool > 0 then
                local callsign = candidates[math.random(#candidates)]
                local target = pool[math.random(#pool)]
                orderSuppress(callsign, squads[callsign], target)
            end
        end
    end
end

return director
