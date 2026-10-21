local _, addon = ...

addon.GameMasterPlayerState = {}

local function getProfileRoot()
    local service = addon.GameMasterService
    local tutorial = service and service.GetTutorialState and service.GetTutorialState()
    if tutorial then
        tutorial.playerState = tutorial.playerState or { targetHistory = {}, automatePreparation = true }
        return tutorial.playerState
    end
    local profile = addon.Database.GetActiveProfileData()
    if type(profile) ~= "table" then
        return nil
    end
    if type(profile.gameMasterPlayer) ~= "table" then
        profile.gameMasterPlayer = {}
    end
    local root = profile.gameMasterPlayer
    if type(root.targetHistory) ~= "table" then
        root.targetHistory = {}
    end
    return root
end

local function getGlobalRoot()
    local database = addon.Database.GetDB()
    if type(database) ~= "table" then
        return nil
    end
    if type(database.settings) ~= "table" then
        database.settings = {}
    end
    if type(database.settings.gameMasterPlayer) ~= "table" then
        database.settings.gameMasterPlayer = {}
    end
    return database.settings.gameMasterPlayer
end

local function cleanSessionID(sessionID)
    if addon.Runtime.IsSafeIdentifier(
        sessionID,
        addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
    ) then
        return sessionID
    end
    return nil
end

local function cleanTarget(value)
    local text = addon.Runtime.Trim(value)
    if not text
        or text == ""
        or #text > addon.Constants.GAMEMASTER_MAX_TARGET_LENGTH
        or text:find("[%c|]")
    then
        return nil
    end
    return text
end

function addon.GameMasterPlayerState.ShouldSendAfterEmote()
    local root = getProfileRoot()
    return root and root.sendAfterEmote == true or false
end

function addon.GameMasterPlayerState.GetTurnSoundPreset()
    local root = getGlobalRoot()
    local preset = root and root.turnSoundPreset
    return addon.Runtime.NormalizeSoundPreset(preset) or "ready"
end

function addon.GameMasterPlayerState.SetTurnSoundPreset(preset)
    preset = addon.Runtime.NormalizeSoundPreset(preset)
    if not preset then return false end
    local root = getGlobalRoot()
    if not root then return false end
    root.turnSoundPreset = preset
    return true
end

function addon.GameMasterPlayerState.ShouldPlayIncomingActionSound()
    local root = getGlobalRoot()
    return root and root.incomingActionSoundEnabled == true or false
end

function addon.GameMasterPlayerState.SetIncomingActionSoundEnabled(enabled)
    local root = getGlobalRoot()
    if not root then return false end
    root.incomingActionSoundEnabled = enabled == true
    return true
end

function addon.GameMasterPlayerState.GetIncomingActionSoundPreset()
    local root = getGlobalRoot()
    local preset = root and root.incomingActionSoundPreset
    return addon.Runtime.NormalizeSoundPreset(preset) or "ready"
end

function addon.GameMasterPlayerState.SetIncomingActionSoundPreset(preset)
    preset = addon.Runtime.NormalizeSoundPreset(preset)
    if not preset then return false end
    local root = getGlobalRoot()
    if not root then return false end
    root.incomingActionSoundPreset = preset
    return true
end

function addon.GameMasterPlayerState.SetSendAfterEmote(enabled)
    local root = getProfileRoot()
    if not root then
        return false
    end
    root.sendAfterEmote = enabled == true
    return true
end

function addon.GameMasterPlayerState.ShouldAutoCompleteTurn()
    if addon.GameMasterSettings
        and type(addon.GameMasterSettings.ShouldAutoCompleteTurn) == "function"
    then
        return addon.GameMasterSettings.ShouldAutoCompleteTurn()
    end
    local root = getProfileRoot()
    return not root or root.autoCompleteTurn ~= false
end

function addon.GameMasterPlayerState.SetAutoCompleteTurn(enabled)
    local root = getProfileRoot()
    if not root then return false end
    root.autoCompleteTurn = enabled == true
    return true
end

function addon.GameMasterPlayerState.ShouldAutomatePreparation()
    local root = getProfileRoot()
    return root and root.automatePreparation == true or false
end

function addon.GameMasterPlayerState.SetAutomatePreparation(enabled)
    local root = getProfileRoot()
    if not root then
        return false
    end
    root.automatePreparation = enabled == true
    return true
end

function addon.GameMasterPlayerState.RememberTextTargets(
    sessionID,
    targets,
    limit
)
    local root = getProfileRoot()
    sessionID = cleanSessionID(sessionID)
    if not root or not sessionID or type(targets) ~= "table" then
        return false
    end
    local history = type(root.targetHistory[sessionID]) == "table"
        and root.targetHistory[sessionID]
        or {}
    local merged = {}
    local seen = {}
    local function add(value)
        local text = cleanTarget(value)
        local key = text and text:lower() or nil
        if text and not seen[key] then
            seen[key] = true
            merged[#merged + 1] = text
        end
    end
    for _, value in ipairs(targets) do
        add(value)
    end
    for _, value in ipairs(history) do
        add(value)
    end
    limit = math.max(1, math.min(
        addon.Constants.GAMEMASTER_MAX_HISTORY,
        math.floor(tonumber(limit)
            or addon.Constants.GAMEMASTER_DEFAULT_HISTORY)
    ))
    while #merged > limit do
        table.remove(merged)
    end
    root.targetHistory[sessionID] = merged
    return true
end

function addon.GameMasterPlayerState.GetTextTargets(sessionID)
    local root = getProfileRoot()
    local history = root
        and cleanSessionID(sessionID)
        and root.targetHistory[sessionID]
        or nil
    local result = {}
    for _, value in ipairs(type(history) == "table" and history or {}) do
        local text = cleanTarget(value)
        if text then
            result[#result + 1] = text
        end
    end
    return result
end

function addon.GameMasterPlayerState.GetPreparation()
    local root = getProfileRoot()
    return root and type(root.preparation) == "table"
        and root.preparation
        or nil
end

function addon.GameMasterPlayerState.SetPreparation(preparation)
    local root = getProfileRoot()
    if not root then
        return false
    end
    root.preparation = type(preparation) == "table" and preparation or nil
    return true
end

function addon.GameMasterPlayerState.ClearPreparation()
    return addon.GameMasterPlayerState.SetPreparation(nil)
end

function addon.GameMasterPlayerState.GetActionWindowLayout()
    local root = getGlobalRoot()
    return root and type(root.actionWindow) == "table"
        and root.actionWindow
        or {}
end

function addon.GameMasterPlayerState.SaveActionWindowLayout(frame)
    local root = getGlobalRoot()
    if not root or not frame or type(frame.GetPoint) ~= "function" then
        return false
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if type(point) ~= "string" or type(relativePoint) ~= "string" then
        return false
    end
    root.actionWindow = {
        point = point,
        relativePoint = relativePoint,
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
    }
    return true
end
