local modem = peripheral.find("modem")
local monitor = peripheral.find("monitor")
local imageChannel = 600
local controlChannel = 601
local distanceChannel = 604
local distance = 0

modem.open(imageChannel)
modem.open(distanceChannel)

local function hexColorFromCode(code)
    local colors = {
        ["0"] = "000000", -- Black
        ["1"] = "0000AA", -- Dark Blue
        ["2"] = "00AA00", -- Dark Green
        ["3"] = "00AAAA", -- Dark Aqua
        ["4"] = "AA0000", -- Dark Red
        ["5"] = "AA00AA", -- Dark Purple
        ["6"] = "FFAA00", -- Gold
        ["7"] = "AAAAAA", -- Gray
        ["8"] = "555555", -- Dark Gray
        ["9"] = "5555FF", -- Blue
        ["a"] = "55FF55", -- Green
        ["b"] = "55FFFF", -- Aqua
        ["c"] = "FF5555", -- Red
        ["d"] = "FF55FF", -- Light Purple
        ["e"] = "FFFF55", -- Yellow
        ["f"] = "FFFFFF", -- White
    }
    return colors[code] or "000000"
end

monitor.setTextScale(0.5)
monitor.clear()
local width, height = monitor.getSize()

local function render(data)
    local mirroredX = width - data[1] + 1
    monitor.setCursorPos(mirroredX, data[2])
    
    -- Check if the position is the center of the screen
    if mirroredX == math.floor(width / 2) + 1 and data[2] == math.floor(height / 2) then
        -- Render crosshair "o" without changing the background color
        monitor.blit("o", "f", data[5])
    else
        monitor.blit(data[3], data[4], data[5])
    end
end

local function receiving()
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if channel == imageChannel then
            render(message)
        elseif channel == distanceChannel then
            distance = message
        end
        monitor.setCursorPos(1, 1)
        monitor.write("- / +".."  ".."TR:"..math.floor(distance))
    end
end

local function handleTouch()
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        if y == 1 and x == 1 then
            modem.transmit(controlChannel,0,0.1)
            print("decreasing")
        elseif y == 1 and x == 5 then
            modem.transmit(controlChannel,0,-0.1)
            print("increasing")
        else
            modem.transmit(controlChannel,0,0)
        end
    end
end

parallel.waitForAny(
    receiving,
    handleTouch
)
