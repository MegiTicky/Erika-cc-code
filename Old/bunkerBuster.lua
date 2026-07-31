while true do
    if redstone.getInput("top") then
        --armmed
        break
    end
    print("Preparing to be armed")

    sleep()
end

sleep(1)

while true do
    --bomb dropped, waiting for impact
    if redstone.getInput("bottom") then
        print("detonated")
        redstone.setOutput("front",true)
        redstone.setOutput("back",true)
        sleep(0.1)
        redstone.setOutput("front",false)
        redstone.setOutput("back",false)
        break
    end
    print("Bomb armmed, waiting for impact")

    sleep()
end

