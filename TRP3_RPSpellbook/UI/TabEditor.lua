local _, addon = ...

addon.TabEditor = {}

local dialog
local state = {}

local function supportsTabThemes(storage)
    return (storage == nil or storage == addon.Database)
        and type(addon.SpellCreationThemes) == "table"
        and type(addon.SpellCreationThemes.GetTabThemeOptions) == "function"
end

local function getStorage()
    return state.storage or addon.Database
end

local function setError(message)
    dialog.errorLabel:SetText(message or "")
end

local function ownsBook(storage, original)
    local book = storage.GetActiveSpellbook()
    if not book or not original then return false end
     
    if storage == addon.Database then return book == original end
    return book.id ~= nil and book.id == original.id and book.profileKey == original.profileKey
end

local function checkBook()
    if ownsBook(getStorage(), state.book) then return true end
    setError(addon.L("EDITOR_PROFILE_CHANGED"))
    return false
end

local function draftCallback(callback)
    local token, storage, book = state.token, getStorage(), state.book
    return function(...)
        if state.token == token and ownsBook(storage, book) then
            return callback(...)
        end
    end
end

local function showDialog()
    dialog:Show()
    addon.UIFactory.BringToFront(dialog)
end

local function setSelectedIcon(icon)
    state.icon = icon
    addon.UIFactory.SetIconTexture(dialog.iconButton.iconTexture, icon, addon.Constants.DEFAULT_TAB_ICON)
end

local function setSelectedTheme(themeID)
    local requestedTheme = themeID or "default"
    local label = addon.L("SPELL_CREATION_EDITOR_THEME_DEFAULT")
    local found = false
    for _, option in ipairs(addon.SpellCreationThemes.GetTabThemeOptions()) do
        if option.value == requestedTheme then
            label = option.label
            found = true
            break
        end
    end
    state.themeID = found and requestedTheme or "default"
    dialog.themeSelector:OverrideText(label)
end

local function findDeleteTarget(spellbook, currentTabID)
    for _, tabID in ipairs(spellbook.tabOrder) do
        if tabID ~= currentTabID and spellbook.tabs[tabID] then
            return tabID, spellbook.tabs[tabID]
        end
    end
    return nil
end

local function saveTab()
    if not dialog:IsShown() then return end
    setError(nil)
    if not checkBook() then return end
    local tab, errorMessage
    if state.tabID then
        local patch = {
            name = dialog.nameField:GetText(),
            icon = state.icon,
            clearOptionalFields = true,
        }
        if state.themeEnabled then
            patch.themeID = state.themeID
        end
        tab, errorMessage = getStorage().UpdateTab(state.tabID, patch)
    else
        tab, errorMessage = getStorage().CreateTab(
            dialog.nameField:GetText(),
            state.icon,
            state.themeEnabled and state.themeID or nil
        )
    end

    if not tab then
        setError(errorMessage)
        return
    end

    state.tabID = tab.id
    local onChanged = state.onChanged
    dialog:Hide()
    if type(onChanged) == "function" then
        onChanged(tab.id)
    end
end

local function deleteTab()
    if not state.tabID or not checkBook() then
        return
    end

    local storage, tabID, onChanged = getStorage(), state.tabID, state.onChanged
    local book, token = state.book, state.token
    local resolved = false
    local spellbook = storage.GetActiveSpellbook()
    local tab = spellbook and spellbook.tabs[state.tabID]
    local targetTabID, targetTab
    if spellbook then
        targetTabID, targetTab = findDeleteTarget(spellbook, state.tabID)
    end
    if not tab or not targetTabID or not targetTab then
        setError(addon.L("KEEP_ONE_TAB"))
        return
    end

    local message = addon.L(
        "DELETE_TAB_CONFIRM",
        tab.name,
        targetTab.name
    )
    dialog:Hide()
    addon.UIFactory.ShowConfirmation(addon.L("DELETE_TAB_TITLE"), message, function()
        if resolved then return end
        resolved = true
        if not ownsBook(storage, book) then
            if state.token == token then
                showDialog()
                setError(addon.L("EDITOR_PROFILE_CHANGED"))
            end
            return
        end
        local deleted, errorMessage = storage.DeleteTab(tabID, targetTabID)
        if not deleted then
            if state.token == token then
                showDialog()
                setError(errorMessage)
            end
            return
        end

        if type(onChanged) == "function" then
            onChanged(targetTabID)
        end
    end, function()
        if resolved then return end
        resolved = true
        if state.token == token then showDialog() end
    end)
end

local function createDialog()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(addon.L("EDIT_TAB_TITLE"), theme.Sizes.tabDialogWidth, theme.Sizes.tabDialogHeight)

    local iconLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.small, addon.L("FIELD_ICON_RESET"), theme.Colors.textMuted)
    iconLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -theme.Spacing.xl - theme.Spacing.lg)

    local iconButton = addon.UIFactory.CreateIconButton(frame)
    iconButton:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    iconButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            setSelectedIcon(nil)
            return
        end

        local success, errorMessage = addon.TRP3Bridge.OpenIconBrowser(
            state.icon,
            draftCallback(setSelectedIcon),
            nil,
            frame
        )
        if not success then
            setError(errorMessage)
        end
    end)

    local nameLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, addon.L("FIELD_NAME"), theme.Colors.textMuted)
    nameLabel:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", theme.Spacing.md, 0)
    local nameField = addon.UIFactory.CreateEditBox(frame, false)
    nameField:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    nameField:SetWidth(theme.Sizes.tabDialogWidth - (theme.Spacing.lg * 2) - theme.Sizes.editorIcon - theme.Spacing.md)

    local themeLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("FIELD_TAB_THEME"),
        theme.Colors.textMuted
    )
    themeLabel:SetPoint("TOPLEFT", iconButton, "BOTTOMLEFT", 0, -theme.Spacing.md)
    local themeSelector = CreateFrame(
        "Frame",
        nil,
        frame,
        "TRP3_DropdownButtonTemplate"
    )
    themeSelector:SetPoint("TOPLEFT", themeLabel, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    themeSelector:SetPoint("RIGHT", frame, "RIGHT", -theme.Spacing.lg, 0)
    themeSelector:SetHeight(theme.Sizes.inputHeight)
    themeSelector:SetupMenu(function(_, rootDescription)
        local maximumWidth = math.max(1, math.min(360, UIParent:GetWidth() - 40))
        rootDescription:SetMinimumWidth(math.min(themeSelector:GetWidth(), maximumWidth))
        rootDescription:SetMaximumWidth(maximumWidth)
        rootDescription:SetScrollMode(math.max(1, math.min(360, UIParent:GetHeight() - 40)))
        for _, option in ipairs(addon.SpellCreationThemes.GetTabThemeOptions()) do
            local current = option
            rootDescription:CreateRadio(
                current.label,
                function(value)
                    return state.themeID == value
                end,
                draftCallback(setSelectedTheme),
                current.value
            )
        end
    end)
    if type(hooksecurefunc) == "function" and themeSelector.Button then
        hooksecurefunc(themeSelector.Button, "OnMenuOpened", function(_, menu)
            menu:SetFrameStrata("TOOLTIP")
        end)
    end
    themeSelector:HookScript("OnHide", function()
        if type(themeSelector.CloseMenu) == "function" then
            themeSelector:CloseMenu()
        end
    end)

    local errorLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.small, "", theme.Colors.error)
    errorLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", theme.Spacing.lg, 54)
    errorLabel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, 54)
    errorLabel:SetJustifyH("LEFT")

    local saveButton = addon.UIFactory.CreateButton(frame, addon.L("SAVE"), theme.Sizes.dialogButtonWidth)
    saveButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)
    saveButton:SetScript("OnClick", saveTab)

    local cancelButton = addon.UIFactory.CreateButton(frame, addon.L("CANCEL"), theme.Sizes.dialogButtonWidth)
    cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -theme.Spacing.sm, 0)
    cancelButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local deleteButton = addon.UIFactory.CreateButton(frame, addon.L("DELETE"), theme.Sizes.deleteButtonWidth)
    deleteButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", theme.Spacing.lg, theme.Spacing.lg)
    deleteButton:SetScript("OnClick", deleteTab)

    frame.deleteButton = deleteButton
    frame.errorLabel = errorLabel
    frame.iconButton = iconButton
    frame.nameField = nameField
    frame.themeLabel = themeLabel
    frame.themeSelector = themeSelector
    return frame
end

local function prepareDialog(tab, onChanged, storage)
    state.storage = storage
    state.book = getStorage().GetActiveSpellbook()
    state.token = {}
    dialog = dialog or createDialog()
    state.tabID = tab and tab.id or nil
    state.onChanged = onChanged
    state.themeEnabled = supportsTabThemes(storage)

    dialog.title:SetText(tab and addon.L("EDIT_TAB_TITLE") or addon.L("NEW_TAB"))
    dialog.nameField:SetText(tab and tab.name or "")
    dialog.deleteButton:SetShown(tab ~= nil)
    dialog.themeLabel:SetShown(state.themeEnabled)
    dialog.themeSelector:SetShown(state.themeEnabled)
    if tab then
        local spellbook = getStorage().GetActiveSpellbook()
        if spellbook and #spellbook.tabOrder <= 1 then
            dialog.deleteButton:Disable()
        else
            dialog.deleteButton:Enable()
        end
    end
    setSelectedIcon(tab and tab.icon or nil)
    if state.themeEnabled then
        setSelectedTheme(tab and tab.themeID or "default")
        if type(dialog.themeSelector.GenerateMenu) == "function" then
            dialog.themeSelector:GenerateMenu()
        end
    else
        state.themeID = nil
        if type(dialog.themeSelector.CloseMenu) == "function" then
            dialog.themeSelector:CloseMenu()
        end
    end
    setError(nil)
    showDialog()
end

function addon.TabEditor.OpenNew(onChanged, storage)
    prepareDialog(nil, onChanged, storage)
end

function addon.TabEditor.OpenEdit(tabID, onChanged, storage)
    local tab = (storage or addon.Database).GetTab(tabID)
    if not tab then
        addon.Logger.Error(addon.L("TAB_NOT_FOUND"))
        return
    end

    prepareDialog(tab, onChanged, storage)
end
