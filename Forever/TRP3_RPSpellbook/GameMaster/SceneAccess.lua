local _, addon = ...

addon.GameMasterSceneAccess = {}

local defaultRights = {
    participants = true,
    rounds = true,
    visibility = true,
}

local function normalizeRights(raw)
    local source = type(raw) == "table" and raw or defaultRights
    return {
        participants = source.participants == true,
        rounds = source.rounds == true,
        visibility = source.visibility == true,
    }
end

local function normalizePlayerEntry(raw)
    local value = type(raw) == "table" and raw.playerID or raw
    local playerID, playerKey = addon.Runtime.NormalizeFullPlayerID(value)
    if not playerID or not playerKey then
        return nil
    end
    return playerID, playerKey
end

function addon.GameMasterSceneAccess.Normalize(raw, fallbackVisibility)
    raw = type(raw) == "table" and raw or {}
    local visibility = raw.defaultVisibility
    if not addon.Constants.GAMEMASTER_VISIBILITY_MODES[visibility] then
        visibility = addon.Constants.GAMEMASTER_VISIBILITY_MODES[
            fallbackVisibility
        ] and fallbackVisibility or "hidden"
    end
    local access = {
        assistants = {},
        defaultVisibility = visibility,
        visibilityOverrides = {},
    }

    local seenAssistants = {}
    for _, rawEntry in ipairs(
        type(raw.assistants) == "table" and raw.assistants or {}
    ) do
        local playerID, playerKey = normalizePlayerEntry(rawEntry)
        if playerKey and not seenAssistants[playerKey] then
            seenAssistants[playerKey] = true
            access.assistants[#access.assistants + 1] = {
                playerID = playerID,
                playerKey = playerKey,
                rights = normalizeRights(rawEntry.rights),
            }
        end
        if #access.assistants
            >= addon.Constants.GAMEMASTER_MAX_ASSISTANTS
        then
            break
        end
    end

    local seenOverrides = {}
    for _, rawEntry in ipairs(
        type(raw.visibilityOverrides) == "table"
            and raw.visibilityOverrides
            or {}
    ) do
        local playerID, playerKey = normalizePlayerEntry(rawEntry)
        local entryVisibility = type(rawEntry) == "table"
            and rawEntry.visibility
            or nil
        if playerKey
            and addon.Constants.GAMEMASTER_VISIBILITY_MODES[
                entryVisibility
            ]
            and not seenOverrides[playerKey]
        then
            seenOverrides[playerKey] = true
            access.visibilityOverrides[
                #access.visibilityOverrides + 1
            ] = {
                playerID = playerID,
                playerKey = playerKey,
                visibility = entryVisibility,
            }
        end
        if #access.visibilityOverrides
            >= addon.Constants.GAMEMASTER_MAX_VISIBILITY_OVERRIDES
        then
            break
        end
    end
    return access
end

function addon.GameMasterSceneAccess.Copy(raw, fallbackVisibility)
    return addon.GameMasterSceneAccess.Normalize(raw, fallbackVisibility)
end

function addon.GameMasterSceneAccess.GetAssistant(access, playerID)
    local _, fullKey = addon.Runtime.NormalizeFullPlayerID(playerID)
    local playerKey = fullKey or addon.Runtime.NormalizePlayerID(playerID)
    if not playerKey then
        return nil
    end
    for _, assistant in ipairs(
        type(access) == "table"
            and type(access.assistants) == "table"
            and access.assistants
            or {}
    ) do
        if assistant.playerKey == playerKey then
            return assistant
        end
    end
    return nil
end

function addon.GameMasterSceneAccess.GetVisibility(access, playerID)
    access = addon.GameMasterSceneAccess.Normalize(access, "hidden")
    local _, fullKey = addon.Runtime.NormalizeFullPlayerID(playerID)
    local playerKey = fullKey or addon.Runtime.NormalizePlayerID(playerID)
    if playerKey then
        for _, override in ipairs(access.visibilityOverrides) do
            if override.playerKey == playerKey then
                return override.visibility
            end
        end
    end
    return access.defaultVisibility
end

function addon.GameMasterSceneAccess.ToAssistantMap(access, ownerKey)
    local result = {}
    for _, assistant in ipairs(
        addon.GameMasterSceneAccess.Normalize(
            access,
            "hidden"
        ).assistants
    ) do
        if assistant.playerKey ~= ownerKey then
            result[assistant.playerKey] =
                normalizeRights(assistant.rights)
        end
    end
    return result
end
