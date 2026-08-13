-- Grandop creative area service.
-- Switches players to creative while inside a set of zones and back to
-- survival when they leave. Run in parallel with the main respawn loop.

local creative_area = {}

-- zones = { { name=..., x=, y=, z= }, ... }
function creative_area.run(radar, zones, radius)
    local insidePlayers = {}
    while true do
        local radarResult = radar.scanForPlayers(9999)
        local newInside = {}

        for _, player in ipairs(radarResult or {}) do
            local px, py, pz = player.pos[1], player.pos[2], player.pos[3]
            local name = player.nickname
            local isInsideAny = false

            for _, zone in ipairs(zones) do
                local dx = px - zone.x
                local dy = py - zone.y
                local dz = pz - zone.z
                if math.sqrt(dx * dx + dy * dy + dz * dz) <= radius then
                    isInsideAny = true
                    break
                end
            end

            if isInsideAny then
                newInside[name] = true
                if not insidePlayers[name] then
                    commands.exec("gamemode creative " .. name)
                    print("Set creative: " .. name)
                end
            else
                if insidePlayers[name] then
                    commands.exec("gamemode survival " .. name)
                    print("Set survival: " .. name)
                end
            end
        end

        insidePlayers = newInside
        sleep(1)
    end
end

return creative_area
