cannon = peripheral.find("cbcmodernwarfare:compact_mount")
rightMech = peripheral.wrap("back")
leftMech = peripheral.wrap("front")

redstoneSides = {
    breech = "right",
    pulley = "bottom",
    dropper = "left",
    removeDeployer = "back"
}

redstone.setOutput("front",false)
redstone.setOutput("left",false)
redstone.setOutput("bottom",false)
redstone.setOutput("right",false)
redstone.setOutput("back",false)
redstone.setOutput("top",false)

while true do
    print("What mode do you want, reload/fire")
    mode = io.read()
    if mode == "fire" then
        cannon.fire()
        sleep(0.05)
        cannon.disassemble()
        cannon.assemble()
        cannon.disassemble()
        sleep(0.1)
        --Unlock breech and place ammo
        print("Unlocking breech")
        redstone.setOutput(redstoneSides.breech,true)
        redstone.setOutput(redstoneSides.dropper,true)
        sleep(0.05*3)
        redstone.setOutput(redstoneSides.breech,false)
        redstone.setOutput(redstoneSides.dropper,false)
        io.read()
        --Remove deployer and Insert ammo
        redstone.setOutput(redstoneSides.removeDeployer,true)
        sleep(0.05*2)
        redstone.setOutput(redstoneSides.removeDeployer,false)       
        print("Inserting ammo")
        redstone.setOutput(redstoneSides.pulley,true)
        sleep(0.05*15)
        redstone.setOutput(redstoneSides.pulley,false)
        io.read()

        --lock breech
        print("lock breech")
        redstone.setOutput(redstoneSides.breech,true)
        sleep(0.05*3)
        redstone.setOutput(redstoneSides.breech,false)
        sleep(0.05)
        io.read()
        cannon.assemble()
    end
    sleep()
end