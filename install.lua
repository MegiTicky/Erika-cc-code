-- Download one file from the Erika ComputerCraft Code repository.
-- Usage: install <repository path> [destination] [--force]

local REPOSITORY = "MegiTicky/Erika-cc-code"
local BRANCH = "main"

local function usage()
    print("Usage: install <repository path> [destination] [--force]")
    print("       install bundle <manifest path> [--force]")
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

local function download(source, target, overwrite)
    if fs.exists(target) and not overwrite then
        printError("Refusing to overwrite existing file: " .. target)
        print("Use --force to replace it.")
        return false
    end

    local url = "https://raw.githubusercontent.com/" .. REPOSITORY .. "/" .. BRANCH .. "/" .. encodePath(source)
    print("Downloading " .. source .. "...")

    local response, reason = http.get(url)
    if not response then
        printError("Download failed: " .. tostring(reason))
        return false
    end

    local status = response.getResponseCode and response.getResponseCode() or 200
    if status ~= 200 then
        response.close()
        printError("Download failed with HTTP status " .. tostring(status))
        return false
    end

    local contents = response.readAll()
    response.close()

    local parent = fs.getDir(target)
    if parent and parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end

    local file, openReason = fs.open(target, "w")
    if not file then
        printError("Could not write " .. target .. ": " .. tostring(openReason))
        return false
    end

    file.write(contents)
    file.close()
    print("Installed " .. target)
    return true
end

if sourcePath == "bundle" then
    local manifestPath = destination
    local overwrite = force == "--force"
    if not manifestPath or manifestPath == "" then
        usage()
        return
    end

    local manifestUrl = "https://raw.githubusercontent.com/" .. REPOSITORY .. "/" .. BRANCH .. "/" .. encodePath(manifestPath)
    local response, reason = http.get(manifestUrl)
    if not response then
        printError("Manifest download failed: " .. tostring(reason))
        return
    end

    local status = response.getResponseCode and response.getResponseCode() or 200
    if status ~= 200 then
        response.close()
        printError("Manifest download failed with HTTP status " .. tostring(status))
        return
    end

    local manifest = response.readAll()
    response.close()

    local installed = 0
    for line in manifest:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local source, target = line:match("^([^|]+)|(.+)$")
            if not source then
                printError("Invalid manifest line: " .. line)
                return
            end
            source = source:gsub("^%s+", ""):gsub("%s+$", "")
            target = target:gsub("^%s+", ""):gsub("%s+$", "")
            if not download(source, target, overwrite) then return end
            installed = installed + 1
        end
    end
    print("Bundle installed: " .. installed .. " files")
    return
end

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

download(sourcePath, destination, force)
