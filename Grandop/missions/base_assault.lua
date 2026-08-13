-- Mission: Base assault (two-team, capture the enemy base to win).

return {
    id = "base_assault",
    name = "Base Assault",

    objective = {
        type = "base_assault",

        blueTeam = "Blue",
        redTeam = "Red",
        blueSpawn = { x = 4243, y = 307, z = 6653 },
        redSpawn = { x = 4237, y = 307, z = 6653 },

        captureRange = 40,
        updateInterval = 0.5,
        maxProgress = 200,
        capRate = 1,
        decapRate = 1,
        stall = 1,

        bases = {
            blue = {
                pos = { name = "Blue Base", x = 4528, y = 18, z = 6458 },
                owner = "Blue",
                prog = 0,
                barId = "bluebasebar",
            },
            red = {
                pos = { name = "Red Base", x = 5778, y = 22, z = 5401 },
                owner = "Red",
                prog = 0,
                barId = "redbasebar",
            },
        },
    },
}
