redstone.setAnalogOutput("top",15)
sleep(0.1)
redstone.setAnalogOutput("top",0)

-- ロードアウト情報
local loadouts = {

    [1] =  { -- Assault突擊兵
    {"additionalguns:bullet_heavy", 64*3},
    "combatgear:modern_chestplate",
    "combatgear:tacticalup_helmet",
    "combatgear:heavycloak_leggings",
    "combatgear:heavycloak_boots",
    "additionalguns:ak15",
    "additionalguns:p250",
    "smallarm:rpg7",
    "smallarm:rpg7_rocket",
    {"minecraft:dirt",64},
    {"cgm:grenade",3},
    {"cgm:stun_grenade",3},
    {"minecraft:bread",64},
    {"additionalguns:bullet_short",64},
    {"combatgear:bandages",8},
    "minecraft:iron_pickaxe",
    "minecraft:iron_axe",
    "combatgear:etool",
    "cgm:medium_scope",
    "cgm:specialised_grip",
    "additionalguns:muzzle_brake",
    {"minecraft:bread",32}
    },
    
    [2] = { -- Medic 軍醫
    {"additionalguns:bullet_short", 64},
    {"additionalguns:bullet_small", 64*4},
    "additionalguns:pp_19",
    "combatgear:modern_chestplate",
    "combatgear:tacticalup_helmet",
    "combatgear:heavycloak_leggings",
    "combatgear:heavycloak_boots",
    "additionalguns:p250",
    {"minecraft:dirt",64},
    {"smallarm:smoke_grenade",8},
    {"minecraft:bread",32},
    {"combatgear:bandages",8},
    {"combatgear:medpack",3},
    {"combatgear:stimpack",3},
    "minecraft:white_shulker_box{BlockEntityTag:{Items:[{id:\"combatgear:medpack\",Count:1b,Slot:0b},{id:\"combatgear:medpack\",Count:1b,Slot:1b},{id:\"combatgear:medpack\",Count:1b,Slot:2b},{id:\"combatgear:medpack\",Count:1b,Slot:3b},{id:\"combatgear:medpack\",Count:1b,Slot:4b},{id:\"combatgear:medpack\",Count:1b,Slot:5b},{id:\"combatgear:medpack\",Count:1b,Slot:6b},{id:\"combatgear:medpack\",Count:1b,Slot:7b},{id:\"combatgear:bandages\",Count:8b,Slot:8b},{id:\"combatgear:bandages\",Count:8b,Slot:9b},{id:\"combatgear:bandages\",Count:8b,Slot:10b},{id:\"combatgear:bandages\",Count:8b,Slot:11b},{id:\"combatgear:bandages\",Count:8b,Slot:12b},{id:\"combatgear:bandages\",Count:8b,Slot:13b},{id:\"combatgear:bandages\",Count:8b,Slot:14b},{id:\"combatgear:bandages\",Count:8b,Slot:15b},{id:\"combatgear:bandages\",Count:8b,Slot:16b},{id:\"combatgear:bandages\",Count:8b,Slot:17b},{id:\"combatgear:bandages\",Count:8b,Slot:18b}]}}",
    "minecraft:iron_pickaxe",
    "minecraft:iron_axe",
    "combatgear:etool",
    {"minecraft:splash_potion{Potion:strong_healing}",6},
    "cgm:medium_scope",
    "cgm:tactical_stock",
    "cgm:specialised_grip",
    "additionalguns:muzzle_brake",
},


    [3] = { -- Engineer 工兵
    {"additionalguns:bullet_short", 64},
    {"moguns:762x51", 64*5},
    "smallarm:m240",
    "combatgear:modern_chestplate",
    "combatgear:tacticalup_helmet",
    "combatgear:heavycloak_leggings",
    "combatgear:heavycloak_boots",
    "additionalguns:p250",
    "cgm:medium_scope",
    "mekanism:atomic_disassembler{mekData:{EnergyContainers:[{Container:0b,stored:\"1000000\"}]}}",
    {"s_a_b:greenhardsteelblock",64},
    {"create:redstone_link",64},
    {"create:encased_chain_drive",64},
    {"s_a_b:sandbag",64},
    {"vs_eureka:ship_helms",64},
    {"create:copycat_panel",64},
    {"computercraft:wireless_modem_advanced",64},
    {"create:andesite_scaffolding",64},
    {"vs_tournament:explosive_instant_small",2},
    {"minecraft:tnt",6},
    "create:linked_controller",
    {"minecraft:lever",64},
    {"trackwork:large_suspension_track",64},
    {"trackwork:phys_track",64},
    {"cbcmodernwarfare:nethersteel_mediumcannon_barrel",64},
    "create:wrench",
    {"combatgear:bandages",8},
    {"minecraft:bread",32}
    },


    [4] = { -- Sniper狙撃兵
    {"additionalguns:bullet_short", 64},
    {"additionalguns:bullet_long", 64},
    "additionalguns:awm",
    "combatgear:modern_chestplate",
    "combatgear:tacticalup_helmet",
    "combatgear:heavycloak_leggings",
    "combatgear:heavycloak_boots",
    "additionalguns:p250",
    "smallarm:pso_1_scope",
    "additionalguns_sniper_muzzle_brake",
    "minecraft:spyglass",
    "minecraft:iron_pickaxe",
    "minecraft:iron_axe",
    "combatgear:etool",
    {"minecraft:dirt",64},
    {"combatgear:bandages",8},
    {"minecraft:bread",32},
    },

    [5] = { -- Heavy重步兵
    {"additionalguns:bullet_short", 64},
    {"smallarm:ap_bullet", 64*7},
    "smallarm:m2brown",
    "minecraft:orange_shulker_box",
    "combatgear:gign_helmet{Enchantments:[{id:projectile_protection,lvl:4}]}",
    "combatgear:gign_chestplate{Enchantments:[{id:protection,lvl:4}]}",
    "combatgear:gign_leggings{Enchantments:[{id:blast_protection,lvl:4}]}",
    "combatgear:gign_boots{Enchantments:[{id:projectile_protection,lvl:4}]}",
    "additionalguns:p250",
    "minecraft:spyglass",
    "minecraft:iron_pickaxe",
    "minecraft:iron_axe",
    "combatgear:etool",
    {"minecraft:dirt",64},
    {"combatgear:bandages",8},
    {"minecraft:bread",32}
    },

    [6] = { -- Pyro火焰兵
    {"additionalguns:bullet_short", 64},
    {"minecraft:magma_cream", 64*10},
    "moguns:flamer",
    "minecraft:orange_shulker_box",
    "combatgear:altynup_helmet",
    "combatgear:ww_1ot_chestplate",
    "combatgear:ww_1ot_leggings",
    "combatgear:gign_boots",
    "combatgear:gasmaks",
    "combatgear:m_2backtank",
    "additionalguns:p250",
    "minecraft:spyglass",
    "minecraft:iron_pickaxe",
    "minecraft:iron_axe",
    "combatgear:etool",
    {"minecraft:dirt",64},
    {"combatgear:bandages",8},
    {"minecraft:bread",32}
    },

    [7] = { -- Signaller通訊兵
    {"additionalguns:bullet_short", 64},
    {"additionalguns:bullet_long", 64*3},
    {"moguns:flare",4},
    "additionalguns:scar",
    "moguns:flare_gun",
    "additionalguns:magnum",
    "cgm:specialised_grip",
    "smallarm:eotech",
    "combatgear:modern_chestplate",
    "combatgear:tacticalup_helmet",
    "combatgear:heavycloak_leggings",
    "combatgear:heavycloak_boots",
    {"createaddition:creative_energy",2},
    {"mekanism:teleporter",2},
    {"mekanism:teleporter_frame",7},
    "minecraft:iron_pickaxe",
    "minecraft:iron_axe",
    "combatgear:etool",
    {"minecraft:dirt",64},
    {"combatgear:bandages",8},
    {"minecraft:bread",32}
    },
}
--[[/tellraw @a[tag=waitloadout] [    {"text":"Choose your loadout選擇您的裝載: ","color":"gold"},    
{"text":"Assault 突撃兵","color":"green","clickEvent":{"action":"run_command","value":"/tag @s add INF-1"}},    
{"text":" | "},    {"text":"Medic 軍医","color":"red","clickEvent":{"action":"run_command","value":"/tag @s add INF-2"}},    
{"text":" | "},    {"text":"Engineering 工兵","color":"gray","clickEvent":{"action":"run_command","value":"/tag @s add INF-3"}},    
{"text":" | "},{"text":"\n"},    {"text":"Sniper 狙撃兵","color":"dark_purple","clickEvent":{"action":"run_command","value":"/tag @s add INF-4"}},
{"text":" | "},    {"text":"Heavy重步兵","color":"white","clickEvent":{"action":"run_command","value":"/tag @s add INF-5"}},
{"text":" | "},    {"text":"Pyro火焰兵","color":"white","clickEvent":{"action":"run_command","value":"/tag @s add INF-6"}},
{"text":" | "},    {"text":"Signaller通訊兵","color":"white","clickEvent":{"action":"run_command","value":"/tag @s add INF-7"}}
]
]]


-- ロードアウトを付与する関数
function giveLoadout(loadoutNumber)
    print(loadoutNumber)
    local selector = "@a[tag=Resporn,tag=INF-" .. loadoutNumber .. "]"
    local items = loadouts[loadoutNumber]

    if not items then
        print("Invalid loadout number.")
        return
    end

    for _, item in pairs(items) do
        if type(item) == "table" then
            commands.exec(string.format("/give %s %s %d", selector, item[1], item[2]))
        else
            commands.exec(string.format("/give %s %s", selector, item))
        end
    end
end










while true do



    for i = 1, #loadouts do
        dead =commands.exec("/tag @a[tag=dead] remove INF-" .. i)
        print(dead)
        sleep(0.1)
        if dead then
            commands.exec("/tag @a[tag=dead] add loadout")
            commands.exec("/tag @a[tag=dead] add waitloadout")
            sleep(1)
            commands.exec("/tag @a[tag=dead] remove waitloadout")
            while true do
                breakOK = false
                for i2 = 1, #loadouts do
                    resp = commands.exec("/tag @a[tag=loadout,tag=INF-"..i2.."] remove dead")
                    print("i2: "..i2)
                    print(resp)
                    if resp then
                        commands.exec("/tag @a[tag=loadout,tag=INF-"..i2.."] add Resporn")
                        commands.exec("/tag @a[tag=loadout,tag=INF-"..i2.."] remove loadout")
                        print("give Loadout:" .. i2)
                        giveLoadout(i2)
                        breakOK = true
                    end 
                    print("Resporn wait")
                end

                if breakOK then
                    break
                end

            end
            sleep(0)
            
            sleep(0)
        end
    end

end


