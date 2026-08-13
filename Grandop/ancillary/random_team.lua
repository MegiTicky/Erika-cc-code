-- Random team allocator (Command Computer)
-- Balanced: decide target sizes first, then randomize to match exactly

math.randomseed(os.epoch("utc"))

-- Helper: run a command and return ok, outputLines, affected
local function run(cmd)
	local ok, out, n = commands.exec(cmd) -- no leading slash
	if not ok then print("Command failed: "..cmd) end
	return ok, out, n
end

-- Ensure teams exist (safe to call repeatedly)
local function ensureTeams()
	run("team add Red")
	run("team add Blue")
	run("team modify Red color red")
	run("team modify Blue color blue")
    run("team modify Red nametagVisibility hideForOtherTeams")
    run("team modify Blue nametagVisibility hideForOtherTeams")
    run("gamerule naturalRegeneration false")
    run("gamerule limitF5 false")
end

-- Get online players via /list and parse names
local function getOnlinePlayers()
	local ok, out = run("list")
	if not ok or not out or #out == 0 then return {} end

	-- e.g. "There are 3 of a max of 20 players online: Alice, Bob, Charlie"
	local line = table.concat(out, " ")
	local names = line:match(":%s*(.*)")
	local players = {}
	if names and #names > 0 then
		for name in names:gmatch("([^,%s]+)") do
			table.insert(players, name)
		end
	end
	return players
end

-- Fisher-Yates shuffle
local function shuffle(t)
	for i = #t, 2, 1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

-- Assign everyone with exact balance (sizes differ by at most 1)
local function assignAllBalanced()
	ensureTeams()

	local players = getOnlinePlayers()
	if #players == 0 then
		print("No players online.")
		return
	end

	-- Decide exact sizes first
	local n = #players
	local base = math.floor(n / 2)
	local extra = n % 2

	-- Randomly choose which team gets the extra slot (when n is odd)
	local extraTeam = (math.random() < 0.5) and "Red" or "Blue"
	local target = { Red = base, Blue = base }
	if extra == 1 then target[extraTeam] = target[extraTeam] + 1 end

	-- Randomize player order
	shuffle(players)

	print(("Players: %d | Target Red=%d, Blue=%d"):format(n, target.Red, target.Blue))

	-- Assign first chunk to Red, remaining to Blue (or vice versa) to match targets
	local redAssigned = 0
	local blueAssigned = 0
	for i, name in ipairs(players) do
		local team
		-- Prefer filling whichever team has not reached its target yet
		if redAssigned < target.Red and blueAssigned < target.Blue then
			-- both have space: flip a coin to avoid bias
			team = (math.random() < 0.5) and "Red" or "Blue"
		elseif redAssigned < target.Red then
			team = "Red"
		else
			team = "Blue"
		end

		if team == "Red" then
			redAssigned = redAssigned + 1
		else
			blueAssigned = blueAssigned + 1
		end

		run(("team join %s %s"):format(team, name))
		print(("%s -> %s"):format(name, team))
	end

	print(("Done. Final Red=%d, Blue=%d"):format(redAssigned, blueAssigned))
end

assignAllBalanced()
