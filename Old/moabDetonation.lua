redstone.setOutput("front",false)

print("input target altitude, default: 20")
local targetAltitude = io.read()
if targetAltitude == "" then
    targetAltitude = 20
end
targetAltitude = tonumber(targetAltitude)

print("waiting for redstone from the back the arm")
while true do
    if redstone.getInput("back") then
        print("armmed")
        break
    end
    sleep()
end

while true do
    local pos = ship.getWorldspacePosition()
    local height = pos.y - targetAltitude
    if height < 120 then
        print("detonating")
        redstone.setOutput("front",true)
        sleep(0.1)
        redstone.setOutput("front",false)
        sleep(0.1)
    end
    if height < 5 then
        redstone.setOutput("front",false)
        break
    end
    sleep()
end
