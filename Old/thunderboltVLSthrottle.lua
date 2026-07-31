local modem = peripheral.find("modem")
local motor = peripheral.find("electric_motor")

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
        if throttle then
            motor.setSpeed(-throttle)
            if throttle > 0 then
                print("accelerating")
            end
        end
        sleep(0.2)
    end
end

local function openLaunchHatch()
    while true do
        if not(launched) and controls and controls.fireMissile and controls.fireMissile[missileId] and controls.fireMissile[missileId].launch == true then
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
