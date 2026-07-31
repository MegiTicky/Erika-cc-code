local left = peripheral.wrap("left")
local right = peripheral.wrap("right")
local monitor = peripheral.find("monitor")
local controller = peripheral.find("tweaked_controller")
local router = peripheral.find("redrouter")



local function round(num)
    return math.floor(num * 100 + 0.5) / 100
end

local leftSpeed = 0
local rightSpeed = 0
local turn = 0
local debounceTime = 0.2 -- debounce time in seconds
local lastToggleTime = 0 -- last time the button was toggled

redstone.setOutput("front", true)
router.setOutput("left", true)
redstone.setOutput("bottom",true)
local function handleController()
    while true do
        local yAxis = controller.getAxis(2)
        local xAxis = controller.getAxis(1)

        if yAxis < 0 then
            if leftSpeed < 0 or rightSpeed < 0 then
                leftSpeed = leftSpeed + 32
                rightSpeed = rightSpeed + 32
            else
                leftSpeed = leftSpeed + 8
                rightSpeed = rightSpeed + 8
            end
        elseif yAxis > 0 then
            if leftSpeed > 0 or rightSpeed > 0 then
                leftSpeed = leftSpeed - 32
                rightSpeed = rightSpeed - 32
            else
                leftSpeed = leftSpeed -8
                rightSpeed = rightSpeed -8
            end
        else
            if leftSpeed > 0 and rightSpeed > 0 then
                leftSpeed = leftSpeed - 8
                rightSpeed = rightSpeed - 8
            elseif leftSpeed < 0 and rightSpeed < 0 then
                leftSpeed = leftSpeed + 8
                rightSpeed = rightSpeed + 8
            end
            if math.abs(leftSpeed) < 16 then
                leftSpeed = 0
                rightSpeed = 0
            end
        end

        if leftSpeed > 256 then
            leftSpeed = 256
        elseif leftSpeed < -256 then
            leftSpeed = -256
        end
        if rightSpeed > 256 then
            rightSpeed = 256
        elseif rightSpeed < -256 then
            rightSpeed = -256
        end

        if xAxis > 0 then
            turn = 1
        elseif xAxis < 0 then
            turn = -1
        else
            turn = 0
        end

        if xAxis > 0 and math.abs(leftSpeed) < 64 and math.abs(rightSpeed) < 64 then
            turn = 2
        elseif xAxis < 0 and math.abs(leftSpeed) < 64 and math.abs(rightSpeed) < 64 then
            turn = -2
        end

        if controller.getButton(7) then
            monitor.setCursorPos(1,5)
            monitor.write("Smoke")
            redstone.setOutput("bottom",false)
            sleep(0.2)
        else
            redstone.setOutput("bottom",true)
        end

        -- Debounce mechanism for button 8
        if controller.getButton(8) then
            local currentTime = os.clock()
            if currentTime - lastToggleTime > debounceTime then
                if router.getOutput("bottom") then
                    router.setOutput("bottom", false)
                else
                    router.setOutput("bottom", true)
                end
                lastToggleTime = currentTime
            end
        end

        sleep(0.05)
    end
end

local function setSpeed()
    while true do
        local currentLeft = left.getTargetSpeed()
        local currentRight = right.getTargetSpeed()

        if turn == 0 then
            if leftSpeed ~= currentLeft then
                left.setTargetSpeed(leftSpeed)
            end
            if rightSpeed ~= currentRight then
                right.setTargetSpeed(rightSpeed)
            end
        elseif turn == 1 then
            if true then
                left.setTargetSpeed(leftSpeed / 1)
            end
            if true then
                right.setTargetSpeed(rightSpeed / 2)
            end
        elseif turn == -1 then
            if true then
                left.setTargetSpeed(leftSpeed / 2)
            end
            if true then
                right.setTargetSpeed(rightSpeed / 1)
            end
        elseif turn == 2 then
            if currentLeft ~= 32 then
                left.setTargetSpeed(64)
            end
            if currentRight ~= -32 then
                right.setTargetSpeed(-64)
            end
        elseif turn == -2 then
            if currentLeft ~= -32 then
                left.setTargetSpeed(-64)
            end
            if currentRight ~= 32 then
                right.setTargetSpeed(64)
            end
        end

        sleep(0.05)
    end
end

local prevSpeed = 0
local prevEnergy = 0
local prevLeftSpeed = 0
local prevRightSpeed = 0

local function updateMonitor()
    while true do
        local velocity = ship.getVelocity()
        local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2) * 3.6
        local currentLeft = left.getTargetSpeed()
        local currentRight = right.getTargetSpeed()
        local suspension = router.getOutput("bottom") and "Up" or "Down"
        if monitor then
            if speed ~= prevSpeed or currentLeft ~= prevLeftSpeed or currentRight ~= prevRightSpeed then
                monitor.setTextScale(0.5)
                monitor.clear()
                monitor.setCursorPos(1, 1)
                monitor.write("Speed:" .. round(speed) .. "km/h")
                monitor.setCursorPos(1, 2)
                monitor.write("Left RPM: " .. round(currentLeft))
                monitor.setCursorPos(1, 3)
                monitor.write("Right RPM: " .. round(currentRight))
                monitor.setCursorPos(1, 4)
                monitor.write("Suspension:" .. suspension)

                prevSpeed = speed
                prevEnergy = energy
                prevLeftSpeed = currentLeft
                prevRightSpeed = currentRight
            end
        end

        print("Speed:" .. speed .. "km/h")
        print("Left RPM: " .. round(currentLeft))
        print("Right RPM: " .. round(currentRight))
        print("set left rpm: " .. leftSpeed)
        print("set right rpm: " .. rightSpeed)
        print(turn)

        sleep(0.05)
    end
end

parallel.waitForAny(handleController, updateMonitor, setSpeed)