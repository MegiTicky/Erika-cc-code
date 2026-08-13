-- Mission: Conquest (single neutral control point with ticket drain).

return {
    id = "conquest",
    name = "Conquest",

    objective = {
        type = "control_point",

        zonePos = { x = 6512, y = 24, z = 6430 },
        blueSpawn = { x = 6436, y = 232, z = 6631 },
        redSpawn = { x = 6442, y = 232, z = 6631 },
        blueTeam = "Blue",
        redTeam = "Red",

        captureRange = 40,
        updateInterval = 0.5,
        ticketDrain = 1,
        maxProgress = 200,
        capRate = 10,
        decapRate = 10,
        decayRate = 2,
        bossbarId = "capturebar",
        startTickets = 750,
    },
}
