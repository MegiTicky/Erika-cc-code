local modem = peripheral.find("modem") or error("No modem attached", 0)

print("Input the controlChannel, default = 1100")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 1100
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel) -- Open a channel to communicate

print("Remote control started. Use WASD keys to control movement, e(up) q(down) for suspension, Space for cannon, Shift for autocannon, T for smoke grenades, Tab to switch cannon control mode.")

local controls = {
    pitchDown = false,
    pitchUp = false,
    rollLeft = false,
    rollRight = false,
    yawRight = false,
    yawLeft = false,
    rotorUp = false,
    rotorDown = false,
    fire = false,
    cannonControlMode = "manual",
    engine = "on",
    cannonUp = false,
    cannonDown = false,
    cannonLeft = false,
    cannonRight = false,
    rotorRPM = 10,
    switchToGun = false,
    switchToRocket = false,
    switchToAGM = false,
    weaponChoosen = "gun",
    lockCoordinate = false,
    lockShip = false
}

local keyMap = {
    w = "pitchDown",
    s = "pitchUp",
    a = "rollLeft",
    d = "rollRight",
    e = "yawRight",
    q = "yawLeft",
    space = "rotorUp",
    leftShift = "rotorDown",
    leftCtrl = "fire",
    tab = "switchMode",
    r = "engineOnOff",
    up = "cannonUp",
    down = "cannonDown",
    left = "cannonLeft",
    right = "cannonRight",
    p = "increaseRPM",
    o = "decreaseRPM",
    one = "switchToGun",
    two = "switchToRocket",
    three = "switchToAGM",
    c = "lockCoordinate",
    x = "lockShip"
}

-- Function to send the current controls state
local function sendControls()
    modem.transmit(controlChannel, controlChannel, controls)
end

-- Function to display control status
local function displayControls()
    term.clear()
    term.setCursorPos(1, 1)

    print("== Z-10 Remote Control ==")
    print("RPM: " .. tostring(controls.rotorRPM) .. "/15")
    print("Roll: " .. (controls.rollLeft and "LEFT" or controls.rollRight and "RIGHT" or "CENTER"))
    print("Pitch: " .. (controls.pitchUp and "UP" or controls.pitchDown and "DOWN" or "LEVEL"))
    print("Yaw: " .. (controls.yawLeft and "LEFT" or controls.yawRight and "RIGHT" or "CENTER"))
    print("Cannon Mode: " .. controls.cannonControlMode)
    print("Engine: " .. (controls.engine))
    print("Fire: " .. (controls.fire and "YES" or "NO"))
    print("chosen weapon: "..controls.weaponChoosen)
    print("Stablizer: "..(controls.cameraStablizer and "YES" or "NO"))
    print("==========================")
    print("W/S=Pitch | A/D=Roll | Q/E=Yaw | crtl=Fire")
    print("1:gun | 2:rocket | 3:missile")
end

while true do
    local event, param1 = os.pullEvent()  -- Listen for all events
    if event == "key" or event == "key_up" then
        displayControls()
        if event == "key" then
            -- Key press event
            for k, control in pairs(keyMap) do
                if param1 == keys[k] then
                    if control == "switchMode" then
                        controls.cannonControlMode = (controls.cannonControlMode == "manual") and "mouseAim" or "manual"
                    elseif control == "engineOnOff" then
                        controls.engine = (controls.engine == "on") and "off" or "on"
                    elseif control == "increaseRPM" then
                        controls.rotorRPM = math.min(controls.rotorRPM + 1, 15)
                    elseif control == "decreaseRPM" then
                        controls.rotorRPM = math.max(controls.rotorRPM - 1, 0)
                    elseif control == "switchToGun" then
                        controls.weaponChoosen = "gun"
                    elseif control == "switchToRocket" then
                        controls.weaponChoosen = "rocket"
                    elseif control == "switchToAGM" then
                        controls.weaponChoosen = "AGM-134"
                    else 
                        controls[control] = true
                    end
                    sendControls()
                end
            end
        elseif event == "key_up" then
            -- Key release event
            for k, control in pairs(keyMap) do
                if param1 == keys[k] then
                    if control ~= "switchMode" and control ~= "engineOnOff"
                       and control ~= "increaseRPM" and control ~= "decreaseRPM"
                       and control ~= "switchToGun" and control ~= "switchToRocket"
                       and control ~= "switchToAGM" then
                        controls[control] = false
                        sendControls()
                    end
                end
            end
        end
    end
end


parallel.waitForAny(keyEventListener, inactivityMonitor)