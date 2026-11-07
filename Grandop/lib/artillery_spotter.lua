-- Grandop artillery spotter.
-- Persistent spyglass designation flow for command-computer missions.

local spotter = {}

local USE_OBJECTIVE = "gp_art_spy"
local SHELL_OBJECTIVE = "gp_art_shell"
local PATTERN_OBJECTIVE = "gp_art_pattern"
local COUNT_OBJECTIVE = "gp_art_count"
local CONFIRM_OBJECTIVE = "gp_art_confirm"
local RESET_OBJECTIVE = "gp_art_reset"
local AGE_OBJECTIVE = "gp_art_age"
local SESSION_TAG = "gp_art_session"
local DEFAULT_LABEL = "Artillery Spotter"
local DEFAULT_CHANNEL = 9001
local DEFAULT_RANGE = 256
local DEFAULT_STEP = 2
local DEFAULT_TIMEOUT = 45
local DEFAULT_MODEM_SIDE = "right"
local SHELLS = { [1] = "he", [2] = "smoke" }
local COUNTS = { [1] = 3, [2] = 6 }

local PATTERNS = { [1] = "concentrated", [2] = "area" }

local sessions = {}
local requestSequence = 0

local function json(value) return textutils.serialiseJSON(value) end
local function score(name, objective)
    local ok, output = commands.exec(("scoreboard players get %s %s"):format(name, objective))
    if not ok then return 0 end
    if type(output) == "number" then return output end
    for _, line in ipairs(output or {}) do
        local n = tostring(line):match("has%s+(-?%d+)")
        if n then return tonumber(n) end
    end
    return 0
end
local function setScore(name, objective, value)
    commands.exec(("scoreboard players set %s %s %d"):format(name, objective, value or 0))
end
local function enable(name, objective) commands.exec(("scoreboard players enable %s %s"):format(name, objective)) end

local function spyglassSpec(label)
    label = label or DEFAULT_LABEL
    return ("minecraft:spyglass{display:{Name:'{\"text\":\"%s\",\"color\":\"gold\",\"italic\":false}'}}"):format(label)
end
local function hasSpyglass(name, label)
    local spec = spyglassSpec(label)
    local nbt = spec:match("{.*}$")
    return commands.exec(("execute if data entity %s Inventory[{id:\"minecraft:spyglass\",tag:%s}]"):format(name, nbt)) == true
end
local function ensureSpyglass(name, label)
    local spec = spyglassSpec(label)
    commands.exec(("scoreboard players set %s %s 0"):format(name, USE_OBJECTIVE))
    commands.exec("clear " .. name .. " " .. spec)
    commands.exec("give " .. name .. " " .. spec .. " 1")
end

local function factionOf(teams, name)
    for team, faction in pairs(teams or {}) do
        if commands.exec(("execute if entity @a[team=%s,name=\"%s\"]"):format(team, name)) then
            return faction, team
        end
    end
    return nil
end
local function playerNames(radar)
    if not radar then return {} end
    local ok, result = pcall(radar.scanForPlayers, 9999)
    if not ok or type(result) ~= "table" then return {} end
    return result
end
local function tell(name, value)
    commands.exec("tellraw " .. name .. " " .. json(value))
end
local function menu(name, title, entries)
    local page = { { text = title .. "\n\n", color = "gold", bold = true } }
    for _, e in ipairs(entries) do
        page[#page + 1] = { text = "[ " .. e.label .. " ]\n", color = e.color or "green",
            clickEvent = { action = "run_command", value = e.command } }
    end
    page[#page + 1] = { text = "[ Reset menu ]\n", color = "red",
        clickEvent = { action = "run_command", value = "/trigger " .. RESET_OBJECTIVE .. " set 1" } }
    tell(name, page)
end

local function readNumbers(lines)
    local values = {}
    if type(lines) == "string" then lines = { lines } end
    for _, line in ipairs(lines or {}) do
        for n in tostring(line):gmatch("([%-]?%d+%.?%d*)[fd]?") do values[#values + 1] = tonumber(n) end
    end
    return values
end
local function entityVector(name)
    local okPos, posLines = commands.exec(("execute as %s run data get entity @s Pos"):format(name))
    local okRot, rotLines = commands.exec(("execute as %s run data get entity @s Rotation"):format(name))
    if not okPos or not okRot then return nil end
    local p, r = readNumbers(posLines), readNumbers(rotLines)
    if #p < 3 or #r < 2 then return nil end
    local yaw, pitch = math.rad(r[1]), math.rad(r[2])
    local cp = math.cos(pitch)
    return p[1], p[2] + 1.62, p[3], -math.sin(yaw) * cp, -math.sin(pitch), math.cos(yaw) * cp
end

local function rayTarget(name, cfg)
    local x, y, z, dx, dy, dz = entityVector(name)
    if not x then return nil, "position unavailable" end
    local maxRange = cfg.maxRange or DEFAULT_RANGE
    local step = cfg.rayStep or DEFAULT_STEP
    local lastX, lastY, lastZ = x, y, z
    for distance = step, maxRange, step do
        local sx, sy, sz = x + dx * distance, y + dy * distance, z + dz * distance
        local ix, iy, iz = math.floor(sx), math.floor(sy), math.floor(sz)
        local replaceable = commands.exec(("execute if block %d %d %d #minecraft:replaceable"):format(ix, iy, iz))
        if replaceable ~= true then
            return math.floor(lastX + 0.5), math.floor(lastZ + 0.5)
        end
        lastX, lastY, lastZ = sx, sy, sz
    end
    return math.floor(lastX + 0.5), math.floor(lastZ + 0.5)
end

local function clearSession(name)
    sessions[name] = nil
    commands.exec(("tag %s remove %s"):format(name, SESSION_TAG))
    for _, objective in ipairs({ SHELL_OBJECTIVE, COUNT_OBJECTIVE, PATTERN_OBJECTIVE, CONFIRM_OBJECTIVE, RESET_OBJECTIVE, AGE_OBJECTIVE }) do
        setScore(name, objective, 0)
        enable(name, objective)
    end
end
local function resetWithMessage(name, label)
    clearSession(name)
    ensureSpyglass(name, label)
    tell(name, { text = "Artillery menu reset.", color = "green" })
end
local function startSession(name, cfg, faction, team)
    local x, z, err = rayTarget(name, cfg)
    if not x then tell(name, { text = "Unable to designate target: " .. tostring(err), color = "red" }); return end
    sessions[name] = { phase = "shell", x = x, z = z, faction = faction, team = team, started = os.epoch("utc") / 1000 }
    commands.exec(("tag %s add %s"):format(name, SESSION_TAG))
    menu(name, "Artillery target: " .. x .. ", " .. z, {
        { label = "HE", command = "/trigger " .. SHELL_OBJECTIVE .. " set 1" },
        { label = "Smoke", command = "/trigger " .. SHELL_OBJECTIVE .. " set 2" },
    })
end
local function nextRequestId(name)
    requestSequence = requestSequence + 1
    return (os.getComputerID and os.getComputerID() or 0) .. "-" .. name .. "-" .. tostring(requestSequence)
end

local function denialText(msg)
    if msg.reason == "cooldown" or (tonumber(msg.remaining) or 0) > 0 then
        local seconds = math.ceil(math.max(0, tonumber(msg.remaining) or 0))
        return ("Artillery is cooling down. Please wait %dm %ds."):format(math.floor(seconds / 60), seconds % 60)
    end
    return "Artillery denied: " .. tostring(msg.reason or "unavailable")
end

local function handleSession(name, cfg, modem)
    local s = sessions[name]
    if not s then return end
    if score(name, RESET_OBJECTIVE) > 0 then
        setScore(name, RESET_OBJECTIVE, 0); resetWithMessage(name, cfg.label); return
    end
    local now = os.epoch("utc") / 1000
    if now - s.started > (cfg.timeout or DEFAULT_TIMEOUT) then
        resetWithMessage(name, cfg.label); return
    end
    if s.phase == "shell" and score(name, SHELL_OBJECTIVE) > 0 then
        local choice = score(name, SHELL_OBJECTIVE); setScore(name, SHELL_OBJECTIVE, 0); enable(name, SHELL_OBJECTIVE)
        if SHELLS[choice] then
            s.shell = SHELLS[choice]; s.phase = "count"
            menu(name, "Shell: " .. s.shell:upper(), {
                { label = "3 shells", command = "/trigger " .. COUNT_OBJECTIVE .. " set 1" },
                { label = "6 shells", command = "/trigger " .. COUNT_OBJECTIVE .. " set 2" },
            })
        end
    elseif s.phase == "count" and score(name, COUNT_OBJECTIVE) > 0 then
        local choice = score(name, COUNT_OBJECTIVE); setScore(name, COUNT_OBJECTIVE, 0); enable(name, COUNT_OBJECTIVE)
        if COUNTS[choice] then
            s.shells = COUNTS[choice]; s.phase = "pattern"
            menu(name, s.shell == "smoke" and "Pattern (HE only; smoke spread unchanged)" or "HE impact pattern", {
                { label = "Concentrated", command = "/trigger " .. PATTERN_OBJECTIVE .. " set 1" },
                { label = "Area", command = "/trigger " .. PATTERN_OBJECTIVE .. " set 2" },
            })
        end
    elseif s.phase == "pattern" and score(name, PATTERN_OBJECTIVE) > 0 then
        local choice = score(name, PATTERN_OBJECTIVE); setScore(name, PATTERN_OBJECTIVE, 0); enable(name, PATTERN_OBJECTIVE)
        if PATTERNS[choice] then
            s.pattern = PATTERNS[choice]; s.phase = "confirm"
            menu(name, ("Confirm %s x%d / %s at %d, %d"):format(s.shell:upper(), s.shells, s.shell == "smoke" and "smoke spread unchanged" or s.pattern, s.x, s.z), {
                { label = "FIRE", command = "/trigger " .. CONFIRM_OBJECTIVE .. " set 1", color = "gold" },
            })
        end
    elseif s.phase == "confirm" and score(name, CONFIRM_OBJECTIVE) > 0 then
        setScore(name, CONFIRM_OBJECTIVE, 0); enable(name, CONFIRM_OBJECTIVE)
        if modem then
            s.requestId = nextRequestId(name)
            local packet = {
                type = "fire_mission", requestId = s.requestId, player = name,
                faction = s.faction, team = s.team,
                x = s.x, z = s.z, shells = s.shells, shell = s.shell, pattern = s.pattern,
                t = os.epoch("utc"),
            }
            s.phase = "await_ack"
            local ack = cfg.submit and cfg.submit(packet)
            if ack then
                spotter.handleMessage(ack)
            elseif modem then
                modem.transmit(cfg.channel or DEFAULT_CHANNEL, cfg.replyChannel or (10000 + os.getComputerID()), packet)
                tell(name, { text = "Artillery request sent.", color = "yellow" })
            else
                resetWithMessage(name, cfg.label)
                tell(name, { text = "Artillery radio unavailable.", color = "red" })
            end
        end
    end
end

function spotter.ensureObjectives()
    commands.exec("scoreboard objectives add " .. USE_OBJECTIVE .. " minecraft.used:minecraft.spyglass")
    for _, objective in ipairs({ SHELL_OBJECTIVE, COUNT_OBJECTIVE, PATTERN_OBJECTIVE, CONFIRM_OBJECTIVE, RESET_OBJECTIVE, AGE_OBJECTIVE }) do
        commands.exec("scoreboard objectives add " .. objective .. " trigger")
    end
end

function spotter.process(ctx, modem)
    local cfg = ctx and ctx.respawn and ctx.respawn.artillerySpotter
    if type(cfg) ~= "table" or (not ctx.standalone and cfg.activeWhen and not cfg.activeWhen()) then return end
    local label = cfg.label or DEFAULT_LABEL
    local seen = {}
    for _, p in ipairs(playerNames(ctx.radar)) do
        local name = type(p) == "table" and p.nickname or nil
        if name and factionOf(ctx.teams, name) then
            local faction, team = factionOf(ctx.teams, name)
            seen[name] = true
            if not hasSpyglass(name, label) then ensureSpyglass(name, label) end
            for _, objective in ipairs({ SHELL_OBJECTIVE, COUNT_OBJECTIVE, PATTERN_OBJECTIVE, CONFIRM_OBJECTIVE, RESET_OBJECTIVE }) do enable(name, objective) end
            if not sessions[name] and score(name, USE_OBJECTIVE) > 0 then
                setScore(name, USE_OBJECTIVE, 0)
                if hasSpyglass(name, label) then
                    if cfg.queryStatus then
                        local status = cfg.queryStatus({ player = name })
                        if status and status.ok then startSession(name, cfg, status.faction, status.team)
                        else tell(name, { text = denialText(status or {}), color = "red" }) end
                    elseif modem then
                        local requestId = nextRequestId(name)
                        sessions[name] = { phase = "await_status", requestId = requestId, cfg = cfg,
                            started = os.epoch("utc") / 1000 }
                        modem.transmit(cfg.channel or DEFAULT_CHANNEL, cfg.replyChannel or (10000 + os.getComputerID()),
                            { type = "status_request", requestId = requestId, player = name })
                    else
                        tell(name, { text = "Artillery radio unavailable.", color = "red" })
                    end
                end
            elseif sessions[name] then
                handleSession(name, cfg, modem)
            end
        end
    end
    for name in pairs(sessions) do
        if not seen[name] or not factionOf(ctx.teams, name) then clearSession(name) end
    end
end

function spotter.handleMessage(msg)
    local s = msg and sessions[msg.player]
    if s and msg.type == "artillery_status" and s.phase == "await_status" and msg.requestId == s.requestId then
        if msg.ok then startSession(msg.player, s.cfg, msg.faction, msg.team)
        else
            tell(msg.player, { text = denialText(msg), color = "red" })
            clearSession(msg.player)
        end
        return true
    end
    if s and msg.type == "mission_ack" and msg.requestId == s.requestId then
        tell(msg.player, { text = msg.accepted and "Artillery mission accepted. First shells in approximately 15 seconds (simulated delay plus projectile fall)." or denialText(msg), color = msg.accepted and "green" or "red" })
        clearSession(msg.player)
        return true
    end
    return false
end

function spotter.run(ctx)
    local cfg = ctx and ctx.respawn and ctx.respawn.artillerySpotter
    if type(cfg) ~= "table" then while true do sleep(1) end end
    spotter.ensureObjectives()
    local modem = peripheral.getType(cfg.modemSide or DEFAULT_MODEM_SIDE) == "modem"
        and peripheral.wrap(cfg.modemSide or DEFAULT_MODEM_SIDE) or nil
    if modem then modem.open(cfg.replyChannel or (10000 + os.getComputerID())) end
    while true do
        spotter.process(ctx, modem)
        if modem then
            local timer = os.startTimer(1)
            local event = { os.pullEventRaw() }
            if event[1] == "timer" and event[2] == timer then
                -- Process scoreboard-triggered clicks on the next loop.
            elseif event[1] == "modem_message" then
                spotter.handleMessage(event[5])
            end
        else
            sleep(1)
        end
    end
end

spotter._test = { rayTarget = rayTarget, entityVector = entityVector, shellFor = SHELLS, countFor = COUNTS, patternFor = PATTERNS }
return spotter
