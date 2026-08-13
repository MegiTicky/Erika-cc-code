-- Load Grandop modules from the computer root regardless of the caller's
-- directory. ComputerCraft versions differ in how require() resolves paths.

local nativeRequire = require

function require(name)
    if package.loaded[name] then
        return package.loaded[name]
    end

    local path = "/" .. name:gsub("%.", "/") .. ".lua"
    local chunk, reason = loadfile(path)
    if not chunk then
        return nativeRequire(name)
    end

    local result = chunk()
    package.loaded[name] = result or true
    return package.loaded[name]
end
