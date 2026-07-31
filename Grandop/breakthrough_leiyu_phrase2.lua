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
local currentZoneIndex = 1

-- Detection range and update rate
local captureRange = 50
local updateInterval = 0.001

-- Team names
local attackTeam = "Blue"
local defenseTeam = "Red"

-- Ticket management computer ID
local ticketComputerId = 2

-- Score changes when player enters zone
local defenseScoreChange = -1
local attackScoreChange = 1
local neutralScoreChange = -1

-- Tickets gained/lost per zone captured
local ticketRewards = {
    { a = 200, d = -50 },
    { a = 200, d = -50 },
    { a = 200, d = -50 }
}

-- Capture zone coordinates
local captureZones = {
    { x = 4836, y = 19, z = 6160 },
    { x = 4711, y = 16, z = 5925 },
    { x = 4815, y = 28, z = 5561  },
}

-- Attacker spawn points
local attackerSpawns = {
    { x = 4243, y = 308, z = 6653 },
    { x = 4243, y = 308, z = 6653 },
    { x = 4243, y = 308, z = 6653 }
}

-- Defender spawn points
local defenderSpawns = {
    { x = 4237, y = 308, z = 6653 },
    { x = 4237, y = 308, z = 6653 },
    { x = 4237, y = 308, z = 6653 }
}

-- Function to broadcast the stage to other computers (e.g., infantry/tank systems)
local function broadcastStage(stage)
    modem.transmit(STAGE_CHANNEL, STAGE_CHANNEL, { stage = stage })
    print("Broadcasting Stage: " .. stage)
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

-- Initial beacon setup
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

-- Main game loop
while true do
    local attackerDetected = commands.exec("execute as @a[team=" .. attackTeam .. ",x=" .. captureZones[currentZoneIndex].x .. ",y=" .. captureZones[currentZoneIndex].y .. ",z=" .. captureZones[currentZoneIndex].z .. ",distance=.." .. captureRange .. "] at @s run effect give @s saturation 1")
    local defenderDetected = commands.exec("execute as @a[team=" .. defenseTeam .. ",x=" .. captureZones[currentZoneIndex].x .. ",y=" .. captureZones[currentZoneIndex].y .. ",z=" .. captureZones[currentZoneIndex].z .. ",distance=.." .. captureRange .. "] at @s run effect give @s saturation 1")

    if defenderDetected then
        zoneScore = zoneScore + defenseScoreChange
        print("Defender in zone")
    end
    if attackerDetected then
        zoneScore = zoneScore + attackScoreChange
        print("Attacker in zone")
    end
    if not(defenderDetected) and not(attackerDetected) then
        zoneScore = zoneScore + neutralScoreChange
    end

    if redstone.getInput("front") and os.clock() > skipCooldown then
        print("Zone skipped by button press")
        zoneScore = 201  -- Trigger capture logic
        skipCooldown = os.clock() + skipDelay
    end
    -- Clamp score
    if zoneScore < 0 then zoneScore = 0 end

    -- Set current beacon
    commands.exec("/setblock " .. captureZones[currentZoneIndex].x .. " " .. captureZones[currentZoneIndex].y .. " " .. captureZones[currentZoneIndex].z .. " minecraft:beacon")
    
    -- After the zone score reaches 200 (zone is captured):
    if zoneScore > 200 then
        zoneScore = 0
        -- Clear current beacon
        print("Captued, moving to next")
        commands.exec("/setblock " .. captureZones[currentZoneIndex].x .. " " .. captureZones[currentZoneIndex].y .. " " .. captureZones[currentZoneIndex].z .. " air")

        -- Send ticket update
        rednet.send(ticketComputerId, "A" .. ticketRewards[currentZoneIndex].a .. "D" .. ticketRewards[currentZoneIndex].d)

        -- Play feedback (victory light or sound)
        redstone.setAnalogOutput("top", 15)
        sleep(0)
        redstone.setAnalogOutput("top", 0)

        -- Show capture notification title to all players
        commands.exec("/title @a title {\"text\":\"Objective Captured! Stage " .. currentZoneIndex .. " Completed!\",\"color\":\"green\"}")

        if currentZoneIndex == #captureZones - 1 then
            -- Near final zone
            sleep(1)
            redstone.setAnalogOutput("left", 15)
            sleep(0.1)
            redstone.setAnalogOutput("left", 0)
        elseif currentZoneIndex == #captureZones then
            -- Final zone captured
            redstone.setAnalogOutput("right", 15)
            sleep(0.1)
            redstone.setAnalogOutput("right", 0)

            while true do
                rednet.send(ticketComputerId, "A0D-10")
                sleep(2)
                print("Game Ended")
            end
        end

        -- Move to next zone
        currentZoneIndex = currentZoneIndex + 1

        -- Broadcast the current stage
        broadcastStage(currentZoneIndex)

        -- Update the boss bar with current and total stage, adjust color dynamically
        commands.exec("/bossbar set " .. bossbarId .. " title \"Stage " .. currentZoneIndex .. " of " .. #captureZones .. "\"")
        -- Set next beacon for the current zone
        commands.exec("/setblock " .. captureZones[currentZoneIndex].x .. " " .. captureZones[currentZoneIndex].y .. " " .. captureZones[currentZoneIndex].z .. " minecraft:beacon")
    end

    -- Dynamically adjust the color of the boss bar based on zone score
    local color = "white"
    if attackerDetected then
        color = "blue"
    elseif zoneScore > 0 then
        color = "green"
    end
    commands.exec("/bossbar set " .. bossbarId .. " color " .. color)

    -- Update the boss bar value
    commands.exec("/bossbar set " .. bossbarId .. " value " .. zoneScore / 2)

    -- Update spawn points for the teams
    commands.exec("/spawnpoint @a[team=" .. attackTeam .. "] " .. attackerSpawns[currentZoneIndex].x .. " " .. attackerSpawns[currentZoneIndex].y .. " " .. attackerSpawns[currentZoneIndex].z)
    commands.exec("/spawnpoint @a[team=" .. defenseTeam .. "] " .. defenderSpawns[currentZoneIndex].x .. " " .. defenderSpawns[currentZoneIndex].y .. " " .. defenderSpawns[currentZoneIndex].z)

    sleep(updateInterval)
end
