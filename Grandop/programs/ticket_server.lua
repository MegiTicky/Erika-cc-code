-- Grandop ticket server.
--
-- Listens for ticket update messages ("A<delta>D<delta>") from objective
-- controllers and applies them to the scoreboard. Mission parameters come from
-- the mission config so the server stays generic.
--
-- Usage: ticket_server <mission_id>

local args = { ... }
local missionId = args[1]

local function rootRequire(name)
    if package.loaded[name] then return package.loaded[name] end
    local chunk, reason = loadfile("/" .. name:gsub("%.", "/") .. ".lua")
    if not chunk then error("Cannot load /" .. name:gsub("%.", "/") .. ".lua: " .. tostring(reason)) end
    local result = chunk()
    package.loaded[name] = result or true
    return package.loaded[name]
end
_G.require = rootRequire

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
