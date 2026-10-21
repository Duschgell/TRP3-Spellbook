local _, addon = ...

addon.Export = {}

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ADLER_MODULUS = 65521
local FILTER_BLACKLIST = "blacklist"
local FILTER_WHITELIST = "whitelist"

local function getTimestamp()
    if type(time) == "function" then
        return math.max(0, math.floor(tonumber(time()) or 0))
    end
    return 0
end

local function cleanSourceID(value)
    if type(value) ~= "string" or value == "" or #value > addon.Constants.MAX_EXPORT_SOURCE_ID_LENGTH then
        return nil
    end
    if value:find("[%c|]") then
        return nil
    end
    return value
end

local function cleanInteger(value, defaultValue)
    local number = tonumber(value)
    if not number
        or number ~= number
        or number == math.huge
        or number < 0
        or number > addon.Constants.MAX_IMPORT_SAFE_INTEGER
    then
        return defaultValue
    end
    return math.floor(number)
end

local function cleanRevision(value)
    local revision = cleanInteger(value, 1)
    return revision >= 1 and revision or 1
end

local function cleanMetadataTimes(createdValue, updatedValue)
    local createdAt = cleanInteger(createdValue, 0)
    local updatedAt = cleanInteger(updatedValue, createdAt)
    return createdAt, math.max(createdAt, updatedAt)
end

local function cleanOwnerField(value)
    if type(value) ~= "string" or value == "" then
        return ""
    end
    if #value > addon.Constants.MAX_EXPORT_SOURCE_ID_LENGTH then
        return ""
    end
    return value
end

local function isAllowedExpiration(seconds)
    for _, option in ipairs(addon.Constants.EXPORT_EXPIRATION_OPTIONS) do
        if option.seconds == seconds then
            return true
        end
    end
    return false
end

local function encodeField(value)
    value = tostring(value or "")
    return tostring(#value) .. ":" .. value
end

local function encodeFields(fields)
    local encoded = {}
    for index, value in ipairs(fields) do
        encoded[index] = encodeField(value)
    end
    return table.concat(encoded)
end

local function encodeBase64(value)
    local result = {}
    local outputIndex = 1
    for index = 1, #value, 3 do
        local first = value:byte(index)
        local second = value:byte(index + 1)
        local third = value:byte(index + 2)
        local combined = (first * 65536) + ((second or 0) * 256) + (third or 0)

        local a = math.floor(combined / 262144) % 64
        local b = math.floor(combined / 4096) % 64
        local c = math.floor(combined / 64) % 64
        local d = combined % 64
        result[outputIndex] = BASE64_ALPHABET:sub(a + 1, a + 1)
        result[outputIndex + 1] = BASE64_ALPHABET:sub(b + 1, b + 1)
        result[outputIndex + 2] = second and BASE64_ALPHABET:sub(c + 1, c + 1) or "="
        result[outputIndex + 3] = third and BASE64_ALPHABET:sub(d + 1, d + 1) or "="
        outputIndex = outputIndex + 4
    end
    return table.concat(result)
end

local function calculateChecksum(value)
    local a = 1
    local b = 0
    for index = 1, #value do
        a = (a + value:byte(index)) % ADLER_MODULUS
        b = (b + a) % ADLER_MODULUS
    end
    return string.format("%08X", (b * 65536) + a)
end

local function addOwnerFields(fields, includeOwner)
    local owner = includeOwner and addon.TRP3Bridge.GetExportOwnerInfo() or nil
    fields[#fields + 1] = owner and "1" or "0"
    fields[#fields + 1] = cleanOwnerField(owner and owner.profileKey)
    fields[#fields + 1] = cleanOwnerField(owner and owner.characterName)
    fields[#fields + 1] = cleanOwnerField(owner and owner.realmName)
    fields[#fields + 1] = cleanOwnerField(owner and owner.rpName)
    fields[#fields + 1] = cleanOwnerField(owner and owner.ownerGuid)
end

local function addIconFields(fields, icon)
    if type(icon) == "number" then
        fields[#fields + 1] = "number"
        fields[#fields + 1] = tostring(math.floor(icon))
    else
        fields[#fields + 1] = "string"
        fields[#fields + 1] = icon or ""
    end
end

local function addSpellFields(fields, spell)
    fields[#fields + 1] = spell.id
    fields[#fields + 1] = spell.name
    addIconFields(fields, spell.icon)
    fields[#fields + 1] = spell.nameColor or ""
    fields[#fields + 1] = spell.resource or ""
    fields[#fields + 1] = spell.range or ""
    fields[#fields + 1] = spell.castTime or ""
    fields[#fields + 1] = spell.cooldown or ""
    fields[#fields + 1] = spell.description or ""
    fields[#fields + 1] = tostring(cleanInteger(spell.createdAt, 0))
    fields[#fields + 1] = tostring(cleanInteger(spell.updatedAt, 0))
    fields[#fields + 1] = tostring(cleanInteger(spell.revision, 1))

    local tagKeys = {}
    for key in pairs(spell.tags or {}) do
        tagKeys[#tagKeys + 1] = key
    end
    table.sort(tagKeys)
    fields[#fields + 1] = tostring(#tagKeys)
    for _, key in ipairs(tagKeys) do
        fields[#fields + 1] = key
        fields[#fields + 1] = spell.tags[key]
    end

    if addon.Constants.EXPORT_FORMAT_VERSION >= 3 then
        local effects = spell.effects or {}
        local supportsDebuffs = addon.Constants.EXPORT_FORMAT_VERSION >= 4
        local effectKind = supportsDebuffs and effects.debuff == true and "2"
            or effects.buff == true and "1" or "0"
        fields[#fields + 1] = effectKind
        fields[#fields + 1] = effects.healing == true and "1" or "0"
        fields[#fields + 1] = effects.duration or ""
        fields[#fields + 1] = (effects.durationRounds ~= addon.Constants.EFFECT_DURATION_PERMANENT
            or addon.Constants.EXPORT_FORMAT_VERSION >= 5) and effects.durationRounds or ""
        fields[#fields + 1] = effects.durationSeconds or ""
        fields[#fields + 1] = effects.whisperTemplate or ""
        if supportsDebuffs and effectKind == "2" then
            fields[#fields + 1] = effects.debuffType or ""
        end
    end
end

local function prepareSpell(sourceSpell)
    if type(sourceSpell) ~= "table" then
        return nil, addon.L("INVALID_ABILITY")
    end
    local sourceSpellID = cleanSourceID(sourceSpell.id)
    if not sourceSpellID then
        return nil, addon.L("EXPORT_INVALID_SOURCE")
    end

    local valid, spell, errors = addon.Validators.ValidateSpell(sourceSpell)
    if not valid then
        return nil, addon.Validators.GetFirstError(errors)
    end
    spell.id = sourceSpellID
    spell.createdAt, spell.updatedAt = cleanMetadataTimes(sourceSpell.createdAt, sourceSpell.updatedAt)
    spell.revision = cleanRevision(sourceSpell.revision)
    if type(spell.icon) == "number" and spell.icon > addon.Constants.MAX_IMPORT_SAFE_INTEGER then
        return nil, addon.L("INVALID_ICON")
    end
    return spell
end

local function prepareTab(sourceTab)
    if type(sourceTab) ~= "table" then
        return nil, addon.L("INVALID_TAB")
    end
    local sourceTabID = cleanSourceID(sourceTab.id)
    if not sourceTabID then
        return nil, addon.L("EXPORT_INVALID_SOURCE")
    end

    local valid, tab, errors = addon.Validators.ValidateTab(sourceTab)
    if not valid then
        return nil, addon.Validators.GetFirstError(errors)
    end
    tab.id = sourceTabID
    tab.createdAt, tab.updatedAt = cleanMetadataTimes(sourceTab.createdAt, sourceTab.updatedAt)
    tab.revision = cleanRevision(sourceTab.revision)
    if type(tab.icon) == "number" and tab.icon > addon.Constants.MAX_IMPORT_SAFE_INTEGER then
        return nil, addon.L("INVALID_ICON")
    end
    return tab
end

local function prepareBookIdentity(spellbook)
    if type(spellbook) ~= "table" then
        return nil, addon.L("ACTIVE_BOOK_UNAVAILABLE")
    end
    local sourceBookID = cleanSourceID(spellbook.id)
    local name = type(spellbook.name) == "string" and spellbook.name:match("^%s*(.-)%s*$") or nil
    if not sourceBookID or not name or name == "" or #name > addon.Validators.Limits.MAX_SHORT_FIELD_LENGTH then
        return nil, addon.L("EXPORT_INVALID_SOURCE")
    end

    local validIcon, cleanedIcon = addon.Validators.ValidateTab({ name = "Book", icon = spellbook.icon })
    if not validIcon then
        return nil, addon.L("INVALID_ICON")
    end
    if type(cleanedIcon.icon) == "number" and cleanedIcon.icon > addon.Constants.MAX_IMPORT_SAFE_INTEGER then
        return nil, addon.L("INVALID_ICON")
    end
    local createdAt, updatedAt = cleanMetadataTimes(spellbook.createdAt, spellbook.updatedAt)
    return {
        id = sourceBookID,
        name = name,
        icon = cleanedIcon.icon,
        createdAt = createdAt,
        updatedAt = updatedAt,
        revision = cleanRevision(spellbook.revision),
    }
end

local function normalizeFilterMode(value)
    if value == nil or value == FILTER_BLACKLIST then
        return FILTER_BLACKLIST
    end
    if value == FILTER_WHITELIST then
        return FILTER_WHITELIST
    end
    return nil
end

local function isSelected(selection, itemID)
    return type(selection) == "table" and selection[itemID] == true
end

local function shouldInclude(itemID, mode, selection)
    local selected = isSelected(selection, itemID)
    return mode == FILTER_WHITELIST and selected or mode == FILTER_BLACKLIST and not selected
end

local function buildCommonFields(spellbook, exportType, options)
    local book, bookError = prepareBookIdentity(spellbook)
    if not book then
        return nil, nil, bookError
    end

    options = type(options) == "table" and options or {}
    local expiresIn = cleanInteger(options.expiresIn, 0)
    if not isAllowedExpiration(expiresIn) then
        return nil, nil, addon.L("EXPORT_INVALID_EXPIRATION")
    end

    local exportedAt = getTimestamp()
    local expiresAt = expiresIn > 0 and exportedAt + expiresIn or 0
    local fields = {
        addon.Constants.ADDON_NAME,
        tostring(addon.Constants.EXPORT_FORMAT_VERSION),
        exportType,
        tostring(exportedAt),
        options.readOnly == false and "0" or "1",
        tostring(expiresAt),
    }
    addOwnerFields(fields, options.includeOwner ~= false)
    fields[#fields + 1] = book.id
    if addon.Constants.EXPORT_FORMAT_VERSION >= 2 then
        fields[#fields + 1] = options.allowSpellCopy == true and "1" or "0"
        fields[#fields + 1] = exportType ~= "spell" and options.allowTabCopy == true and "1" or "0"
    end
    return fields, book
end

local function finishExport(fields, typeCode)
    local payload = encodeFields(fields)
    if #payload > addon.Constants.MAX_EXPORT_PAYLOAD_LENGTH then
        return nil, addon.L("EXPORT_TOO_LARGE")
    end

    local legacyHeaderTemplate = string.format(
        "%s:%d:%s:00000000:",
        addon.Constants.EXPORT_FORMAT_PREFIX,
        addon.Constants.EXPORT_FORMAT_VERSION,
        typeCode
    )
    local legacyLength = #legacyHeaderTemplate + (math.ceil(#payload / 3) * 4)
    local compactExport = addon.ExportCodec.Encode(payload)
    if compactExport
        and #compactExport < legacyLength
        and #compactExport <= addon.Constants.MAX_EXPORT_STRING_LENGTH
    then
        return compactExport
    end

    if legacyLength > addon.Constants.MAX_EXPORT_STRING_LENGTH then
        return nil, addon.L("EXPORT_TOO_LARGE")
    end
    local legacyHeader = string.format(
        "%s:%d:%s:%s:",
        addon.Constants.EXPORT_FORMAT_PREFIX,
        addon.Constants.EXPORT_FORMAT_VERSION,
        typeCode,
        calculateChecksum(payload)
    )
    return legacyHeader .. encodeBase64(payload)
end

local function collectTab(spellbook, sourceTab, spellFilterMode, spellSelection)
    local tab, tabError = prepareTab(sourceTab)
    if not tab then
        return nil, tabError
    end

    local spells = {}
    for _, spellID in ipairs(tab.spellIds) do
        if shouldInclude(spellID, spellFilterMode, spellSelection) then
            local spell, spellError = prepareSpell(type(spellbook.spells) == "table" and spellbook.spells[spellID] or nil)
            if not spell then
                return nil, spellError
            end
            spells[#spells + 1] = spell
            if #spells > addon.Constants.MAX_EXPORT_SPELLS then
                return nil, addon.L("EXPORT_TOO_LARGE")
            end
        end
    end
    return { tab = tab, spells = spells }
end

local function addTabFields(fields, collectedTab)
    local tab = collectedTab.tab
    fields[#fields + 1] = tab.id
    fields[#fields + 1] = tab.name
    addIconFields(fields, tab.icon)
    fields[#fields + 1] = tostring(tab.createdAt)
    fields[#fields + 1] = tostring(tab.updatedAt)
    fields[#fields + 1] = tostring(tab.revision)
    fields[#fields + 1] = tostring(#collectedTab.spells)
    for _, spell in ipairs(collectedTab.spells) do
        addSpellFields(fields, spell)
    end
end

function addon.Export.ExportSpell(spellbook, sourceSpell, options)
    if type(spellbook) ~= "table" or type(sourceSpell) ~= "table" then
        return nil, addon.L("INVALID_ABILITY")
    end

    local fields, _, commonError = buildCommonFields(spellbook, "spell", options)
    if not fields then
        return nil, commonError
    end
    local spell, spellError = prepareSpell(sourceSpell)
    if not spell then
        return nil, spellError
    end

    fields[#fields + 1] = spell.id
    addSpellFields(fields, spell)
    return finishExport(fields, addon.Constants.EXPORT_SPELL_TYPE_CODE)
end

function addon.Export.ExportTab(spellbook, sourceTab, options)
    if type(spellbook) ~= "table" or type(sourceTab) ~= "table" then
        return nil, addon.L("INVALID_TAB")
    end
    options = type(options) == "table" and options or {}
    local spellFilterMode = normalizeFilterMode(options.spellFilterMode)
    if not spellFilterMode then
        return nil, addon.L("EXPORT_INVALID_FILTER")
    end

    local fields, _, commonError = buildCommonFields(spellbook, "tab", options)
    if not fields then
        return nil, commonError
    end
    local collectedTab, tabError = collectTab(spellbook, sourceTab, spellFilterMode, options.spellSelection)
    if not collectedTab then
        return nil, tabError
    end

    addTabFields(fields, collectedTab)
    return finishExport(fields, addon.Constants.EXPORT_TAB_TYPE_CODE)
end

function addon.Export.ExportBook(spellbook, options)
    if type(spellbook) ~= "table" then
        return nil, addon.L("ACTIVE_BOOK_UNAVAILABLE")
    end
    options = type(options) == "table" and options or {}
    local tabFilterMode = normalizeFilterMode(options.tabFilterMode)
    local spellFilterMode = normalizeFilterMode(options.spellFilterMode)
    if not tabFilterMode or not spellFilterMode then
        return nil, addon.L("EXPORT_INVALID_FILTER")
    end

    local fields, book, commonError = buildCommonFields(spellbook, "book", options)
    if not fields then
        return nil, commonError
    end

    local tabs = {}
    local totalSpellCount = 0
    local seenTabs = {}
    local tabOrder = type(spellbook.tabOrder) == "table" and spellbook.tabOrder or {}
    for _, tabID in ipairs(tabOrder) do
        if seenTabs[tabID] then
            return nil, addon.L("EXPORT_INVALID_SOURCE")
        end
        seenTabs[tabID] = true
        if shouldInclude(tabID, tabFilterMode, options.tabSelection) then
            local sourceTab = type(spellbook.tabs) == "table" and spellbook.tabs[tabID] or nil
            local collectedTab, tabError = collectTab(spellbook, sourceTab, spellFilterMode, options.spellSelection)
            if not collectedTab then
                return nil, tabError
            end
            tabs[#tabs + 1] = collectedTab
            totalSpellCount = totalSpellCount + #collectedTab.spells
            if #tabs > addon.Constants.MAX_EXPORT_TABS
                or totalSpellCount > addon.Constants.MAX_EXPORT_SPELLS
            then
                return nil, addon.L("EXPORT_TOO_LARGE")
            end
        end
    end
    if #tabs == 0 then
        return nil, addon.L("EXPORT_EMPTY_TAB_SELECTION")
    end

    fields[#fields + 1] = book.name
    addIconFields(fields, book.icon)
    fields[#fields + 1] = tostring(book.createdAt)
    fields[#fields + 1] = tostring(book.updatedAt)
    fields[#fields + 1] = tostring(book.revision)
    fields[#fields + 1] = tostring(#tabs)
    for _, collectedTab in ipairs(tabs) do
        addTabFields(fields, collectedTab)
    end
    return finishExport(fields, addon.Constants.EXPORT_BOOK_TYPE_CODE)
end
