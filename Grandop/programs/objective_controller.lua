-- Grandop objective controller.
--
-- Runs the objective engine for a mission. The engine is chosen by the
-- mission's objective.type so the same program serves every objective style.
--
-- Usage: objective_controller <mission_id>

local args = { ... }
local missionId = args[1]
if not missionId then
    error("Usage: objective_controller <mission>")
end

dofile("/lib/bootstrap.lua")

local mission = require("missions." .. missionId)
local objective = mission.objective
if not objective then error("Mission has no objective config: " .. missionId) end

-- Objective engines send stage/ticket updates through the bottom modem.
rednet.open(objective.rednetSide or "bottom")

local engine
if objective.type == "staged_capture" then
    engine = require("lib.objective.staged_capture")
elseif objective.type == "control_point" then
    engine = require("lib.objective.control_point")
elseif objective.type == "base_assault" then
    engine = require("lib.objective.base_assault")
else
    error("Unknown objective type: " .. tostring(objective.type))
end

print("Starting objective: " .. tostring(objective.type))
engine.run(objective)
