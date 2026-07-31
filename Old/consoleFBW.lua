local modem = peripheral.wrap("left")
local monitor = peripheral.find("monitor")
local controller = peripheral.find("tweaked_controller")
local arController = peripheral.find("arController")

local throttleChannel = 400
local rudderChannel = 401
local elevatorChannel = 402
local aileronChannel = 403
local landingGearChannel = 404
local flapChannel = 405
local startX,startY,endX,endY = 50,2,100,70
if modem then
    modem.open(throttleChannel)
    modem.open(rudderChannel)
    modem.open(elevatorChannel)
    modem.open(aileronChannel)
    modem.open(landingGearChannel)
    modem.open(flapChannel)
end

local throttle = 0
local speed = 0
local landingGear = "down" -- Correctly initialize landingGear as a string
local flap = 0
local pos = { x = 0, y = 0, z = 0 }
local rudderControl = " "
local aileronControl = "0"
local elevatorControl = "0"
print("Input roll and pitch mode 1/2: ")
local mode = tonumber(io.read())

local debounceTime = 0.2 -- debounce time in seconds
local lastToggleTime = 0 -- last time the landing gear button was toggled
local lastFlapTime = 0 -- last time the flap button was toggled

local prevDisplayText = {}
arController.clear()
arController.setRelativeMode(true, 1920, 1080)


local function round(num)
    return math.floor(num * 100 + 0.5) / 100
end
local function toDegrees(radians)
    return radians * (180 / math.pi)
end
local function handleController()
    while true do
        if controller then
            controller.setFullPrecision(true)
            local yAxis = controller.getAxis(2)
            local xAxis = controller.getAxis(1)

            throttle = -controller.getAxis(2) * 256

            if throttle > 256 then
                throttle = 256
            elseif throttle < -128 then
                throttle = -128
            end

            if xAxis > 0.5 then
                rudderControl = "left"
            elseif xAxis < -0.5 then
                rudderControl = "right"
            else
                rudderControl = "stop"
            end

            if controller.getAxis(4) > 0.2 then
                elevatorControl = -math.floor(controller.getAxis(4) * 15)
            elseif controller.getAxis(4) < -0.2 then
                elevatorControl = -math.floor(controller.getAxis(4) * 15)
            else
                elevatorControl = 0
            end

            if controller.getAxis(3) > 0.2 then
                aileronControl = -math.floor(controller.getAxis(3) * 15)
            elseif controller.getAxis(3) < -0.2 then
                aileronControl = -math.floor(controller.getAxis(3) * 15)
            else
                aileronControl = 0
            end

            -- Debounce mechanism for button 7 (landing gear)
            if controller.getButton(3) then
                local currentTime = os.clock()
                if currentTime - lastToggleTime > debounceTime then
                    if landingGear == "up" then
                        landingGear = "down"
                    else
                        landingGear = "up"
                    end
                    lastToggleTime = currentTime
                end
            end

            -- Debounce mechanism for flap control buttons
            local currentTime = os.clock()
            if controller.getButton(1) and currentTime - lastFlapTime > debounceTime then
                flap = flap - 1
                if flap < 0 then
                    flap = 0
                end
                lastFlapTime = currentTime
            elseif controller.getButton(2) and currentTime - lastFlapTime > debounceTime then
                flap = flap + 1
                if flap > 15 then
                    flap = 15
                end
                lastFlapTime = currentTime
            end
        end
        sleep(0.05)
    end
end

local function setSpeed()
    while true do
        if modem then
            modem.transmit(throttleChannel, 0, -throttle)
            modem.transmit(rudderChannel, 0, rudderControl)
            modem.transmit(elevatorChannel, 0, elevatorControl)
            modem.transmit(aileronChannel, 0, aileronControl)
            modem.transmit(landingGearChannel, 0, landingGear) -- Transmit landing gear state
            modem.transmit(flapChannel, 0, flap)
        end
        sleep(0.05)
    end
end

local function clearLine(monitor, x, y, length)
    if monitor then
        monitor.setCursorPos(x, y)
        monitor.write(string.rep(" ", length))
    end
end

local function updateDisplay()
    local velocity = { x = 0, y = 0, z = 0 }
    if ship then
        velocity = ship.getVelocity()
        pos = ship.getWorldspacePosition()
        pitch = toDegrees(ship.getRoll())
        roll = toDegrees(ship.getPitch())
    end
    speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2) * 1.9438452
    local booster = " "
    if throttle > 128 then
        booster = "Jet Engaged"
    end
    local displayText = {
        "Speed: " .. math.floor(speed) .. " knots",
        "Altitude: " .. math.floor(pos.y) .. " blocks",
        "Throttle: " .. throttle .. " RPM "..booster,
        "Rudder: " .. rudderControl,
        "Elevator: " .. elevatorControl,
        "Aileron: " .. aileronControl,
        "L Gear: " .. landingGear,
        "Pitch: "..pitch,
        "Roll: "..roll,
        flap == 0 and "Flap: off" or flap == 15 and "Flap: full" or "Flap: " .. flap
    }


    if arController then
        for i, line in ipairs(displayText) do
            if prevDisplayText[i] ~= line then
                arController.clearElement(tostring(i))
                arController.drawStringWithId(tostring(i), line, 1, i * 10 + 60, 0xFFFFFF)
            end
        end
    end
    
    local pitch, roll = 0, 0

    prevDisplayText = displayText
end

local function updateMonitor()
    while true do
        updateDisplay()
        sleep(0.01)
    end
end

arController.fill(startX,startY,endX,endY,0x000000)
local midY = startY + math.floor(endY - startY / 2)
local adjacent = (endY - startY) / 2
-- ... (previous code remains the same)

-- ... (previous code remains the same)

local function altitudeIndicatorQuarter(startX, endX, startY, endY, midX, midY, adjacent, pitch, roll)
    local slope = math.tan(roll)

    for x = startX, endX, 4 do
        arController.clearElement("horizon"..x)
        
        -- Calculate the y-coordinate of the horizon line based on the slope and pitch
        local lineY = midY - (x - midX) * slope + adjacent * math.tan(pitch)
        
        arController.drawStringWithId("horizon"..x, ".", x, lineY, 0xFFFFFF)
    end
end

local function altitudeIndicator()
    while true do
        local pitch, roll = 0, 0
        if ship then
            if mode == 1 then
                pitch = - toDegrees(ship.getRoll())
                roll = toDegrees(ship.getPitch())
                yaw = toDegrees(ship.getYaw()) - 90
                if yaw < 0 then yaw = yaw + 360 end
                print("mode1")
            else
                pitch = toDegrees(ship.getPitch())
                roll = toDegrees(ship.getRoll())
                yaw = toDegrees(ship.getYaw()) - 90
                if yaw < 0 then yaw = yaw + 360 end
                print("mode2")
            end
        end

        local width, height = endX - startX + 1, endY - startY
        local midY = startY + math.floor(height / 2)
        local midX = (startX + endX) / 2 

        -- Clear previous elements
        arController.clearElement("sky")
        arController.clearElement("ground")

        pitch = math.rad(pitch)
        roll = - math.rad(roll)

        -- Generate the horizon line from four quarters simultaneously
        local quarterWidth = math.floor((endX - startX + 1) / 4)
        parallel.waitForAll(
            function()
                altitudeIndicatorQuarter(startX, startX + quarterWidth, startY, endY, midX, midY, adjacent, pitch, roll)
            end,
            function()
                altitudeIndicatorQuarter(startX + quarterWidth, startX + 2 * quarterWidth, startY, endY, midX, midY, adjacent, pitch, roll)
            end,
            function()
                altitudeIndicatorQuarter(startX + 2 * quarterWidth, startX + 3 * quarterWidth, startY, endY, midX, midY, adjacent, pitch, roll)
            end,
            function()
                altitudeIndicatorQuarter(startX + 3 * quarterWidth, endX, startY, endY, midX, midY, adjacent, pitch, roll)
            end
        )

        arController.clearElement("hLine")
        arController.clearElement("vLine")
        if mode == 1 then
            pitchStr = tostring(math.floor(- toDegrees(ship.getRoll())))
        else
            pitchStr = tostring(math.floor( toDegrees(ship.getPitch())))
        end
        local pitchStrWidth = string.len(pitchStr)
        local lineLength = 10
        local spacing = 2

        -- Clear previous elements
        arController.clearElement("hLineLeft")
        arController.clearElement("hLineRight")
        arController.clearElement("pitchValue")
        arController.clearElement("yaw")

        -- Draw horizontal lines on both sides
        arController.horizontalLineWithId("hLineLeft", midX - lineLength - spacing - pitchStrWidth - 2, midX - spacing - pitchStrWidth - 2, midY + 5, 0xFFFFFF)
        arController.horizontalLineWithId("hLineRight", midX + spacing + pitchStrWidth, midX + lineLength + spacing + pitchStrWidth, midY + 5, 0xFFFFFF)

        -- Draw the pitch value in the middle
        arController.drawCenteredStringWithId("pitchValue", pitchStr, midX, midY + 1, 0xFFFFFF)

        arController.verticalLineWithId("vLine", midX - 1, startY + 10, midY - 5, 0xFFFFFF)
        if mode == 1 then
            arController.drawCenteredStringWithId("roll", tostring(math.floor(math.abs(toDegrees(ship.getPitch())))),midX, startY + 1, 0xFFFFFF)
        else
            arController.drawCenteredStringWithId("roll", tostring(math.floor(math.abs(toDegrees(ship.getRoll())))),midX, startY + 1, 0xFFFFFF)
        end
        arController.drawCenteredStringWithId("yaw", tostring(math.floor(yaw)), midX, endY + 1, 0xFFFFFF)

        sleep(0.001)  -- Adjust the update frequency as needed
    end
end

-- ... (remaining code remains the same)

parallel.waitForAny(handleController, updateMonitor, setSpeed, altitudeIndicator)



--[[ Mouse and keyboard
        if yAxis < 0 then
            throttle = throttle + 8
        elseif yAxis > 0 then
            throttle = throttle - 8
        end

        if throttle > 256 then
            throttle = 256
        elseif throttle < -128 then
            throttle = -128
        end

        if xAxis > 0 then
            rudderControl = "right"
        elseif xAxis < 0 then
            rudderControl = "left"
        else
            rudderControl = "stop"
        end

        if controller.getButton(12) then
            elevatorControl = "down"
        elseif controller.getButton(14) then
            elevatorControl = "up"
        else
            elevatorControl = "stop"
        end

        if controller.getButton(13) then
            aileronControl = "right"
        elseif controller.getButton(15) then
            aileronControl = "left"
        else
            aileronControl = "stop"
        end]]