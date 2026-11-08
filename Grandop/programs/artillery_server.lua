-- Grandop artillery service. Standalone usage: run artillery <mission>

local args = { ... }
local missionId = args[1]
if not missionId then error("Usage: artillery_server <mission>") end

local MODEM_SIDE = "right"
local CHANNEL = 9001
local FIRST_SHELL_DELAY = 15
local COOLDOWNS = { [3] = 90, [6] = 150 }
local SHOT_INTERVAL_SEC = 1

local function rootRequire(name)
  local chunk, reason = loadfile("/" .. name:gsub("%.", "/") .. ".lua")
  if not chunk then error("Cannot load " .. name .. ": " .. tostring(reason)) end
  return chunk()
end
local spotter = rootRequire("lib.artillery_spotter")
local artillery = rootRequire("lib.artillery")
local missionFile = "/missions/" .. missionId:gsub("[^%w_%-]", "") .. ".lua"
local chunk, reason = loadfile(missionFile)
if not chunk then error("Cannot load " .. missionFile .. ": " .. tostring(reason)) end
local mission = chunk()
local cfg = mission.respawn and mission.respawn.artillerySpotter
if type(cfg) ~= "table" then error("Mission has no respawn.artillerySpotter configuration: " .. missionId) end
if type(mission.teams) ~= "table" then error("Mission has no team map: " .. missionId) end

local radar = peripheral.find("sp_radar")
if not radar then error("Artillery spotter requires an sp_radar peripheral") end
if peripheral.getType(cfg.modemSide or MODEM_SIDE) ~= "modem" then error("No modem on side: " .. (cfg.modemSide or MODEM_SIDE)) end
local modem = peripheral.wrap(cfg.modemSide or MODEM_SIDE)
local listenChannel = cfg.channel or CHANNEL
local replyChannelDefault = cfg.replyChannel or (10000 + os.getComputerID())
modem.open(listenChannel)
modem.open(replyChannelDefault)

local function now() return os.epoch("utc") / 1000 end
local cooldownUntil = {}
local seenRequests = {}
local queue = {}
local function remaining(key) return math.ceil(math.max(0, (cooldownUntil[key] or 0) - now())) end
local function setCooldown(key, shells, acceptedAt)
  local cd = COOLDOWNS[shells]
  cooldownUntil[key] = acceptedAt + cd
  return cd
end
local function factionOf(name)
  for team, faction in pairs(mission.teams) do
    local ok = commands.exec(("execute if entity @a[team=%s,name=\"%s\"]"):format(team, name))
    if ok then return faction, team end
  end
end
local function replyChannel(incoming)
  return (type(incoming) == "number" and incoming > 0) and incoming or listenChannel
end
local function send(to, payload)
  modem.transmit(to, to, payload)
end
local function queryStatus(msg)
  local faction, team
  if msg.player then faction, team = factionOf(msg.player) end
  local seconds = faction and remaining(faction) or 0
  return { type="artillery_status", player=msg.player, requestId=msg.requestId,
    ok=faction ~= nil and seconds == 0, remaining=seconds, faction=faction, team=team,
    reason=not faction and "invalid faction" or (seconds > 0 and "cooldown" or nil) }
end
local function acceptMission(msg)
  local faction, team
  if msg.player then faction, team = factionOf(msg.player) end
  local x, z, shells = tonumber(msg.x), tonumber(msg.z), tonumber(msg.shells)
  x, z, shells = x and math.floor(x), z and math.floor(z), shells
  local pattern = msg.pattern
  if pattern == nil then pattern = "concentrated" end -- Older clients omit pattern.
  local valid = artillery.patterns[pattern] and msg.requestId and msg.player and faction and x and z and shells and COOLDOWNS[shells] and (msg.shell == "he" or msg.shell == "smoke")
  if seenRequests[msg.requestId] then valid = false end
  if not valid then return { type="mission_ack", accepted=false, requestId=msg.requestId, reason="invalid mission" } end
  if remaining(faction) > 0 then return { type="mission_ack", accepted=false, requestId=msg.requestId, faction=faction, team=team, remaining=remaining(faction), reason="cooldown" } end
  local acceptedAt = now()
  seenRequests[msg.requestId] = acceptedAt
  local cd = setCooldown(faction, shells, acceptedAt)
  queue[#queue + 1] = { x=x, z=z, shells=shells, shell=msg.shell, faction=faction,
    pattern=pattern, player=msg.player, fired=0, readyAt=acceptedAt + FIRST_SHELL_DELAY }
  print(("Accepted %s x%d for %s at (%d,%d); cooldown %ds"):format(msg.shell:upper(), shells, faction, x, z, cd))
  return { type="mission_ack", accepted=true, requestId=msg.requestId, faction=faction, team=team, cooldown=cd, x=x, z=z, shells=shells, shell=msg.shell, pattern=pattern, firstShellDelay=FIRST_SHELL_DELAY }
end

local function listener()
  while true do
    local _, _, ch, incomingReply, msg = os.pullEvent("modem_message")
    if (ch == listenChannel or ch == replyChannelDefault) and type(msg) == "table" then
      if spotter.handleMessage(msg) then
        -- Acknowledgements are consumed by the shared spotter session.
      else
        local destination = replyChannel(incomingReply)
        if msg.type == "status_request" then
          send(destination, queryStatus(msg))
      elseif msg.type == "fire_mission" then
        local ack = acceptMission(msg)
        ack.player = msg.player
        send(destination, ack)
      end
      end
    end
  end
end
local function worker()
  while true do
    local ready
    for i, job in ipairs(queue) do
      if job.readyAt <= now() and (not ready or job.readyAt < queue[ready].readyAt) then ready = i end
    end
    if ready then
      local job = queue[ready]
      artillery.fireShell(job)
      job.fired = job.fired + 1
      if job.fired == job.shells then
        table.remove(queue, ready)
        commands.exec("tellraw " .. job.player .. " " .. textutils.serialiseJSON({
          text = ("Artillery mission complete: %s x%d dispatched."):format(job.shell:upper(), job.shells), color = "green" }))
      else
        job.readyAt = now() + (job.shell == "smoke" and 0.5 or SHOT_INTERVAL_SEC)
      end
    else sleep(0.1) end
  end
end
local function spotterLoop()
  cfg.queryStatus = queryStatus
  cfg.submit = function(msg)
    print("Received local artillery request from " .. tostring(msg.player))
    local ack = acceptMission(msg)
    ack.player = msg.player
    if not ack.accepted then print("Rejected artillery request: " .. tostring(ack.reason)) end
    return ack
  end
  local context = { respawn = { artillerySpotter = cfg }, teams = mission.teams, radar = radar, standalone = true }
  spotter.ensureObjectives()
  while true do
    spotter.process(context, modem)
    sleep(1)
  end
end
print("Artillery standalone service: " .. missionId)
parallel.waitForAny(listener, worker, spotterLoop)
