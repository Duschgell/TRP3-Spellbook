local _, addon = ...

addon.ReleaseNotes = {}
local releases = {
    ["1.2"] = {
        enUS = "- CHANGELOG",
        deDE = "- CHANGELOG",
        frFR = "- CHANGELOG",
    },
}
local locales = { enUS = true, deDE = true, frFR = true }
local limits = addon.Constants

local function validText(text)
    if type(text) ~= "string" or #text == 0 or #text > limits.VERSION_CHECK_MAX_NOTE_BYTES
        or not text:find("%S") or text:find("[|%z\1-\9\11-\31\127]") then return false end
    local index, lineStart, lines = 1, 1, 1
    while index <= #text do
        local first = text:byte(index)
        local length, code, minimum = 1, first, 0
        if first >= 194 and first <= 223 then length, code, minimum = 2, first - 192, 128
        elseif first >= 224 and first <= 239 then length, code, minimum = 3, first - 224, 2048
        elseif first >= 240 and first <= 244 then length, code, minimum = 4, first - 240, 65536
        elseif first >= 128 then return false end
        for offset = 1, length - 1 do
            local byte = text:byte(index + offset)
            if not byte or byte < 128 or byte > 191 then return false end
            code = code * 64 + byte - 128
        end
        if code < minimum or code > 1114111 or code >= 55296 and code <= 57343
            or code >= 128 and code <= 159 or code == 173 or code == 847 or code == 1564
            or code == 6158 or code >= 8203 and code <= 8207
            or code >= 8232 and code <= 8238 or code >= 8288 and code <= 8303
            or code == 65279 or code >= 65529 and code <= 65531
            or code >= 64976 and code <= 65007 or code % 65536 >= 65534 then return false end
        if code == 10 then
            if index - lineStart > limits.VERSION_CHECK_MAX_NOTE_LINE_BYTES then return false end
            lines, lineStart = lines + 1, index + 1
            if lines > limits.VERSION_CHECK_MAX_NOTE_LINES then return false end
        end
        index = index + length
    end
    return #text - lineStart + 1 <= limits.VERSION_CHECK_MAX_NOTE_LINE_BYTES
end

function addon.ReleaseNotes.Copy(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
    local result, count, bytes = {}, 0, 0
    for locale, text in pairs(value) do
        if not locales[locale] or not validText(text) then return nil end
        bytes = bytes + #text
        if bytes > limits.VERSION_CHECK_MAX_NOTES_BYTES then return nil end
        result[locale], count = text, count + 1
    end
    return count > 0 and result or nil
end

function addon.ReleaseNotes.Key(value)
    local notes = addon.ReleaseNotes.Copy(value)
    if notes then return table.concat({ notes.enUS or "", notes.deDE or "", notes.frFR or "" }, "\0") end
end

function addon.ReleaseNotes.Same(left, right)
    for locale in pairs(locales) do
        if (left and left[locale]) ~= (right and right[locale]) then return false end
    end
    return true
end

function addon.ReleaseNotes.Get(version)
    return addon.ReleaseNotes.Copy(releases[version])
end

function addon.ReleaseNotes.GetVersions()
    local versions = {}
    for version in pairs(releases) do versions[#versions + 1] = version end
    return versions
end

function addon.ReleaseNotes.GetCurrent()
    return addon.ReleaseNotes.Get(addon.Constants.ADDON_VERSION)
end

function addon.ReleaseNotes.GetText(notes)
    notes = addon.ReleaseNotes.Copy(notes)
    return notes and (notes[addon.Localization.GetLocale()] or notes.enUS) or nil
end
