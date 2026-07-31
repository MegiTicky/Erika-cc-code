-- Setup
local posX, posY, posZ = commands.getBlockPosition()
local zonePos = { x = 6512, y = 24, z = 6430 }
local blueSpawn = {x=6436,y=232,z=6631}
local redSpawn = {x=6442,y=232,z=6631}

local captureRange = 40
local updateInterval = 0.5  -- seconds

-- Team names
local blueTeam = "Blue"
local redTeam = "Red"

-- Ticket drain per tick after capture
local ticketDrain = 1

-- Capture progress for each team
local blueProgress = 0
local redProgress = 0
local maxProgress = 200

-- Capture state
local currentOwner = nil

-- Initialize scores
commands.exec("/scoreboard players set Red Tickets 750")
commands.exec("/scoreboard players set Blue Tickets 750")

-- Initialize bossbar
commands.exec("/bossbar add capturebar \"Capture Progress\"")
commands.exec("/bossbar set capturebar max " .. maxProgress)
commands.exec("/bossbar set capturebar visible true")
commands.exec("/bossbar set capturebar players @a")

while true do
    -- Check players in zone
    local redInZone = commands.exec(
        "execute as @a[team=" .. redTeam .. ",x=" .. zonePos.x ..
        ",y=" .. zonePos.y .. ",z=" .. zonePos.z .. ",distance=.." .. captureRange ..
        "] run effect give @s saturation 1"
    )

    local blueInZone = commands.exec(
        "execute as @a[team=" .. blueTeam .. ",x=" .. zonePos.x ..
        ",y=" .. zonePos.y .. ",z=" .. zonePos.z .. ",distance=.." .. captureRange ..
        "] run effect give @s saturation 1"
    )

    local redPresent = redInZone
    local bluePresent = blueInZone

    if redPresent and not bluePresent then
        if blueProgress > 0 then
            blueProgress = math.max(blueProgress - 10, 0)
            print("Red is decapping Blue! Blue progress: " .. blueProgress)
        else
            redProgress = math.min(redProgress + 10, maxProgress)
            print("Red capturing... Red progress: " .. redProgress)
        end
    elseif bluePresent and not redPresent then
        if redProgress > 0 then
            redProgress = math.max(redProgress - 10, 0)
            print("Blue is decapping Red! Red progress: " .. redProgress)
        else
            blueProgress = math.min(blueProgress + 10, maxProgress)
            print("Blue capturing... Blue progress: " .. blueProgress)
        end
    elseif redPresent and bluePresent then
        print("Contested! Progress paused.")
    else
        print("No players in zone. Progress paused.")
    end

    -- Check if capture completed
    if redProgress >= maxProgress then
        currentOwner = "Red"
        print("Red captured the zone!")
    elseif blueProgress >= maxProgress then
        currentOwner = "Blue"
        print("Blue captured the zone!")
    else
        currentOwner = "NotCaptured"
        if redProgress > 0 then
            redProgress = math.max(redProgress - 2, 0)
            print("Red progress decaying: " .. redProgress)
        end
        if blueProgress > 0 then
            blueProgress = math.max(blueProgress - 2, 0)
            print("Blue progress decaying: " .. blueProgress)
        end
    end
        

    
    -- Update bossbar to show whichever team's progress is higher
    if redProgress > 0 then
        commands.exec("/bossbar set capturebar value " .. redProgress)
        commands.exec("/bossbar set capturebar name {\"text\":\"Red\",\"color\":\"red\"}")
        commands.exec("/bossbar set capturebar color red")
    elseif blueProgress > 0 then
        commands.exec("/bossbar set capturebar value " .. blueProgress)
        commands.exec("/bossbar set capturebar name {\"text\":\"Blue\",\"color\":\"blue\"}")
        commands.exec("/bossbar set capturebar color blue")
    else
        commands.exec("/bossbar set capturebar value 0")
        commands.exec("/bossbar set capturebar name {\"text\":\"Neutral Zone\",\"color\":\"white\"}")
        commands.exec("/bossbar set capturebar color white")
    end

    -- Drain tickets if captured
    if currentOwner == "Red" then
        commands.exec("/scoreboard players remove Blue Tickets " .. ticketDrain)
        print("Red owns zone! Draining Blue tickets.")
    elseif currentOwner == "Blue" then
        commands.exec("/scoreboard players remove Red Tickets " .. ticketDrain)
        print("Blue owns zone! Draining Red tickets.")
    end

    -- Check scores
    local _,_,redResult = commands.exec("/scoreboard players get Red Tickets")
    local _,_,blueResult = commands.exec("/scoreboard players get Blue Tickets")

    local redScore = tonumber(redResult)
    local blueScore = tonumber(blueResult)

    if redScore and redScore <= 0 then
        commands.exec("/title @a title {\"text\":\"Blue Wins!\",\"color\":\"blue\"}")
        break
    elseif blueScore and blueScore <= 0 then
        commands.exec("/title @a title {\"text\":\"Red Wins!\",\"color\":\"red\"}")
        break
    end

    --set spawn point
    commands.exec("/spawnpoint @a[team=" .. blueTeam .. "] " .. blueSpawn.x .. " " .. blueSpawn.y .. " " .. blueSpawn.z)
    commands.exec("/spawnpoint @a[team=" .. redTeam .. "] " .. redSpawn.x .. " " .. redSpawn.y .. " " .. redSpawn.z)

    sleep(updateInterval)
end
