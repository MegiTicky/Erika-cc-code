-- artillery_server_modem.lua — Artillery battery server (wireless modem)
-- Requires: Command Computer (for commands.exec) + Wireless Modem on MODEM_SIDE.

----------------------------
-- Configuration
----------------------------
local MODEM_SIDE           = "right"   -- change if needed
local CHANNEL              = 9001      -- fixed frequency to listen on
local ALTITUDE_Y           = 350       -- shell spawn height
local RADIUS_HE             = 30        -- impact dispersion radius
local RADIUS_Smoke = 50
local COOLDOWN_PER_SHELL   = 10        -- seconds of cooldown per fired shell
local SHOT_INTERVAL_SEC    = 1         -- delay between individual shells
local max_shell            = 20

-- Shell summon commands (adjust to your mod IDs as needed)
-- Keep the %d placeholders (x y z).
local SHELL_CMD = {
  he    = "/summon crusty_chunks:artillery_fire_projectile %d %d %d",
  smoke = "/summon cbcmodernwarfare:smoke_mediumshell %d %d %d {Fuze:{id:\"createbigcannons:impact_fuze\",Count:1b}, Motion:[0d,-10d,0d]}"
}

----------------------------
-- Utilities
----------------------------
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

----------------------------
-- Cooldown state
----------------------------
local cooldown_until = 0  -- epoch seconds when the battery is next ready

local function secondsRemaining()
  local remain = math.ceil(math.max(0, cooldown_until - now()))
  return remain
end

local function readyToFire()
  return secondsRemaining() == 0
end

local function setCooldownForShells(shells)
  local cd = math.max(1, math.floor(shells)) * COOLDOWN_PER_SHELL
  cooldown_until = now() + cd
  return cd
end

----------------------------
-- Gunnery
----------------------------
local function summonShell(shellType, x, y, z)
  local pattern = SHELL_CMD[shellType] or SHELL_CMD.he
  local cmd = pattern:format(x, y, z)
  return commands.exec(cmd)
end

local function fireSalvo(shellType, cx, cz, shells)
  sleep(10)
  local radius = 30
  local timeInterval = SHOT_INTERVAL_SEC
  if shellType == "he" then
    radius = RADIUS_HE
  elseif shellType == "smoke" then
    radius = RADIUS_Smoke
    shells = shells*2
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

----------------------------
-- Messaging
----------------------------
local function sendStatus(modem, toChannel)
  local ok = readyToFire()
  local remaining = secondsRemaining()
  modem.transmit(toChannel, toChannel, {
    type = "artillery_status",
    ok = ok,
    remaining = remaining
  })
end

local function sendAck(modem, toChannel, accepted, fields)
  fields = fields or {}
  fields.type = "mission_ack"
  fields.accepted = accepted
  modem.transmit(toChannel, toChannel, fields)
end

----------------------------
-- Main (listener + worker)
----------------------------
math.randomseed(os.epoch("utc") + os.getComputerID())
local modem = openModem()

-- Simple FIFO queue for missions so we can keep answering status while firing
local queue = {}

local function enqueue(mission) table.insert(queue, mission) end
local function pop()
  if #queue == 0 then return nil end
  return table.remove(queue, 1)
end

-- Listener: receives status requests and fire missions
local function listener()
  while true do
    local _, side, ch, replyCh, msg = os.pullEvent("modem_message")
    if ch ~= CHANNEL or type(msg) ~= "table" then
      -- ignore unrelated traffic
    elseif msg.type == "status_request" then
      -- Reply immediately with current readiness
      sendStatus(modem, CHANNEL)
    elseif msg.type == "fire_mission" then
      local x      = math.floor(tonumber(msg.x) or 0)
      local z      = math.floor(tonumber(msg.z) or 0)
      local shells = math.max(1, math.floor(tonumber(msg.shells) or 1))
      local shell  = (msg.shell == "smoke") and "smoke" or "he"

      if readyToFire() then
        -- Reserve the battery by setting cooldown immediately
        local cd = setCooldownForShells(shells)
        -- Tell the client we accepted and what the cooldown will be
        sendAck(modem, CHANNEL, true, {
          cooldown = cd, x = x, z = z, shells = shells, shell = shell
        })
        -- Queue the work so we can continue answering status requests
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

-- Worker: pulls missions off the queue and fires them
local function worker()
  while true do
    local job = pop()
    if job then
      print(("FIRING: %s x%d @ (%d,%d)")
        :format(job.shell:upper(), job.shells, job.x, job.z))
      fireSalvo(job.shell, job.x, job.z, job.shells)
      -- Cooldown was set when mission was accepted; nothing else to do here.
    else
      sleep(0.1)
    end
  end
end

parallel.waitForAny(listener, worker)
