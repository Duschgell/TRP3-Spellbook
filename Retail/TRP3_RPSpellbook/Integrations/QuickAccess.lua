local _, addon = ...
addon.QuickAccess = {}
local quick = addon.QuickAccess
local registered, registrationAttempted, activeProfile = false, false, nil
local slots, maximum = {}, 8
local function configuration() return _G.TRP3_API and TRP3_API.configuration end
local function pins()
    local profile = addon.Database.GetActiveProfileData()
    if not profile then return {} end
    if type(profile.quickSpells) ~= "table" then profile.quickSpells = {} end
    for index = 1, maximum do
        if type(profile.quickSpells[index]) ~= "string" or not addon.Database.GetSpell(profile.quickSpells[index]) then
            profile.quickSpells[index] = nil
        end
    end
    return profile.quickSpells
end
local function key(index) return "toolbar_content_rpspellbook_quick_" .. index end
local function toolbarIcon(icon)
    if type(icon) == "string" then
        local numeric = tonumber(icon)
        if numeric then icon = numeric
        else
            local _, prefix = icon:lower():find("^interface[\\/]icons[\\/]")
            if prefix then icon = icon:sub(prefix + 1) end
            if icon:match("^[%w_%-]+$") then return icon end
        end
    end
    if type(icon) == "number" and icon > 0 and icon < math.huge and icon % 1 == 0 then return icon end
    return addon.Constants.DEFAULT_TRP3_TOOLBAR_ICON
end

function quick.IsPinned(spellID)
    local entries = pins()
    for index = 1, maximum do if entries[index] == spellID then return true end end
    return false
end

function quick.Minutes()
    local profile = addon.Database.GetActiveProfileData()
    local value = profile and tonumber(profile.quickEffectMinutes)
    return value and value >= 1 and value <= 1440 and value % 1 == 0 and value or 30
end

function quick.SetMinutes(value)
    local profile = addon.Database.GetActiveProfileData()
    value = tonumber(value)
    if profile and value and value >= 1 and value <= 1440 and value % 1 == 0 then profile.quickEffectMinutes = value end
end

function quick.Refresh()
    if not registered then return end
    local profile, entries, config = addon.Database.GetActiveProfileKey(), pins(), configuration()
    for index = 1, maximum do
        local changed = activeProfile ~= profile or slots[index] ~= entries[index]
        slots[index] = entries[index]
        if changed then config.setValue(key(index), entries[index] ~= nil) end
    end
    activeProfile = profile
end

function quick.Toggle(spellID)
    if not registered or not addon.Database.GetSpell(spellID) then return false end
    local entries, empty = pins(), nil
    for index = 1, maximum do
        if entries[index] == spellID then entries[index] = nil; quick.Refresh(); return true end
        if not entries[index] and not empty then empty = index end
    end
    if not empty then addon.Logger.Error(addon.L("QUICK_FULL")); return false end
    entries[empty] = spellID
    quick.Refresh()
    return true
end

function quick.Activate(model, mouse)
    if addon.Core and not addon.Core.enabled then return false end
    if model.profile ~= addon.Database.GetActiveProfileKey() or not quick.IsPinned(model.spellID) then return false end
    local spell = addon.Database.GetSpell(model.spellID)
    if not spell or addon.GameMasterService.IsTutorialActive() or addon.GameMasterService.IsTestMode() then return false end
    if IsShiftKeyDown and IsShiftKeyDown() then
        return addon.ChatInsert.InsertSpell(model.profile, spell)
    end
    if addon.GameMasterService.IsSessionActive() then return addon.GameMasterActionDialog.Open(spell) end
    if addon.TimedEffects.CanCast(spell.id) then
        if mouse == "RightButton" then addon.TimedEffectsView.Cast(spell.id); return true end
        local target = addon.EffectDisplay.UnitPlayerID("target")
        if not target then target = addon.GameMasterRoster.GetLocalPlayerID() end
        local profileData = addon.Database.GetActiveProfileData()
        local success, message = addon.TimedEffects.Cast(spell.id, target, quick.Minutes(), profileData and profileData.quickEffectHidden == true)
        if success then addon.Logger.Info(message) else addon.Logger.Error(message) end
        return success
    end
    return addon.ChatInsert.InsertSpell(model.profile, spell)
end

function quick.Register()
    if registered or registrationAttempted then return registered end
    local config = configuration()
    if not config then return false end
    registrationAttempted = true
    local models = {}
    for index = 1, maximum do
         
        config.registerConfigKey(key(index), false)
        local model = {
            id = "rpspellbook_quick_" .. index, icon = toolbarIcon(nil),
            text = addon.L("QUICK_SLOT", index), configText = addon.L("QUICK_SLOT", index),
            onClick = function(_, model, mouse) quick.Activate(model, mouse) end,
            onModelUpdate = function(model)
                model.profile, model.spellID = addon.Database.GetActiveProfileKey(), pins()[index]
                local spell = model.spellID and addon.Database.GetSpell(model.spellID)
                model.icon = toolbarIcon(spell and spell.icon)
                model.tooltip = spell and addon.EffectDisplay.Text(spell.name) or addon.L("QUICK_SLOT", index)
                if addon.GameMasterService.IsSessionActive() then model.tooltipSub = addon.L("QUICK_COMBAT_HELP")
                elseif spell and addon.TimedEffects.CanCast(spell.id) then model.tooltipSub = addon.L("QUICK_HELP", quick.Minutes())
                else model.tooltipSub = addon.L("QUICK_CHAT_HELP") end
                local data = addon.Database.GetActiveProfileData()
                if spell and not addon.GameMasterService.IsSessionActive() and addon.TimedEffects.CanCast(spell.id)
                    and data and data.quickEffectHidden then model.tooltipSub = model.tooltipSub .. " " .. addon.L("TIMED_HIDDEN") end
                model.tooltipInstructions = { { "SHIFT-BUTTON1", addon.L("QUICK_CHAT_HELP") } }
            end,
        }
        models[index] = model
        local success, message = addon.TRP3Bridge.RegisterToolbarButton(model)
        if not success then
             
            for slot, partial in ipairs(models) do
                partial.onModelUpdate, partial.onClick = nil, nil
                config.setValue(key(slot), false)
            end
            addon.Logger.Error(addon.L("TOOLBAR_REGISTER_FAILED", tostring(message)))
            return false
        end
    end
    registered = true
    quick.Refresh()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, quick.Refresh) end
    return true
end
