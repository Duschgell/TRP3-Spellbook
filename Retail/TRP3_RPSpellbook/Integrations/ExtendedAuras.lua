local _, addon = ...
addon.ExtendedAuras = {}
local adapter = addon.ExtendedAuras
local managed, profileKey, busy, hooked, initialized = {}, nil, false, false, false

 
function adapter.ID(profile, effectID)
    local first, second = 5381, 7919
    local value = profile .. "\031" .. effectID
    for index = 1, #value do
        local byte = value:byte(index)
        first = (first * 33 + byte) % 2147483647
        second = (second * 37 + byte) % 2147483647
    end
    return string.format("rpsb_aura_%08x%08x", first, second)
end

local function api()
    local extended = _G.TRP3_API and TRP3_API.extended
    local auras = extended and extended.auras
    if not auras or type(extended.registerObject) ~= "function" or type(extended.unregisterObject) ~= "function"
        or type(extended.getClass) ~= "function" or type(extended.classExists) ~= "function" then return nil end
    for _, name in ipairs({ "apply", "remove", "cancel", "isActive", "getDuration", "setDuration" }) do
        if type(auras[name]) ~= "function" then return nil end
    end
    return extended, auras
end

local function iconName(icon)
    if type(icon) == "string" then
        icon = icon:gsub("^Interface[\\/]ICONS[\\/]", "")
        if icon:match("^[%w_%-]+$") then return icon end
    elseif type(icon) == "number" and _G.LibStub then
        local library = LibStub("LibRPMedia-1.2", true)
        if library and library.GetIconNameByID then
            local ok, name = pcall(library.GetIconNameByID, library, icon)
            if ok and type(name) == "string" then return name end
        end
    end
    return "INV_Misc_Book_09"
end

function adapter.BuildClass(entry, fingerprint)
    local spell, effects = entry.spell, entry.spell.effects
    local text = addon.EffectDisplay.Text
    local class = { TY = "AU", rpsbOwner = fingerprint, BA = {
        NA = text(spell.name, 200), DE = text(spell.description), IC = iconName(spell.icon),
        CA = addon.L(effects.debuff and "TIMED_DEBUFF" or "TIMED_BUFF"),
        HE = effects.debuff ~= true, CC = true, WE = not entry.hidden, AA = true,
        CO = effects.debuff and "b76464" or "baa270",
        OV = entry.combat and (effects.durationRounds == 0 and "\226\136\158" or addon.L("AURA_ROUNDS")) or "",
    } }
    if not entry.combat then class.BA.DU = math.max(1, entry.expiresAt - addon.Runtime.GetTimestamp()) end
    return class
end

local function ownsClass(extended, id, state)
    local class = extended.classExists(id) and extended.getClass(id)
    return type(class) == "table" and class.rpsbOwner == state.fingerprint
end

local function initializeHooks(extended, auras)
    if hooked or type(hooksecurefunc) ~= "function" then return end
    hooked = true
    local function removed(id)
        local state = managed[id]
        if busy or not state or state.profile ~= addon.Database.GetActiveProfileKey() then return end
        local ok, confirmed = pcall(function()
            return ownsClass(extended, id, state) and auras.isActive(id) == false
        end)
        if ok and confirmed then
            if not addon.EffectDisplay.Remove(state.entry) and addon.Logger then addon.Logger.Error(addon.L("AURA_REMOVE_FAILED")) end
        end
    end
    hooksecurefunc(auras, "cancel", removed)
    hooksecurefunc(auras, "remove", removed)
end

local function samePresentation(first, second)
    if type(first) ~= "table" or type(first.BA) ~= "table" then return false end
    for _, key in ipairs({ "NA", "DE", "IC", "CA", "HE", "CC", "WE", "AA", "CO", "OV" }) do
        if first.BA[key] ~= second.BA[key] then return false end
    end
    return (first.BA.DU == nil) == (second.BA.DU == nil)
end

function adapter.Sync()
    if busy or addon.GameMasterService.IsTutorialActive() or addon.GameMasterService.IsTestMode() then return end
    local extended, auras = api()
    local profile = addon.Database.GetActiveProfileKey()
    if not extended or not profile then return end
    initializeHooks(extended, auras)
    busy = true
    local ok, failure = pcall(function()
        if profileKey ~= profile then
             
            for id, state in pairs(managed) do
                if not auras.isActive(id) and ownsClass(extended, id, state) then extended.unregisterObject(id) end
            end
            managed, profileKey = {}, profile
        end
        local wanted, count = {}, 0
        for _, entry in ipairs(addon.EffectDisplay.List(addon.GameMasterRoster.GetLocalPlayerID())) do
            if not entry.pending and not entry.native then
                count = count + 1
                if count > 64 then break end
                local id = adapter.ID(profile, entry.id)
                local fingerprint = profile .. "\031" .. entry.id
                local exists = extended.classExists(id)
                local existing = exists and extended.getClass(id)
                if not existing or existing.rpsbOwner == fingerprint then
                    wanted[id] = true
                    local class = adapter.BuildClass(entry, fingerprint)
                    local writable = true
                    if existing and not samePresentation(existing, class) then
                        if auras.isActive(id) then auras.remove(id) end
                        local replacement = extended.classExists(id) and extended.getClass(id)
                        if replacement and replacement.rpsbOwner ~= fingerprint then
                            managed[id], writable = nil, false
                        elseif auras.isActive(id) then
                             
                            writable = false
                        else
                            managed[id] = nil
                        end
                    end
                    if writable then
                        if not managed[id] then
                            extended.registerObject(id, class, 0)
                            managed[id] = { entry = entry, profile = profile, fingerprint = fingerprint, combat = entry.combat }
                        else managed[id].entry = entry end
                        if not auras.isActive(id) then auras.apply(id) end
                        local remaining = entry.combat and math.huge or math.max(0, entry.expiresAt - addon.Runtime.GetTimestamp())
                        local nativeRemaining = auras.getDuration(id)
                        if nativeRemaining ~= remaining and (remaining == math.huge or math.abs(nativeRemaining - remaining) > 1) then
                            auras.setDuration(id, remaining, "=")
                        end
                    end
                end
            end
        end
        for id, state in pairs(managed) do
            if not wanted[id] then
                if ownsClass(extended, id, state) then
                    if auras.isActive(id) then auras.remove(id) end
                    if not auras.isActive(id) then
                        if ownsClass(extended, id, state) then extended.unregisterObject(id) end
                        managed[id] = nil
                    end
                else
                    managed[id] = nil
                end
            end
        end
    end)
    busy = false
    if not ok and addon.Logger then addon.Logger.Error(tostring(failure)) end
end

function adapter.Initialize()
    if initialized then return end
    initialized = true
    local queued = false
    local function request()
        if queued then return end
        queued = true
        local function run() queued = false; adapter.Sync() end
        if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
    end
    addon.TimedEffects.RegisterListener(request)
    addon.GameMasterService.RegisterListener(request)
     
    if C_Timer and C_Timer.After then C_Timer.After(0, adapter.Sync) end
end
