local gear = peripheral.find("Create_RotationSpeedController")

local speed = 0

while true do
    if redstone.getInput("top") then
        speed = math.floor(redstone.getAnalogInput("top")*256/15)
    elseif redstone.getInput("bottom") then
        speed = -math.floor(redstone.getAnalogInput("bottom")*256/15)
    else
        speed = 0
    end

    gear.setTargetSpeed(speed)
end