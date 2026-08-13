-- Setup
local posX, posY, posZ = commands.getBlockPosition()
local myPosition = { x = posX, y = posY, z = posZ }
local zoneScore = 0
local bossbarId = 1
local currentZoneIndex = 1

-- Detection range and update rate
local captureRange = 20
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
    { a = 200, d = -50 },
    { a = 200, d = -50 },
    { a = 200, d = -50 }
}

-- Capture zone coordinates
local captureZones = {
    { x = 4105, y = 3, z = 6850 },
    { x = 4333, y = 35, z = 6908 },
    { x = 4363, y = 19, z = 6534 },
    { x = 4323, y = 14, z = 6395 },
    { x = 4581, y = 17, z = 6429 }
}

-- Attacker spawn points
local attackerSpawns = {
    { x = 0, y = 0, z = 0 },
    { x = 4280, y = 297, z = 6662 },
    { x = 4266, y = 297, z = 6662 },
    { x = 4252, y = 297, z = 6662 },
    { x = 4238, y = 297, z = 6662 }
}

-- Defender spawn points
local defenderSpawns = {
    { x = 4301, y = 297, z = 6662 },
    { x = 4288, y = 297, z = 6662 },
    { x = 4274, y = 297, z = 6662 },
    { x = 4260, y = 297, z = 6662 },
    { x = 4246, y = 297, z = 6662 }
}

--[[Attacker spawn points (actual tp)
local attackerSpawns = {
    { x = 0, y = 0, z = 0 },
    { x = 4129, y = 12, z = 6795 },
    { x = 4440, y = 31, z = 6787 },
    { x = 4222, y = 10, z = 6610 },
    { x = 4362, y = 19, z = 6553 }
}

Defender spawn points
local defenderSpawns = {
    { x = 4292, y = 23, z = 6908 },
    { x = 4418, y = 29, z = 6972 },
    { x = 4475, y = 24, z = 6510 },
    { x = 4475, y = 24, z = 6510 },
    { x = 4617, y = 15, z = 6395 }
}]]

-- Initial beacon setup
redstone.setOutput("back", false)
sleep(0.1)
redstone.setOutput("back", true)
commands.exec("/setblock " .. captureZones[currentZoneIndex].x .. " " .. captureZones[currentZoneIndex].y .. " " .. captureZones[currentZoneIndex].z .. " minecraft:beacon")

-- Clear all other zones
for i = 1, #captureZones do
    commands.exec("/setblock " .. captureZones[i].x .. " " .. captureZones[i].y .. " " .. captureZones[i].z .. " air")
end

-- Set current active zone
commands.exec("/setblock " .. captureZones[currentZoneIndex].x .. " " .. captureZones[currentZoneIndex].y .. " " .. captureZones[currentZoneIndex].z .. " minecraft:beacon")

local skipCooldown = 0
local skipDelay = 3  -- seconds

-- Main game loop
while true do
    local attackerDetected = commands.exec("execute as @a[team=" .. attackTeam .. ",x=" .. captureZones[currentZoneIndex].x .. ",y=" .. captureZones[currentZoneIndex].y .. ",z=" .. captureZones[currentZoneIndex].z .. ",distance=.." .. captureRange .. "] at @s run effect give @s saturation 1")
    local defenderDetected = commands.exec("execute as @a[team=" .. defenseTeam .. ",x=" .. captureZones[currentZoneIndex].x .. ",y=" .. captureZones[currentZoneIndex].y .. ",z=" .. captureZones[currentZoneIndex].z .. ",distance=.." .. captureRange .. "] at @s run effect give @s saturation 1")

    print(attackerDetected)

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

    if zoneScore > 200 then
        zoneScore = 0
        -- Clear current beacon
        commands.exec("/setblock " .. captureZones[currentZoneIndex].x .. " " .. captureZones[currentZoneIndex].y .. " " .. captureZones[currentZoneIndex].z .. " air")

        -- Send ticket update
        rednet.send(ticketComputerId, "A" .. ticketRewards[currentZoneIndex].a .. "D" .. ticketRewards[currentZoneIndex].d)

        -- Play feedback (victory light or sound)
        redstone.setAnalogOutput("top", 15)
        sleep(0)
        redstone.setAnalogOutput("top", 0)

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
        commands.exec("/setblock " .. captureZones[currentZoneIndex].x .. " " .. captureZones[currentZoneIndex].y .. " " .. captureZones[currentZoneIndex].z .. " minecraft:beacon")
    end

    -- Update boss bar and spawn points
    commands.exec("/bossbar set " .. bossbarId .. " value " .. zoneScore / 2)
    if currentZoneIndex ~= 1 then
        commands.exec("/spawnpoint @a[team=" .. attackTeam .. "] " .. attackerSpawns[currentZoneIndex].x .. " " .. attackerSpawns[currentZoneIndex].y .. " " .. attackerSpawns[currentZoneIndex].z)
        --they spawn on ships
    end
    commands.exec("/spawnpoint @a[team=" .. defenseTeam .. "] " .. defenderSpawns[currentZoneIndex].x .. " " .. defenderSpawns[currentZoneIndex].y .. " " .. defenderSpawns[currentZoneIndex].z)

    sleep(updateInterval)
end
