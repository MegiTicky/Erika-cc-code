rednet.open("bottom")
--ticket管理コンピュータのid
ticketcomputerId = 2

--毎更新毎の攻撃防御側のチケット更新
timeticket = { a = -1, d = 0}

--毎更新にかかる時間
sleep_time = 1

while true do
    sleep(sleep_time)
    rednet.send(ticketcomputerId,"A".. timeticket.a .."D"..timeticket.d)
end
