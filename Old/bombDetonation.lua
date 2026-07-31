local Armed = false
local lastVel = 0

while not redstone.getInput("bottom") do -- loop until the input is on (i.e. while the input is not on)
  os.pullEvent("redstone") -- wait for redstone event
end
Armed = true
print("Armed")
sleep(1)
while Armed == true do

    local vel = ship.getVelocity()
    local DeltaVel = math.abs(vel.y-lastVel)

if DeltaVel > 5 then
    redstone.setAnalogOutput("top",1)
    sleep(0.5)
    redstone.setAnalogOutput("top",0)
    print("detonating")
    break
end

    lastVel = vel.y
    os.sleep()
end