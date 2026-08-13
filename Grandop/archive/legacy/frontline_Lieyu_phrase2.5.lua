--=== modem setup ===--
local modem = peripheral.find("modem")
if not modem then error("Modem (wireless or wired) not found!") end

local STAGE_CHANNEL = 125     -- The channel for broadcasting stage updates
modem.open(STAGE_CHANNEL)  -- Open the channel for listening

-- Setup
local posX, posY, posZ = commands.getBlockPosition()
local myPosition = { x = posX, y = posY, z = posZ }
local zoneScore = 0
local bossbarId = 1
local currentZoneIndex = 2

-- Detection range and update rate
local captureRange = 20
local updateInterval = 0.001

-- Team names
local attackTeam = "Red"
local defenseTeam = "Blue"

-- Ticket management computer ID
local ticketComputerId = 2

-- Score changes when player enters zone
local scoreChange = 3
local neutralScoreChange = 1

local reinforcement_arrived = false

-- Tickets gained/lost per zone captured
local ticketRewards = {
    { a = 200, d = -50 },
    { a = 200, d = -50 },
    { a = 200, d = -50 },
    { a = 200, d = -50 },
    { a = 200, d = -50 },
}

-- Capture zone coordinates
local captureZones = {
    { x = 4421, y = 3, z = 5534 },  -- A (red base)
    { x = 4552, y = 11, z = 5631 },  -- B
    { x = 4688, y = 14, z = 5654 },  -- C
    { x = 4780, y = 26, z = 5621 },  -- D
    { x = 4841, y = 30, z = 5546 },  -- E (blue base)
}

local objectiveName = {"A(Red base)","B","C","D","E(Blue base)"}

-- Attacker spawn points (Red)
local attackerSpawns = {x = 4237, y = 308, z = 6653}
-- Defender spawn points (Blue)
local defenderSpawns = {x = 4243, y = 308, z = 6653}


-- Function to broadcast the stage to other computers (e.g., infantry/tank systems)
local function broadcastStage(stage)
    modem.transmit(STAGE_CHANNEL, STAGE_CHANNEL, { stage = stage })
    print("Broadcasting Stage: " .. stage)
end

local function setBeaconWithNetherrite(x, y, z)
    --print("/setblock " .. x .. " " .. y .. " " .. z .. " minecraft:beacon")
    -- Set the beacon block at the given coordinates
    commands.exec("/setblock " .. x .. " " .. y .. " " .. z .. " minecraft:beacon")
    -- Fill a 3x3 area around the beacon with Netherrite blocks (1 block below the beacon's y-coordinate)
    --print("/fill " .. (x-1) .. " " .. (y-1) .. " " .. (z-1) .. " " .. (x+1) .. " " .. (y-1) .. " " .. (z+1) .. " minecraft:netherite_block")
    commands.exec("/fill " .. (x-1) .. " " .. (y-1) .. " " .. (z-1) .. " " .. (x+1) .. " " .. (y-1) .. " " .. (z+1) .. " minecraft:netherite_block")
end

--=== Bossbar Initialization ===--

-- Make sure we first clear any existing bossbars
commands.exec("/bossbar remove " .. bossbarId)

-- Add a new bossbar
print("/bossbar add " .. bossbarId .. " \"Stage 1 of " .. #captureZones .. "\"")
commands.exec("/bossbar add " .. bossbarId .. " \"Stage 1 of " .. #captureZones .. "\"")

-- Set maximum value for the bossbar
commands.exec("/bossbar set " .. bossbarId .. " max " .. 100)

-- Set initial value and style of the bossbar
commands.exec("/bossbar set " .. bossbarId .. " value 0")
commands.exec("/bossbar set " .. bossbarId .. " style progress")
commands.exec("/bossbar set " .. bossbarId .. " players @a")

-- Initial beacon setup for zone A
redstone.setOutput("back", false)
sleep(0.1)
redstone.setOutput("back", true)
commands.exec("/setblock " .. captureZones[currentZoneIndex].x .. " " .. captureZones[currentZoneIndex].y .. " " .. captureZones[currentZoneIndex].z .. " minecraft:beacon")

-- Clear all other zones
for i = 1, #captureZones do
    commands.exec("/setblock " .. captureZones[i].x .. " " .. captureZones[i].y .. " " .. captureZones[i].z .. " air")
end

broadcastStage(currentZoneIndex)
local skipCooldown = 0
local skipDelay = 3  -- seconds

function updateZone(currentZoneNum, nextZoneNum)
    zoneScore = 0
    -- Clear current beacon
    print("Captured, moving to next")
    commands.exec("/setblock " .. captureZones[currentZoneNum].x .. " " .. captureZones[currentZoneNum].y .. " " .. captureZones[currentZoneNum].z .. " air")

    -- Play feedback (victory light or sound)
    redstone.setAnalogOutput("top", 15)
    sleep(0)
    redstone.setAnalogOutput("top", 0)

    -- Show capture notification title to all players
    commands.exec("/title @a title {\"text\":\"Objective " .. objectiveName[currentZoneNum] .. " captured!\",\"color\":\"green\"}")

    -- Check for the final stage
    if nextZoneNum == #captureZones + 1 then
        -- Final zone captured, game end logic
        sleep(2)
        commands.exec("/title @a title \"red wins\"")
        error("Game finished")
    end

    -- Broadcast the current stage
    broadcastStage(nextZoneNum)
    sleep(2)
    commands.exec("/title @a title \"Next Objective unlocked in 30s\"")
    sleep(30)
    commands.exec("/title @a title \"Objective unlocked\"")
    currentZoneIndex = nextZoneNum
end



-- Main game loop
while true do
    local attackerDetected = commands.exec("execute as @a[team=" .. attackTeam .. ",x=" .. captureZones[currentZoneIndex].x .. ",y=" .. captureZones[currentZoneIndex].y .. ",z=" .. captureZones[currentZoneIndex].z .. ",distance=.." .. captureRange .. "] at @s run effect give @s saturation 1")
    local defenderDetected = commands.exec("execute as @a[team=" .. defenseTeam .. ",x=" .. captureZones[currentZoneIndex].x .. ",y=" .. captureZones[currentZoneIndex].y .. ",z=" .. captureZones[currentZoneIndex].z .. ",distance=.." .. captureRange .. "] at @s run effect give @s saturation 1")
    --check reinforcement status
    local _,_,USReinforcementTimer = commands.exec("/scoreboard players get USReinforcement Troops_Strength")
    print(USReinforcementTimer)
    if USReinforcementTimer < 1 then
        reinforcement_arrived = true
    end
    -- Zone score changes when a player enters the zone
    -- positive: attacker own objective, negative, defender own objecitve
    if defenderDetected and reinforcement_arrived then
        zoneScore = zoneScore - scoreChange
        print("Defender in zone")
    end
    if attackerDetected then
        zoneScore = zoneScore + scoreChange
        print("Attacker in zone")
    end
    if not(defenderDetected) and not(attackerDetected) then
        if zoneScore > 0 then
            zoneScore = zoneScore - neutralScoreChange
        elseif zoneScore < 0 then
            zoneScore = zoneScore + neutralScoreChange
        end
    end
    if defenderDetected and not reinforcement_arrived and not(attackerDetected) then
        if zoneScore > 0 then
            zoneScore = zoneScore - neutralScoreChange
        elseif zoneScore < 0 then
            zoneScore = zoneScore + neutralScoreChange
        end
    end

    -- Skip logic
    if redstone.getInput("front") and os.clock() > skipCooldown then
        print("Zone skipped by button press")
        zoneScore = 201  -- Trigger capture logic
        skipCooldown = os.clock() + skipDelay
    elseif redstone.getInput("back") and os.clock() > skipCooldown then
        print("Zone skipped by button press")
        zoneScore = -201  -- Trigger capture logic
        skipCooldown = os.clock() + skipDelay
    end
    

    -- Set current beacon
    commands.exec("/setblock " .. captureZones[currentZoneIndex].x .. " " .. captureZones[currentZoneIndex].y .. " " .. captureZones[currentZoneIndex].z .. " minecraft:beacon")
    
    -- After the zone score reaches 100 or -100 (zone is captured):
    if zoneScore > 200 then
        updateZone(currentZoneIndex, currentZoneIndex + 1)
    elseif zoneScore < -200 then
        updateZone(currentZoneIndex, currentZoneIndex - 1)
    end
    -- Set beacon for the current zone
    setBeaconWithNetherrite(captureZones[currentZoneIndex].x, captureZones[currentZoneIndex].y, captureZones[currentZoneIndex].z)

    -- Dynamically adjust the color of the boss bar based on zone score
    local color = "white"
    if zoneScore > 0 then
        color = "red"
        commands.exec("/bossbar set " .. bossbarId .. " value " .. zoneScore / 2)
    elseif zoneScore < 0 then
        color = "blue"
        commands.exec("/bossbar set " .. bossbarId .. " value " .. -zoneScore / 2)
    end
    commands.exec("/bossbar set " .. bossbarId .. " color " .. color)

    -- Update the boss bar value
    commands.exec("/bossbar set " .. bossbarId .. " name \"Objective "..objectiveName[currentZoneIndex] .. "\"")
    
    --set spawn point
    commands.exec("/spawnpoint @a[team=" .. attackTeam .. "] " .. attackerSpawns.x .. " " .. attackerSpawns.y .. " " .. attackerSpawns.z)
    commands.exec("/spawnpoint @a[team=" .. defenseTeam .. "] " .. defenderSpawns.x .. " " .. defenderSpawns.y .. " " .. defenderSpawns.z)
    sleep(updateInterval)
end
