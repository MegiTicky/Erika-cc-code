rednet.open("bottom")

attackteam = "Red"
defenseteam = "Blue"

-- Initialize death counters for each team
A_t = 0
D_t = 0

ticketcomputerId = 2

bx, by, bz = commands.getBlockPosition()
mypos = { x = bx, y = by, z = bz }

redstone.setAnalogOutput("top", 15)

while true do
    -- Reset death counts every iteration
    A_t = 0
    D_t = 0
    send_f = false

    -- Track attacker deaths
    for i = 1, #attackerDeathticket do
        -- Remove 1 death from the attacker team when their death score increases
        Adead = commands.exec("execute as @a[tag=INF-" .. i .. ",team=" .. attackteam .. ",scores={teamDeath=1..}] at @s run scoreboard players remove @s teamDeath 1")
        if Adead then
            A_t = A_t + attackerDeathticket[i] -- Add the corresponding death value
            send_f = true
        end
    end

    -- Track defender deaths
    for i = 1, #defenderDeathticket do
        Ddead = commands.exec("execute as @a[tag=INF-" .. i .. ",team=" .. defenseteam .. ",scores={teamDeath=1..}] at @s run scoreboard players remove @s teamDeath 1")
        if Ddead then
            D_t = D_t + defenderDeathticket[i] -- Add the corresponding death value
        end
    end

    -- Send the death count data to the ticket computer
    if send_f then
        rednet.send(ticketcomputerId, "A" .. A_t .. "D" .. D_t)
    end

    -- Update the sidebar with the death count of each team
    commands.exec("scoreboard objectives setdisplay sidebar teamDeaths")

    -- You can update the display with the actual values if needed (example for displaying counts):
    commands.exec("scoreboard players set @a[team=" .. attackteam .. "] teamDeaths " .. A_t)
    commands.exec("scoreboard players set @a[team=" .. defenseteam .. "] teamDeaths " .. D_t)

    sleep(1)  -- Adjust the delay as needed
end
