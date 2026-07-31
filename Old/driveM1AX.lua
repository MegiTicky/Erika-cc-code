-- drive PL-01.lua
local modem = peripheral.wrap("front")
local left = peripheral.wrap("left")
local right = peripheral.wrap("right")
local suspensionMotor = peripheral.find("electric_motor")

print("Input the controlChannel, default = 500")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 500
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

-- Function to set the speed based on current RPM and turn level
local function setSpeed()
    while true do
        local currentLeft = left.getTargetSpeed()
        local currentRight = right.getTargetSpeed()

        if turnLevel == 0 then
            if RPM ~= currentLeft then
                left.setTargetSpeed(-RPM)
            end
            if RPM ~= currentRight then
                right.setTargetSpeed(-RPM)
            end
        elseif turnLevel == 1 then
            if true then
                left.setTargetSpeed(-RPM / 1)
            end
            if true then
                right.setTargetSpeed(-RPM / 2)
            end
        elseif turnLevel == -1 then
            if true then
                left.setTargetSpeed(-RPM / 2)
            end
            if true then
                right.setTargetSpeed(-RPM / 1)
            end
        elseif turnLevel == 2 then
            if currentLeft ~= 32 then
                left.setTargetSpeed(-64)
            end
            if currentRight ~= -32 then
                right.setTargetSpeed(64)
            end
        elseif turnLevel == -2 then
            if currentLeft ~= -32 then
                left.setTargetSpeed(64)
            end
            if currentRight ~= 32 then
                right.setTargetSpeed(-64)
            end
        end

        sleep()
    end
end

local function executeControls()
    while true do
        if controls.accelerate then
            RPM = RPM + 64
            if controls.turnLeft then
                turnLevel = -1
            elseif controls.turnRight then
                turnLevel = 1
            else
                turnLevel = 0
            end
        elseif controls.decelerate then
            RPM = RPM - 64
            if controls.turnLeft then
                turnLevel = -1
            elseif controls.turnRight then
                turnLevel = 1
            else
                turnLevel = 0
            end
        else
            if controls.turnLeft then
                turnLevel = -2
            elseif controls.turnRight then
                turnLevel = 2
            else
                turnLevel = 0
            end
        end

        -- Gradually slow down if neither accelerate nor decelerate is pressed
        if not(controls.accelerate or controls.decelerate) then
            if RPM > 0 then
                RPM = RPM - 32
            elseif RPM < 0 then
                RPM = RPM + 32
            end
        end

        -- Clamp RPM to a maximum and minimum value
        if RPM > 256 then
            RPM = 256
        elseif RPM < -256 then
            RPM = -256
        end

        -- Suspension control
        if controls.suspensionUp then
            suspensionMotor.setSpeed(128)
        elseif controls.suspensionDown then
            suspensionMotor.setSpeed(-128)
        elseif not(controls.suspensionDown or controls.suspensionUp) then
            suspensionMotor.setSpeed(0)
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
    executeControls,
    setSpeed
)
