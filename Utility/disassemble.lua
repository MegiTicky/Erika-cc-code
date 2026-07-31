local cannon1 = peripheral.wrap("left")
for i = 0, 200 do  -- Assuming there are 2 Create_RotationSpeedController peripherals
    cannon2 = peripheral.wrap("cbc_cannon_mount_"..tostring(i))
    if cannon2 then
        break
    end
end
if not(cannon2) then
    error("cannon2 not found")
end

print("Are you sure you want to unasseblme, press enter to confirm")
io.read()
cannon1.disassemble()
cannon2.disassemble()