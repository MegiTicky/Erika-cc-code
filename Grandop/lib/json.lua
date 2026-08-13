-- Grandop JSON file helpers
-- Loads/saves JSON data files (loadouts, mission state, etc).

local json = {}

local function readAll(path)
    local f = fs.open(path, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    return content
end

local function writeAll(path, content)
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

--- Load a JSON file into a Lua table. Returns nil if the file does not exist.
function json.load(path)
    local content = readAll(path)
    if not content then return nil end
    local ok, res = pcall(textutils.unserialiseJSON, content)
    if not ok then
        error("Invalid JSON in " .. path .. ": " .. tostring(res))
    end
    return res
end

--- Save a Lua table to a JSON file (pretty printed).
function json.save(path, data)
    return writeAll(path, textutils.serialiseJSON(data, true))
end

function json.exists(path)
    return fs.exists(path)
end

return json
