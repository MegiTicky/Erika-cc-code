--セットアップ
rednet.open("bottom")

bx,by,bz=commands.getBlockPosition()
mypos = { x = bx, y = by, z = bz } 
ds = 0
Zid = 1
Gm = 1

--範囲と更新
distance = 7
sleep_time =0.001

--チームの名前
attackteam = "Red"
defenseteam = "Blue"

--チケット管理コンピュータのid
ticketcomputerId = 2

--ゾーン進入時のスコア
defendr_in_score = -3
attacker_in_score = 2
other_score = -1

--ゾーン突破時のチケット増減
getticket = {
    { a = 100, d = -50}, 
    { a = 100, d = -50}, 
}


---占領地の座標
Dp = {
    { x = -38, y = 0, z = -125 }, 
    { x = -38, y = 0, z = -150 }, 
}
--攻撃側スポーンの座標
Asp = {
    { x = -40, y = 1, z = -111 }, 
    { x = -5, y = 15, z = 25 }, 
}
--防衛側スポーンの座標
Dsp= {
    { x = -40, y = 1, z = -111 }, 
    { x = -5, y = 15, z = 25 }, 
}



--起動前セットアップ
redstone.setAnalogOutput("back",15)
commands.exec("/setblock " ..Dp[Gm].x .." "..Dp[Gm].y .." "..Dp[Gm].z.." minecraft:beacon")


for i = 1, #Dp do
    commands.exec("/setblock " ..Dp[i].x .." "..Dp[i].y .." "..Dp[i].z.." air")
end
commands.exec("/setblock " ..Dp[Gm].x .." "..Dp[Gm].y .." "..Dp[Gm].z.." minecraft:beacon")

while true do


    attacker_in = commands.exec("execute as @a[team="..attackteam..",x=".. Dp[Gm].x ..",y=".. Dp[Gm].y ..",z=".. Dp[Gm].z ..",distance=.."..distance.."] at @s run effect give @s saturation 1")
    
    defendr_in = commands.exec("execute as @a[team="..defenseteam..",x=".. Dp[Gm].x ..",y=".. Dp[Gm].y ..",z=".. Dp[Gm].z ..",distance=.."..distance.."] at @s run effect give @s saturation 1")
    
    print(attacker_in)
   
    if defendr_in then
        ds = ds + defendr_in_score 
        print("defendr_in")
    elseif attacker_in then
        ds = ds + attacker_in_score
        print("attacker_in")
    else
        ds = ds + other_score
    end

    if ds < 0 then
        ds = 0
    end

    if ds >100 then
        ds = 0
        commands.exec("/setblock " ..Dp[Gm].x .." "..Dp[Gm].y .." "..Dp[Gm].z.." air")
        
        rednet.send(ticketcomputerId,"A".. getticket[Gm].a .."D"..getticket[Gm].d)--ticket送信
        
        redstone.setAnalogOutput("top",15)
        sleep(0)
        redstone.setAnalogOutput("top",0)


        if Gm == #Dp-1 then
            --
            sleep(1)
            redstone.setAnalogOutput("left",15)
            sleep(0.1)
            redstone.setAnalogOutput("left",0)
            
        elseif Gm == #Dp then
            redstone.setAnalogOutput("right",15)
            sleep(0.1)
            redstone.setAnalogOutput("right",0)


            while true do
                rednet.send(ticketcomputerId,"A0".."D".."-10")--ticket送信
                sleep(2)
                print("end")
            end
        end

        Gm = Gm+1

        commands.exec("/setblock " ..Dp[Gm].x .." "..Dp[Gm].y .." "..Dp[Gm].z.." minecraft:beacon")
    end

    -- ボスバーの更新コマンドを実行
    commands.exec("/bossbar set " .. Zid .. " value " .. ds)
    commands.exec("/spawnpoint @a[team="..attackteam.."] ".. Asp[Gm].x .." "..Asp[Gm].y .." "..Asp[Gm].z)
    commands.exec("/spawnpoint @a[team="..defenseteam.."] ".. Dsp[Gm].x .." "..Dsp[Gm].y .." "..Dsp[Gm].z)

    


end

