local _, addon = ...

addon.TRP3Integration = {
    isRegistered = false,
    importedRegistered = false,
    toolbarRegistered = false,
}

local pageFrame
local importedPageFrame
local pendingImportID
local workflowRegistered = false
local backupToolbarRegistered = false
local npcPageFrame
local NPC_PAGE_ID = "rpspellbook_npc_register_page"
local NPC_MENU_ID = "rpspellbook_npc_archive"

local function routeBookClose(frame, visible)
    local main = _G.TRP3_MainFrame
    local button = main and main.CloseButton
    if not button or not button.GetScript or not button.SetScript then return end
    if visible and frame.panel and frame.panel.RequestClose then
        if button:GetScript("OnClick") == frame.bookCloseHandler then return end
        local original = button:GetScript("OnClick")
        frame.bookCloseOriginal = original
        frame.bookCloseHandler = function(self, mouseButton, down)
            local function close()
                if original then original(self, mouseButton, down) else main:Hide() end
            end
            if frame.panel.fancyPresentation and frame:IsShown() then
                frame.panel.RequestClose(close)
            else
                close()
            end
        end
        button:SetScript("OnClick", frame.bookCloseHandler)
    elseif button:GetScript("OnClick") == frame.bookCloseHandler then
        button:SetScript("OnClick", frame.bookCloseOriginal)
    end
end

local function keepMainCloseButtonVisible(frame, visible)
    local mainFrame = _G.TRP3_MainFrame
    local closeButton = mainFrame and mainFrame.CloseButton
    if not closeButton or type(closeButton.SetFrameLevel) ~= "function" then
        return
    end
    if visible then
        if frame.closeButtonOriginalLevel == nil
            and type(closeButton.GetFrameLevel) == "function"
        then
            local success, level = pcall(
                closeButton.GetFrameLevel, closeButton
            )
            if success then
                frame.closeButtonOriginalLevel = level
            end
        end
        local panelLevel = frame.panel
            and type(frame.panel.GetFrameLevel) == "function"
            and frame.panel:GetFrameLevel()
            or 1
        closeButton:SetFrameLevel(math.max(
            tonumber(frame.closeButtonOriginalLevel) or 1,
            panelLevel + 20
        ))
    elseif frame.closeButtonOriginalLevel ~= nil then
        closeButton:SetFrameLevel(frame.closeButtonOriginalLevel)
    end
end

local function getProfileLabel()
    local profileName = addon.TRP3Bridge.GetActiveProfileName()
    if not profileName then
        return addon.L("PROFILE_PREFIX") .. addon.L("UNKNOWN")
    end

    return addon.L("PROFILE_PREFIX") .. profileName
end

local function refreshPage()
    if not pageFrame or not pageFrame.panel then
        return
    end

    local spellbook = addon.Database.GetActiveSpellbook()
    addon.SpellbookPanel.Refresh(pageFrame.panel, spellbook, getProfileLabel())
end

local function createPageFrame()
    if pageFrame then
        return pageFrame
    end

    pageFrame = CreateFrame("Frame")
    pageFrame:Hide()
    pageFrame.panel = addon.SpellbookPanel.Create(pageFrame, {
        extendFancySurface = true,
    })
    if type(pageFrame.HookScript) == "function" then
        pageFrame:HookScript("OnShow", function(frame)
            keepMainCloseButtonVisible(frame, true)
            routeBookClose(frame, true)
        end)
        pageFrame:HookScript("OnHide", function(frame)
            keepMainCloseButtonVisible(frame, false)
            routeBookClose(frame, false)
        end)
    end
    return pageFrame
end

local function refreshImportedPage()
    if not importedPageFrame or not importedPageFrame.panel then
        return
    end

    addon.ImportedLibraryPanel.Refresh(importedPageFrame.panel, pendingImportID)
    pendingImportID = nil
end

local function createImportedPageFrame()
    if importedPageFrame then
        return importedPageFrame
    end

    importedPageFrame = CreateFrame("Frame")
    importedPageFrame:Hide()
    importedPageFrame.panel = addon.ImportedLibraryPanel.Create(importedPageFrame)
    return importedPageFrame
end

local function registerNavigation()
    local constants = addon.Constants
    local parentSuccess, parentRegistered = addon.TRP3Bridge.IsNavigationMenuRegistered(constants.CHARACTER_MENU_ID)
    if not parentSuccess then
        return false, parentRegistered
    end

    if not parentRegistered then
        return false, addon.L("TRP3_CHARACTER_MENU_NOT_REGISTERED")
    end

    local frame = createPageFrame()
    local pageSuccess, pageError = addon.TRP3Bridge.RegisterNavigationPage({
        id = constants.NAVIGATION_PAGE_ID,
        frame = frame,
        onPagePreShow = refreshPage,
    })
    if not pageSuccess then
        return false, pageError
    end

    local importedFrame = createImportedPageFrame()
    local importedPageSuccess, importedPageError = addon.TRP3Bridge.RegisterNavigationPage({
        id = constants.IMPORTED_NAVIGATION_PAGE_ID,
        frame = importedFrame,
        onPagePreShow = refreshImportedPage,
    })
    if not importedPageSuccess then
        return false, importedPageError
    end

    local menuSuccess, menuError = addon.TRP3Bridge.RegisterNavigationMenu({
        id = constants.NAVIGATION_MENU_ID,
        text = addon.BookNavigationStyle and addon.BookNavigationStyle.GetText() or addon.L("ADDON_TITLE"),
        isChildOf = constants.CHARACTER_MENU_ID,
        sortGroup = constants.NAVIGATION_MENU_ID,
        sortIndex = 1,
        onSelected = function()
            local success, errorMessage = addon.TRP3Bridge.SetNavigationPage(constants.NAVIGATION_PAGE_ID)
            if not success then
                addon.Logger.Error(errorMessage)
            end
        end,
    })
    if not menuSuccess then
        return false, menuError
    end

    local importedMenuSuccess, importedMenuError = addon.TRP3Bridge.RegisterNavigationMenu({
        id = constants.IMPORTED_NAVIGATION_MENU_ID,
        text = addon.L("IMPORT_ARCHIVE"),
        isChildOf = constants.CHARACTER_MENU_ID,
        sortGroup = constants.NAVIGATION_MENU_ID,
        sortIndex = 2,
        onSelected = function()
            local success, errorMessage = addon.TRP3Bridge.SetNavigationPage(constants.IMPORTED_NAVIGATION_PAGE_ID)
            if not success then
                addon.Logger.Error(errorMessage)
            end
        end,
    })
    if not importedMenuSuccess then
        return false, importedMenuError
    end

    addon.TRP3Integration.isRegistered = true
    addon.TRP3Integration.importedRegistered = true
    if addon.Modules and addon.Modules.IsEnabled("npc") and addon.NPCArchive
        and type(addon.NPCArchive.CreatePage) == "function" then
        if not npcPageFrame then
            local created, frameOrError = pcall(addon.NPCArchive.CreatePage)
            if not created or not frameOrError then
                addon.Logger.Error(tostring(frameOrError or addon.L("NPC_ARCHIVE_ENTRY")))
                return true
            end
            npcPageFrame = frameOrError
        end
        local pageOK, pageError = addon.TRP3Bridge.RegisterNavigationPage({
            id = NPC_PAGE_ID, frame = npcPageFrame,
            onPagePreShow = function()
                if addon.NPCArchive.RefreshPage then addon.NPCArchive.RefreshPage() end
            end,
        })
        if not pageOK then addon.Logger.Error(tostring(pageError)); return true end
        local ok, err = addon.TRP3Bridge.RegisterNavigationMenu({
            id = NPC_MENU_ID,
            text = addon.L("NPC_ARCHIVE_ENTRY"),
            isChildOf = constants.CHARACTER_MENU_ID,
            sortGroup = constants.NAVIGATION_MENU_ID,
            sortIndex = 3,
            onSelected = function()
                local selected, selectionError = addon.TRP3Bridge.SetNavigationPage(NPC_PAGE_ID)
                if not selected then addon.Logger.Error(tostring(selectionError)) end
            end,
        })
        addon.TRP3Integration.npcRegistered = ok == true
        if not ok then addon.Logger.Error(tostring(err)) end
    end
    return true
end

local function registerToolbar()
    if addon.TRP3Integration.toolbarRegistered then return true end
    local settingsInstructions = { "SHIFT-BUTTON1", addon.L("TOOLBAR_SHIFT_SETTINGS") }
    local leftClickInstructions = {
        { "BUTTON1", addon.L("TOOLBAR_LEFT_CLICK") },
        settingsInstructions,
    }
    local gameMasterInstructions = {
        leftClickInstructions[1],
        { "BUTTON2", addon.L("TOOLBAR_RIGHT_CLICK_GAMEMASTER") },
        settingsInstructions,
    }
    local compactInstructions = {
        leftClickInstructions[1],
        { "BUTTON2", addon.L("TOOLBAR_RIGHT_CLICK_COMPACT") },
        settingsInstructions,
    }
    local activeLeaderInstructions = {
        leftClickInstructions[1],
        { "BUTTON2", addon.L("TOOLBAR_RIGHT_CLICK_GAMEMASTER") },
        settingsInstructions,
    }
    if addon.Modules and addon.Modules.IsEnabled("npc") then
        for _, instructions in ipairs({ leftClickInstructions, gameMasterInstructions,
            compactInstructions, activeLeaderInstructions }) do
            instructions[#instructions + 1] = { "SHIFT-BUTTON2", addon.L("TOOLBAR_SHIFT_NPC") }
        end
    end
    local constants = addon.Constants
    local success, errorMessage = addon.TRP3Bridge.RegisterToolbarButton({
        id = constants.TOOLBAR_BUTTON_ID,
        icon = addon.GameMasterSettings.GetBookToolbarIcon
            and addon.GameMasterSettings.GetBookToolbarIcon() or constants.DEFAULT_TRP3_TOOLBAR_ICON,
        text = addon.L("ADDON_TITLE"),
        configText = addon.L("ADDON_TITLE"),
        tooltip = addon.L("ADDON_TITLE"),
        tooltipSub = addon.L("TOOLBAR_TOOLTIP"),
        tooltipInstructions = leftClickInstructions,
        onClick = function(_, _, button)
            if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
                if button == "LeftButton" then
                    local opened, errorMessage = addon.GameMasterSettings.Open()
                    if not opened then addon.Logger.Error(errorMessage) end
                    return
                elseif button == "RightButton" then
                    addon.Core.CaptureNPCTarget()
                    return
                end
            end
            local canControl = addon.GameMasterService.CanControl()
                or addon.GameMasterService.IsAssistantGameMaster()
            local sessionActive = addon.GameMasterService.IsSessionActive()
            if button == "RightButton" and canControl then
                addon.GameMasterService.OpenControl()
            elseif button == "RightButton" and sessionActive then
                addon.GameMasterCompactSpellbook.Open()
            elseif button == "RightButton" then
                if not addon.Modules or addon.Modules.IsEnabled("gameMaster") then
                    addon.GameMasterService.OpenControl()
                else
                    addon.Core.OpenSpellbook()
                end
            else
                addon.Core.OpenSpellbook()
            end
        end,
        onModelUpdate = function(button)
            addon.TRP3Integration.toolbarButton = button
            if addon.BookNavigationStyle then addon.BookNavigationStyle.Refresh() end
            if addon.GameMasterSettings.GetBookToolbarIcon then
                button.icon = addon.GameMasterSettings.GetBookToolbarIcon()
                addon.GameMasterSettings.RefreshBookIcon()
            end
            local canControl = addon.GameMasterService.CanControl()
                or addon.GameMasterService.IsAssistantGameMaster()
            local sessionActive = addon.GameMasterService.IsSessionActive()
            if canControl and sessionActive then
                button.tooltipSub = addon.L("TOOLBAR_TOOLTIP_GAMEMASTER_COMPACT")
                button.tooltipInstructions = activeLeaderInstructions
            elseif canControl then
                button.tooltipSub = addon.L("TOOLBAR_TOOLTIP_GAMEMASTER")
                button.tooltipInstructions = gameMasterInstructions
            elseif sessionActive then
                button.tooltipSub = addon.L("TOOLBAR_TOOLTIP_COMPACT")
                button.tooltipInstructions = compactInstructions
            else
                button.tooltipSub = addon.L("TOOLBAR_TOOLTIP")
                button.tooltipInstructions = leftClickInstructions
            end
        end,
    })
    if success then
        addon.TRP3Integration.toolbarRegistered = true
    end

    return success, errorMessage
end

function addon.TRP3Integration.RefreshBookIcon()
    local button = addon.TRP3Integration.toolbarButton
    if button then button.icon = addon.GameMasterSettings.GetBookToolbarIcon() end
    if pageFrame and pageFrame:IsShown() then refreshPage() end
end

local function onWorkflowLoaded()
    local creationSuccess, creationError =
        addon.SpellCreationSettings.Initialize()
    if not creationSuccess then
        addon.Logger.Error(tostring(creationError))
    end
    if creationSuccess and addon.SeasonalVisuals then addon.SeasonalVisuals.RefreshSettings() end

    local settingsSuccess, settingsError = addon.GameMasterSettings.RegisterPage()
    if not settingsSuccess then
        addon.Logger.Error(tostring(settingsError))
    end

    local navigationSuccess, navigationError = registerNavigation()
    if not navigationSuccess then
        addon.Logger.Error(addon.L("NAVIGATION_REGISTER_FAILED", tostring(navigationError)))
    end

    local toolbarSuccess, toolbarError = registerToolbar()
    if not toolbarSuccess then
        addon.Logger.Error(addon.L("TOOLBAR_REGISTER_FAILED", tostring(toolbarError)))
    end
    if addon.QuickAccess then addon.QuickAccess.Register() end
end

function addon.TRP3Integration.Initialize()
    if workflowRegistered then
        return true
    end
    local success, errorMessage = addon.TRP3Bridge.RegisterWorkflowLoadedCallback(onWorkflowLoaded)
    if success then
        workflowRegistered = true
    end
    return success, errorMessage
end

 
 
function addon.TRP3Integration.InitializeToolbarForBackup(onRegistered)
    if backupToolbarRegistered then return true end
    local success, err = addon.TRP3Bridge.RegisterWorkflowLoadedCallback(function()
        local creationOK, creationError = addon.SpellCreationSettings.Initialize()
        local settingsOK, settingsError = addon.GameMasterSettings.Initialize()
        local toolbarOK, toolbarError = registerToolbar()
        local quickOK = not addon.QuickAccess or addon.QuickAccess.Register()
        onRegistered(creationOK and settingsOK and toolbarOK and quickOK,
            creationError or settingsError or toolbarError)
    end)
    if success then backupToolbarRegistered = true end
    return success, err
end

function addon.TRP3Integration.InitializeAfterBackup()
    if workflowRegistered then return true end
     
    onWorkflowLoaded()
    workflowRegistered = true
    return true
end

function addon.TRP3Integration.Open()
    if not addon.TRP3Integration.isRegistered then
        return false
    end

    local success, errorMessage = addon.TRP3Bridge.OpenNavigationMenu(addon.Constants.NAVIGATION_MENU_ID)
    if not success then
        addon.Logger.Error(errorMessage)
        return false
    end

    return true
end

function addon.TRP3Integration.OpenImportedLibrary(preferredImportID)
    if not addon.TRP3Integration.importedRegistered then
        return false
    end

    pendingImportID = type(preferredImportID) == "string" and preferredImportID or nil
    local success, errorMessage = addon.TRP3Bridge.OpenNavigationMenu(addon.Constants.IMPORTED_NAVIGATION_MENU_ID)
    if not success then
        pendingImportID = nil
        addon.Logger.Error(errorMessage)
        return false
    end
    return true
end

function addon.TRP3Integration.GetSpellbookPanel()
    return pageFrame and pageFrame.panel
end

function addon.TRP3Integration.OpenNPCArchive()
    if not addon.TRP3Integration.npcRegistered or not addon.Modules.IsEnabled("npc") then return false end
    return addon.TRP3Bridge.OpenNavigationMenu(NPC_MENU_ID)
end
