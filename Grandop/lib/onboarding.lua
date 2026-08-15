-- Grandop newcomer onboarding.
-- Players request a team with trigger objectives; this service performs the
-- privileged team join and staging teleport on the command computer.

local onboarding = {}

-- Keep objective names within Minecraft's 16-character limit.
local RED_OBJECTIVE = "g_join_red"
local BLUE_OBJECTIVE = "g_join_blue"
local PROMPT_TAG = "grandop_onboarding_prompted"

local function validPlayerName(name)
    return type(name) == "string" and name:match("^[A-Za-z0-9_][A-Za-z0-9_%-]*$") ~= nil
end

local function validTeamName(name)
    return type(name) == "string" and name:match("^[A-Za-z0-9_%-]+$") ~= nil
end

local function playerTarget(name, filters)
    return "@a[name=" .. name .. (filters or "") .. "]"
end

local function commandScore(name, objective)
    local ok, output, value = commands.exec("/scoreboard players get " .. name .. " " .. objective)
    if ok and tonumber(value) then return tonumber(value) end
    for _, line in ipairs(output or {}) do
        local found = tostring(line):match("has%s+(-?%d+)")
        if found then return tonumber(found) end
    end
    return 0
end

local function splitNames(text, result)
    for name in tostring(text):gmatch("[A-Za-z0-9_][A-Za-z0-9_%-]*") do
        if validPlayerName(name) then result[name] = true end
    end
end

local function onlinePlayers()
    local ok, output = commands.exec("/list")
    if not ok then return nil, "list command failed" end
    local result = {}
    if type(output) == "table" then
        for _, line in ipairs(output) do
            local names = tostring(line):match(":%s*(.*)$")
            if names and names ~= "" then splitNames(names, result) end
        end
    else
        local names = tostring(output):match(":%s*(.*)$")
        if names and names ~= "" then splitNames(names, result) end
    end
    return result
end

local function sendPrompt(target, redTeam, blueTeam)
    -- Team names are validated before this function is called. Keep this
    -- payload literal because some ComputerCraft versions mis-serialize JSON.
    local message = '[{"text":"You are not assigned to the current event.\\n","color":"gold","bold":true},{"text":"If you already have a team and are fighting, ignore this message.\\n","color":"gray"},{"text":"[ Join ' .. redTeam .. ' ]","color":"red","clickEvent":{"action":"run_command","value":"/trigger ' .. RED_OBJECTIVE .. ' set 1"}},{"text":"   "},{"text":"[ Join ' .. blueTeam .. ' ]\\n","color":"blue","clickEvent":{"action":"run_command","value":"/trigger ' .. BLUE_OBJECTIVE .. ' set 1"}}]'
    return commands.exec("/tellraw " .. target .. " " .. message)
end

local function stagingArea(ctx, team)
    local faction = ctx.teams[team]
    local areas = faction and ctx.respawn.stagingAreas[faction]
    if not areas then return nil end
    return areas[ctx.stage.current] or areas.default
end

local function clearRequest(name)
    commands.exec("/scoreboard players set " .. name .. " " .. RED_OBJECTIVE .. " 0")
    commands.exec("/scoreboard players set " .. name .. " " .. BLUE_OBJECTIVE .. " 0")
end

local function enableRequests(name)
    local target = playerTarget(name)
    commands.exec("/scoreboard players enable " .. target .. " " .. RED_OBJECTIVE)
    commands.exec("/scoreboard players enable " .. target .. " " .. BLUE_OBJECTIVE)
end

local function markJoined(name)
    commands.exec("/tag " .. playerTarget(name) .. " remove " .. PROMPT_TAG)
end

local function teamExists(ctx, team)
    return type(team) == "string" and ctx.teams[team] ~= nil
end

function onboarding.run(ctx)
    local config = ctx.mission.onboarding or {}
    local redTeam = config.red_team or "Red"
    local blueTeam = config.blue_team or "Blue"
    if not validTeamName(redTeam) or not validTeamName(blueTeam) or redTeam == blueTeam then
        error("Onboarding team names are invalid")
    end
    if not teamExists(ctx, redTeam) or not teamExists(ctx, blueTeam) then
        error("Onboarding requires configured teams " .. redTeam .. " and " .. blueTeam)
    end

    commands.exec("/team add " .. redTeam)
    commands.exec("/team add " .. blueTeam)
    commands.exec("/scoreboard objectives add " .. RED_OBJECTIVE .. " trigger")
    commands.exec("/scoreboard objectives add " .. BLUE_OBJECTIVE .. " trigger")

    local prompted = {}
    local previousOnline = {}
    local promptInterval = tonumber(config.prompt_interval) or 1
    local nextPrompt = 0
    local log = ctx.log or print

    local function eligible(name)
        return commands.exec("execute if entity " .. playerTarget(name, ",team=!" .. redTeam .. ",team=!" .. blueTeam) .. ")")
    end

    local function promptNewcomers(players)
        for name in pairs(players) do
            if not previousOnline[name] then
                commands.exec("/tag " .. playerTarget(name) .. " remove " .. PROMPT_TAG)
                prompted[name] = nil
            end
            if not prompted[name] and eligible(name) then
                if sendPrompt(playerTarget(name), redTeam, blueTeam) then
                    commands.exec("/tag " .. playerTarget(name) .. " add " .. PROMPT_TAG)
                    prompted[name] = true
                    log("Onboarding prompt sent to " .. name)
                end
            end
            enableRequests(name)
        end
    end

    local function processRequest(name, team)
        local target = playerTarget(name)
        local requested = commandScore(name, team == redTeam and RED_OBJECTIVE or BLUE_OBJECTIVE)
        if requested < 1 then return end
        local other = commandScore(name, team == redTeam and BLUE_OBJECTIVE or RED_OBJECTIVE)
        if other > 0 then
            commands.exec("/tellraw " .. target .. " {\"text\":\"Choose only one team.\",\"color\":\"red\"}")
            clearRequest(name)
            enableRequests(name)
            return
        end
        if not eligible(name) then
            clearRequest(name)
            enableRequests(name)
            markJoined(name)
            return
        end
        local area = stagingArea(ctx, team)
        if not area then
            log("Onboarding rejected for " .. name .. ": no staging area for " .. team .. " stage " .. ctx.stage.current)
            commands.exec("/tellraw " .. target .. " {\"text\":\"That team's staging area is unavailable.\",\"color\":\"red\"}")
            clearRequest(name)
            enableRequests(name)
            return
        end
        local joined = commands.exec("/team join " .. team .. " " .. target)
        if joined then
            commands.exec("/spawnpoint " .. target .. " " .. area.x .. " " .. area.y .. " " .. area.z)
            commands.exec("/tp " .. target .. " " .. area.x .. " " .. area.y .. " " .. area.z)
            commands.exec("/tellraw " .. target .. " {\"text\":\"You joined " .. team .. " and were sent to staging.\",\"color\":\"green\"}")
            markJoined(name)
            prompted[name] = nil
            log("Onboarding joined " .. name .. " to " .. team .. " at stage " .. ctx.stage.current)
        end
        clearRequest(name)
        enableRequests(name)
    end

    while not ctx.operator.shutdown do
        local players, reason = onlinePlayers()
        if players then
            for name in pairs(previousOnline) do
                if not players[name] then prompted[name] = nil end
            end
            promptNewcomers(players)
            for name in pairs(players) do
                processRequest(name, redTeam)
                processRequest(name, blueTeam)
            end
            previousOnline = players
        elseif reason then
            log("Onboarding player-list scan failed: " .. reason)
        end
        sleep(promptInterval)
    end
end

return onboarding
