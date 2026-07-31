local modem = peripheral.find("modem") or error("No modem attached", 0)

local registeredChannels = {}

print("Input the EMBTEMBTControlChannel, default = 2000")
local EMBTControlChannel = io.read()
if EMBTControlChannel == "" then
    EMBTControlChannel = 2000
end
EMBTControlChannel = tonumber(EMBTControlChannel)
SHARDControlChannel = EMBTControlChannel + 10
droneControlChannel = EMBTControlChannel + 20
modem.open(EMBTControlChannel) -- Open a channel to communicate
modem.open(droneControlChannel)

local systems = {
    { name = "Main Turret", EMBTControlsPage = "Main Turret EMBTControls" },
    { name = "SHARD", EMBTControlsPage = "S.H.A.R.D. EMBTControls" },
    { name = "Drone", EMBTControlsPage = "Scout Drone control"}
}

local currentPage = "home"
local currentSelection = 1 -- Initially on the first system (Main Turret)

local EMBTControls = {
    accelerate = false,
    decelerate = false,
    turnLeft = false,
    turnRight = false,
    suspensionUp = false,
    suspensionDown = false,
    fireCannon = false,
    fireAutocannon = false,
    targetSwitch = false,
    fireMissile = {},
    launchSmokeGrenade = false,
    cannonControlMode = "manual",
    cannonUp = false,
    cannonDown = false,
    cannonLeft = false,
    cannonRight = false,
    shellMode = "APHE_Delayed"
}

local EMBTKeyMap = {
    w = "accelerate",
    s = "decelerate",
    a = "turnLeft",
    d = "turnRight",
    e = "suspensionUp",
    q = "suspensionDown",
    space = "fireCannon",
    r = "targetSwitch",
    f = "fireAutocannon",
    leftCtrl = "fireCOAX",
    leftShift = "fireMissile",
    t = "launchSmokeGrenade",
    tab = "switchMode",
    up = "cannonUp",
    down = "cannonDown",
    left = "cannonLeft",
    right = "cannonRight",
    one = "shellSwitch_APHE_Delayed",
    two = "shellSwitch_APHE_Proximity"
}


local SHARDControls = {
    accelerate = false,
    decelerate = false,
    turnLeft = false,
    turnRight = false,
    suspensionUp = false,
    suspensionDown = false,
    fireCannon = false,
    fireAutocannon = false,
    fireCOAX = false,
    targetSwitch = false,
    fireMissile = {},
    launchSmokeGrenade = false,
    cannonControlMode = "manual",
    cannonUp = false,
    cannonDown = false,
    cannonLeft = false,
    cannonRight = false,
}

local SHARDKeyMap = {
    w = "accelerate",
    s = "decelerate",
    a = "turnLeft",
    d = "turnRight",
    e = "suspensionUp",
    q = "suspensionDown",
    space = "fireCannon",
    leftCtrl = "fireAutocannon",
    r = "targetSwitch",
    leftShift = "fireMissile",
    t = "launchSmokeGrenade",
    tab = "switchMode",
    up = "cannonUp",
    down = "cannonDown",
    left = "cannonLeft",
    right = "cannonRight"
}

local SPAAControls = {
    accelerate = false,
    decelerate = false,
    turnLeft = false,
    turnRight = false,
    suspensionUp = false,
    suspensionDown = false,
    fireCannon = false,
    fireAutocannon = false,
    targetSwitch = false,
    fireMissile = {},
    launchSmokeGrenade = false,
    cannonControlMode = "manual",
    cannonUp = false,
    cannonDown = false,
    cannonLeft = false,
    cannonRight = false,
}

local SPAAKeyMap = {
    w = "accelerate",
    s = "decelerate",
    a = "turnLeft",
    d = "turnRight",
    e = "suspensionUp",
    q = "suspensionDown",
    space = "fireCannon",
    r = "targetSwitch",
    f = "fireAutocannon",
    leftCtrl = "fireCOAX",
    leftShift = "fireMissile",
    t = "launchSmokeGrenade",
    tab = "switchMode",
    up = "cannonUp",
    down = "cannonDown",
    left = "cannonLeft",
    right = "cannonRight"
}

local missileId = 1 -- Initial missile ID to be launched
local missileLaunched = {} -- List to store launched missile IDs

-- Function to draw the home page
local function drawHomePage()
    term.clear()
    term.setCursorPos(1, 1)
    print("Select Weapon System:")
    
    for i, system in ipairs(systems) do
        if i == currentSelection then
            -- Highlight the selected item in blue
            term.clearLine()
            term.setCursorPos(1, i + 1)
            term.setBackgroundColor(colors.blue)
        else
            term.setBackgroundColor(colors.black)
        end
        print(system.name)
        term.setBackgroundColor(colors.black)
    end
end

local function launchMissile()
    if type(EMBTControls.fireMissile) ~= "table" then
        EMBTControls.fireMissile = {}
    end

    local currentMissileId = missileId
    -- Assign a table to this missile's ID in fireMissile, marking it as launched
    EMBTControls.fireMissile[currentMissileId] = {launch = true}
    missileLaunched[currentMissileId] = true -- Mark this missile as launched
    print("Launching missile:", currentMissileId)
    
    missileId = missileId + 1 -- Increment missile ID for next launch
end

local function turretControl(event, param1)
    if event == "key" then
        for k, control in pairs(EMBTKeyMap) do
            if param1 == keys[k] then

                if control == "shellSwitch_APHE_Delayed" then
                    -- User pressed '1'
                    EMBTControls.shellMode = "APHE_Delayed"
                    print("Switched shell to APHE_Delayed")

                elseif control == "shellSwitch_APHE_Proximity" then
                    -- User pressed '2'
                    EMBTControls.shellMode = "APHE_Proximity"
                    print("Switched shell to APHE_Proximity")

                elseif control == "switchMode" then
                    -- (existing tab logic)
                    if EMBTControls.cannonControlMode == "manual" then
                        EMBTControls.cannonControlMode = "mouseAim"
                        print("Switched to Mouse Aim mode")
                    else
                        EMBTControls.cannonControlMode = "manual"
                        print("Switched to Manual Control mode")
                    end

                elseif control == "fireMissile" then
                    -- (existing logic)
                    launchMissile()

                else
                    -- (existing logic)
                    EMBTControls[control] = true
                end

                -- Transmit updated controls state after handling key press
                modem.transmit(EMBTControlChannel, EMBTControlChannel, EMBTControls)
                print("Key pressed:", k, control)
            end
        end

    elseif event == "key_up" then
        for k, control in pairs(EMBTKeyMap) do
            if param1 == keys[k] then
                -- (existing release logic)
                if control ~= "switchMode" 
                   and control ~= "shellSwitch_APHE_Delayed" 
                   and control ~= "shellSwitch_APHE_Proximity" then
                   
                    EMBTControls[control] = false
                    modem.transmit(EMBTControlChannel, EMBTControlChannel, EMBTControls)
                    print("Key released:", k, control)
                end
            end
        end
    end
end

local function SHARDControl(event,param1)
    if event == "key" then
        -- Key press event
        for k, control in pairs(SHARDKeyMap) do
            if param1 == keys[k] then
                if control == "switchMode" then
                    -- Switch cannon control mode when Tab is pressed
                    if SHARDControls.cannonControlMode == "manual" then
                        SHARDControls.cannonControlMode = "mouseAim"
                        print("Switched to Mouse Aim mode")
                    else
                        SHARDControls.cannonControlMode = "manual"
                        print("Switched to Manual Control mode")
                    end
                else
                    SHARDControls[control] = true
                end
                modem.transmit(SHARDControlChannel, SHARDControlChannel, SHARDControls)
                print("Key pressed:", k, control)
            end
        end

    elseif event == "key_up" then
        -- Key release event
        for k, control in pairs(SHARDKeyMap) do
            if param1 == keys[k] then
                if control ~= "switchMode" then
                    SHARDControls[control] = false
                    modem.transmit(SHARDControlChannel, SHARDControlChannel, SHARDControls)
                    print("Key released:", k, control)
                end
            end
        end
    end
end

local droneControls = {
    forward = false,
    backward = false,
    strafeLeft = false,
    strafeRight = false,
    turnLeft = false,
    turnRight = false,
    goUp = false,
    goDown = false,
    designate = false
}

local droneKeyMap = {
    w = "forward",
    s = "backward",
    q = "strafeLeft",
    e = "strafeRight",
    a = "turnLeft",
    d = "turnRight",
    leftShift = "goUp",
    leftCtrl = "goDown",
    space = "designate",
}

local function droneControl(event, param1)
    if event == "key" then
        for k, control in pairs(droneKeyMap) do
            if param1 == keys[k] then
                -- Transmit updated controls state after handling key press
                droneControls[control] = true
                modem.transmit(droneControlChannel, droneControlChannel, droneControls)
                print("Key pressed:", k, control)
            end
        end

    elseif event == "key_up" then
        for k, control in pairs(droneKeyMap) do
            if param1 == keys[k] then
                -- (existing release logic)
                if control ~= "switchMode" 
                   and control ~= "shellSwitch_APHE_Delayed" 
                   and control ~= "shellSwitch_APHE_Proximity" then
                   
                    droneControls[control] = false
                    modem.transmit(droneControlChannel, droneControlChannel, droneControls)
                    print("Key released:", k, control)
                end
            end
        end
    end
end

-- Function to draw the EMBTControls page
local function drawEMBTControlsPage(event,key)
    term.setCursorPos(1, 1)
    print(systems[currentSelection].EMBTControlsPage)
    print("Press Backspace to return")

    if event == "key" then
        if key == keys.backspace then
            currentPage = "home"
            drawHomePage()
        end
    end

    if systems[currentSelection].name == "Main Turret" then
        -- Mouse Aim Mode Indicator with color
        if EMBTControls.cannonControlMode == "mouseAim" then
            term.setCursorPos(1, 3)
            term.setBackgroundColor(colors.green)  -- Green for ON
            term.clearLine()  -- Clear line to ensure the color is applied only for the current line
            print("Mouse Aim Mode: ON")
            term.setBackgroundColor(colors.black)
        else
            term.setCursorPos(1, 3)
            term.setBackgroundColor(colors.red)  -- Red for OFF
            term.clearLine()  -- Clear line to ensure the color is applied only for the current line
            print("Mouse Aim Mode: OFF")
            term.setBackgroundColor(colors.black)
        end
        term.setCursorPos(1,4)
        term.clearLine()
        print("Shell: "..EMBTControls.shellMode)
        turretControl(event,key)
    elseif systems[currentSelection].name == "SHARD" then
        -- SHARD system EMBTControls here
        if SHARDControls.cannonControlMode == "mouseAim" then
            term.setCursorPos(1, 3)
            term.setBackgroundColor(colors.green)  -- Green for ON
            term.clearLine()  -- Clear line to ensure the color is applied only for the current line
            print("Auto lock Mode: ON")
            term.setBackgroundColor(colors.black)
        else
            term.setCursorPos(1, 3)
            term.setBackgroundColor(colors.red)  -- Red for OFF
            term.clearLine()  -- Clear line to ensure the color is applied only for the current line
            print("Auto lock Mode: OFF")
            term.setBackgroundColor(colors.black)
        end
        SHARDControl(event,key)
    elseif systems[currentSelection].name =="Drone" then
        droneControl(event,key)
    end
end

-- Function to navigate through systems
local function navigateSystems(key)
    if key == keys.up then
        currentSelection = currentSelection - 1
        if currentSelection < 1 then
            currentSelection = #systems
        end
    elseif key == keys.down then
        currentSelection = currentSelection + 1
        if currentSelection > #systems then
            currentSelection = 1
        end
    end
end

local function handleHomePageKey(event, key)
    if event == "key" then
        if key == keys.enter then
            currentPage = systems[currentSelection].EMBTControlsPage
            drawEMBTControlsPage()
        elseif key == keys.up or key == keys.down then
            navigateSystems(key)
            drawHomePage()
        end
    end
end

while true do
    if currentPage == "home" then
        drawHomePage()
        local event, key = os.pullEvent()
        if event == "key" and key then
            handleHomePageKey(event, key)
        end
    elseif currentPage == systems[currentSelection].EMBTControlsPage then
        local event, key = os.pullEvent()
        drawEMBTControlsPage(event, key)
    end
end