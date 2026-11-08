-- Enemy artillery schedule, independent of player-requested fire missions.
local mc = grandopRequire("lib.minecraft")
local artillery = grandopRequire("lib.artillery")
local scheduler = {}

function scheduler.new(siege, ctx)
    local config = siege.enemyArtillery
    local zone = siege.objective.captureZones[siege.objective.startZone or 1]
    local log = ctx.log or print
    local pending, jobs = {}, {}
    local elapsed = 0
    local lastTime = os.epoch("utc") / 1000
    local wasPaused = ctx.operator.paused
    local api = {}

    function api.startWave(wave)
        local count = (config.barrages or {})[wave] or 0
        for i = 1, count do
            pending[#pending + 1] = { wave = wave, due = elapsed + (config.delay or 30) + (i - 1) * (config.interval or 30) }
        end
        if count > 0 then log(("Siege artillery: wave %d scheduled %d barrage(s)"):format(wave, count)) end
    end

    function api.endWave(wave)
        for i = #pending, 1, -1 do
            if pending[i].wave == wave then
                table.remove(pending, i)
                log("Siege artillery: cancelled unannounced barrage for wave " .. wave)
            end
        end
    end

    local function warn(entry)
        local candidates = {}
        for _, player in ipairs(mc.playerPositions(siege.defenderTeam, true)) do
            local dx, dz = player.x - zone.x, player.z - zone.z
            if dx * dx + dz * dz <= (config.radius or 150) ^ 2 then candidates[#candidates + 1] = player end
        end
        if #candidates == 0 then
            log("Siege artillery: wave " .. entry.wave .. " skipped; no eligible defenders")
            return
        end
        local target = candidates[math.random(#candidates)]
        local job = { wave = entry.wave, x = target.x, z = target.z, shell = "he", pattern = "area", fired = 0, due = elapsed + 15 }
        jobs[#jobs + 1] = job
        commands.exec('/say You hear artillery firing in the distance.')
        log(("Siege artillery: wave %d warned; targeting %s at (%d,%d)"):format(entry.wave, target.name, target.x, target.z))
    end

    -- Exposed as a single tick for deterministic tests. Paused time never
    -- advances the scheduler, including the transition into or out of pause.
    function api.tick(now)
        local paused = ctx.operator.paused
        local delta = math.max(0, now - lastTime)
        lastTime = now
        if not paused and not wasPaused then elapsed = elapsed + delta end
        wasPaused = paused
        if ctx.operator.shutdown or (siege.objective.runtimeState and siege.objective.runtimeState.ended) then
            pending, jobs = {}, {}
            return false
        end
        if paused then return true end
        for i = #pending, 1, -1 do
            if pending[i].due <= elapsed then
                local entry = table.remove(pending, i)
                warn(entry)
            end
        end
        for i = #jobs, 1, -1 do
            local job = jobs[i]
            if job.due <= elapsed then
                local ok = artillery.fireShell(job)
                job.fired = job.fired + 1
                log(("Siege artillery: wave %d shell %d/3 dispatched (%s)"):format(job.wave, job.fired, tostring(ok)))
                if job.fired == 3 then table.remove(jobs, i) else job.due = elapsed + 1 end
            end
        end
        return true
    end

    function api.run()
        while api.tick(os.epoch("utc") / 1000) do sleep(0.1) end
    end
    return api
end

return scheduler
