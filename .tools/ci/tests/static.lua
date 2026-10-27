local root = ...
local F = {}
F.releaseCheck = assert(loadfile(root .. "/.tools/ci/check_release_notes.lua"))().Validate

local modules = {
    constants = { "Constants.lua", "Constants" },
    extensions = { "Core/ConstantsExtension.lua", "Constants" },
    localization = { "Localization.lua", "Localization", "GetLocale", "SetLanguage" },
    english = { "Locales/enUS.lua", "Localization" },
    german = { "Locales/deDE.lua", "Localization" },
    french = { "Locales/frFR.lua", "Localization" },
    presets = { "SpellCreation/Presets.lua", "SpellCreationPresets", "NormalizeField", "NormalizeSpell" },
    notes = { "Data/ReleaseNotes.lua", "ReleaseNotes", "Get", "GetVersions", "GetCurrent", "Copy" },
    portable = { "Data/PortableTable.lua", "PortableTable", "Encode", "Decode" },
    validators = {
        "Data/Validators.lua", "Validators", "ValidateSpell", "ValidateTab",
    },
    backup = {
        "Data/BackupValidation.lua", "BackupValidation", "Clone", "Book", "Rebind",
    },
}
local plans = {
    releaseNotes = { "constants", "extensions", "notes" },
    portable = { "portable" },
    validators = { "constants", "localization", "english", "german", "french", "presets", "validators" },
    backup = { "constants", "portable", "localization", "english", "german", "french", "presets", "validators", "backup" },
}

local function environment()
    local env = {}

    for _, name in ipairs({
        "assert", "error", "ipairs", "pairs", "next", "pcall",
        "tonumber", "tostring", "type", "getmetatable", "setmetatable", "select",
    })
    do 
    env[name] = _G[name] 
    end

    for _, name in ipairs({ "math", "string", "table" }) 

    do
        env[name] = {}

        for key, value in pairs(_G[name]) 
        do env[name][key] = value 

        end

    end

    env.math.random, env.math.randomseed = nil, nil
    env._G = env

    return setmetatable(env, {

        __index = function(_, key)
            error("Unexpected global/API read: " .. tostring(key), 2)

        end,

        __newindex = function(_, key)
            error("Unexpected global/API write: " .. tostring(key), 2)
        end,
    })
end


function F.runner(path)
    return setfenv(assert(loadfile(path)), environment())()
end

function F.fresh(area)

    local plan = assert(plans[area], "Unsupported production area: " .. area)

    local addon = setmetatable({
        L = function(key) assert(type(key) == "string"); 
        return key 
        end,

    }, 

    {
        __index = function(_, key)
            if key == "SpellPresentation" then 
            return nil 
            end

            error("Unexpected addon dependency: " .. tostring(key), 2)
        end,
    })

    local env, api = environment(), {}
    if area == "validators" or area == "backup" then
        rawset(env, "GetLocale", function() return "enUS" end)
        rawset(env, "TRP3_RPSpellbookDB", { settings = {} })
    end

    for _, key in ipairs(plan) 
    do

        local entry = modules[key]
        local chunk = assert(loadfile(
            root .. "/TRP3_RPSpellbook/" .. entry[1]))

        setfenv(chunk, env)("TRP3_RPSpellbook", addon)

        local export = rawget(addon, entry[2])

        assert(type(export) == "table", "Missing export: " .. entry[2])
        for index = 3, #entry 
        do
            assert(type(export[entry[index]]) == "function",
                "Missing function: " .. entry[2] .. "." .. entry[index])

        end
        api[key] = export
    end
    return api
end


function F.copy(value)

    if type(value) ~= "table" then 
    return value 
    end

    local result = {}

    for key, child in pairs(value) 
    do result[key] = F.copy(child) 
    end

    return result
end

function F.equal(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then 
    return left == right 
    end

    for key, value in pairs(left) 
    do
        if not F.equal(value, right[key]) then 
        return false 
        end

    end

    for key in pairs(right) 
    do 
    if left[key] == nil then 
    return false 
    end 

    end

    return true

end

function F.spell(fields)
    local spell = { name = "Spark" }

    for key, value in pairs(fields or {}) 
    do spell[key] = value 
    end

    return spell
end

function F.book(key)
    return {
        id = "book_" .. key, profileKey = key,
        tabs = { general = {
            id = "general", name = "General", spellIds = { "spark" },
        } },
        tabOrder = { "general" },
        spells = { spark = F.spell({ id = "spark", ownerKey = key }) },
        favorites = { spark = true },
    }
end

function F.binding(key)
    key = key or "source"
    return { profiles = { [key] = {
        profileKey = key, owner = { profileKey = key }, spellbook = F.book(key),
    } } }
end

return F
