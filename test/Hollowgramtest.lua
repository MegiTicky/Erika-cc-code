s = peripheral.wrap("right")

s.Clear()

local function BakeBitMap(buf, color)
    local b = {}
    i = 0
    for _, v in ipairs(buf) do
        if v > 0 then
            b[i] = color
        else
            b[i] = 0x00000000
        end
        i = i + 1
    end
    return b
end

buffer = {}
for i = 0, (512*256-1) do
    buffer[i] = 0x00A0FF6F
end

img = {
    0,1,1,0,
    1,0,0,1,
    1,1,1,1,
    1,0,0,1,
    1,0,0,1,
    0,0,0,0,
}

print("")

--img = BakeBitMap(img, 0xFF00FFF0)
--img2 = BakeBitMap(img, 0xFF00FFFF)
while true do

    s.Resize(3440/4,1440/4)
    s.SetRotation(0, 0, 0)
    s.SetTranslation(0,0,0)
    s.SetScale(0.01, 0.01)

    s.Fill(256, 128, 256, 128,0xFFA00080,0);
    s.Blit(2,10,4,6,img,0)
    s.Blit(8,10,4,6,img,1)
    s.Blit(14,10,4,6,img,2)
    str = "\\u865A\\u7A7A\\u52A8\\u529B\n --Hologram."
    s.Text(-3, 50, "hello", 0xFFFFFF8F, 0)

    s.Flush()
    sleep()
end