local _, addon = ...

 
_G.TRP3_RPSpellbookAddon = addon
local Modules = {}
addon.Modules = Modules
local registry, callbacks = {}, {}
local loggedIn = type(IsLoggedIn) == "function" and IsLoggedIn() == true
local coreReady, ready = false, false
local names = {
    gameMaster = "TRP3_RPSpellbook_GameMaster",
    npc = "TRP3_RPSpellbook_NPC",
}

local function report(errorMessage)
    if addon.Logger then addon.Logger.Error(tostring(errorMessage)) end
end

local function initializeModule(entry)
    if entry.initialized or entry.failed then return end
    entry.initialized = true
    if entry.initialize then
        local ok, result, err = pcall(entry.initialize)
        if not ok or result == false then
            entry.failed = true
            entry.failure = tostring((ok and err or result) or "Module initialization failed")
            report(entry.failure)
        end
    end
end

local function finishStartup()
    if ready or not coreReady or not loggedIn then return end
     
    for _, entry in pairs(registry) do initializeModule(entry) end
    ready = true
    local pending = callbacks
    callbacks = {}
    for _, callback in ipairs(pending) do
        local ok, err = pcall(callback)
        if not ok then report(err) end
    end
end

function Modules.Register(id, initialize)
    if not names[id] or registry[id]
        or (initialize ~= nil and type(initialize) ~= "function") then
        return false
    end
    local entry = { initialize = initialize }
    registry[id] = entry
    if ready then initializeModule(entry) end
    return not entry.failed
end

function Modules.IsEnabled(id)
    local entry = registry[id]
    return entry ~= nil and not entry.failed
end

function Modules.IsReady() return ready end

function Modules.WhenReady(callback)
    if type(callback) ~= "function" then return end
    if ready then callback() else callbacks[#callbacks + 1] = callback end
end

function Modules.CoreReady()
    coreReady = true
    finishStartup()
end

function Modules.Require(id)
    if Modules.IsEnabled(id) then return true end
    report(registry[id] and registry[id].failure
        or addon.L("OPTIONAL_MODULE_REQUIRED", names[id] or tostring(id)))
    return false
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    loggedIn = true
    finishStartup()
end)
