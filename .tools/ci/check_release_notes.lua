local M = {}
local languages = { "enUS", "deDE", "frFR" }

local function version(value)
    assert(type(value) == "string" and #value <= 24, "Invalid release version")
    local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then major, minor = value:match("^(%d+)%.(%d+)$"); patch = "0" end
    if not major then major, minor, patch = value:match("^(%d+)$"), "0", "0" end
    assert(major, "Expected a stable numeric release version")
    local parts = { tonumber(major), tonumber(minor), tonumber(patch) }
    for _, part in ipairs(parts) do assert(part <= 999999, "Release version component is too large") end
    return parts, table.concat(parts, ".")
end

local function less(left, right)
    for index = 1, 3 do
        if left[index] ~= right[index] then return left[index] < right[index] end
    end
    return false
end

local function normalized(text)
    return text:gsub("\194\160", " "):gsub("\226\128\175", " ")
        :gsub("%s+", " "):match("^%s*(.-)%s*$")
end

function M.Validate(addon, expectedVersion)
    local currentVersion = addon.Constants.ADDON_VERSION
    local current = version(currentVersion)
    assert(not expectedVersion or expectedVersion == currentVersion,
        "TOC and runtime versions disagree")
    if less(current, { 1, 2, 0 }) then return false end

    local notes = assert(addon.ReleaseNotes, "Release notes module is missing")
    local entry = assert(notes.GetCurrent(), "Missing or invalid current release notes in Data/ReleaseNotes.lua")
    for _, locale in ipairs(languages) do
        assert(type(entry[locale]) == "string" and normalized(entry[locale]) ~= "",
            "Current release notes are missing content for " .. locale)
    end

    local seen, previous = {}, 0
    for _, name in ipairs(notes.GetVersions()) do
        local parts, key = version(name)
        assert(not seen[key], "Duplicate equivalent release versions in Data/ReleaseNotes.lua")
        seen[key] = true
        if less(parts, current) then
            local older = assert(notes.Get(name), "Invalid historical release notes: " .. key)
            previous = previous + 1
            for _, locale in ipairs(languages) do
                assert(not older[locale] or normalized(entry[locale]) ~= normalized(older[locale]),
                    "Release notes for " .. locale .. " repeat version " .. key)
            end
        end
    end
    assert(previous > 0 or not less({ 1, 2, 0 }, current),
        "Retain previous release notes so the current content can be compared")
    return true
end

function M.Run(root, expectedVersion)
    assert(type(root) == "string" and root ~= "", "Repository root is required")
    if not expectedVersion then
        local toc = assert(io.open(root .. "/TRP3_RPSpellbook/TRP3_RPSpellbook.toc", "rb"))
        for line in toc:lines() do
            local value = line:match("^##%s+Version:%s*(.-)%s*$")
            if value then
                assert(not expectedVersion, "Duplicate TOC version")
                expectedVersion = value
            end
        end
        assert(toc:close())
        assert(expectedVersion, "Missing TOC version")
    end

    local env = {}
    for _, name in ipairs({ "assert", "error", "ipairs", "pairs", "tonumber", "tostring",
        "type", "getmetatable", "setmetatable" }) do env[name] = _G[name] end
    for _, name in ipairs({ "math", "string", "table" }) do
        env[name] = {}
        for key, value in pairs(_G[name]) do env[name][key] = value end
    end
    env.math.random, env.math.randomseed, env.string.dump = nil, nil, nil
    local addon = {}
    local function loadSource(path)
        local chunk = assert(loadfile(root .. "/TRP3_RPSpellbook/" .. path))
        setfenv(chunk, env)("TRP3_RPSpellbook", addon)
    end
    loadSource("Constants.lua")
    if less(version(addon.Constants.ADDON_VERSION), { 1, 2, 0 }) then
        return M.Validate(addon, expectedVersion)
    end
    loadSource("Core/ConstantsExtension.lua")
    loadSource("Data/ReleaseNotes.lua")
    return M.Validate(addon, expectedVersion)
end

if arg and type(arg[0]) == "string" and arg[0]:match("check_release_notes%.lua$") then
    local ok, result = pcall(M.Run, arg[1], arg[2])
    if not ok then
        io.stderr:write("Release notes check failed: ", tostring(result), "\n")
        os.exit(1)
    end
    print(result and "PASS: release notes are complete and differ from older releases"
        or "SKIP: release notes content check starts at version 1.2")
end

return M
