-- Run from the repository root with desktop Lua 5.1. No Minecraft files are touched.
local desktopLoadfile = loadfile
local server = assert(desktopLoadfile("Grandop/programs/artillery_server.lua"))
local spotter = assert(desktopLoadfile("Grandop/lib/artillery_spotter.lua"))()
local cfg = {}
local mission = { teams = { red = "allies", blue = "axis" },
    respawn = { artillerySpotter = cfg } }
local players = { Alice = "red", Bob = "red", Carol = "blue" }
local scores, shots, acknowledgements, notices = {}, {}, {}, {}
local activePlayer
local raycasts, menus = 0, 0
local modem = {
    open = function() end,
    transmit = function() error("Local submissions must not require modem loopback") end,
}
local function setScore(player, objective, value)
    scores[player] = scores[player] or {}
    scores[player][objective] = value
end
commands = { exec = function(command)
    local team, player = command:match('^execute if entity @a%[team=([^,]+),name="([^"]+)"%]$')
    if team then return players[player] == team end
    local name, objective = command:match("^scoreboard players get (%S+) (%S+)$")
    if name then return true, (scores[name] or {})[objective] or 0 end
    local value
    name, objective, value = command:match("^scoreboard players set (%S+) (%S+) (%-?%d+)$")
    if name then setScore(name, objective, tonumber(value)); return true end
    if command:match("^execute if data entity ") then return true end
    if command:match("run data get entity @s Pos$") then raycasts = raycasts + 1; return true, { "[100d, 64d, 200d]" } end
    if command:match("run data get entity @s Rotation$") then return true, { "[0f, 0f]" } end
    if command:match("^execute if block ") then return false end
    if command:match("^/summon ") then shots[#shots + 1] = command; return true end
    if command:match("^tellraw ") then notices[#notices + 1] = command; return true end
    if command:match("^scoreboard objectives add ") or command:match("^scoreboard players enable ")
        or command:match("^tag ") then return true end
    error("Unexpected command: " .. command)
end }
textutils = { serialiseJSON = function(value)
    if not value.text then menus = menus + 1 end
    return value.text or "menu"
end }
peripheral = {
    find = function(kind)
        assert(kind == "sp_radar")
        return { scanForPlayers = function()
            return { { nickname = "Alice" }, { nickname = "Bob" }, { nickname = "Carol" } }
        end }
    end,
    getType = function() return "modem" end,
    wrap = function() return modem end,
}
local clock = 1000
os.epoch = function() return clock * 1000 end
os.getComputerID = function() return 19 end
os.pullEvent = function() error("Listener must not be needed for local submission") end
sleep = function(seconds) coroutine.yield(seconds) end
loadfile = function(path)
    if path == "/lib/artillery_spotter.lua" then return function() return spotter end end
    if path == "/missions/test.lua" then return function() return mission end end
    error("Unexpected CC loadfile: " .. path)
end
local realHandleMessage = spotter.handleMessage
spotter.handleMessage = function(ack)
    acknowledgements[#acknowledgements + 1] = ack
    assert(realHandleMessage(ack), "Callback acknowledgement must match an active spotter session")
    return true
end
local function resume(thread)
    local ok, result = coroutine.resume(thread)
    assert(ok, result)
    assert(coroutine.status(thread) == "suspended", "Service loop unexpectedly stopped")
    return result
end
parallel = { waitForAny = function(listener, worker, spotterLoop)
    assert(type(listener) == "function")
    local spotterThread, workerThread = coroutine.create(spotterLoop), coroutine.create(worker)
    local function submit(player, shellChoice, countChoice, patternChoice)
        activePlayer = player
        setScore(player, "gp_art_spy", 1)
        resume(spotterThread)
        assert(type(cfg.submit) == "function", "Server must install its local submit callback")
        setScore(player, "gp_art_shell", shellChoice)
        resume(spotterThread)
        setScore(player, "gp_art_count", countChoice or 1)
        resume(spotterThread)
        setScore(player, "gp_art_pattern", patternChoice or 1)
        resume(spotterThread)
        setScore(player, "gp_art_confirm", 1)
        local before = #acknowledgements
        resume(spotterThread)
        assert(#acknowledgements == before + 1, "Confirmation must synchronously acknowledge")
        local ack = acknowledgements[#acknowledgements]
        assert(ack.type == "mission_ack" and ack.player == player)
        assert(ack.team == players[player] and ack.requestId:find(player, 1, true))
        assert(scores[player].gp_art_confirm == 0)
        return ack
    end
    local function drainWorker(count, interval)
        for i = 1, count do
            resume(workerThread)
            clock = clock + interval
        end
    end
    -- Bob designates before Alice submits, so his eventual confirmation must
    -- still pass the authoritative final admission check.
    activePlayer = "Bob"
    setScore("Bob", "gp_art_spy", 1)
    resume(spotterThread)
    assert(cfg.queryStatus({ player = "Bob", faction = "axis" }).faction == "allies")
    local first = submit("Alice", 1)
    assert(first.accepted and first.faction == "allies" and first.cooldown == 90)
    assert(first.x == 100 and first.z == 200 and first.shells == 3 and first.shell == "he")
    assert(#shots == 0, "Acceptance must queue work for the worker")
    assert(first.pattern == "concentrated" and first.firstShellDelay == 15)
    resume(workerThread)
    clock = 1014.9; resume(workerThread)
    assert(#shots == 0, "No projectile before acceptance + 15 seconds")
    clock = 1015
    drainWorker(3, 1)
    assert(#shots == 3, "Accepted local mission must fire exactly three shells")
    for _, command in ipairs(shots) do assert(command:match("^/summon crusty_chunks:artillery_fire_projectile ")) end
    activePlayer = "Bob"
    setScore("Bob", "gp_art_shell", 1); resume(spotterThread)
    setScore("Bob", "gp_art_count", 1); resume(spotterThread)
    setScore("Bob", "gp_art_pattern", 2); resume(spotterThread)
    setScore("Bob", "gp_art_confirm", 1); resume(spotterThread)
    local blocked = acknowledgements[#acknowledgements]
    assert(not blocked.accepted and blocked.reason == "cooldown" and blocked.remaining == 72)
    assert(blocked.faction == "allies", "Cooldown must be shared by teammates")
    local beforeRays, beforeMenus, beforeAcks = raycasts, menus, #acknowledgements
    setScore("Bob", "gp_art_spy", 1); resume(spotterThread)
    assert(raycasts == beforeRays and menus == beforeMenus, "Cooldown must reject before raycast and menus")
    assert(#acknowledgements == beforeAcks, "Early rejection must not submit a mission")
    assert(scores.Bob.gp_art_spy == 0, "Early rejection must consume the designation")
    resume(workerThread)
    assert(#shots == 3, "Rejected mission must not queue shells")
    local other = submit("Carol", 2, 2, 2)
    assert(other.accepted and other.faction == "axis" and other.cooldown == 150)
    assert(other.shell == "smoke")
    assert(other.pattern == "area" and other.shells == 6)
    resume(workerThread)
    assert(#shots == 3)
    clock = clock + 15
    drainWorker(6, 0.5)
    assert(#shots == 9, "Other team's six-shell mission must fire independently")
    for i = 4, 9 do assert(shots[i]:match("^/summon cbcmodernwarfare:smoke_mediumshell ")) end
    local function packet(id, pattern, count)
        return { requestId=id, player="Alice", x=100, z=200, shell="he", shells=count or 3, pattern=pattern }
    end
    assert(not cfg.submit(packet("bad-pattern", "square")).accepted)
    assert(not cfg.submit(packet("bad-count", "area", 10)).accepted)
    assert(not cfg.submit(packet("fractional-count", "area", 3.5)).accepted)
    clock = 1200
    local legacy = cfg.submit(packet("legacy"))
    assert(legacy.accepted and legacy.pattern == "concentrated")
    assert(not cfg.submit(packet("legacy")).accepted, "Duplicate requests must be rejected")
    -- A future job at the head must not block another faction's ready job.
    clock = 1190
    local area = packet("area", "area", 6); area.player = "Carol"
    assert(cfg.submit(area).accepted)
    clock = 1205; resume(workerThread)
    assert(#shots == 10, "Ready job behind future head must fire")
    clock = 1215; drainWorker(12, 1)
    local completions = 0
    for _, notice in ipairs(notices) do
        if notice:find("Artillery mission complete:", 1, true) then completions = completions + 1 end
    end
    assert(completions == 4, "Requester must receive completion for each dispatched salvo")
    -- Exercise both patterns through real acceptance and worker paths.
    math.randomseed(12345)
    local savedPrint = print
    print = function() end
    local stats = { concentrated={n=0,x=0,z=0,r2=0}, area={n=0,x=0,z=0,r2=0} }
    for i = 1, 600 do
        clock = 2000 + i * 200
        local pattern = i % 2 == 0 and "area" or "concentrated"
        local before = #shots
        assert(cfg.submit(packet("sample" .. i, pattern, 6)).accepted)
        clock = clock + 15; drainWorker(6, 1)
        local st = stats[pattern]
        local cap = pattern == "area" and 45 or 22
        for j = before + 1, #shots do
            local x, z = shots[j]:match(" (%-?%d+) 350 (%-?%d+)$")
            local dx, dz = tonumber(x)-100, tonumber(z)-200
            local r2 = dx*dx + dz*dz
            assert(r2 <= cap*cap, "Gaussian samples must stay within circular cap")
            st.n=st.n+1; st.x=st.x+dx; st.z=st.z+dz; st.r2=st.r2+r2
        end
    end
    print = savedPrint
    for pattern, st in pairs(stats) do
        assert(st.n == 1800)
        assert(math.abs(st.x/st.n) < 1 and math.abs(st.z/st.n) < 1, "Distribution must center on designation")
        local expected = pattern == "area" and 472 or 94
        assert(math.abs(st.r2/st.n - expected) < expected*0.15, "Spread must match selected Gaussian")
    end
    local accepted, denied = 0, 0
    for _, notice in ipairs(notices) do
        if notice:find("Artillery mission accepted.", 1, true) then
            assert(notice:find("First shells in approximately 15 seconds (simulated delay plus projectile fall).", 1, true))
            accepted = accepted + 1
        end
        if notice:find("Artillery is cooling down. Please wait 1m 12s.", 1, true) then denied = denied + 1 end
    end
    assert(accepted == 2 and denied == 2, "Both early and final denials must explain the cooldown")
end }
server("test")
-- Embedded spotters must wait for a matching remote status before targeting.
local remote = assert(desktopLoadfile("Grandop/lib/artillery_spotter.lua"))()
local packets = {}
local radio = { transmit = function(_, _, packet) packets[#packets + 1] = packet end }
local context = { teams = mission.teams, radar = peripheral.find("sp_radar"),
    respawn = { artillerySpotter = {} } }
setScore("Alice", "gp_art_spy", 1)
local beforeRays, beforeMenus = raycasts, menus
remote.process(context, radio)
local request = packets[#packets]
assert(request.type == "status_request" and request.player == "Alice")
assert(raycasts == beforeRays and menus == beforeMenus)
assert(not remote.handleMessage({ type="artillery_status", player="Alice", requestId="stale", ok=true }))
assert(remote.handleMessage({ type="artillery_status", player="Alice", requestId=request.requestId,
    ok=false, reason="cooldown", remaining=100 }))
assert(raycasts == beforeRays and menus == beforeMenus)
setScore("Alice", "gp_art_spy", 1)
remote.process(context, radio)
request = packets[#packets]
assert(remote.handleMessage({ type="artillery_status", player="Alice", requestId=request.requestId,
    ok=true, faction="allies", team="red" }))
assert(raycasts == beforeRays + 1 and menus == beforeMenus + 1)
setScore("Alice", "gp_art_shell", 1); remote.process(context, radio)
setScore("Alice", "gp_art_count", 2); remote.process(context, radio)
setScore("Alice", "gp_art_pattern", 2); remote.process(context, radio)
setScore("Alice", "gp_art_confirm", 1); remote.process(context, radio)
local fire = packets[#packets]
assert(fire.type == "fire_mission" and fire.pattern == "area" and fire.shells == 6 and fire.shell == "he")
print("ARTILLERY LOCAL SUBMIT PASS")
