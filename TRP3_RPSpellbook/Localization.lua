local _, addon = ...

local Localization = {
    fallbackLocale = "enUS",
    translations = {},
}
addon.Localization = Localization

function Localization.Register(locale, translations)
    if type(locale) == "string" and type(translations) == "table" then
        Localization.translations[locale] = translations
    end
end

function Localization.GetLocale()
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
