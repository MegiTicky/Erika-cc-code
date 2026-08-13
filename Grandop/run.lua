-- Grandop launcher.
--
-- A single entry point for all Grandop services. Install this alongside the
-- lib/, missions/, programs/ and tools/ folders at the root of a computer and
-- invoke it from the ROM computer's terminal operations (or a startup file):
--
--   run objective <mission>          objective controller
--   run respawn  <mission> [country] respawn terminal
--   run tickets  <mission>           ticket server
--   run loadout  [loadout_file]      loadout service
--   run artillery                    artillery server
--   run gen [path] [side]            generate a loadout JSON from a chest
--
-- Example: run objective lieyu_phase_2_5

local args = { ... }
local role = args[1]

if not role then
    print("Usage: run <role> [args...]")
    print("  objective <mission> [country]")
    print("  respawn   <mission> [country]")
    print("  tickets   <mission>")
    print("  loadout   [loadout_file]")
    print("  artillery")
    print("  gen       [output_path] [side]")
    return
end

local rest = {}
for i = 2, #args do rest[#rest + 1] = args[i] end

local program
if role == "objective" then
    program = "programs/objective_controller"
elseif role == "respawn" then
    program = "programs/respawn_terminal"
elseif role == "tickets" then
    program = "programs/ticket_server"
elseif role == "loadout" then
    program = "programs/loadout_service"
elseif role == "artillery" then
    program = "programs/artillery_server"
elseif role == "gen" then
    program = "tools/loadout_generator"
else
    error("Unknown role: " .. tostring(role))
end

if #rest > 0 then
    shell.run(program, unpack(rest))
else
    shell.run(program)
end
