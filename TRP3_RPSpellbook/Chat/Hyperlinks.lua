local _, addon = ...

addon.ChatHyperlinks = {
    initialized = false,
}

local CHAT_EVENTS = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
}
local TOTALRP3_TRANSPORT_PATTERN = "(%[TRP3:([^%]]+)%])"
local TOTALRP3_COLORED_HYPERLINK_PATTERN = "(|c%x%x%x%x%x%x%x%x|Haddon:totalrp3:[^:|]+:([^|]+)|h%[[^%]]*%]|h|r)"
local hookedFrames = setmetatable({}, { __mode = "k" })
local hoveredFrames = setmetatable({}, { __mode = "k" })
local hoverCache = {}
local hoverCacheOrder = {}
local hoverNegativeCache = {}
local hoverNegativeOrder = {}
local hoverPendingByKey = {}
local hoverPendingByRequestID = {}
local hoverCapableSenders = {}
local hoverPendingCount = 0
local hoverRequestSerial = 0

local function getTimeNow()
    if type(GetTime) == "function" then
        return GetTime()
    end
    return type(time) == "function" and time() or 0
end

local function schedule(delay, callback)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(delay, callback)
    else
        callback()
    end
end

local function normalizeSender(sender)
    return type(sender) == "string" and string.lower(sender) or ""
end

local function senderMatches(expected, actual)
    local normalizedExpected = normalizeSender(expected)
    local normalizedActual = normalizeSender(actual)
    if normalizedExpected == normalizedActual then
        return true
    end

    local expectedShort = normalizedExpected:match("^([^-]+)")
    local actualShort = normalizedActual:match("^([^-]+)")
    return expectedShort ~= nil
        and expectedShort == actualShort
        and (not normalizedExpected:find("-", 1, true) or not normalizedActual:find("-", 1, true))
end

local function makeHoverKey(sender, identifier)
    return normalizeSender(sender) .. "\031" .. identifier
end

local function rememberBounded(cache, order, key, value)
    if cache[key] == nil then
        order[#order + 1] = key
    end
    cache[key] = value

    local maximum = addon.Constants.MAX_CHAT_HOVER_CACHE_ENTRIES
    while #order > maximum do
        local expiredKey = table.remove(order, 1)
        cache[expiredKey] = nil
    end
end

local function showForHoveredKey(key, spell)
    for frame, state in pairs(hoveredFrames) do
        if state.key == key then
            addon.SpellTooltip.Show(frame, spell, false, "ANCHOR_CURSOR")
        end
    end
end

local function showUnavailableForHoveredKey(key, displayName)
    for frame, state in pairs(hoveredFrames) do
        if state.key == key then
            addon.SpellTooltip.ShowRemoteUnavailable(
                frame,
                state.displayName or displayName,
                "ANCHOR_CURSOR"
            )
        end
    end
end

local function clearPending(pending)
    if not pending then
        return
    end
    hoverPendingByKey[pending.key] = nil
    hoverPendingByRequestID[pending.requestId] = nil
    hoverPendingCount = math.max(0, hoverPendingCount - 1)
end

local function onHoverResponse(sender, response)
    if type(response) ~= "table"
        or response.formatVersion ~= addon.Constants.CHAT_LINK_FORMAT_VERSION
        or type(response.requestId) ~= "string"
        or response.requestId == ""
        or #response.requestId > addon.Constants.MAX_CHAT_HOVER_REQUEST_ID_LENGTH
        or response.requestId:find("[%c|]")
        or type(response.identifier) ~= "string"
        or response.identifier == ""
        or #response.identifier > addon.Constants.MAX_CHAT_TOKEN_LENGTH
        or response.identifier:find("[%c|]")
        or (response.status ~= "ok" and response.status ~= "not_spell" and response.status ~= "missing")
    then
        return
    end

    local pending = hoverPendingByRequestID[response.requestId]
    if not pending
        or pending.identifier ~= response.identifier
        or not senderMatches(pending.sender, sender)
    then
        return
    end
    clearPending(pending)

    if response.status == "ok" then
        local spell = addon.ChatLinks.ValidateTooltipSpell(response.spell)
        if not spell then
            return
        end
        rememberBounded(hoverCache, hoverCacheOrder, pending.key, spell)
        hoverCapableSenders[normalizeSender(sender)] = true
        hoverCapableSenders[normalizeSender(pending.sender)] = true
        showForHoveredKey(pending.key, spell)
        return
    end

    if response.status == "not_spell" then
        rememberBounded(hoverNegativeCache, hoverNegativeOrder, pending.key, {
            status = "not_spell",
            retryAt = math.huge,
        })
        return
    end

    if response.status == "missing" then
        rememberBounded(hoverNegativeCache, hoverNegativeOrder, pending.key, {
            status = "missing",
            retryAt = getTimeNow() + addon.Constants.CHAT_HOVER_RETRY_DELAY,
        })
        showUnavailableForHoveredKey(pending.key, pending.displayName)
    end
end

local function createHoverRequestID()
    hoverRequestSerial = hoverRequestSerial + 1
    return string.format("%d-%d", math.floor(getTimeNow() * 1000), hoverRequestSerial)
end

local function requestRemoteHover(sender, identifier, key, displayName)
    if hoverPendingByKey[key]
        or hoverPendingCount >= addon.Constants.MAX_CHAT_HOVER_PENDING_REQUESTS
    then
        return
    end

    local negative = hoverNegativeCache[key]
    if negative and negative.retryAt > getTimeNow() then
        if negative.status == "missing" then
            showUnavailableForHoveredKey(key, displayName)
        end
        return
    end

    local requestID = createHoverRequestID()
    local pending = {
        key = key,
        sender = sender,
        identifier = identifier,
        requestId = requestID,
        displayName = displayName,
    }
    hoverPendingByKey[key] = pending
    hoverPendingByRequestID[requestID] = pending
    hoverPendingCount = hoverPendingCount + 1

    if hoverCapableSenders[normalizeSender(sender)] then
        for frame, state in pairs(hoveredFrames) do
            if state.key == key then
                addon.SpellTooltip.ShowRemoteLoading(frame, displayName, "ANCHOR_CURSOR")
            end
        end
    end

    local success = addon.TRP3Bridge.RequestSpellHover(sender, identifier, requestID)
    if not success then
        clearPending(pending)
        return
    end

    schedule(addon.Constants.CHAT_HOVER_REQUEST_TIMEOUT, function()
        if hoverPendingByRequestID[requestID] ~= pending then
            return
        end
        clearPending(pending)
        rememberBounded(hoverNegativeCache, hoverNegativeOrder, key, {
            status = "timeout",
            retryAt = getTimeNow() + addon.Constants.CHAT_HOVER_RETRY_DELAY,
        })
    end)
end

local function beginNativeHover(frame, sender, identifier, displayName)
    local key = makeHoverKey(sender, identifier)
    local hoverState = {
        kind = "native",
        key = key,
        displayName = displayName,
    }
    hoveredFrames[frame] = hoverState

    local ownSpell = addon.TRP3Bridge.GetOwnSpellChatTooltip(sender, identifier)
    if ownSpell then
        rememberBounded(hoverCache, hoverCacheOrder, key, ownSpell)
        addon.SpellTooltip.Show(frame, ownSpell, false, "ANCHOR_CURSOR")
        return
    end

    local cachedSpell = hoverCache[key]
    if cachedSpell then
        addon.SpellTooltip.Show(frame, cachedSpell, false, "ANCHOR_CURSOR")
        return
    end

    local negative = hoverNegativeCache[key]
    if negative and negative.retryAt > getTimeNow() then
        if negative.status == "missing" then
            addon.SpellTooltip.ShowRemoteUnavailable(frame, displayName, "ANCHOR_CURSOR")
        end
        return
    end

    schedule(addon.Constants.CHAT_HOVER_DELAY, function()
        local state = hoveredFrames[frame]
        if state ~= hoverState or hoverCache[key] then
            return
        end
        requestRemoteHover(sender, identifier, key, displayName)
    end)
end

local function resolve(link)
    local reference = addon.ChatLinks.Parse(link)
    if not reference then
        return nil, nil
    end
    local spell = addon.Database.ResolveSpellReference(
        reference.owner,
        reference.spellId,
        reference.revision
    )
    return reference, spell
end

local function onHyperlinkEnter(frame, link, text)
    if addon.ChatLinks.IsSpellLink(link) then
        hoveredFrames[frame] = { kind = "legacy" }
        local _, spell = resolve(link)
        if spell then
            addon.SpellTooltip.Show(frame, spell, false, "ANCHOR_CURSOR")
        else
            addon.SpellTooltip.ShowUnknown(frame, text, "ANCHOR_CURSOR")
        end
        return
    end

    local sender, identifier = addon.TRP3Bridge.ParseTotalRP3ChatHyperlink(link)
    if sender then
        beginNativeHover(
            frame,
            sender,
            identifier,
            addon.ChatLinks.SanitizeDisplayName(text)
        )
    end
end

local function onHyperlinkLeave(frame)
    if not hoveredFrames[frame] then
        return
    end
    hoveredFrames[frame] = nil
    addon.SpellTooltip.Hide()
end

local function hookChatFrame(frame)
    local frameType = type(frame)
    if (frameType ~= "table" and frameType ~= "userdata")
        or hookedFrames[frame]
        or type(frame.HookScript) ~= "function"
    then
        return
    end

    local enterSuccess = pcall(frame.HookScript, frame, "OnHyperlinkEnter", onHyperlinkEnter)
    local leaveSuccess = pcall(frame.HookScript, frame, "OnHyperlinkLeave", onHyperlinkLeave)
    if enterSuccess or leaveSuccess then
        hookedFrames[frame] = true
    end
end

local function hookChatFrames()
    if type(_G.CHAT_FRAMES) == "table" then
        for _, frameName in ipairs(_G.CHAT_FRAMES) do
            hookChatFrame(_G[frameName])
        end
    end

    local count = tonumber(_G.NUM_CHAT_WINDOWS) or 0
    for index = 1, count do
        hookChatFrame(_G["ChatFrame" .. index])
    end
end

local function formatTransportTokens(_, _, message, author, ...)
    if type(message) ~= "string" then
        return false, message, author, ...
    end

    local formattedMessage = message:gsub(
        addon.ChatLinks.TRANSPORT_PATTERN,
        function(rawToken, encodedDisplayName, encodedOwner, encodedSpellID, revisionText)
            local displayName = addon.ChatLinks.DecodeTransportName(encodedDisplayName)
            local reference = addon.ChatLinks.ParseTransportComponents(
                encodedOwner,
                encodedSpellID,
                revisionText
            )
            if not displayName or not reference then
                return rawToken
            end

            local spell = addon.Database.ResolveSpellReference(
                reference.owner,
                reference.spellId,
                reference.revision
            )
            local formattedLink = addon.ChatLinks.Create(reference.owner, {
                id = reference.spellId,
                revision = reference.revision,
                name = spell and spell.name or displayName,
                nameColor = spell and spell.nameColor or nil,
            })
            return formattedLink or rawToken
        end
    )
    return false, formattedMessage, author, ...
end

local function formatOutgoingWhisperLinks(_, _, message, recipient, ...)
    if type(message) ~= "string" then
        return false, message, recipient, ...
    end

    local function replaceLink(rawLink, identifier)
        return addon.TRP3Bridge.FormatOwnSpellChatHyperlink(identifier) or rawLink
    end

    local formattedMessage = message:gsub(TOTALRP3_COLORED_HYPERLINK_PATTERN, replaceLink)
    formattedMessage = formattedMessage:gsub(TOTALRP3_TRANSPORT_PATTERN, replaceLink)
    return false, formattedMessage, recipient, ...
end

local function registerMessageFilters()
    local chatFrameUtil = _G.ChatFrameUtil
    if type(chatFrameUtil) ~= "table" or type(chatFrameUtil.AddMessageEventFilter) ~= "function" then
        return false
    end

    local registered = false
    for _, eventName in ipairs(CHAT_EVENTS) do
        local success = pcall(chatFrameUtil.AddMessageEventFilter, eventName, formatTransportTokens)
        registered = success or registered
    end

    local whisperSuccess = pcall(
        chatFrameUtil.AddMessageEventFilter,
        "CHAT_MSG_WHISPER_INFORM",
        formatOutgoingWhisperLinks
    )
    return whisperSuccess or registered
end

local function onSetItemRef(link, text, button)
    if addon.TimedEffectsView and addon.TimedEffectsView.HandleOfferLink
        and addon.TimedEffectsView.HandleOfferLink(link, button) then return end
    if not addon.ChatLinks.IsSpellLink(link) or (button and button ~= "LeftButton") then
        return
    end

    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
        local reference = addon.ChatLinks.Parse(link)
        if reference then
            addon.ChatInsert.ReplaceHyperlink(link, text, reference)
        end
        return
    end

    local reference, spell = resolve(link)
    if reference and spell then
        addon.SpellLinkWindow.OpenSpell(reference, spell)
    else
        addon.SpellLinkWindow.OpenUnknown(text)
    end
end

function addon.ChatHyperlinks.Initialize()
    if addon.ChatHyperlinks.initialized then
        return true
    end
    if type(hooksecurefunc) ~= "function" or type(_G.SetItemRef) ~= "function" then
        return false, addon.L("CHAT_LINK_API_UNAVAILABLE")
    end

    if not registerMessageFilters() then
        return false, addon.L("CHAT_LINK_API_UNAVAILABLE")
    end

    local hoverSuccess, hoverError = addon.TRP3Bridge.InitializeSpellHover(onHoverResponse)
    if not hoverSuccess then
        addon.Logger.Error(hoverError or addon.L("CHAT_HOVER_API_UNAVAILABLE"))
    end

    addon.ChatHyperlinks.initialized = true
    hooksecurefunc("SetItemRef", onSetItemRef)
    hookChatFrames()

    if type(_G.FCF_OpenNewWindow) == "function" then
        hooksecurefunc("FCF_OpenNewWindow", function()
            if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                C_Timer.After(0, hookChatFrames)
            else
                hookChatFrames()
            end
        end)
    end
    return true
end
