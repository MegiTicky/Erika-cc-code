-- Grandop base assault objective engine.
--
-- Two bases, one per team. Each base has an owner and attacker progress shown
-- on a bossbar. Capturing the enemy base ends the round instantly. Faithful
-- port of BattleGroundSystem.lua, driven by mission config.

local mc = require("minecraft")

local engine = {}

function engine.run(mcfg)
    local BLUE, RED = mcfg.blueTeam, mcfg.redTeam
    local blueSpawn, redSpawn = mcfg.blueSpawn, mcfg.redSpawn
    local captureRange = mcfg.captureRange or 40
    local updateInterval = mcfg.updateInterval or 0.5
    local maxProgress = mcfg.maxProgress or 200
    local capRate = mcfg.capRate or 1
    local decapRate = mcfg.decapRate or 1
    local stall = mcfg.stall or 1

    local bases = mcfg.bases -- { blue = {name, x, y, z, owner, prog, barId}, red = {...} }

    local function anyone(selector)
        return commands.exec("execute if entity " .. selector) and true or false
    end

    local function setupBossbars()
        for key, b in pairs(bases) do
            commands.exec('/bossbar add ' .. b.barId .. ' "' .. b.pos.name .. '"')
            commands.exec('/bossbar set ' .. b.barId .. ' max ' .. maxProgress)
            commands.exec('/bossbar set ' .. b.barId .. ' visible true')
            commands.exec('/bossbar set ' .. b.barId .. ' players @a')
        end
    end

    local function updateBossbar(b)
        local bar = b.barId
        if b.prog > 0 then
            local attacker = (b.owner == BLUE) and RED or BLUE
            commands.exec('/bossbar set ' .. bar .. ' value ' .. b.prog)
            if attacker == RED then
                commands.exec('/bossbar set ' .. bar .. ' name {"text":"' .. b.pos.name .. ' - Attacked by RED","color":"red"}')
                commands.exec('/bossbar set ' .. bar .. ' color red')
            else
                commands.exec('/bossbar set ' .. bar .. ' name {"text":"' .. b.pos.name .. ' - Attacked by BLUE","color":"blue"}')
                commands.exec('/bossbar set ' .. bar .. ' color blue')
            end
        else
            commands.exec('/bossbar set ' .. bar .. ' value 0')
            if b.owner == BLUE then
                commands.exec('/bossbar set ' .. bar .. ' name {"text":"' .. b.pos.name .. ' - Controlled by Blue","color":"blue"}')
                commands.exec('/bossbar set ' .. bar .. ' color blue')
            elseif b.owner == RED then
                commands.exec('/bossbar set ' .. bar .. ' name {"text":"' .. b.pos.name .. ' - Controlled by Red","color":"red"}')
                commands.exec('/bossbar set ' .. bar .. ' color red')
            else
                commands.exec('/bossbar set ' .. bar .. ' name {"text":"' .. b.pos.name .. ' - Neutral","color":"white"}')
                commands.exec('/bossbar set ' .. bar .. ' color white')
            end
        end
    end

    setupBossbars()

    local function stepBase(key)
        local b = bases[key]
        local px, py, pz = b.pos.x, b.pos.y, b.pos.z

        local selectorBlue = "@a[team=" .. BLUE .. ",x=" .. px .. ",y=" .. py .. ",z=" .. pz .. ",distance=.." .. captureRange .. "]"
        local selectorRed  = "@a[team=" .. RED .. ",x=" .. px .. ",y=" .. py .. ",z=" .. pz .. ",distance=.." .. captureRange .. "]"

        local blueHere = anyone(selectorBlue)
        local redHere = anyone(selectorRed)

        local attacker, defender
        if b.owner == BLUE then
            attacker, defender = RED, BLUE
        else
            attacker, defender = BLUE, RED
        end

        if blueHere then commands.exec("execute as " .. selectorBlue .. " run effect give @s saturation 1") end
        if redHere then commands.exec("execute as " .. selectorRed .. " run effect give @s saturation 1") end

        if blueHere and redHere then
            if stall ~= 0 and b.prog > 0 then
                b.prog = math.max(0, b.prog - stall)
            end
        else
            if attacker == RED then
                if redHere and not blueHere then
                    b.prog = math.min(maxProgress, b.prog + capRate)
                elseif blueHere and not redHere then
                    if b.prog > 0 then b.prog = math.max(0, b.prog - decapRate) end
                end
            else
                if blueHere and not redHere then
                    b.prog = math.min(maxProgress, b.prog + capRate)
                elseif redHere and not blueHere then
                    if b.prog > 0 then b.prog = math.max(0, b.prog - decapRate) end
                end
            end
        end

        if not blueHere and not redHere then
            if b.prog > 0 then b.prog = math.max(0, b.prog - stall) end
        end

        if b.prog >= maxProgress then
            b.owner = attacker
            b.prog = 0
            local winner = attacker
            commands.exec('/title @a title {"text":"' .. winner .. ' captured the enemy base!","color":"' .. (winner == BLUE and 'blue' or 'red') .. '"}')
            commands.exec('/title @a subtitle {"text":"' .. winner .. ' Wins","color":"' .. (winner == BLUE and 'blue' or 'red') .. '"}')
            return true
        end

        updateBossbar(b)
        return false
    end

    while true do
        mc.setSpawnpoint(BLUE, blueSpawn.x, blueSpawn.y, blueSpawn.z)
        mc.setSpawnpoint(RED, redSpawn.x, redSpawn.y, redSpawn.z)

        if stepBase("blue") then break end
        if stepBase("red") then break end

        sleep(updateInterval)
    end
end

return engine
