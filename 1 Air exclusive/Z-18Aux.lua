local modem = peripheral.find("modem")
local motor = peripheral.find("Create_RotationSpeedController")
redstone.setOutput("front",false)
motor.setTargetSpeed(0)
print("Input the controlChannel, default = 1100")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 1100
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel) -- Open a channel to communicate
local AuxControlChannel = controlChannel + 1
modem.open(AuxControlChannel)

local function manualCannonControl()
    while true do
        if AuxControls then
            motor.setTargetSpeed(AuxControls.tailSpeed)
        end
        sleep()
    end
end

local function pitchControl()
    while true do
        if AuxControls and AuxControls.pitch then
            if AuxControls.pitch > 0  then
                redstone.setAnalogOutput("bottom",math.min(math.abs(AuxControls.pitch),15))
                redstone.setOutput("back",false)
            elseif AuxControls.pitch < 0 then
                redstone.setAnalogOutput("back",math.min(math.abs(AuxControls.pitch),15))
                redstone.setOutput("bottom",false)
            else
                redstone.setOutput("bottom",false)
                redstone.setOutput("back",false)
            end
        end
        sleep()
    end
end

local function throttleControl()
    while true do
        if AuxControls and AuxControls.throttle then
            if AuxControls.throttle > 0 then
                redstone.setAnalogOutput("front",math.abs(AuxControls.throttle))
            else
                redstone.setOutput("front",false)
            end
        end
        sleep()
    end
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == AuxControlChannel then
                AuxControls = message
            end
        else
            sleep()
        end
    end
end

parallel.waitForAny(
    modemMessage,
    manualCannonControl,
    pitchControl,
    throttleControl
)
