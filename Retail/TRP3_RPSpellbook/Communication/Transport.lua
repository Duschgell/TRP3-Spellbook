local _, addon = ...

addon.CommunicationTransport = {}

local VALID_PRIORITIES = {
    HIGH = true,
    LOW = true,
    MEDIUM = true,
}

local PRIORITY_ALIASES = {
    NORMAL = "MEDIUM",
}

local VALID_BROADCAST_METHODS = {
    WORLD = true,
    GUILD = true,
    GROUP = true,
}

local function getCommunications()
    local totalRP3 = _G.AddOn_TotalRP3
    local communications = totalRP3 and totalRP3.Communications or nil
    return type(communications) == "table" and communications or nil
end

local function isValidProtocolName(value, maximumLength)
    return type(value) == "string"
        and value ~= ""
        and #value <= maximumLength
        and value:match("^[%w_.-]+$") ~= nil
end

local function isValidTarget(target)
    return type(target) == "string"
        and target ~= ""
        and #target <= addon.Constants.MAX_LINK_OWNER_LENGTH
        and not target:find("[%c|:]")
end

local function invokeHandler(callback, ...)
    local success, errorMessage = addon.Runtime.SafeInvoke(callback, ...)
    if not success then
        addon.Logger.Error(addon.L("COMMUNICATION_HANDLER_FAILED", tostring(errorMessage)))
    end
end

function addon.CommunicationTransport.IsAvailable()
    local communications = getCommunications()
    return communications ~= nil
        and type(communications.registerSubSystemPrefix) == "function"
        and type(communications.sendObject) == "function"
end

function addon.CommunicationTransport.RegisterObjectHandler(prefix, callback)
    if not isValidProtocolName(prefix, 64) or type(callback) ~= "function" then
        return false, addon.L("COMMUNICATION_INVALID_HANDLER")
    end

    local communications = getCommunications()
    if not communications or type(communications.registerSubSystemPrefix) ~= "function" then
        return false, addon.L("COMMUNICATION_UNAVAILABLE")
    end

    local success, result = pcall(
        communications.registerSubSystemPrefix,
        prefix,
        function(payload, sender, channel)
            invokeHandler(callback, payload, sender, channel)
        end
    )
    if not success then
        return false, result
    end
    return true, result
end

function addon.CommunicationTransport.SendObject(prefix, payload, target, priority)
    if not isValidProtocolName(prefix, 64) or not isValidTarget(target) then
        return false, addon.L("COMMUNICATION_INVALID_TARGET")
    end

    priority = type(priority) == "string" and string.upper(priority) or "LOW"
    priority = PRIORITY_ALIASES[priority] or priority
    if not VALID_PRIORITIES[priority] then
        return false, addon.L("COMMUNICATION_INVALID_PRIORITY")
    end

    local communications = getCommunications()
    if not communications or type(communications.sendObject) ~= "function" then
        return false, addon.L("COMMUNICATION_UNAVAILABLE")
    end

    local success, result = pcall(
        communications.sendObject,
        prefix,
        payload,
        "WHISPER",
        target,
        priority
    )
    if not success or result == false then
        return false, result or addon.L("COMMUNICATION_SEND_FAILED")
    end
    return true
end

function addon.CommunicationTransport.RegisterBroadcastHandler(command, callback)
    if not isValidProtocolName(command, 32) or type(callback) ~= "function" then
        return false, addon.L("COMMUNICATION_INVALID_HANDLER")
    end

    local communications = getCommunications()
    local broadcast = communications and communications.broadcast or nil
    if type(broadcast) ~= "table" or type(broadcast.registerCommand) ~= "function" then
        return false, addon.L("COMMUNICATION_BROADCAST_UNAVAILABLE")
    end

    local success, result = pcall(broadcast.registerCommand, command, function(sender, ...)
        invokeHandler(callback, sender, ...)
    end)
    if not success then
        return false, result
    end
    return true
end

function addon.CommunicationTransport.RegisterTRP3HelloHandler(callback)
    local communications = getCommunications()
    local broadcast = communications and communications.broadcast or nil
    local helloCommand = type(broadcast) == "table" and broadcast.HELLO_CMD or nil
    if not helloCommand then
        return false, addon.L("COMMUNICATION_BROADCAST_UNAVAILABLE")
    end
    return addon.CommunicationTransport.RegisterBroadcastHandler(helloCommand, callback)
end

function addon.CommunicationTransport.Broadcast(command, method, ...)
    if not isValidProtocolName(command, 32)
        or type(method) ~= "string" or not VALID_BROADCAST_METHODS[method] then
        return false, addon.L("COMMUNICATION_BROADCAST_UNAVAILABLE")
    end

    local communications = getCommunications()
    local broadcast = communications and communications.broadcast or nil
    if type(broadcast) ~= "table" or type(broadcast.broadcast) ~= "function" then
        return false, addon.L("COMMUNICATION_BROADCAST_UNAVAILABLE")
    end

     
    local length = #"RPB1" + 1 + #command
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) ~= "string" and type(value) ~= "number" then
            return false, addon.L("COMMUNICATION_INVALID_MESSAGE")
        end
        value = tostring(value)
        if value:find("~", 1, true) then return false, addon.L("COMMUNICATION_INVALID_MESSAGE") end
        length = length + 1 + #value
    end
    if length > 254 then return false, addon.L("COMMUNICATION_INVALID_MESSAGE") end

    local success, errorMessage = pcall(broadcast.broadcast, command, method, ...)
    if not success or errorMessage == false then
        return false, errorMessage
    end
    return true
end

function addon.CommunicationTransport.GetBroadcastMethods()
    local api = _G.TRP3_API
    local methods = type(api) == "table" and api.BroadcastMethod or nil
    return type(methods) == "table" and methods or {}
end
