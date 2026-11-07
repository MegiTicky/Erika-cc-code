-- Focused desktop checks for artillery spotter constants and pure vector math.
local source = assert(loadfile("Grandop/lib/artillery_spotter.lua"))
commands = { exec = function() return false end }
textutils = { serialiseJSON = function() return "{}" end }
local spotter = source()
assert(spotter._test.shellFor[1] == "he")
assert(spotter._test.shellFor[2] == "smoke")
assert(spotter._test.countFor[1] == 3)
assert(spotter._test.countFor[2] == 6)
assert(spotter._test.patternFor[1] == "concentrated")
assert(spotter._test.patternFor[2] == "area")
print("ARTILLERY SPOTTER CONSTANTS PASS")
