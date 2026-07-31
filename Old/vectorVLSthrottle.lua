local modem = peripheral.find("modem")

print("Input the missile id, eg:1, default: 1")
local missileId = io.read()
if missileId == "" then
    missileId = 1
end
missileId = tonumber(missileId)

local controlsChannel = 1300

local throttleChannel = controlsChannel + missileId
modem.open(throttleChannel)
modem.open(controlsChannel)
print("throttleChannel: "..throttleChannel)

redstone.setAnalogOutput("front",0)
redstone.setAnalogOutput("back",0)
redstone.setOutput("top",false)

local launched = false
local function throttleControl()
    while true do
        if throttle and launched and type(throttle) == "number" then
            redstone.setAnalogOutput("front",math.min(tonumber(throttle),15))
            redstone.setAnalogOutput("back",math.min(tonumber(throttle),15))
        end
        sleep()
    end
end

local function openLaunchHatch()
    while true do
        if throttle and throttle == "unlock" then
            redstone.setOutput("top",true)
            sleep(0.1)
            redstone.setOutput("top",false)
            launched = true
        end
        sleep()
    end
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == controlsChannel then
                controls = message
            elseif channel == throttleChannel then
                throttle = message
            end
        else
            sleep()
        end
    end
end

parallel.waitForAny(
    modemMessage,
    throttleControl,
    openLaunchHatch
)
