local modem = peripheral.wrap("bottom")
local engine = peripheral.find("Create_RotationSpeedController")
local routerLeft = peripheral.wrap("left")
local routerRight = peripheral.wrap("right")
local gear = peripheral.find("Create_SequencedGearshift")

local throttleChannel = 400
local rudderChannel = 401
local elevatorChannel = 402
local aileronChannel = 403
local landingGearChannel = 404
local flapChannel = 405

modem.open(throttleChannel)
modem.open(rudderChannel)
modem.open(elevatorChannel)
modem.open(aileronChannel)
modem.open(landingGearChannel)
modem.open(flapChannel)


local engineSpeed = 0
local rudderControl = "stop"
local aileronControl = 0
local elevatorControl = 0
local currentGear = "down"
local targetGear = "down"
local flap = 0

local function listenForCoordinates()
    while true do
        local event, side, senderChannel, replyChannel, message, senderDistance = os.pullEvent("modem_message")
        if senderChannel == throttleChannel then
            engineSpeed = message
        elseif senderChannel == rudderChannel then
            rudderControl = message
        elseif senderChannel == elevatorChannel then
            elevatorControl = message
        elseif senderChannel == aileronChannel then
            aileronControl = message
        elseif senderChannel == landingGearChannel then
            targetGear = message
        elseif senderChannel == flapChannel then
            flap = message
        end
    end
end

routerLeft.setOutput("left", false)
routerLeft.setOutput("top", false)
routerLeft.setOutput("back", false)
routerLeft.setOutput("bottom", false)
routerRight.setOutput("left", false)
routerRight.setOutput("top", false)
routerRight.setOutput("back", false)
routerRight.setOutput("bottom", false)

parallel.waitForAny(
    listenForCoordinates,
    function()
        while true do
            -- Engine control
            print("throttle: " .. engineSpeed)
            print("rudderControl: " .. rudderControl)
            print("elevatorControl: " .. elevatorControl)
            print("aileronControl: " .. aileronControl)
            print("Current Gear: "..currentGear)
            print("Target Gear: "..targetGear)
            print("Flap: "..flap)
            engine.setTargetSpeed(engineSpeed)
            if engineSpeed < -128 then
                redstone.setOutput("back",true)
            else
                redstone.setOutput("back",false)
            end
            --[[mouse and keyboard
            if aileronControl == "left" then
                print("rolling left")
                routerLeft.setOutput("front", true)
                routerRight.setOutput("front", false)
            elseif aileronControl == "right" then
                print("rolling right")
                routerRight.setOutput("front", true)
                routerLeft.setOutput("front", false)
            else
                routerRight.setOutput("front", false)
                routerLeft.setOutput("front", false)
            end

            -- Rudder control (yaw)
            if rudderControl == "left" then
                print("yaw turning left")
                routerLeft.setOutput("top", true)
                routerRight.setOutput("top", false)
            elseif rudderControl == "right" then
                print("yaw turning right")
                routerRight.setOutput("top", true)
                routerLeft.setOutput("top", false)
            else
                routerRight.setOutput("top", false)
                routerLeft.setOutput("top", false)
            end

            -- Elevator control (pitch)
            if elevatorControl == "up" then
                print("pitching up")
                redstone.setOutput("top", true)
                redstone.setOutput("front",false)
            elseif elevatorControl == "down" then
                print("pitching down")
                redstone.setOutput("top", false)
                redstone.setOutput("front",true)
            else
                redstone.setOutput("top", false)
                redstone.setOutput("front",false)
            end]]
            if aileronControl < 0 then
                routerRight.setAnalogOutput("front",math.abs(aileronControl))
                routerLeft.setOutput("front",false)
            elseif aileronControl > 0 then
                routerLeft.setAnalogOutput("front",math.abs(aileronControl))
                routerRight.setOutput("front",false)
            else
                routerLeft.setOutput("front",false)
                routerRight.setOutput("front",false)
            end

            if rudderControl == "left" then
                print("yaw turning left")
                routerLeft.setOutput("top", true)
                routerRight.setOutput("top", false)
            elseif rudderControl == "right" then
                print("yaw turning right")
                routerRight.setOutput("top", true)
                routerLeft.setOutput("top", false)
            else
                routerRight.setOutput("top", false)
                routerLeft.setOutput("top", false)
            end

            if elevatorControl > 0 then
                print("pitching up")
                redstone.setAnalogOutput("top", math.abs(elevatorControl))
                redstone.setOutput("front",false)
            elseif elevatorControl < 0 then
                print("pitching down")
                redstone.setOutput("top", false)
                redstone.setAnalogOutput("front",math.abs(elevatorControl))
            else
                redstone.setOutput("top", false)
                redstone.setOutput("front",false)
            end
            
            if not(currentGear == targetGear) then
                routerRight.setOutput("bottom",true)
                sleep(0.1)
                routerRight.setOutput("bottom",false)
                if currentGear == "down" then
                    currentGear = "up"
                elseif currentGear == "up" then
                    currentGear = "down"
                end
            end

            routerLeft.setAnalogOutput("back",flap)

            sleep(0.2)
        end
    end
)