local counter = 0
local router1 = peripheral.find("redrouter")

router1.setOutput("left",false)
router1.setOutput("front",false)
router1.setOutput("bottom",false)
router1.setOutput("right",false)
router1.setOutput("back",false)
redstone.setOutput("top",false)
redstone.setOutput("left",false)
redstone.setOutput("right",false)
redstone.setOutput("front",false)
while true do
    if redstone.getInput("bottom") then
        print("starting reload")
        --removing srcew
        redstone.setOutput("front",false)
        sleep(0.05)
        redstone.setOutput("right",true)
        sleep(0.2)
        redstone.setOutput("right",false)

        sleep(0.5)

        --placing shell
        router1.setOutput("back",true)
        sleep(0.1)
        router1.setOutput("back",false)

        sleep(0.5)

        redstone.setOutput("top",true)
        sleep(0.2)
        redstone.setOutput("top",false)

        sleep(1)

        --loading shell
        redstone.setOutput("back",true)
        sleep(0.5)
        redstone.setOutput("back",false)
        sleep(0.1)

        --placing powder
        sleep(1)
        for i=1,8,1 do
            router1.setOutput("top",true)
            sleep(0.1)
            router1.setOutput("top",false)
            sleep(1.2)

            redstone.setOutput("back",true)
            sleep(0.1)
            redstone.setOutput("back",false)
            sleep(1.2)

            print("loaded: "..i)
        end

        redstone.setOutput("right",true)
        sleep(0.1)
        redstone.setOutput("right",false)
        sleep(0.2)

        --screwing

        sleep(0.5)
        redstone.setOutput("front",true)
    end
    sleep(0.1)
end