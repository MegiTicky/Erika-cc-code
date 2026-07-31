-- Configure the scheme names for different sides (left, right, front, back) with yaw offsets
local schemeName = {
    left = {name = "F6FHellcat", yawOffset = 90},  -- Example scheme for the left side with 90° offset
    right = {name = nil, yawOffset = 0},          -- No scheme for right side
    front = {name = nil, yawOffset = 0},          -- No scheme for front side
    back = {name = nil, yawOffset = 0}            -- No scheme for back side
}

-- Set a cooldown to prevent continuous input processing (for debouncing)
local buttonCooldown = true

-- Find the camera peripheral
local camera = peripheral.find("camera")

-- Normalize a vector
local function normalizeVector(v)
    local length = math.sqrt(v[1]^2 + v[2]^2 + v[3]^2)
    if length == 0 then
        return {0, 0, 0}
    end
    return {v[1] / length, v[2] / length, v[3] / length}
end

-- Normalize the rotation matrix
local function normalizeRotationMatrix(rotMatrix)
    local normalizedMatrix = {}
    for i = 1, #rotMatrix do
        normalizedMatrix[i] = normalizeVector(rotMatrix[i])
    end
    return normalizedMatrix
end

-- Get the yaw of the ship
local function getYaw()
    local rotMatrix = ship.getTransformationMatrix()
    local normalizedMatrix = normalizeRotationMatrix(rotMatrix)
    return math.atan2(-normalizedMatrix[3][1], -normalizedMatrix[3][3]) -- Extract yaw from the matrix
end

-- Function to handle redstone inputs and load/place the corresponding schematic
local function checkRedstoneInput()
    -- Get camera position
    local cameraPos = camera.getCameraPosition()
    local x = cameraPos.x
    local y = cameraPos.y + 2
    local z = cameraPos.z

    -- Get ship yaw (degrees)
    local yaw = math.floor(getYaw()) -- vmod prefers integers

    -- Place the schematic with its yaw offset
    local function placeSchem(scheme)
        -- Add yaw offset to the ship's yaw
        local finalYaw = yaw + scheme.yawOffset

        -- Ensure the final yaw is within the range of 0 to 360 degrees
        finalYaw = finalYaw % 360

        print("Loading schematic:", scheme.name)
        commands.exec("/vmod schem load-from-server " .. scheme.name)
        commands.exec(
            "/vmod schem place "
            .. x .. " " .. y .. " " .. z .. " "
            .. "(0 " .. finalYaw .. " 0)"  -- Apply rotation with offset
        )
        -- Set cooldown to false after schematic is placed
        buttonCooldown = false
    end

    -- Check redstone inputs and load the corresponding schematic with offset
    if redstone.getInput("left") and schemeName.left.name and buttonCooldown then
        placeSchem(schemeName.left) 
    elseif redstone.getInput("right") and schemeName.right.name and buttonCooldown then
        placeSchem(schemeName.right)

    elseif redstone.getInput("front") and schemeName.front.name and buttonCooldown then
        placeSchem(schemeName.front)

    elseif redstone.getInput("back") and schemeName.back.name and buttonCooldown then
        placeSchem(schemeName.back)
    end
end

-- Function to reset the cooldown when the button is released
local function checkButtonRelease()
    -- Check if any redstone signal is low (button release)
    if not redstone.getInput("left") and not redstone.getInput("right") and
       not redstone.getInput("front") and not redstone.getInput("back") then
        buttonCooldown = true  -- Allow the next input to be processed
    end
end

-- Main loop to keep checking redstone inputs
while true do
    -- Check if buttonCooldown is active or if redstone signals are received
    if buttonCooldown then
        checkRedstoneInput()
    end

    -- Check for button release to reset cooldown
    checkButtonRelease()

    sleep(0.5)  -- Adjust to suit your system's speed
end
