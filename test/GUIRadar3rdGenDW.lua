local modem = peripheral.find("modem")
local monitor = peripheral.find("monitor")

local shipCenters = {}

print("Input the radarResultChannel, default: 400")
local radarResultChannel = io.read()
if radarResultChannel == "" then
    radarResultChannel = 400
end
radarResultChannel = tonumber(radarResultChannel)

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == radarResultChannel then
                shipCenters = message
            end
        else
            sleep()
        end
    end
end

local function main()
    while true do
        if shipCenters then
            if monitor then
                if next(shipCenters) == nil then
                    monitor.write("No ships detected.")
                else
                    for ship_id, center in pairs(shipCenters) do
                        monitor.write(string.format("Ship ID: %s\nCenter: X: %.2f, Y: %.2f, Z: %.2f\n", ship_id, center.x, center.y, center.z))
                        local x, y = monitor.getCursorPos()
                        monitor.setCursorPos(1, y + 1)
                        monitor.clearLine()
                    end
                end
            end
        end
        sleep()
    end
end

parallel.waitForAny(
    modemMessage,
    main
)