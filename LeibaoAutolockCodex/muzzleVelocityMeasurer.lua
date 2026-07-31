-- Simple muzzle velocity detector (assumes only ONE shell in range)
-- Detect the shell twice -> speed = deltaDistance / deltaTime

local radar = peripheral.find("sp_radar")
if not radar then error("sp_radar not found") end

--local entityName = "entity.cbcmoreshells.normal_ap_shot"
local entityName = "entity.cbcmodernwarfare.he_mediumshell"

local SCAN_RADIUS = 500
local MIN_DT      = 0.02   -- seconds
local POLL_DT     = 0.02   -- sleep between scans

-- wall-clock seconds
local function now()
  return os.epoch("utc") / 1000
end

-- pos may be {x,y,z} or {[1],[2],[3]}
local function vx(p) return p.x or p[1] or 0 end
local function vy(p) return p.y or p[2] or 0 end
local function vz(p) return p.z or p[3] or 0 end

local function dist(a, b)
  local dx = vx(a) - vx(b)
  local dy = vy(a) - vy(b)
  local dz = vz(a) - vz(b)
  return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function findShell()
  local results = radar.scanForEntities(SCAN_RADIUS) or {}
  for _, e in ipairs(results) do
    if e.entity_type == entityName and e.pos then
      return e
    end
  end
  return nil
end

print("Watching for: " .. entityName)
print("Scan radius: " .. SCAN_RADIUS)
print("Fire a shot now...")

local firstPos, firstT = nil, nil

while true do
  local e = findShell()
  if e then
    local t = now()

    if not firstPos then
      -- first detection
      firstPos = e.pos
      firstT = t
      print("Shell detected (1st sample)")
    else
      -- second detection
      local dt = t - firstT
      local d = dist(e.pos, firstPos)
      local v = d / dt
      if dt >= MIN_DT and v > 10 then
        
        
        print(string.format("Muzzle velocity ~ %.2f blocks/s (d=%.2f, dt=%.3f)", v, d, dt))

        -- reset so you can fire again and measure again
        firstPos, firstT = nil, nil
        print("Ready for next shot...")
        error()
      end
    end
  end

  sleep(POLL_DT)
end
