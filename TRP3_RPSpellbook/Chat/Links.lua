local _, addon = ...

addon.ChatLinks = {}
addon.ChatLinks.TRANSPORT_PATTERN = "(%["
    .. addon.Constants.CHAT_TOKEN_PREFIX
    .. ":([^:%]]*):([^:%]]+):([^:%]]+):(%d+)%])"

local function encodeComponent(value)
    return value:gsub("([^%w%._%-])", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
end

local function decodeComponent(value)
    local unescaped = value:gsub("%%%x%x", "")
    if unescaped:find("%", 1, true) then
        return nil
    end

    return value:gsub("%%(%x%x)", function(byte)
        return string.char(tonumber(byte, 16))
    end)
end

 
 
function addon.ChatLinks.EncodeTransportName(value, maximumBytes)
    local name = addon.ChatLinks.SanitizeDisplayName(value)
    local parts, length = {}, 0
    for character in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local encoded = encodeComponent(character)
        if maximumBytes and length + #encoded > maximumBytes then break end
        parts[#parts + 1], length = encoded, length + #encoded
    end
    return table.concat(parts)
end

function addon.ChatLinks.DecodeNativeDisplayName(identifier)
    if type(identifier) ~= "string" or #identifier > addon.Constants.MAX_CHAT_TOKEN_LENGTH then return nil end
    local stem = identifier:match("^(.-)%-rpsba%-%d+%-%d+%-%x+:%d+$")
        or identifier:match("^(.-)%-rpsb:%d+$")
    if not stem or stem == "" or not stem:match("^[%w%._%%%-]+$") then return nil end
    local decoded = decodeComponent(stem)
    if not decoded or decoded:find("[%c|]") then return nil end
     
    local position = 1
    while position <= #decoded do
        local first = decoded:byte(position)
        local size = first < 128 and 1 or (first >= 194 and first <= 223 and 2)
            or (first >= 224 and first <= 239 and 3) or (first >= 240 and first <= 244 and 4)
        if not size or position + size - 1 > #decoded then return nil end
        for index = position + 1, position + size - 1 do
            local byte = decoded:byte(index)
            if byte < 128 or byte > 191 then return nil end
        end
        local second = decoded:byte(position + 1)
        if (first == 224 and second < 160) or (first == 237 and second >= 160)
            or (first == 240 and second < 144) or (first == 244 and second >= 144) then return nil end
        position = position + size
    end
    return decoded
end

local function isValidReferenceValue(value, maximumLength)
    return type(value) == "string"
        and value ~= ""
        and #value <= maximumLength
        and not value:find("[%c|]")
end

local function normalizeColor(color)
    if type(color) == "string" then
        color = string.upper(color:gsub("#", ""))
        if color:match("^%x%x%x%x%x%x$") then
            return color
        end
    end
    return addon.Constants.DEFAULT_CHAT_LINK_COLOR
end

local function normalizeRevision(value)
    local revision = tonumber(value)
    if not revision
        or revision ~= revision
        or revision == math.huge
        or revision < 1
        or revision > addon.Constants.MAX_LINK_REVISION
        or revision ~= math.floor(revision)
    then
        return nil
    end
    return revision
end

function addon.ChatLinks.DecodeTransportName(value)
    if type(value) ~= "string" then
        return nil
    end
    local decoded = decodeComponent(value)
    if not decoded then
        return nil
    end
    return addon.ChatLinks.SanitizeDisplayName(decoded)
end

function addon.ChatLinks.SanitizeDisplayName(value)
    if type(value) ~= "string" then
        return addon.L("UNKNOWN_ABILITY")
    end

    local name = value
        :gsub("|H.-|h(.-)|h", "%1")
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub("|", "")
        :gsub("[%c]", " ")
        :match("^%s*(.-)%s*$")
    name = name:match("^%[(.*)%]$") or name
    return name ~= "" and name or addon.L("UNKNOWN_ABILITY")
end

local function sanitizeSnapshotText(value)
    if type(value) ~= "string" then
        return value
    end
    return value:gsub("|", "")
end

function addon.ChatLinks.ValidateTooltipSpell(spell)
    local valid, cleanedSpell, errors = addon.Validators.ValidateSpell(spell)
    if not valid then
        return nil, addon.Validators.GetFirstError(errors)
    end

    cleanedSpell.name = addon.ChatLinks.SanitizeDisplayName(cleanedSpell.name)
    cleanedSpell.resource = sanitizeSnapshotText(cleanedSpell.resource)
    cleanedSpell.range = sanitizeSnapshotText(cleanedSpell.range)
    cleanedSpell.castTime = sanitizeSnapshotText(cleanedSpell.castTime)
    cleanedSpell.cooldown = sanitizeSnapshotText(cleanedSpell.cooldown)
    cleanedSpell.description = sanitizeSnapshotText(cleanedSpell.description)
    if type(cleanedSpell.effects) == "table" then
        cleanedSpell.effects.duration = sanitizeSnapshotText(
            cleanedSpell.effects.duration
        )
        cleanedSpell.effects.whisperTemplate = sanitizeSnapshotText(
            cleanedSpell.effects.whisperTemplate
        )
    end
    if type(cleanedSpell.tags) == "table" then
        for key, value in pairs(cleanedSpell.tags) do
            cleanedSpell.tags[key] = sanitizeSnapshotText(value)
        end
    end
    return cleanedSpell
end

function addon.ChatLinks.CreateSnapshot(ownerKey, spell)
    if not isValidReferenceValue(ownerKey, addon.Constants.MAX_LINK_OWNER_LENGTH)
        or type(spell) ~= "table"
        or not isValidReferenceValue(spell.id, addon.Constants.MAX_LINK_SPELL_ID_LENGTH)
    then
        return nil, addon.L("INVALID_CHAT_LINK")
    end

    local revision = normalizeRevision(spell.revision)
    if not revision then
        return nil, addon.L("INVALID_CHAT_LINK")
    end

    local cleanedSpell, spellError = addon.ChatLinks.ValidateTooltipSpell(spell)
    if not cleanedSpell then
        return nil, spellError
    end

    return {
        formatVersion = addon.Constants.CHAT_LINK_FORMAT_VERSION,
        owner = ownerKey,
        spellId = spell.id,
        revision = math.floor(revision),
        spell = cleanedSpell,
    }
end

function addon.ChatLinks.IsSpellLink(link)
    if type(link) ~= "string" then
        return false
    end
    local prefix = addon.Constants.CHAT_LINK_TYPE .. ":"
    return link:sub(1, #prefix) == prefix
end

function addon.ChatLinks.Create(ownerKey, spell)
    if not isValidReferenceValue(ownerKey, addon.Constants.MAX_LINK_OWNER_LENGTH)
        or type(spell) ~= "table"
        or not isValidReferenceValue(spell.id, addon.Constants.MAX_LINK_SPELL_ID_LENGTH)
    then
        return nil, addon.L("INVALID_CHAT_LINK")
    end

    local revision = normalizeRevision(spell.revision)
    if not revision then
        return nil, addon.L("INVALID_CHAT_LINK")
    end
    revision = math.floor(revision)

    local name = addon.ChatLinks.SanitizeDisplayName(spell.name)
    local color = normalizeColor(spell.nameColor)
    local payload = string.format(
        "%s:%s:%d",
        encodeComponent(ownerKey),
        encodeComponent(spell.id),
        revision
    )
    local link = string.format(
        "|cff%s|H%s:%s|h[%s]|h|r",
        color,
        addon.Constants.CHAT_LINK_TYPE,
        payload,
        name
    )
    if #link > addon.Constants.MAX_CHAT_LINK_LENGTH then
        return nil, addon.L("INVALID_CHAT_LINK")
    end
    return link
end

function addon.ChatLinks.CreateTransportReference(reference, displayName)
    if type(reference) ~= "table" then
        return nil, addon.L("INVALID_CHAT_LINK")
    end

    local _, linkError = addon.ChatLinks.Create(reference.owner, {
        id = reference.spellId,
        revision = reference.revision,
        name = displayName,
    })
    if linkError then
        return nil, linkError
    end

    local transportName = addon.ChatLinks.SanitizeDisplayName(displayName)
    local token = string.format(
        "[%s:%s:%s:%s:%d]",
        addon.Constants.CHAT_TOKEN_PREFIX,
        encodeComponent(transportName),
        encodeComponent(reference.owner),
        encodeComponent(reference.spellId),
        math.floor(tonumber(reference.revision))
    )
    if #token > addon.Constants.MAX_CHAT_TOKEN_LENGTH then
        return nil, addon.L("CHAT_LINK_TOO_LONG")
    end
    return token
end

function addon.ChatLinks.CreateTransport(ownerKey, spell)
    if type(spell) ~= "table" then
        return nil, addon.L("INVALID_CHAT_LINK")
    end
    return addon.ChatLinks.CreateTransportReference({
        owner = ownerKey,
        spellId = spell.id,
        revision = spell.revision,
    }, spell.name)
end

function addon.ChatLinks.ParseTransportComponents(encodedOwner, encodedSpellID, revisionText)
    if type(encodedOwner) ~= "string"
        or type(encodedSpellID) ~= "string"
        or type(revisionText) ~= "string"
    then
        return nil, addon.L("INVALID_CHAT_LINK")
    end

    local link = string.format(
        "%s:%s:%s:%s",
        addon.Constants.CHAT_LINK_TYPE,
        encodedOwner,
        encodedSpellID,
        revisionText
    )
    return addon.ChatLinks.Parse(link)
end

function addon.ChatLinks.Parse(link)
    if not addon.ChatLinks.IsSpellLink(link) or #link > addon.Constants.MAX_CHAT_LINK_LENGTH then
        return nil, addon.L("INVALID_CHAT_LINK")
    end

    local prefix = addon.Constants.CHAT_LINK_TYPE .. ":"
    local payload = link:sub(#prefix + 1)
    local encodedOwner, encodedSpellID, revisionText = payload:match("^([^:]+):([^:]+):(%d+)$")
    if not encodedOwner or not encodedSpellID then
        return nil, addon.L("INVALID_CHAT_LINK")
    end

    local ownerKey = decodeComponent(encodedOwner)
    local spellID = decodeComponent(encodedSpellID)
    local revision = tonumber(revisionText)
    if not isValidReferenceValue(ownerKey, addon.Constants.MAX_LINK_OWNER_LENGTH)
        or not isValidReferenceValue(spellID, addon.Constants.MAX_LINK_SPELL_ID_LENGTH)
        or not revision
        or revision < 1
        or revision > addon.Constants.MAX_LINK_REVISION
    then
        return nil, addon.L("INVALID_CHAT_LINK")
    end

    return {
        owner = ownerKey,
        spellId = spellID,
        revision = math.floor(revision),
    }
end
