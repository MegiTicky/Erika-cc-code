-- Grandop control point (conquest) objective engine.
--
-- A single neutral capture zone: teams build opposing progress; whoever caps
-- first owns the zone and drains the enemy tickets each tick until one side
-- hits zero. Faithful port of conquestGround.lua, driven by mission config.

local mc = require("minecraft")

local engine = {}

function engine.run(mcfg)
    local zonePos = mcfg.zonePos
    local blueTeam, redTeam = mcfg.blueTeam, mcfg.redTeam
    local blueSpawn, redSpawn = mcfg.blueSpawn, mcfg.redSpawn
    local captureRange = mcfg.captureRange or 40
    local updateInterval = mcfg.updateInterval or 0.5
    local ticketDrain = mcfg.ticketDrain or 1
    local maxProgress = mcfg.maxProgress or 200
    local capRate = mcfg.capRate or 10
    local decapRate = mcfg.decapRate or 10
    local decayRate = mcfg.decayRate or 2
    local bossbarId = mcfg.bossbarId or "capturebar"
    local startTickets = mcfg.startTickets or 750

    local blueProgress, redProgress = 0, 0
    local currentOwner = nil

    mc.scoreboardSet("Red", "Tickets", startTickets)
    mc.scoreboardSet("Blue", "Tickets", startTickets)

    commands.exec("/bossbar add " .. bossbarId .. " \"Capture Progress\"")
    commands.exec("/bossbar set " .. bossbarId .. " max " .. maxProgress)
    commands.exec("/bossbar set " .. bossbarId .. " visible true")
    commands.exec("/bossbar set " .. bossbarId .. " players @a")

    while true do
        local redInZone = mc.playersInRange(redTeam, zonePos.x, zonePos.y, zonePos.z, captureRange)
        local blueInZone = mc.playersInRange(blueTeam, zonePos.x, zonePos.y, zonePos.z, captureRange)
        local redPresent, bluePresent = redInZone, blueInZone

        if redPresent and not bluePresent then
            if blueProgress > 0 then
                blueProgress = math.max(blueProgress - decapRate, 0)
                print("Red is decapping Blue! Blue progress: " .. blueProgress)
            else
                redProgress = math.min(redProgress + capRate, maxProgress)
                print("Red capturing... Red progress: " .. redProgress)
            end
        elseif bluePresent and not redPresent then
            if redProgress > 0 then
                redProgress = math.max(redProgress - decapRate, 0)
                print("Blue is decapping Red! Red progress: " .. redProgress)
            else
                blueProgress = math.min(blueProgress + capRate, maxProgress)
                print("Blue capturing... Blue progress: " .. blueProgress)
            end
        elseif redPresent and bluePresent then
            print("Contested! Progress paused.")
        else
            print("No players in zone. Progress paused.")
        end

        if redProgress >= maxProgress then
            currentOwner = "Red"
            print("Red captured the zone!")
        elseif blueProgress >= maxProgress then
            currentOwner = "Blue"
            print("Blue captured the zone!")
        else
            currentOwner = "NotCaptured"
            if redProgress > 0 then
                redProgress = math.max(redProgress - decayRate, 0)
                print("Red progress decaying: " .. redProgress)
            end
            if blueProgress > 0 then
                blueProgress = math.max(blueProgress - decayRate, 0)
                print("Blue progress decaying: " .. blueProgress)
            end
        end

        if redProgress > 0 then
            commands.exec("/bossbar set " .. bossbarId .. " value " .. redProgress)
            commands.exec('/bossbar set ' .. bossbarId .. ' name {"text":"Red","color":"red"}')
            commands.exec("/bossbar set " .. bossbarId .. " color red")
        elseif blueProgress > 0 then
            commands.exec("/bossbar set " .. bossbarId .. " value " .. blueProgress)
            commands.exec('/bossbar set ' .. bossbarId .. ' name {"text":"Blue","color":"blue"}')
            commands.exec("/bossbar set " .. bossbarId .. " color blue")
        else
            commands.exec("/bossbar set " .. bossbarId .. " value 0")
            commands.exec('/bossbar set ' .. bossbarId .. ' name {"text":"Neutral Zone","color":"white"}')
            commands.exec("/bossbar set " .. bossbarId .. " color white")
        end

        if currentOwner == "Red" then
            commands.exec("/scoreboard players remove Blue Tickets " .. ticketDrain)
            print("Red owns zone! Draining Blue tickets.")
        elseif currentOwner == "Blue" then
            commands.exec("/scoreboard players remove Red Tickets " .. ticketDrain)
            print("Blue owns zone! Draining Red tickets.")
        end

        local redScore = mc.scoreboardGet("Red", "Tickets")
        local blueScore = mc.scoreboardGet("Blue", "Tickets")

        if redScore and redScore <= 0 then
            commands.exec('/title @a title {"text":"Blue Wins!","color":"blue"}')
            break
        elseif blueScore and blueScore <= 0 then
            commands.exec('/title @a title {"text":"Red Wins!","color":"red"}')
            break
        end

        mc.setSpawnpoint(blueTeam, blueSpawn.x, blueSpawn.y, blueSpawn.z)
        mc.setSpawnpoint(redTeam, redSpawn.x, redSpawn.y, redSpawn.z)

        sleep(updateInterval)
    end
end

return engine
