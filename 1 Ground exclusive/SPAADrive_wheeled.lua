-- drive Bradley.lua
local modem = peripheral.find("modem")
local engine = peripheral.find("Create_RotationSpeedController")

print("Input the controlChannel, default = 2100")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 2100
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel)

local RPM = 0
local turnLevel = 0

-- Redstone sides for cannon and autocannon
local cannonSide = "top"
local autocannonSide = "bottom"

print("Tank controller started.")

local controls = {
    accelerate = false,
    decelerate = false,
    turnLeft = false,
    turnRight = false,
    suspensionUp = false,
    suspensionDown = false,
    fireCannon = false,
    fireAutocannon = false
}

local function executeControls()
    while true do
        if controls.turnLeft then
            redstone.setOutput("left",true)
            redstone.setOutput("right",false)
        elseif controls.turnRight then
            redstone.setOutput("left",false)
            redstone.setOutput("right",true)
        else
            redstone.setOutput("left",false)
            redstone.setOutput("right",false)
        end

        if controls.accelerate then
            RPM = 256
        elseif controls.decelerate then
            RPM = -256
        else
            RPM = 0
        end

        -- Fire controls
        if controls.fireCannon then
            print("Firing Cannon")
            redstone.setOutput("bottom", true)
        else
            redstone.setOutput("bottom", false)
        end

        if controls.fireAutocannon then
            print("Firing Autocannon")
            redstone.setOutput("front", true)
        else
            redstone.setOutput("front", false)
        end
        engine.setTargetSpeed(RPM)
        sleep() -- Adjust the delay for control responsiveness
    end
end

-- Function to listen for modem messages and update controls
local function modem_message()
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if channel == controlChannel then
            controls = message
        end
    end
end

-- Run the functions in parallel
parallel.waitForAll(
    modem_message,
    executeControls
)
