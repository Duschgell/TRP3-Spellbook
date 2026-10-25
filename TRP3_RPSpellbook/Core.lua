local _, addon = ...

addon.Core = {
    enabled = false,
    initialized = false,
    initializing = false,
    moduleRegistered = false,
}

local function getProfileLabel()
    local profileName = addon.TRP3Bridge.GetActiveProfileName()
    if not profileName then
        return addon.L("PROFILE_PREFIX") .. addon.L("UNKNOWN")
    end
    return addon.L("PROFILE_PREFIX") .. profileName
end

local function initializeChatHyperlinks()
    local callSuccess, nativeSuccess, nativeError = addon.Runtime.SafeInvoke(
        addon.TRP3Bridge.InitializeSpellChatLinks
    )
    if not callSuccess then
        addon.Logger.Error(tostring(nativeSuccess))
    elseif not nativeSuccess then
        addon.Logger.Error(nativeError or addon.L("CHAT_LINK_API_UNAVAILABLE"))
    end

    callSuccess, nativeSuccess, nativeError = addon.Runtime.SafeInvoke(
        addon.ChatHyperlinks.Initialize
    )
    if not callSuccess then
        addon.Logger.Error(tostring(nativeSuccess))
    elseif not nativeSuccess then
        addon.Logger.Error(nativeError or addon.L("CHAT_LINK_API_UNAVAILABLE"))
    end
end

local function openSpellbook()
    if not addon.Core.enabled then
        addon.Logger.Error(addon.L("ADDON_DISABLED"))
        return
    end

    if addon.TRP3Integration.Open() then
        return
    end

    local spellbook = addon.Database.GetActiveSpellbook()
    if not spellbook then
        addon.Logger.Error(addon.L("ACTIVE_PROFILE_UNAVAILABLE"))
        return
    end
    addon.SpellbookWindow.Open(spellbook, getProfileLabel())
end
addon.Core.OpenSpellbook = openSpellbook

function addon.Core.OpenNPCArchive()
    if addon.Modules and not addon.Modules.Require("npc") then return false end
    if not addon.NPCArchive then return false end
    local ok, err = addon.NPCArchive.Open()
    if not ok then addon.Logger.Error(err or addon.L("ADDON_DISABLED")) end
    return ok == true
end

function addon.Core.CaptureNPCTarget()
    if not addon.Core.enabled then
        addon.Logger.Error(addon.L("ADDON_DISABLED"))
        return false
    end
    if addon.Modules and not addon.Modules.Require("npc") then return false end
    local archive = addon.NPCArchive
    if not archive or type(archive.CaptureTarget) ~= "function" then return false end
    local npcID, err = archive.CaptureTarget()
    if not npcID then
        addon.Logger.Error(archive.L and archive.L(err or "TARGET") or addon.L("NPC_CAPTURE_FAILED"))
        return false
    end
    local profile = type(archive.Get) == "function" and archive.Get(npcID)
    if addon.Onboarding and addon.Onboarding.RecordAction then addon.Onboarding.RecordAction("npcCaptured", npcID) end
    addon.Logger.Info(addon.L("NPC_CAPTURED", profile and profile.name or tostring(npcID)))
    return true
end

local function handleSlashCommand(message)
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
    if command == "backup" and addon.BackupWindow then
        addon.BackupWindow.Open()
        return
    end
    if not addon.Core.enabled then
        addon.Logger.Error(addon.L("ADDON_DISABLED"))
        return
    end
    if command == "effects" or command == "buffs" then
        addon.TimedEffectsView.Open()
        return
    end
    if command == "gm" or command == "gamemaster" then
        addon.GameMasterService.OpenControl()
        return
    end
    if command == "compact" or command == "quick" then
        addon.GameMasterCompactSpellbook.Open()
        return
    end
    if command == "test" or command == "debug" then
        if addon.Modules and not addon.Modules.Require("gameMaster") then return end
        addon.GameMasterTestDialog.Open()
        return
    end
    if command == "npc" then
        addon.Core.OpenNPCArchive()
        return
    end
    openSpellbook()
end

local function registerSlashCommand()
    if type(_G.SlashCmdList) ~= "table" then
        _G.SlashCmdList = {}
    end
    if _G.SlashCmdList.TRP3RPSPELLBOOK then
        return
    end
    _G.SLASH_TRP3RPSPELLBOOK1 = addon.Constants.SLASH_COMMAND
    _G.SLASH_TRP3RPSPELLBOOK2 = addon.Constants.SLASH_COMMAND_ALIAS
    _G.SlashCmdList.TRP3RPSPELLBOOK = handleSlashCommand
end

local function failInitialization(errorMessage)
    addon.Core.initializing = false
    return false, errorMessage
end

local function initializeCore()
    if addon.Core.initialized then
        return true
    end
    if addon.Core.initializing then
        return false, addon.L("ADDON_DISABLED")
    end

    addon.Core.initializing = true
    registerSlashCommand()
    if not addon.TRP3Bridge.IsAvailable() then
        return failInitialization(addon.L("ADDON_DISABLED"))
    end

    if addon.Backup then
        local ok, success, err = pcall(addon.Backup.ApplyStartup)
        if not ok or success ~= true then
            return failInitialization(addon.L("BACKUP_STARTUP_FAILED", addon.L(ok and err or "BACKUP_INVALID")))
        end
        if err == "deferred" then
            addon.Core.initializing = false
            return true
        end
    end

    local callSuccess, databaseSuccess, databaseError = addon.Runtime.SafeInvoke(
        addon.Database.Initialize
    )
    if not callSuccess then
        return failInitialization(tostring(databaseSuccess))
    end
    if databaseSuccess == false then
        return failInitialization(databaseError or addon.L("DATABASE_INVALID"))
    end

    local settingsCallSuccess, settingsSuccess, settingsError =
        addon.Runtime.SafeInvoke(addon.GameMasterSettings.Initialize)
    if not settingsCallSuccess then
        addon.Logger.Error(tostring(settingsSuccess))
    elseif not settingsSuccess then
        addon.Logger.Error(settingsError)
    end

    local layoutCallSuccess, layoutSuccess, layoutError =
        addon.Runtime.SafeInvoke(addon.GameMasterLayout.Initialize)
    if not layoutCallSuccess then
        addon.Logger.Error(tostring(layoutSuccess))
    elseif not layoutSuccess then
        addon.Logger.Error(layoutError)
    end

    if addon.VersionCheck then addon.VersionCheck.Initialize() end
    local communicationCallSuccess, communicationSuccess, communicationError =
        addon.Runtime.SafeInvoke(addon.Communication.Initialize)
    if not communicationCallSuccess then
        addon.Logger.Error(tostring(communicationSuccess))
    elseif not communicationSuccess then
        addon.Logger.Error(communicationError or addon.L("COMMUNICATION_UNAVAILABLE"))
    end

    local function initializeEncounters()
        local gameMasterCallSuccess, gameMasterSuccess, gameMasterError =
            addon.Runtime.SafeInvoke(addon.GameMasterService.Initialize)
        if not gameMasterCallSuccess then
            addon.Logger.Error(tostring(gameMasterSuccess))
        elseif not gameMasterSuccess then
            addon.Logger.Error(gameMasterError)
        end
    end
    if communicationCallSuccess and communicationSuccess then
        if addon.Modules then
            addon.Modules.WhenReady(initializeEncounters)
        else
            initializeEncounters()
        end
    end

    local fallbackCallSuccess, fallbackSuccess, fallbackError =
        addon.Runtime.SafeInvoke(addon.ChatFallbacks.Initialize)
    if not fallbackCallSuccess then
        addon.Logger.Error(tostring(fallbackSuccess))
    elseif not fallbackSuccess then
        addon.Logger.Error(
            fallbackError or addon.L("CHAT_FALLBACK_UNAVAILABLE")
        )
    end
    initializeChatHyperlinks()
    if addon.TimedEffects then addon.TimedEffects.Initialize() end
    if addon.EffectSharing then addon.EffectSharing.Initialize() end
    if addon.TimedEncounterEffects then addon.TimedEncounterEffects.Initialize() end
    addon.Core.enabled = true
    addon.Core.initialized = true
    addon.Core.initializing = false
    if addon.Modules then addon.Modules.CoreReady() end
    return true
end

function addon.Core.OnModuleInit()
    local success, errorMessage = initializeCore()
    if not success then
        addon.Logger.Error(errorMessage)
    end
    return success, errorMessage
end

function addon.Core.OnModuleStart()
    if addon.Backup and addon.Backup.IsWaiting() then return true end
    if not addon.Core.enabled then
        return false, addon.L("ADDON_DISABLED")
    end
     
     
    local callSuccess, success, errorMessage = addon.Runtime.SafeInvoke(
        addon.TRP3Integration.Initialize
    )
    if not callSuccess then
        addon.Logger.Error(tostring(success))
        return false, success
    end
    if not success then
        addon.Logger.Error(errorMessage)
        return false, errorMessage
    end

    if addon.Onboarding then addon.Onboarding.Initialize() end
    if addon.TimedEffectsView then addon.TimedEffectsView.Initialize() end
    if addon.ExtendedAuras then addon.ExtendedAuras.Initialize() end
    if addon.CurrentlyEffects then addon.CurrentlyEffects.Initialize() end
    if addon.CurrentlyEffectsEditor then addon.CurrentlyEffectsEditor.Initialize() end

    local tooltipCallSuccess, tooltipSuccess, tooltipError = addon.Runtime.SafeInvoke(
        addon.PlayerTooltip.Initialize
    )
    if not tooltipCallSuccess then
        addon.Logger.Error(tostring(tooltipSuccess))
    elseif not tooltipSuccess then
        addon.Logger.Error(tooltipError or addon.L("TRP3_API_UNAVAILABLE", "character tooltip"))
    end
    return true
end

function addon.Core.InitializeFallback()
    local success, errorMessage = initializeCore()
    if not success then
        addon.Logger.Error(errorMessage)
    end
    return success, errorMessage
end

addon.Core.Initialize = addon.Core.OnModuleInit

 
registerSlashCommand()

local moduleSuccess, moduleError = addon.TRP3Bridge.RegisterModule({
    id = addon.Constants.MODULE_ID,
    name = addon.L("ADDON_TITLE"),
    description = addon.L("ADDON_DESCRIPTION"),
    version = addon.Constants.MODULE_VERSION,
    minVersion = addon.Constants.MINIMUM_TRP3_VERSION,
    onInit = addon.Core.OnModuleInit,
    onStart = addon.Core.OnModuleStart,
})
addon.Core.moduleRegistered = moduleSuccess
if not moduleSuccess then
    addon.Logger.Error(addon.L("MODULE_REGISTER_FAILED", tostring(moduleError)))
end

addon.Events.Initialize()
