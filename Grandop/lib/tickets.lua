-- Grandop ticket management.
-- Standardises the ticket message protocol between objective controllers and
-- the ticket server, and runs the rednet-based ticket server loop.

local tickets = {}

-- Protocol: a message is "A<atkDelta>D<defDelta>" where a negative value means
-- tickets are removed, a positive value means they are added.
function tickets.format(atkDelta, defDelta)
    return "A" .. tostring(atkDelta) .. "D" .. tostring(defDelta)
end

function tickets.parse(msg)
    return msg:match("A(-?%d+)D(-?%d+)")
end

-- Apply a parsed message to the scoreboard. Returns true when it was applied.
function tickets.apply(attackTeam, defenseTeam, atkDelta, defDelta)
    if atkDelta < 0 then
        commands.exec("/scoreboard players remove " .. attackTeam .. " tickets " .. math.abs(atkDelta))
    else
        commands.exec("/scoreboard players add " .. attackTeam .. " tickets " .. math.abs(atkDelta))
    end

    if defDelta < 0 then
        commands.exec("/scoreboard players remove " .. defenseTeam .. " tickets " .. math.abs(defDelta))
    else
        commands.exec("/scoreboard players add " .. defenseTeam .. " tickets " .. math.abs(defDelta))
    end

    return true
end

-- Read the current ticket values from the scoreboard.
function tickets.get(attackTeam, defenseTeam)
    local _, _, a = commands.exec("/scoreboard players get " .. attackTeam .. " tickets")
    local _, _, d = commands.exec("/scoreboard players get " .. defenseTeam .. " tickets")
    return tonumber(a), tonumber(d)
end

--- Run the ticket server.
-- options = {
--   openSide  = "bottom",          -- rednet side
--   attackTeam = "Red",
--   defenseTeam = "Blue",
--   attackStart = 500,
--   defenseStart = 500,
--   beaconPulse = { side = "top", seconds = 0.1 },  -- optional startup pulse
--   onLow = function(teamName) end,  -- called when a team's tickets hit 0
-- }
function tickets.run(options)
    if options.openSide then
        rednet.open(options.openSide)
    end

    if options.beaconPulse then
        local b = options.beaconPulse
        redstone.setAnalogOutput(b.side, 15)
        sleep(b.seconds or 0.1)
        redstone.setAnalogOutput(b.side, 0)
    end

    commands.exec("/scoreboard players set " .. options.attackTeam .. " tickets " .. tostring(options.attackStart or 500))
    commands.exec("/scoreboard players set " .. options.defenseTeam .. " tickets " .. tostring(options.defenseStart or 500))

    while true do
        local id, msg = rednet.receive(0)
        if id and type(msg) == "string" then
            local a, d = tickets.parse(msg)
            if a and d then
                tickets.apply(options.attackTeam, options.defenseTeam, tonumber(a), tonumber(d))
                print("Processed message from ID: " .. id)
            else
                print("Invalid message format from ID: " .. id)
            end

            local atkNow, defNow = tickets.get(options.attackTeam, options.defenseTeam)
            if atkNow and atkNow < 1 then
                redstone.setAnalogOutput("left", 15)
                sleep(0.1)
                redstone.setAnalogOutput("left", 0)
                if options.onLow then options.onLow(options.attackTeam) end
            end
            if defNow and defNow < 1 then
                redstone.setAnalogOutput("right", 15)
                sleep(0.1)
                redstone.setAnalogOutput("right", 0)
                if options.onLow then options.onLow(options.defenseTeam) end
            end
        end
        sleep(0.05)
    end
end

return tickets
