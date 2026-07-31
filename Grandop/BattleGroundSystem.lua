-- Setup
local posX, posY, posZ = commands.getBlockPosition()

-- One base per team
local blueBase = { name = "Blue Base",  x = 4528, y = 18, z = 6458 }  -- <— set to your Blue base
local redBase  = { name = "Red Base",   x = 5778, y = 22, z = 5401 }  -- <— set to your Red base

-- Team spawns
local blueSpawn = {x = 4243, y = 307, z = 6653}
local redSpawn  = {x = 4237, y = 307, z = 6653}

local captureRange   = 40
local updateInterval = 0.5  -- seconds

-- Teams
local BLUE = "Blue"
local RED  = "Red"

-- Capture numbers
local maxProgress = 200
local capRate     = 1     -- progress per tick while uncontested
local decapRate   = 1     -- how fast defenders reduce enemy progress on own base
local stall       = 1      -- progress change when contested (0 = pause). Set >0 to slow “bleed” if you want.

-- Base state
local bases = {
  blue = {
    pos    = blueBase,
    owner  = BLUE,        -- blue owns blue base at start
    prog   = 0,           -- attacker progress on this base
    barId  = "bluebasebar"
  },
  red  = {
    pos    = redBase,
    owner  = RED,         -- red owns red base at start
    prog   = 0,
    barId  = "redbasebar"
  }
}

-- Helper: detect if any entity matches selector
local function anyone(selector)
  -- returns true if entity exists
  local ok = commands.exec("execute if entity " .. selector)
  return ok and true or false
end

-- Bossbars (one per base)
local function setupBossbars()
  commands.exec('/bossbar add ' .. bases.blue.barId .. ' "Blue Base"')
  commands.exec('/bossbar set ' .. bases.blue.barId .. ' max ' .. maxProgress)
  commands.exec('/bossbar set ' .. bases.blue.barId .. ' visible true')
  commands.exec('/bossbar set ' .. bases.blue.barId .. ' players @a')

  commands.exec('/bossbar add ' .. bases.red.barId .. ' "Red Base"')
  commands.exec('/bossbar set ' .. bases.red.barId .. ' max ' .. maxProgress)
  commands.exec('/bossbar set ' .. bases.red.barId .. ' visible true')
  commands.exec('/bossbar set ' .. bases.red.barId .. ' players @a')
end

local function updateBossbar(baseKey)
  local b = bases[baseKey]
  local bar = b.barId
  -- Show attacker color on progress; owner color if no progress
  if b.prog > 0 then
    -- If owner is BLUE, then current attacker is RED (and vice versa)
    local attacker = (b.owner == BLUE) and RED or BLUE
    commands.exec('/bossbar set ' .. bar .. ' value ' .. b.prog)
    if attacker == RED then
      commands.exec('/bossbar set ' .. bar .. ' name {"text":"'..b.pos.name..' - Attacked by RED","color":"red"}')
      commands.exec('/bossbar set ' .. bar .. ' color red')
    else
      commands.exec('/bossbar set ' .. bar .. ' name {"text":"'..b.pos.name..' - Attacked by BLUE","color":"blue"}')
      commands.exec('/bossbar set ' .. bar .. ' color blue')
    end
  else
    -- No attacker progress; show owner/neutral
    commands.exec('/bossbar set ' .. bar .. ' value 0')
    if b.owner == BLUE then
      commands.exec('/bossbar set ' .. bar .. ' name {"text":"'..b.pos.name..' - Controlled by Blue","color":"blue"}')
      commands.exec('/bossbar set ' .. bar .. ' color blue')
    elseif b.owner == RED then
      commands.exec('/bossbar set ' .. bar .. ' name {"text":"'..b.pos.name..' - Controlled by Red","color":"red"}')
      commands.exec('/bossbar set ' .. bar .. ' color red')
    else
      commands.exec('/bossbar set ' .. bar .. ' name {"text":"'..b.pos.name..' - Neutral","color":"white"}')
      commands.exec('/bossbar set ' .. bar .. ' color white')
    end
  end
end

-- Initialize (no tickets; instant win on enemy-base capture)
setupBossbars()

-- Core capture logic for a single base (defenders own it at start; attackers must fill prog to capture)
local function stepBase(baseKey)
  local b = bases[baseKey]
  local px, py, pz = b.pos.x, b.pos.y, b.pos.z

  -- Presence checks around this base
  local selectorBlue = "@a[team="..BLUE..",x="..px..",y="..py..",z="..pz..",distance=.."..captureRange.."]"
  local selectorRed  = "@a[team="..RED ..",x="..px..",y="..py..",z="..pz..",distance=.."..captureRange.."]"

  local blueHere = anyone(selectorBlue)
  local redHere  = anyone(selectorRed)

  -- Determine who is the attacker for this base (owner's enemy)
  local attacker, defender
  if b.owner == BLUE then
    attacker, defender = RED, BLUE
  else
    attacker, defender = BLUE, RED
  end

  -- “Healing/feeding” effect like your original (optional)
  if blueHere then commands.exec("execute as "..selectorBlue.." run effect give @s saturation 1") end
  if redHere  then commands.exec("execute as "..selectorRed .." run effect give @s saturation 1") end

  -- Apply progress rules
  if blueHere and redHere then
    -- Contested: pause or tiny bleed if you want (stall)
    if stall ~= 0 then
      -- bleed towards zero
      if b.prog > 0 then
        b.prog = math.max(0, b.prog - stall)
      end
    end

    else
    -- Only one team present or none
        if attacker == RED then
        -- RED is attacker against a BLUE-owned base
            if redHere and not blueHere then
                -- Build capture progress
                b.prog = math.min(maxProgress, b.prog + capRate)
            elseif blueHere and not redHere then
                -- Defenders de-cap enemy progress on THEIR base
                if b.prog > 0 then
                b.prog = math.max(0, b.prog - decapRate)
                end
            end
        else
            -- BLUE attacker against a RED-owned base
            if blueHere and not redHere then
                b.prog = math.min(maxProgress, b.prog + capRate)
            elseif redHere and not blueHere then
                if b.prog > 0 then
                b.prog = math.max(0, b.prog - decapRate)
                end
            end
        end
    end
    --no one in objective
    if not blueHere and not redHere then
        if b.prog > 0 then
            b.prog = math.max(0, b.prog - stall)
        end
    end


  -- Check capture complete (attacker takes base)
    if b.prog >= maxProgress then
        -- Flip owner to attacker
        b.owner = attacker
        b.prog  = 0
        -- Instant victory: capturing enemy base ends the round
        local winner = attacker
        local loser  = (winner == BLUE) and RED or BLUE
        commands.exec('/title @a title {"text":"'..winner..' captured the enemy base!","color":"'..(winner==BLUE and 'blue' or 'red')..'"}')
        commands.exec('/title @a subtitle {"text":"'..winner..' Wins","color":"'..(winner==BLUE and 'blue' or 'red')..'"}')
        return true -- signal end of game
    end

    updateBossbar(baseKey)
    return false
end

-- Main loop
while true do
  -- Keep spawnpoints updated
  commands.exec("/spawnpoint @a[team=" .. BLUE .. "] " .. blueSpawn.x .. " " .. blueSpawn.y .. " " .. blueSpawn.z)
  commands.exec("/spawnpoint @a[team=" .. RED  .. "] " .. redSpawn.x  .. " " .. redSpawn.y  .. " " .. redSpawn.z)

  -- Step both bases; if any returns true, game ends
  if stepBase("blue") then break end  -- enemy captured Blue base
  if stepBase("red")  then break end  -- enemy captured Red base

  sleep(updateInterval)
end
