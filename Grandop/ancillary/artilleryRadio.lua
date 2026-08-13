-- radio_client_modem.lua — Commander’s field radio (wireless modem)
-- Put a wireless modem on MODEM_SIDE.

local MODEM_SIDE = "right"   -- change if needed (e.g., "top","back")
local max_shell = 20

-- ---------- modem ----------
local function openModem()
  if peripheral.getType(MODEM_SIDE) ~= "modem" then
    error("No modem on side: " .. MODEM_SIDE)
  end
  local m = peripheral.wrap(MODEM_SIDE)
  m.open(0) -- a dummy channel; we’ll open the real one later
  return m
end

-- ---------- input helpers ----------
local function askNumber(prompt, default)
  while true do
    io.write(prompt .. (default and (" ["..default.."]") or "") .. ": ")
    local s = read()
    if s == "" and default then return default end
    local n = tonumber(s)
    if n then return n end
    print("Please enter a number.")
  end
end

local function askChoice(prompt, choices, defaultIdx)
  while true do
    print(prompt)
    for i, txt in ipairs(choices) do
      print(("  %d) %s"):format(i, txt))
    end
    io.write("Choose (1-"..#choices..")" .. (defaultIdx and (" ["..defaultIdx.."]") or "") .. ": ")
    local s = read()
    if s == "" and defaultIdx then return defaultIdx end
    local n = tonumber(s)
    if n and n >= 1 and n <= #choices then return n end
    print("Invalid choice.")
  end
end

-- ---------- client protocol ----------
local function awaitByType(channel, wantType, timeout)
  local timer = os.startTimer(timeout or 8)
  while true do
    local e, p1, p2, p3, p4, p5 = os.pullEvent()
    if e == "timer" and p1 == timer then
      return nil
    elseif e == "modem_message" then
      local _, ch, replyCh, msg = p1, p2, p3, p4
      if ch == channel and type(msg) == "table" and msg.type == wantType then
        return msg
      end
    end
  end
end

local function requestStatus(m, channel)
  m.open(channel)
  m.transmit(channel, channel, { type = "status_request", t = os.epoch("utc") })
  return awaitByType(channel, "artillery_status", 6)
end

local function sendFireMission(m, channel, payload)
  m.open(channel)
  m.transmit(channel, channel, payload)
  return awaitByType(channel, "mission_ack", 8)
end

-- ---------- main ----------
local modem = openModem()
print("=== Field Radio (modem) ===")

-- 1) Frequency first, then we immediately get server status
local chan = askNumber("Enter frequency (channel)", nil)
local st = requestStatus(modem, chan)
if st then
  if st.ok then
    print("STATUS: Battery ready. No cooldown.")
  else
    print(("STATUS: ON COOLDOWN ~%ds remaining."):format(st.remaining or 0))
  end
else
  print("No status reply (wrong channel, range, or server offline).")
end

-- 2) Choose shell type
local shellChoices = { "HE", "Smoke" }
local choice = askChoice("Select shell type:", shellChoices, 1)
local shellType = (choice == 2) and "smoke" or "he"

-- 3) Choose number of shells (cooldown = shells * 10s on server)
local shells
print("Suggested shells count: HE: 20, Smoke: 20")
while true do
  shells = askNumber(("How many shells? (1-%d)"):format(max_shell), 1)
  if shells >= 1 and shells <= max_shell then break end
  print(("Invalid: enter between 1 and %d shells."):format(max_shell))
end

-- 4) Coordinates
local tx   = askNumber("Target X", nil)
local tz   = askNumber("Target Z", nil)

-- 5) Send mission
local msg = {
  type   = "fire_mission",
  x      = math.floor(tx),
  z      = math.floor(tz),
  shells = math.max(1, math.floor(shells)),
  shell  = shellType,
  t      = os.epoch("utc")
}

print(("Sending fire mission: %s x%d @ (%d,%d)")
  :format(shellType:upper(), msg.shells, msg.x, msg.z))

local ack = sendFireMission(modem, chan, msg)
if not ack then
  print("No ACK from server (out of range or busy).")
elseif ack.accepted then
  print(("MISSION ACCEPTED: %s x%d. New cooldown ~%ds.")
    :format(shellType:upper(), msg.shells, ack.cooldown or (msg.shells*15)))
else
  print(("MISSION DENIED: cooldown ~%ds remaining."):format(ack.remaining or 0))
end
