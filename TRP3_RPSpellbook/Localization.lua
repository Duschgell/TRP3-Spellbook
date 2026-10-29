local _, addon = ...

local Localization = {
    fallbackLocale = "enUS",
    translations = {},
}
addon.Localization = Localization

function Localization.GetLanguage()
    local database = _G.TRP3_RPSpellbookDB
    local settings = type(database) == "table" and database.settings
    local language = type(settings) == "table" and settings.language
    return (language == "enUS" or language == "deDE" or language == "frFR") and language or "client"
end

function Localization.SetLanguage(language)
    if language ~= "client" and language ~= "enUS" and language ~= "deDE" and language ~= "frFR" then return false end
    local database = _G.TRP3_RPSpellbookDB
    if type(database) ~= "table" then return false end
    if type(database.settings) ~= "table" then database.settings = {} end
    database.settings.language = language ~= "client" and language or nil
    return true
end

function Localization.Register(locale, translations)
    if type(locale) == "string" and type(translations) == "table" then
        Localization.translations[locale] = translations
    end
end

function Localization.GetLocale()
    local language = Localization.GetLanguage()
    if language ~= "client" then return language end
    local locale = type(GetLocale) == "function" and GetLocale() or nil
    if locale == "enGB" then
        return "enUS"
    end
    return type(locale) == "string" and locale or Localization.fallbackLocale
end

function Localization.Get(key, ...)
    local localeTable = Localization.translations[Localization.GetLocale()]
    local fallbackTable = Localization.translations[Localization.fallbackLocale] or {}
    local value = localeTable and localeTable[key] or fallbackTable[key] or key
    if select("#", ...) > 0 then
        local success, formatted = pcall(string.format, value, ...)
        return success and formatted or value
    end
    return value
end

addon.L = Localization.Get
addon.Text = setmetatable({}, {
    __index = function(_, key)
        return Localization.Get(key)
    end,
})
