-- Grandop stage channel.
-- Shared stage broadcast/listen over a modem channel, used by objective
-- controllers (broadcaster) and respawn terminals (listener).

local stage = {}

--- Create a stage hub bound to a channel. Requires a modem peripheral.
function stage.new(channel)
    local modem = peripheral.find("modem")
    if not modem then error("Modem (wireless or wired) not found!") end
    return {
        channel = channel,
        current = 1,
        modem = modem,
    }
end

-- Broadcast the current stage to everyone listening on the channel.
function stage.broadcast(s, stageNum)
    s.modem.transmit(s.channel, s.channel, { stage = stageNum })
    print("Broadcasting Stage: " .. tostring(stageNum))
end

-- Returns a loop to run with parallel.waitForAny; keeps s.current updated.
-- Accepts plain numbers or tables { stage = number }.
function stage.listener(s)
    s.modem.open(s.channel)
    return function()
        while true do
            local ev, side, ch, rch, msg = os.pullEvent("modem_message")
            if ch == s.channel then
                if type(msg) == "number" then
                    s.current = msg
                elseif type(msg) == "table" and tonumber(msg.stage) then
                    s.current = tonumber(msg.stage)
                end
                print("Stage update -> " .. tostring(s.current))
            end
        end
    end
end

return stage
