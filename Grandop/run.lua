-- Grandop launcher.
--
-- Run with no arguments for an interactive service and mission menu, or use the
-- direct command forms documented below.
--
--   run                              interactive launcher
--   run objective <mission> [country] objective controller
--   run respawn  <mission> [country] respawn terminal
--   run tickets  <mission>           ticket server
--   run loadout   [loadout_file]     loadout service
--   run artillery                    artillery server
--   run gen       [path] [side]      generate a loadout JSON from a chest
--   run event     <mission> [flags]  complete unified event controller

local args = { ... }
local role = args[1]

local function usage()
    print("Usage: run")
    print("       run objective <mission> [country]")
    print("       run respawn <mission> [country]")
    print("       run tickets <mission>")
    print("       run loadout [loadout_file]")
    print("       run artillery")
    print("       run gen [path] [side]")
    print("       run event <mission> [--validate]")
end

local function listMissions()
    local result = {}
    if not fs.exists("/missions") then return result end
    for _, filename in ipairs(fs.list("/missions")) do
        if not fs.isDir("/missions/" .. filename) then
            local mission = filename:match("^(.+)%.lua$")
            if mission then table.insert(result, mission) end
        end
    end
    table.sort(result)
    return result
end

local function chooseMission()
    local available = listMissions()
    if #available == 0 then
        print("No mission files found in /missions.")
        return nil
    end

    print("Select a mission:")
    for i, mission in ipairs(available) do
        print("  " .. i .. ". " .. mission)
    end
    io.write("Mission number: ")
    local choice = tonumber(io.read())
    return choice and available[choice]
end

local function listLoadouts()
    local result = {}
    if not fs.exists("/data/loadouts") then return result end
    for _, filename in ipairs(fs.list("/data/loadouts")) do
        if not fs.isDir("/data/loadouts/" .. filename) and filename:match("%.json$") then
            table.insert(result, "data/loadouts/" .. filename)
        end
    end
    table.sort(result)
    return result
end

local function chooseLoadout()
    local available = listLoadouts()
    if #available == 0 then
        print("No loadout JSON files found in /data/loadouts.")
        return nil
    end

    print("Select a loadout:")
    for i, path in ipairs(available) do print("  " .. i .. ". " .. path) end
    io.write("Loadout number: ")
    local choice = tonumber(io.read())
    return choice and available[choice]
end

local function launch(program, arguments)
    if #arguments > 0 then
        shell.run(program, unpack(arguments))
    else
        shell.run(program)
    end
end

local function interactive()
    local entries = {}
    if fs.exists("/programs/event_controller.lua") then
        table.insert(entries, { label = "Start unified event", program = "programs/event_controller", mission = true })
        table.insert(entries, { label = "Validate unified event", program = "programs/event_controller", mission = true, validate = true })
    end
    if fs.exists("/programs/objective_controller.lua") then
        table.insert(entries, { label = "Start objective controller", program = "programs/objective_controller", mission = true })
    end
    if fs.exists("/programs/respawn_terminal.lua") then
        table.insert(entries, { label = "Start respawn terminal", program = "programs/respawn_terminal", mission = true })
    end
    if fs.exists("/programs/ticket_server.lua") then
        table.insert(entries, { label = "Start ticket server", program = "programs/ticket_server", mission = true })
    end
    if fs.exists("/programs/loadout_service.lua") then
        table.insert(entries, { label = "Start loadout service", program = "programs/loadout_service", loadout = true })
    end
    if fs.exists("/programs/artillery_server.lua") then
        table.insert(entries, { label = "Start artillery server", program = "programs/artillery_server" })
    end
    if fs.exists("/tools/loadout_generator.lua") then
        table.insert(entries, { label = "Generate loadout from chest", program = "tools/loadout_generator", generator = true })
    end

    if #entries == 0 then
        print("No Grandop services are installed.")
        return
    end

    print("=== Grandop Launcher ===")
    for i, entry in ipairs(entries) do print("  " .. i .. ". " .. entry.label) end
    print("  " .. (#entries + 1) .. ". Exit")
    io.write("Select an option: ")
    local selected = entries[tonumber(io.read()) or 0]
    if not selected then return end

    local arguments = {}
    if selected.mission then
        local mission = chooseMission()
        if not mission then print("Invalid mission selection."); return end
        arguments = { mission }
        if selected.validate then table.insert(arguments, "--validate") end
    elseif selected.loadout then
        local path = chooseLoadout()
        if not path then print("Invalid loadout selection."); return end
        arguments = { path }
    elseif selected.generator then
        io.write("Output path (default: data/loadouts/generated.json): ")
        local output = io.read()
        arguments = { output == "" and "data/loadouts/generated.json" or output }
        io.write("Inventory side (blank for automatic detection): ")
        local side = io.read()
        if side ~= "" then table.insert(arguments, side) end
    end
    launch(selected.program, arguments)
end

if not role then
    interactive()
    return
end

local programs = {
    objective = "programs/objective_controller",
    respawn = "programs/respawn_terminal",
    tickets = "programs/ticket_server",
    loadout = "programs/loadout_service",
    artillery = "programs/artillery_server",
    gen = "tools/loadout_generator",
    event = "programs/event_controller",
}

local program = programs[role]
if not program then
    usage()
    error("Unknown role: " .. tostring(role))
end

local rest = {}
for i = 2, #args do rest[#rest + 1] = args[i] end
launch(program, rest)
