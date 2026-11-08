local mission = assert(loadfile('Grandop/missions/lieyu_siege.lua'))()
local answers = { '', 'abc', '0', '-1', '12.5' }
write = function() end
read = function() return table.remove(answers, 1) end
assert(mission.siege.squadSpawnInterval() == 40)
assert(mission.siege.squadSpawnInterval() == 12.5)
assert(#answers == 0)
print('SQUAD INTERVAL PROMPT PASS')
