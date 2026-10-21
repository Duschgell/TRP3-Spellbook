local _, addon = ...

addon.ChatFallbacks = {
    initialized = false,
}

local constants = addon.Constants
local pendingLinks = {}
local pendingOrder = {}
local pendingSerial = 0
local trp3Peers = addon.Cache.NewBounded(constants.COMMUNICATION_MAX_PEERS or 256)
local recentManual = addon.Cache.NewBounded(128)
local recentAutomatic = addon.Cache.NewBounded(256)
local recentGameMaster = addon.Cache.NewBounded(128)
local recentEffect = addon.Cache.NewBounded(256)
local effectQueue = {}
local queuedEffects = {}
local effectQueueTimer
local effectQueueDueAt
local effectQueueGeneration = 0
local lastEffectFailureLog = -math.huge

local EFFECT_QUEUE_LIMIT = 128
local EFFECT_QUEUE_TTL = 180
local EFFECT_QUEUE_MAX_ATTEMPTS = 3
local EFFECT_QUEUE_RETRY_DELAY = 5

local GROUP_CHAT_EVENTS = {
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local rateWindows = {
    automatic = {
        count = 0,
        limit = constants.CHAT_FALLBACK_AUTO_MESSAGE_BUDGET or 32,
        startedAt = -math.huge,
    },
    effect = {
        count = 0,
        limit = constants.GAMEMASTER_EFFECT_WHISPER_BUDGET or 20,
        startedAt = -math.huge,
    },
    gameMaster = {
        count = 0,
        limit = constants.CHAT_FALLBACK_GAMEMASTER_MESSAGE_BUDGET or 12,
        startedAt = -math.huge,
    },
    manual = {
        count = 0,
        limit = constants.CHAT_FALLBACK_MANUAL_MESSAGE_BUDGET or 48,
        startedAt = -math.huge,
    },
}

local function hasText(value)
    return type(value) == "string" and value ~= ""
end

local function cleanChatText(value)
    if type(value) ~= "string" then
        return ""
    end
    local cleaned = value
        :gsub("|H.-|h(.-)|h", "%1")
        :gsub("|T.-|t", "")
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub("|", "")
        :gsub("[%c]", " ")
        :gsub("%s+", " ")
    return addon.Runtime.Trim(cleaned) or ""
end

local function cleanWhisperTarget(value)
    local target = addon.Runtime.Trim(value)
    if not target
        or target == ""
        or #target > constants.MAX_LINK_OWNER_LENGTH
        or target:find("[%c|:]")
    then
        return nil
    end
    return addon.Runtime.NormalizeChatPlayerID(target)
end

local function playerIDsMatch(first, second)
    local firstKey = addon.Runtime.NormalizePlayerID(first)
    local secondKey = addon.Runtime.NormalizePlayerID(second)
    if not firstKey or not secondKey then
        return false
    end
    if firstKey == secondKey then
        return true
    end
    local firstName = firstKey:match("^([^-]+)")
    local secondName = secondKey:match("^([^-]+)")
    return firstName ~= nil
        and firstName == secondName
        and (not firstKey:find("-", 1, true)
            or not secondKey:find("-", 1, true))
end

local function getLocalPlayerID()
    if addon.GameMasterRoster
        and type(addon.GameMasterRoster.GetLocalPlayerID) == "function"
    then
        return addon.GameMasterRoster.GetLocalPlayerID()
    end
    local api = _G.TRP3_API
    return type(api) == "table"
        and type(api.globals) == "table"
        and api.globals.player_id
        or nil
end

local function splitUTF8(text, maximumBytes)
    local chunks = {}
    local remaining = addon.Runtime.Trim(text) or ""
    while #remaining > maximumBytes do
        local boundary = maximumBytes
        while boundary > 0 do
            local nextByte = remaining:byte(boundary + 1)
            if not nextByte or nextByte < 128 or nextByte >= 192 then
                break
            end
            boundary = boundary - 1
        end
        if boundary < 1 then
            boundary = maximumBytes
        end

        local candidate = remaining:sub(1, boundary)
        local whitespace = candidate:match("^.*()%s")
        if whitespace and whitespace > math.floor(maximumBytes * 0.55) then
            boundary = whitespace - 1
        end
        local chunk = addon.Runtime.Trim(remaining:sub(1, boundary))
        if chunk and chunk ~= "" then
            chunks[#chunks + 1] = chunk
        end
        remaining = addon.Runtime.Trim(remaining:sub(boundary + 1)) or ""
    end
    if remaining ~= "" then
        chunks[#chunks + 1] = remaining
    end
    return chunks
end

local function appendField(parts, label, value)
    value = cleanChatText(value)
    if value ~= "" then
        parts[#parts + 1] = string.format("%s: %s", label, value)
    end
end

local function buildSpellSections(spell)
    local sections = {
        addon.L(
            "CHAT_FALLBACK_SPELL_NAME",
            cleanChatText(spell.name)
        ),
    }
    local kind = addon.SpellPresentation.GetKind(spell.tags)
    local kindLabel = kind == constants.SPELL_KIND_MAGIC
        and addon.L("ENTRY_KIND_MAGIC")
        or addon.L("ENTRY_KIND_ABILITY")
    local classification = addon.SpellPresentation
        .GetClassificationSummary(spell.tags, spell.effects)
    local classificationParts = {
        string.format("%s: %s", addon.L("CHAT_FALLBACK_KIND"), kindLabel),
    }
    appendField(
        classificationParts,
        addon.L("FIELD_PROPERTIES"),
        classification
    )
    sections[#sections + 1] = table.concat(classificationParts, "; ")

    local metadata = {}
    appendField(metadata, addon.L("FIELD_RESOURCE"), spell.resource)
    appendField(metadata, addon.L("FIELD_RANGE"), spell.range)
    appendField(metadata, addon.L("FIELD_CAST_TIME"), spell.castTime)
    if addon.SpellPresentation.ShouldShowCooldown(spell.cooldown) then
        appendField(metadata, addon.L("FIELD_COOLDOWN"), spell.cooldown)
    end
    appendField(metadata, addon.L("FIELD_DURATION"), addon.SpellPresentation.GetBuffDuration(spell))
    if #metadata > 0 then
        sections[#sections + 1] = table.concat(metadata, "; ")
    end

    local description = cleanChatText(spell.description)
    if description ~= "" then
        sections[#sections + 1] = string.format(
            "%s: %s",
            addon.L("FIELD_DESCRIPTION"),
            description
        )
    end
    return sections
end

function addon.ChatFallbacks.BuildSpellMessages(spell)
    local cleaned, errorMessage = addon.ChatLinks.ValidateTooltipSpell(spell)
    if not cleaned then
        return nil, errorMessage or addon.L("INVALID_ABILITY")
    end

    local content = {}
    local maximumContentBytes =
        constants.CHAT_FALLBACK_CONTENT_BYTES or 210
    for _, section in ipairs(buildSpellSections(cleaned)) do
        for _, chunk in ipairs(splitUTF8(section, maximumContentBytes)) do
            content[#content + 1] = chunk
        end
    end

    local maximumMessages =
        constants.CHAT_FALLBACK_MAX_SPELL_MESSAGES or 14
    if #content > maximumMessages then
        while #content >= maximumMessages do
            content[#content] = nil
        end
        content[#content + 1] = addon.L("CHAT_FALLBACK_TRUNCATED")
    end

    local messages = {}
    local total = #content
    for index, chunk in ipairs(content) do
        messages[index] = string.format(
            "[Spellbook %d/%d] %s",
            index,
            total,
            chunk
        )
    end
    return messages, cleaned
end

local function reserveBudget(kind, messageCount)
    local window = rateWindows[kind]
    if not window then
        return false
    end
    local now = addon.Runtime.GetMonotonicTime()
    local duration = constants.CHAT_FALLBACK_RATE_WINDOW or 60
    if now - window.startedAt >= duration then
        window.startedAt = now
        window.count = 0
    end
    if messageCount < 1
        or window.count + messageCount > window.limit
    then
        return false
    end
    window.count = window.count + messageCount
    return true
end

local function getBudgetDelay(kind, now)
    local window = rateWindows[kind]
    if not window then
        return 1
    end
    local duration = constants.CHAT_FALLBACK_RATE_WINDOW or 60
    if now - window.startedAt >= duration then
        return 0
    end
    return math.max(0.1, duration - (now - window.startedAt))
end

local function sendOne(message, channel, target, priority, queueName)
    local chomp = _G.AddOn_Chomp
    if type(chomp) == "table"
        and type(chomp.SendChatMessage) == "function"
    then
        local success, result = pcall(
            chomp.SendChatMessage,
            message,
            channel,
            nil,
            target,
            priority or "LOW",
            queueName
        )
        return success and result ~= false
    end

    local chatInfo = _G.C_ChatInfo
    local sender = type(chatInfo) == "table"
        and chatInfo.SendChatMessage
        or _G.SendChatMessage
    if type(sender) ~= "function" then
        return false
    end
    local success, result = pcall(
        sender,
        message,
        channel,
        nil,
        target
    )
    return success and result ~= false
end

local function dispatchMessages(messages, channel, target, queueName)
    for _, message in ipairs(messages) do
        if type(message) ~= "string"
            or message == ""
            or #message > 255
            or not sendOne(
                message,
                channel,
                target,
                "LOW",
                queueName
            )
        then
            return false
        end
    end
    return true
end

local drainEffectQueue

local function logEffectFailure()
    local now = addon.Runtime.GetMonotonicTime()
    local interval = constants.CHAT_FALLBACK_RATE_WINDOW or 60
    if now - lastEffectFailureLog < interval then
        return
    end
    lastEffectFailureLog = now
    addon.Logger.Error(addon.L("CHAT_FALLBACK_SEND_FAILED"))
end

local function scheduleEffectQueue(delay)
    if #effectQueue == 0 then
        return
    end
    local timers = _G.C_Timer
    if type(timers) ~= "table"
        or (type(timers.NewTimer) ~= "function"
            and type(timers.After) ~= "function")
    then
        logEffectFailure()
        return
    end
    delay = math.max(0.1, tonumber(delay) or EFFECT_QUEUE_RETRY_DELAY)
    local dueAt = addon.Runtime.GetMonotonicTime() + delay
    if effectQueueTimer and effectQueueDueAt
        and effectQueueDueAt <= dueAt
    then
        return
    end
    if effectQueueTimer and type(effectQueueTimer.Cancel) == "function" then
        effectQueueTimer:Cancel()
    end
    effectQueueGeneration = effectQueueGeneration + 1
    local generation = effectQueueGeneration
    local function callback()
        if generation ~= effectQueueGeneration then
            return
        end
        effectQueueTimer = nil
        effectQueueDueAt = nil
        if addon.Runtime.GetMonotonicTime() < dueAt then
            return
        end
        drainEffectQueue()
    end
    effectQueueDueAt = dueAt
    if type(timers.NewTimer) == "function" then
        effectQueueTimer = timers.NewTimer(delay, callback)
    elseif type(timers.After) == "function" then
        effectQueueTimer = true
        timers.After(delay, callback)
    else
        logEffectFailure()
    end
end

local function removeQueuedEffect(index)
    local item = table.remove(effectQueue, index)
    if item then
        queuedEffects[item.key] = nil
    end
    return item
end

drainEffectQueue = function()
    local now = addon.Runtime.GetMonotonicTime()
    local index = 1
    while index <= #effectQueue do
        local item = effectQueue[index]
        if now >= item.expiresAt
            or item.attempts >= EFFECT_QUEUE_MAX_ATTEMPTS
        then
            removeQueuedEffect(index)
            logEffectFailure()
        elseif not reserveBudget("effect", 1) then
            scheduleEffectQueue(getBudgetDelay("effect", now))
            return
        elseif dispatchMessages(
            { item.message },
            "WHISPER",
            item.target,
            "TRP3RPSB:effect"
        ) then
            recentEffect:Set(item.key, now)
            removeQueuedEffect(index)
        else
            item.attempts = item.attempts + 1
            if item.attempts >= EFFECT_QUEUE_MAX_ATTEMPTS then
                removeQueuedEffect(index)
                logEffectFailure()
            else
                index = index + 1
            end
        end
    end
    if #effectQueue > 0 then
        scheduleEffectQueue(EFFECT_QUEUE_RETRY_DELAY)
    end
end

local function queueEffectWhisper(key, target, message, attempts)
    if queuedEffects[key] then
        return true
    end
    if #effectQueue >= EFFECT_QUEUE_LIMIT then
        logEffectFailure()
        return false
    end
    local timers = _G.C_Timer
    if type(timers) ~= "table"
        or (type(timers.NewTimer) ~= "function"
            and type(timers.After) ~= "function")
    then
        logEffectFailure()
        return false
    end
    local now = addon.Runtime.GetMonotonicTime()
    local item = {
        attempts = math.max(0, tonumber(attempts) or 0),
        expiresAt = now + EFFECT_QUEUE_TTL,
        key = key,
        message = message,
        target = target,
    }
    effectQueue[#effectQueue + 1] = item
    queuedEffects[key] = item
    scheduleEffectQueue(getBudgetDelay("effect", now))
    return true
end

function addon.ChatFallbacks.SendEffectWhisper(target, message, dedupeKey, casterName)
    target = cleanWhisperTarget(target)
    message = cleanChatText(message)
    if not target or message == "" or #message > 255 then
        return false
    end
    local key = table.concat({
        addon.Runtime.NormalizePlayerID(target) or target,
        tostring(dedupeKey or message),
    }, "\031")
    local now = addon.Runtime.GetMonotonicTime()
    local previous = recentEffect:Get(key)
    if previous
        and now - previous
            < (constants.GAMEMASTER_EFFECT_WHISPER_COOLDOWN or 2)
    then
        return false
    end
    if queuedEffects[key] then
        return true
    end
     
     
    local localTarget = cleanWhisperTarget(getLocalPlayerID())
    if localTarget and addon.Runtime.NormalizePlayerID(target) == addon.Runtime.NormalizePlayerID(localTarget) then
        local source = cleanChatText(casterName)
        local success = addon.Runtime.SafeInvoke(addon.Logger.Info, source ~= "" and (source .. ": " .. message) or message)
        if not success then return false end
        recentEffect:Set(key, now)
        return true
    end
    if not reserveBudget("effect", 1) then
        return queueEffectWhisper(key, target, message, 0)
    end
    if not dispatchMessages(
            { message },
            "WHISPER",
            target,
            "TRP3RPSB:effect"
        ) then
        return queueEffectWhisper(key, target, message, 1)
    end
    recentEffect:Set(key, now)
    return true
end

local function createSpellRateKey(target, spell)
    local spellKey = hasText(spell.id) and spell.id
        or cleanChatText(spell.name)
    return string.format(
        "%s\031%s\031%s",
        addon.Runtime.NormalizePlayerID(target) or target,
        spellKey,
        tostring(spell.revision or 0)
    )
end

function addon.ChatFallbacks.SendSpellWhisper(spell, target)
    target = cleanWhisperTarget(target)
    if not target then
        return false, addon.L("CHAT_FALLBACK_INVALID_TARGET")
    end

    local messages, cleanedOrError =
        addon.ChatFallbacks.BuildSpellMessages(spell)
    if not messages then
        return false, cleanedOrError
    end
    local now = addon.Runtime.GetMonotonicTime()
    local rateKey = createSpellRateKey(target, spell)
    local lastSent = recentManual:Get(rateKey)
    if lastSent
        and now - lastSent
            < (constants.CHAT_FALLBACK_MANUAL_REPEAT_COOLDOWN or 10)
    then
        return false, addon.L("CHAT_FALLBACK_RATE_LIMITED")
    end
    if not reserveBudget("manual", #messages) then
        return false, addon.L("CHAT_FALLBACK_RATE_LIMITED")
    end

    local queueName = "TRP3RPSB:manual:"
        .. (addon.Runtime.NormalizePlayerID(target) or "target")
    if not dispatchMessages(
        messages,
        "WHISPER",
        target,
        queueName
    ) then
        return false, addon.L("CHAT_FALLBACK_SEND_FAILED")
    end
    recentManual:Set(rateKey, now)
    return true, #messages
end

function addon.ChatFallbacks.RememberTRP3Peer(
    playerID,
    version,
    extendedVersion
)
    local playerKey = addon.Runtime.NormalizePlayerID(playerID)
    if not playerKey then
        return false
    end
    trp3Peers:Set(playerKey, {
        extendedVersion = cleanChatText(tostring(extendedVersion or "")),
        lastSeen = addon.Runtime.GetMonotonicTime(),
        version = cleanChatText(tostring(version or "")),
    })
    return true
end

function addon.ChatFallbacks.CanReadSpellLinks(playerID)
    if playerIDsMatch(playerID, getLocalPlayerID()) then
        return true
    end
    if addon.Communication
        and type(addon.Communication.GetPeer) == "function"
        and addon.Communication.GetPeer(playerID)
    then
        return true
    end

    local playerKey = addon.Runtime.NormalizePlayerID(playerID)
    local peer = playerKey and trp3Peers:Get(playerKey) or nil
    return peer ~= nil
        and addon.Runtime.GetMonotonicTime() - peer.lastSeen
            <= (constants.CHAT_FALLBACK_TRP3_PEER_TTL or 1800)
end

function addon.ChatFallbacks.GetSpellFallbackRecipients()
    local recipients = {}
    local members = addon.GameMasterRoster
        and addon.GameMasterRoster.GetMembers()
        or {}
    for _, member in ipairs(members) do
        if member.online ~= false
            and not playerIDsMatch(member.playerID, getLocalPlayerID())
            and not addon.ChatFallbacks.CanReadSpellLinks(member.playerID)
        then
            recipients[#recipients + 1] = member
        end
    end
    table.sort(recipients, function(left, right)
        return string.lower(left.playerID)
            < string.lower(right.playerID)
    end)
    return recipients
end

function addon.ChatFallbacks.GetGroupTargets()
    local targets = {}
    local members = addon.GameMasterRoster
        and addon.GameMasterRoster.GetMembers()
        or {}
    for _, member in ipairs(members) do
        if member.online ~= false
            and not playerIDsMatch(member.playerID, getLocalPlayerID())
        then
            local label = hasText(member.rpName)
                and string.format(
                    "%s (%s)",
                    cleanChatText(member.rpName),
                    cleanChatText(member.playerID)
                )
                or cleanChatText(member.playerID)
            targets[#targets + 1] = {
                label = label,
                value = member.playerID,
            }
        end
    end
    table.sort(targets, function(left, right)
        return string.lower(left.label) < string.lower(right.label)
    end)
    return targets
end

local function getGroupChannel()
    return addon.GameMasterRoster
        and type(addon.GameMasterRoster.GetChatChannel) == "function"
        and addon.GameMasterRoster.GetChatChannel()
        or nil
end

local function markAutomaticRecipients(recipients, spell, timestamp)
    for _, member in ipairs(recipients) do
        recentAutomatic:Set(
            createSpellRateKey(member.playerID, spell),
            timestamp
        )
    end
end

local function getEligibleAutomaticRecipients(recipients, spell)
    local eligible = {}
    local now = addon.Runtime.GetMonotonicTime()
    local cooldown =
        constants.CHAT_FALLBACK_AUTO_REPEAT_COOLDOWN or 90
    for _, member in ipairs(recipients) do
        local key = createSpellRateKey(member.playerID, spell)
        local lastSent = recentAutomatic:Get(key)
        if not lastSent or now - lastSent >= cooldown then
            eligible[#eligible + 1] = member
        end
    end
    return eligible, now
end

local function dispatchAutomaticSpell(snapshot)
    if not addon.GameMasterSettings.ShouldAutoWhisperSpellFallback()
        or type(snapshot) ~= "table"
        or type(snapshot.spell) ~= "table"
    then
        return false
    end

    local channel = getGroupChannel()
    if not channel then
        return false
    end
    local recipients = addon.ChatFallbacks
        .GetSpellFallbackRecipients()
    local now
    local rateSpell = {
        id = snapshot.spellId,
        name = snapshot.spell.name,
        revision = snapshot.revision,
    }
    recipients, now = getEligibleAutomaticRecipients(
        recipients,
        rateSpell
    )
    if #recipients == 0 then
        return false
    end

    local messages, cleanedOrError =
        addon.ChatFallbacks.BuildSpellMessages(snapshot.spell)
    if not messages then
        addon.Logger.Error(cleanedOrError)
        return false
    end
    local maximumWhispers =
        constants.CHAT_FALLBACK_AUTO_MAX_WHISPER_RECIPIENTS or 4
    local maximumWhisperMessages =
        constants.CHAT_FALLBACK_AUTO_MAX_WHISPER_MESSAGES or 24
    local whisperMessageCount = #messages * #recipients

    if #recipients <= maximumWhispers
        and whisperMessageCount <= maximumWhisperMessages
    then
        if not reserveBudget("automatic", whisperMessageCount) then
            addon.Logger.Info(addon.L("CHAT_FALLBACK_RATE_LIMITED"))
            return false
        end
        for _, member in ipairs(recipients) do
            if not dispatchMessages(
                messages,
                "WHISPER",
                member.playerID,
                "TRP3RPSB:auto:"
                    .. (member.playerKey or member.playerID)
            ) then
                addon.Logger.Error(addon.L("CHAT_FALLBACK_SEND_FAILED"))
                return false
            end
        end
    else
        if not reserveBudget("automatic", #messages) then
            addon.Logger.Info(addon.L("CHAT_FALLBACK_RATE_LIMITED"))
            return false
        end
        if not dispatchMessages(
            messages,
            channel,
            nil,
            "TRP3RPSB:auto:group"
        ) then
            addon.Logger.Error(addon.L("CHAT_FALLBACK_SEND_FAILED"))
            return false
        end
    end

    markAutomaticRecipients(recipients, rateSpell, now)
    return true
end

local function queryGroupPeers()
    if not addon.Communication
        or type(addon.Communication.QueryPeer) ~= "function"
    then
        return
    end
    for _, member in ipairs(addon.GameMasterRoster.GetMembers()) do
        if not playerIDsMatch(member.playerID, getLocalPlayerID()) then
            addon.Communication.QueryPeer(member.playerID)
        end
    end
end

local function schedule(delay, callback)
    if type(_G.C_Timer) == "table"
        and type(_G.C_Timer.After) == "function"
    then
        _G.C_Timer.After(math.max(0, delay or 0), callback)
    else
        callback()
    end
end

local function prunePendingLinks()
    local now = addon.Runtime.GetMonotonicTime()
    local retained = {}
    for _, ordered in ipairs(pendingOrder) do
        local current = pendingLinks[ordered.link]
        if current
            and current.token == ordered.token
            and current.expiresAt >= now
        then
            retained[#retained + 1] = ordered
        elseif current and current.token == ordered.token then
            pendingLinks[ordered.link] = nil
        end
    end
    pendingOrder = retained
end

function addon.ChatFallbacks.TrackInsertedSpell(snapshot, link)
    if type(snapshot) ~= "table"
        or type(snapshot.spell) ~= "table"
        or type(link) ~= "string"
        or link == ""
    then
        return false
    end
    prunePendingLinks()
    pendingSerial = pendingSerial + 1
    local token = pendingSerial
    pendingLinks[link] = {
        expiresAt = addon.Runtime.GetMonotonicTime()
            + (constants.CHAT_FALLBACK_PENDING_LINK_TTL or 120),
        identifier = link:match("^%[TRP3:(.+)%]$"),
        snapshot = snapshot,
        token = token,
    }
    pendingOrder[#pendingOrder + 1] = {
        link = link,
        token = token,
    }
    while #pendingOrder
        > (constants.CHAT_FALLBACK_MAX_PENDING_LINKS or 24)
    do
        local removed = table.remove(pendingOrder, 1)
        local current = removed and pendingLinks[removed.link] or nil
        if current and current.token == removed.token then
            pendingLinks[removed.link] = nil
        end
    end
    return true
end

local function takePendingSnapshots(message)
    prunePendingLinks()
    if #pendingOrder == 0 then
        return {}
    end
    local identifiers = {}
    for sender, identifier in message:gmatch("|Haddon:totalrp3:([^:|]+):([^|]+)|h") do
        if playerIDsMatch(sender, getLocalPlayerID()) then
            identifiers[identifier] = true
        end
    end
    local snapshots, retained = {}, {}
    for _, ordered in ipairs(pendingOrder) do
        local current = pendingLinks[ordered.link]
        if current
            and current.token == ordered.token
            and (
                message:find(ordered.link, 1, true)
                or (current.identifier and identifiers[current.identifier])
            )
        then
            pendingLinks[ordered.link] = nil
            snapshots[#snapshots + 1] = current.snapshot
        else
            retained[#retained + 1] = ordered
        end
    end
    pendingOrder = retained
    return snapshots
end

local function canReadChatValue(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return false end
    end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        return ok and accessible == true
    end
    return true
end

local function observeOutgoingSpell(_, _, message, author, ...)
    if type(message) ~= "string"
        or not canReadChatValue(message) or not canReadChatValue(author)
        or not playerIDsMatch(author, getLocalPlayerID())
    then
        return false, message, author, ...
    end
    local snapshots = takePendingSnapshots(message)
    if #snapshots > 0
        and addon.GameMasterSettings.ShouldAutoWhisperSpellFallback()
    then
        queryGroupPeers()
        schedule(
            constants.GAMEMASTER_COMPATIBILITY_DELAY or 3,
            function()
                for _, snapshot in ipairs(snapshots) do
                    dispatchAutomaticSpell(snapshot)
                end
            end
        )
    end
    return false, message, author, ...
end

local function hasGameMasterFallbackAudience()
    local supports = addon.GameMasterProtocol
        and addon.GameMasterProtocol.Supports
    if type(supports) ~= "function" then
        return false
    end
    for _, member in ipairs(addon.GameMasterRoster.GetMembers()) do
        if member.online ~= false
            and not playerIDsMatch(member.playerID, getLocalPlayerID())
            and not supports(member.playerID)
        then
            return true
        end
    end
    return false
end

local function buildGameMasterMessage(eventName, context)
    context = type(context) == "table" and context or {}
    if eventName == "session_started" then
        return addon.L(
            "CHAT_FALLBACK_GM_SESSION_STARTED",
            cleanChatText(context.sessionName)
        )
    elseif eventName == "round_started" then
        return addon.L(
            context.phase == "enemies" and "CHAT_FALLBACK_GM_ENEMY_PHASE"
                or context.phase == "players" and "CHAT_FALLBACK_GM_PLAYER_PHASE"
                or "CHAT_FALLBACK_GM_ROUND_STARTED",
            math.max(1, math.floor(tonumber(context.roundNumber) or 1))
        )
    elseif eventName == "round_locked" then
        return addon.L("CHAT_FALLBACK_GM_ROUND_LOCKED")
    elseif eventName == "round_unlocked" then
        return addon.L("CHAT_FALLBACK_GM_ROUND_UNLOCKED")
    elseif eventName == "session_stopped" then
        return addon.L("CHAT_FALLBACK_GM_SESSION_STOPPED")
    end
    return nil
end

function addon.ChatFallbacks.AnnounceGameMaster(eventName, context)
    if not addon.GameMasterSettings.ShouldAnnounceGameMasterFallback()
        or not hasGameMasterFallbackAudience()
    then
        return false
    end

    local channel = getGroupChannel()
    local message = buildGameMasterMessage(eventName, context)
    if not channel or not hasText(message) then
        return false
    end
    message = cleanChatText(message)
    if message == "" or #message > 255 then
        return false
    end

    context = type(context) == "table" and context or {}
    local dedupeKey = table.concat({
        tostring(eventName),
        tostring(context.activationID or ""),
        tostring(context.sessionID or ""),
        tostring(context.roundID or ""),
        tostring(context.roundNumber or ""),
        tostring(context.phase or ""),
    }, "\031")
    local now = addon.Runtime.GetMonotonicTime()
    local lastSent = recentGameMaster:Get(dedupeKey)
    if lastSent and now - lastSent < 5 then
        return false
    end
    if not reserveBudget("gameMaster", 1) then
        return false
    end
    if not dispatchMessages(
        { message },
        channel,
        nil,
        "TRP3RPSB:gm"
    ) then
        return false
    end
    recentGameMaster:Set(dedupeKey, now)
    return true
end

function addon.ChatFallbacks.ScheduleGameMasterAnnouncement(
    eventName,
    context,
    delay
)
    local copied = {}
    if type(context) == "table" then
        for key, value in pairs(context) do
            copied[key] = value
        end
    end
    queryGroupPeers()
    schedule(delay or 0, function()
        if (eventName == "session_started" or eventName == "round_started")
            and addon.GameMasterService
            and type(addon.GameMasterService.GetActiveSession)
                == "function"
        then
            local session = addon.GameMasterService.GetActiveSession()
            if not session or session.id ~= copied.sessionID then
                return
            end
            if eventName == "round_started" then
                local current = addon.GameMasterService.GetSubmissionContext()
                if not current or current.activationID ~= copied.activationID
                    or current.roundID ~= copied.roundID
                    or (copied.phase and addon.GameMasterService.GetPhase() ~= copied.phase) then return end
            end
        end
        addon.ChatFallbacks.AnnounceGameMaster(eventName, copied)
    end)
    return true
end

local function registerMessageFilters()
    local chatFrameUtil = _G.ChatFrameUtil
    if type(chatFrameUtil) ~= "table"
        or type(chatFrameUtil.AddMessageEventFilter) ~= "function"
    then
        return false
    end
    local registered = false
    for _, eventName in ipairs(GROUP_CHAT_EVENTS) do
        local success = pcall(
            chatFrameUtil.AddMessageEventFilter,
            eventName,
            observeOutgoingSpell
        )
        registered = success or registered
    end
    return registered
end

function addon.ChatFallbacks.Initialize()
    if addon.ChatFallbacks.initialized then
        return true
    end
    if addon.CommunicationTransport
        and type(
            addon.CommunicationTransport.RegisterTRP3HelloHandler
        ) == "function"
    then
        addon.CommunicationTransport.RegisterTRP3HelloHandler(
            function(sender, version, _, extendedVersion)
                addon.ChatFallbacks.RememberTRP3Peer(
                    sender,
                    version,
                    extendedVersion
                )
            end
        )
    end
    addon.ChatFallbacks.automaticMonitoringAvailable =
        registerMessageFilters()
    addon.ChatFallbacks.initialized = true
    return true
end
