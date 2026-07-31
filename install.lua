-- Download one file from the Erika ComputerCraft Code repository.
-- Usage: install <repository path> [destination] [--force]

local REPOSITORY = "MegiTicky/Erika-cc-code"
local BRANCH = "main"

local function usage()
    print("Usage: install <repository path> [destination] [--force]")
    print("Example: install Utility/matrix.lua matrix.lua")
end

-- Encode bytes rather than relying on a particular ComputerCraft textutils
-- implementation. Slashes are handled separately so path components remain
-- path components in the raw GitHub URL.
local function encodeComponent(component)
    return (component:gsub("[^A-Za-z0-9%-._~]", function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end

local function encodePath(path)
    local encoded = {}
    for component in path:gmatch("[^/]+") do
        encoded[#encoded + 1] = encodeComponent(component)
    end
    return table.concat(encoded, "/")
end

local function basename(path)
    local normalized = path:gsub("\\", "/")
    return normalized:match("([^/]+)$")
end

local sourcePath, destination, force = ...
if not sourcePath or sourcePath == "" then
    usage()
    return
end

if destination == "--force" then
    force = destination
    destination = nil
end

if force ~= "--force" then
    force = false
end

destination = destination or basename(sourcePath)
if not destination or destination == "" then
    printError("Could not determine a destination filename.")
    return
end

if fs.exists(destination) and not force then
    printError("Refusing to overwrite existing file: " .. destination)
    print("Use --force to replace it.")
    return
end

local url = "https://raw.githubusercontent.com/" .. REPOSITORY .. "/" .. BRANCH .. "/" .. encodePath(sourcePath)
print("Downloading " .. sourcePath .. "...")

local response, reason = http.get(url)
if not response then
    printError("Download failed: " .. tostring(reason))
    return
end

local status = response.getResponseCode and response.getResponseCode() or 200
if status ~= 200 then
    response.close()
    printError("Download failed with HTTP status " .. tostring(status))
    return
end

local contents = response.readAll()
response.close()

local parent = fs.getDir(destination)
if parent and parent ~= "" and not fs.exists(parent) then
    fs.makeDir(parent)
end

local file, openReason = fs.open(destination, "w")
if not file then
    printError("Could not write " .. destination .. ": " .. tostring(openReason))
    return
end

file.write(contents)
file.close()
print("Installed " .. destination)
