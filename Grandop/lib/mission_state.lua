-- Versioned, crash-recoverable mission state snapshots.
local state = {}

state.VERSION = 1

local function pathFor(missionId)
    return "/data/mission_state_" .. missionId:gsub("[^%w_%-]", "_") .. ".json"
end

local function read(path)
    local file = fs.open(path, "r")
    if not file then return nil end
    local content = file.readAll()
    file.close()
    local ok, value = pcall(textutils.unserialiseJSON, content)
    if not ok then return nil, tostring(value) end
    return value
end

local function validate(snapshot, missionId)
    if type(snapshot) ~= "table" then return false, "root must be an object" end
    if snapshot.schema_version ~= state.VERSION then return false, "unsupported schema version" end
    if snapshot.mission_id ~= missionId then return false, "mission ID does not match" end
    if type(snapshot.stage) ~= "number" or snapshot.stage < 1 or snapshot.stage % 1 ~= 0 then
        return false, "invalid stage"
    end
    for _, name in ipairs({ "objective", "tickets", "quotas", "flags", "operator" }) do
        if snapshot[name] ~= nil and type(snapshot[name]) ~= "table" then
            return false, "invalid " .. name
        end
    end
    return true
end

function state.path(missionId)
    return pathFor(missionId)
end

function state.load(missionId)
    local path = pathFor(missionId)
    local primaryExists = fs.exists(path)
    local backupPath = path .. ".bak"
    if not primaryExists and not fs.exists(backupPath) then return nil, "missing" end
    local snapshot, reason = primaryExists and read(path) or nil
    if not snapshot then
        local backup = read(backupPath)
        if backup then snapshot = backup else return nil, "invalid JSON: " .. tostring(reason) end
    end
    local ok
    ok, reason = validate(snapshot, missionId)
    if not ok then return nil, reason end
    return snapshot
end

function state.save(missionId, snapshot)
    local path = pathFor(missionId)
    local ok, reason = validate(snapshot, missionId)
    if not ok then return false, reason end
    if not fs.exists("/data") then fs.makeDir("/data") end
    local temp = path .. ".tmp"
    local backup = path .. ".bak"
    local encoded = textutils.serialiseJSON(snapshot, true)
    local file = fs.open(temp, "w")
    if not file then return false, "could not open temporary state file" end
    file.write(encoded)
    file.close()
    if fs.exists(backup) then fs.delete(backup) end
    if fs.exists(path) then fs.move(path, backup) end
    local moved, moveReason = pcall(fs.move, temp, path)
    if not moved then
        if fs.exists(backup) then fs.move(backup, path) end
        return false, tostring(moveReason)
    end
    if fs.exists(backup) then fs.delete(backup) end
    return true
end

function state.reset(missionId)
    for _, suffix in ipairs({ "", ".tmp", ".bak" }) do
        local path = pathFor(missionId) .. suffix
        if fs.exists(path) then fs.delete(path) end
    end
end

return state
