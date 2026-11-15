local _, addon = ...

addon.Runtime = {}

function addon.Runtime.GetMonotonicTime()
    if type(GetTime) == "function" then
        return GetTime()
    end
    if type(time) == "function" then
        return time()
    end
    return 0
end

function addon.Runtime.GetTimestamp()
    if type(time) ~= "function" then
        return 0
    end
    return math.max(0, math.floor(tonumber(time()) or 0))
end

function addon.Runtime.Trim(value)
    if type(value) ~= "string" then
        return nil
    end
    return value:match("^%s*(.-)%s*$")
end

function addon.Runtime.NormalizeSoundPreset(value)
    if value == "ready" or value == "whisper" or value == "soft" then return value end
    if type(value) ~= "string" or #value > 14 then return nil end
    local digits = value:match("^kit:(%d+)$")
    local id = digits and tonumber(digits)
    if not id or id < 1 or id > 2147483647 then return nil end
    return "kit:" .. string.format("%d", id)
end

function addon.Runtime.CountEntries(entries)
    if type(entries) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(entries) do
        count = count + 1
    end
    return count
end

function addon.Runtime.GetBoundedArrayLength(value, maximum)
    if type(value) ~= "table"
        or type(maximum) ~= "number"
        or maximum < 0
        or maximum ~= maximum
        or maximum == math.huge
        or maximum ~= math.floor(maximum)
    then
        return nil
    end

    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number"
            or key < 1
            or key > maximum
            or key ~= key
            or key == math.huge
            or key ~= math.floor(key)
        then
            return nil
        end
        count = count + 1
        if count > maximum then
            return nil
        end
    end
    for index = 1, count do
        if rawget(value, index) == nil then
            return nil
        end
    end
    return count
end

function addon.Runtime.IsSafeIdentifier(value, maximumLength)
    maximumLength = tonumber(maximumLength)
    return type(value) == "string"
        and type(maximumLength) == "number"
        and maximumLength >= 0
        and maximumLength == maximumLength
        and maximumLength < math.huge
        and maximumLength == math.floor(maximumLength)
        and value ~= ""
        and #value <= maximumLength
        and not value:find("[%c|]")
end

function addon.Runtime.NormalizePlayerID(playerID)
    if type(playerID) ~= "string" then
        return nil
    end

    local normalized = addon.Runtime.Trim(playerID)
    if not normalized or normalized == "" or normalized:find("[%c|:]") then
        return nil
    end
    return string.lower(normalized)
end

function addon.Runtime.NormalizeFullPlayerID(playerID)
    local text = addon.Runtime.Trim(playerID)
    if not text
        or text == ""
        or #text > addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
        or text:find("[%c|:]")
    then
        return nil
    end

    local separator = text:find("-", 1, true)
    if not separator then
        return nil
    end
    local name = addon.Runtime.Trim(text:sub(1, separator - 1))
    local realm = addon.Runtime.Trim(text:sub(separator + 1))
    if not name
        or name == ""
        or name:find("%s")
        or not realm
        or realm == ""
    then
        return nil
    end

    local normalized = name .. "-" .. realm
    local lookupID = name .. "-" .. realm:gsub("%s+", "")
    return normalized, addon.Runtime.NormalizePlayerID(lookupID)
end

function addon.Runtime.NormalizeChatPlayerID(playerID)
    local text = addon.Runtime.Trim(playerID)
    if not text or text == "" or text:find("[%c|:]") then
        return nil
    end
    local separator = text:find("-", 1, true)
    if not separator then
        return text:find("%s") and nil or text
    end
    local name = addon.Runtime.Trim(text:sub(1, separator - 1))
    local realm = addon.Runtime.Trim(text:sub(separator + 1))
    if not name or name == "" or name:find("%s")
        or not realm or realm == ""
    then
        return nil
    end
    realm = realm:gsub("%s+", "")
    return realm ~= "" and (name .. "-" .. realm) or nil
end

function addon.Runtime.SafeInvoke(callback, ...)
    if type(callback) ~= "function" then
        return false, "invalid callback"
    end
    return pcall(callback, ...)
end
