-- Grandop ticket server.
--
-- Listens for ticket update messages ("A<delta>D<delta>") from objective
-- controllers and applies them to the scoreboard. Mission parameters come from
-- the mission config so the server stays generic.
--
-- Usage: ticket_server <mission_id>

local args = { ... }
local missionId = args[1]

dofile("/lib/bootstrap.lua")

local mission = missionId and require("missions." .. missionId)

local tickets = require("lib.tickets")

local options = {
    openSide = "bottom",
    attackTeam = mission and mission.objective.attackTeam or "Red",
    defenseTeam = mission and mission.objective.defenseTeam or "Blue",
    attackStart = 500,
    defenseStart = 500,
    beaconPulse = { side = "top", seconds = 0.1 },
}

tickets.run(options)
