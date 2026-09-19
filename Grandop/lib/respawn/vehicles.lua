-- Grandop vehicle (tank) respawn support.
-- Tanks spawn directly from server schematics via VMod
-- (/vmod schem load-from-sever + /vmod schem place). Availability follows a
-- Battlefield-style model: each tank type has a concurrent-instance cap
-- (maxLive) and a respawn cooldown that STARTS AT SPAWN TIME. While the
-- cooldown runs the type cannot spawn at all; once it has expired, the next
-- destruction/abandonment frees the slot for an immediate respawn. There is
-- no finite stock.
--
-- Naming: we hand VMod a vehicle slug like "chinu-5-" (trailing dash). VMod
-- renames every ship of a multi-island placement to <slug>0, <slug>1, ...
-- (plain concatenation), so vehicle 5's ships are chinu-5-0 (hull),
-- chinu-5-1, ... A single-island schematic keeps the bare slug. The vehicle
-- number is ours and only commits after a confirmed spawn; VMod's ship index
-- is never parsed or relied on.
--
-- Destruction marker: every vehicle owner permanently carries a renamed
-- carrot-on-a-stick. Right-clicking it scores on the gptankmarker objective
-- (minecraft.used:minecraft.carrot_on_a_stick), which instantly recalls the
-- vehicle to the reserve depot. The marker is re-issued automatically if
-- dropped, moved out, or lost to a soldier respawn.

local monitor_ui = grandopRequire("lib.monitor_ui")

local vehicles = {}

local SCAN_CACHE_TTL = 5      -- seconds a radar scan stays fresh for reconcile
local SCAN_CACHE_MAX_AGE = 15 -- give up on a cache this old once scans fail
local PLACE_POLL_INTERVAL = 0.5
local PLACE_POLL_TIMEOUT = 8  -- seconds to wait for the placed ship to show on radar
local SPAWN_RADIUS = 15       -- radar proximity for matching a freshly placed ship

local MARKER_OBJECTIVE = "gptankmarker"       -- minecraft.used:minecraft.carrot_on_a_stick
local MARKER_DEFAULT_LABEL = "Vehicle Destruction Marker"

local function markerItemSpec(label)
    -- Byte-identical between give and clear so the NBT filter matches.
    return ("minecraft:carrot_on_a_stick{display:{Name:'{\"text\":\"%s\",\"color\":\"red\",\"italic\":false}'},Unbreakable:1b,HideFlags:1}")
        :format(label or MARKER_DEFAULT_LABEL)
end

-- Remove every marker copy from an inventory and zero their score, so a
-- stale score can never instantly destroy a freshly spawned vehicle.
local function stripMarker(owner, label)
    commands.exec(("scoreboard players set %s %s 0"):format(owner, MARKER_OBJECTIVE))
    commands.exec("clear " .. owner .. " " .. markerItemSpec(label))
end

local function status(monitor, text)
    if monitor then
        monitor_ui.print(monitor, text)
    else
        print(text)
    end
end

local function now()
    return os.epoch("utc") / 1000
end

--================================================================--
-- Config normalisation + persistence-aware merge
--================================================================--
-- Per-tank config (mission side): maxLive, cooldown, and the optional
-- schematic, rotation, anchorOffset placement tweaks. Legacy `stock` maps
-- onto maxLive so older mission formats keep working. Runtime fields
-- (active, cooldownUntil, counter) ride along on the same tables and are
-- persisted by the checkpoint's `vehicles` snapshot.
local function normalise(cfg)
    if type(cfg) ~= "table" then return nil end
    cfg.maxLive = math.max(1, math.floor(tonumber(cfg.maxLive) or tonumber(cfg.stock) or 1))
    cfg.cooldown = math.max(0, tonumber(cfg.cooldown) or 180)
    cfg.active = type(cfg.active) == "table" and cfg.active or {}
    cfg.cooldownUntil = tonumber(cfg.cooldownUntil) or 0
    cfg.counter = math.max(0, math.floor(tonumber(cfg.counter) or 0))
    return cfg
end

function vehicles.newState(tanksList, options)
    options = options or {}
    return {
        tanks = tanksList,
        pointIndex = 1,
        abandonRadius = tonumber(options.abandonRadius) or 20,
        abandonSeconds = tonumber(options.abandonSeconds) or 30,
        reserve = options.reserve,
        markerLabel = options.markerLabel or MARKER_DEFAULT_LABEL,
    }
end

function vehicles.ensure(v, country, tankName)
    local factionTanks = v.tanks[country]
    local cfg = factionTanks and factionTanks[tankName] or nil
    if not cfg then return nil, nil end
    return normalise(cfg)
end

-- Overlay recovered runtime state onto the mission's pool defaults. Saved
-- values win (cooldown/maxLive tweaks survive restarts) and tanks added to
-- the mission appear without wiping runtime data; tanks removed from the
-- mission disappear even if still saved.
function vehicles.mergePoolConfig(defaults, saved)
    local result = {}
    for country, tanks in pairs(defaults or {}) do
        if type(tanks) == "table" then
            result[country] = {}
            for name, cfg in pairs(tanks) do
                result[country][name] = normalise(cfg) or { maxLive = 1, cooldown = 180 }
            end
        end
    end
    for country, tanks in pairs(saved or {}) do
        if type(tanks) == "table" and type(result[country]) == "table" then
            for name, cfg in pairs(tanks) do
                local base = result[country][name]
                if type(cfg) == "table" and base then
                    for key, value in pairs(cfg) do base[key] = value end
                    result[country][name] = normalise(base)
                end
            end
        end
    end
    return result
end

--================================================================--
-- Availability (concurrent cap + destroy-triggered cooldown)
--================================================================--
function vehicles.liveCount(v, country, tankName)
    local cfg = vehicles.ensure(v, country, tankName)
    if not cfg then return 0 end
    local count = 0
    for _ in pairs(cfg.active) do count = count + 1 end
    return count
end

-- Returns (true, "READY") when a tank can be deployed, (false, reason) otherwise.
function vehicles.available(v, country, tankName)
    local cfg = vehicles.ensure(v, country, tankName)
    if not cfg then return false, "unknown tank" end
    local live = vehicles.liveCount(v, country, tankName)
    if live >= cfg.maxLive then
        return false, ("in use %d/%d"):format(live, cfg.maxLive)
    end
    local remain = math.ceil(cfg.cooldownUntil - now())
    if remain > 0 then
        return false, ("cooldown %ds"):format(remain)
    end
    return true, "READY"
end

--================================================================--
-- Radar reconciliation (occupancy + destruction detection)
--================================================================--
local function cachedRadarList(v, kind, scanFn)
    local cache = v["_scan_" .. kind]
    if not cache or (now() - cache.at) >= SCAN_CACHE_TTL then
        local ok, list = pcall(scanFn)
        if ok then
            cache = { list = list, at = now() }
            v["_scan_" .. kind] = cache
        elseif not cache or (now() - cache.at) > SCAN_CACHE_MAX_AGE then
            v["_scan_" .. kind] = nil
            return nil
        end
    end
    return cache and cache.list or nil
end

local function cachedShips(v, radar)
    return cachedRadarList(v, "ships", function() return radar.scanForShips(9999) end)
end

local function cachedPlayers(v, radar)
    return cachedRadarList(v, "players", function() return radar.scanForPlayers(9999) end)
end

-- Player scan entries expose pos as an array ([1]/[3]) per the sp_radar API.
local function playerXZ(player)
    local pos = type(player) == "table" and player.pos or nil
    if type(pos) ~= "table" then return nil end
    if pos[1] and pos[3] then return pos[1], pos[3] end
    if pos.x and pos.z then return pos.x, pos.z end
    return nil
end

local function shipById(ships, id)
    for _, ship in ipairs(ships or {}) do
        if ship.id == id then return ship end
    end
    return nil
end

-- Remove a deployed tank's bookkeeping (owner mapping, slug -> radar id).
local function cleanupDeployedTank(state, slug, owner)
    if type(state) ~= "table" then return end
    if owner and type(state.playerTankMap) == "table" and state.playerTankMap[owner] == slug then
        state.playerTankMap[owner] = nil
    end
    if type(state.tankslugtoID) == "table" then
        state.tankslugtoID[slug] = nil
    end
end

-- Freeze a ship and teleport it to the reserve depot area. The chunk loader
-- keeps the destination loaded during the teleport.
function vehicles.parkShipAtReserve(reserve, slug)
    local rX = reserve.x + math.random(-100, 100)
    local rY = reserve.y
    local rZ = reserve.z + math.random(-100, 100)

    commands.exec("vs set-static " .. slug .. " true")
    sleep(0.5)
    commands.exec(("fill %d %d %d %d %d %d vscontrolcraft:chunk_loader"):format(rX, rY, rY, rX, rY, rY))
    sleep(0.5)
    commands.exec(("vmod teleport %s %d %d %d"):format(slug, rX, rY, rZ))
    sleep(1.5)
    commands.exec(("vmod teleport %s %d %d %d"):format(slug, rX, rY, rZ))
    sleep(0.5)
    commands.exec(("fill %d %d %d %d %d %d air"):format(rX, rY, rY, rX, rY, rY))
end

-- Recall every ship of a vehicle. A multi-island placement produces slugs
-- <base>0 .. <base>N-1; a single-island one keeps the bare base. Commands
-- against slugs that do not exist fail harmlessly (VMod has no delete), so
-- we also try the bare base to cover legacy slugs and undercounted islands.
function vehicles.parkVehicleShips(reserve, base, shipCount)
    if not reserve or type(base) ~= "string" then return end
    local count = math.max(1, math.floor(tonumber(shipCount) or 1))
    for i = 0, count - 1 do
        vehicles.parkShipAtReserve(reserve, base .. i)
    end
    vehicles.parkShipAtReserve(reserve, base)
end

--================================================================--
-- Destruction marker (owner right-click recalls the vehicle)
--================================================================--
-- Scoreboard criterion: every right-click of the marker increments the
-- owner's gptankmarker score, which processMarkers turns into an instant
-- recall. The objective is per-world and safe to re-add.
function vehicles.ensureMarkerObjective()
    commands.exec("scoreboard objectives add " .. MARKER_OBJECTIVE
        .. " minecraft.used:minecraft.carrot_on_a_stick")
end

-- Exactly one marker in the owner's inventory: clear every matching copy
-- (NBT-exact, real carrot sticks are untouched) then hand out one.
local function ensureMarkerItem(owner, label)
    stripMarker(owner, label)
    commands.exec(("give %s %s 1"):format(owner, markerItemSpec(label)))
end

-- Non-destructive presence check (reading player NBT is allowed). Reuses the
-- give spec's NBT so only OUR marker counts, never a real carrot stick.
local function hasMarker(owner, label)
    local nbt = markerItemSpec(label):match("{.*}$")
    if not nbt then return false end
    return commands.exec(("execute if data entity %s Inventory[{id:\"minecraft:carrot_on_a_stick\",tag:%s}]")
        :format(owner, nbt)) == true
end

local function markerUseCount(owner)
    local ok, out = commands.exec(("scoreboard players get %s %s"):format(owner, MARKER_OBJECTIVE))
    if not ok or type(out) ~= "table" then return 0 end
    local n = tostring(out[1] or ""):match("has%s+(-?%d+)")
    return tonumber(n) or 0
end

-- Free a deployed vehicle slot: forget the entry, recall every ship to the
-- reserve depot and clean up ownership. The respawn cooldown is NOT touched
-- here — under the Battlefield model it runs from spawn time, so freeing the
-- slot only makes the next spawn possible once the cooldown has expired.
-- The owner also loses their marker and marker score.
local function freeVehicle(v, cfg, state, slug, entry)
    cfg.active[slug] = nil
    if v.reserve then
        vehicles.parkVehicleShips(v.reserve, slug, entry.shipCount)
    end
    if entry.owner then
        stripMarker(entry.owner, v.markerLabel)
    end
    cleanupDeployedTank(state, slug, entry.owner)
end

-- Check every deployed vehicle's owner for marker use and keep the marker
-- in their inventory. Call this on the same cadence as reconcile (~1s).
function vehicles.processMarkers(v, state)
    local seenOwners = {}
    for _, tanks in pairs(v.tanks or {}) do
        for _, cfg in pairs(tanks) do
            if type(cfg) == "table" and type(cfg.active) == "table" then
                for slug, entry in pairs(cfg.active) do
                    if type(entry) == "table" and entry.owner then
                        if markerUseCount(entry.owner) > 0 then
                            commands.exec(("scoreboard players set %s %s 0"):format(entry.owner, MARKER_OBJECTIVE))
                            local remain = math.ceil((cfg.cooldownUntil or 0) - now())
                            status(nil, ("Vehicle %s destroyed by %s's marker; %s")
                                :format(slug, entry.owner,
                                    remain > 0 and ("respawn in " .. remain .. "s") or "respawn ready"))
                            commands.exec(("/tellraw %s {\"text\":\"Your %s was sent back to the depot\",\"color\":\"gold\"}")
                                :format(entry.owner, slug))
                            stripMarker(entry.owner, v.markerLabel)
                            freeVehicle(v, cfg, state, slug, entry)
                        elseif not seenOwners[entry.owner] then
                            seenOwners[entry.owner] = true
                            -- Only touch the inventory when the marker is
                            -- actually gone; a constant clear+give makes the
                            -- item flicker in the owner's inventory.
                            if not hasMarker(entry.owner, v.markerLabel) then
                                ensureMarkerItem(entry.owner, v.markerLabel)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Drop destroyed tanks and recall abandoned ones.
-- A tank counts as in use while ANY player is within abandonRadius (blocks,
-- horizontal) of its hull's current position. The owner is warned the moment
-- they leave the radius; after abandonSeconds unattended the whole vehicle —
-- every ship of it — is parked in the reserve depot. The respawn cooldown is
-- never (re)started here: under the Battlefield model it runs from spawn
-- time, so destruction/abandonment only frees the slot. A hull that fully
-- broke apart (radar id gone) destroys the vehicle immediately; any
-- surviving sub-ships are recalled too. Sub-ships that die while the hull
-- lives are only pruned from tracking. Entries saved before multi-ship
-- tracking (scalar id, no ids list) and entries without an id (state
-- restored before a restart) keep working / are dropped so a lost mapping
-- can never deadlock a slot.
function vehicles.reconcile(v, radar, state)
    if not radar then return end
    local ships = cachedShips(v, radar)
    if not ships then return end
    local players = cachedPlayers(v, radar)

    local present = {}
    for _, ship in ipairs(ships) do present[ship.id] = true end

    for _, tanks in pairs(v.tanks) do
        for _, cfg in pairs(tanks) do
            if type(cfg) == "table" and type(cfg.active) == "table" then
                for slug, entry in pairs(cfg.active) do
                    if type(entry) ~= "table" then
                        cfg.active[slug] = nil
                    else
                        -- Pre-multi-ship entries only stored the hull id.
                        if entry.id ~= nil and type(entry.ids) ~= "table" then
                            entry.ids = { entry.id }
                            entry.shipCount = 1
                        end
                        local id = entry.id
                        if not id then
                            cfg.active[slug] = nil
                            cleanupDeployedTank(state, slug, entry.owner)
                        elseif not present[id] then
                            local remain = math.ceil(cfg.cooldownUntil - now())
                            status(nil, ("Tank %s destroyed; %s"):format(slug,
                                remain > 0 and ("respawn in " .. remain .. "s") or "respawn ready"))
                            if entry.owner then
                                commands.exec(("/tellraw %s {\"text\":\"Your %s was destroyed\",\"color\":\"red\"}"):format(entry.owner, slug))
                            end
                            freeVehicle(v, cfg, state, slug, entry)
                        else
                            -- Dead sub-ships while the hull lives: prune only.
                            local alive = {}
                            for _, subId in ipairs(entry.ids or {}) do
                                if present[subId] then table.insert(alive, subId) end
                            end
                            entry.ids = alive

                            local ship = shipById(ships, id)
                            local occupied = false
                            if players and ship then
                                for _, player in ipairs(players) do
                                    local px, pz = playerXZ(player)
                                    if px then
                                        local dx, dz = ship.pos.x - px, ship.pos.z - pz
                                        if dx * dx + dz * dz <= v.abandonRadius * v.abandonRadius then
                                            occupied = true
                                            break
                                        end
                                    end
                                end
                            end
                            if occupied then
                                entry.abandonedSince = nil
                            else
                                local wasUnattended = entry.abandonedSince ~= nil
                                entry.abandonedSince = entry.abandonedSince or now()
                                if not wasUnattended and entry.owner then
                                    commands.exec(("/tellraw %s {\"text\":\"Your %s is abandoned - it counts as destroyed in %ds. Return to it or use your destruction marker.\",\"color\":\"yellow\"}")
                                        :format(entry.owner, slug, math.floor(v.abandonSeconds or 30)))
                                end
                                if now() - entry.abandonedSince >= v.abandonSeconds then
                                    local remain = math.ceil(cfg.cooldownUntil - now())
                                    status(nil, ("Tank %s abandoned; recalled to depot; %s"):format(slug,
                                        remain > 0 and ("respawn in " .. remain .. "s") or "respawn ready"))
                                    if entry.owner then
                                        commands.exec(("/tellraw %s {\"text\":\"Your %s was abandoned and returned to the depot\",\"color\":\"gold\"}"):format(entry.owner, slug))
                                    end
                                    freeVehicle(v, cfg, state, slug, entry)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

--================================================================--
-- Spawn grids
--================================================================--
function vehicles.generateGridPoints(centerX, centerY, centerZ, numX, numZ, spacing)
    local result = {}
    for ix = 1, numX do
        for iz = 1, numZ do
            local offsetX = (ix - math.ceil(numX / 2)) * spacing
            local offsetZ = (iz - math.ceil(numZ / 2)) * spacing
            table.insert(result, { x = centerX + offsetX, y = centerY, z = centerZ + offsetZ })
        end
    end
    return result
end

--================================================================--
-- Radar ship helpers
--================================================================--
function vehicles.tankInSpawnFilter(result, spawnCoord, range)
    local filtered = {}
    for _, ship in ipairs(result or {}) do
        local x, z = ship.pos.x, ship.pos.z
        local horizontal = math.sqrt((spawnCoord.x - x) ^ 2 + (spawnCoord.z - z) ^ 2)
        if horizontal <= range then
            table.insert(filtered, ship)
        end
    end
    return filtered
end

-- All ships that appeared since oldList. VMod can split one schematic
-- placement into several ships (one per disconnected island), so spawn
-- detection must return every new id, not just the heaviest.
function vehicles.filterNewlySpawnedShips(oldList, newList)
    local function exists(ship, list)
        for _, s in ipairs(list) do
            if s.id == ship.id then return true end
        end
        return false
    end
    local found = {}
    for _, ship in ipairs(newList or {}) do
        if not exists(ship, oldList or {}) then
            table.insert(found, ship)
        end
    end
    return found
end

-- Kept for compatibility: heaviest of the newly spawned ships (the hull).
function vehicles.filterNewlySpawnedShip(oldList, newList)
    local highest = nil
    for _, ship in ipairs(vehicles.filterNewlySpawnedShips(oldList, newList)) do
        if not highest or ship.mass > highest.mass then
            highest = ship
        end
    end
    return highest
end

--================================================================--
-- Touch UI: spawn point selection
--================================================================--
function vehicles.selectSpawnPoint(monitor, spawnPoints)
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor_ui.print(monitor, "Select Spawn Location:")

    local y = 2
    local buttonMap = {}
    for _, point in ipairs(spawnPoints) do
        monitor.setCursorPos(2, y)
        monitor.write("[" .. point.name .. "]")
        buttonMap[y] = point
        y = y + 2
    end
    monitor.setCursorPos(2, y)
    monitor.write("[ Cancel ]")
    buttonMap[y] = "cancel"

    while true do
        local ev, side, x, ry = os.pullEvent("monitor_touch")
        local selection = buttonMap[ry]
        if selection == "cancel" then return nil end
        if selection then return selection end
    end
end

--================================================================--
-- Touch UI: tank list with live status and admin maxLive buttons
--================================================================--
function vehicles.selectTankTouch(monitor, availableTanks, v, country)
    local buttonX   = 38
    local xSpacing  = 5
    local labels    = { "+2", "+1", "-1", "-2" }
    local deltas    = {  2,    1,   -1,   -2  }
    local refreshMs = 0.5

    local cancelButtonY = nil
    local rowMap        = {}
    local buttonRegions = {}

    local function render()
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write("Touch a tank to select or modify:")
        monitor.setCursorPos(1, 2)
        monitor.write("Only admin can press the +/- button (maxLive)")

        rowMap        = {}
        buttonRegions = {}

        local y = 3
        for _, name in ipairs(availableTanks) do
            local ok, info = vehicles.available(v, country, name)
            local cfg = vehicles.ensure(v, country, name) or { maxLive = 1 }
            local live = vehicles.liveCount(v, country, name)
            local statusText = ok and info or (info .. (" [%d/%d]"):format(live, cfg.maxLive))

            monitor.setCursorPos(2, y)
            monitor.write(("- %s  %s"):format(name, statusText))
            rowMap[y] = name

            for i, label in ipairs(labels) do
                local x = buttonX + (i - 1) * xSpacing
                local btnText = "[" .. label .. "]"
                monitor.setCursorPos(x, y)
                monitor.write(btnText)
                table.insert(buttonRegions, {
                    y = y, xStart = x, xEnd = x + #btnText - 1, tank = name, delta = deltas[i],
                })
            end
            y = y + 1
        end

        monitor.setCursorPos(2, y)
        monitor.write("[ Cancel ]")
        cancelButtonY = y
    end

    render()
    local timer = os.startTimer(refreshMs)

    while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "monitor_touch" then
            local x, ty = b, c
            if ty == cancelButtonY and x >= 2 and x <= 12 then
                return nil
            end

            local handled = false
            for _, btn in ipairs(buttonRegions) do
                if ty == btn.y and x >= btn.xStart and x <= btn.xEnd then
                    print("\nAdmin modification request:")
                    print("  Tank: " .. btn.tank)
                    print("  Change maxLive: " .. (btn.delta >= 0 and "+" or "") .. btn.delta)
                    io.write("Press Enter within 3 seconds to confirm... ")

                    local t = os.startTimer(3)
                    local confirmed = false
                    while true do
                        local ev2, p = os.pullEvent()
                        if ev2 == "timer" and p == t then
                            print(" (timed out)")
                            break
                        elseif ev2 == "key" and p == keys.enter then
                            confirmed = true
                            break
                        end
                    end

                    if confirmed then
                        local cfg = vehicles.ensure(v, country, btn.tank)
                        if cfg then
                            cfg.maxLive = math.max(1, cfg.maxLive + btn.delta)
                            print("Change applied. New maxLive for " .. btn.tank .. ": " .. cfg.maxLive)
                        end
                    end
                    render()
                    timer = os.startTimer(refreshMs)
                    handled = true
                    break
                end
            end

            if not handled then
                local selectedTank = rowMap[ty]
                if selectedTank and x < (buttonX - 2) then
                    return selectedTank
                end
            end
        elseif ev == "timer" and a == timer then
            render()
            timer = os.startTimer(refreshMs)
        end
    end
end

--================================================================--
-- Full tank spawn flow (VMod schematic placement)
--================================================================--
-- ctx = {
--   v, monitor, radar, player, mission,
--   spawnPoint (from vehicleSpawns), tankName, country,
--   playerTankMap, tankslugtoID, repairKits, checkpoint,
-- }
-- Returns true when a tank was spawned from the schematic.
function vehicles.spawnTank(ctx)
    local v = ctx.v
    local country = ctx.country
    local mission = ctx.mission
    local radar = ctx.radar
    local monitor = ctx.monitor
    local player = ctx.player

    local cfg = vehicles.ensure(v, country, ctx.tankName)
    if not cfg then
        status(monitor, "Unknown tank type " .. tostring(ctx.tankName))
        return false
    end

    local ready, readyInfo = vehicles.available(v, country, ctx.tankName)
    if not ready then
        status(monitor, "Tank unavailable: " .. tostring(readyInfo))
        return false
    end

    local spawnPoint = ctx.spawnPoint
    local grid = vehicles.generateGridPoints(
        spawnPoint.x, spawnPoint.y, spawnPoint.z,
        mission.numPointsX or 3, mission.numPointsZ or 3, mission.spacing or 20)

    local point = grid[v.pointIndex]
    local finalX, finalY, finalZ
    if spawnPoint.useGrid then
        finalX, finalY, finalZ = point.x, spawnPoint.y, point.z
    else
        finalX, finalY, finalZ = spawnPoint.x, spawnPoint.y, spawnPoint.z
    end
    local offset = cfg.anchorOffset
    if type(offset) == "table" then
        finalX = finalX + (tonumber(offset.x) or 0)
        finalY = finalY + (tonumber(offset.y) or 0)
        finalZ = finalZ + (tonumber(offset.z) or 0)
    end
    local target = { x = finalX, y = finalY, z = finalZ }

    -- Park the player's previous tank (every ship of it) in the reserve
    -- depot (frozen).
    local oldTank = ctx.playerTankMap[player]
    if oldTank then
        status(monitor, "Moving old tank " .. oldTank .. " to reserve area...")
        local oldInfo = ctx.tankslugtoID and ctx.tankslugtoID[oldTank] or nil
        vehicles.parkVehicleShips(v.reserve or mission.reserve, oldTank, oldInfo and oldInfo.shipCount or 1)
    end

    -- /vmod schem place reports success even when it fails, so the radar
    -- diff below is the only trustworthy confirmation that a ship appeared.
    -- Empirically (VMod 0.1.3): the load name must include the .vschem
    -- extension, and place requires a parenthesized rotation.
    local schematic = cfg.schematic or ctx.tankName
    if schematic:sub(-7) ~= ".vschem" then schematic = schematic .. ".vschem" end

    local deployed = false
    local baseName = nil
    local spawnedShips = {}

    for _ = 1, 2 do
        -- VMod 0.1.3 returns a failure status even when load/place succeed,
        -- so the command results are ignored entirely; the radar diff below
        -- is the only trustworthy confirmation that a ship appeared.
        status(monitor, "Loading schematic " .. schematic .. "...")
        commands.exec("vmod schem load-from-sever " .. schematic)

        -- The vehicle number is only committed after a confirmed spawn, so
        -- failed attempts never consume one. The trailing dash keeps our
        -- number visually separate from VMod's glued-on ship index.
        local candidate = cfg.counter + 1
        baseName = ctx.tankName .. "-" .. candidate .. "-"

        commands.exec(("fill %d %d %d %d %d %d vscontrolcraft:chunk_loader"):format(finalX, finalY, finalZ, finalX, finalY, finalZ))
        sleep(0.5)

        -- Fresh baseline for every attempt so ships left over from the
        -- previous attempt are never attributed to this one.
        local oldScan = radar.scanForShips(9999)
        local oldInSpawn = vehicles.tankInSpawnFilter(oldScan, target, SPAWN_RADIUS)

        -- VMod 0.1.3 requires the rotation argument before the name, and
        -- the vector must be parenthesized: (pitch yaw roll).
        local placeCmd = ("vmod schem place %d %d %d"):format(finalX, finalY, finalZ)
        local rot = type(cfg.rotation) == "table" and cfg.rotation or {}
        placeCmd = placeCmd .. (" (%d %d %d)"):format(rot[1] or 0, rot[2] or 0, rot[3] or 0)
        placeCmd = placeCmd .. " " .. baseName

        status(monitor, ("Placing vehicle %s at X:%d Y:%d Z:%d"):format(baseName, finalX, finalY, finalZ))
        commands.exec(placeCmd)

        local deadline = now() + PLACE_POLL_TIMEOUT
        while now() < deadline do
            sleep(PLACE_POLL_INTERVAL)
            local newScan = radar.scanForShips(9999)
            local newInSpawn = vehicles.tankInSpawnFilter(newScan, target, SPAWN_RADIUS)
            local ships = vehicles.filterNewlySpawnedShips(oldInSpawn, newInSpawn)
            if #ships > 0 then
                -- VMod queues ship creation, so sibling islands can unfreeze
                -- a moment after the first one; give them time to show up.
                sleep(2)
                local late = vehicles.filterNewlySpawnedShips(oldInSpawn,
                    vehicles.tankInSpawnFilter(radar.scanForShips(9999), target, SPAWN_RADIUS))
                for _, lateShip in ipairs(late) do
                    local seen = false
                    for _, s in ipairs(ships) do
                        if s.id == lateShip.id then seen = true break end
                    end
                    if not seen then table.insert(ships, lateShip) end
                end
                deployed = true
                spawnedShips = ships
                break
            end
        end

        commands.exec(("fill %d %d %d %d %d %d air"):format(finalX, finalY, finalZ, finalX, finalY, finalZ))

        if deployed then
            cfg.counter = candidate
            -- Battlefield model: the respawn cooldown for this type starts
            -- the moment a vehicle deploys, not when it dies.
            cfg.cooldownUntil = now() + cfg.cooldown
            v.pointIndex = v.pointIndex + 1
            if v.pointIndex > #grid then v.pointIndex = 1 end
            break
        end
        status(monitor, "Placement not detected, retrying...")
    end

    if not deployed or not baseName or #spawnedShips == 0 then
        status(monitor, "Tank placement failed for " .. ctx.tankName)
        return false
    end

    -- Heaviest island is treated as the hull; player TP and infantry spawn
    -- anchor to it. Slug-wise the hull is <base>0 for multi-island
    -- placements and the bare base for a single-island schematic.
    local mainShip = spawnedShips[1]
    for _, s in ipairs(spawnedShips) do
        if (tonumber(s.mass) or 0) > (tonumber(mainShip.mass) or 0) then mainShip = s end
    end
    local ids = {}
    for _, s in ipairs(spawnedShips) do table.insert(ids, s.id) end
    local hullSlug = #spawnedShips > 1 and (baseName .. "0") or baseName

    cfg.active[baseName] = {
        id = mainShip.id,
        ids = ids,
        shipCount = #spawnedShips,
        deployedAt = now(),
        owner = player,
    }
    ctx.playerTankMap[player] = baseName

    local extra = cfg.extraCrewCount or 0
    ctx.tankslugtoID[baseName] = {
        id = mainShip.id,
        ids = ids,
        shipCount = #spawnedShips,
        crewSpawnLeft = extra,
        mass = mainShip.mass,
    }

    commands.exec(("give %s create_tweaked_controllers:tweaked_linked_controller{display:{Name:'{\"text\":\"%s\"}'}}"):format(player, hullSlug))

    for _, item in ipairs(ctx.repairKits or {}) do
        commands.exec(("give %s %s %d"):format(player, item.item or item.id, item.count or 1))
    end

    -- Owner always carries exactly one destruction marker (right-click
    -- recalls the vehicle); reset any stale marker score first.
    ensureMarkerItem(player, v.markerLabel)

    commands.exec(("tp %s %d %d %d"):format(player, finalX, finalY + 2, finalZ))
    -- Tankers deploy straight into battle in survival; the old creative
    -- staging area around the vehicle spawns is gone.
    commands.exec("/gamemode survival " .. player)
    commands.exec(("tellraw %s {\"text\":\"Right click controller hub to link\",\"color\":\"yellow\"}"):format(player))
    sleep(1)
    commands.exec("kill @e[type=trackwork:wheel_entity]")

    if ctx.checkpoint then ctx.checkpoint("vehicle deployed") end
    status(monitor, ("Vehicle deployed: %s (%d ship%s)"):format(hullSlug, #spawnedShips, #spawnedShips == 1 and "" or "s"))
    return true
end

return vehicles
