rednet.open("bottom")

redstone.setAnalogOutput("top",15)
sleep(0.1)
redstone.setAnalogOutput("top",0)

--チームの名前
attackteam = "Red"
defenseteam = "Blue"

--初期チケット
attackteam_ticket = 500
defenseteam_ticket = 500


commands.exec("/scoreboard players set " .. attackteam .. " tickets " .. attackteam_ticket)
commands.exec("/scoreboard players set " .. defenseteam .. " tickets " .. defenseteam_ticket)

local receivedMessages = {} -- 受信したメッセージを一時的に保存するテーブル

local function processMessage(id, msg)
    local A_t, D_t = msg:match("A(-?%d+)D(-?%d+)")

    if A_t and D_t then  -- 受信したメッセージが正しい形式であるか確認
        if tonumber(A_t)<0 then
            commands.exec("/scoreboard players remove " .. attackteam .. " tickets " .. math.abs(A_t))
        else
            commands.exec("/scoreboard players add " .. attackteam .. " tickets " .. math.abs(A_t))
        end

        if tonumber(D_t)<0 then
            commands.exec("/scoreboard players remove " .. defenseteam .. " tickets " .. math.abs(D_t))
        else
            commands.exec("/scoreboard players add " .. defenseteam .. " tickets " .. math.abs(D_t))
        end


        print("Processed message from ID:", id)
    else
        print("Invalid message format from ID:", id)
    end
    if attackteam_ticket < 1 then
        redstone.setAnalogOutput("left",15)
        sleep(0.1)
        redstone.setAnalogOutput("left",0)
    end
    if defenseteam_ticket < 1 then

        redstone.setAnalogOutput("right",15)
        sleep(0.1)
        redstone.setAnalogOutput("right",0)

    end

end

while true do
    local id, msg = rednet.receive(0) -- timeout を 0 に設定し、ブロックせずに受信

    if id then
        table.insert(receivedMessages, { id = id, msg = msg }) -- 受信したメッセージをテーブルに追加
    end

    -- 受信したメッセージを順番に処理
    for i, data in ipairs(receivedMessages) do
        processMessage(data.id, data.msg)
        table.remove(receivedMessages, i) -- 処理済みのメッセージを削除
    end
end
