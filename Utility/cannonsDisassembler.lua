local cannons = {}
local k = 1
local nilCount = 0
local i = 0
peripheralfindFound = false

redstone.setOutput("front",false)
while nilCount < 200 do
    local cannon = peripheral.wrap("createbigcannons:cannon_mount_"..tostring(i)) or peripheral.wrap("cbcmodernwarfare:compact_mount_"..tostring(i))
    if not(cannon) and not(peripheralfindFound) then
        cannon = peripheral.find("createbigcannons:cannon_mount") or peripheral.find("cbcmodernwarfare:compact_mount")
        peripheralfindFound = true
    end

    if cannon then
        cannon.assemble()
        cannons[k] = cannon
        k = k + 1
        nilCount = 0
        print("found cannon")
    else
        nilCount = nilCount + 1
    end
    i = i + 1
end
print("Found "..#cannons.." cannons")

for i, cannon in ipairs(cannons) do
    cannon.disassemble()
    print("disassembling cannon "..i)
end