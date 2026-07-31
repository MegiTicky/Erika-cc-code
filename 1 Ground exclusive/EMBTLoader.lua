-- Define the peripheral devices
local barrel = peripheral.find("minecraft:barrel")  -- Find the barrel
local deployer = peripheral.find("create:deployer")  -- Find the deployer
local unscrewMotor = peripheral.wrap("back")
local screwRemoveMotor = peripheral.wrap("front")
local modem = peripheral.wrap("right")

local loadingMotor
local nilCount = 0
local i = 0



-- Loop to find loading motor through modem (searching "electric_motor_X")d
while nilCount < 200 do
    local motorName = "electric_motor_" .. tostring(i)
    loadingMotor = peripheral.wrap(motorName)
    
    if loadingMotor then
        print("Found loading motor:", motorName)
        break
    else
        nilCount = nilCount + 1
    end
    i = i + 1
end

unscrewMotor.setSpeed(0)
loadingMotor.setSpeed(0)

local function askUser(prompt, defaultValue)
    print(prompt .. " (default: " .. defaultValue .. ")")
    local input = io.read()
    if input == "" then
        return defaultValue
    else
        return input
    end
end

EMBTControlChannel = tonumber(askUser("Input the EMBT channel","2000"))
reloadChannel = EMBTControlChannel + 20
modem.open(reloadChannel)
modem.open(EMBTControlChannel)
local reloadMessage_recived = {}
local reloadMessage_send = {}

-- Finds an item in the barrel that exactly matches the given display name.
local function findItemByDisplayName(displayName)
    -- get a quick list of everything in the barrel
    local items = barrel.list()
    for slot, data in pairs(items) do
        -- get full detail for the item in this slot
        local detail = barrel.getItemDetail(slot)
        if detail and detail.displayName == displayName then
            -- If matched, return slot and quantity
            return true, slot, detail.count
        end
    end
    return false
end

local function pullItemByDisplayName(displayName)
    local found, slot, count = findItemByDisplayName(displayName)
    if found then
        print("Found item '" .. displayName .. "' in slot ".. slot .." (count = "..count..")")
        deployer.pullItems(peripheral.getName(barrel), slot, 1)
        print("Pulled 1x '" .. displayName .. "' into deployer.")
    else
        print("No item named '" .. displayName .. "' in the barrel.")
    end
end

local function hasItem(itemName)
    local items = barrel.list()  -- Get the list of items in the barrel
    for slot, data in pairs(items) do
        print(data.name)
        if data.name == itemName then
            return true, slot, data.count  -- If we find the item, return true, its slot number, and item count
        end
    end
    return false  -- No item found
end

-- Function to pull the item from the barrel to the deployer
local function pullItem(itemName)
    local success, slot, count = hasItem(itemName)
    if success then
        print("Found " .. itemName .. " in slot " .. slot .. " with quantity " .. count)
        -- Pull the item from the barrel and place it in the deployer’s inventory
        deployer.pullItems(peripheral.getName(barrel), slot, 1)  -- Pull 1 item from the specified slot
        print(itemName .. " successfully transferred to the deployer!")
    else
        print("Item not found in the barrel.")
    end
end

local function main()
    while true do
        if reloadMessage_recived and reloadMessage_recived.startReload then
            reloadMessage_send = {reloaded = false}
            reloadMessage_recived.startReload = false
            modem.transmit(reloadChannel,reloadChannel,reloadMessage_send)
            local startTime = os.clock()  -- Start the timer

            -- Unscrew
            unscrewMotor.setSpeed(256)
            sleep(0.2)
            unscrewMotor.setSpeed(0)

            -- Remove screw
            screwRemoveMotor.rotate(35,1)
            sleep(0.1)

            -- Add shell
            if controls and controls.shellMode == "APHE_Proximity" then
                pullItemByDisplayName("APHE_Proximity")
            elseif controls and controls.shellMode == "APHE_Delayed" then
                pullItemByDisplayName("APHE_Delayed")
            end
            sleep(0.35)

            -- Load shell
            loadingMotor.setSpeed(-256)
            sleep(0.4)
            loadingMotor.setSpeed(256)
            sleep(0.1)

            -- Load powder charge 8 times
            for i = 1, 8 do
                print("Loading powder charge " .. i .. "...")
                pullItem("createbigcannons:powder_charge")
                sleep(0.5)
                
                -- Load powder charge
                loadingMotor.setSpeed(-256)
                sleep(0.4)
                loadingMotor.setSpeed(256)
                sleep(0.05)
            end

            -- Place screw
            sleep(0.35)
            loadingMotor.setSpeed(0)
            screwRemoveMotor.rotate(25,-1)
            sleep(0.5)

            -- Screw it tight
            unscrewMotor.setSpeed(-256)
            sleep(0.3)
            unscrewMotor.setSpeed(0)
            local endTime = os.clock()  -- End the timer
            local reloadTime = endTime - startTime  -- Calculate elapsed time

            print(string.format("Reload completed in %.2f seconds.", reloadTime))

            reloadMessage_send = {reloaded = true}
            modem.transmit(reloadChannel,reloadChannel,reloadMessage_send)
        end
        sleep()  -- Reduce CPU usage
    end
end

local function modemMessage()
    while true do
        if modem then
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if channel == reloadChannel then
                reloadMessage_recived = message
            elseif channel == EMBTControlChannel then
                controls = message
            end
        else
            sleep()
        end
    end
end

parallel.waitForAny(
    main,
    modemMessage
)