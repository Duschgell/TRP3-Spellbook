local _, addon = ...

addon.GameMasterSettings = {
    initialized = false,
    pageRegistered = false,
}

local listeners = {}
local defaults = {
    opacity = 95,
    fontSize = 12,
    history = addon.Constants.GAMEMASTER_DEFAULT_HISTORY,
    style = "modern",
    confirmClose = true,
    nameMode = "trp_full",
    profileColors = true,
    profileIcons = true,
    compactOpacity = 92,
    compactFontSize = 12,
    compactStyle = "modern",
    feedbackChat = false,
    feedbackScreen = true,
    feedbackSound = false,
    defaultVisibility = "hidden",
    autoSpellFallback = false,
    gameMasterChatFallback = true,
}

local function getConfiguration()
    local api = _G.TRP3_API
    local configuration = type(api) == "table" and api.configuration or nil
    return type(configuration) == "table" and configuration or nil
end

local function notifyListeners()
    for _, listener in ipairs(listeners) do
        local success, errorMessage = addon.Runtime.SafeInvoke(listener)
        if not success then
            addon.Logger.Error(tostring(errorMessage))
        end
    end
end

local function registerKey(configuration, key, defaultValue)
    if type(configuration.registerConfigKey) ~= "function" then
        return false
    end
    local success = pcall(
        configuration.registerConfigKey,
        key,
        defaultValue
    )
    return success
end

local function getNumber(key, fallback, minimum, maximum)
    local configuration = getConfiguration()
    local value = fallback
    if configuration and type(configuration.getValue) == "function" then
        local success, result = pcall(configuration.getValue, key)
        local candidate = success and tonumber(result) or nil
        if candidate
            and candidate == candidate
            and candidate ~= math.huge
            and candidate ~= -math.huge
        then
            value = candidate
        end
    end
    return math.max(minimum, math.min(maximum, value))
end

local function getBoolean(key, fallback)
    local configuration = getConfiguration()
    if configuration and type(configuration.getValue) == "function" then
        local success, value = pcall(configuration.getValue, key)
        if success and type(value) == "boolean" then
            return value
        end
    end
    return fallback == true
end

local function getString(key, fallback, allowed)
    local configuration = getConfiguration()
    if configuration and type(configuration.getValue) == "function" then
        local success, value = pcall(configuration.getValue, key)
        if success
            and type(value) == "string"
            and (not allowed or allowed[value])
        then
            return value
        end
    end
    return fallback
end

function addon.GameMasterSettings.Initialize()
    if addon.GameMasterSettings.initialized then
        return true
    end

    local configuration = getConfiguration()
    if not configuration then
        return false, addon.L("TRP3_API_UNAVAILABLE", "configuration")
    end

    local constants = addon.Constants
    local settings = {
        {
            key = constants.GAMEMASTER_SETTING_OPACITY,
            value = defaults.opacity,
        },
        {
            key = constants.GAMEMASTER_SETTING_FONT_SIZE,
            value = defaults.fontSize,
        },
        {
            key = constants.GAMEMASTER_SETTING_HISTORY,
            value = defaults.history,
        },
        {
            key = constants.GAMEMASTER_SETTING_STYLE,
            value = defaults.style,
        },
        {
            key = constants.GAMEMASTER_SETTING_CONFIRM_CLOSE,
            value = defaults.confirmClose,
        },
        {
            key = constants.GAMEMASTER_SETTING_NAME_MODE,
            value = defaults.nameMode,
        },
        {
            key = constants.GAMEMASTER_SETTING_PROFILE_COLORS,
            value = defaults.profileColors,
        },
        {
            key = constants.GAMEMASTER_SETTING_PROFILE_ICONS,
            value = defaults.profileIcons,
        },
        {
            key = constants.GAMEMASTER_SETTING_COMPACT_OPACITY,
            value = defaults.compactOpacity,
        },
        {
            key = constants.GAMEMASTER_SETTING_COMPACT_FONT_SIZE,
            value = defaults.compactFontSize,
        },
        {
            key = constants.GAMEMASTER_SETTING_COMPACT_STYLE,
            value = defaults.compactStyle,
        },
        {
            key = constants.GAMEMASTER_SETTING_FEEDBACK_CHAT,
            value = defaults.feedbackChat,
        },
        {
            key = constants.GAMEMASTER_SETTING_FEEDBACK_SCREEN,
            value = defaults.feedbackScreen,
        },
        {
            key = constants.GAMEMASTER_SETTING_FEEDBACK_SOUND,
            value = defaults.feedbackSound,
        },
        {
            key = constants.CHAT_FALLBACK_SETTING_AUTO_SPELL,
            value = defaults.autoSpellFallback,
        },
        {
            key = constants.GAMEMASTER_SETTING_CHAT_FALLBACK,
            value = defaults.gameMasterChatFallback,
        },
        {
            key = constants.GAMEMASTER_SETTING_DEFAULT_VISIBILITY,
            value = defaults.defaultVisibility,
        },
    }

    local keys = {}
    for _, setting in ipairs(settings) do
        if not registerKey(
            configuration,
            setting.key,
            setting.value
        ) then
            return false, addon.L(
                "TRP3_API_UNAVAILABLE",
                "registerConfigKey"
            )
        end
        keys[#keys + 1] = setting.key
    end

    if type(configuration.registerHandler) == "function" then
        pcall(configuration.registerHandler, keys, notifyListeners)
    end
    addon.GameMasterSettings.initialized = true
    return true
end

function addon.GameMasterSettings.RestoreRoundWindows()
    if not addon.GameMasterService.IsSessionActive() then
        addon.Logger.Error(addon.L("GAMEMASTER_WINDOWS_RESTORE_NONE"))
        return false
    end

    local windows = {}
    if addon.GameMasterService.IsActiveGameMaster() then
        windows[#windows + 1] = addon.GameMasterWindow or false
    end
    windows[#windows + 1] = addon.GameMasterSharedActions or false
    windows[#windows + 1] = addon.GameMasterCompactSpellbook or false
    windows[#windows + 1] = addon.GameMasterActionStatus or false
    local restored, failed = 0, false
    for _, module in ipairs(windows) do
        local ok, opened = false, false
        if module and type(module.Open) == "function" then
            ok, opened = pcall(module.Open, true)
        end
        if ok and opened == true then restored = restored + 1 else failed = true end
    end
    if failed then
        addon.Logger.Error(addon.L(restored > 0 and "GAMEMASTER_WINDOWS_RESTORE_PARTIAL"
            or "GAMEMASTER_WINDOWS_RESTORE_NONE"))
    end
    return not failed
end

local function chooseNotificationSound(incoming)
    local state = addon.GameMasterPlayerState
    local database = addon.Database.GetDB()
    if not database then return end
    local getter = incoming and state.GetIncomingActionSoundPreset or state.GetTurnSoundPreset
    local setter = incoming and state.SetIncomingActionSoundPreset or state.SetTurnSoundPreset
    addon.SoundBrowser.Open(getter(), setter, {
        owner = "settings",
        isValid = function() return addon.Database.GetDB() == database end,
    })
end

local function fitSettingsButton(button)
    local row = button:GetParent()
    local label = button:GetFontString()
    local width = math.min(math.max(150, math.ceil(label:GetUnboundedStringWidth()) + 24),
        math.max(1, row:GetWidth() * 0.55))
    button:SetWidth(width)
    label:SetWidth(math.max(1, width - 24))
    label:SetWordWrap(true)
    label:SetNonSpaceWrap(true)
    local height = math.max(22, math.ceil(label:GetStringHeight()) + 8)
    button:SetHeight(height)
    row:SetHeight(math.max(35, height + 8))
     
    row.Title:SetPoint("RIGHT", button, "LEFT", -16, 0)
end

local function showSettingsButton(button)
    local row = button:GetParent()
    if not button.spellbookAdaptiveWidth then
        button.spellbookAdaptiveWidth = true
        row:HookScript("OnSizeChanged", function() fitSettingsButton(button) end)
    end
    fitSettingsButton(button)
end

local function initializeSettingsButton(row)
     
    showSettingsButton(row.Button)
end

local function getPageElements(constants)
    local elements = {
        {
            inherit = "TRP3_ConfigParagraph",
            title = addon.L("GAMEMASTER_SETTINGS_DESCRIPTION"),
        },
        {
            inherit = "TRP3_ConfigH1",
            title = addon.L("GAMEMASTER_TEST_SETTINGS_HEADER"),
            optionalModule = "gameMaster",
        },
        {
            inherit = "TRP3_ConfigButton",
            title = addon.L("GAMEMASTER_TEST_TITLE"),
            optionalModule = "gameMaster",
            help = addon.L("GAMEMASTER_TEST_SETTINGS_HELP"),
            text = addon.L("GAMEMASTER_TEST_OPEN"),
            callback = function()
                addon.GameMasterTestDialog.Open()
            end,
        },
        {
            inherit = "TRP3_ConfigH1",
            title = addon.L("LAYOUT_SETTINGS_HEADER"),
        },
        {
            inherit = "TRP3_ConfigButton",
            title = addon.L("LAYOUT_EDIT_MODE"),
            help = addon.L("LAYOUT_EDIT_MODE_HELP"),
            text = addon.L("LAYOUT_EDIT_MODE"),
            OnShow = showSettingsButton,
            elementInitializer = initializeSettingsButton,
            elementData = true,
            callback = function()
                addon.GameMasterLayoutEditor.Open()
            end,
        },
        {
            inherit = "TRP3_ConfigH1",
            title = addon.L("CHAT_FALLBACK_SETTINGS_HEADER"),
        },
        {
            inherit = "TRP3_ConfigCheck",
            title = addon.L("CHAT_FALLBACK_AUTO_SPELL"),
            help = addon.L("CHAT_FALLBACK_AUTO_SPELL_HELP"),
            configKey =
                constants.CHAT_FALLBACK_SETTING_AUTO_SPELL,
        },
        {
            inherit = "TRP3_ConfigH1",
            title = addon.L("GAMEMASTER_SETTINGS_HEADER"),
            optionalModule = "gameMaster",
        },
        {
            inherit = "TRP3_ConfigButton",
            title = addon.L("GAMEMASTER_CONTROL"),
            optionalModule = "gameMaster",
            text = addon.L("GAMEMASTER_CONTROL_OPEN"),
            OnShow = showSettingsButton,
            elementInitializer = initializeSettingsButton,
            elementData = true,
            callback = function() addon.GameMasterService.OpenControl() end,
        },
        {
            inherit = "TRP3_ConfigButton",
            title = addon.L("GAMEMASTER_WINDOWS_RESTORE"),
            help = addon.L("GAMEMASTER_WINDOWS_RESTORE_HELP"),
            text = addon.L("GAMEMASTER_WINDOWS_RESTORE"),
            OnShow = showSettingsButton,
            elementInitializer = initializeSettingsButton,
            elementData = true,
            callback = addon.GameMasterSettings.RestoreRoundWindows,
        },
        {
            inherit = "TRP3_ConfigH1",
            title = addon.L("GAMEMASTER_FEEDBACK_SETTINGS_HEADER"),
        },
        {
            inherit = "TRP3_ConfigButton",
            title = addon.L("SOUND_SETTINGS_TURN"),
            help = addon.L("SOUND_SETTINGS_TURN_HELP"),
            text = addon.L("SOUND_BROWSER_OPEN"),
            callback = function() chooseNotificationSound(false) end,
        },
        {
            inherit = "TRP3_ConfigButton",
            title = addon.L("SOUND_SETTINGS_INCOMING"),
            help = addon.L("SOUND_SETTINGS_INCOMING_HELP"),
            text = addon.L("SOUND_BROWSER_OPEN"),
            callback = function() chooseNotificationSound(true) end,
        },
        {
            inherit = "TRP3_ConfigCheck",
            title = addon.L("GAMEMASTER_FEEDBACK_SCREEN"),
            help = addon.L("GAMEMASTER_FEEDBACK_SCREEN_HELP"),
            configKey = constants.GAMEMASTER_SETTING_FEEDBACK_SCREEN,
        },
        {
            inherit = "TRP3_ConfigCheck",
            title = addon.L("GAMEMASTER_FEEDBACK_CHAT"),
            help = addon.L("GAMEMASTER_FEEDBACK_CHAT_HELP"),
            configKey = constants.GAMEMASTER_SETTING_FEEDBACK_CHAT,
        },
        {
            inherit = "TRP3_ConfigCheck",
            title = addon.L("GAMEMASTER_FEEDBACK_SOUND"),
            help = addon.L("GAMEMASTER_FEEDBACK_SOUND_HELP"),
            configKey = constants.GAMEMASTER_SETTING_FEEDBACK_SOUND,
        },
        {
            inherit = "TRP3_ConfigCheck",
            title = addon.L("GAMEMASTER_CHAT_FALLBACK"),
            help = addon.L("GAMEMASTER_CHAT_FALLBACK_HELP"),
            configKey =
                constants.GAMEMASTER_SETTING_CHAT_FALLBACK,
        },
        {
            inherit = "TRP3_ConfigH1",
            title = addon.L("GAMEMASTER_VISIBILITY_SETTINGS_HEADER"),
            optionalModule = "gameMaster",
        },
        {
            inherit = "TRP3_ConfigDropDown",
            title = addon.L("GAMEMASTER_SETTING_DEFAULT_VISIBILITY"),
            optionalModule = "gameMaster",
            help = addon.L("GAMEMASTER_SETTING_DEFAULT_VISIBILITY_HELP"),
            configKey = constants.GAMEMASTER_SETTING_DEFAULT_VISIBILITY,
            listContent = {
                {
                    addon.L("GAMEMASTER_VISIBILITY_FULL"),
                    "full",
                },
                {
                    addon.L("GAMEMASTER_VISIBILITY_TARGETS"),
                    "targets",
                },
                {
                    addon.L("GAMEMASTER_VISIBILITY_HIDDEN"),
                    "hidden",
                },
            },
        },
        {
            inherit = "TRP3_ConfigH1",
            title = addon.L("GAMEMASTER_HISTORY_SETTINGS_HEADER"),
            optionalModule = "gameMaster",
        },
        {
            inherit = "TRP3_ConfigSlider",
            title = addon.L("GAMEMASTER_SETTING_HISTORY"),
            optionalModule = "gameMaster",
            help = addon.L("GAMEMASTER_SETTING_HISTORY_HELP"),
            configKey = constants.GAMEMASTER_SETTING_HISTORY,
            min = 2,
            max = constants.GAMEMASTER_MAX_HISTORY,
            step = 1,
            integer = true,
        },
        {
            inherit = "TRP3_ConfigButton",
            title = addon.L("GAMEMASTER_HISTORY_SETTINGS_TITLE"),
            optionalModule = "gameMaster",
            help = addon.L("GAMEMASTER_HISTORY_SETTINGS_HELP"),
            text = addon.L("GAMEMASTER_HISTORY_OPEN"),
            callback = function()
                addon.GameMasterHistoryWindow.Open()
            end,
        },
    }

    local creationElements =
        addon.SpellCreationSettings.GetPageElements()
    for index = #creationElements, 1, -1 do
        table.insert(elements, 6, creationElements[index])
    end
    local onboardingElements = addon.Onboarding
        and addon.Onboarding.GetSettingsElements()
        or {}
    for index = #onboardingElements, 1, -1 do
        table.insert(elements, 2, onboardingElements[index])
    end
    local visible = {}
    for _, element in ipairs(elements) do
        if not element.optionalModule or not addon.Modules
            or addon.Modules.IsEnabled(element.optionalModule) then
            element.optionalModule = nil
            visible[#visible + 1] = element
        end
    end
    if addon.Modules and addon.Modules.IsEnabled("npc") then
        visible[#visible + 1] = {
            inherit = "TRP3_ConfigButton",
            title = addon.L("NPC_ARCHIVE_ENTRY"),
            text = addon.L("NPC_ARCHIVE_ENTRY"),
            help = addon.L("NPC_ARCHIVE_ENTRY_HELP"),
            callback = function() addon.Core.OpenNPCArchive() end,
        }
    end
    if addon.BackupWindow then
        visible[#visible + 1] = {
            inherit = "TRP3_ConfigButton",
            title = addon.L("BACKUP_TITLE"),
            text = addon.L("BACKUP_OPEN"),
            help = addon.L("BACKUP_GUIDANCE"),
            callback = function() addon.BackupWindow.Open() end,
        }
    end
    for _, element in ipairs(visible) do
        if element.inherit == "TRP3_ConfigButton" and not element.OnShow
            and not element.elementInitializer then
            element.OnShow = showSettingsButton
            element.elementInitializer = initializeSettingsButton
            element.elementData = true
        end
    end
    return visible
end

function addon.GameMasterSettings.GetPageElements()
    return getPageElements(addon.Constants)
end

function addon.GameMasterSettings.GetBookToolbarIcon()
    local icon = addon.Database.GetSpellbookIcon()
    if type(icon) == "string" then
        local numeric = tonumber(icon)
        if numeric then
            icon = numeric
        else
            local _, prefix = icon:lower():find("^interface[\\/]icons[\\/]")
            if prefix then icon = icon:sub(prefix + 1) end
            if icon:match("^[%w_%-]+$") then return icon end
        end
    end
    if type(icon) == "number" and icon > 0 and icon < math.huge and icon % 1 == 0 then return icon end
    return addon.Constants.DEFAULT_TRP3_TOOLBAR_ICON
end

function addon.GameMasterSettings.RefreshBookIcon()
    local button = addon.GameMasterSettings.bookIconButton
    if not button then return end
    local icon = addon.Database.GetSpellbookIcon()
    if button.bookIconValue ~= icon then
        addon.UIFactory.SetIconTexture(button.iconTexture, icon, addon.Constants.DEFAULT_BOOK_ICON)
        button.bookIconValue = icon
    end
end

local function initializeBookIcon(frame)
    if not frame or not frame.Title then return end
    local button = addon.UIFactory.CreateIconButton(frame)
    button:SetSize(32, 32)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.Title:ClearAllPoints()
    frame.Title:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, -20)
    frame.Title:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    if frame.Divider then frame.Divider:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", -42, -16) end
    addon.GameMasterSettings.bookIconButton = button
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addon.L("BOOK_ICON_CHANGE"))
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        local book = addon.Database.GetActiveSpellbook()
        if not book then return end
        local request = {}
        self.iconRequest = request
        local success, err = addon.TRP3Bridge.OpenIconBrowser(book.icon, function(icon, info)
            if self.iconRequest ~= request or not frame:IsShown()
                or addon.Database.GetActiveSpellbook() ~= book then return end
            self.iconRequest = nil
            local accepted, message = addon.Database.SetSpellbookIcon(type(info) == "table" and info.file or icon)
            if not accepted then addon.Logger.Error(message); return end
            addon.GameMasterSettings.RefreshBookIcon()
            if addon.TRP3Integration then addon.TRP3Integration.RefreshBookIcon() end
        end, function()
            if self.iconRequest == request then self.iconRequest = nil end
        end, frame)
        if not success then self.iconRequest = nil; addon.Logger.Error(err) end
    end)
    frame:HookScript("OnShow", addon.GameMasterSettings.RefreshBookIcon)
    frame:HookScript("OnHide", function() button.iconRequest = nil end)
    addon.GameMasterSettings.RefreshBookIcon()
end

function addon.GameMasterSettings.RegisterPage()
    if addon.GameMasterSettings.pageRegistered then
        return true
    end
    if not addon.GameMasterSettings.initialized then
        local initialized, errorMessage =
            addon.GameMasterSettings.Initialize()
        if not initialized then
            return false, errorMessage
        end
    end

    local configuration = getConfiguration()
    if not configuration
        or type(configuration.registerConfigurationPage) ~= "function"
    then
        return false, addon.L(
            "TRP3_API_UNAVAILABLE",
            "registerConfigurationPage"
        )
    end

    local constants = addon.Constants
    local page = {
        id = constants.GAMEMASTER_SETTINGS_PAGE_ID,
        menuText = addon.L("ADDON_TITLE"),
        pageText = addon.L("ADDON_TITLE"),
        elements = addon.GameMasterSettings.GetPageElements(),
    }
    local success, errorMessage = pcall(
        configuration.registerConfigurationPage,
        page
    )
    if not success then
        return false, errorMessage
    end
    addon.GameMasterSettings.pageRegistered = true
    initializeBookIcon(page.frame)
    if addon.BookNavigationStyle then addon.BookNavigationStyle.Initialize(page.frame) end
    return true
end

local function getLayoutModule(moduleID)
    return addon.GameMasterLayout
        and addon.GameMasterLayout.GetModule(moduleID)
        or nil
end

function addon.GameMasterSettings.GetWindowOpacity(moduleID, fallback)
    local module = getLayoutModule(moduleID)
    return module and module.opacity / 100 or fallback
end

function addon.GameMasterSettings.GetWindowFontSize(moduleID, fallback)
    local module = getLayoutModule(moduleID)
    return module and module.fontSize or fallback
end

function addon.GameMasterSettings.GetWindowStyle(moduleID, fallback)
    local module = getLayoutModule(moduleID)
    return module and module.style or fallback
end

function addon.GameMasterSettings.ShouldShowWindowBorder(moduleID)
    local module = getLayoutModule(moduleID)
    return not module or module.showBorder ~= false
end

function addon.GameMasterSettings.ShouldAutoOpenWindow(moduleID)
    local module = getLayoutModule(moduleID)
    return module and module.autoOpen == true or false
end

function addon.GameMasterSettings.GetWindowOption(moduleID, key, fallback)
    local module = getLayoutModule(moduleID)
    local value = module and module.options and module.options[key]
    return value == nil and fallback or value
end
function addon.GameMasterSettings.GetWindowMetrics(moduleID, frame, fallbackFontSize)
    local module = getLayoutModule(moduleID)
    if not module or not addon.GameMasterLayout then
        return nil
    end
    local layout = module.layout or {}
    local width = frame and type(frame.GetWidth) == "function"
        and tonumber(frame:GetWidth()) or tonumber(layout.width)
    local height = frame and type(frame.GetHeight) == "function"
        and tonumber(frame:GetHeight()) or tonumber(layout.height)
    return addon.GameMasterLayout.GetAdaptiveMetrics(
        moduleID,
        width,
        height,
        module.fontSize or fallbackFontSize,
        module.options,
        module.style
    )
end
function addon.GameMasterSettings.GetOpacity()
    return addon.GameMasterSettings.GetWindowOpacity(
        "gameMaster",
        getNumber(
            addon.Constants.GAMEMASTER_SETTING_OPACITY,
            defaults.opacity,
            35,
            100
        ) / 100
    )
end

function addon.GameMasterSettings.GetFontSize()
    return addon.GameMasterSettings.GetWindowFontSize(
        "gameMaster",
        math.floor(getNumber(
            addon.Constants.GAMEMASTER_SETTING_FONT_SIZE,
            defaults.fontSize,
            10,
            18
        ))
    )
end

function addon.GameMasterSettings.GetHistoryLimit()
    return math.floor(getNumber(
        addon.Constants.GAMEMASTER_SETTING_HISTORY,
        defaults.history,
        2,
        addon.Constants.GAMEMASTER_MAX_HISTORY
    ))
end

function addon.GameMasterSettings.GetStyle()
    return addon.GameMasterSettings.GetWindowStyle(
        "gameMaster",
        getString(
            addon.Constants.GAMEMASTER_SETTING_STYLE,
            defaults.style,
            { modern = true, minimal = true }
        )
    )
end

function addon.GameMasterSettings.ShouldConfirmClose()
    return getBoolean(
        addon.Constants.GAMEMASTER_SETTING_CONFIRM_CLOSE,
        defaults.confirmClose
    )
end

function addon.GameMasterSettings.GetNameMode()
    return addon.GameMasterSettings.GetWindowOption(
        "gameMaster",
        "nameMode",
        defaults.nameMode
    )
end

function addon.GameMasterSettings.ShouldUseProfileColors()
    return addon.GameMasterSettings.GetWindowOption(
        "gameMaster",
        "profileColors",
        defaults.profileColors
    ) == true
end

function addon.GameMasterSettings.ShouldShowProfileIcons()
    return addon.GameMasterSettings.GetWindowOption(
        "gameMaster",
        "profileIcons",
        defaults.profileIcons
    ) == true
end

function addon.GameMasterSettings.ShouldShowVersions()
    return addon.GameMasterSettings.GetWindowOption(
        "gameMaster",
        "showVersions",
        true
    ) == true
end

function addon.GameMasterSettings.GetCompactOpacity()
    return addon.GameMasterSettings.GetWindowOpacity(
        "compactSpellbook",
        getNumber(
            addon.Constants.GAMEMASTER_SETTING_COMPACT_OPACITY,
            defaults.compactOpacity,
            25,
            100
        ) / 100
    )
end

function addon.GameMasterSettings.GetCompactFontSize()
    return addon.GameMasterSettings.GetWindowFontSize(
        "compactSpellbook",
        math.floor(getNumber(
            addon.Constants.GAMEMASTER_SETTING_COMPACT_FONT_SIZE,
            defaults.compactFontSize,
            9,
            18
        ))
    )
end

function addon.GameMasterSettings.GetCompactStyle()
    return addon.GameMasterSettings.GetWindowStyle(
        "compactSpellbook",
        getString(
            addon.Constants.GAMEMASTER_SETTING_COMPACT_STYLE,
            defaults.compactStyle,
            { modern = true, minimal = true }
        )
    )
end

function addon.GameMasterSettings.ShouldShowCompactIcons()
    return addon.GameMasterSettings.GetWindowOption(
        "compactSpellbook", "showIcons", true
    ) == true
end

function addon.GameMasterSettings.ShouldShowSharedIcons()
    return addon.GameMasterSettings.GetWindowOption(
        "roundOverview", "showIcons", true
    ) == true
end

function addon.GameMasterSettings.ShouldUseSharedProfileColors()
    return addon.GameMasterSettings.GetWindowOption(
        "roundOverview", "profileColors", true
    ) == true
end

function addon.GameMasterSettings.ShouldShowActionIcon()
    return addon.GameMasterSettings.GetWindowOption(
        "currentAction", "showIcon", true
    ) == true
end

function addon.GameMasterSettings.ShouldAutoCompleteTurn()
    return addon.GameMasterSettings.GetWindowOption(
        "currentAction", "autoCompleteTurn", true
    ) == true
end

function addon.GameMasterSettings.ShouldNotifyOwnTurn()
    return addon.GameMasterSettings.GetWindowOption(
        "currentAction", "notifyTurn", true
    ) == true
end

function addon.GameMasterSettings.ShouldPlayOwnTurnSound()
    return addon.GameMasterSettings.GetWindowOption(
        "currentAction", "turnSound", false
    ) == true
end

function addon.GameMasterSettings.ShouldShowChatFeedback()
    return getBoolean(
        addon.Constants.GAMEMASTER_SETTING_FEEDBACK_CHAT,
        defaults.feedbackChat
    )
end

function addon.GameMasterSettings.ShouldShowScreenFeedback()
    return getBoolean(
        addon.Constants.GAMEMASTER_SETTING_FEEDBACK_SCREEN,
        defaults.feedbackScreen
    )
end

function addon.GameMasterSettings.ShouldPlayFeedbackSound()
    return getBoolean(
        addon.Constants.GAMEMASTER_SETTING_FEEDBACK_SOUND,
        defaults.feedbackSound
    )
end

function addon.GameMasterSettings.ShouldAutoWhisperSpellFallback()
    return getBoolean(
        addon.Constants.CHAT_FALLBACK_SETTING_AUTO_SPELL,
        defaults.autoSpellFallback
    )
end

function addon.GameMasterSettings.ShouldAnnounceGameMasterFallback()
    return getBoolean(
        addon.Constants.GAMEMASTER_SETTING_CHAT_FALLBACK,
        defaults.gameMasterChatFallback
    )
end


function addon.GameMasterSettings.GetDefaultVisibility()
    return getString(
        addon.Constants.GAMEMASTER_SETTING_DEFAULT_VISIBILITY,
        defaults.defaultVisibility,
        addon.Constants.GAMEMASTER_VISIBILITY_MODES
    )
end
function addon.GameMasterSettings.RegisterListener(listener)
    if type(listener) ~= "function" then
        return false
    end
    listeners[#listeners + 1] = listener
    return true
end

function addon.GameMasterSettings.Open()
    return addon.TRP3Bridge.OpenConfigurationPage(
        addon.Constants.GAMEMASTER_SETTINGS_PAGE_ID
    )
end
