local raycaster = peripheral.find("raycaster")
local modem = peripheral.find("modem")

local cannonHitPosChannel = 700
if modem then
    modem.open(cannonHitPosChannel)
end

if not raycaster then
    print("No raycaster found.")
    return
end

local max_distance = 300

local function castRay()
    local var1 = 0 
    local var2 = 0
    local var3 = 1
    local euler_mode = false
    local immediate_execution = true
    local check_for_blocks_in_world = true

    local result = raycaster.raycast(max_distance, {var1, var2, var3}, euler_mode, immediate_execution)

    -- Check the result
    if result.is_block and result.block_type ~= "block.minecraft.air" then
        print("Block hit at:")
        print("Hit position: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
        print("Block type: " .. result.block_type)
        print("Distance: " .. result.distance)
    elseif result.is_entity then
        print("Entity hit at:")
        print("Hit position: " .. result.hit_pos[1] .. ", " .. result.hit_pos[2] .. ", " .. result.hit_pos[3])
        print("Entity ID: " .. result.id)
        print("Entity type: " .. result.descriptionId)
        print("Distance: " .. result.distance)
    elseif result.ship_id then
        print("No hit detected within " .. max_distance .. " blocks.")
        print("Hit position: "..result.hit_pos[1].." , "..result.hit_pos[2].." , "..result.hit_pos[3])
    end

    -- Insert "coordinate" text into the hit_pos table at the fourth position
    if result.hit_pos then
        table.insert(result.hit_pos, 4, "coordinate")
        print(textutils.serialize(result.hit_pos))
        modem.transmit(700, 0, result.hit_pos)
        print("transmitting")
    end
end

-- Cast the ray and return the hit coordinates
while true do
    castRay()
    sleep(0.01)
end
