local _, addon = ...

addon.GameMasterDelayedSubmission = {}

local pending
local listeners = {}
local eventFrame
local chatBursts = {}

local supportedEvents = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_EMOTE = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
}

local function canAccess(value)
    if type(_G.canaccessvalue) ~= "function" then
        return true
    end
    local success, accessible = pcall(_G.canaccessvalue, value)
    return success and accessible == true
end

local function notify(reason)
    for _, listener in ipairs(listeners) do
        addon.Runtime.SafeInvoke(listener, reason)
    end
end

local function isOwnMessage(author, guid)
    if canAccess(guid)
        and type(UnitGUID) == "function"
        and type(guid) == "string"
        and guid ~= ""
    then
        local success, playerGUID = pcall(UnitGUID, "player")
        if success and canAccess(playerGUID) and guid == playerGUID then
            return true
        end
    end
    if not canAccess(author) then return false end
    local localID = addon.GameMasterRoster.GetLocalPlayerID()
    return addon.Runtime.NormalizePlayerID(author)
        == addon.Runtime.NormalizePlayerID(localID)
end

local function cleanMessage(message, initialDepth)
    if not canAccess(message) or type(message) ~= "string" then
        return nil, 0
    end
     
    message = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
        :gsub("|", ""):gsub("[%c]", " ")
    message = addon.Runtime.Trim(message)
    if not message or message == "" then
        return nil, initialDepth or 0
    end
    local inspected = message:gsub("^%s*%[%d+/%d+%]%s*", "")
        :gsub("%s*%[%d+/%d+%]%s*$", "")
    local depth, hasIC = initialDepth or 0, false
     
     
    for index = 1, #inspected do
        local character = inspected:sub(index, index)
        if character == "(" then
            depth = depth + 1
        elseif character == ")" then
            depth = math.max(0, depth - 1)
        elseif depth == 0 and not character:match("[%s%p]") then
            hasIC = true
        end
    end
    return hasIC and message:sub(1, addon.Constants.GAMEMASTER_MAX_EMOTE_LENGTH)
        or nil, depth
end

local function isGeneratedAnnouncement(message)
    if not canAccess(message) or type(message) ~= "string" then
        return false
    end
    local plain = message:gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
    plain = addon.Runtime.Trim(plain) or ""
    return plain:match("^%[Spellbook%]") ~= nil
        or plain:match("^%[Spellbook%s+%d+/%d+%]") ~= nil
        or plain:match("^%(%s*%[Spellbook%]") ~= nil
        or plain:match("^%(%s*%[Spellbook%s+%d+/%d+%]") ~= nil
end

addon.GameMasterDelayedSubmission.ClassifyMessage = cleanMessage

function addon.GameMasterDelayedSubmission.RecognizeMessage(playerKey, message, now)
    if not playerKey or type(now) ~= "number" then return nil end
    if isGeneratedAnnouncement(message) then return nil end
    local burstSeconds = addon.Constants.GAMEMASTER_CHAT_BURST_SECONDS or 5
    local burst = chatBursts[playerKey]
    if not burst or now < burst.lastAt
        or now - burst.lastAt >= burstSeconds
    then
        burst = { depth = 0, counted = false }
        chatBursts[playerKey] = burst
    end
    local cleaned, depth = cleanMessage(message, burst.depth)
    burst.depth, burst.lastAt = depth, now
    for key, entry in pairs(chatBursts) do
        if now - entry.lastAt >= burstSeconds then chatBursts[key] = nil end
    end
    if not cleaned or burst.counted then return nil end
    burst.counted = true
    return cleaned
end

local function captureContext()
    local context = addon.GameMasterService.GetSubmissionContext()
    if type(context) ~= "table"
        or type(context.activationID) ~= "string"
        or type(context.roundID) ~= "string"
        or type(context.sessionID) ~= "string"
    then
        return nil
    end
    return {
        activationID = context.activationID,
        roundID = context.roundID,
        sessionID = context.sessionID,
        phase = context.phase,
        profile = addon.Database and addon.Database.GetActiveProfileKey and addon.Database.GetActiveProfileKey(),
        book = addon.Database and addon.Database.GetActiveSpellbook
            and addon.GameMasterService.GetActionSpellbook and addon.GameMasterService.GetActionSpellbook(),
    }
end

local function isCurrentContext(expected)
    local current = captureContext()
    return current ~= nil
        and addon.GameMasterService.CanSubmit()
        and current.activationID == expected.activationID
        and current.roundID == expected.roundID
        and current.sessionID == expected.sessionID
        and current.phase == expected.phase
        and current.profile == expected.profile
        and current.book == expected.book
end

local function onChatEvent(_, event, message, author, ...)
    if not supportedEvents[event]
        or (not pending and (not addon.GameMasterService.IsSessionActive
            or not addon.GameMasterService.IsSessionActive()))
    then
        return
    end
     
     
    if not canAccess(message) or not canAccess(author) then return end
    local guid = select(10, ...)
    local own = isOwnMessage(author, guid)
    local playerID
    if own then
        playerID = addon.GameMasterRoster.GetLocalPlayerID()
    elseif addon.GameMasterRoster.FindMember then
        local member = addon.GameMasterRoster.FindMember(author)
        playerID = member and member.playerID
    end
    if not playerID then return end
    local cleanedMessage = addon.GameMasterDelayedSubmission.RecognizeMessage(
        addon.Runtime.NormalizePlayerID(playerID), message,
        addon.Runtime.GetMonotonicTime()
    )
    if not cleanedMessage then return end
    if addon.GameMasterService.OnRecognizedEmote then
        addon.GameMasterService.OnRecognizedEmote(playerID)
    end
    if not own or not pending then return end
    local queued = pending
    pending = nil
    if not isCurrentContext(queued.context) then
        addon.Logger.Error(addon.L("GAMEMASTER_DELAYED_CONTEXT_CHANGED"))
        notify("failed")
        return
    end
    local entries = queued.actions or { queued }
    for index, entry in ipairs(entries) do
        local sent, errorMessage = addon.GameMasterService.Submit(
            entry.spell, entry.action, entry.targets,
            {
                aoe = entry.aoe, mode = entry.mode,
                emote = {
                    channel = event, text = cleanedMessage,
                    timestamp = addon.Runtime.GetTimestamp(),
                },
            }
        )
        if not sent then
             
            local remaining = {}
            for i = index, #entries do remaining[#remaining + 1] = entries[i] end
            queued.actions = remaining
            pending = queued
            addon.Logger.Error(errorMessage or addon.L("GAMEMASTER_SUBMISSION_REJECTED"))
            notify("failed")
            return
        end
    end
    notify("sent")
end

local function initialize()
    if eventFrame or type(CreateFrame) ~= "function" then
        return
    end
    eventFrame = CreateFrame("Frame")
    for event in pairs(supportedEvents) do
        eventFrame:RegisterEvent(event)
    end
    eventFrame:SetScript("OnEvent", onChatEvent)
end

addon.GameMasterDelayedSubmission.Initialize = initialize

function addon.GameMasterDelayedSubmission.Queue(
    spell,
    action,
    targets,
    aoe,
    mode
)
    if type(spell) ~= "table"
        or not addon.Constants.GAMEMASTER_ACTIONS[action]
        or not addon.GameMasterService.CanSubmit()
    then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end
    local context = captureContext()
    if not context then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end
    if mode ~= nil and mode ~= "replace" and mode ~= "append" then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end
    if pending and not isCurrentContext(pending.context) then pending = nil end
    local actions = {}
    if mode == "append" then
        local projected = addon.GameMasterDelayedSubmission.GetProjectedSubmission()
        local collection = addon.GameMasterActionCollection
        if collection and (action == "prepare" or collection.ContainsPreparation(projected)) then
            return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
        end
        if collection and collection.Count(projected) >= addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER then
            return false, addon.L("GAMEMASTER_ACTION_LIMIT_REACHED")
        end
        for _, entry in ipairs(pending and pending.actions or {}) do actions[#actions + 1] = entry end
    end
    initialize()
    local entry = {
        action = action,
        aoe = aoe == true,
        context = context,
        mode = mode == "append" and "append" or "replace",
        spell = spell,
        targets = targets,
    }
    actions[#actions + 1] = entry
    pending = {
        action = entry.action, aoe = entry.aoe, context = context, mode = entry.mode,
        spell = entry.spell, targets = entry.targets, actions = actions,
    }
    notify("queued")
    return true
end

function addon.GameMasterDelayedSubmission.Cancel()
    if not pending then
        return false
    end
    pending = nil
    notify("cancelled")
    return true
end

function addon.GameMasterDelayedSubmission.GetPending()
    return pending
end

function addon.GameMasterDelayedSubmission.GetProjectedSubmission()
    local context = addon.GameMasterService.GetSubmissionContext()
    local collection = addon.GameMasterActionCollection
    if not collection then return context and context.lastSubmission end
    local actions = {}
    for _, entry in ipairs(collection.Get(context and context.lastSubmission)) do
        actions[#actions + 1] = entry
    end
    if pending and isCurrentContext(pending.context) then
        for _, entry in ipairs(pending.actions) do
            if entry.mode ~= "append" then actions = {} end
            actions[#actions + 1] = entry
        end
    end
    return #actions > 0 and collection.Set({}, actions) or nil
end

addon.GameMasterService.RegisterListener(function(reason)
    if pending
        and (reason == "round" or reason == "phase" or reason == "remote" or reason == "stopped")
        and not isCurrentContext(pending.context)
    then
        addon.GameMasterDelayedSubmission.Cancel()
    end
end)

function addon.GameMasterDelayedSubmission.RegisterListener(callback)
    if type(callback) ~= "function" then
        return false
    end
    listeners[#listeners + 1] = callback
    return true
end
