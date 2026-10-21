local _, addon = ...

addon.ArchiveCopyDialog = {}

local dialog
local state = {}

local function setButtonEnabled(button, enabled)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

local function closeDialog()
    if dialog then
        dialog:Hide()
    end
    state = {}
end

local function updateTarget()
    local targetBook = addon.Database.GetActiveSpellbook()
    local tabOrder = type(targetBook) == "table" and targetBook.tabOrder or {}
    local tabID = tabOrder[state.targetIndex]
    local tab = tabID and targetBook.tabs[tabID] or nil

    state.targetTabID = tabID
    dialog.targetName:SetText(tab and tab.name or addon.L("ARCHIVE_NO_TARGET_TABS"))
    addon.UIFactory.SetIconTexture(
        dialog.targetIcon,
        tab and tab.icon,
        addon.Constants.DEFAULT_TAB_ICON
    )
    setButtonEnabled(dialog.previousButton, state.targetIndex > 1)
    setButtonEnabled(dialog.nextButton, state.targetIndex < #tabOrder)
    setButtonEnabled(dialog.confirmButton, tab ~= nil)
end

local function createDialog()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("ARCHIVE_COPY_SPELL_TITLE"),
        theme.Sizes.archiveCopyDialogWidth,
        theme.Sizes.archiveCopyDialogHeight
    )

    local hint = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, addon.L("ARCHIVE_COPY_SPELL_HINT"), theme.Colors.text)
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -(theme.Spacing.xl + theme.Spacing.md))
    hint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.lg, -(theme.Spacing.xl + theme.Spacing.md))
    hint:SetJustifyH("LEFT")

    local targetLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, addon.L("ARCHIVE_COPY_TARGET_TAB"), theme.Colors.gold)
    targetLabel:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -theme.Spacing.lg)

    local previousButton = addon.UIFactory.CreateButton(frame, "<", theme.Sizes.pageButtonWidth)
    previousButton:SetPoint("LEFT", targetLabel, "RIGHT", theme.Spacing.md, 0)
    local targetIcon = frame:CreateTexture(nil, "ARTWORK")
    targetIcon:SetSize(theme.Sizes.tabIcon, theme.Sizes.tabIcon)
    targetIcon:SetPoint("LEFT", previousButton, "RIGHT", theme.Spacing.sm, 0)
    local targetName = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, "", theme.Colors.text)
    targetName:SetPoint("LEFT", targetIcon, "RIGHT", theme.Spacing.xs, 0)
    targetName:SetWidth(190)
    targetName:SetWordWrap(false)
    local nextButton = addon.UIFactory.CreateButton(frame, ">", theme.Sizes.pageButtonWidth)
    nextButton:SetPoint("LEFT", targetName, "RIGHT", theme.Spacing.sm, 0)

    local confirmButton = addon.UIFactory.CreateButton(frame, addon.L("ARCHIVE_COPY_CONFIRM"), theme.Sizes.dialogButtonWidth)
    confirmButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)
    local cancelButton = addon.UIFactory.CreateButton(frame, addon.L("CANCEL"), theme.Sizes.dialogButtonWidth)
    cancelButton:SetPoint("RIGHT", confirmButton, "LEFT", -theme.Spacing.sm, 0)

    frame.targetIcon = targetIcon
    frame.targetName = targetName
    frame.previousButton = previousButton
    frame.nextButton = nextButton
    frame.confirmButton = confirmButton

    previousButton:SetScript("OnClick", function()
        state.targetIndex = math.max(1, state.targetIndex - 1)
        updateTarget()
    end)
    nextButton:SetScript("OnClick", function()
        state.targetIndex = state.targetIndex + 1
        updateTarget()
    end)
    cancelButton:SetScript("OnClick", closeDialog)
    frame.closeButton:SetScript("OnClick", closeDialog)
    confirmButton:SetScript("OnClick", function()
        local copiedSpell, errorMessage = addon.ArchiveCopy.CopySpell(
            state.archiveBook,
            state.spellID,
            state.targetTabID
        )
        if not copiedSpell then
            addon.Logger.Error(errorMessage or addon.L("ARCHIVE_COPY_FAILED"))
            return
        end
        closeDialog()
        addon.Logger.Info(addon.L("ARCHIVE_SPELL_COPIED", copiedSpell.name))
    end)
    return frame
end

function addon.ArchiveCopyDialog.OpenSpell(archiveBook, spellID)
    local allowed, errorMessage = addon.ArchiveCopy.CanCopySpell(archiveBook, spellID)
    if not allowed then
        addon.Logger.Error(errorMessage)
        return false
    end

    local targetBook = addon.Database.GetActiveSpellbook()
    if type(targetBook) ~= "table"
        or type(targetBook.tabOrder) ~= "table"
        or #targetBook.tabOrder == 0
    then
        addon.Logger.Error(addon.L("ARCHIVE_NO_TARGET_TABS"))
        return false
    end

    dialog = dialog or createDialog()
    state = {
        archiveBook = archiveBook,
        spellID = spellID,
        targetIndex = 1,
    }
    updateTarget()
    dialog:Show()
    addon.UIFactory.BringToFront(dialog)
    return true
end
