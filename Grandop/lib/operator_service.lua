-- Rednet control service for a dedicated operator computer.
local service = {}
local REQUEST = "grandop_operator_request"
local RESPONSE = "grandop_operator_response"
local PROTOCOL = "grandop_operator"

local function score(player, objective)
    local ok, _, value = commands.exec("/scoreboard players get " .. player .. " " .. objective)
    return ok and tonumber(value) or 0
end

local function reply(id, requestId, ok, message, data)
    rednet.broadcast({ type = RESPONSE, target = id, request_id = requestId, ok = ok, message = message, data = data }, PROTOCOL)
end

local function audit(ctx, sender, action, message)
    ctx.log("Operator " .. sender .. " " .. action .. ": " .. message)
end

local function quotaPools(ctx)
    return (ctx.mission.operator and ctx.mission.operator.quota_pools) or {}
end

local function status(ctx)
    local result = { mission = ctx.mission.id, paused = ctx.operator.paused, stage = ctx.stage.current, quotas = {} }
    for pool in pairs(quotaPools(ctx)) do
        result.quotas[pool] = score(pool, "Troops_Strength")
    end
    return result
end

function service.run(ctx, config)
    if not config or not config.rednet_side then error("Missing operator configuration") end
    rednet.open(config.rednet_side)
    ctx.log("Operator service listening on Rednet; access is trusted at the command-computer boundary")
    while not ctx.operator.shutdown do
        local sender, message = rednet.receive(PROTOCOL, 0.25)
        if sender and type(message) == "table" and message.type == REQUEST then
            local requestId = message.request_id
            local action, args = message.action, message.args or {}
            if action == "status" then
                reply(sender, requestId, true, "Status", status(ctx))
            elseif action == "pause" then
                ctx.operator.paused = true
                if ctx.checkpoint then ctx.checkpoint("operator pause") end
                audit(ctx, sender, action, "event paused")
                reply(sender, requestId, true, "Event paused")
            elseif action == "resume" then
                ctx.operator.paused = false
                if ctx.checkpoint then ctx.checkpoint("operator resume") end
                audit(ctx, sender, action, "event resumed")
                reply(sender, requestId, true, "Event resumed")
            elseif action == "stage_set" then
                local value = tonumber(args.value)
                local stages = ctx.objective.captureZones or {}
                if not value or value ~= math.floor(value) or value < 1 or value > #stages then
                    reply(sender, requestId, false, "Invalid stage number")
                else
                    ctx.operator.stageRequest = value
                    if ctx.checkpoint then ctx.checkpoint("operator stage request") end
                    audit(ctx, sender, action, "stage " .. value .. " requested")
                    reply(sender, requestId, true, "Stage " .. value .. " requested")
                end
            elseif action == "quota_set" then
                local pool, value = tostring(args.pool or ""), tonumber(args.value)
                if not quotaPools(ctx)[pool] or not value or value < 0 or value > 10000 then
                    reply(sender, requestId, false, "Invalid quota pool or value")
                else
                    commands.exec("/scoreboard players set " .. pool .. " Troops_Strength " .. math.floor(value))
                    if ctx.checkpoint then ctx.checkpoint("operator quota change") end
                    audit(ctx, sender, action, pool .. "=" .. math.floor(value))
                    reply(sender, requestId, true, pool .. " set", { value = score(pool, "Troops_Strength") })
                end
            elseif action == "shutdown" then
                ctx.operator.shutdown = true
                if ctx.checkpoint then ctx.checkpoint("operator shutdown") end
                audit(ctx, sender, action, "graceful shutdown requested")
                reply(sender, requestId, true, "Event shutting down")
            elseif action == "reset_match" then
                ctx.operator.resetRequested = true
                ctx.operator.shutdown = true
                audit(ctx, sender, action, "new match reset requested")
                reply(sender, requestId, true, "Event stopped; restart once with resetSpawns and resetTanks enabled")
            else
                reply(sender, requestId, false, "Unsupported action")
            end
        end
    end
end

return service
