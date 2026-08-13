-- Grandop unified event controller.
-- Runs objectives, local tickets, stage updates, written-book respawns, and
-- the respawn-area creative service on one command computer.
--
-- Usage: event_controller <mission_id> [--validate]

local args = { ... }
local missionId = args[1]
if not missionId then error("Usage: event_controller <mission>") end
local validateOnly = args[2] == "--validate"

local originalPrint = print
local originalPrintError = printError
local logFile
local logPath

local function joinArguments(...)
    local values = { ... }
    for i, value in ipairs(values) do values[i] = tostring(value) end
    return table.concat(values, " ")
end

local function writeLog(kind, text)
    if logFile then
        logFile.writeLine("[" .. tostring(os.epoch("utc")) .. "][" .. kind .. "] " .. text)
        logFile.flush()
    end
end

if not fs.exists("/logs") then fs.makeDir("/logs") end
logPath = "/logs/event_" .. missionId:gsub("[^%w_%-]", "_") .. "_" .. tostring(os.epoch("utc")) .. ".log"
logFile = fs.open(logPath, "w")
if logFile then
    print = function(...)
        local text = joinArguments(...)
        writeLog("OUT", text)
        originalPrint(text)
    end
    printError = function(...)
        local text = joinArguments(...)
        writeLog("ERR", text)
        originalPrintError(text)
    end
    print("Event log: " .. logPath)
else
    originalPrintError("Unable to create event log: " .. logPath)
end

local function rootRequire(name)
    if package.loaded[name] then return package.loaded[name] end
    local chunk, reason = loadfile("/" .. name:gsub("%.", "/") .. ".lua")
    if not chunk then error("Cannot load /" .. name:gsub("%.", "/") .. ".lua: " .. tostring(reason)) end
    local result = chunk()
    package.loaded[name] = result or true
    return package.loaded[name]
end
_G.require = rootRequire
_G.grandopRequire = rootRequire

local missionFile = "/missions/" .. missionId:gsub("[^%w_%-]", "") .. ".lua"
local missionChunk, missionReason = loadfile(missionFile)
if not missionChunk then error("Cannot load " .. missionFile .. ": " .. tostring(missionReason)) end
local mission = missionChunk()
local objective = mission.objective
local respawn = mission.respawn
local teams = mission.teams
local features = mission.features or {}

local function requireTable(value, name)
    if type(value) ~= "table" then error("Configuration error: " .. name .. " must be a table") end
end

local function validateMission()
    requireTable(mission, "mission")
    requireTable(objective, "objective")
    requireTable(respawn, "respawn")
    requireTable(teams, "teams")
    if not teams.Blue or not teams.Red then
        error("Configuration error: teams.Blue and teams.Red are required")
    end
    if type(respawn.loadout_file) ~= "string" or respawn.loadout_file == "" then
        error("Configuration error: respawn.loadout_file is required")
    end
    if not fs.exists("/" .. respawn.loadout_file) then
        error("Configuration error: missing loadout file /" .. respawn.loadout_file)
    end
    if type(objective.type) ~= "string" then
        error("Configuration error: objective.type is required")
    end
    if objective.type == "staged_capture" and (type(objective.captureZones) ~= "table" or #objective.captureZones == 0) then
        error("Configuration error: staged_capture needs at least one capture zone")
    end
    if objective.type == "staged_capture" and (type(objective.capture) ~= "table" or tonumber(objective.capture.threshold) == nil or objective.capture.threshold <= 0) then
        error("Configuration error: staged_capture needs a positive capture.threshold")
    end
    if type(features.tanks) ~= "boolean" then features.tanks = false end
    if type(features.creative) ~= "boolean" then features.creative = false end
    if type(features.stageSync) ~= "boolean" then features.stageSync = false end
    requireTable(respawn.stagingAreas, "respawn.stagingAreas")
    requireTable(respawn.infantrySpawns, "respawn.infantrySpawns")
    for team, faction in pairs(teams) do
        local areas = respawn.stagingAreas[faction]
        if type(areas) ~= "table" or type(areas.default) ~= "table" then
            error("Configuration error: missing default staging area for " .. team .. "/" .. faction)
        end
        for _, field in ipairs({ "x", "y", "z", "radius" }) do
            if tonumber(areas.default[field]) == nil then
                error("Configuration error: staging area " .. faction .. ".default." .. field .. " must be a number")
            end
        end
        if type(respawn.infantrySpawns[faction]) ~= "table" then
            error("Configuration error: missing infantry spawns for " .. faction)
        end
        if objective.type == "staged_capture" then
            for stageIndex = 1, #objective.captureZones do
                if type(areas[stageIndex] or areas.default) ~= "table" then
                    error("Configuration error: missing staging area for " .. faction .. " stage " .. stageIndex)
                end
                if type(respawn.infantrySpawns[faction][stageIndex]) ~= "table" or #respawn.infantrySpawns[faction][stageIndex] == 0 then
                    error("Configuration error: missing infantry spawns for " .. faction .. " stage " .. stageIndex)
                end
            end
        end
    end
    if features.tanks then
        requireTable(respawn.vehiclePools, "respawn.vehiclePools")
        requireTable(respawn.vehiclePools.initial, "respawn.vehiclePools.initial")
        requireTable(respawn.vehicleSpawns, "respawn.vehicleSpawns")
        for _, faction in pairs(teams) do
            if type(respawn.vehiclePools.initial[faction]) ~= "table" then
                error("Configuration error: missing initial vehicle pool for " .. faction)
            end
            if type(respawn.vehicleSpawns[faction]) ~= "table" then
                error("Configuration error: missing vehicle spawns for " .. faction)
            end
        end
    end
end

validateMission()
if validateOnly then
    print("Mission configuration valid: " .. missionId)
    if logFile then logFile.close() end
    return
end

local radar = peripheral.find("sp_radar")
local monitor = peripheral.find("monitor")
if features.tanks and not radar then
    error("Configuration error: tanks require an sp_radar peripheral")
end

local loadout = grandopRequire("lib.loadout")
local stage = grandopRequire("lib.stage_channel")
local creative = grandopRequire("lib.services.creative_area")
local book = grandopRequire("lib.respawn.book")

local data = loadout.load(respawn.loadout_file)
if not data then error("Missing loadout file: " .. respawn.loadout_file) end

if features.tanks then
    local vehicles = grandopRequire("lib.respawn.vehicles")
    local tankListFile = respawn.tankListFile or "tanksList.txt"
    if respawn.resetTanks then
        vehicles.saveTankList(tankListFile, respawn.vehiclePools.initial)
    end
    respawn.tanks = vehicles.loadTankList(tankListFile, respawn.vehiclePools.initial)
    respawn.resetTanks = false
end

if respawn.initScoreboard then respawn.initScoreboard(respawn.resetSpawns or false) end

local stageHub = objective.stageState or { current = objective.startZone or 1 }
objective.stagingAreas = respawn.stagingAreas
objective.teamFactions = teams
objective.attackerDepleted = respawn.attackerDepleted
local state = {
    playerTankMap = {},
    tankslugtoID = {},
}

local ctx = {
    mission = mission,
    objective = objective,
    respawn = respawn,
    teams = teams,
    features = features,
    monitor = monitor,
    radar = radar,
    loadoutData = data,
    stage = stageHub,
    state = state,
    log = print,
}

local objectiveEngine
if objective.type == "staged_capture" then
    objectiveEngine = grandopRequire("lib.objective.staged_capture")
elseif objective.type == "control_point" then
    objectiveEngine = grandopRequire("lib.objective.control_point")
elseif objective.type == "base_assault" then
    objectiveEngine = grandopRequire("lib.objective.base_assault")
else
    error("Unknown objective type: " .. tostring(objective.type))
end

local function objectiveLoop()
    objectiveEngine.run(objective)
end

local function bookLoop()
    book.run(ctx)
end

local function stageListenerLoop()
    if features.stageSync and objective.stage_channel and not objective.stageState then
        stage.listener(stageHub)()
    else
        while true do sleep(1) end
    end
end

local function creativeLoop()
    if features.creative and radar and respawn.creativeZones then
        creative.run(radar, respawn.creativeZones("USMC"), respawn.creativeRadius or 50)
    else
        while true do sleep(1) end
    end
end

local tasks = { objectiveLoop, bookLoop, stageListenerLoop, creativeLoop }
if respawn.reinforcement and respawn.reinforcement.loop then
    table.insert(tasks, function() respawn.reinforcement.loop(ctx) end)
end
if respawn.retreatLoop then
    table.insert(tasks, function() respawn.retreatLoop(ctx) end)
end

print("Starting unified event: " .. missionId)
local ok, reason = xpcall(function()
    parallel.waitForAny(unpack(tasks))
end, function(message)
    return tostring(message)
end)

if not ok then
    printError("Event task failed: " .. reason)
else
    print("Event ended")
end

if logFile then logFile.close() end
