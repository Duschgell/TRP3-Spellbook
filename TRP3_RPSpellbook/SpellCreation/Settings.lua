local _, addon = ...

addon.SpellCreationSettings = {
    initialized = false,
}

local defaults = {
    bookPresentation = "fancy",
    editorTheme = "default",
    timeMode = "rounds",
    showMagicSubtypes = true,
}

local editorThemes = {
    default = true,
    midnight = true,
    parchment = true,
    emerald = true,
    titan = true,
    dynamic = true,
}
local listeners = {}
local REDUCED_MOTION_KEY = "rpspellbook_fancy_reduced_motion"

local function notifyListeners()
    for _, listener in ipairs(listeners) do
        local success, errorMessage = pcall(listener)
        if not success and addon.Logger
            and type(addon.Logger.Error) == "function"
        then
            addon.Logger.Error(tostring(errorMessage))
        end
    end
end

local function getConfiguration()
    local api = _G.TRP3_API
    local configuration = type(api) == "table" and api.configuration or nil
    return type(configuration) == "table" and configuration or nil
end

local function registerKey(configuration, key, defaultValue)
    return type(configuration.registerConfigKey) == "function"
        and pcall(configuration.registerConfigKey, key, defaultValue)
end

function addon.SpellCreationSettings.Initialize()
    if addon.SpellCreationSettings.initialized then
        return true
    end
    local configuration = getConfiguration()
    if not configuration then
        return false, addon.L("TRP3_API_UNAVAILABLE", "configuration")
    end
    local constants = addon.Constants
    if not registerKey(
        configuration,
        constants.SPELL_CREATION_SETTING_TIME_MODE,
        defaults.timeMode
    ) or not registerKey(
        configuration,
        constants.SPELL_CREATION_SETTING_EDITOR_THEME,
        defaults.editorTheme
    ) or not registerKey(
        configuration,
        constants.SPELLBOOK_SETTING_PRESENTATION,
        defaults.bookPresentation
    ) or not registerKey(
        configuration,
        constants.SPELL_CREATION_SETTING_MAGIC_SUBTYPES,
        defaults.showMagicSubtypes
    ) or not registerKey(
        configuration,
        "rpspellbook_currently_effects",
        false
    ) or not registerKey(
        configuration,
        REDUCED_MOTION_KEY,
        false
    ) or not registerKey(
        configuration,
        "rpspellbook_effect_bar_locked",
        false
    ) or not registerKey(
        configuration,
        "rpspellbook_update_notifications",
        true
    ) then
        return false, addon.L("TRP3_API_UNAVAILABLE", "registerConfigKey")
    end
    if type(configuration.registerHandler) == "function" then
        pcall(configuration.registerHandler, {
            constants.SPELL_CREATION_SETTING_TIME_MODE,
            constants.SPELL_CREATION_SETTING_EDITOR_THEME,
            constants.SPELLBOOK_SETTING_PRESENTATION,
            constants.SPELL_CREATION_SETTING_MAGIC_SUBTYPES,
            "rpspellbook_currently_effects",
            REDUCED_MOTION_KEY,
            "rpspellbook_effect_bar_locked",
            "rpspellbook_update_notifications",
        }, notifyListeners)
    end
    registerKey(configuration, "rpspellbook_aura_nameplates", false)
    addon.SpellCreationSettings.initialized = true
    notifyListeners()
    return true
end

function addon.SpellCreationSettings.RegisterListener(listener)
    if type(listener) ~= "function" then
        return false
    end
    listeners[#listeners + 1] = listener
    return true
end

function addon.SpellCreationSettings.GetBookPresentation()
    local configuration = getConfiguration()
    if configuration and type(configuration.getValue) == "function" then
        local success, value = pcall(
            configuration.getValue,
            addon.Constants.SPELLBOOK_SETTING_PRESENTATION
        )
        if success and (value == "default" or value == "fancy") then
            return value
        end
    end
    return defaults.bookPresentation
end

function addon.SpellCreationSettings.IsFancyMode()
    return addon.SpellCreationSettings.GetBookPresentation() == "fancy"
end

function addon.SpellCreationSettings.ShouldReduceBookMotion()
    local configuration = getConfiguration()
    if configuration and type(configuration.getValue) == "function" then
        local ok, value = pcall(configuration.getValue, REDUCED_MOTION_KEY)
        return ok and value == true
    end
    return false
end

function addon.SpellCreationSettings.GetEditorTheme()
    local configuration = getConfiguration()
    if configuration and type(configuration.getValue) == "function" then
        local success, value = pcall(
            configuration.getValue,
            addon.Constants.SPELL_CREATION_SETTING_EDITOR_THEME
        )
        if success and editorThemes[value] then
            return value
        end
    end
    return defaults.editorTheme
end

function addon.SpellCreationSettings.GetTimeMode()
    local configuration = getConfiguration()
    if configuration and type(configuration.getValue) == "function" then
        local success, value = pcall(
            configuration.getValue,
            addon.Constants.SPELL_CREATION_SETTING_TIME_MODE
        )
        if success and (value == "rounds" or value == "time") then
            return value
        end
    end
    return defaults.timeMode
end

function addon.SpellCreationSettings.ShouldShowMagicSubtypes()
    local configuration = getConfiguration()
    if configuration and type(configuration.getValue) == "function" then
        local success, value = pcall(
            configuration.getValue,
            addon.Constants.SPELL_CREATION_SETTING_MAGIC_SUBTYPES
        )
        if success and type(value) == "boolean" then
            return value
        end
    end
    return defaults.showMagicSubtypes
end

function addon.SpellCreationSettings.ShouldPublishCurrentlyEffects()
    local configuration = getConfiguration()
    if configuration and type(configuration.getValue) == "function" then
        local ok, value = pcall(configuration.getValue, "rpspellbook_currently_effects")
        return ok and value == true
    end
    return false
end

function addon.SpellCreationSettings.ShouldNotifyUpdates()
    local configuration = getConfiguration()
    if configuration and type(configuration.getValue) == "function" then
        local ok, value = pcall(configuration.getValue, "rpspellbook_update_notifications")
        if ok and type(value) == "boolean" then return value end
    end
    return true
end

function addon.SpellCreationSettings.GetPageElements()
    local constants = addon.Constants
    local elements = {
        {
            inherit = "TRP3_ConfigH1",
            title = addon.L("SPELL_CREATION_SETTINGS_HEADER"),
        },
        {
            inherit = "TRP3_ConfigParagraph",
            title = addon.L("SPELL_CREATION_SETTINGS_DESCRIPTION"),
        },
        {
            inherit = "TRP3_ConfigCheck",
            title = addon.L("UPDATE_SETTING"),
            help = addon.L("UPDATE_SETTING_HELP"),
            configKey = "rpspellbook_update_notifications",
        },
        {
            inherit = "TRP3_ConfigDropDown",
            title = addon.L("SPELLBOOK_SETTING_PRESENTATION"),
            help = addon.L("SPELLBOOK_SETTING_PRESENTATION_HELP"),
            configKey = constants.SPELLBOOK_SETTING_PRESENTATION,
            listContent = {
                { addon.L("SPELLBOOK_PRESENTATION_DEFAULT"), "default" },
                { addon.L("SPELLBOOK_PRESENTATION_FANCY"), "fancy" },
            },
        },
        {
            inherit = "TRP3_ConfigCheck",
            title = addon.L("FANCY_REDUCED_MOTION"),
            help = addon.L("FANCY_REDUCED_MOTION_HELP"),
            configKey = REDUCED_MOTION_KEY,
        },
        {
            inherit = "TRP3_ConfigDropDown",
            title = addon.L("SPELL_CREATION_SETTING_TIME_MODE"),
            help = addon.L("SPELL_CREATION_SETTING_TIME_MODE_HELP"),
            configKey = constants.SPELL_CREATION_SETTING_TIME_MODE,
            listContent = {
                { addon.L("SPELL_CREATION_TIME_MODE_ROUNDS"), "rounds" },
                { addon.L("SPELL_CREATION_TIME_MODE_TIME"), "time" },
            },
        },
        {
            inherit = "TRP3_ConfigDropDown",
            title = addon.L("SPELL_CREATION_SETTING_EDITOR_THEME"),
            help = addon.L("SPELL_CREATION_SETTING_EDITOR_THEME_HELP"),
            configKey = constants.SPELL_CREATION_SETTING_EDITOR_THEME,
            listContent = {
                { addon.L("SPELL_CREATION_EDITOR_THEME_DEFAULT"), "default" },
                { addon.L("SPELL_CREATION_EDITOR_THEME_MIDNIGHT"), "midnight" },
                { addon.L("SPELL_CREATION_EDITOR_THEME_PARCHMENT"), "parchment" },
                { addon.L("SPELL_CREATION_EDITOR_THEME_EMERALD"), "emerald" },
                { addon.L("SPELL_CREATION_EDITOR_THEME_TITAN"), "titan" },
                { addon.L("SPELL_CREATION_EDITOR_THEME_DYNAMIC"), "dynamic" },
            },
        },
        {
            inherit = "TRP3_ConfigCheck",
            title = addon.L("SPELL_CREATION_SETTING_MAGIC_SUBTYPES"),
            help = addon.L("SPELL_CREATION_SETTING_MAGIC_SUBTYPES_HELP"),
            configKey = constants.SPELL_CREATION_SETTING_MAGIC_SUBTYPES,
        },
        {
            inherit = "TRP3_ConfigCheck",
            title = addon.L("AURA_NAMEPLATES"),
            help = addon.L("AURA_NAMEPLATES_HELP"),
            configKey = "rpspellbook_aura_nameplates",
        },
        {
            inherit = "TRP3_ConfigCheck",
            title = addon.L("CURRENTLY_EFFECTS_SETTING"),
            help = addon.L("CURRENTLY_EFFECTS_HELP"),
            configKey = "rpspellbook_currently_effects",
        },
    }
    local effectElements = addon.EffectBar and addon.EffectBar.GetSettingsElements() or {}
    for _, element in ipairs(effectElements) do elements[#elements + 1] = element end
    return elements
end
