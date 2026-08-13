-- Grandop infantry respawn support.
-- Class selection, kit application (from JSON loadouts), quota-gated spawn
-- selection, and teleporting. Mission-specific quota rules are injected via
-- ctx.hasQuota / ctx.decrementQuota so the module stays reusable.

local monitor_ui = grandopRequire("lib.monitor_ui")
local loadout = grandopRequire("lib.loadout")

local infantry = {}

function infantry.isKitReady(ctx, className)
    return loadout.isReady(ctx.loadoutData, className, os.epoch("utc") / 1000)
end

function infantry.secondsLeft(ctx, className)
    return loadout.secondsLeft(ctx.loadoutData, className, os.epoch("utc") / 1000)
end

function infantry.useKit(ctx, className)
    loadout.applyClass(ctx.loadoutData, className, ctx.player)
    loadout.markUsed(className, os.epoch("utc") / 1000)
end

-- Touch menu listing the available classes.
function infantry.selectClass(ctx)
    local rows = {}
    for _, name in ipairs(loadout.classNames(ctx.loadoutData)) do
        table.insert(rows, { label = "[" .. name .. "]", value = name })
    end
    return monitor_ui.rowMenu(ctx.monitor, rows, "[ Cancel ]")
end

-- Touch menu of spawn points for the current stage, quota gated.
-- Supports optional extra rows (e.g. tanks with crew left) via ctx.extraRows()
-- returning { label = ..., value = ... } entries.
function infantry.selectSpawn(ctx)
    local mission = ctx.mission
    local stageSpawns = {}
    if mission.infantrySpawns and mission.infantrySpawns[ctx.country] then
        stageSpawns = mission.infantrySpawns[ctx.country][ctx.stage.current] or {}
    end

    while true do
        ctx.monitor.clear()
        if ctx.displayScoreboard then ctx.displayScoreboard() end

        local y = 7
        local rowMap = {}
        ctx.monitor.setCursorPos(1, y)
        monitor_ui.print(ctx.monitor, "Select Infantry Spawn (Stage " .. tostring(ctx.stage.current) .. "):")
        y = y + 2

        for _, p in ipairs(stageSpawns) do
            if not ctx.hasQuota or ctx.hasQuota(ctx.country, p.name) then
                ctx.monitor.setCursorPos(2, y)
                ctx.monitor.write(("[%s]  (%d,%d,%d)"):format(p.name, p.x, p.y, p.z))
                rowMap[y] = p
                y = y + 2
            end
        end

        if ctx.extraRows then
            for _, r in ipairs(ctx.extraRows()) do
                ctx.monitor.setCursorPos(2, y)
                ctx.monitor.write(r.label)
                rowMap[y] = r.value
                y = y + 2
            end
        end

        if y == 7 then
            monitor_ui.print(ctx.monitor, "No spawn points available! Respawn limit reached.")
            sleep(2)
            return nil
        end

        ctx.monitor.setCursorPos(2, y)
        ctx.monitor.write("[ Refresh ]")
        local refreshY = y
        rowMap[refreshY] = "refresh"

        ctx.monitor.setCursorPos(2, y + 2)
        ctx.monitor.write("[ Cancel ]")
        rowMap[y + 2] = "cancel"

        local ev, side, x, ry = os.pullEvent("monitor_touch")
        if ry == refreshY then
            -- loop redraws with the current stage
        elseif rowMap[ry] == "cancel" then
            return nil
        elseif rowMap[ry] then
            local selected = rowMap[ry]
            if selected.type == "vehicle" then
                if ctx.onVehicleSelected then ctx.onVehicleSelected(selected.name) end
                return selected
            end
            if not ctx.decrementQuota or ctx.decrementQuota(ctx.country, selected.name) then
                return selected
            else
                monitor_ui.print(ctx.monitor, "Respawn limit for " .. selected.name .. " reached!")
                sleep(2)
            end
        end
    end
end

-- Teleport a player to a spawn point (or onto a vehicle / commander).
function infantry.respawn(ctx, spawnLocation, className)
    local player = ctx.player

    if spawnLocation.type == "vehicle" then
        local tankId = ctx.tankslugtoID[spawnLocation.name]
        if tankId then
            local tankScan = ctx.radar.scanForShips(9999)
            for _, ship in ipairs(tankScan or {}) do
                if ship.id == tankId.id then
                    commands.exec(("tp %s %d %d %d"):format(player, ship.pos.x, ship.pos.y, ship.pos.z))
                    commands.exec(("title %s actionbar {\"text\":\"Respawned as %s at %s (Stage %d)\",\"color\":\"yellow\"}"):format(player, className, tankId.id, ctx.stage.current))
                    commands.exec("/effect give " .. player .. " minecraft:resistance 4 10")
                    return
                end
            end
        end
        return
    end

    if spawnLocation.name == "USCommander" then
        commands.exec("/tp " .. player .. " @a[tag=USCom,limit=1]")
    elseif spawnLocation.name == "JPCommander" then
        commands.exec("/tp " .. player .. " @a[tag=JPCom,limit=1]")
    else
        local dx = math.random(-ctx.spawnRadius, ctx.spawnRadius)
        local dz = math.random(-ctx.spawnRadius, ctx.spawnRadius)
        local x = math.floor(spawnLocation.x + dx + 0.5)
        local z = math.floor(spawnLocation.z + dz + 0.5)
        local y = spawnLocation.y

        commands.exec(("tp %s %d %d %d"):format(player, x, y, z))
        commands.exec(("title %s actionbar {\"text\":\"Respawned as %s at %s (Stage %d)\",\"color\":\"yellow\"}"):format(player, className, spawnLocation.name, ctx.stage.current))
        commands.exec("/effect give " .. player .. " minecraft:resistance 4 10")
        print(("%s respawned near %s at (%d, %d, %d)"):format(player, spawnLocation.name, x, y, z))
    end
end

return infantry
