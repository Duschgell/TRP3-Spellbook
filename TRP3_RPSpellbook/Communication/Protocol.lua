local _, addon = ...

addon.Communication = {
    enabled = false,
    initialized = false,
}

local constants = addon.Constants
local handlers = {}
local peerListeners = {}
local peers = addon.Cache.NewBounded(constants.COMMUNICATION_MAX_PEERS)
local peerQueries = addon.Cache.NewBounded(constants.COMMUNICATION_MAX_PEERS)
local presenceQueries = addon.Cache.NewBounded(constants.COMMUNICATION_MAX_PEERS)
local senderRates = addon.Cache.NewBounded(constants.COMMUNICATION_MAX_PEERS)
local seenMessages = addon.Cache.NewBounded(constants.COMMUNICATION_MAX_SEEN_MESSAGES)
local initializationError
local messageSerial = 0
local lastAnnouncementAt = -math.huge

local RESERVED_MESSAGE_TYPES = {
    hello = true,
    hello_ack = true,
}

local unpackArguments = unpack or table.unpack

local function isValidMessageType(messageType)
    return type(messageType) == "string"
        and messageType ~= ""
        and #messageType <= constants.COMMUNICATION_MESSAGE_TYPE_LENGTH
        and messageType:match("^[%l%d_.-]+$") ~= nil
end

local function validatePayloadValue(value, depth, budget, seen)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" then
        return true
    end
    if valueType == "number" then
        return value == value and value ~= math.huge and value ~= -math.huge
    end
    if valueType == "string" then
        budget.bytes = budget.bytes + #value
        return #value <= constants.COMMUNICATION_MAX_PAYLOAD_STRING_LENGTH
            and budget.bytes <= constants.COMMUNICATION_MAX_PAYLOAD_BYTES
    end
    if valueType ~= "table"
        or depth >= constants.COMMUNICATION_MAX_PAYLOAD_DEPTH
        or seen[value]
    then
        return false
    end

    seen[value] = true
    for key, child in pairs(value) do
        local keyType = type(key)
        budget.count = budget.count + 1
        if budget.count > constants.COMMUNICATION_MAX_PAYLOAD_ENTRIES
            or (keyType ~= "string" and keyType ~= "number")
            or not validatePayloadValue(key, depth + 1, budget, seen)
            or not validatePayloadValue(child, depth + 1, budget, seen)
        then
            seen[value] = nil
            return false
        end
    end
    seen[value] = nil
    return true
end

local function isValidPayload(payload)
    return validatePayloadValue(payload, 0, {
        bytes = 0,
        count = 0,
    }, {})
end

local function normalizeCapabilities(capabilities)
    if type(capabilities) ~= "table" then
        return {}
    end

    local normalized = {}
    local seen = {}
    for _, capability in ipairs(capabilities) do
        if #normalized >= constants.COMMUNICATION_MAX_CAPABILITIES then
            break
        end
        if type(capability) == "string"
            and #capability > 0
            and #capability <= constants.COMMUNICATION_MAX_CAPABILITY_LENGTH
            and capability:match("^[%l%d_.-]+$")
            and not seen[capability]
        then
            seen[capability] = true
            normalized[#normalized + 1] = capability
        end
    end
    table.sort(normalized)
    return normalized
end

local function capabilitiesToSet(capabilities)
    local result = {}
    for _, capability in ipairs(capabilities) do
        result[capability] = true
    end
    return result
end

local function getLocalCapabilities()
    local copy = {}
    for _, capability in ipairs(constants.COMMUNICATION_CAPABILITIES) do
        if capability ~= constants.GAMEMASTER_DELEGATION_CAPABILITY
            or not addon.Modules or addon.Modules.IsEnabled("gameMaster") then
            copy[#copy + 1] = capability
        end
    end
    return copy
end

local function createMessageID()
    messageSerial = messageSerial + 1
    if messageSerial >= 1000000 then
        messageSerial = 1
    end
    return string.format(
        "%d-%d",
        math.floor(addon.Runtime.GetMonotonicTime() * 1000),
        messageSerial
    )
end

local function isSelf(sender)
    local api = _G.TRP3_API
    local playerID = type(api) == "table"
        and type(api.globals) == "table"
        and api.globals.player_id
        or nil
    local senderKey = addon.Runtime.NormalizePlayerID(sender)
    local playerKey = addon.Runtime.NormalizePlayerID(playerID)
    return senderKey ~= nil and senderKey == playerKey
end

local function allowIncoming(senderKey, messageType)
    local now = addon.Runtime.GetMonotonicTime()
    local isChunk = messageType
        == constants.GAMEMASTER_MESSAGE_VISIBILITY_CHUNK
    local rateKey = senderKey .. "\031" .. (isChunk and "chunk" or "message")
    local limit = isChunk
        and constants.COMMUNICATION_MAX_CHUNK_MESSAGES_PER_WINDOW
        or constants.COMMUNICATION_MAX_MESSAGES_PER_WINDOW
    local rate = senderRates:Get(rateKey)
    if not rate or now - rate.startedAt >= constants.COMMUNICATION_RATE_WINDOW then
        senderRates:Set(rateKey, {
            count = 1,
            startedAt = now,
        })
        return true
    end
    if rate.count >= limit then
        return false
    end
    rate.count = rate.count + 1
    return true
end

local function isDuplicateMessage(senderKey, messageID)
    local key = senderKey .. "\031" .. messageID
    if seenMessages:Get(key) then
        return true
    end
    seenMessages:Set(key, true)
    return false
end

local function copyPeer(peer)
    if type(peer) ~= "table" then
        return nil
    end

    local capabilities = {}
    for index, capability in ipairs(peer.capabilities) do
        capabilities[index] = capability
    end
    return {
        addonVersion = peer.addonVersion,
        capabilities = capabilities,
        lastSeen = peer.lastSeen,
        playerID = peer.playerID,
        protocolVersion = peer.protocolVersion,
    }
end

local function notifyPeerListeners(peer)
    for _, listener in ipairs(peerListeners) do
        local success, errorMessage = addon.Runtime.SafeInvoke(listener, copyPeer(peer))
        if not success then
            addon.Logger.Error(addon.L("COMMUNICATION_HANDLER_FAILED", tostring(errorMessage)))
        end
    end
end

local function rememberPeer(sender, payload)
    if type(payload) ~= "table" then
        return nil
    end

    local senderKey = addon.Runtime.NormalizePlayerID(sender)
    local protocolVersion = tonumber(payload.protocolVersion)
    local addonVersion = payload.addonVersion
    if not senderKey
        or not protocolVersion
        or protocolVersion < 1
        or protocolVersion ~= math.floor(protocolVersion)
        or type(addonVersion) ~= "string"
        or addonVersion == ""
        or #addonVersion > 40
        or addonVersion:find("[%c|]")
    then
        return nil
    end

    local capabilities = normalizeCapabilities(payload.capabilities)
    local previous = peers:Get(senderKey)
    local previousWasFresh = previous
        and addon.Runtime.GetMonotonicTime() - previous.lastSeen
            <= constants.COMMUNICATION_PEER_TTL
    local peer = {
        addonVersion = addonVersion,
        capabilities = capabilities,
        capabilitySet = capabilitiesToSet(capabilities),
        lastSeen = addon.Runtime.GetMonotonicTime(),
        playerID = sender,
        protocolVersion = protocolVersion,
    }
    peers:Set(senderKey, peer)
    peerQueries:Remove(senderKey)

    if not previous
        or not previousWasFresh
        or previous.addonVersion ~= peer.addonVersion
        or previous.protocolVersion ~= peer.protocolVersion
        or table.concat(previous.capabilities, "\031") ~= table.concat(peer.capabilities, "\031")
    then
        notifyPeerListeners(peer)
    end
    return peer
end

local function createHelloPayload(replyRequested)
    return {
        addonVersion = constants.ADDON_VERSION,
        capabilities = getLocalCapabilities(),
        protocolVersion = constants.COMMUNICATION_PROTOCOL_VERSION,
        replyRequested = replyRequested == true,
    }
end

local function sendEnvelope(target, messageType, payload, priority)
    if not addon.Communication.enabled
        or not isValidMessageType(messageType)
        or not isValidPayload(payload)
    then
        return false, addon.L("COMMUNICATION_INVALID_MESSAGE")
    end

    return addon.CommunicationTransport.SendObject(
        constants.COMMUNICATION_OBJECT_PREFIX,
        {
            id = createMessageID(),
            payload = payload,
            protocolVersion = constants.COMMUNICATION_PROTOCOL_VERSION,
            type = messageType,
        },
        target,
        priority
    )
end

local function dispatchMessage(messageType, payload, sender, channel)
    local callbacks = handlers[messageType]
    if not callbacks then
        return
    end

    for _, callback in ipairs(callbacks) do
        local success, errorMessage = addon.Runtime.SafeInvoke(callback, payload, sender, channel)
        if not success then
            addon.Logger.Error(addon.L("COMMUNICATION_HANDLER_FAILED", tostring(errorMessage)))
        end
    end
end

local function onObjectReceived(envelope, sender, channel)
    local senderKey = addon.Runtime.NormalizePlayerID(sender)
    if not senderKey
        or isSelf(sender)
        or type(envelope) ~= "table"
        or not isValidMessageType(envelope.type)
        or not allowIncoming(senderKey, envelope.type)
    then
        return
    end
    if envelope.protocolVersion ~= constants.COMMUNICATION_PROTOCOL_VERSION
        or type(envelope.id) ~= "string"
        or envelope.id == ""
        or #envelope.id > constants.COMMUNICATION_MESSAGE_ID_LENGTH
        or envelope.id:find("[%c|]")
        or not isValidPayload(envelope.payload)
        or isDuplicateMessage(senderKey, envelope.id)
    then
        return
    end

    if envelope.type == "hello" then
        local peer = rememberPeer(sender, envelope.payload)
        if peer and envelope.payload.replyRequested == true then
            sendEnvelope(sender, "hello_ack", createHelloPayload(false), "LOW")
        end
        return
    end
    if envelope.type == "hello_ack" then
        rememberPeer(sender, envelope.payload)
        return
    end

    local peer = peers:Get(senderKey)
    if not peer
        or peer.protocolVersion ~= constants.COMMUNICATION_PROTOCOL_VERSION
    then
        addon.Communication.QueryPeer(sender)
        return
    end
     
    peer.lastSeen = addon.Runtime.GetMonotonicTime()
    dispatchMessage(envelope.type, envelope.payload, sender, channel)
end

local function parseAnnouncedCapabilities(value)
    local capabilities = {}
    if type(value) ~= "string" then
        return capabilities
    end
    for capability in value:gmatch("[^,]+") do
        capabilities[#capabilities + 1] = capability
    end
    return capabilities
end

local function onPresenceAnnounced(sender, protocolVersion, addonVersion, capabilityList)
    if isSelf(sender) then
        return
    end

    local senderKey = addon.Runtime.NormalizePlayerID(sender)
    local previous = senderKey and peers:Get(senderKey) or nil
    local peer = rememberPeer(sender, {
        addonVersion = addonVersion,
        capabilities = parseAnnouncedCapabilities(capabilityList),
        protocolVersion = tonumber(protocolVersion),
    })
    if peer
        and not previous
        and peer.protocolVersion == constants.COMMUNICATION_PROTOCOL_VERSION
    then
        sendEnvelope(sender, "hello_ack", createHelloPayload(false), "LOW")
    end
end

local function onPresenceDiscovered(sender, protocolVersion, addonVersion)
    if isSelf(sender) or tonumber(protocolVersion) ~= constants.COMMUNICATION_PROTOCOL_VERSION
        or type(addonVersion) ~= "string" or addonVersion == "" or #addonVersion > 40
        or addonVersion:find("[%c|~]") then return end
    local key = addon.Runtime.NormalizePlayerID(sender)
    if not key then return end
    local now = addon.Runtime.GetMonotonicTime()
    local previous = presenceQueries:Get(key)
    if previous and now - previous < constants.COMMUNICATION_QUERY_COOLDOWN then return end
     
     
    if addon.Communication.QueryPeer(sender) then presenceQueries:Set(key, now) end
end

local function sendBroadcast(method, arguments)
    if not method then
        return false
    end
    return addon.CommunicationTransport.Broadcast(
        constants.COMMUNICATION_PRESENCE_COMMAND,
        method,
        unpackArguments(arguments)
    )
end

local function announcePresence()
    if not addon.Communication.enabled then
        return false
    end

    local now = addon.Runtime.GetMonotonicTime()
    if now - lastAnnouncementAt < constants.COMMUNICATION_ANNOUNCE_COOLDOWN then
        return false
    end

    local methods = addon.CommunicationTransport.GetBroadcastMethods()
    local arguments = {
        tostring(constants.COMMUNICATION_PROTOCOL_VERSION),
        constants.ADDON_VERSION,
    }
    local sent = sendBroadcast(methods.World, arguments)
    if methods.Guild and type(IsInGuild) == "function" and IsInGuild() then
        sent = sendBroadcast(methods.Guild, arguments) or sent
    end
    if methods.Group and type(IsInGroup) == "function" and IsInGroup() then
        sent = sendBroadcast(methods.Group, arguments) or sent
    end
    if sent then
        lastAnnouncementAt = now
    end
    return sent
end

local function scheduleAnnouncement(delay)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(delay, announcePresence)
    else
        announcePresence()
    end
end

local function onTRP3Hello(sender)
    if isSelf(sender) then
        scheduleAnnouncement(0)
    end
end

function addon.Communication.Initialize()
    if addon.Communication.initialized then
        return addon.Communication.enabled, initializationError
    end

    local registered, registerError = addon.CommunicationTransport.RegisterObjectHandler(
        constants.COMMUNICATION_OBJECT_PREFIX,
        onObjectReceived
    )
    if not registered then
        initializationError = registerError or addon.L("COMMUNICATION_UNAVAILABLE")
        return false, initializationError
    end

    local broadcastRegistered = addon.CommunicationTransport.RegisterBroadcastHandler(
        constants.COMMUNICATION_PRESENCE_COMMAND,
        onPresenceDiscovered
    )
    addon.CommunicationTransport.RegisterBroadcastHandler(
        constants.COMMUNICATION_BROADCAST_COMMAND,
        onPresenceAnnounced
    )
    addon.Communication.enabled = true
    addon.Communication.initialized = true

    if broadcastRegistered then
        addon.CommunicationTransport.RegisterTRP3HelloHandler(onTRP3Hello)
        scheduleAnnouncement(constants.COMMUNICATION_ANNOUNCE_DELAY)
    end
    return true
end

function addon.Communication.RegisterHandler(messageType, callback)
    if not isValidMessageType(messageType)
        or RESERVED_MESSAGE_TYPES[messageType]
        or type(callback) ~= "function"
    then
        return false, addon.L("COMMUNICATION_INVALID_HANDLER")
    end

    local callbacks = handlers[messageType]
    if not callbacks then
        callbacks = {}
        handlers[messageType] = callbacks
    end
    callbacks[#callbacks + 1] = callback
    return true
end

function addon.Communication.RegisterPeerListener(callback)
    if type(callback) ~= "function" then
        return false, addon.L("COMMUNICATION_INVALID_HANDLER")
    end
    peerListeners[#peerListeners + 1] = callback
    return true
end

function addon.Communication.Send(target, messageType, payload, priority)
    if RESERVED_MESSAGE_TYPES[messageType] then
        return false, addon.L("COMMUNICATION_INVALID_MESSAGE")
    end
    return sendEnvelope(target, messageType, payload, priority)
end

function addon.Communication.CanSendPayload(payload)
    return isValidPayload(payload)
end

function addon.Communication.MeasurePayload(payload, depth)
    local budget = { bytes = 0, count = 0 }
    if validatePayloadValue(payload, depth or 0, budget, {}) then return budget end
end

function addon.Communication.QueryPeer(target)
    local targetKey = addon.Runtime.NormalizePlayerID(target)
    if not targetKey then
        return false, addon.L("COMMUNICATION_INVALID_TARGET")
    end
    local now = addon.Runtime.GetMonotonicTime()
    local lastQuery = peerQueries:Get(targetKey)
    if lastQuery
        and now - lastQuery < constants.COMMUNICATION_QUERY_COOLDOWN
    then
        return true
    end
    local sent, errorMessage = sendEnvelope(
        target,
        "hello",
        createHelloPayload(true),
        "LOW"
    )
    if sent then
        peerQueries:Set(targetKey, now)
    end
    return sent, errorMessage
end

function addon.Communication.GetPeer(playerID)
    local key = addon.Runtime.NormalizePlayerID(playerID)
    local peer = key and peers:Get(key) or nil
    if peer
        and addon.Runtime.GetMonotonicTime() - peer.lastSeen > constants.COMMUNICATION_PEER_TTL then
        return nil
    end
    return copyPeer(peer)
end

function addon.Communication.HasCapability(playerID, capability)
    local key = addon.Runtime.NormalizePlayerID(playerID)
    local peer = key and peers:Get(key) or nil
    if not peer
        or addon.Runtime.GetMonotonicTime() - peer.lastSeen > constants.COMMUNICATION_PEER_TTL
    then
        return false
    end
    return peer.protocolVersion == constants.COMMUNICATION_PROTOCOL_VERSION
        and peer.capabilitySet[capability] == true
end

function addon.Communication.HasKnownCapability(playerID, capability)
    local key = addon.Runtime.NormalizePlayerID(playerID)
    local peer = key and peers:Get(key) or nil
    return peer ~= nil
        and peer.protocolVersion == constants.COMMUNICATION_PROTOCOL_VERSION
        and peer.capabilitySet[capability] == true
end

function addon.Communication.Announce()
    return announcePresence()
end
