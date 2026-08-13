-- Grandop unified event controller.
-- Runs objectives, local tickets, stage updates, written-book respawns, and
-- the respawn-area creative service on one command computer.
--
-- Usage: event_controller <mission_id>

local args = { ... }
local missionId = args[1]
if not missionId then error("Usage: event_controller <mission>") end

local function rootRequire(name)
    if package.loaded[name] then return package.loaded[name] end
    local chunk, reason = loadfile("/" .. name:gsub("%.", "/") .. ".lua")
    if not chunk then error("Cannot load /" .. name:gsub("%.", "/") .. ".lua: " .. tostring(reason)) end
    local result = chunk()
    package.loaded[name] = result or true
    return package.loaded[name]
end
_G.require = rootRequire

local missionFile = "/missions/" .. missionId:gsub("[^%w_%-]", "") .. ".lua"
local missionChunk, missionReason = loadfile(missionFile)
if not missionChunk then error("Cannot load " .. missionFile .. ": " .. tostring(missionReason)) end
local mission = missionChunk()
local objective = mission.objective
local respawn = mission.respawn
if not objective then error("Mission has no objective config: " .. missionId) end
if not respawn then error("Mission has no respawn config: " .. missionId) end
if not respawn.area then error("Mission respawn config needs area: " .. missionId) end

local radar = peripheral.find("sp_radar")
local monitor = peripheral.find("monitor")

local loadout = require("lib.loadout")
local stage = require("lib.stage_channel")
local creative = require("lib.services.creative_area")
local book = require("lib.respawn.book")

local data = loadout.load(respawn.loadout_file)
if not data then error("Missing loadout file: " .. respawn.loadout_file) end

local vehicles = require("lib.respawn.vehicles")
local tankListFile = respawn.tankListFile or "tanksList.txt"
if respawn.resetTanks then
    vehicles.saveTankList(tankListFile, respawn.tanks)
end
respawn.tanks = vehicles.loadTankList(tankListFile, respawn.tanks)

if respawn.resetTanks then
    respawn.resetTanks = false
end

if respawn.initScoreboard then respawn.initScoreboard(respawn.resetSpawns or false) end

local stageHub = objective.stageState or { current = objective.startZone or 1 }
local state = {
    playerTankMap = {},
    tankslugtoID = {},
}

local ctx = {
    mission = mission,
    monitor = monitor,
    radar = radar,
    loadoutData = data,
    stage = stageHub,
    state = state,
}

local objectiveEngine
if objective.type == "staged_capture" then
    objectiveEngine = require("lib.objective.staged_capture")
elseif objective.type == "control_point" then
    objectiveEngine = require("lib.objective.control_point")
elseif objective.type == "base_assault" then
    objectiveEngine = require("lib.objective.base_assault")
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
    if objective.stage_channel and not objective.stageState then
        stage.listener(stageHub)()
    else
        while true do sleep(1) end
    end
end

local function creativeLoop()
    if radar and respawn.creativeZones then
        creative.run(radar, respawn.creativeZones("USMC"), respawn.creativeRadius or respawn.area.radius)
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
parallel.waitForAny(unpack(tasks))
