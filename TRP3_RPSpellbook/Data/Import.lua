local _, addon = ...

addon.Import = {}

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_VALUES = {}
local ADLER_MODULUS = 65521
local LEGACY_COMMON_FIELD_COUNT = 13
local COPY_PERMISSION_FIELD_COUNT = 2
local SPELL_FIELD_COUNT = 14
local TAB_FIELD_COUNT = 8
local BOOK_FIELD_COUNT = 7

for index = 1, #BASE64_ALPHABET do
    BASE64_VALUES[BASE64_ALPHABET:sub(index, index)] = index - 1
end

local function trim(value)
    if type(value) ~= "string" then
        return nil
    end
    return value:match("^%s*(.-)%s*$")
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

local function decodeBase64(value)
    if type(value) ~= "string" or value == "" or #value % 4 ~= 0 or value:find("[^A-Za-z0-9+/=]") then
        return nil
    end

    local paddingStart = value:find("=", 1, true)
    if paddingStart and paddingStart < #value - 1 then
        return nil
    end

    local output = {}
    for index = 1, #value, 4 do
        local firstCharacter = value:sub(index, index)
        local secondCharacter = value:sub(index + 1, index + 1)
        local thirdCharacter = value:sub(index + 2, index + 2)
        local fourthCharacter = value:sub(index + 3, index + 3)
        local first = BASE64_VALUES[firstCharacter]
        local second = BASE64_VALUES[secondCharacter]
        local third = thirdCharacter == "=" and 0 or BASE64_VALUES[thirdCharacter]
        local fourth = fourthCharacter == "=" and 0 or BASE64_VALUES[fourthCharacter]
        if first == nil or second == nil or third == nil or fourth == nil then
            return nil
        end
        if thirdCharacter == "=" then
            if fourthCharacter ~= "=" or index + 3 ~= #value or second % 16 ~= 0 then
                return nil
            end
        elseif fourthCharacter == "=" then
            if index + 3 ~= #value or third % 4 ~= 0 then
                return nil
            end
        end

        local combined = (first * 262144) + (second * 4096) + (third * 64) + fourth
        output[#output + 1] = string.char(math.floor(combined / 65536) % 256)
        if thirdCharacter ~= "=" then
            output[#output + 1] = string.char(math.floor(combined / 256) % 256)
        end
        if fourthCharacter ~= "=" then
            output[#output + 1] = string.char(combined % 256)
        end
    end
    return table.concat(output)
end

local function isValidUTF8(value)
    local index = 1
    while index <= #value do
        local first = value:byte(index)
        if first <= 127 then
            index = index + 1
        elseif first >= 194 and first <= 223 then
            local second = value:byte(index + 1)
            if not second or second < 128 or second > 191 then return false end
            index = index + 2
        elseif first >= 224 and first <= 239 then
            local second = value:byte(index + 1)
            local third = value:byte(index + 2)
            if not second or not third or third < 128 or third > 191 then return false end
            if first == 224 then
                if second < 160 or second > 191 then return false end
            elseif first == 237 then
                if second < 128 or second > 159 then return false end
            elseif second < 128 or second > 191 then
                return false
            end
            index = index + 3
        elseif first >= 240 and first <= 244 then
            local second = value:byte(index + 1)
            local third = value:byte(index + 2)
            local fourth = value:byte(index + 3)
            if not second or not third or not fourth
                or third < 128 or third > 191
                or fourth < 128 or fourth > 191
            then
                return false
            end
            if first == 240 then
                if second < 144 or second > 191 then return false end
            elseif first == 244 then
                if second < 128 or second > 143 then return false end
            elseif second < 128 or second > 191 then
                return false
            end
            index = index + 4
        else
            return false
        end
    end
    return true
end

local function createFieldReader(payload)
    local position = 1
    local fieldCount = 0
    return function()
        fieldCount = fieldCount + 1
        if fieldCount > addon.Constants.MAX_IMPORT_FIELD_COUNT then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end

        local colon = payload:find(":", position, true)
        if not colon then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        local lengthText = payload:sub(position, colon - 1)
        if lengthText == ""
            or not lengthText:match("^%d+$")
            or (#lengthText > 1 and lengthText:sub(1, 1) == "0")
            or #lengthText > 6
        then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end

        local length = tonumber(lengthText)
        if not length or length > addon.Constants.MAX_IMPORT_FIELD_LENGTH then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        local first = colon + 1
        local last = first + length - 1
        if last > #payload then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        local value = length > 0 and payload:sub(first, last) or ""
        position = last + 1
        return value
    end, function()
        return position == #payload + 1
    end
end

local function readFields(readField, count)
    local fields = {}
    for index = 1, count do
        local value, errorMessage = readField()
        if value == nil then
            return nil, errorMessage
        end
        fields[index] = value
    end
    return fields
end

local function parseInteger(value, minimum, maximum)
    if type(value) ~= "string" or value == "" or not value:match("^%d+$") or #value > 16 then
        return nil
    end
    local number = tonumber(value)
    if not number or number < minimum or number > maximum or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function sanitizeText(value, multiline)
    if type(value) ~= "string" then
        return ""
    end
    local output = {}
    for index = 1, #value do
        local byte = value:byte(index)
        if byte == 10 and multiline then
            output[#output + 1] = "\n"
        elseif byte == 9 or ((byte == 10 or byte == 13) and not multiline) then
            output[#output + 1] = " "
        elseif byte >= 32 and byte ~= 127 and byte ~= 124 then
            output[#output + 1] = string.char(byte)
        end
    end
    return trim(table.concat(output)) or ""
end

local function isValidSourceID(value)
    return type(value) == "string"
        and value ~= ""
        and #value <= addon.Constants.MAX_EXPORT_SOURCE_ID_LENGTH
        and not value:find("[%c|]")
end

local function buildOwner(fields, ownerPresent)
    if not ownerPresent then
        for index = 8, 12 do
            if fields[index] ~= "" then
                return nil, addon.L("IMPORT_INVALID_PAYLOAD")
            end
        end
        return nil
    end

    local owner = {}
    local ownerFields = {
        profileKey = fields[8],
        characterName = fields[9],
        realmName = fields[10],
        rpName = fields[11],
        ownerGuid = fields[12],
    }
    for key, rawValue in pairs(ownerFields) do
        if #rawValue > addon.Constants.MAX_EXPORT_SOURCE_ID_LENGTH then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        local value = sanitizeText(rawValue, false)
        if value ~= "" then
            owner[key] = value
        end
    end
    return next(owner) and owner or nil
end

local function decodeIcon(iconType, iconValue)
    if iconType == "number" then
        local icon = parseInteger(iconValue, 1, addon.Constants.MAX_IMPORT_SAFE_INTEGER)
        return icon or nil
    end
    if iconType == "string" then
        local icon = sanitizeText(iconValue, false)
        return icon ~= "" and icon or false
    end
    return nil
end

local function decodeCommon(readField, expectedType, formatVersion)
    local fieldCount = LEGACY_COMMON_FIELD_COUNT
        + (formatVersion >= 2 and COPY_PERMISSION_FIELD_COUNT or 0)
    local fields, fieldsError = readFields(readField, fieldCount)
    if not fields then
        return nil, fieldsError
    end
    if fields[1] ~= addon.Constants.ADDON_NAME
        or fields[2] ~= tostring(formatVersion)
        or fields[3] ~= expectedType
    then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local maximum = addon.Constants.MAX_IMPORT_SAFE_INTEGER
    local exportedAt = parseInteger(fields[4], 0, maximum)
    local expiresAt = parseInteger(fields[6], 0, maximum)
    if not exportedAt or not expiresAt or (expiresAt ~= 0 and expiresAt < exportedAt) then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local readOnly
    if fields[5] == "1" then
        readOnly = true
    elseif fields[5] == "0" then
        readOnly = false
    else
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local ownerPresent
    if fields[7] == "1" then
        ownerPresent = true
    elseif fields[7] == "0" then
        ownerPresent = false
    else
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end
    local owner, ownerError = buildOwner(fields, ownerPresent)
    if ownerError then
        return nil, ownerError
    end
    if not isValidSourceID(fields[13]) then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local allowSpellCopy = false
    local allowTabCopy = false
    if formatVersion >= 2 then
        if (fields[14] ~= "0" and fields[14] ~= "1")
            or (fields[15] ~= "0" and fields[15] ~= "1")
        then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        allowSpellCopy = fields[14] == "1"
        allowTabCopy = expectedType ~= "spell" and fields[15] == "1"
    end

    local copyPermissions = {
        spells = allowSpellCopy,
        tabs = allowTabCopy,
    }

    return {
        owner = owner,
        sourceBookId = fields[13],
        formatVersion = formatVersion,
        exportMeta = {
            formatVersion = formatVersion,
            exportedAt = exportedAt,
            exportType = expectedType,
            readOnly = readOnly,
            expiresAt = expiresAt,
            sourceBookId = fields[13],
            copyPermissions = copyPermissions,
        },
    }
end

local function decodeSpellBlock(readField, formatVersion)
    local fields, fieldsError = readFields(readField, SPELL_FIELD_COUNT)
    if not fields then
        return nil, fieldsError
    end
    if not isValidSourceID(fields[1]) then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local icon = decodeIcon(fields[3], fields[4])
    if icon == nil then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end
    if icon == false then icon = nil end

    local maximum = addon.Constants.MAX_IMPORT_SAFE_INTEGER
    local createdAt = parseInteger(fields[11], 0, maximum)
    local updatedAt = parseInteger(fields[12], 0, maximum)
    local revision = parseInteger(fields[13], 1, addon.Constants.MAX_LINK_REVISION)
    local tagCount = parseInteger(fields[14], 0, addon.Validators.Limits.MAX_TAGS_PER_SPELL)
    if not createdAt or not updatedAt or updatedAt < createdAt or not revision or tagCount == nil then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local tags = {}
    for _ = 1, tagCount do
        local key, keyError = readField()
        local value, valueError = readField()
        if key == nil or value == nil then
            return nil, keyError or valueError or addon.L("IMPORT_INVALID_PAYLOAD")
        end
        key = sanitizeText(key, false)
        value = sanitizeText(value, false)
        if key == "" or value == "" or tags[key] ~= nil then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        tags[key] = value
    end

    local effects
    if formatVersion >= 3 then
        local effectFields, effectError = readFields(readField, 6)
        if not effectFields then
            return nil, effectError
        end
        local effectKind = effectFields[1]
        local validKind = effectKind == "0" or effectKind == "1"
            or (formatVersion >= 4 and effectKind == "2")
        if not validKind
            or (effectFields[2] ~= "0" and effectFields[2] ~= "1")
        then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        local debuffType
        if formatVersion >= 4 and effectKind == "2" then
            local debuffTypeError
            debuffType, debuffTypeError = readField()
            if debuffType == nil then
                return nil, debuffTypeError or addon.L("IMPORT_INVALID_PAYLOAD")
            end
            debuffType = sanitizeText(debuffType, false)
        end
        local durationRounds = effectFields[4] ~= ""
            and parseInteger(effectFields[4], formatVersion >= 5 and 0 or 1, 100) or nil
        local durationSeconds = effectFields[5] ~= ""
            and parseInteger(effectFields[5], 1, 31536000) or nil
        if (effectFields[4] ~= "" and not durationRounds)
            or (effectFields[5] ~= "" and not durationSeconds)
        then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        effects = {
            buff = effectKind == "1",
            debuff = effectKind == "2",
            debuffType = debuffType,
            healing = effectFields[2] == "1",
            duration = sanitizeText(effectFields[3], false),
            durationRounds = durationRounds,
            durationSeconds = durationSeconds,
            whisperTemplate = sanitizeText(effectFields[6], true),
        }
    end

    local candidate = {
        name = sanitizeText(fields[2], false),
        icon = icon,
        nameColor = sanitizeText(fields[5], false),
        resource = sanitizeText(fields[6], false),
        range = sanitizeText(fields[7], false),
        castTime = sanitizeText(fields[8], false),
        cooldown = sanitizeText(fields[9], false),
        description = sanitizeText(fields[10], true),
        tags = next(tags) and tags or nil,
        effects = effects,
    }
    local valid, spell, errors = addon.Validators.ValidateSpell(candidate)
    if not valid then
        return nil, addon.Validators.GetFirstError(errors)
    end
    spell.id = fields[1]
    spell.createdAt = createdAt
    spell.updatedAt = updatedAt
    spell.revision = revision
    return spell
end

local function decodeTabBlock(readField, seenSpellIDs, totalSpellCount, formatVersion)
    local fields, fieldsError = readFields(readField, TAB_FIELD_COUNT)
    if not fields then
        return nil, nil, fieldsError
    end
    if not isValidSourceID(fields[1]) then
        return nil, nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local icon = decodeIcon(fields[3], fields[4])
    if icon == nil then
        return nil, nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end
    if icon == false then icon = nil end

    local maximum = addon.Constants.MAX_IMPORT_SAFE_INTEGER
    local createdAt = parseInteger(fields[5], 0, maximum)
    local updatedAt = parseInteger(fields[6], 0, maximum)
    local revision = parseInteger(fields[7], 1, addon.Constants.MAX_LINK_REVISION)
    local spellCount = parseInteger(fields[8], 0, addon.Constants.MAX_EXPORT_SPELLS)
    if not createdAt or not updatedAt or updatedAt < createdAt or not revision or spellCount == nil then
        return nil, nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end
    if totalSpellCount.value + spellCount > addon.Constants.MAX_EXPORT_SPELLS then
        return nil, nil, addon.L("IMPORT_TOO_MANY_ABILITIES")
    end

    local valid, tab, errors = addon.Validators.ValidateTab({
        name = sanitizeText(fields[2], false),
        icon = icon,
        spellIds = {},
    })
    if not valid then
        return nil, nil, addon.Validators.GetFirstError(errors)
    end
    tab.id = fields[1]
    tab.createdAt = createdAt
    tab.updatedAt = updatedAt
    tab.revision = revision

    local spells = {}
    for _ = 1, spellCount do
        local spell, spellError = decodeSpellBlock(readField, formatVersion)
        if not spell then
            return nil, nil, spellError
        end
        if seenSpellIDs[spell.id] then
            return nil, nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        seenSpellIDs[spell.id] = true
        totalSpellCount.value = totalSpellCount.value + 1
        spells[spell.id] = spell
        tab.spellIds[#tab.spellIds + 1] = spell.id
    end
    return tab, spells
end

local function decodeSpellPayload(payload, formatVersion)
    local readField, isFinished = createFieldReader(payload)
    local common, commonError = decodeCommon(readField, "spell", formatVersion)
    if not common then
        return nil, commonError
    end

    local sourceSpellID, sourceError = readField()
    if sourceSpellID == nil then
        return nil, sourceError
    end
    local spell, spellError = decodeSpellBlock(readField, formatVersion)
    if not spell then
        return nil, spellError
    end
    if not isValidSourceID(sourceSpellID) or spell.id ~= sourceSpellID or not isFinished() then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    common.sourceSpellId = sourceSpellID
    common.spell = spell
    common.exportMeta.sourceSpellIds = { sourceSpellID }
    return common
end

local function decodeTabPayload(payload, formatVersion)
    local readField, isFinished = createFieldReader(payload)
    local common, commonError = decodeCommon(readField, "tab", formatVersion)
    if not common then
        return nil, commonError
    end

    local seenSpellIDs = {}
    local totalSpellCount = { value = 0 }
    local tab, spells, tabError = decodeTabBlock(readField, seenSpellIDs, totalSpellCount, formatVersion)
    if not tab then
        return nil, tabError
    end
    if not isFinished() then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local sourceSpellIDs = {}
    for _, spellID in ipairs(tab.spellIds) do sourceSpellIDs[#sourceSpellIDs + 1] = spellID end
    common.book = {
        id = common.sourceBookId,
        name = addon.L("DEFAULT_BOOK_NAME"),
        icon = tab.icon or addon.Constants.DEFAULT_BOOK_ICON,
        tabs = { [tab.id] = tab },
        tabOrder = { tab.id },
        spells = spells,
        createdAt = tab.createdAt,
        updatedAt = tab.updatedAt,
        revision = 1,
    }
    common.exportMeta.sourceTabIds = { tab.id }
    common.exportMeta.sourceSpellIds = sourceSpellIDs
    return common
end

local function decodeBookPayload(payload, formatVersion)
    local readField, isFinished = createFieldReader(payload)
    local common, commonError = decodeCommon(readField, "book", formatVersion)
    if not common then
        return nil, commonError
    end

    local fields, fieldsError = readFields(readField, BOOK_FIELD_COUNT)
    if not fields then
        return nil, fieldsError
    end
    local icon = decodeIcon(fields[2], fields[3])
    if icon == nil then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end
    if icon == false then icon = nil end
    local validBookIcon, cleanedBookIcon = addon.Validators.ValidateTab({ name = "Book", icon = icon })
    if not validBookIcon then
        return nil, addon.L("INVALID_ICON")
    end
    icon = cleanedBookIcon.icon

    local maximum = addon.Constants.MAX_IMPORT_SAFE_INTEGER
    local createdAt = parseInteger(fields[4], 0, maximum)
    local updatedAt = parseInteger(fields[5], 0, maximum)
    local revision = parseInteger(fields[6], 1, addon.Constants.MAX_LINK_REVISION)
    local tabCount = parseInteger(fields[7], 1, addon.Constants.MAX_EXPORT_TABS)
    local name = sanitizeText(fields[1], false)
    if name == ""
        or #name > addon.Validators.Limits.MAX_SHORT_FIELD_LENGTH
        or not createdAt
        or not updatedAt
        or updatedAt < createdAt
        or not revision
        or not tabCount
    then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local tabs = {}
    local tabOrder = {}
    local spells = {}
    local sourceSpellIDs = {}
    local seenTabIDs = {}
    local seenSpellIDs = {}
    local totalSpellCount = { value = 0 }
    for _ = 1, tabCount do
        local tab, tabSpells, tabError = decodeTabBlock(readField, seenSpellIDs, totalSpellCount, formatVersion)
        if not tab then
            return nil, tabError
        end
        if seenTabIDs[tab.id] then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        seenTabIDs[tab.id] = true
        tabs[tab.id] = tab
        tabOrder[#tabOrder + 1] = tab.id
        for _, spellID in ipairs(tab.spellIds) do
            spells[spellID] = tabSpells[spellID]
            sourceSpellIDs[#sourceSpellIDs + 1] = spellID
        end
    end
    if not isFinished() then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    common.book = {
        id = common.sourceBookId,
        name = name,
        icon = icon,
        tabs = tabs,
        tabOrder = tabOrder,
        spells = spells,
        createdAt = createdAt,
        updatedAt = updatedAt,
        revision = revision,
    }
    common.exportMeta.sourceTabIds = tabOrder
    common.exportMeta.sourceSpellIds = sourceSpellIDs
    return common
end

local function getCompactPayloadHeader(payload)
    local readField = createFieldReader(payload)
    local fields, fieldsError = readFields(readField, 3)
    if not fields then
        return nil, nil, fieldsError
    end
    if fields[1] ~= addon.Constants.ADDON_NAME then
        return nil, nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local formatVersion = fields[2]:match("^%d+$") and tonumber(fields[2]) or nil
    if not addon.Import.IsSupportedFormatVersion(formatVersion) then
        return nil, nil, addon.L("IMPORT_UNSUPPORTED_VERSION")
    end

    local typeCodeByExportType = {
        spell = addon.Constants.EXPORT_SPELL_TYPE_CODE,
        tab = addon.Constants.EXPORT_TAB_TYPE_CODE,
        book = addon.Constants.EXPORT_BOOK_TYPE_CODE,
    }
    local typeCode = typeCodeByExportType[fields[3]]
    if not typeCode then
        return nil, nil, addon.L("IMPORT_UNSUPPORTED_TYPE")
    end
    return formatVersion, typeCode
end

function addon.Import.IsSupportedFormatVersion(formatVersion)
    return type(formatVersion) == "number"
        and formatVersion == math.floor(formatVersion)
        and formatVersion >= addon.Constants.MIN_EXPORT_FORMAT_VERSION
        and formatVersion <= addon.Constants.EXPORT_FORMAT_VERSION
end

function addon.Import.Decode(exportString)
    if type(exportString) ~= "string" then
        return nil, addon.L("IMPORT_INVALID_STRING")
    end
    exportString = trim(exportString)
    if not exportString or exportString == "" then
        return nil, addon.L("IMPORT_EMPTY")
    end
    if #exportString > addon.Constants.MAX_EXPORT_STRING_LENGTH then
        return nil, addon.L("IMPORT_TOO_LARGE")
    end

    local payload
    local formatVersion
    local typeCode
    if addon.ExportCodec.IsCompact(exportString) then
        local compactError
        payload, compactError = addon.ExportCodec.Decode(exportString)
        if not payload then
            if compactError == "unavailable" then
                return nil, addon.L("IMPORT_COMPRESSION_UNAVAILABLE")
            end
            if compactError == "too_large" then
                return nil, addon.L("IMPORT_TOO_LARGE")
            end
            if compactError == "unsupported" then
                return nil, addon.L("IMPORT_UNSUPPORTED_VERSION")
            end
            return nil, addon.L("IMPORT_INVALID_COMPRESSION")
        end
        formatVersion, typeCode, compactError = getCompactPayloadHeader(payload)
        if not formatVersion then
            return nil, compactError
        end
    else
        local prefix, versionText, checksum, encoded
        prefix, versionText, typeCode, checksum, encoded = exportString:match(
            "^([^:]+):([^:]+):([^:]+):([^:]+):(.+)$"
        )
        if prefix ~= addon.Constants.EXPORT_FORMAT_PREFIX then
            return nil, addon.L("IMPORT_INVALID_STRING")
        end
        formatVersion = versionText:match("^%d+$") and tonumber(versionText) or nil
        if not addon.Import.IsSupportedFormatVersion(formatVersion) then
            return nil, addon.L("IMPORT_UNSUPPORTED_VERSION")
        end
        if typeCode ~= addon.Constants.EXPORT_SPELL_TYPE_CODE
            and typeCode ~= addon.Constants.EXPORT_TAB_TYPE_CODE
            and typeCode ~= addon.Constants.EXPORT_BOOK_TYPE_CODE
        then
            return nil, addon.L("IMPORT_UNSUPPORTED_TYPE")
        end
        if type(checksum) ~= "string" or #checksum ~= 8 or not checksum:match("^%x%x%x%x%x%x%x%x$") then
            return nil, addon.L("IMPORT_INVALID_STRING")
        end

        payload = decodeBase64(encoded)
        if not payload then
            return nil, addon.L("IMPORT_INVALID_BASE64")
        end
        if calculateChecksum(payload) ~= string.upper(checksum) then
            return nil, addon.L("IMPORT_CHECKSUM_MISMATCH")
        end
    end
    if #payload > addon.Constants.MAX_EXPORT_PAYLOAD_LENGTH then
        return nil, addon.L("IMPORT_TOO_LARGE")
    end
    if not isValidUTF8(payload) then
        return nil, addon.L("IMPORT_INVALID_UTF8")
    end

    if typeCode == addon.Constants.EXPORT_SPELL_TYPE_CODE then
        return decodeSpellPayload(payload, formatVersion)
    end
    if typeCode == addon.Constants.EXPORT_TAB_TYPE_CODE then
        return decodeTabPayload(payload, formatVersion)
    end
    return decodeBookPayload(payload, formatVersion)
end

function addon.Import.DecodeSpell(exportString)
    local decoded, errorMessage = addon.Import.Decode(exportString)
    if not decoded then
        return nil, errorMessage
    end
    if decoded.exportMeta.exportType ~= "spell" then
        return nil, addon.L("IMPORT_UNSUPPORTED_TYPE")
    end
    return decoded
end

function addon.Import.GetOwnerDisplayName(owner)
    if type(owner) ~= "table" then
        return addon.L("UNKNOWN")
    end
    if type(owner.rpName) == "string" and owner.rpName ~= "" then
        return owner.rpName
    end
    if type(owner.characterName) == "string" and owner.characterName ~= "" then
        if type(owner.realmName) == "string" and owner.realmName ~= "" then
            return owner.characterName .. " - " .. owner.realmName
        end
        return owner.characterName
    end
    return addon.L("UNKNOWN")
end
