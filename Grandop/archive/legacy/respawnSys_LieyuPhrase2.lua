local monitor = peripheral.find("monitor")
local radar = peripheral.find("sp_radar")
local modem = peripheral.find("modem")


if not monitor then error("Monitor not found!") end
if not radar then error("Radar not found!") end
if not modem then error("Modem (wireless or wired) not found!") end

monitor.clear()
monitor.setTextScale(0.5)
--============--
--Tank related--
--============--
local defaultTanksList = {
    germany = {
        tigeri   = { stock = 1, cooldown = 180, buffer = 1 },
        panther  = { stock = 5, cooldown = 120, buffer = 2 }, -- 2x burst
        panzer4 = { stock = 8, cooldown = 60,  buffer = 9999 }
    },
    allied = {
        sherman75     = { stock = 11, cooldown = 3, buffer = 1 },
        shermanfirefly       = { stock = 2, cooldown = 60, buffer = 1 },
        churchillvii = { stock = 2, cooldown = 60, buffer = 1 }
    },
    japan = {
        --[[chiha  = { stock = 10, cooldown = 1,  buffer = 1 },
        chinu  = { stock = 2,  cooldown = 100, buffer = 1 },
        chihalg= { stock = 1,  cooldown = 120, buffer = 1 },
        horo   = { stock = 1,  cooldown = 100, buffer = 1 }]]
        chinu  = { stock = 2, cooldown = 180,  buffer = 1 },
        horo   = { stock = 1,  cooldown = 180, buffer = 1 }
    },
    USMC = {
        --[[m3gmc         = { stock = 4, cooldown = 1,  buffer = 1 },
        sherman75     = { stock = 4, cooldown = 1,  buffer = 1 },
        sherman75deco = { stock = 7, cooldown = 1,  buffer = 1 },
        sherman75usmc = { stock = 4, cooldown = 1,  buffer = 1 },
        sherman76 = { stock = 6, cooldown = 60,  buffer = 1 },
        churchill7 = { stock = 1, cooldown = 60,  buffer = 1 }]]
        sherman75usmc = { stock = 3, cooldown = 180,  buffer = 1 },
    }
}
local repairKits = {
    { id = "trackwork:suspension_track", count = 64 },
    { id = "trackwork:phys_track", count = 16 },
    { id = "create:wrench", count = 1 },
    { id = "create:copycat_panel", count = 64 },
    { id = "s_a_b:hardsteelblockpanzer", count = 64 },
    { id = "create:shaft", count = 32 },
    { id = "tallyho:scope_block", count = 2 },
    { id = "create:analog_lever", count = 32 },
    { id = "vs_clockwork:gravitron", count = 1 },
    { id = "combatgear:pillsui", count = 1}    
}

-- Reserve area
local reserveCord = {
    x = 1572,
    y = 90,
    z = 6280
}
-- Map of players and their current tank
local playerTankMap = {}
local availableTanks = {}

-- Define point grid
local numPointsX = 3  -- adjust how many points in X
local numPointsZ = 3  -- adjust how many points in Z
local spacing = 20    -- distance between points

--========--
--infantry--
--========--
local infantrySpawns = {
    germany = {
        [1] = { {name="G_S1 Trench", x=5800,y=40,z=6500}, {name="G_S1 Forest", x=5825,y=40,z=6520} },
        [2] = { {name="G_S2 Ruins",  x=5930,y=42,z=6600}, {name="G_S2 Road",   x=5960,y=42,z=6630} },
    },
    allied = {
        [1] = { {name="A_S1 Beach",  x=7080,y=28,z=6460}, {name="A_S1 Cliff",  x=7110,y=30,z=6485} },
        [2] = { {name="A_S2 Depot",  x=7200,y=29,z=6550}, {name="A_S2 Yard",   x=7230,y=29,z=6575} },
    },
    japan = {
        [1] = { {name="Town X",  x=4836,y=20,z=6160}, {name="Town Y",  x=4711,y=17,z=5925}, {name="Town Z", x=4815, y=29, z=5561} },
        [2] = { {name="Town X",  x=4836,y=20,z=6160}, {name="Town Y",  x=4711,y=17,z=5925}, {name="Town Z", x=4815, y=29, z=5561} },
        [3] = { {name="Town X",  x=4836,y=20,z=6160}, {name="Town Y",  x=4711,y=17,z=5925}, {name="Town Z", x=4815, y=29, z=5561} }
    },
    USMC = {
        [1] = { {name="S1 Main Town",  x=4592,y=18,z=6411}, {name="USCommander",  x=0,y=0,z=0} },
        [2] = { {name="S2 Town X",  x=4825,y=19,z=6149}, {name="USCommander",  x=0,y=0,z=0} },
        [3] = { {name="S3 Town Y",  x=4735,y=20,z=5881}, {name="USCommander",  x=0,y=0,z=0} }

    }
}

local townRespawnQuota = {
    ["Town X"] = 30,
    ["Town Y"] = 30,
    ["Town Z"] = 40
}

-- Keep track of the number of respawns per town
local townRespawnCount = {
    ["Town X"] = 0,
    ["Town Y"] = 0,
    ["Town Z"] = 0
}

-- Global respawn quota for USMC (maximum of 100 respawns anywhere)
local USMCRespawnQuota = 100
local USMCRespawnCount = 0

--=== infantry classes & kits ===--
local infantryClasses = { "assault","engineer","medic","commander","machine_gunner" }

-- Put your real items here. Examples are placeholders.
local infantryKitsWithCooldown = {
    japan = {
        assault = {
            -- Armor
            "/item replace entity @p armor.chest with combatgear:wwi_chestplate{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.head with combatgear:pacific_helmet{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.legs with combatgear:drab_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            -- Food
            "/give @p combatgear:rations 32",
            -- Main Weapon
            "/give @p pointblank:type38",
            -- Secondary Weapon (Knife)
            "/give @p combatgear:knife",
            -- Ammo
            "/give @p pointblank:ammocreative 64",
            -- Special Gadgets
            "/give @p smallarm:lunge_mine",
            "/give @p cgm:grenade 3",
            cooldown = 0  -- Cooldown in seconds
        },
        engineer = {
            -- Armor
            "/item replace entity @p armor.chest with combatgear:wwi_chestplate{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.head with combatgear:pacific_helmet{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.legs with combatgear:drab_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            -- Food
            "/give @p combatgear:rations 32",
            -- Main Weapon
            "/give @p pointblank:type38",
            -- Secondary Weapon (Knife)
            "/give @p combatgear:knife",
            -- Ammo
            "/give @p pointblank:ammocreative 64",
            -- Special Gadgets
            "/give @p trackwork:med_phys_track 8",
            "/give @p trackwork:med_suspension_track 24",
            "/give @p create:redstone_link 64",
            "/give @p copycats:copycat_layer 64",
            "/give @p crusty_chunks:sand_bags 32",
            "/give @p minecraft:iron_shovel",
            "/give @p combatgear:landmine 2",
            "/give @p vs_tournament:explosive_instant_small 2",
            "/give @p create_tweaked_controllers:tweaked_linked_controller",
            "/give @p create:wrench",
            cooldown = 0  -- Cooldown in seconds
        },
        medic = {
            -- Armor
            "/item replace entity @p armor.chest with combatgear:wwi_chestplate{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.head with combatgear:pacific_helmet{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.legs with combatgear:drab_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            -- Food
            "/give @p combatgear:rations 32",
            -- Main Weapon
            "/give @p pointblank:ribeyrolles{display:{Name:'{\"text\":\"Type 100\",\"italic\":false}'}}",
            -- Secondary Weapon (Knife)
            "/give @p combatgear:knife",
            -- Ammo
            "/give @p pointblank:ammocreative 128",
            -- Special Gadgets
            "/give @p smallarm:smoke_grenade 8",
            "/give @p combatgear:bandages 16",
            "/give @p combatgear:medpack 2",
            "/give @p minecraft:snowball{display:{Name:'{\"text\":\"Heal ball\",\"italic\":false}'},Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]} 6",
            cooldown = 0  -- Cooldown in seconds
        },
        commander = {
            -- Armor
            "/item replace entity @p armor.chest with combatgear:wwi_chestplate{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.head with combatgear:tankcap_helmet{Enchantments:[{id:\"minecraft:projectile_protection\",lvl:2s},{id:\"minecraft:vanishing_curse\",lvl:1s}]} 1",
            "/item replace entity @p armor.legs with combatgear:drab_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            -- Food
            "/give @p combatgear:rations 32",
            -- Main Weapon
            "/give @p pointblank:type38",
            -- Secondary Weapon (Luger P08 for Commander)
            "/give @p pointblank:lugerp08",
            "/give @p combatgear:katanan",
            -- Ammo
            "/give @p pointblank:ammocreative 128",
            -- Special Gadgets
            "/give @p combatgear:bandages 8",
            "/give @p combatgear:stimpack",
            cooldown = 0  -- Cooldown in seconds
        },
        machine_gunner = {
            -- Armor
            "/item replace entity @p armor.chest with combatgear:wwi_chestplate{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.head with combatgear:pacific_helmet{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.legs with combatgear:drab_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            -- Food
            "/give @p combatgear:rations 32",
            -- Main Weapon
            "/give @p pointblank:madsen{display:{Name:'{\"text\":\"Type 97\"}'}}",
            -- Secondary Weapon (Knife)
            "/give @p combatgear:knife",
            -- Ammo
            "/give @p pointblank:ammocreative 256",
            -- Special Gadgets
            "/effect give @p minecraft:slowness infinite 2",
            cooldown = 90  -- Cooldown in seconds
        }
    },
    USMC = {
        assault = { 
            "/item replace entity @p armor.chest with crusty_chunks:flame_thrower_tank_chestplate{Fluid: 1000}",
            "/item replace entity @p armor.head with combatgear:snow_helmet{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.legs with combatgear:pacific_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/give @p pointblank:tw_m1_garand",
            "/give @p crusty_chunks:flame_thrower_animated",
            "/give @p combatgear:knife",
            "/give @p combatgear:rations 8",
            "/give @p pointblank:ammocreative 64",
            "/give @p cgm:grenade 3",
            cooldown = 0  -- Cooldown in seconds
        },
        engineer = {
            "/item replace entity @p armor.chest with combatgear:pacific_chestplate{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.head with combatgear:snow_helmet{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.legs with combatgear:pacific_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/give @p pointblank:htg_thompson1928",
            "/give @p combatgear:rations 8",
            "/give @p pointblank:ammocreative 128",
            "/give @p trackwork:med_phys_track 8",
            "/give @p trackwork:med_suspension_track 24",
            "/give @p create:redstone_link 64",
            "/give @p copycats:copycat_layer 64",
            "/give @p crusty_chunks:sand_bags 32",
            "/give @p minecraft:iron_shovel",
            "/give @p combatgear:knife",
            "/give @p vs_tournament:explosive_instant_small 3",
            "/give @p tnt 3",
            "/give @p lever 32",
            cooldown = 0  -- Cooldown in seconds
        },
        medic = {
            "/item replace entity @p armor.chest with combatgear:pacific_chestplate{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.head with combatgear:snow_helmet{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.legs with combatgear:pacific_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/give @p pointblank:htg_thompson1928",
            "/give @p minecraft:snowball{display:{Name:'{\"text\":\"Heal ball\",\"italic\":false}'},Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]} 6",
            "/give @p combatgear:knife",
            "/give @p combatgear:rations 32",
            "/give @p pointblank:ammocreative 128",
            "/give @p smallarm:smoke_grenade 8",
            "/give @p combatgear:bandages 16",
            "/give @p combatgear:medpack 2",
            cooldown = 0  -- Cooldown in seconds
        },
        commander = {
            "/item replace entity @p armor.chest with combatgear:pacific_chestplate{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.head with combatgear:tankcap_helmet{Enchantments:[{id:\"minecraft:projectile_protection\",lvl:2s},{id:\"minecraft:vanishing_curse\",lvl:1s}]} 1",
            "/item replace entity @p armor.legs with combatgear:pacific_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/give @p pointblank:tw_m1_garand",
            "/give @p combatgear:knife",
            "/give @p combatgear:rations 32",
            "/give @p pointblank:ammocreative 128",
            "/give @p pointblank:m1911a1",
            "/give @p combatgear:bandages 8",
            "/give @p computercraft:computer_advanced{ComputerId: 0}",
            "/give @p computercraft:wireless_modem_advanced",
            "/give @p combatgear:stimpack",
            cooldown = 0  -- Cooldown in seconds
        },
        machine_gunner = {
            "/item replace entity @p armor.chest with combatgear:pacific_chestplate{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.head with combatgear:snow_helmet{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.legs with combatgear:pacific_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/give @p pointblank:barm1918{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/give @p pointblank:ammocreative 256",
            "/give @p combatgear:rations 32",
            "/effect give @p minecraft:slowness infinite 2",
            cooldown = 60  -- Cooldown in seconds
        },
        anti_tank = {
            "/item replace entity @p armor.chest with combatgear:pacific_chestplate{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.head with combatgear:snow_helmet{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.legs with combatgear:pacific_leggings{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/item replace entity @p armor.feet with combatgear:pacific_boots{Enchantments:[{id:\"minecraft:vanishing_curse\",lvl:1s}]}",
            "/give @p smallarm:m72_law{display:{Name:'{\"text\":\"M1 Bazooka\",\"italic\":false}'},AmmoCount:1}",
            "/give @p smallarm:m72_law_rocket",
            "/give @p pointblank:m1911a1",
            "/give @p pointblank:ammocreative 64",         
            "/give @p combatgear:rations 32",     
            cooldown = 90        
        }
    }
}
local kitCooldowns = {}

--===============--
--helper function--
--===============--
local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

-- Improved printMonitor with wrapping
local function printMonitor(text)
    local w, h = monitor.getSize()
    local x, y = monitor.getCursorPos()

    while #text > 0 do
        local line = text
        if #line > w then
            line = text:sub(1, w)
            text = text:sub(w + 1)
        else
            text = ""
        end

        monitor.setCursorPos(1, y)
        monitor.clearLine()
        monitor.write(line)
        y = y + 1
        if y > h then
            monitor.clear()
            y = 1
        end
    end

    monitor.setCursorPos(1, y)
end

local closetPlayerName = "Not detected"
local function getClosestUserName()
    while true do
        local radarResult = radar.scanForPlayers(20)
        local closestDistance = math.huge
        local closetPlayerPos
        local computerPosX ,computerPosY,computerPosZ = commands.getBlockPosition()
        for _, player in pairs(radarResult) do
            if player and player.pos then
                local dx = player.pos[1] - computerPosX
                local dy = player.pos[2] - computerPosY
                local dz = player.pos[3] - computerPosZ
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                -- If this player is closer than the current closest, update the closest target
                if distance < closestDistance then
                    closestDistance = distance
                    closetPlayerPos = player.pos
                    closetPlayerName = player.nickname
                end
            end
        end
        if not closetPlayerName then
            print("Increase radar scan distance in config, cannot detect players")
        end
        --print(closetPlayerName)
        sleep(0.2)
    end
end

--=== modem / stage ===--


local STAGE_CHANNEL = 125     -- <-- set this to match your capture broadcaster
modem.open(STAGE_CHANNEL)
local currentStage = 1
local function listenStage()
    while true do
        local ev, side, ch, rch, msg = os.pullEvent("modem_message")
        if ch == STAGE_CHANNEL then
            -- Accept plain numbers or a table {stage=number}
            if type(msg) == "number" then
                currentStage = msg
            elseif type(msg) == "table" and tonumber(msg.stage) then
                currentStage = tonumber(msg.stage)
            end
            -- Optional: show it on server
            print("Stage update -> " .. tostring(currentStage))
        end
    end
end
--===========--
--file system--
--===========--
-- Function to save tanksList to a file
local function saveTanksListToFile(filename, tanksList)
    local file = fs.open(filename, "w")
    file.write(textutils.serialize(tanksList))
    file.close()
end

-- Function to load tanksList from a file
local function loadTanksListFromFile(filename)
    if fs.exists(filename) then
        local file = fs.open(filename, "r")
        local content = file.readAll()
        file.close()
        return textutils.unserialize(content)
    else
        return nil  -- Return nil if the file doesn't exist
    end
end

intializeSpawnInfantrySpawn = false
-- Function to prompt the user for a reset option
local function promptReset()
    print("Do you want to reset the tank list and overwrite the file? (y/n): ")
    local input = io.read()
    if input == "y" or input == "Y" then
        -- Save default tanksList to file
        saveTanksListToFile("tanksList.txt", defaultTanksList)
        print("Tank list has been reset!")
    else
        print("Loading the existing tank list from file...")
    end

    print("Do you want to reset the infantry spawn count? (y/n): ")
    local input = io.read()
    if input == "y" or input == "Y" then
        -- Save default tanksList to file
        intializeSpawnInfantrySpawn = true
        print("Reseted the spawn count score board")
    else
        print("Loading the existing spawn count")
    end
end

-- Prompt for reset at the start of the program
promptReset()

-- Load the tanksList from the file if it exists
local tanksList = loadTanksListFromFile("tanksList.txt") or defaultTanksList
--===========--
--Setup phase--
--===========--
print("=== Tank Teleportation System ===")
-- Get the list of countries dynamically from tanksList
local countries = {}
for country, _ in pairs(tanksList) do
    table.insert(countries, country)
end

local country = nil
repeat
    print("Select your country:")

    -- Display country options
    for i, country in ipairs(countries) do
        print(i .. ". " .. country)
    end

    io.write("Enter a number from 1 to " .. #countries .. ": ")
    local input = io.read()
    local selectedIndex = tonumber(input)

    -- Check if the input is valid
    if selectedIndex and selectedIndex >= 1 and selectedIndex <= #countries then
        country = countries[selectedIndex]
        print("You selected " .. country)
    else
        print("Invalid selection! Please choose a valid number from the list.")
    end
until country


local defaultCoords = {
    germany = {
        { name = "Main", x = 5847, y = 38, z = 6540 }
    },
    allied = {
        { name = "Main", x = 7094, y = 28, z = 6473 }
    },
    japan = {
        { name = "S1 Town Spawn", x = 6068, y = 27, z = 5417 },
        { name = "S2 Hill Top", x = 5401, y = 62, z = 4658 },
        { name = "S3 West Plane", x = 4747, y = 21, z = 4602 }
    },
    USMC = {
        { name = "Main spawn", x = 4293, y = 23, z = 6700 }
    }
}

local function generateGridPoints(centerX, centerY, centerZ)
    local result = {}
    for ix = 1, numPointsX do
        for iz = 1, numPointsZ do
            local offsetX = (ix - math.ceil(numPointsX / 2)) * spacing
            local offsetZ = (iz - math.ceil(numPointsZ / 2)) * spacing
            table.insert(result, {
                x = centerX + offsetX,
                y = centerY,
                z = centerZ + offsetZ
            })
        end
    end
    return result
end

local currentPointIndex = 1

-- Create spawn point selection function:
local function selectSpawnPoint()
    monitor.clear()
    monitor.setCursorPos(1,1)
    printMonitor("Select Spawn Location:")

    local spawnPoints = defaultCoords[country]
    local y = 2
    local buttonMap = {}

    for i, point in ipairs(spawnPoints) do
        monitor.setCursorPos(2, y)
        monitor.write("[" .. point.name .. "]")
        buttonMap[y] = point
        y = y + 2
    end

    monitor.setCursorPos(2, y)
    monitor.write("[ Cancel ]")
    buttonMap[y] = "cancel"

    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        local selection = buttonMap[y]
        if selection == "cancel" then
            return nil
        elseif selection then
            return selection
        end
    end
end

local function confirmSelection(tankName)
    monitor.clear()
    printMonitor("You selected: " .. tankName)
    printMonitor("")
    printMonitor("Touch one of the options below:")

    local confirmY = 6
    local cancelY = 8

    monitor.setCursorPos(2, confirmY)
    monitor.write("[ Confirm ]")

    monitor.setCursorPos(2, cancelY)
    monitor.write("[ Cancel ]")

    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        if y == confirmY then
            return true
        elseif y == cancelY then
            return false
        end
    end
end

local function manageCreativeArea()
    local insidePlayers = {}
    local radius = 50

    -- Build a flat list of all possible creative areas
    local creativeZones = {}
    for _, point in ipairs(defaultCoords[country]) do
        table.insert(creativeZones, {
            name = point.name,
            x = point.x,
            y = point.y,
            z = point.z
        })
    end

    while true do
        local radarResult = radar.scanForPlayers(9999)
        local newInside = {}

        for _, player in ipairs(radarResult) do
            local px, py, pz = player.pos[1], player.pos[2], player.pos[3]
            local name = player.nickname
            local isInsideAny = false

            for _, zone in ipairs(creativeZones) do
                local dx = px - zone.x
                local dy = py - zone.y
                local dz = pz - zone.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                if distance <= radius then
                    isInsideAny = true
                    break
                end
            end

            if isInsideAny then
                newInside[name] = true
                if not insidePlayers[name] then
                    commands.exec("gamemode creative " .. name)
                    print("Set creative: " .. name)
                end
            else
                if insidePlayers[name] then
                    commands.exec("gamemode survival " .. name)
                    print("Set survival: " .. name)
                end
            end
        end

        insidePlayers = newInside
        sleep(1)
    end
end
--=================--
--infantry function--
--=================--
-- Fallback if a country has no coords
local function ensureCoordsFor(country)
    if not defaultCoords[country] or #defaultCoords[country] == 0 then
        local cx, cy, cz = commands.getBlockPosition()
        defaultCoords[country] = { { name = "Main", x = cx, y = cy, z = cz } }
    end
    return defaultCoords[country]
end

local function getStageSpawns(country)
    local c = infantrySpawns[country]
    if c and c[currentStage] and #c[currentStage] > 0 then
        return c[currentStage]
    end
    -- fallback to your vehicle default coords if nothing set for stage
    return ensureCoordsFor(country)
end

local function selectMode()
    monitor.clear()
    monitor.setCursorPos(1,1)
    printMonitor("Select Mode:")
    local yTank, yInf = 3, 5
    monitor.setCursorPos(2, yTank); monitor.write("[ Tank ]")
    monitor.setCursorPos(2, yInf ); monitor.write("[ Infantry ]")
    while true do
        local ev, side, x, y = os.pullEvent("monitor_touch")
        if y == yTank and x >= 2 and x <= 9 then return "tank" end
        if y == yInf  and x >= 2 and x <= 12 then return "infantry" end
    end
end

-- Function to check if a specific kit is ready to use
local function isKitReady(kitName)
    local currentTime = os.epoch("utc") / 1000  -- Current time in seconds
    local kit = infantryKitsWithCooldown[country][kitName]
    if not kit then return false end  -- No kit found for this class

    -- If the kit has been used before, check the cooldown
    local lastUsed = kitCooldowns[kitName] or 0
    local cooldown = kit.cooldown
    if currentTime - lastUsed >= cooldown then
        return true  -- The kit is ready to use
    else
        return false  -- The kit is still on cooldown
    end
end

local function useKit(kitName)
    local currentTime = os.epoch("utc") / 1000  -- Current time in seconds
    kitCooldowns[kitName] = currentTime  -- Set the last used time to now

    -- Now execute the stored commands
    local kit = infantryKitsWithCooldown[country][kitName]
    if kit then
        for _, command in ipairs(kit) do
            -- Execute each command, replacing %s with the player name
            local finalCommand = command:format(closetPlayerName)
            commands.exec(finalCommand)
        end
    end
end

-- Function to display the cooldown status of the selected kit
local function displayKitCooldownStatus(kitName)
    monitor.clear()
    monitor.setCursorPos(1,1)

    print(textutils.serialize(kitCooldowns))
    local currentTime = os.epoch("utc") / 1000
    local lastUsed = kitCooldowns[kitName] or 0
    local timeLeft = math.floor(infantryKitsWithCooldown[country][kitName].cooldown - (currentTime - lastUsed))

    print(country,kitName,currentTime,lastUsed, timeLeft)

    -- Show whether the kit is ready or on cooldown
    if isKitReady(kitName) then
        monitor.write(kitName .. " ready")
        sleep(1)
    else
        monitor.write(kitName .. " is on cooldown. Time left: " .. timeLeft .. "s")
        sleep(2)
    end
end

-- Function to select Infantry class and show cooldown status
local function selectInfantryClass()
    monitor.clear()
    monitor.setCursorPos(1,1)
    printMonitor("Choose Class:")

    local y = 3
    local rowMap = {}

    -- Display infantry class options
    for clsName, kitDetails in pairs(infantryKitsWithCooldown[country]) do
        -- Display class name
        monitor.setCursorPos(2, y)
        monitor.write("[" .. clsName .. "]")  -- clsName is the name of the class/kit
        rowMap[y] = clsName  -- Store the class name in the rowMap
        y = y + 2
    end

    -- Display the Cancel button
    monitor.setCursorPos(2, y)
    monitor.write("[ Cancel ]")
    rowMap[y] = "cancel"  -- Store cancel button in rowMap

    while true do
        local ev, side, x, ry = os.pullEvent("monitor_touch")

        -- Check if the cancel button is pressed
        if rowMap[ry] == "cancel" then
            return nil  -- Return nil when the cancel button is pressed
        end

        -- Return the selected class when one of the class options is pressed
        if rowMap[ry] then
            -- Display cooldown status for the selected class's kit
            displayKitCooldownStatus(rowMap[ry])
            return rowMap[ry]
        end
    end
end
-- Function to handle kit selection with cooldown check
local function handleInfantryKit(player, class)
    -- Check if the kit is ready, and if yes, give the kit and start cooldown
    if isKitReady(class) then
        useKit(class)
        print(class .. " kit used!")
    else
        print(class .. " kit is on cooldown. Please wait.")
    end
end

if intializeSpawnInfantrySpawn then
    -- Create the 'spawnCount' scoreboard
    commands.exec("/scoreboard objectives add spawnCount dummy")

    -- Create the teams for each country/town
    commands.exec("/team add USMC")
    commands.exec("/team add TownX_JP")
    commands.exec("/team add TownY_JP")
    commands.exec("/team add TownZ_JP")
    -- Initialize the spawn count for each team (set initial spawn count to 0)
    commands.exec("/scoreboard players set USMC spawnCount 0")
    commands.exec("/scoreboard players set TownX_JP spawnCount 0")
    commands.exec("/scoreboard players set TownY_JP spawnCount 0")
    commands.exec("/scoreboard players set TownZ_JP spawnCount 0")
end

-- Function to check if a country/town has respawn quota remaining based on the scoreboard
local function hasRespawnQuota(country, townName)
    local remainingQuota = 0
    local _,_,XSpawnCount = commands.exec("/scoreboard players get TownX_JP spawnCount")
    local _,_,YSpawnCount = commands.exec("/scoreboard players get TownY_JP spawnCount")
    local _,_,ZSpawnCount = commands.exec("/scoreboard players get TownZ_JP spawnCount")
    local _,_,USMCSpawnCount = commands.exec("/scoreboard players get USMC spawnCount")
    if country == "USMC" then
        -- Get the current spawn count for the USMC team
        remainingQuota = USMCRespawnQuota - USMCSpawnCount
    elseif townName == "Town X" then
        -- Get the current spawn count for the respective town team
        remainingQuota = townRespawnQuota[townName] - XSpawnCount
    elseif townName == "Town Y" then
        -- Get the current spawn count for the respective town team
        remainingQuota = townRespawnQuota[townName] - YSpawnCount
    elseif townName == "Town Z" then
        -- Get the current spawn count for the respective town team
        remainingQuota = townRespawnQuota[townName] - ZSpawnCount
    end

    return remainingQuota > 0
end

-- Function to decrement the respawn count using the scoreboard
local function decrementRespawnQuota(country, townName)
    if country == "USMC" then
        local _,_,currentCount = commands.exec("/scoreboard players get USMC spawnCount")
        if currentCount < USMCRespawnQuota then
            -- Increment the spawn count for USMC
            commands.exec("/scoreboard players add USMC spawnCount 1")
            print("Increasing spawn count for USMC")
            return true
        else
            print("Respawn limit for USMC reached")
            return false
        end
    else
        local currentCount
        if townName == "Town X" then _,_,currentCount = commands.exec("/scoreboard players get TownX_JP spawnCount") end
        if townName == "Town Y" then _,_,currentCount = commands.exec("/scoreboard players get TownY_JP spawnCount") end
        if townName == "Town Z" then _,_,currentCount = commands.exec("/scoreboard players get TownZ_JP spawnCount") end

        if currentCount < townRespawnQuota[townName] then
            -- Increment the spawn count for the respective town
            if townName == "Town X" then
                commands.exec("/scoreboard players add TownX_JP spawnCount 1")
            elseif townName == "Town Y" then
                commands.exec("/scoreboard players add TownY_JP spawnCount 1")
            elseif townName == "Town Z" then
                commands.exec("/scoreboard players add TownZ_JP spawnCount 1")
            end
            print("Increasing spawn count for " .. townName)
            return true
        else
            print("Respawn limit for " .. townName .. " reached")
            return false
        end
    end
end

local function resetTownRespawnQuota(townName)
    -- Reset the spawn count for the specific town
    commands.exec("/scoreboard players set " .. townName .. " spawnCount 0")
    print("Respawn quota for " .. townName .. " has been reset")
end

commands.exec("/scoreboard objectives add Troops_Strength dummy")
commands.exec("/scoreboard objectives setdisplay sidebar Troops_Strength")
commands.exec("/team add USMCSpawn")
commands.exec("/team add TownX_JPSpawn")
commands.exec("/team add TownY_JPSpawn")
commands.exec("/team add TownZ_JPSpawn")
local _,_,XSpawnCountTemp = commands.exec("/scoreboard players get TownX_JP spawnCount")
local _,_,YSpawnCountTemp = commands.exec("/scoreboard players get TownY_JP spawnCount")
local _,_,ZSpawnCountTemp = commands.exec("/scoreboard players get TownZ_JP spawnCount")
local _,_,USMCSpawnCountTemp = commands.exec("/scoreboard players get USMC spawnCount")
commands.exec("/scoreboard players set USMCSpawn Troops_Strength " .. (USMCRespawnQuota - USMCSpawnCountTemp))
commands.exec("/scoreboard players set TownX_JPSpawn Troops_Strength " .. (townRespawnQuota["Town X"] - XSpawnCountTemp))
commands.exec("/scoreboard players set TownY_JPSpawn Troops_Strength " .. (townRespawnQuota["Town Y"] - YSpawnCountTemp))
commands.exec("/scoreboard players set TownZ_JPSpawn Troops_Strength " .. (townRespawnQuota["Town Z"] - ZSpawnCountTemp))

local function displayScoreboard()
    -- Show the remaining respawn counts for each team
    local _,_,XSpawnCount = commands.exec("/scoreboard players get TownX_JP spawnCount")
    local _,_,YSpawnCount = commands.exec("/scoreboard players get TownY_JP spawnCount")
    local _,_,ZSpawnCount = commands.exec("/scoreboard players get TownZ_JP spawnCount")
    local _,_,USMCSpawnCount = commands.exec("/scoreboard players get USMC spawnCount")
    commands.exec("/scoreboard players set USMCSpawn Troops_Strength " .. (USMCRespawnQuota - USMCSpawnCount))
    commands.exec("/scoreboard players set TownX_JPSpawn Troops_Strength " .. (townRespawnQuota["Town X"] - XSpawnCount))
    commands.exec("/scoreboard players set TownY_JPSpawn Troops_Strength " .. (townRespawnQuota["Town Y"] - YSpawnCount))
    commands.exec("/scoreboard players set TownZ_JPSpawn Troops_Strength " .. (townRespawnQuota["Town Z"] - ZSpawnCount))
end
displayScoreboard()
-- Function to select an infantry spawn point
local function selectInfantrySpawn()
    while true do
        monitor.clear()

        -- Display the spawn quota on the scoreboard
        displayScoreboard()

        -- Move the cursor down to start showing spawn points
        local y = 7
        local rowMap = {}

        monitor.setCursorPos(1, y)
        printMonitor("Select Infantry Spawn (Stage "..tostring(currentStage).."):")
        y = y + 2

        -- Display available spawn points
        for i, p in ipairs(infantrySpawns[country][currentStage]) do
            -- Check if the town has remaining respawns
            if hasRespawnQuota(country, p.name) then
                monitor.setCursorPos(2, y)
                monitor.write(("[%s]  (%d,%d,%d)"):format(p.name, p.x, p.y, p.z))
                rowMap[y] = p
                y = y + 2
            end
        end

        -- If no valid spawn points, notify the player
        if y == 7 then
            printMonitor("No spawn points available! Respawn limit reached.")
            sleep(2)
            return nil
        end

        -- Display the Refresh button
        monitor.setCursorPos(2, y)
        monitor.write("[ Refresh ]")
        local refreshY = y
        rowMap[refreshY] = "refresh"

        -- Display the Cancel button
        monitor.setCursorPos(2, y + 2)
        monitor.write("[ Cancel ]")
        rowMap[y + 2] = "cancel"  -- Store cancel button in rowMap

        local ev, side, x, ry = os.pullEvent("monitor_touch")

        -- Handle Refresh button
        if ry == refreshY then
            -- Stage might have changed, so loop will redraw
        -- Handle Cancel button press
        elseif rowMap[ry] == "cancel" then
            return nil  -- Return nil when Cancel is pressed
        -- Handle Spawn selection
        elseif rowMap[ry] then
            local selectedSpawn = rowMap[ry]
            local townName = selectedSpawn.name
            if decrementRespawnQuota(country, townName) then
                return selectedSpawn
            else
                printMonitor("Respawn limit for " .. townName .. " reached!")
                sleep(2)
            end
        end
    end
end

local function giveInfantryKit(player, class)
    local kit = infantryKits[class]
    if not kit then return end
    for _, it in ipairs(kit) do
        commands.exec(("give %s %s %d"):format(player, it.id, it.count or 1))
    end
end

local spawnRadius = 50
local function respawnInfantry(player, spawnLocation, class)
    if spawnLocation and spawnLocation.name == "USCommander" then
        commands.exec("/tp "..player.." @a[tag=USCom,limit=1]")
    else
        -- pick a random offset in the horizontal plane
        local dx = math.random(-spawnRadius, spawnRadius)
        local dz = math.random(-spawnRadius, spawnRadius)
        local x = math.floor(spawnLocation.x + dx + 0.5)
        local z = math.floor(spawnLocation.z + dz + 0.5)
        local y = spawnLocation.y  -- keep same height; adjust if you have ground-finding logic

        -- Teleport the player
        commands.exec(("tp %s %d %d %d"):format(player, x, y, z))

        -- Feedback
        commands.exec((
            "title %s actionbar {\"text\":\"Respawned as %s at %s (Stage %d)\",\"color\":\"yellow\"}"
        ):format(player, class, spawnLocation.name, currentStage))
        commands.exec("/effect give "..player.." minecraft:resistance 4 10")
        print(("%s respawned near %s at (%d, %d, %d)"):format(player, spawnLocation.name, x, y, z))
    end
end


local townXRetreated,townYRetreated = false,false
local function retreatTown()
    while true do
        if country == "japan" then
            if currentStage == 2 and not townXRetreated then
                print("Retreat from X")
                local _,_,XSpawnCount = commands.exec("/scoreboard players get TownX_JP spawnCount")
                local remainingTownXJP = townRespawnQuota["Town X"] - XSpawnCountTemp
                commands.exec("/scoreboard players set TownX_JP spawnCount "..townRespawnQuota["Town X"])
                commands.exec("/scoreboard players remove TownY_JP spawnCount "..math.floor(remainingTownXJP * 0.7))
                commands.exec("/say JP soldier in town X retreated to town Y")
                townXRetreated = true
            elseif currentStage == 3 and not townYRetreated then
                print("Retreat from Y")
                local _,_,YSpawnCount = commands.exec("/scoreboard players get TownY_JP spawnCount")
                local remainingTownYJP = townRespawnQuota["Town Y"] - YSpawnCount
                commands.exec("/scoreboard players set TownY_JP spawnCount "..townRespawnQuota["Town Y"])
                commands.exec("/scoreboard players remove TownZ_JP spawnCount "..math.floor(remainingTownYJP * 0.7))
                commands.exec("/say JP soldier in town Y retreated to town Z")
                townYRetreated = true
            end
        end
        sleep(0.5)
    end
end

--========--
--Cooldown--
--========--
local tankState = { germany = {}, allied = {}, japan = {}, USMC = {} }
local function now()
    return os.epoch("utc") / 1000  -- seconds
end

local function ensureState(country, tankName)
    local cfg = tanksList[country][tankName]
    local st  = tankState[country][tankName]
    if not st then
        st = { tokens = cfg.buffer, lastRefill = now() }
        tankState[country][tankName] = st
    end
    return cfg, st
end

-- Refill tokens based on elapsed time and cooldown
local function refillTokens(country, tankName)
    local cfg, st = ensureState(country, tankName)
    local t = now()
    local elapsed = t - st.lastRefill
    if elapsed >= cfg.cooldown then
        local add = math.floor(elapsed / cfg.cooldown)
        if add > 0 then
            st.tokens = math.min(cfg.buffer, st.tokens + add)
            st.lastRefill = st.lastRefill + add * cfg.cooldown
        end
    end
    return cfg, st
end

local function timeToNext(country, tankName)
    local cfg, st = refillTokens(country, tankName)
    if st.tokens > 0 then return 0 end
    local remain = cfg.cooldown - (now() - st.lastRefill)
    return math.max(1, math.ceil(remain))
end

-- Try to consume one token. Returns (true) if allowed; (false, secondsLeft) if blocked
local function tryConsume(country, tankName)
    local cfg, st = refillTokens(country, tankName)
    if st.tokens > 0 then
        local wasFull = (st.tokens == cfg.buffer)
        st.tokens = st.tokens - 1
        -- If we were full and just spent one, start the refill timer now
        if wasFull then st.lastRefill = now() end
        return true
    else
        return false, timeToNext(country, tankName)
    end
end

-- Convenience wrappers so the rest of your code can read/write stock easily
local function getStock(country, tankName)
    return tanksList[country][tankName].stock
end
local function setStock(country, tankName, value)
    tanksList[country][tankName].stock = math.max(0, value)
end

-- Display and wait for tank selection via touch (live cooldown)
local function selectTankTouch(availableTanks)
    local buttonX   = 38           -- where the first button starts
    local xSpacing  = 5            -- distance between button starts
    local labels    = { "+2", "+1", "-1", "-2" }
    local deltas    = {  2,    1,   -1,   -2  }
    local refreshMs = 0.5          -- seconds between UI refreshes

    local cancelButtonY = nil

    local rowMap        = {}       -- [y] = tankName
    local buttonRegions = {}       -- { y, xStart, xEnd, tank, delta }

    local function render()
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write("Touch a tank to select or modify:")
        monitor.setCursorPos(1, 2)
        monitor.write("Only admin can press the +/- button")

        rowMap        = {}
        buttonRegions = {}

        local y = 3
        for _, name in ipairs(availableTanks) do
            local cfg = tanksList[country][name] or { stock = 0, buffer = 0 }
            local _, st = ensureState(country, name)
            refillTokens(country, name)

            local cd = timeToNext(country, name)
            local cdText = (st.tokens > 0) and "Ready" or (tostring(cd) .. "s")

            monitor.setCursorPos(2, y)
            monitor.write(("- %s (%d)  cooldown:%s"):format(name, cfg.stock or 0, cdText))
            rowMap[y] = name

            -- draw buttons using buttonX/xSpacing; record clickable regions
            for i, label in ipairs(labels) do
                local x = buttonX + (i - 1) * xSpacing
                local btnText = "[" .. label .. "]"
                monitor.setCursorPos(x, y)
                monitor.write(btnText)

                table.insert(buttonRegions, {
                    y      = y,
                    xStart = x,
                    xEnd   = x + #btnText - 1, -- inclusive
                    tank   = name,
                    delta  = deltas[i]
                })
            end

            y = y + 1
        end

        -- Cancel button added to the interface
        monitor.setCursorPos(2, y)
        monitor.write("[ Cancel ]")
        cancelButtonY = y
    end

    -- initial draw + start refresh timer
    render()
    local timer = os.startTimer(refreshMs)

    while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "monitor_touch" then
            local x, ty = b, c

            -- Check if the cancel button was pressed
            if ty == cancelButtonY and x >= 2 and x <= 12 then
                return nil  -- Return nil if the cancel button was pressed
            end

            -- check +/- buttons first
            for _, btn in ipairs(buttonRegions) do
                if ty == btn.y and x >= btn.xStart and x <= btn.xEnd then
                    -- admin confirm in terminal
                    print("\nAdmin modification request:")
                    print("  Tank: " .. btn.tank)
                    print("  Change: " .. (btn.delta >= 0 and "+" or "") .. btn.delta)
                    io.write("Press Enter within 3 seconds to confirm... ")

                    local t = os.startTimer(3)
                    local confirmed = false
                    while true do
                        local ev2, p = os.pullEvent()
                        if ev2 == "timer" and p == t then
                            print(" (timed out)")
                            break
                        elseif ev2 == "key" and p == keys.enter then
                            confirmed = true
                            break
                        end
                    end

                    if confirmed then
                        local cfg = tanksList[country][btn.tank]
                        cfg.stock = math.max(0, (cfg.stock or 0) + btn.delta)
                        print("Change applied. New stock for " .. btn.tank .. ": " .. cfg.stock)
                    end

                    -- redraw immediately and reset refresh timer
                    render()
                    timer = os.startTimer(refreshMs)
                    goto continue_event_loop
                end
            end

            -- if not a button, check row selection (left side of row)
            local selectedTank = rowMap[ty]
            if selectedTank and x < (buttonX - 2) then
                return selectedTank
            end
        elseif ev == "timer" and a == timer then
            -- periodic refresh to update cooldowns
            render()
            timer = os.startTimer(refreshMs)
        end
        ::continue_event_loop::
    end
end
--========--
--tank pin--
--========--
-- === Tank PIN auth ===
local TANK_PIN = "1314"
local function promptTankPin()
    monitor.clear()
    local w, h = monitor.getSize()

    local input = ""
    local message = "Enter 4-digit PIN"
    local keypad = {
        {"1","2","3"},
        {"4","5","6"},
        {"7","8","9"},
        {"C","0","OK"},
    }

    -- layout
    local startX, startY = 2, 4  -- top-left of keypad
    local cellW, cellH = 6, 2    -- width/height of each button
    local regions = {}           -- {x1,y1,x2,y2,key}
    local cancelRegion = nil

    local function draw()
        monitor.clear()
        monitor.setCursorPos(2, 1); monitor.write(message)
        monitor.setCursorPos(2, 2); monitor.write("PIN: " .. string.rep("*", #input))

        -- draw keypad buttons and record regions
        regions = {}
        for r = 1, #keypad do
            for c = 1, #keypad[r] do
                local key = keypad[r][c]
                local x1 = startX + (c-1)*cellW
                local y1 = startY + (r-1)*cellH
                monitor.setCursorPos(x1, y1)
                monitor.write("["..key.."]")
                table.insert(regions, {x1=x1, y1=y1, x2=x1+2+ #key, y2=y1, key=key})
            end
        end

        -- Cancel button under keypad
        local cancelY = startY + (#keypad)*cellH + 2
        monitor.setCursorPos(2, cancelY)
        monitor.write("[ Cancel ]")
        cancelRegion = {x1=2, y1=cancelY, x2=2 + 9, y2=cancelY}
    end

    local function inside(x,y,rect)
        return y == rect.y1 and x >= rect.x1 and x <= rect.x2
    end

    draw()
    while true do
        local ev, side, x, y = os.pullEvent("monitor_touch")

        -- cancel?
        if inside(x, y, cancelRegion) then
            return false
        end

        -- any keypad key?
        for _, r in ipairs(regions) do
            if inside(x, y, r) then
                local k = r.key
                if k == "C" then
                    input = ""
                    message = "Enter 4-digit PIN"
                    draw()
                elseif k == "OK" then
                    if #input ~= 4 then
                        message = "Enter exactly 4 digits"
                        draw()
                    else
                        if input == TANK_PIN then
                            message = "Access granted"
                            draw()
                            sleep(0.15)
                            return true
                        else
                            message = "Wrong PIN"
                            draw()
                            sleep(0.9)
                            return false
                        end
                    end
                else
                    -- digit
                    if #input < 4 and k:match("%d") then
                        input = input .. k
                        draw()
                    end
                end
                break
            end
        end
    end
end

-- Main loop
parallel.waitForAny(
    function()
        while true do
            -- Pick mode first
            local mode = selectMode()

            if mode == "tank" then
                ::continue_tank::
                --[[local okPin = promptTankPin()
                if not okPin then
                    printMonitor("Access denied.")
                    sleep(1)
                    goto post_action
                end]]

                monitor.clear()
                monitor.setCursorPos(1,1)
                printMonitor("=== Available Tanks ===")
                availableTanks = {}

                -- Build list of tanks with stock > 0
                for tankName, cfg in pairs(tanksList[country]) do
                    if cfg.stock and cfg.stock > 0 then
                        table.insert(availableTanks, tankName)
                    end
                end

                if #availableTanks == 0 then
                    printMonitor("No tanks available!")
                    sleep(1.2)
                    goto post_action
                end

                -- Show stock + quick cooldown badge
                for _, name in ipairs(availableTanks) do
                    local cfg = tanksList[country][name]
                    local _, st = ensureState(country, name)
                    refillTokens(country, name)
                    local cd = timeToNext(country, name)
                    local cdText = (st.tokens > 0) and "Ready" or (tostring(cd) .. "s")
                    printMonitor(("- %s (%d)  cooldown:%s"):format(name, cfg.stock, cdText))
                end

                -- Choose which tank (has live-cooldown UI inside)
                local selectedTank = selectTankTouch(availableTanks)
                if not selectedTank then
                    printMonitor("No tank selected.")
                    sleep(1)
                    goto post_action
                end

                -- Cooldown gate
                local ok, waitSec = tryConsume(country, selectedTank)
                if not ok then
                    printMonitor(selectedTank .. " cooldown. Ready in ~" .. waitSec .. "s.")
                    sleep(1.2)
                    goto post_action
                end

                -- Pick spawn point for TANK (your existing chooser)
                local spawnPoint = selectSpawnPoint()
                if not spawnPoint then
                    printMonitor("Spawn cancelled.")
                    sleep(1)
                    goto post_action
                end

                --=== Your existing TANK teleport flow ===--
                local teleportCord = spawnPoint
                local points = generateGridPoints(teleportCord.x, teleportCord.y, teleportCord.z)
                local currentCount = getStock(country, selectedTank)
                local teleported = false
                local tankNumber = currentCount

                while tankNumber > 0 and not teleported do
                    local tankToTeleport = selectedTank .. "-" .. tankNumber
                    local point = points[currentPointIndex]
                    local finalX, finalY, finalZ = point.x, teleportCord.y, point.z

                    -- Move old tank (if any) to reserve
                    local oldTank = playerTankMap[closetPlayerName]
                    if oldTank then
                        printMonitor("Moving old tank " .. oldTank .. " to reserve area...")
                        local offsetX = math.random(-100, 100)
                        local offsetZ = math.random(-100, 100)
                        local rX, rY, rZ = reserveCord.x + offsetX, reserveCord.y, reserveCord.z + offsetZ

                        commands.exec("vs set-static " .. tankToTeleport .. " true")
                        sleep(0.5)
                        commands.exec(("vmod teleport %s %d %d %d"):format(tankToTeleport, rX, rY, rZ))
                        printMonitor(("Teleporting to X:%d Y:%d Z:%d"):format(rX,rY,rZ))
                        commands.exec(("fill %d %d %d %d %d %d vscontrolcraft:chunk_loader"):format(rX,rY,rY,rX,rY,rY))
                        sleep(1.5)
                        commands.exec(("vmod teleport %s %d %d %d"):format(oldTank, rX, rY, rZ))
                        sleep(0.5)
                        commands.exec(("fill %d %d %d %d %d %d air"):format(rX,rY,rY,rX,rY,rY))
                    end

                    printMonitor(("Teleporting %s to X:%d Y:%d Z:%d"):format(tankToTeleport, finalX, finalY, finalZ))
                    commands.exec("vs set-static " .. tankToTeleport .. " true")
                    sleep(0.3)

                    local _, result = commands.exec(("vmod teleport %s %d %d %d"):format(tankToTeleport, finalX, finalY, finalZ))
                    currentPointIndex = currentPointIndex + 1; if currentPointIndex > #points then currentPointIndex = 1 end

                    local teleportFailed = not (result and result[1] == nil)
                    if teleportFailed then
                        printMonitor("Tank not found, trying next...")
                        tankNumber = tankNumber - 1
                    else
                        teleported = true
                        printMonitor("Teleport successful!")
                        playerTankMap[closetPlayerName] = tankToTeleport
                        commands.exec(("give %s create_tweaked_controllers:tweaked_linked_controller{display:{Name:'{\"text\":\"%s\"}'}}"):format(closetPlayerName, tankToTeleport))

                        for _, item in ipairs(repairKits) do
                            commands.exec(("give %s %s %d"):format(closetPlayerName, item.id, item.count))
                        end
                        printMonitor("Given " .. selectedTank .. " repair kit!")

                        commands.exec(("tp %s %d %d %d"):format(closetPlayerName, finalX, finalY + 2, finalZ))
                        commands.exec(("tellraw %s {\"text\":\"Right click controller hub to link\",\"color\":\"yellow\"}"):format(closetPlayerName))
                        sleep(1)
                        commands.exec("kill @e[type=trackwork:wheel_entity]")
                        commands.exec("vs set-static " .. tankToTeleport .. " false")

                        setStock(country, selectedTank, tankNumber - 1)
                        saveTanksListToFile("tanksList.txt", tanksList)
                        printMonitor("Remaining " .. selectedTank .. ": " .. getStock(country, selectedTank))
                    end
                end

                if not teleported then
                    printMonitor("No tanks of type " .. selectedTank .. " could be found!")
                    setStock(country, selectedTank, 0)
                    saveTanksListToFile("tanksList.txt", tanksList)
                end

            elseif mode == "infantry" then
                -- Infantry respawn flow
                monitor.clear()
                monitor.setCursorPos(1,1)
                printMonitor("Infantry respawn\nStage: "..tostring(currentStage))

                -- pick class
                local class = selectInfantryClass()
                if not class then goto post_action end
                if not isKitReady(class) then goto post_action end

                -- pick stage-driven spawn
                local spawn = selectInfantrySpawn()
                if not spawn then goto post_action end
                handleInfantryKit(closetPlayerName, class)
                -- Teleport & kit (with respawn quota logic)
                respawnInfantry(closetPlayerName, spawn, class)
            end

            ::post_action::
            displayScoreboard()
            sleep(0.5)
        end
    end,
    getClosestUserName,
    manageCreativeArea,
    listenStage,
    retreatTown
)
