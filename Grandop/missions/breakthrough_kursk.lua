-- Mission: Battle of Kursk breakthrough
-- Objective mode: staged capture (forward only), no modem stage broadcast.

return {
    id = "breakthrough_kursk",
    name = "Kursk Breakthrough",

    objective = {
        type = "staged_capture",
        bossbarId = 1,
        attackTeam = "Red",
        defenseTeam = "Blue",
        ticketComputerId = 2,
        startZone = 1,

        captureZones = {
            { x = 913, y = 4, z = 2069 },
            { x = 852, y = 4, z = 1771 },
        },

        attackerSpawns = {
            { x = 762, y = 158, z = 1690 },
            { x = 762, y = 158, z = 1699 },
        },
        defenderSpawns = {
            { x = 762, y = 158, z = 1712 },
            { x = 762, y = 158, z = 1721 },
        },

        ticketRewards = {
            { a = 100, d = -50 },
            { a = 100, d = -50 },
        },

        capture = {
            mode = "forward",
            radius = 20,
            updateInterval = 0.001,
            threshold = 200,
            maxValue = 100,
            attackScore = 1,
            defenseScore = -1,
            neutralScore = -1,
            skipCooldown = 3,
        },
    },
}
