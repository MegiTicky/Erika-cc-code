local modem = peripheral.find("modem") or error("No modem attached", 0)

print("Input the controlChannel, default = 500")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 500
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel) -- Open a channel to communicate

print("Remote control started. Use WASD keys to control movement, e(up) q(down) for suspension, Space for cannon, Shift for autocannon, T for smoke grenades, Tab to switch cannon control mode.")

local controls = {
    accelerate = false,
    decelerate = false,
    turnLeft = false,
    turnRight = false,
    suspensionUp = false,
    suspensionDown = false,
    fireCannon = false,
    fireAutocannon = false,
    launchSmokeGrenade = false,
    cannonControlMode = "manual",
    cannonUp = false,
    cannonDown = false,
    cannonLeft = false,
    cannonRight = false
}

local keyMap = {
    w = "accelerate",
    s = "decelerate",
    a = "turnLeft",
    d = "turnRight",
    e = "suspensionUp",
    q = "suspensionDown",
    space = "fireCannon",
    leftShift = "fireAutocannon",
    t = "launchSmokeGrenade",
    tab = "switchMode",
    up = "cannonUp",
    down = "cannonDown",
    left = "cannonLeft",
    right = "cannonRight"
}

-- Function to send the current controls state
local function sendControls()
    modem.transmit(controlChannel, controlChannel, controls)
end

while true do
    local event, param1, param2 = os.pullEvent()
    
    if event == "key" then
        -- Key press event
        for k, control in pairs(keyMap) do
            if param1 == keys[k] then
                if control == "switchMode" then
                    -- Switch cannon control mode when Tab is pressed
                    if controls.cannonControlMode == "manual" then
                        controls.cannonControlMode = "mouseAim"
                        print("Switched to Mouse Aim mode")
                    else
                        controls.cannonControlMode = "manual"
                        print("Switched to Manual Control mode")
                    end
                else
                    controls[control] = true
                end
                sendControls()
                print("Key pressed:", k, control)
            end
        end

    elseif event == "key_up" then
        -- Key release event
        for k, control in pairs(keyMap) do
            if param1 == keys[k] then
                if control ~= "switchMode" then
                    controls[control] = false
                    sendControls()
                    print("Key released:", k, control)
                end
            end
        end
    end
end
