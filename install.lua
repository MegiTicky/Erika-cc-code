-- Download files from the Erika ComputerCraft Code repository.
-- With no arguments, show the operator installation menu.
-- Usage: install [event lieyu_phase_2|riverbend_coldwar] [--force]
--        install <repository path> [destination] [--force]
--        install bundle <manifest path> [--force]

local REPOSITORY = "MegiTicky/Erika-cc-code"
local BRANCH = "main"

local function usage()
    print("Usage: install")
    print("       install event lieyu_phase_2 [--force]")
    print("       install <repository path> [destination] [--force]")
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

local PROFILES = {
    lieyu_phase_2 = {
        label = "Lieyu Phase 2 - Complete Event System",
        manifest = "Grandop/manifests/phase_2_complete.txt",
    },
    riverbend_coldwar = {
        label = "Riverbend Cold War - Frontline Event",
        manifest = "Grandop/manifests/riverbend_event.txt",
    },
}

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

local function fetch(url, failureLabel)
    local response, reason = http.get(url)
    if not response then
        printError(failureLabel .. " failed: " .. tostring(reason))
        return nil
    end

    local status = response.getResponseCode and response.getResponseCode() or 200
    if status ~= 200 then
        response.close()
        printError(failureLabel .. " failed with HTTP status " .. tostring(status))
        return nil
    end

    local contents = response.readAll()
    response.close()
    return contents
end

local function readManifest(manifestPath)
    local url = "https://raw.githubusercontent.com/" .. REPOSITORY .. "/" .. BRANCH .. "/" .. encodePath(manifestPath)
    local manifest = fetch(url, "Manifest download")
    if not manifest then return nil end

    local entries = {}
    for line in manifest:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local source, target = line:match("^([^|]+)|(.+)$")
            if not source then
                printError("Invalid manifest line: " .. line)
                return nil
            end
            entries[#entries + 1] = {
                source = source:gsub("^%s+", ""):gsub("%s+$", ""),
                target = target:gsub("^%s+", ""):gsub("%s+$", ""),
            }
        end
    end
    return entries
end

local function installEntries(entries, overwrite)
    local installed = 0
    for _, entry in ipairs(entries) do
        if not download(entry.source, entry.target, overwrite) then return false end
        installed = installed + 1
    end
    print("Installed " .. installed .. " files")
    return true
end

local function askOverwrite(entries)
    local existing = {}
    for _, entry in ipairs(entries) do
        if fs.exists(entry.target) then existing[#existing + 1] = entry.target end
    end
    if #existing == 0 then return true end

    print("The selected install will replace " .. #existing .. " existing file(s).")
    print("Replace all selected files? (y/n)")
    local answer = io.read()
    return answer and answer:lower() == "y"
end

local function installManifest(manifestPath, overwrite, profileLabel)
    print("Loading " .. (profileLabel or manifestPath) .. "...")
    local entries = readManifest(manifestPath)
    if not entries then return false end
    if not overwrite and not askOverwrite(entries) then
        print("Installation cancelled.")
        return false
    end
    return installEntries(entries, true)
end

local function showMenu()
    print("=== Erika ComputerCraft Installer ===")
    print("1. " .. PROFILES.lieyu_phase_2.label)
    print("2. " .. PROFILES.riverbend_coldwar.label)
    print("3. Exit")
    io.write("Select an option: ")
    local choice = io.read()
    if choice == "1" then
        return installManifest(PROFILES.lieyu_phase_2.manifest, false, PROFILES.lieyu_phase_2.label)
    elseif choice == "2" then
        return installManifest(PROFILES.riverbend_coldwar.manifest, false, PROFILES.riverbend_coldwar.label)
    end
    print("Installation cancelled.")
    return false
end

if not sourcePath then
    showMenu()
    return
end

if sourcePath == "event" then
    local profile = PROFILES[destination]
    if not profile then
        usage()
        return
    end
    installManifest(profile.manifest, force == "--force", profile.label)
    return
end

if sourcePath == "bundle" then
    local manifestPath = destination
    if not manifestPath or manifestPath == "" then
        usage()
        return
    end
    installManifest(manifestPath, force == "--force")
    return
end

if sourcePath == "" then
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
