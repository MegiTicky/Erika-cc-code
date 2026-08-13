-- Grandop loadout service.
--
-- Gives loadouts to players who select one via the /tellraw class menu (they
-- get tagged INF-1 .. INF-N after marking themselves dead). Loadouts come from
-- the external loadout_service.json so the service never needs a code edit to
-- change kits.
--
-- Usage: loadout_service [loadout_file]

local loadout = require("lib.loadout")

local args = { ... }
local dataFile = args[1] or "data/loadouts/loadout_service.json"

local data = loadout.load(dataFile)
if not data then error("Missing loadout file: " .. dataFile) end

local classCount = 0
for _ in pairs(data.classes or {}) do classCount = classCount + 1 end

redstone.setAnalogOutput("top", 15)
sleep(0.1)
redstone.setAnalogOutput("top", 0)

while true do
    for i = 1, classCount do
        local dead = commands.exec("/tag @a[tag=dead] remove INF-" .. i)
        if dead then
            commands.exec("/tag @a[tag=dead] add loadout")
            commands.exec("/tag @a[tag=dead] add waitloadout")
            sleep(1)
            commands.exec("/tag @a[tag=dead] remove waitloadout")

            while true do
                local done = false
                for j = 1, classCount do
                    local resp = commands.exec("/tag @a[tag=loadout,tag=INF-" .. j .. "] remove dead")
                    if resp then
                        commands.exec("/tag @a[tag=loadout,tag=INF-" .. j .. "] add Resporn")
                        commands.exec("/tag @a[tag=loadout,tag=INF-" .. j .. "] remove loadout")
                        print("give Loadout: " .. j)
                        loadout.applyClass(data, tostring(j), "@a[tag=Resporn,tag=INF-" .. j .. "]")
                        done = true
                    end
                end
                if done then break end
            end

            sleep(0)
        end
    end
end
