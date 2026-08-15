-- Grandop newcomer onboarding.
-- Players request a team with trigger objectives; this service performs the
-- privileged team join and staging teleport on the command computer.

local onboarding = {}

-- Keep objective names within Minecraft's 16-character limit.
local RED_OBJECTIVE = "g_join_red"
local BLUE_OBJECTIVE = "g_join_blue"
local COOLDOWN_OBJECTIVE = "g_onboard_cd"
local PROMPT_TAG = "grandop_onboarding_prompted"
local RED_PENDING_TAG = "grandop_join_red_pending"
local BLUE_PENDING_TAG = "grandop_join_blue_pending"

local function validTeamName(name)
    return type(name) == "string" and name:match("^[A-Za-z0-9_%-]+$") ~= nil
end

local function unassignedSelector(redTeam, blueTeam, extra)
    local filters = "team=!" .. redTeam .. ",team=!" .. blueTeam
    if extra then filters = filters .. "," .. extra end
    return "@a[" .. filters .. "]"
end

local function sendPrompt(target, redTeam, blueTeam)
    -- Team names are validated before this function is called. Keep this
    -- payload literal because some ComputerCraft versions mis-serialize JSON.
    local message = ('[{"text":"You are not assigned to the current event.\\n","color":"gold","bold":true},{"text":"If you already have a team and are fighting, ignore this message.\\n","color":"gray"},{"text":"[ Join %s ]","color":"red","clickEvent":{"action":"run_command","value":"/trigger %s set 1"}},{"text":"   "},{"text":"[ Join %s ]\\n","color":"blue","clickEvent":{"action":"run_command","value":"/trigger %s set 1"}}]'):format(redTeam, RED_OBJECTIVE, blueTeam, BLUE_OBJECTIVE)
    return commands.exec("tellraw " .. target .. " " .. message)
end

local function stagingArea(ctx, team)
    local faction = ctx.teams[team]
    local areas = faction and ctx.respawn.stagingAreas[faction]
    if not areas then return nil end
    return areas[ctx.stage.current] or areas.default
end

local function clearRequests(target)
    commands.exec("scoreboard players set " .. target .. " " .. RED_OBJECTIVE .. " 0")
    commands.exec("scoreboard players set " .. target .. " " .. BLUE_OBJECTIVE .. " 0")
end

local function enableRequests(target)
    commands.exec("scoreboard players enable " .. target .. " " .. RED_OBJECTIVE)
    commands.exec("scoreboard players enable " .. target .. " " .. BLUE_OBJECTIVE)
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

    local loopInterval = math.max(0.25, tonumber(config.loop_interval) or 1)
    local log = ctx.log or print

    commands.exec("team add " .. redTeam)
    commands.exec("team add " .. blueTeam)
    commands.exec("scoreboard objectives add " .. RED_OBJECTIVE .. " trigger")
    commands.exec("scoreboard objectives add " .. BLUE_OBJECTIVE .. " trigger")
    commands.exec("scoreboard objectives add " .. COOLDOWN_OBJECTIVE .. " dummy")

    -- Do not carry an old click or pending request across a controller restart.
    commands.exec("scoreboard players set @a " .. RED_OBJECTIVE .. " 0")
    commands.exec("scoreboard players set @a " .. BLUE_OBJECTIVE .. " 0")
    commands.exec("tag @a remove " .. RED_PENDING_TAG)
    commands.exec("tag @a remove " .. BLUE_PENDING_TAG)

    local function initializeScores()
        commands.exec("scoreboard players add @a " .. RED_OBJECTIVE .. " 0")
        commands.exec("scoreboard players add @a " .. BLUE_OBJECTIVE .. " 0")
        commands.exec("scoreboard players add @a " .. COOLDOWN_OBJECTIVE .. " 0")
        -- A trigger objective must be enabled again after a player uses it.
        enableRequests(unassignedSelector(redTeam, blueTeam))
        -- Never retain a request from before a player joined an event team.
        clearRequests("@a[team=" .. redTeam .. "]")
        clearRequests("@a[team=" .. blueTeam .. "]")
    end

    local function promptUnassigned()
        local ready = unassignedSelector(redTeam, blueTeam, "tag=!" .. PROMPT_TAG)
        if sendPrompt(ready, redTeam, blueTeam) then
            if commands.exec("tag " .. ready .. " add " .. PROMPT_TAG) then
                log("Onboarding prompt sent to unassigned players")
            else
                log("Onboarding prompt sent, but prompt lock tag could not be added")
            end
        end
    end

    local function processConflicts()
        local conflict = unassignedSelector(redTeam, blueTeam, "scores={" .. RED_OBJECTIVE .. "=1..," .. BLUE_OBJECTIVE .. "=1..}")
        commands.exec("tellraw " .. conflict .. " {\"text\":\"Choose only one team.\",\"color\":\"red\"}")
        clearRequests(conflict)
        enableRequests(unassignedSelector(redTeam, blueTeam))
    end

    local function processTeam(team, objective, pendingTag, otherObjective)
        local area = stagingArea(ctx, team)
        local request = unassignedSelector(redTeam, blueTeam, "tag=!" .. pendingTag .. ",scores={" .. objective .. "=1..," .. otherObjective .. "=0}")
        if not area then
            commands.exec("tellraw " .. request .. " {\"text\":\"That team's staging area is unavailable.\",\"color\":\"red\"}")
            clearRequests(request)
            enableRequests(unassignedSelector(redTeam, blueTeam))
            log("Onboarding rejected: no staging area for " .. team .. " stage " .. ctx.stage.current)
            return
        end

        -- Tag the request before joining so the same validated player set is
        -- used for team assignment, teleport, feedback, and cleanup.
        commands.exec("tag " .. request .. " add " .. pendingTag)
        local pending = "@a[tag=" .. pendingTag .. "]"
        commands.exec("team join " .. team .. " " .. pending)

        local assigned = "@a[tag=" .. pendingTag .. ",team=" .. team .. "]"
        commands.exec("spawnpoint " .. assigned .. " " .. area.x .. " " .. area.y .. " " .. area.z)
        commands.exec("tp " .. assigned .. " " .. area.x .. " " .. area.y .. " " .. area.z)
        commands.exec("tellraw " .. assigned .. " {\"text\":\"You joined " .. team .. " and were sent to staging.\",\"color\":\"green\"}")
        clearRequests(assigned)
        commands.exec("tag " .. assigned .. " remove " .. pendingTag)
        commands.exec("tag " .. assigned .. " remove " .. PROMPT_TAG)
        -- Clean requests that failed because the player disconnected or the
        -- server rejected the team operation.
        clearRequests("@a[tag=" .. pendingTag .. "]")
        commands.exec("tag @a[tag=" .. pendingTag .. "] remove " .. pendingTag)
        log("Onboarding joined players to " .. team .. " at stage " .. ctx.stage.current)
    end

    while not ctx.operator.shutdown do
        initializeScores()
        commands.exec("scoreboard players remove " .. unassignedSelector(redTeam, blueTeam, "scores={" .. COOLDOWN_OBJECTIVE .. "=1..}") .. " " .. COOLDOWN_OBJECTIVE .. " 1")
        promptUnassigned()
        processConflicts()
        processTeam(redTeam, RED_OBJECTIVE, RED_PENDING_TAG, BLUE_OBJECTIVE)
        processTeam(blueTeam, BLUE_OBJECTIVE, BLUE_PENDING_TAG, RED_OBJECTIVE)
        sleep(loopInterval)
    end
end

return onboarding
