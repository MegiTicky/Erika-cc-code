-- Grandop monitor UI helper.

local monitor_ui = {}

-- Word-wrapping write to a monitor. Mirrors the original printMonitor.
function monitor_ui.print(monitor, text)
    local w, h = monitor.getSize()
    local _, y = monitor.getCursorPos()

    while #text > 0 do
        local line = text
        if #line > w then
            line = text:sub(1, w)
            text = text:sub(w + 1)
        else
            text = ""
        end

        monitor.setCursorPos(1, y)
        monitor.clearLine()
        monitor.write(line)
        y = y + 1
        if y > h then
            monitor.clear()
            y = 1
        end
    end

    monitor.setCursorPos(1, y)
end

-- Simple row-based touch menu.
-- rows = { { label = "...", value = anything } }
-- Returns the selected value, or nil when cancel is touched.
function monitor_ui.rowMenu(monitor, rows, cancelLabel)
    monitor.clear()
    monitor.setCursorPos(1, 1)

    local y = 2
    local rowMap = {}
    for _, r in ipairs(rows) do
        monitor.setCursorPos(2, y)
        monitor.write(r.label)
        rowMap[y] = r.value
        y = y + 2
    end

    if cancelLabel then
        monitor.setCursorPos(2, y)
        monitor.write(cancelLabel)
        rowMap[y] = "__cancel__"
    end

    while true do
        local event, side, x, ry = os.pullEvent("monitor_touch")
        local value = rowMap[ry]
        if value == "__cancel__" then
            return nil
        elseif value ~= nil then
            return value
        end
    end
end

return monitor_ui
