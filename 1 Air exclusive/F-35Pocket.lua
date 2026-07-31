local modem = peripheral.find("modem") or error("No modem attached", 0)

print("Input the controlChannel, default = 1420")
local controlChannel = io.read()
if controlChannel == "" then
    controlChannel = 1420
end
controlChannel = tonumber(controlChannel)
modem.open(controlChannel) -- Open a channel to communicate

local controls = {
    pitchDown = false,
    pitchUp = false,
    rollLeft = false,
    rollRight = false,
    yawRight = false,
    yawLeft = false,
    autoPilot = false,
    throttle = 0,
    fire = false,
    cannonControlMode = "manual",
    hoverMode = false,
    cannonUp = false,
    cannonDown = false,
    cannonLeft = false,
    cannonRight = false,
    switchToAIM220 = false,
    switchToGBU = false,
    switchToThunderbolt = false,
    switchToAIM9 = false,
    switchToGun = false
}

local keyMap = {
    w = "pitchDown",
    s = "pitchUp",
    a = "rollLeft",
    d = "rollRight",
    e = "yawRight",
    q = "yawLeft",
    p = "autoPilot",
    space = "fire",
    capsLock = "hoverModeSwitch",
    leftShift = "throttleUp",
    leftCtrl = "throttleDown",
    tab = "switchMode",
    up = "cannonUp",
    down = "cannonDown",
    left = "cannonLeft",
    right = "cannonRight",
    one = "switchToAIM220",
    two = "switchToGBU",
    three = "switchToThunderbolt",
    four = "switchToAIM9",
    five = "switchToGun"
}

local lastInputTime = os.clock() -- Tracks last input time
local timeoutDuration = 9999999 -- 9999999 seconds timeout
local weaponChoosen = "AIM-220"

-- Function to send the current controls state
local function sendControls()
    modem.transmit(controlChannel, controlChannel, controls)
end

-- Function to display control status
local function displayControls()
    term.clear()
    term.setCursorPos(1, 1)

    print("== F-35 Remote Control ==")
    print("Throttle: " .. tostring(controls.throttle) .. "/15")
    print("Roll: " .. (controls.rollLeft and "LEFT" or controls.rollRight and "RIGHT" or "CENTER"))
    print("Pitch: " .. (controls.pitchUp and "UP" or controls.pitchDown and "DOWN" or "LEVEL"))
    print("Yaw: " .. (controls.yawLeft and "LEFT" or controls.yawRight and "RIGHT" or "CENTER"))
    print("Cannon Mode: " .. controls.cannonControlMode)
    print("VTOL Mode: " .. (controls.hoverMode and "ON" or "OFF"))
    print("AutoPilot: "..(controls.autoPilot and "ON" or "OFF"))
    print("Fire: " .. (controls.fire and "YES" or "NO"))
    print("chosen weapon: "..weaponChoosen)
    print("==========================")
    print("W/S=Pitch | A/D=Roll | Q/E=Yaw | Space=Fire")
    print("Shift=Throttle+ | Ctrl=Throttle- | Tab=Cannon Mode")
    print("Caps = Toggle VTOL")
    print("1:AIM220 | 2:GBU | 3:TB | 4:AIM9 | 5:Gun")
end

-- Function to handle key input
local function keyEventListener()
    while true do
        displayControls()
        local event, param1, param2 = os.pullEvent()

        if event == "key" then
            lastInputTime = os.clock() -- Update last input time

            for k, control in pairs(keyMap) do
                if param1 == keys[k] then
                    if control == "switchMode" then
                        controls.cannonControlMode = (controls.cannonControlMode == "manual") and "mouseAim" or "manual"
                    elseif control == "hoverModeSwitch" then
                        controls.hoverMode = not controls.hoverMode
                    elseif control == "throttleUp" then
                        controls.throttle = math.min(controls.throttle + 1, 15)
                    elseif control == "throttleDown" then
                        controls.throttle = math.max(controls.throttle - 1, 0)
                    elseif control == "autoPilot" then
                        controls.autoPilot = not controls.autoPilot
                    else
                        controls[control] = true
                    end
                    sendControls()
                end
            end
        elseif event == "key_up" then
            for k, control in pairs(keyMap) do
                if param1 == keys[k] then
                    if control ~= "switchMode" and control ~= "hoverModeSwitch" and control ~= "autoPilot" then
                        controls[control] = false
                        sendControls()
                    end
                end
            end
        end
        if controls.switchToAIM220 then
            weaponChoosen = "AIM-220"
        elseif controls.switchToGBU then
            weaponChoosen = "GBU-42"
        elseif controls.switchToThunderbolt then
            weaponChoosen = "Thunderbolt"
        elseif controls.switchToAIM9 then
            weaponChoosen = "AIM-9"
        elseif controls.switchToGun then
            weaponChoosen = "Gun"
        end
    end
end

-- Function to monitor inactivity and reset throttle
local function inactivityMonitor()
    while true do
        sleep(1) -- Check every second

        if os.clock() - lastInputTime > timeoutDuration then
            if controls.throttle > 0 then
                print("\n[Warning] No input detected for " .. timeoutDuration .. "s. Resetting throttle to 0!")
                controls.throttle = 0
                sendControls()
            end
        end
    end
end

-- Run both event listener and inactivity monitor in parallel
parallel.waitForAny(keyEventListener, inactivityMonitor)
