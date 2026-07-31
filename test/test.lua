local s = peripheral.find("hologram")
if not s then error("No hologram found!") end

-- Config
local WIDTH, HEIGHT = 1024, 1024
local CLICK_COLOR = 0x00FF00FF -- Green
local BG_COLOR = 0x00000088    -- Black

-- Initialize hologram
s.Resize(WIDTH, HEIGHT)
s.SetClearColor(BG_COLOR)
s.Clear()
s.SetRotation(0, 0, 0)
s.SetTranslation(0, 1, 0)
s.SetScale(0.02, 0.02)

-- State
local clickCount = 0
local lastX,lastY = 0,0

-- Function to redraw screen
local function redraw()
    s.Clear()
    s.Text(10, 30, "Clicks: " .. tostring(clickCount), CLICK_COLOR, 0)
    s.Text(10, 50, "Last click Pos X:"..lastX.." Y: "..lastY, CLICK_COLOR, 0)
    s.Flush()
end

redraw()

-- Event loop
while true do
    local event, screenName, button, x, y = os.pullEvent("vp_mouse_clicked")
    if screenName == s.GetName() then
        clickCount = clickCount + 1
        if x and y then
            lastX = tonumber(x)
            lastY = tonumber(y)
        end

        redraw()
    end
end
