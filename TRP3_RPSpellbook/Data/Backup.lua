local _, addon = ...
local backup, validation = {}, addon.BackupValidation
addon.Backup = backup
backup.MAX_BYTES = validation.Limits.MAX_BYTES + 12
local PREFIX = "RPSBBACKUP1:"
local plans = setmetatable({}, { __mode = "k" })
local applying, applied, waiting = false, false, false

local function enum(...) local result = {}; for _, key in ipairs({ ... }) do result[key] = true end; return result end
local specs = {
    TRP3_RPSpellbook_GMOpacity = { minimum = 35, maximum = 100 },
    TRP3_RPSpellbook_GMFontSize = { minimum = 10, maximum = 18 },
    TRP3_RPSpellbook_GMHistory = { minimum = 2, maximum = addon.Constants.GAMEMASTER_MAX_HISTORY },
    TRP3_RPSpellbook_GMStyle = enum("modern", "minimal"),
    TRP3_RPSpellbook_GMConfirmClose = "boolean",
    TRP3_RPSpellbook_GMNameMode = enum("engine", "trp_first", "trp_full", "trp_last", "trp_title"),
    TRP3_RPSpellbook_GMProfileColors = "boolean", TRP3_RPSpellbook_GMProfileIcons = "boolean",
    TRP3_RPSpellbook_GMCompactOpacity = { minimum = 25, maximum = 100 },
    TRP3_RPSpellbook_GMCompactFontSize = { minimum = 9, maximum = 18 },
    TRP3_RPSpellbook_GMCompactStyle = enum("modern", "minimal"),
    TRP3_RPSpellbook_GMFeedbackChat = "boolean", TRP3_RPSpellbook_GMFeedbackScreen = "boolean",
    TRP3_RPSpellbook_GMFeedbackSound = "boolean", TRP3_RPSpellbook_AutoSpellFallback = "boolean",
    TRP3_RPSpellbook_GMChatFallback = "boolean", TRP3_RPSpellbook_GMDefaultVisibility = enum("full", "targets", "hidden"),
    TRP3_RPSpellbook_CreationTimeMode = enum("rounds", "time"),
    TRP3_RPSpellbook_CreationEditorTheme = enum("default", "midnight", "parchment", "emerald", "titan", "dynamic"),
    TRP3_RPSpellbook_BookPresentation = enum("default", "fancy"),
    rpspellbook_fancy_reduced_motion = "boolean",
    rpspellbook_fancy_button_clarity = { minimum = 0, maximum = 100 },
    rpspellbook_fancy_button_background = { minimum = 0, maximum = 100 },
    rpspellbook_seasonal_enabled = "boolean",
    rpspellbook_effect_bar_locked = "boolean",
    rpspellbook_update_notifications = "boolean",
    TRP3_RPSpellbook_CreationMagicSubtypes = "boolean",
    rpspellbook_currently_effects = "boolean", rpspellbook_aura_nameplates = "boolean",
    toolbar_content_trp3_rpspellbook = "boolean",
}
for slot = 1, 8 do specs["toolbar_content_rpspellbook_quick_" .. slot] = "boolean" end
local configKeys = {}
for key in pairs(specs) do configKeys[#configKeys + 1] = key end
table.sort(configKeys)

local function validPreference(key, value)
    local spec = specs[key]
    if spec == "boolean" then return type(value) == "boolean" end
    if type(spec) ~= "table" then return false end
    if spec.minimum then
        return type(value) == "number" and value % 1 == 0 and value >= spec.minimum and value <= spec.maximum
    end
    return type(value) == "string" and spec[value] == true
end

local function config()
    local api = _G.TRP3_API
    return type(api) == "table" and api.configuration or nil
end

function backup.GetConfigurationKeys()
    local result = {}; for index, key in ipairs(configKeys) do result[index] = key end; return result
end

local function preferences()
    local api, result = config(), {}
    if type(api) ~= "table" or type(api.getValue) ~= "function" or type(api.setValue) ~= "function" then return nil end
    for _, key in ipairs(configKeys) do
        local ok, value = pcall(api.getValue, key)
        if not ok or not validPreference(key, value) then return nil end
        result[key] = value
    end
    return result
end

local function coreCopy()
    local root = _G.TRP3_RPSpellbookDB
    if type(root) ~= "table" then return nil end
    local value = {}
    for key, item in pairs(root) do if key ~= "backupControl" then value[key] = item end end
    return validation.Clone(value)
end

local function npcAvailable()
    return addon.Modules and addon.Modules.IsEnabled("npc") and type(_G.TRP3_RPSpellbookNPCDB) == "table"
end

local function validate(value)
    if type(value) ~= "table" or value.format ~= "spellbook-backup" or value.version ~= 1
        or (value.scope ~= "core" and value.scope ~= "full" and value.scope ~= "settings" and value.scope ~= "npc") then return false end
    for key in pairs(value) do
        if key ~= "format" and key ~= "version" and key ~= "scope" and key ~= "core"
            and key ~= "settings" and key ~= "configuration" and key ~= "npc" then return false end
    end
    local ownsCore = value.scope == "core" or value.scope == "full"
    local ownsNPC = value.scope == "npc" or value.scope == "full"
    if ownsCore ~= (value.core ~= nil) or ownsNPC ~= (value.npc ~= nil)
        or (value.scope == "settings") ~= (value.settings ~= nil)
        or (value.scope ~= "npc") ~= (value.configuration ~= nil) then return false end
    if ownsCore and not validation.Core(value.core) then return false end
    if ownsNPC and not validation.NPC(value.npc) then return false end
    if value.settings ~= nil and type(value.settings) ~= "table" then return false end
    if value.configuration then
        if type(value.configuration) ~= "table" then return false end
         
         
        if value.configuration.rpspellbook_fancy_reduced_motion == nil then
            value.configuration.rpspellbook_fancy_reduced_motion = false
        end
        for _, key in ipairs({ "rpspellbook_fancy_button_clarity", "rpspellbook_fancy_button_background" }) do
            if value.configuration[key] == nil then value.configuration[key] = 0 end
        end
        if value.configuration.rpspellbook_seasonal_enabled == nil then
            value.configuration.rpspellbook_seasonal_enabled = true
        end
        for _, key in ipairs({ "rpspellbook_seasonal_sounds", "rpspellbook_seasonal_music" }) do
            local retired = value.configuration[key]
            if retired ~= nil and type(retired) ~= "boolean" then return false end
            value.configuration[key] = nil
        end
        if value.configuration.rpspellbook_effect_bar_locked == nil then
            value.configuration.rpspellbook_effect_bar_locked = false
        end
        if value.configuration.rpspellbook_update_notifications == nil then
            value.configuration.rpspellbook_update_notifications = true
        end
        for key, item in pairs(value.configuration) do if not validPreference(key, item) then return false end end
        for _, key in ipairs(configKeys) do if value.configuration[key] == nil then return false end end
    end
    return true
end

local function encode(value)
    local ok, valid = pcall(validate, value)
    if not ok or not valid then return nil, "BACKUP_INVALID" end
    local payload = addon.PortableTable.Encode(value, validation.Limits)
    if not payload then return nil, "BACKUP_LIMIT" end
    return PREFIX .. payload
end

function backup.Export(scope)
    scope = scope or "full"
    if scope ~= "full" and scope ~= "core" and scope ~= "settings" and scope ~= "npc" then return nil, "BACKUP_INVALID" end
    if (scope == "full" or scope == "npc") and not npcAvailable() then return nil, "BACKUP_NPC_UNAVAILABLE" end
    local value = { format = "spellbook-backup", version = 1, scope = scope }
    if scope ~= "npc" then
        value.configuration = preferences()
        if not value.configuration then return nil, "BACKUP_CONFIG_UNAVAILABLE" end
    end
    if scope == "core" or scope == "full" then
        value.core = coreCopy()
        if not value.core then return nil, "BACKUP_LIMIT" end
    elseif scope == "settings" then
        value.settings = validation.Clone(_G.TRP3_RPSpellbookDB and _G.TRP3_RPSpellbookDB.settings)
        if not value.settings then return nil, "BACKUP_INVALID" end
    end
    if scope == "full" or scope == "npc" then
        value.npc = validation.Clone(_G.TRP3_RPSpellbookNPCDB)
        if not value.npc then return nil, "BACKUP_LIMIT" end
    end
    local output, err = encode(value)
    if not output then return nil, err end
    return output, scope == "core" and "BACKUP_CORE_ONLY" or scope == "settings" and "BACKUP_SETTINGS_ONLY" or nil
end

function backup.Prepare(input, sourceProfile, destinationProfile)
    if type(input) ~= "string" or #input > backup.MAX_BYTES or input:sub(1, #PREFIX) ~= PREFIX then return nil, "BACKUP_INVALID" end
    local value = addon.PortableTable.Decode(input:sub(#PREFIX + 1), validation.Limits)
    local ok, valid = pcall(validate, value)
    if not ok or not valid then return nil, "BACKUP_INVALID" end
    if value.npc and not npcAvailable() then return nil, "BACKUP_NPC_UNAVAILABLE" end
    if sourceProfile ~= nil and (not value.core or not validation.Rebind(value.core, sourceProfile, destinationProfile)) then
        return nil, "BACKUP_BINDING_INVALID"
    end
    local canonical, err = encode(value)
    if not canonical then return nil, err end
    local plan = { scope = value.scope, sourceProfile = sourceProfile, destinationProfile = destinationProfile }
    plans[plan] = canonical
    return plan
end

local function safeRestore()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, combat = pcall(InCombatLockdown)
    if not ok or combat ~= false then return false end
    local service = addon.GameMasterService
    for _, method in ipairs({ "IsSessionActive", "IsTestMode", "IsTutorialActive" }) do
        if service and type(service[method]) == "function" then
            local success, active = pcall(service[method])
            if not success or active then return false end
        end
    end
    if addon.Onboarding and type(addon.Onboarding.GetActive) == "function" then
        local success, active = pcall(addon.Onboarding.GetActive)
        if not success or active then return false end
    end
    return true
end

function backup.Stage(plan, confirmed)
    local input = plans[plan]
    if confirmed ~= true or not input then return false, "BACKUP_CONFIRM_REQUIRED" end
    if not safeRestore() then return false, "BACKUP_BUSY" end
    local root = _G.TRP3_RPSpellbookDB
    if type(root) ~= "table" or root.backupControl ~= nil and type(root.backupControl) ~= "table" then
        return false, "BACKUP_INVALID"
    end
    if root.backupControl and root.backupControl.pending then return false, "BACKUP_PENDING" end
    local checked, err = backup.Prepare(input)
    if not checked then return false, err end
    local recovery, recoveryError = backup.Export(checked.scope)
    if not recovery then return false, recoveryError end
     
    root.backupControl = { pending = input, recovery = recovery }
    plans[plan] = nil
    return true, "BACKUP_STAGED"
end

function backup.GetRecovery()
    local root = _G.TRP3_RPSpellbookDB
    local control = type(root) == "table" and root.backupControl
    return type(control) == "table" and control.recovery or nil
end

function backup.CancelPending()
    local root = _G.TRP3_RPSpellbookDB
    local control = type(root) == "table" and root.backupControl
    if type(control) ~= "table" or applying then return false end
    control.pending = nil
    return true
end

function backup.CanReload()
    local root = _G.TRP3_RPSpellbookDB
    local control = type(root) == "table" and root.backupControl
    if type(control) ~= "table" or not control.pending then return false, "BACKUP_CHECK_REQUIRED" end
    if not safeRestore() then return false, "BACKUP_BUSY" end
    return true
end

function backup.IsWaiting() return waiting end

local function deferStartup()
    if waiting then return true, "deferred" end
    if not C_Timer or type(C_Timer.After) ~= "function" then return false, "BACKUP_CONFIG_UNAVAILABLE" end
    waiting = true
    local ok, registered = pcall(addon.TRP3Integration.InitializeToolbarForBackup, function(success)
        if not success then
            waiting = false
            addon.Logger.Error(addon.L("BACKUP_STARTUP_FAILED", addon.L("BACKUP_CONFIG_UNAVAILABLE")))
            return
        end
         
         
        C_Timer.After(0, function()
            waiting = false
            if not preferences() then
                addon.Logger.Error(addon.L("BACKUP_STARTUP_FAILED", addon.L("BACKUP_CONFIG_UNAVAILABLE"))); return
            end
            local appliedOK, appliedError = backup.ApplyStartup()
            if not appliedOK then
                addon.Logger.Error(addon.L("BACKUP_STARTUP_FAILED", addon.L(appliedError))); return
            end
            local initialized = addon.Core.InitializeFallback()
            if initialized then
                addon.TRP3Integration.InitializeAfterBackup()
                addon.Core.OnModuleStart()
            end
        end)
    end)
    if not ok or not registered then waiting = false; return false, "BACKUP_CONFIG_UNAVAILABLE" end
    return true, "deferred"
end

local function archiveAuthority(root)
    local gm = root.gameMaster
    local archive = { runtimeStates = gm.runtimeStates, activeSessionID = gm.activeSessionID, sessions = {}, transfers = {} }
    gm.runtimeStates, gm.activeSessionID = {}, nil
    for sessionID, session in pairs(gm.sessions or {}) do
        if session.runningActivationID then
            archive.sessions[sessionID] = session.runningActivationID
            session.runningActivationID = nil
        end
    end
    for profileKey, profile in pairs(root.profiles) do
        local effects = profile.timedEffects
        if effects and effects.transfers then
            archive.transfers[profileKey], effects.transfers = effects.transfers, {}
        end
    end
    return archive
end

 
function backup.ApplyStartup()
    local root = _G.TRP3_RPSpellbookDB
    local control = type(root) == "table" and root.backupControl
    if type(control) ~= "table" or not control.pending then return true end
    if applying or applied or addon.Core and (addon.Core.initialized or addon.Core.enabled)
        or addon.Modules and addon.Modules.IsReady() then return false, "BACKUP_STARTUP_ONLY" end
    if not safeRestore() then return false, "BACKUP_BUSY" end
    local plan, err = backup.Prepare(control.pending)
    if not plan then return false, err end
    local value = addon.PortableTable.Decode(plans[plan]:sub(#PREFIX + 1), validation.Limits)
    if value.configuration and not preferences() then return deferStartup() end
     
    local recovery, recoveryError = backup.Export(value.scope)
    if not recovery then return false, recoveryError end
    local nextRoot = value.core or coreCopy()
    if not nextRoot then return false, "BACKUP_LIMIT" end
    if value.settings then nextRoot.settings = value.settings end
    local authority = value.core and archiveAuthority(nextRoot) or nil
    if authority then
        if nextRoot.backupArchives ~= nil and not validation.Array(nextRoot.backupArchives) then return false, "BACKUP_INVALID" end
        nextRoot.backupArchives = nextRoot.backupArchives or {}
        nextRoot.backupArchives[#nextRoot.backupArchives + 1] = authority
    end
     
     
    if not validation.Clone(nextRoot) then return false, "BACKUP_LIMIT" end
    local restoredNPC = value.npc and validation.Clone(value.npc)
    if value.npc and not restoredNPC then return false, "BACKUP_LIMIT" end
    local api, before, touched = config(), {}, {}
    local oldNPC = _G.TRP3_RPSpellbookNPCDB
    applying = true
    local function fail(message)
        _G.TRP3_RPSpellbookDB, _G.TRP3_RPSpellbookNPCDB = root, oldNPC
        local rollbackOK = true
        for index = #touched, 1, -1 do
            local key = touched[index]
             
            pcall(api.setValue, key, before[key])
        end
         
        for _, key in ipairs(touched) do
            local ok, actual = pcall(api.getValue, key)
            if not ok or actual ~= before[key] then rollbackOK = false end
        end
        applying = false
        return false, rollbackOK and message or "BACKUP_ROLLBACK_FAILED"
    end
    if value.configuration then
        if type(api) ~= "table" or type(api.getValue) ~= "function" or type(api.setValue) ~= "function" then
            return fail("BACKUP_CONFIG_UNAVAILABLE")
        end
        for _, key in ipairs(configKeys) do
            local ok, current = pcall(api.getValue, key)
            if not ok or not validPreference(key, current) then return fail("BACKUP_CONFIG_UNAVAILABLE") end
            before[key] = current
        end
         
         
        for _, key in ipairs(configKeys) do touched[#touched + 1] = key end
        _G.TRP3_RPSpellbookDB = nextRoot
        if value.npc then _G.TRP3_RPSpellbookNPCDB = value.npc end
        if value.core and addon.QuickAccess and type(addon.QuickAccess.Refresh) == "function" then
            local ok = pcall(addon.QuickAccess.Refresh)
            if not ok then return fail("BACKUP_CONFIG_FAILED") end
        end
        for _, key in ipairs(configKeys) do
            local ok = pcall(api.setValue, key, value.configuration[key])
            local readOK, actual = pcall(api.getValue, key)
            if not ok or not readOK or actual ~= value.configuration[key] then return fail("BACKUP_CONFIG_FAILED") end
        end
        for _, key in ipairs(configKeys) do
            local ok, actual = pcall(api.getValue, key)
            if not ok or actual ~= value.configuration[key] then return fail("BACKUP_CONFIG_FAILED") end
        end
    end
    nextRoot.backupControl = { recovery = recovery, restored = true }
     
    _G.TRP3_RPSpellbookDB = nextRoot
    if value.npc then
        _G.TRP3_RPSpellbookNPCDB = value.npc
         
         
         
        addon.Modules.WhenReady(function()
            local live = _G.TRP3_RPSpellbookNPCDB
            for key in pairs(live) do live[key] = nil end
            for key, item in pairs(restoredNPC) do live[key] = item end
            local presets = addon.SpellCreationPresets
            if presets and presets.NormalizeSpell and type(live.book) == "table" then
                for _, spell in pairs(live.book.spells or {}) do presets.NormalizeSpell(spell) end
            end
        end)
    end
    applying, applied = false, true
    return true
end
