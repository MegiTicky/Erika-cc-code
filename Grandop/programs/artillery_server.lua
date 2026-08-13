-- Grandop artillery server (wireless modem).
-- Ported from the legacy artilleryServer.lua. Requires: command computer +
-- wireless modem on MODEM_SIDE.

local MODEM_SIDE           = "right"   -- change if needed
local CHANNEL              = 9001      -- fixed frequency to listen on
local ALTITUDE_Y           = 350       -- shell spawn height
local RADIUS_HE            = 30        -- impact dispersion radius
local RADIUS_SMOKE         = 50
local COOLDOWN_PER_SHELL   = 10        -- seconds of cooldown per fired shell
local SHOT_INTERVAL_SEC    = 1         -- delay between individual shells
local MAX_SHELL            = 20

local SHELL_CMD = {
  he    = "/summon crusty_chunks:artillery_fire_projectile %d %d %d",
  smoke = "/summon cbcmodernwarfare:smoke_mediumshell %d %d %d {Fuze:{id:\"createbigcannons:impact_fuze\",Count:1b}, Motion:[0d,-10d,0d]}"
}

local function now()
  return os.epoch("utc") / 1000
end

local function openModem()
  if peripheral.getType(MODEM_SIDE) ~= "modem" then
    error("No modem on side: " .. MODEM_SIDE)
  end
  local m = peripheral.wrap(MODEM_SIDE)
  m.open(CHANNEL)
  print(("Artillery server up. Listening on channel %d"):format(CHANNEL))
  return m
end

local cooldown_until = 0

local function secondsRemaining()
  return math.ceil(math.max(0, cooldown_until - now()))
end

local function readyToFire()
  return secondsRemaining() == 0
end

local function setCooldownForShells(shells)
  local cd = math.max(1, math.floor(shells)) * COOLDOWN_PER_SHELL
  cooldown_until = now() + cd
  return cd
end

local function summonShell(shellType, x, y, z)
  local pattern = SHELL_CMD[shellType] or SHELL_CMD.he
  return commands.exec(pattern:format(x, y, z))
end

local function fireSalvo(shellType, cx, cz, shells)
  sleep(10)
  local radius = RADIUS_HE
  local timeInterval = SHOT_INTERVAL_SEC
  if shellType == "smoke" then
    radius = RADIUS_SMOKE
    shells = shells * 2
    timeInterval = 0.5
  end
  local dx = math.random(-radius, radius)
  local dz = math.random(-radius, radius)
  summonShell(shellType, cx + dx, ALTITUDE_Y, cz + dz)
  sleep(10)
  shells = shells - 1
  for i = 1, shells do
    local dx = math.random(-radius, radius)
    local dz = math.random(-radius, radius)
    summonShell(shellType, cx + dx, ALTITUDE_Y, cz + dz)
    if i < shells then sleep(timeInterval) end
  end
end

local function sendStatus(modem, toChannel)
  local ok = readyToFire()
  modem.transmit(toChannel, toChannel, {
    type = "artillery_status",
    ok = ok,
    remaining = secondsRemaining(),
  })
end

local function sendAck(modem, toChannel, accepted, fields)
  fields = fields or {}
  fields.type = "mission_ack"
  fields.accepted = accepted
  modem.transmit(toChannel, toChannel, fields)
end

math.randomseed(os.epoch("utc") + os.getComputerID())
local modem = openModem()

local queue = {}

local function enqueue(mission) table.insert(queue, mission) end
local function pop()
  if #queue == 0 then return nil end
  return table.remove(queue, 1)
end

local function listener()
  while true do
    local _, _, ch, replyCh, msg = os.pullEvent("modem_message")
    if ch == CHANNEL and type(msg) == "table" then
      if msg.type == "status_request" then
        sendStatus(modem, CHANNEL)
      elseif msg.type == "fire_mission" then
        local x      = math.floor(tonumber(msg.x) or 0)
        local z      = math.floor(tonumber(msg.z) or 0)
        local shells = math.max(1, math.floor(tonumber(msg.shells) or 1))
        local shell  = (msg.shell == "smoke") and "smoke" or "he"

        if readyToFire() then
          local cd = setCooldownForShells(shells)
          sendAck(modem, CHANNEL, true, { cooldown = cd, x = x, z = z, shells = shells, shell = shell })
          enqueue({ x = x, z = z, shells = shells, shell = shell })
          print(("Accepted mission: %s x%d @ (%d,%d); cooldown %ds")
            :format(shell:upper(), shells, x, z, cd))
        else
          local remain = secondsRemaining()
          sendAck(modem, CHANNEL, false, { remaining = remain })
          print(("Denied mission (cooldown %ds remaining)."):format(remain))
        end
      end
    end
  end
end

local function worker()
  while true do
    local job = pop()
    if job then
      print(("FIRING: %s x%d @ (%d,%d)")
        :format(job.shell:upper(), job.shells, job.x, job.z))
      fireSalvo(job.shell, job.x, job.z, job.shells)
    else
      sleep(0.1)
    end
  end
end

parallel.waitForAny(listener, worker)
