local _, addon = ...

addon.ChatAddonSupport = {}
local integration = addon.ChatAddonSupport
local protectedStart, protectedEnd = "\005\006RPSB", "\007\008"
local protectedPattern = protectedStart .. "([%w+/=]+):(%d+)" .. protectedEnd
local hookedCore, coreHandler, hookedThrottle, throttleHandler

local function readable(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret ~= false then return false end
    end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible ~= true then return false end
    end
    return true
end

local function validIdentifier(identifier)
    return addon.ChatLinks.DecodeNativeIdentifier(identifier) ~= nil
        and addon.ChatLinks.DecodeNativeDisplayName(identifier) ~= nil
end

local function protect(message, codec)
    local failed = false
    local result = message:gsub("%[TRP3:([^%]]+)%]", function(identifier)
        if not validIdentifier(identifier) then return nil end
        local name, suffix = identifier:match("^(.*):(%d+)$")
        local ok, encoded = pcall(codec.EncodeBase64, name)
        if not ok or type(encoded) ~= "string" or not encoded:match("^[%w+/=]+$")
            or #encoded > 108 or #encoded % 4 ~= 0 then failed = true; return nil end
        local token = protectedStart .. encoded .. ":" .. suffix .. protectedEnd
        if #token > 249 or #token < #identifier + 7 then failed = true; return nil end
        return token
    end)
    result = result:gsub("[^ \n]+", function(word)
        if #word <= 249 or not word:find(protectedStart, 1, true) then return nil end
        return word:gsub("()" .. protectedPattern .. "()", function(start, encoded, suffix, finish)
            return (start > 1 and "\011 " or "")
                .. protectedStart .. encoded .. ":" .. suffix .. protectedEnd
                .. (finish <= #word and " \012" or "")
        end)
    end)
    return not failed and result or nil
end

local function restore(message, codec)
    local failed = false
    local result = message:gsub(protectedPattern, function(encoded, suffix)
        if #encoded > 108 or #encoded % 4 ~= 0 or #suffix > 200 then failed = true; return nil end
        local ok, name = pcall(codec.DecodeBase64, encoded)
        if not ok or type(name) ~= "string" or #name > 80 then failed = true; return nil end
        local encodeSuccess, reencodedName = pcall(codec.EncodeBase64, name)
        local identifier = name .. ":" .. suffix
        if not encodeSuccess or reencodedName ~= encoded or not validIdentifier(identifier) then failed = true; return nil end
        return "[TRP3:" .. identifier .. "]"
    end)
    if failed or result:find(protectedStart, 1, true) then return nil end
    return result:gsub("\011 ?", ""):gsub(" ?\012", "")
end

local function reportFailure()
    addon.Logger.Error(addon.L("CHAT_LINK_API_UNAVAILABLE"))
end

function integration.Initialize()
    local codec, stub, throttle = _G.C_EncodingUtil, _G.LibStub, _G.ChatThrottleLib
    if type(codec) ~= "table" or type(codec.EncodeBase64) ~= "function" or type(codec.DecodeBase64) ~= "function"
        or (type(stub) ~= "table" and type(stub) ~= "function")
        or type(throttle) ~= "table" or type(throttle.SendChatMessage) ~= "function" then return false end
    local libraryOK, library = pcall(stub, "AceAddon-3.0", true)
    if not libraryOK or type(library) ~= "table" or type(library.GetAddon) ~= "function" then return false end
    local coreOK, core = pcall(library.GetAddon, library, "UnlimitedChatMessage", true)
    if not coreOK or type(core) ~= "table" or type(core.SendChatMessage) ~= "function" then return false end

    if hookedThrottle ~= throttle or throttleHandler ~= throttle.SendChatMessage then
        local original = throttle.SendChatMessage
        throttleHandler = function(self, priority, prefix, message, ...)
            if readable(prefix) and prefix == "UCM" and type(message) == "string" and readable(message)
                and (message:find(protectedStart, 1, true) or message:find("[\011\012]")) then
                message = restore(message, codec)
                if not message then reportFailure(); return end
                if message == "" then return end
            end
            return original(self, priority, prefix, message, ...)
        end
        hookedThrottle, throttle.SendChatMessage = throttle, throttleHandler
    end
    if hookedCore ~= core or coreHandler ~= core.SendChatMessage then
        local original = core.SendChatMessage
        coreHandler = function(self, message, ...)
            if type(message) == "string" and readable(message) and (#message > 255 or message:find("\n", 1, true)) then
                message = protect(message, codec)
                if not message then reportFailure(); return end
            end
            return original(self, message, ...)
        end
        hookedCore, core.SendChatMessage = core, coreHandler
    end
    return true
end

if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self, event, name)
        if event == "PLAYER_LOGIN" then self:UnregisterEvent("PLAYER_LOGIN") end
        if hookedCore or event == "PLAYER_LOGIN" or name == "UnlimitedChatMessage" then integration.Initialize() end
    end)
end
