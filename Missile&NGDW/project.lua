function get_view_rotation_matrix(orientation)
    local ori_rad = {math.rad(orientation.x), math.rad(orientation.y), math.rad(orientation.z)}
    local Rx = {
        {math.cos(ori_rad[1]), -math.sin(ori_rad[1]), 0, 0},
        {math.sin(ori_rad[1]), math.cos(ori_rad[1]), 0, 0},
        {0, 0, 1, 0},
        {0, 0, 0, 1}
    }
    local Ry = {
        {1, 0, 0, 0},
        {0, math.cos(ori_rad[2]), -math.sin(ori_rad[2]), 0},
        {0, math.sin(ori_rad[2]), math.cos(ori_rad[2]), 0},
        {0, 0, 0, 1}
    }
    local Rz = {
        {math.cos(ori_rad[3]), 0, math.sin(ori_rad[3]), 0},
        {0, 1, 0, 0},
        {-math.sin(ori_rad[3]), 0, math.cos(ori_rad[3]), 0},
        {0, 0, 0, 1}
    }
    return mattranspose(matmul(matmul(Rz, Ry), Rx))  -- Combine rotations
end

function get_projection_matrix(cameraSetting)
    local thv = math.tan(math.rad(cameraSetting.vfov_deg) * 0.5)
    return {
        {1 / (cameraSetting.aspect_ratio * thv), 0, 0, 0},
        {0, 1 / thv, 0, 0},
        {0, 0, -(cameraSetting.far + cameraSetting.near) / (cameraSetting.far - cameraSetting.near), -(2 * cameraSetting.far * cameraSetting.near) / (cameraSetting.far - cameraSetting.near)},
        {0, 0, -1, 0}
    }
end

-- Project a 3D point onto the 2D screen
function projectToScreen(point, camera)
    -- Convert 3D point to 4D homogeneous coordinates
    local vertex_4d = {{point.x}, {point.y}, {point.z}, {1}}
    local camera_pos_4d = {{camera.position.x}, {camera.position.y}, {camera.position.z}, {1}}
    --print(textutils.serialize(vertex_4d))
    --print(textutils.serialize(camera_pos_4d))
    -- Translate the point to camera space
    local translated = matsub(vertex_4d, camera_pos_4d)
    --print(textutils.serialize(translated))
    -- Apply view rotation
    rotationMatrix = get_view_rotation_matrix(camera.orientation)
    --print(textutils.serialize(rotationMatrix))
    local rotated = matmul(rotationMatrix, translated)
    --print(textutils.serialize(rotated))

    -- Check if the point is behind the camera (near plane clipping)
    --print(rotated[3][1])
    if rotated[3][1] <= camera.near then return nil, nil end

    -- Apply the projection matrix
    local projected = matmul(get_projection_matrix(camera), rotated)

    -- Perspective divide (normalize by w)
    projected = matscalarmul(projected, 1 / projected[4][1])
    print(projected[1][1], projected[2][1])
    --print(camera.screen_width, camera.screen_height)
    -- Convert to screen coordinates
    --local screen_x = math.floor((-projected[1][1] + 0.5) * camera.screen_width / 2)
    --local screen_y = math.floor(camera.screen_height / 2)
    local screen_x = math.floor((projected[1][1] + 1) * camera.screen_width / 2)
    local screen_y = math.floor((1 - projected[2][1]) * camera.screen_height / 2)

    print(screen_x, screen_y)

    return screen_x, screen_y
end