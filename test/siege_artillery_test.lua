local clock, notices, shots, logs = 0, {}, {}, {}
os.epoch = function() return clock * 1000 end
commands = { exec = function(cmd) notices[#notices + 1] = cmd return true end }
local players = { {name='Near',x=100,z=0}, {name='Far',x=151,z=0} }
local mc = { playerPositions = function(team, exclude) assert(team == 'Blue' and exclude); return players end }
local art = { fireShell = function(job) shots[#shots + 1] = {t=clock,x=job.x,z=job.z,pattern=job.pattern}; return true end }
function grandopRequire(name) if name == 'lib.minecraft' then return mc elseif name == 'lib.artillery' then return art end error(name) end
local mod = assert(loadfile('Grandop/lib/siege/artillery.lua'))()
local function fresh()
  clock, notices, shots, logs = 0, {}, {}, {}
  players = { {name='Near',x=100,z=0}, {name='Far',x=151,z=0} }
  local siege = { defenderTeam='Blue', objective={captureZones={{x=0,z=0}}}, enemyArtillery={barrages={[4]=1,[5]=2,[6]=2}, delay=30, interval=30, radius=150} }
  local ctx = {operator={paused=false,shutdown=false}, log=function(s) logs[#logs+1]=s end}
  return mod.new(siege,ctx), ctx, siege
end
local function tick(s,t) clock=t; assert(s.tick(t)) end
for _,wave in ipairs({4,5,6}) do
  local s = fresh(); s.startWave(wave)
  tick(s,29); assert(#notices==0)
  tick(s,30); assert(#notices==1 and #shots==0)
  tick(s,44); assert(#shots==0)
  tick(s,45); tick(s,46); tick(s,47)
  assert(#shots==3 and shots[1].x==100 and shots[1].pattern=='area' and shots[1].t==45)
  tick(s,60); assert(#notices==(wave==4 and 1 or 2))
  if wave~=4 then tick(s,75); tick(s,76); tick(s,77); assert(#shots==6) end
end
do local s=fresh(); s.startWave(5); tick(s,30); s.endWave(5); tick(s,45); tick(s,46); tick(s,47); tick(s,61); assert(#notices==1 and #shots==3) end
do local s=fresh(); players={}; s.startWave(4); tick(s,30); tick(s,60); assert(#notices==0 and #shots==0) end
do local s,c=fresh(); s.startWave(4); tick(s,10); c.operator.paused=true; tick(s,11); tick(s,110); c.operator.paused=false; tick(s,111); tick(s,130); assert(#notices==0); tick(s,131); assert(#notices==1) end
do local s,c=fresh(); s.startWave(4); tick(s,30); c.operator.shutdown=true; clock=45; assert(not s.tick(45) and #shots==0) end
do local s,c,mission=fresh(); s.startWave(4); tick(s,30); mission.objective.runtimeState={ended=true}; clock=45; assert(not s.tick(45) and #shots==0) end
print('SIEGE ARTILLERY PASS')
