-- Dedicated Grandop operator terminal. Configure /data/operator_config.lua first.
local config = dofile("/data/operator_config.lua")
if peripheral.getType(config.rednet_side) ~= "modem" then error("No modem on " .. config.rednet_side) end
rednet.open(config.rednet_side)
local nextRequest = 0
local PROTOCOL = "grandop_operator"

local function request(action, args)
    nextRequest = nextRequest + 1
    rednet.broadcast({ type = "grandop_operator_request", reply_to = os.getComputerID(), request_id = nextRequest, action = action, args = args or {} }, PROTOCOL)
    local timer = os.startTimer(5)
    while true do
        local event, id, message = os.pullEvent()
        if event == "timer" and id == timer then return nil, "Timed out" end
        if event == "rednet_message" and type(message) == "table" and message.type == "grandop_operator_response" and message.target == os.getComputerID() and message.request_id == nextRequest then
            return message.ok and message.data or nil, message.message
        end
    end
end

local function confirm(text)
    write(text .. " Type YES: ")
    return read() == "YES"
end

local function showStatus()
    local data, message = request("status")
    if not data then printError(message); return end
    print("Mission: " .. data.mission .. " | " .. (data.paused and "PAUSED" or "RUNNING") .. " | Stage: " .. data.stage)
    print("Respawn counts:")
    for pool, value in pairs(data.quotas) do print("  " .. pool .. ": " .. value) end
end

while true do
    term.clear(); term.setCursorPos(1, 1)
    print("=== Grandop Operator ===")
    print("1. Status")
    print("2. Pause event")
    print("3. Resume event")
    print("4. Set stage")
    print("5. Set respawn count")
    print("6. Graceful event shutdown")
    print("7. Stop and reset new match")
    print("8. Exit")
    write("Select: ")
    local choice = read()
    if choice == "1" then showStatus()
    elseif choice == "2" and confirm("Pause event?") then local _, m = request("pause"); print(m)
    elseif choice == "3" and confirm("Resume event?") then local _, m = request("resume"); print(m)
    elseif choice == "4" then
        write("Stage number: "); local value = tonumber(read())
        if value and confirm("Set active stage to " .. value .. "?") then local _, m = request("stage_set", { value = value }); print(m) end
    elseif choice == "5" then
        write("Respawn pool: "); local pool = read(); write("Remaining count: "); local value = tonumber(read())
        if value and confirm("Set " .. pool .. " to " .. value .. "?") then local _, m = request("quota_set", { pool = pool, value = value }); print(m) end
    elseif choice == "6" and confirm("Shut down event?") then local _, m = request("shutdown"); print(m)
    elseif choice == "7" and confirm("Stop event before resetting the match?") then local _, m = request("reset_match"); print(m)
    elseif choice == "8" then break end
    print("Press any key..."); os.pullEvent("key")
end
