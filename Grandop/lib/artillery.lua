-- Shared projectile and dispersion behavior for player and siege artillery.
local artillery = {}
artillery.patterns = { concentrated = { sigma = 7, cap = 22 }, area = { sigma = 16, cap = 45 } }
local shellCommands = {
    he = '/summon crusty_chunks:artillery_fire_projectile %d %d %d',
    smoke = '/summon cbcmodernwarfare:smoke_mediumshell %d %d %d {Fuze:{id:"createbigcannons:impact_fuze",Count:1b}, Motion:[0d,-10d,0d]}',
}

function artillery.impactOffset(pattern)
    local spec = assert(artillery.patterns[pattern], "Unknown artillery pattern")
    while true do
        local radius = spec.sigma * math.sqrt(-2 * math.log(1 - math.random()))
        if radius <= spec.cap then
            local angle = 2 * math.pi * math.random()
            local x, z = math.floor(radius * math.cos(angle) + 0.5), math.floor(radius * math.sin(angle) + 0.5)
            if x*x + z*z <= spec.cap*spec.cap then return x, z end
        end
    end
end

function artillery.fireShell(job)
    local dx, dz
    if job.shell == "smoke" then
        dx, dz = math.random(-50, 50), math.random(-50, 50)
    else
        dx, dz = artillery.impactOffset(job.pattern)
    end
    return commands.exec(assert(shellCommands[job.shell]):format(job.x + dx, 350, job.z + dz))
end

return artillery
