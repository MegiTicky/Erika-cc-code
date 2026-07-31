local radar = peripheral.find("sp_radar")
local ar = peripheral.find("arController")
local raycaster = peripheral.find("raycaster")
local cannon = peripheral.find("cbcmf_compact_cannon_mount")

local euler_mode = true
local max_distance = 2000
local immediate_execution = true
local check_for_blocks_in_world = true
local gravity = 10
local time_step = 0.1
local max_simulation_time = 100

local dfpwm = require("cc.audio.dfpwm")

-- PERIPHERALS --
local MONITOR = peripheral.find("monitor")
local SPEAKER = peripheral.find("speaker")

-- CONSTANTS --
-- You can touch these
local GROUND_LEVEL = tonumber(arg[1]) or 0   -- Change this to how high your map's ground level is.
local INVERT_ROLL = arg[2] == "invert"
local TAKEN_OFF_THRESHOLD = 20               -- How many blocks into the air you need to be for the voice warnings to be enabled
local LANDED_THRESHOLD = 3                   -- How close to ground level you need to be for the voice warnings to be disabled
local GROUND_WARNING_THRESHOLD = 70          --
local CRITICAL_GROUND_WARNING_THRESHOLD = 30 --
local G_FORCE_WARNING_THRESHOLD = 8.5        --
local SOUNDS = {                             -- Format: "FILE_NAME", sound cooldown in ticks
    ground_warning = { "ALTITUDE", 150 },
    critical_ground_warning = { "PULL_UP", 60 },
    over_g_warning = { "OVER_G", 100 },
    hit_warning = { "WARNING", 60 }, -- Look, I don't have a better system other than mass to detect damage
}

local DELTA_TICK = 3   -- How often the script runs (3 = once every 3 ticks), increase if the screen flickers a lot (lag)
local SOUND_VOLUME = 3 -- 🗣️🗣️🗣️

-- No need to touch these
local SCREEN_WIDTH = 15
local SCREEN_HEIGHT = 10
local DIRECTIONS = { "N", "E", "S", "W" }
local GRAVITY = 10           -- m/s (I'm using CBC's gravity value)
local SOUND_EXTENSION_TYPE = "dfpwm"
local DECODER = dfpwm.make_decoder()

-- STATE VARIABLES --
local current_time = 0
local plane = {
    x = 0, -- Position
    y = 0,
    z = 0,
    vx = 0, -- Velocity
    vy = 0,
    vz = 0,

    speed = 0,
    max_speed = 0,

    ax = 0, -- Acceleration
    ay = 0,
    az = 0,
    o_x = 0, -- Omega
    o_y = 0,
    o_z = 0,
    g_force = 0,
    yaw = 0, -- Orientation
    pitch = 0,
    roll = 0,
    mass = 0,

    rel_y = 0,
    got_hit = false,
    has_taken_off = false,
    descending = false,
}
local last_played = {}
for _, v in pairs(SOUNDS) do
    last_played[v[1]] = 0
end

print("press enter to assemble cannon")
io.read()
cannon.assemble()

local function calculateBombLandingPosition(ship_pos, ship_velocity, release_height)
    local time = 0
    local bomb_pos = {ship_pos.x, ship_pos.y, ship_pos.z} -- Starting at ship's position
    local bomb_velocity = {ship_velocity.x, ship_velocity.y, ship_velocity.z} -- Initial velocity same as the ship's velocity

    while time < max_simulation_time do
        -- Update the bomb's position based on current velocity
        bomb_pos[1] = bomb_pos[1] + bomb_velocity[1] * time_step -- X position
        bomb_pos[2] = bomb_pos[2] + bomb_velocity[2] * time_step -- Y position (height)
        bomb_pos[3] = bomb_pos[3] + bomb_velocity[3] * time_step -- Z position

        -- Update the bomb's vertical velocity due to gravity
        bomb_velocity[1] = bomb_velocity[1] * 0.975
        bomb_velocity[2] = bomb_velocity[2] - gravity * time_step -- Y velocity decreases due to gravity
        bomb_velocity[3] = bomb_velocity[3] * 0.975

        -- Check if bomb hits the ground (Y position <= 0)
        if bomb_pos[2] <= 0 then
            break
        end

        time = time + time_step
    end

    return bomb_pos -- The final position where the bomb hits the ground
end

local function findRelativeAngle(targetYaw,targetPitch)
    rot = ship.getQuaternion()
    cacheYaw = math.pi - math.rad(targetYaw)
    cachePitch = - math.rad(targetPitch)
    rotMatAdj11 = 1 - 2*(rot.x^2 + rot.y^2)
    rotMatAdj12 = 2*(rot.z * rot.x + rot.y * rot.w)
    rotMatAdj13 = 2*(rot.z * rot.y - rot.x * rot.w)
    rotMatAdj21 = 2*(rot.z * rot.x - rot.y * rot.w)
    rotMatAdj22 = 1 - 2*(rot.z^2 + rot.y^2)
    rotMatAdj23 = 2*(rot.x * rot.y + rot.z * rot.w)
    rotMatAdj31 = 2*(rot.z * rot.y + rot.x * rot.w)
    rotMatAdj32 = 2*(rot.x * rot.y - rot.z * rot.w)
    rotMatAdj33 = 1 - 2*(rot.z^2 + rot.x^2)

    rotMatTGT11 = math.cos(cacheYaw) * math.cos(cachePitch)
    rotMatTGT21 = math.sin(cacheYaw) * math.cos(cachePitch)
    rotMatTGT31 = - math.sin(cachePitch)
    
    rotMatRSLT11 = rotMatAdj11 * rotMatTGT11 + rotMatAdj12 * rotMatTGT21 + rotMatAdj13 * rotMatTGT31
    rotMatRSLT21 = rotMatAdj21 * rotMatTGT11 + rotMatAdj22 * rotMatTGT21 + rotMatAdj23 * rotMatTGT31
    rotMatRSLT31 = rotMatAdj31 * rotMatTGT11 + rotMatAdj32 * rotMatTGT21 + rotMatAdj33 * rotMatTGT31

    turretYaw = math.atan2(rotMatRSLT21, rotMatRSLT11)
    barrelPitch = math.asin(-rotMatRSLT31)
    return math.deg(-turretYaw),math.deg(-barrelPitch)
end

local function aimCannon(targetPos, source)
    print(textutils.serialize(source))
    print(textutils.serialize(targetPos))
    if source and targetPos then
        local dx = targetPos.x - source.x
        local dy = targetPos.y - source.y
        local dz = targetPos.z - source.z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        local horizontalDistance = math.sqrt(dx * dx + dz * dz)
        local pitch = math.deg(math.atan2(dy, horizontalDistance))

        local yaw = math.deg(math.atan2(-dx, dz))
        yaw = (yaw + 180) % 360

        local shipYaw = math.deg(ship.getYaw())
        if shipYaw < 0 then shipYaw = shipYaw + 360 end
        local shipPitch = math.deg(ship.getPitch())

        local requiredRelativeYaw = yaw - shipYaw
        if requiredRelativeYaw > 180 then
            requiredRelativeYaw = requiredRelativeYaw - 360
        elseif requiredRelativeYaw < -180 then
            requiredRelativeYaw = requiredRelativeYaw + 360
        end

        local requiredRelativeYaw,requiredRelativePitch = findRelativeAngle(yaw,pitch)

        requiredRelativePitch = requiredRelativePitch + 90
        requiredRelativeYaw = requiredRelativeYaw

        print("requiredRelativeYaw: "..requiredRelativeYaw)
        print("requiredRelativePitch: "..requiredRelativePitch)

        cannon.setPitch(requiredRelativePitch)
        cannon.setYaw(requiredRelativeYaw)
    end
end

local function hitMark()
    while true do
        if raycaster then
            local result = {}
            local shipPitch = math.deg(ship.getPitch())
            local shipRoll = math.deg(ship.getRoll())
            local shipLocation = ship.getWorldspacePosition()
            local shipVelocity = ship.getVelocity()
            var1 = math.rad(shipRoll)
            var2 = math.rad(-shipPitch)
            result = raycaster.raycast(max_distance, {0, var2}, true, true)

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
            else
                
            end

            if result and result.hitpos and result.hit_pos[2] < 0 then
                result.hit_pos[2] = 0
                result.distance = shipLocation.y - 0
            end

            if result and result.hit_pos and result.hit_pos[2] then
                print("altitude = "..shipLocation.y - result.hit_pos[2])
                
                local bombLandingPos = calculateBombLandingPosition(shipLocation, shipVelocity, shipLocation.y - result.hit_pos[2])

                aimCannon({ x = bombLandingPos[1], y = bombLandingPos[2], z = bombLandingPos[3]}, shipLocation)
            end
        end
        sleep()
    end
end

local function round(number, decimal)
    if decimal then
        local fmt_str = "%." .. decimal .. "f"
        return tonumber(string.format(fmt_str, number))
    else
        return math.floor(number + 0.5)
    end
end

local function write_at(x, y, text, colour)
    local previous_colour = MONITOR.getTextColour()
    if colour then MONITOR.setTextColour(colour) end
    MONITOR.setCursorPos(x, y)
    MONITOR.write(text)
    MONITOR.setTextColour(previous_colour)
end

local function run_async(func, ...)
    local args = { ... }
    local co = coroutine.create(
        function()
            func(unpack(args))
        end
    )
    coroutine.resume(co)
end

local function check_files_exists()
    local file_path
    for _, v in pairs(SOUNDS) do
        file_path = v[1] .. "." .. SOUND_EXTENSION_TYPE
        if not fs.exists(file_path) then
            print("MISSING SOUND: " .. file_path)
        end
    end
end

-- Audio at high speed is fucked and there's no fix 😭
local function play_sound(file_name)
    local file_path = file_name .. "." .. SOUND_EXTENSION_TYPE
    if not fs.exists(file_path) then return end
    for chunk in io.lines(file_path, 16 * 1024) do
        local buffer = DECODER(chunk)
        while not SPEAKER.playAudio(buffer, SOUND_VOLUME) do
            os.pullEvent("speaker_audio_empty")
        end
    end
end

local function check_play_sound(sound)
    if current_time - last_played[sound[1]] >= sound[2] then
        run_async(play_sound, sound[1])
        last_played[sound[1]] = current_time
    end
end

local function sound_player()
    if not SPEAKER then return end
    print("Speaker attached.")
    while true do
        -- Maybe rework the if-branching, it's kinda scuffed ngl
        if plane.has_taken_off then
            if plane.got_hit then
                check_play_sound(SOUNDS.hit_warning)
                plane.got_hit = false
            elseif plane.descending then
                if plane.rel_y < CRITICAL_GROUND_WARNING_THRESHOLD then
                    check_play_sound(SOUNDS.critical_ground_warning)
                elseif plane.rel_y < GROUND_WARNING_THRESHOLD then
                    check_play_sound(SOUNDS.ground_warning)
                end
            elseif plane.g_force > G_FORCE_WARNING_THRESHOLD then
                check_play_sound(SOUNDS.over_g_warning)
            end
        end

        sleep(DELTA_TICK / 20)
    end
end

-- Consider this function as copied from Endal
local line_types = { "\xAF", "-", "_", "|" } -- High, middle, low, vertical
local function plot_line(x0, y0, x1, y1)
    y1 = math.floor(y1 * (#line_types - 1) + 1)
    y0 = math.floor(y0 * (#line_types - 1) + 1)
    x1 = math.floor(x1)
    x0 = math.floor(x0)
    local dx = math.abs(x1 - x0)
    local sx = x0 < x1 and 1 or -1
    local dy = -math.abs(y1 - y0)
    local sy = y0 < y1 and 1 or -1
    local error = dx + dy

    while true do
        local char = dx < 3 and
            line_types[#line_types] or
            line_types[math.floor(y0 % (#line_types - 1)) + 1]
        write_at(
            x0,
            math.floor(y0 / (#line_types - 1)),
            char
        )
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * error
        if e2 >= dy then
            if x0 == x1 then break end
            error = error + dy
            x0 = x0 + sx
        end
        if e2 <= dx then
            if y0 == y1 then break end
            error = error + dx
            y0 = y0 + sy
        end
    end
end

-- Consider this function as copied from Endal
local function draw_heading()
    -- Outer arrows, draw on strip level
    write_at(1, 2, "\xAB")
    write_at(SCREEN_WIDTH, 2, "\xBB")

    local yaw_offset = math.floor(plane.yaw / 10 + 0.5)
    local adjustment = 2
    for i = 0, SCREEN_WIDTH - 2 * adjustment + 1, 1 do
        local x = i + adjustment
        write_at(
            x,
            2,
            (i + yaw_offset) % 3 == 0 and "|" or ","
        )
        if DIRECTIONS[(i + yaw_offset - 6) % 36 / 9 + 1] then
            -- N = 0, E = 9, S = 18, W = 27 --> N = 1, E = 2, S = 3, W = 4
            write_at(
                x,
                1,
                DIRECTIONS[(i + yaw_offset - 6) % 36 / 9 + 1]
            )
        end
    end

    -- Display the yaw top-mid
    local string_formatted_yaw = string.format("%03d", plane.yaw)
    write_at(math.floor(SCREEN_WIDTH / 2), 1, string_formatted_yaw)

    -- Display the arrow bottom-mid
    write_at(math.floor(SCREEN_WIDTH / 2 + 0.5), 3, "\x1E")
end

local function draw_altitude()
    local y_offset = 2
    local strip_length = 7
    -- Every 100 meters is -, every 50 is .
    local rounded_alt = 50 * math.floor(plane.rel_y / 50 + 0.5)
    local is_hundred = rounded_alt % 100 == 0

    for i = 1, strip_length do
        local char = (i % 2 == 0) == is_hundred and "-" or "\xB7"
        write_at(SCREEN_WIDTH, i + y_offset, char)
    end

    write_at(
        SCREEN_WIDTH - 1,
        math.floor((y_offset + strip_length) / 2 + 0.5) + 1,
        "\x10"
    )
    write_at(
        SCREEN_WIDTH - #tostring(round(plane.rel_y)) + 1,
        y_offset + strip_length + 1,
        tostring(round(plane.rel_y))
    )
end

local function draw_speed()
    local y_offset = 2
    local strip_length = 7

    -- Every 10 m/s is -, every 5 is .
    local rounded_alt = 5 * math.floor(plane.speed / 5 + 0.5)
    local is_ten = rounded_alt % 10 == 0

    for i = 1, strip_length do
        local char = (i % 2 == 0) == is_ten and "-" or "\xB7"
        write_at(1, i + y_offset, char)
    end

    local fraction = plane.max_speed ~= 0 and plane.speed / plane.max_speed or 0
    local indicator_height = y_offset + strip_length - fraction * strip_length + 1
    write_at(2, indicator_height, "\x11")

    local rounded_speed = round(plane.speed)
    local rounded_max_speed = round(plane.max_speed)
    local string_formatted_speed = string.format("%0" .. #tostring(rounded_max_speed) .. "d", rounded_speed)
    write_at(
        1,
        y_offset + strip_length + 1,
        string_formatted_speed .. "|" .. tostring(round(plane.g_force, 1)) .. "G"
    )
end

local function display_center()
    local self = setmetatable({}, {})
    self.init = function()
        self.center_x = 8
        self.center_y = 6
        self.width = 9
        self.height = 7

        self.min_x = self.center_x - math.floor(self.width / 2)
        self.max_x = self.center_x + math.ceil(self.width / 2)
        self.min_y = self.center_y - math.floor(self.height / 2)
        self.max_y = self.center_y + math.ceil(self.height / 2)

        self.horizon_y = 0

        self.pitch_values = {}
        for i = 90, -90, -20 do table.insert(self.pitch_values, i) end
        self.ladder_spacing = 2

        return self
    end

    self.draw = function()
        self.draw_horizon()
        self.draw_pitch_ladder()
        self.draw_center_marker()
    end

    self.draw_horizon = function()
        -- Calculate horizon line position based on pitch
        self.horizon_y = self.center_y + math.floor(plane.pitch * (self.height / 2) / 45)

        -- Calculate roll
        local rounded_roll_deg = round(plane.roll)
        local roll_rad = INVERT_ROLL and -math.rad(rounded_roll_deg) or math.rad(rounded_roll_deg)
        local dx = math.cos(roll_rad) * (self.width / 2)
        local dy = math.sin(roll_rad) * (self.width / 2)

        local x1 = math.floor(self.center_x - dx)
        local y1 = math.floor(self.horizon_y - dy)
        local x2 = math.floor(self.center_x + dx)
        local y2 = math.floor(self.horizon_y + dy)

        x1, y1 = self.clip_point(x1, y1)
        x2, y2 = self.clip_point(x2, y2)

        -- Draw the horizon line
        plot_line(x1, y1, x2, y2)
    end

    self.draw_pitch_ladder = function()
        for _, pitch in ipairs(self.pitch_values) do
            local y_offset = (-pitch / 20) * self.ladder_spacing
            local ladder_y = self.horizon_y + y_offset + 1
            local char = pitch > 0 and "\xAF" or "_"

            -- Left and right side
            self.draw_ladder_line(self.center_x - 2, ladder_y, char)
            self.draw_ladder_line(self.center_x + 2, ladder_y, char, pitch)
        end
    end

    self.draw_center_marker = function()
        write_at(self.center_x, self.center_y, "+")
    end

    -- Clip a line to stay within bounds
    self.clip_point = function(x, y)
        return math.max(self.min_x, math.min(x, self.max_x)),
            math.max(self.min_y, math.min(y, self.max_y - 1))
    end

    self.draw_ladder_line = function(x, y, char, pitch)
        -- LATER: stupid hack, otherwise the ladder will draw too low
        -- but if not >= then it will draw not high enough
        if y >= self.min_y and y < self.max_y then
            write_at(x, y, char)
            if pitch then
                local formatted_number = string.format("% 3d", pitch)
                write_at(x + 1, y, formatted_number)
            end
        end
    end

    return self
end

local function display_hud()
    if not MONITOR then return end
    print("Monitor attached.")
    MONITOR.setTextScale(0.5)
    MONITOR.setTextColour(colours.yellow)
    local CENTER_DISPLAY = display_center().init()
    while true do
        MONITOR.clear()

        CENTER_DISPLAY.draw()
        draw_heading()
        draw_altitude()
        draw_speed()

        sleep()
    end
end

local function update_information()
    local position = ship.getWorldspacePosition()
    local velocity = ship.getVelocity()
    local omega = ship.getOmega()
    local dt = DELTA_TICK / 20

    -- Linear acceleration
    local linear_ax = (velocity.x - plane.vx) / dt
    local linear_ay = (velocity.y - plane.vy) / dt
    local linear_az = (velocity.z - plane.vz) / dt
    -- Angular acceleration
    local angular_ax = (omega.x - plane.o_x) / dt
    local angular_ay = (omega.y - plane.o_y) / dt
    local angular_az = (omega.z - plane.o_z) / dt

    local combined_ax = linear_ax + angular_ax
    local combined_ay = linear_ay + angular_ay
    local combined_az = linear_az + angular_az

    plane.ax = combined_ax
    plane.ay = combined_ay
    plane.az = combined_az

    local a_magnitude = math.sqrt(plane.ax ^ 2 + plane.ay ^ 2 + plane.az ^ 2)
    plane.g_force = a_magnitude / GRAVITY

    -- At the moment, x, z aren't used.
    -- Position
    plane.x = position.x
    plane.y = position.y
    plane.z = position.z
    -- Velocity
    plane.vx = velocity.x
    plane.vy = velocity.y
    plane.vz = velocity.z

    plane.speed = math.sqrt(plane.vx ^ 2 + plane.vy ^ 2 + plane.vz ^ 2)
    plane.max_speed = math.max(plane.speed, plane.max_speed)
    -- Angular velocity
    plane.omega_x = omega.x
    plane.omega_y = omega.y
    plane.omega_z = omega.z

    -- Rotation
    plane.yaw = math.deg(ship.getYaw()) + 180
    plane.pitch = math.deg(-ship.getPitch())
    plane.roll = math.deg(-ship.getRoll())

    plane.rel_y = plane.y - GROUND_LEVEL

    if not SPEAKER then return end

    local new_mass = ship.getMass()
    if new_mass < plane.mass then
        plane.got_hit = true
    end
    plane.mass = new_mass

    if not plane.has_taken_off and plane.rel_y > TAKEN_OFF_THRESHOLD then
        plane.has_taken_off = true
    elseif plane.has_taken_off and (plane.rel_y < LANDED_THRESHOLD or ship.isStatic()) then
        plane.has_taken_off = false
    end
    plane.descending = round(plane.vy, 1) < 0
end

local function update_state()
    if SPEAKER then check_files_exists() end
    while true do
        update_information()
        current_time = current_time + DELTA_TICK
        sleep()
    end
end

-- Main loop
parallel.waitForAny(
    hitMark
)
