local function entry(label)
    return { enUS = label .. " English", deDE = label .. " German", frFR = label .. " French" }
end

local function subject(api, current, history)
    return { Constants = { ADDON_VERSION = current }, ReleaseNotes = {
        GetCurrent = function() return api.notes.Copy(history[current]) end,
        Get = function(key) return api.notes.Copy(history[key]) end,
        GetVersions = function()
            local keys = {}
            for key in pairs(history) do keys[#keys + 1] = key end
            return keys
        end,
    } }
end

local function rejects(t, F, addon, expected)
    local ok, message = pcall(F.releaseCheck, addon, expected)
    t.eq(ok, false)
    t.eq(type(message), "string")
end

return {
    format = 1, area = "releaseNotes", count = 11,

    { id = "release-notes.actual-runtime", run = function(t, api, F)
        t.eq(type(F.releaseCheck({ Constants = api.constants, ReleaseNotes = api.notes })), "boolean")
    end },

    { id = "release-notes.starts-at-1-2", run = function(t, api, F)
        for _, value in ipairs({ "1", "1.0", "1.1", "1.1.999" }) do
            t.eq(F.releaseCheck({ Constants = { ADDON_VERSION = value } }), false)
        end
        t.eq(F.releaseCheck(subject(api, "1.1", { ["1.1"] = { enUS = "|Hbad" } })), false)
        rejects(t, F, subject(api, "1.2", {}))
        rejects(t, F, subject(api, "1.2.0", {}))
        rejects(t, F, subject(api, "1.10", {}))
        rejects(t, F, subject(api, "2.0", {}))
    end },

    { id = "release-notes.complete-changed-content", run = function(t, api, F)
        t.eq(F.releaseCheck(subject(api, "1.2", { ["1.1"] = entry("Old"), ["1.2"] = entry("New") }), "1.2"), true)
        t.eq(F.releaseCheck(subject(api, "1.10", { ["1.9"] = entry("Old"), ["1.10"] = entry("New") })), true)
    end },

    { id = "release-notes.requires-every-locale", run = function(t, api, F)
        for _, locale in ipairs({ "enUS", "deDE", "frFR" }) do
            for _, value in ipairs({ false, "", "   ", "\n\n", "|Hbad", string.rep("x", 1201) }) do
                local current = entry("New")
                current[locale] = value
                rejects(t, F, subject(api, "1.2", { ["1.1"] = entry("Old"), ["1.2"] = current }))
            end
        end
    end },

    { id = "release-notes.each-locale-must-change", run = function(t, api, F)
        for _, locale in ipairs({ "enUS", "deDE", "frFR" }) do
            local old, current = entry("Old"), entry("New")
            current[locale] = old[locale]
            rejects(t, F, subject(api, "1.2", { ["1.1"] = old, ["1.2"] = current }))
            current[locale] = " \n" .. old[locale]:gsub(" ", "\194\160") .. "\n "
            rejects(t, F, subject(api, "1.2", { ["1.1"] = old, ["1.2"] = current }))
        end
    end },

    { id = "release-notes.compares-all-older-releases", run = function(t, api, F)
        rejects(t, F, subject(api, "1.3", { ["1.1"] = entry("First"), ["1.2"] = entry("Second"), ["1.3"] = entry("First") }))
        t.eq(F.releaseCheck(subject(api, "1.2", { ["1.1"] = entry("First"), ["1.2"] = entry("Second"), ["1.3"] = entry("Second") })), true)
    end },

    { id = "release-notes.exact-current-key-and-history", run = function(t, api, F)
        rejects(t, F, subject(api, "1.2.1", { ["1.2.1"] = entry("New") }))
        rejects(t, F, subject(api, "1.2", { ["1.1"] = entry("Old"), ["1.2.0"] = entry("New") }))
        rejects(t, F, subject(api, "1.2", { ["1.1"] = entry("Old"), ["1.1.0"] = entry("Old"), ["1.2"] = entry("New") }))
    end },

    { id = "release-notes.first-documented-release", run = function(t, api, F)
        for _, current in ipairs({ "1.2", "1.2.0" }) do
            t.eq(F.releaseCheck(subject(api, current, { [current] = entry("First") })), true)
        end
        for _, current in ipairs({ "1.2.1", "1.3", "2.0" }) do
            rejects(t, F, subject(api, current, { [current] = entry("Next") }))
            t.eq(F.releaseCheck(subject(api, current, { ["1.2.0"] = entry("First"), [current] = entry("Next") })), true)
            rejects(t, F, subject(api, current, { ["1.2.0"] = entry("First"), [current] = entry("First") }))
        end
        rejects(t, F, subject(api, "1.2.0", { ["1.2.0"] = { enUS = "Incomplete" } }))
    end },

    { id = "release-notes.metadata-cannot-skip-check", run = function(t, api, F)
        rejects(t, F, { Constants = { ADDON_VERSION = "1.1" } }, "1.2")
        rejects(t, F, subject(api, "1.2", { ["1.1"] = entry("Old"), ["1.2"] = entry("New") }), "1.2.0")
        for _, value in ipairs({ "1.2-beta", "bad", "1.2.3.4", "1000000.0" }) do
            rejects(t, F, { Constants = { ADDON_VERSION = value } })
        end
    end },

    { id = "release-notes.history-exports-are-detached", run = function(t, api)
        t.eq(type(api.notes.GetVersions()), "table")
        for _, version in ipairs(api.notes.GetVersions()) do
            local current = api.notes.Get(version)
            if current then
                local before = current.enUS
                current.enUS = "Changed externally"
                t.eq(api.notes.Get(version).enUS, before)
            end
        end
        local versions = api.notes.GetVersions()
        versions[1] = "Changed externally"
        for _, value in ipairs(api.notes.GetVersions()) do t.eq(value ~= "Changed externally", true) end
    end },

    { id = "release-notes.rejects-broken-old-history", run = function(t, api, F)
        rejects(t, F, subject(api, "1.2", { ["1.1"] = { enUS = "|Hbad" }, ["1.2"] = entry("New") }))
        rejects(t, F, subject(api, "1.2", { invalid = entry("Old"), ["1.2"] = entry("New") }))
    end },
}
