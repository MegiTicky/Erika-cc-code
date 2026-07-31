local router1ID="redrouter_0"
local router2ID="redrouter_1"
local counter = 0

router1 = peripheral.find(router1ID)
router2 = peripheral.find(router2ID)

print("Connect router1 and press enter")
io.read()
router1 = peripheral.find("redrouter")
if not router1 then
    error("no router 1")
end
print("Disconnect router1 and connect router 2 and press enter")
io.read()
router2 = peripheral.find("redrouter")
if not router2 then
    error("no router2")
end

print("Connect router1 and router 2 and press enter")
io.read()

if not router1 then
    error("no router 1")
end
if not router2 then
    error("no router2")
end

router1.setOutput("top",false)
router1.setOutput("left",false)
router1.setOutput("front",false)
router2.setOutput("top",false)
router2.setOutput("front",false)
router2.setOutput("left",false)
while true do
    if redstone.getAnalogInput("bottom")==15 then
        redstone.setOutput("top",false)
        redstone.setOutput("left",false)
        redstone.setOutput("right",false)
        redstone.setOutput("front",false)
        router1.setOutput("top",false)
        router1.setOutput("left",false)
        router1.setOutput("front",false)
        router2.setOutput("top",false)
        router2.setOutput("front",false)
        router2.setOutput("left",false)
    end
    if redstone.getAnalogInput("front")==15 then
        
--mianhub   
            redstone.setOutput("top", false)
            print("Removing screw")
            sleep(0.2)
            router1.setOutput("back", true)
            sleep(0.2)
            router1.setOutput("back", false)
            --[[repeat
                sleep(0.01)
                counter = counter + 1
                if counter > 500 then
                    print("fail to remove screw, manually override required")
                    io.read()
                    counter = 0
                end
            until not(redstone.getInput("left"))]]
            counter = 0
            print("Screw removed")
            sleep(0.2)

--[[unloader
            router1.setOutput("left", true)
            sleep(0.2)
            router1.setOutput("left", false)
            sleep(0.5)
            router1.setOutput("front", true)
            sleep(0.5)
            router1.setOutput("front", false)
            print("removing empty cartridge")
            repeat
                sleep(0.01)
                counter = counter + 1
                if counter > 500 then
                    print("fail to remove empty cratrige, manually override required, enter -1 if it is normal")
                    read = io.read()
                    counter = 0

                end
            until (redstone.getInput("left") or read == "-1")
            counter = 0

            router1.setOutput("top", true)
            sleep(1)
            router1.setOutput("top", false)
            sleep(0.2)
            print("cannon unloaded")]]

--placing magazine
            router2.setOutput("left",true)
            router2.setOutput("front", true)
            sleep(0.2)
            router2.setOutput("front", false)
            router2.setOutput("left",false)
            print("waiting for magazine")
            sleep(0.4)
            --[[repeat
                sleep(0.01)
                counter = counter + 1
                if counter > 500 then
                    print("Magazine not detected, manually override required")
                    io.read()
                    counter = 0
                end
            until redstone.getInput("left")]]
            counter = 0
--loading step 1
            sleep(0.5)
            router1.setOutput("front", true)
            sleep(0.4)
            router1.setOutput("front", false)
            --[[repeat
                sleep(0.01)
                counter = counter + 0.01
                if counter > 10 then
                    print("Jammed, manually override required")
                    io.read()
                    counter = 0
                end
            until not(redstone.getInput("left"))
            sleep(counter)]]
            sleep(1)
            counter = 0
            print("step 1 loaded")
--loading step 2
            router2.setOutput("top",true)
            sleep(0.3)
            router2.setOutput("top",false)
            --[[repeat
                sleep(0.01)
                counter = counter + 1
                if counter > 500 then
                    print("Magazine not detected, manually override required")
                    io.read()
                    counter = 0
                end
            until redstone.getInput("left")
            counter = 0]]
            sleep(0.2)
            router1.setOutput("front", true)
            sleep(0.4)
            router1.setOutput("front", false)
            --[[repeat
                sleep(0.01)
                counter = counter + 0.01
                if counter > 10 then
                    print("Jammed, manually override required")
                    io.read()
                    counter = 0
                end
            until not(redstone.getInput("left"))
            sleep(counter)]]
            sleep(1)
            counter = 0
            print("step 2 loaded")
--loading step 3
            router2.setOutput("top",true)
            sleep(0.2)
            router2.setOutput("top",false)
            --[[repeat
                sleep(0.01)
                counter = counter + 1
                if counter > 500 then
                    print("Magazine not detected, manually override required")
                    io.read()
                    counter = 0
                end
            until redstone.getInput("left")]]
            counter = 0
            sleep(0.1)
            router1.setOutput("front", true)
            sleep(0.3)
            router1.setOutput("front", false)
            --[[repeat
                sleep(0.01)
                counter = counter + 0.01
                if counter > 10 then
                    print("Jammed, manually override required")
                    io.read()
                    counter = 0
                end
            until not(redstone.getInput("left"))
            sleep(counter)]]
            sleep(1)
            counter = 0
            print("step 3 loaded")
--loading step 4
            router2.setOutput("top",true)
            sleep(0.2)
            router2.setOutput("top",false)
            --[[repeat
                sleep(0.01)
                counter = counter + 1
                if counter > 500 then
                    print("Magazine not detected, manually override required")
                    io.read()
                    counter = 0
                end
            until redstone.getInput("left")]]
            counter = 0
            sleep(0.2)
            router1.setOutput("front", true)
            sleep(0.3)
            router1.setOutput("front", false)
            --[[repeat
                sleep(0.01)
                counter = counter + 0.01
                if counter > 10 then
                    print("Jammed, manually override required")
                    io.read()
                    counter = 0
                end
            until not(redstone.getInput("left"))
            sleep(counter)]]
            counter = 0
            print("step 4 loaded")
            sleep(1.5)
--resetting piston
            router2.setOutput("front",true)
            sleep(0.2)
            router2.setOutput("front",false)
            router1.setOutput("back",true)
            sleep(0.2)
            router1.setOutput("back",false)
            sleep(0.5)

            router2.setOutput("back",true)
            sleep(0.2)
            router2.setOutput("back",false)
            sleep(0.5)
            redstone.setOutput("top",true)
            print("Ready to fire")
    end
    sleep(0.1)
end