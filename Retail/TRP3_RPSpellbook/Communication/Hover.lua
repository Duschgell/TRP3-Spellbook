local _, addon = ...

local bridge = addon.TRP3Bridge
local legacyInitialize = bridge.InitializeSpellHover
local legacyRequest = bridge.RequestSpellHover
local responseCallback
local initialized = false
local protocolReady = false
local requestRates = addon.Cache.NewBounded(addon.Constants.COMMUNICATION_MAX_PEERS)

local function isValidRequestID(value)
    return addon.Runtime.IsSafeIdentifier(
        value,
        addon.Constants.MAX_CHAT_HOVER_REQUEST_ID_LENGTH
    )
end

local function isValidIdentifier(value)
    return addon.Runtime.IsSafeIdentifier(
        value,
        addon.Constants.MAX_CHAT_TOKEN_LENGTH
    )
end

local function allowRequest(sender)
    local senderKey = addon.Runtime.NormalizePlayerID(sender)
    if not senderKey then
        return false
    end

    local now = addon.Runtime.GetMonotonicTime()
    local rate = requestRates:Get(senderKey)
    if not rate
        or now - rate.startedAt >= addon.Constants.CHAT_HOVER_RATE_WINDOW
    then
        requestRates:Set(senderKey, {
            count = 1,
            startedAt = now,
        })
        return true
    end
    if rate.count >= addon.Constants.MAX_CHAT_HOVER_REQUESTS_PER_SENDER_WINDOW then
        return false
    end
    rate.count = rate.count + 1
    return true
end

local function deliverResponse(sender, response)
    if type(responseCallback) ~= "function" then
        return
    end

    local success, errorMessage = addon.Runtime.SafeInvoke(responseCallback, sender, response)
    if not success then
        addon.Logger.Error(tostring(errorMessage))
    end
end

local function getLocalPlayerID()
    local api = _G.TRP3_API
    return type(api) == "table"
        and type(api.globals) == "table"
        and api.globals.player_id
        or nil
end

local function handleRequest(request, sender)
    if type(request) ~= "table"
        or request.formatVersion ~= addon.Constants.CHAT_LINK_FORMAT_VERSION
        or not isValidRequestID(request.requestId)
        or not isValidIdentifier(request.identifier)
        or not allowRequest(sender)
    then
        return
    end

    local spell = bridge.GetOwnSpellChatTooltip(getLocalPlayerID(), request.identifier)
    addon.Communication.Send(
        sender,
        addon.Constants.COMMUNICATION_HOVER_RESPONSE_TYPE,
        {
            formatVersion = addon.Constants.CHAT_LINK_FORMAT_VERSION,
            identifier = request.identifier,
            requestId = request.requestId,
            spell = spell,
            status = spell and "ok" or "missing",
        },
        "LOW"
    )
end

local function handleResponse(response, sender)
    deliverResponse(sender, response)
end

local function initializeProtocol()
    if not addon.Communication.enabled then
        return false, addon.L("COMMUNICATION_UNAVAILABLE")
    end

    local requestRegistered, requestError = addon.Communication.RegisterHandler(
        addon.Constants.COMMUNICATION_HOVER_REQUEST_TYPE,
        handleRequest
    )
    if not requestRegistered then
        return false, requestError
    end

    local responseRegistered, responseError = addon.Communication.RegisterHandler(
        addon.Constants.COMMUNICATION_HOVER_RESPONSE_TYPE,
        handleResponse
    )
    if not responseRegistered then
        return false, responseError
    end
    return true
end

function bridge.InitializeSpellHover(callback)
    if type(callback) ~= "function" then
        return false, addon.L("INVALID_CALLBACK")
    end
    responseCallback = callback
    if initialized then
        return true
    end

    local protocolSuccess, protocolError = initializeProtocol()
    protocolReady = protocolSuccess
    local legacySuccess, legacyError = false, nil
    if type(legacyInitialize) == "function" then
        legacySuccess, legacyError = legacyInitialize(deliverResponse)
    end
    initialized = protocolSuccess or legacySuccess
    if initialized then
        return true
    end
    return false, protocolError or legacyError or addon.L("CHAT_HOVER_API_UNAVAILABLE")
end

function bridge.RequestSpellHover(sender, identifier, requestID)
    if not initialized
        or not addon.Runtime.NormalizePlayerID(sender)
        or not isValidIdentifier(identifier)
        or not isValidRequestID(requestID)
    then
        return false, addon.L("CHAT_HOVER_API_UNAVAILABLE")
    end

    if protocolReady
        and addon.Communication.HasCapability(
        sender,
        addon.Constants.COMMUNICATION_HOVER_CAPABILITY
    ) then
        local sent, sendError = addon.Communication.Send(
            sender,
            addon.Constants.COMMUNICATION_HOVER_REQUEST_TYPE,
            {
                formatVersion = addon.Constants.CHAT_LINK_FORMAT_VERSION,
                identifier = identifier,
                requestId = requestID,
            },
            "LOW"
        )
        if sent then
            return true
        end
        addon.Logger.Error(sendError or addon.L("COMMUNICATION_SEND_FAILED"))
    elseif addon.Communication.enabled then
        addon.Communication.QueryPeer(sender)
    end

    if type(legacyRequest) == "function" then
        return legacyRequest(sender, identifier, requestID)
    end
    return false, addon.L("CHAT_HOVER_API_UNAVAILABLE")
end
