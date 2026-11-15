local _, addon = ...

addon.ExportWindow = {}

local window
local state = {
    expirationIndex = 1,
    scope = "spell",
    tabFilterMode = "blacklist",
    spellFilterMode = "blacklist",
    selectedTabs = {},
    selectedSpells = {},
}

local refreshFilters
local generateExport

local function setButtonEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end

local function setStatus(message, isError)
    if not window then
        return
    end
    window.status:SetText(message or "")
    local color = isError and addon.Theme.Colors.error or addon.Theme.Colors.textMuted
    window.status:SetTextColor(color[1], color[2], color[3], color[4])
end

local function setOutput(exportString)
    window.exportText = exportString or ""
    window.output:SetText(window.exportText)
    if window.exportText ~= "" then
        window.output:SetFocus()
        window.output:HighlightText()
    end
end

local function invalidateExport()
    if not window then
        return
    end
    setOutput("")
    setStatus(addon.L("EXPORT_REGENERATE"), false)
end

local function handleCommonOptionChanged()
    if state.scope == "spell" then
        generateExport()
    else
        invalidateExport()
    end
end

local function isSelected(selection, itemID)
    return type(selection) == "table" and selection[itemID] == true
end

local function shouldInclude(itemID, mode, selection)
    local selected = isSelected(selection, itemID)
    return mode == "whitelist" and selected or mode == "blacklist" and not selected
end

local function getActiveTab()
    local tabs = type(state.spellbook) == "table" and state.spellbook.tabs or nil
    return type(tabs) == "table" and tabs[state.tabID] or nil
end

local function getFilterSelection(kind)
    return kind == "tabs" and state.selectedTabs or state.selectedSpells
end

local function getFilterMode(kind)
    return kind == "tabs" and state.tabFilterMode or state.spellFilterMode
end

local function setFilterMode(kind, mode)
    if kind == "tabs" then
        state.tabFilterMode = mode
    else
        state.spellFilterMode = mode
    end
end

local function buildTabItems()
    local items = {}
    local spellbook = state.spellbook
    for _, tabID in ipairs(type(spellbook) == "table" and type(spellbook.tabOrder) == "table" and spellbook.tabOrder or {}) do
        local tab = type(spellbook.tabs) == "table" and spellbook.tabs[tabID] or nil
        items[#items + 1] = {
            id = tabID,
            label = type(tab) == "table" and tab.name or tabID,
        }
    end
    return items
end

local function addSpellItems(items, tab, includeTabName)
    if type(tab) ~= "table" then
        return
    end
    local spellbook = state.spellbook
    for _, spellID in ipairs(type(tab.spellIds) == "table" and tab.spellIds or {}) do
        local spell = type(spellbook.spells) == "table" and spellbook.spells[spellID] or nil
        local spellName = type(spell) == "table" and spell.name or addon.L("UNKNOWN_ABILITY")
        items[#items + 1] = {
            id = spellID,
            label = includeTabName and addon.L("EXPORT_SPELL_FILTER_ROW", tab.name, spellName) or spellName,
        }
    end
end

local function buildSpellItems()
    local items = {}
    if state.scope == "tab" then
        addSpellItems(items, getActiveTab(), false)
        return items
    end

    local spellbook = state.spellbook
    for _, tabID in ipairs(type(spellbook) == "table" and type(spellbook.tabOrder) == "table" and spellbook.tabOrder or {}) do
        if shouldInclude(tabID, state.tabFilterMode, state.selectedTabs) then
            local tab = type(spellbook.tabs) == "table" and spellbook.tabs[tabID] or nil
            addSpellItems(items, tab, true)
        end
    end
    return items
end

local function renderFilterSection(section)
    local items = section.kind == "tabs" and buildTabItems() or buildSpellItems()
    local selection = getFilterSelection(section.kind)
    local mode = getFilterMode(section.kind)
    local pageCount = math.max(1, math.ceil(#items / #section.rows))
    section.page = math.max(1, math.min(section.page or 1, pageCount))
    local firstIndex = ((section.page - 1) * #section.rows) + 1

    section.title:SetText(section.kind == "tabs" and addon.L("EXPORT_TABS") or addon.L("EXPORT_ABILITIES"))
    section.modeButton:SetText(addon.L(mode == "blacklist" and "EXPORT_BLACKLIST" or "EXPORT_WHITELIST"))
    section.hint:SetText(addon.L(mode == "blacklist" and "EXPORT_BLACKLIST_HINT" or "EXPORT_WHITELIST_HINT"))
    section.pageLabel:SetText(addon.L("PAGE_FORMAT", section.page, pageCount))
    setButtonEnabled(section.previousButton, section.page > 1)
    setButtonEnabled(section.nextButton, section.page < pageCount)

    for rowIndex, row in ipairs(section.rows) do
        local item = items[firstIndex + rowIndex - 1]
        row.itemID = item and item.id or nil
        if item then
            row.label:SetText(item.label)
            row:SetChecked(selection[item.id] == true)
            row:Show()
        else
            row:SetChecked(false)
            row:Hide()
        end
    end
    section.emptyLabel:SetShown(#items == 0)
end

refreshFilters = function()
    if not window then
        return
    end
    window.tabFilterSection:SetShown(state.scope == "book")
    window.spellFilterSection:ClearAllPoints()
    if state.scope == "book" then
        window.spellFilterSection:SetPoint("TOPLEFT", window.tabFilterSection, "TOPRIGHT", addon.Theme.Spacing.md, 0)
        window.spellFilterSection:SetPoint("BOTTOMRIGHT", window.filterFrame, "BOTTOMRIGHT", 0, 0)
        renderFilterSection(window.tabFilterSection)
    else
        window.spellFilterSection:SetAllPoints(window.filterFrame)
    end
    renderFilterSection(window.spellFilterSection)
end

local function updateExpiration()
    local options = addon.Constants.EXPORT_EXPIRATION_OPTIONS
    local option = options[state.expirationIndex] or options[1]
    window.expirationValue:SetText(addon.L(option.labelKey))
end

local function cycleExpiration(direction)
    local options = addon.Constants.EXPORT_EXPIRATION_OPTIONS
    state.expirationIndex = ((state.expirationIndex - 1 + direction) % #options) + 1
    updateExpiration()
    handleCommonOptionChanged()
end

local function updateScopeLabels()
    local spellbook = state.spellbook
    if state.scope == "spell" then
        window.typeLabel:SetText(addon.L("EXPORT_TYPE_SPELL"))
        window.subjectLabel:SetText(state.spell and state.spell.name or addon.L("UNKNOWN_ABILITY"))
    elseif state.scope == "tab" then
        local tab = getActiveTab()
        window.typeLabel:SetText(addon.L("EXPORT_TYPE_TAB"))
        window.subjectLabel:SetText(tab and tab.name or addon.L("UNKNOWN"))
        window.scopeValue:SetText(addon.L("EXPORT_SCOPE_TAB"))
    else
        window.typeLabel:SetText(addon.L("EXPORT_TYPE_BOOK"))
        window.subjectLabel:SetText(type(spellbook) == "table" and spellbook.name or addon.L("DEFAULT_BOOK_NAME"))
        window.scopeValue:SetText(addon.L("EXPORT_SCOPE_BOOK"))
    end
end

local function layoutWindow()
    local theme = addon.Theme
    local collection = state.scope ~= "spell"
    window.scopeLabel:SetShown(collection)
    window.previousScope:SetShown(collection)
    window.scopeValue:SetShown(collection)
    window.nextScope:SetShown(collection)
    window.filterFrame:SetShown(collection)
    window.copySpellCheck:Show()
    window.copySpellLabel:Show()
    window.copyTabCheck:SetShown(collection)
    window.copyTabLabel:SetShown(collection)

    window.ownerCheck:ClearAllPoints()
    if collection then
        window.ownerCheck:SetPoint("TOPLEFT", window.scopeLabel, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    else
        window.ownerCheck:SetPoint("TOPLEFT", window.subjectLabel, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    end

    window.generateButton:ClearAllPoints()
    if collection then
        window.filterFrame:ClearAllPoints()
        window.filterFrame:SetPoint("TOPLEFT", window.expirationLabel, "BOTTOMLEFT", 0, -theme.Spacing.md)
        window.filterFrame:SetSize(
            theme.Sizes.exportDialogWidth - (theme.Spacing.lg * 2),
            theme.Sizes.exportFilterHeight
        )
        window.generateButton:SetPoint("TOPLEFT", window.filterFrame, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    else
        window.generateButton:SetPoint("TOPLEFT", window.expirationLabel, "BOTTOMLEFT", 0, -theme.Spacing.md)
    end

    window.outputLabel:ClearAllPoints()
    window.outputLabel:SetPoint("TOPLEFT", window.generateButton, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    window.outputContainer:ClearAllPoints()
    window.outputContainer:SetPoint("TOPLEFT", window.outputLabel, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    window.outputContainer:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Sizes.exportFooterHeight)
    if collection then
        refreshFilters()
    end
end

local function cycleScope()
    state.scope = state.scope == "book" and "tab" or "book"
    state.tabFilterMode = "blacklist"
    state.spellFilterMode = "blacklist"
    state.selectedTabs = {}
    state.selectedSpells = {}
    window.tabFilterSection.page = 1
    window.spellFilterSection.page = 1
    updateScopeLabels()
    layoutWindow()
    invalidateExport()
end

local function createCheckOption(parent, labelText)
    local theme = addon.Theme
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(theme.Sizes.inputHeight, theme.Sizes.inputHeight)
    local label = addon.UIFactory.CreateLabel(parent, theme.Fonts.body, labelText, theme.Colors.text)
    label:SetPoint("LEFT", check, "RIGHT", theme.Spacing.xs, 0)
    check:HookScript("OnShow", function(self)
        self:SetHitRectInsets(0, -(theme.Spacing.xs + label:GetWidth()), 0, 0)
    end)
    check:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label:GetText(), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    local function hideTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    check:HookScript("OnLeave", hideTooltip)
    check:HookScript("OnHide", hideTooltip)
    return check, label
end

local function createFilterSection(parent, kind)
    local theme = addon.Theme
    local section = addon.UIFactory.CreateBackdropFrame(parent, theme.Colors.parchmentDark, theme.Colors.border)
    section.kind = kind
    section.page = 1

    local title = addon.UIFactory.CreateLabel(section, theme.Fonts.body, "", theme.Colors.gold)
    title:SetPoint("TOPLEFT", section, "TOPLEFT", theme.Spacing.sm, -theme.Spacing.sm)
    local modeButton = addon.UIFactory.CreateButton(section, "", theme.Sizes.exportFilterModeWidth)
    modeButton:SetPoint("TOPRIGHT", section, "TOPRIGHT", -theme.Spacing.sm, -theme.Spacing.xs)
    local hint = addon.UIFactory.CreateLabel(section, theme.Fonts.small, "", theme.Colors.textMuted)
    hint:SetPoint("TOPLEFT", section, "TOPLEFT", theme.Spacing.sm, -30)
    hint:SetPoint("TOPRIGHT", section, "TOPRIGHT", -theme.Spacing.sm, -30)
    hint:SetHeight(12)
    hint:SetJustifyH("LEFT")

    local rows = {}
    for index = 1, theme.Sizes.exportFilterVisibleRows do
        local row = CreateFrame("CheckButton", nil, section, "UICheckButtonTemplate")
        row:SetSize(theme.Sizes.tabIcon, theme.Sizes.tabIcon)
        row:SetPoint("TOPLEFT", section, "TOPLEFT", theme.Spacing.xs, -(48 + ((index - 1) * theme.Sizes.exportFilterRowHeight)))
        local label = addon.UIFactory.CreateLabel(row, theme.Fonts.small, "", theme.Colors.text)
        label:SetPoint("LEFT", row, "RIGHT", theme.Spacing.tiny, 0)
        label:SetPoint("RIGHT", section, "RIGHT", -theme.Spacing.sm, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.label = label
        row:SetScript("OnClick", function(self)
            if not self.itemID then return end
            local selection = getFilterSelection(section.kind)
            selection[self.itemID] = self:GetChecked() == true and true or nil
            if section.kind == "tabs" then
                window.spellFilterSection.page = 1
                refreshFilters()
            end
            invalidateExport()
        end)
        row:Hide()
        rows[index] = row
    end

    local previousButton = addon.UIFactory.CreateButton(section, "<", theme.Sizes.pageButtonWidth)
    previousButton:SetPoint("BOTTOMLEFT", section, "BOTTOMLEFT", theme.Spacing.sm, theme.Spacing.xs)
    local pageLabel = addon.UIFactory.CreateLabel(section, theme.Fonts.small, "", theme.Colors.textMuted)
    pageLabel:SetPoint("LEFT", previousButton, "RIGHT", theme.Spacing.sm, 0)
    local nextButton = addon.UIFactory.CreateButton(section, ">", theme.Sizes.pageButtonWidth)
    nextButton:SetPoint("LEFT", pageLabel, "RIGHT", theme.Spacing.sm, 0)
    local clearButton = addon.UIFactory.CreateButton(section, addon.L("EXPORT_CLEAR_SELECTION"), theme.Sizes.exportClearButtonWidth)
    clearButton:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -theme.Spacing.sm, theme.Spacing.xs)
    local emptyLabel = addon.UIFactory.CreateLabel(section, theme.Fonts.small, addon.L("EXPORT_NO_FILTER_ITEMS"), theme.Colors.textMuted)
    emptyLabel:SetPoint("CENTER", section, "CENTER", 0, -theme.Spacing.sm)

    section.title = title
    section.modeButton = modeButton
    section.hint = hint
    section.rows = rows
    section.previousButton = previousButton
    section.nextButton = nextButton
    section.pageLabel = pageLabel
    section.emptyLabel = emptyLabel

    modeButton:SetScript("OnClick", function()
        local current = getFilterMode(section.kind)
        setFilterMode(section.kind, current == "blacklist" and "whitelist" or "blacklist")
        section.page = 1
        if section.kind == "tabs" then
            window.spellFilterSection.page = 1
        end
        refreshFilters()
        invalidateExport()
    end)
    clearButton:SetScript("OnClick", function()
        if section.kind == "tabs" then
            state.selectedTabs = {}
            window.spellFilterSection.page = 1
        else
            state.selectedSpells = {}
        end
        section.page = 1
        refreshFilters()
        invalidateExport()
    end)
    previousButton:SetScript("OnClick", function()
        section.page = section.page - 1
        renderFilterSection(section)
    end)
    nextButton:SetScript("OnClick", function()
        section.page = section.page + 1
        renderFilterSection(section)
    end)
    return section
end

generateExport = function()
    if not window or type(state.spellbook) ~= "table" then
        return
    end

    local option = addon.Constants.EXPORT_EXPIRATION_OPTIONS[state.expirationIndex]
    local options = {
        readOnly = true,
        includeOwner = window.ownerCheck:GetChecked() == true,
        expiresIn = option and option.seconds or 0,
        allowSpellCopy = window.copySpellCheck:GetChecked() == true,
        allowTabCopy = state.scope ~= "spell" and window.copyTabCheck:GetChecked() == true,
        tabFilterMode = state.tabFilterMode,
        tabSelection = state.selectedTabs,
        spellFilterMode = state.spellFilterMode,
        spellSelection = state.selectedSpells,
    }

    local exportString, errorMessage
    if state.scope == "spell" then
        exportString, errorMessage = addon.Export.ExportSpell(state.spellbook, state.spell, options)
    elseif state.scope == "tab" then
        exportString, errorMessage = addon.Export.ExportTab(state.spellbook, getActiveTab(), options)
    else
        exportString, errorMessage = addon.Export.ExportBook(state.spellbook, options)
    end
    if not exportString then
        setOutput("")
        setStatus(errorMessage or addon.L("EXPORT_FAILED"), true)
        return
    end

    setOutput(exportString)
    setStatus(addon.L("EXPORT_CREATED", #exportString), false)
end

local function createWindow()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("EXPORT_CONTENT_TITLE"),
        theme.Sizes.exportDialogWidth,
        theme.Sizes.exportDialogHeight
    )

    local typeLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, "", theme.Colors.textMuted)
    typeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -(theme.Spacing.xl + theme.Spacing.md))
    local subjectLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.header, "", theme.Colors.gold)
    subjectLabel:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -theme.Spacing.tiny)
    subjectLabel:SetWidth(theme.Sizes.exportDialogWidth - (theme.Spacing.lg * 2))
    subjectLabel:SetJustifyH("LEFT")
    subjectLabel:SetWordWrap(false)

    local scopeLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, addon.L("EXPORT_SCOPE"), theme.Colors.textMuted)
    scopeLabel:SetPoint("TOPLEFT", subjectLabel, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    local previousScope = addon.UIFactory.CreateButton(frame, "<", theme.Sizes.pageButtonWidth)
    previousScope:SetPoint("LEFT", scopeLabel, "RIGHT", theme.Spacing.md, 0)
    local scopeValue = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, "", theme.Colors.text)
    scopeValue:SetPoint("LEFT", previousScope, "RIGHT", theme.Spacing.sm, 0)
    scopeValue:SetWidth(theme.Sizes.exportScopeWidth)
    scopeValue:SetJustifyH("CENTER")
    local nextScope = addon.UIFactory.CreateButton(frame, ">", theme.Sizes.pageButtonWidth)
    nextScope:SetPoint("LEFT", scopeValue, "RIGHT", theme.Spacing.sm, 0)

    local ownerCheck, ownerLabel = createCheckOption(frame, addon.L("EXPORT_INCLUDE_OWNER"))

    local copySpellCheck, copySpellLabel = createCheckOption(frame, addon.L("EXPORT_ALLOW_SPELL_COPY"))
    copySpellCheck:SetPoint("TOPLEFT", ownerCheck, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    copySpellLabel:SetWidth(290)
    copySpellLabel:SetWordWrap(false)
    local copyTabCheck, copyTabLabel = createCheckOption(frame, addon.L("EXPORT_ALLOW_TAB_COPY"))
    copyTabCheck:SetPoint("TOPLEFT", ownerCheck, "BOTTOMLEFT", 350, -theme.Spacing.sm)
    copyTabLabel:SetWidth(290)
    copyTabLabel:SetWordWrap(false)

    local expirationLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, addon.L("EXPORT_EXPIRATION"), theme.Colors.textMuted)
    expirationLabel:SetPoint("TOPLEFT", copySpellCheck, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    local previousExpiration = addon.UIFactory.CreateButton(frame, "<", theme.Sizes.pageButtonWidth)
    previousExpiration:SetPoint("LEFT", expirationLabel, "RIGHT", theme.Spacing.md, 0)
    local expirationValue = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, "", theme.Colors.text)
    expirationValue:SetPoint("LEFT", previousExpiration, "RIGHT", theme.Spacing.sm, 0)
    expirationValue:SetWidth(theme.Sizes.exportScopeWidth)
    expirationValue:SetJustifyH("CENTER")
    local nextExpiration = addon.UIFactory.CreateButton(frame, ">", theme.Sizes.pageButtonWidth)
    nextExpiration:SetPoint("LEFT", expirationValue, "RIGHT", theme.Spacing.sm, 0)

    local filterFrame = CreateFrame("Frame", nil, frame)
    local tabFilterSection = createFilterSection(filterFrame, "tabs")
    tabFilterSection:SetPoint("TOPLEFT", filterFrame, "TOPLEFT", 0, 0)
    tabFilterSection:SetPoint("BOTTOMLEFT", filterFrame, "BOTTOMLEFT", 0, 0)
    tabFilterSection:SetWidth(theme.Sizes.exportTabFilterWidth)
    local spellFilterSection = createFilterSection(filterFrame, "spells")

    local generateButton = addon.UIFactory.CreateButton(frame, addon.L("GENERATE_EXPORT"), theme.Sizes.exportActionButtonWidth)
    local outputLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, addon.L("EXPORT_OUTPUT"), theme.Colors.gold)
    local output, outputContainer = addon.UIFactory.CreateTextArea(frame)
    if type(output.SetMaxBytes) == "function" then
        output:SetMaxBytes(addon.Constants.MAX_EXPORT_STRING_LENGTH)
    end

    local copyHint = addon.UIFactory.CreateLabel(frame, theme.Fonts.small, addon.L("EXPORT_COPY_HINT"), theme.Colors.textMuted)
    copyHint:SetPoint("TOPLEFT", outputContainer, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    copyHint:SetWidth(theme.Sizes.exportDialogWidth - (theme.Spacing.lg * 2))
    copyHint:SetJustifyH("LEFT")
    local selectButton = addon.UIFactory.CreateButton(frame, addon.L("SELECT_ALL"), theme.Sizes.exportActionButtonWidth)
    selectButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)
    local status = addon.UIFactory.CreateLabel(frame, theme.Fonts.small, "", theme.Colors.textMuted)
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", theme.Spacing.lg, theme.Spacing.lg)
    status:SetPoint("BOTTOMRIGHT", selectButton, "BOTTOMLEFT", -theme.Spacing.sm, 0)
    status:SetJustifyH("LEFT")

    frame.typeLabel = typeLabel
    frame.subjectLabel = subjectLabel
    frame.scopeLabel = scopeLabel
    frame.previousScope = previousScope
    frame.scopeValue = scopeValue
    frame.nextScope = nextScope
    frame.ownerCheck = ownerCheck
    frame.ownerLabel = ownerLabel
    frame.copySpellCheck = copySpellCheck
    frame.copySpellLabel = copySpellLabel
    frame.copyTabCheck = copyTabCheck
    frame.copyTabLabel = copyTabLabel
    frame.expirationLabel = expirationLabel
    frame.expirationValue = expirationValue
    frame.filterFrame = filterFrame
    frame.tabFilterSection = tabFilterSection
    frame.spellFilterSection = spellFilterSection
    frame.generateButton = generateButton
    frame.outputLabel = outputLabel
    frame.output = output
    frame.outputContainer = outputContainer
    frame.status = status

    local outputOnTextChanged = output:GetScript("OnTextChanged")
    output:SetScript("OnTextChanged", function(self, userInput)
        if self:GetText() ~= (frame.exportText or "") then
            self:SetText(frame.exportText or "")
            self:HighlightText()
            return
        end
        if type(outputOnTextChanged) == "function" then
            outputOnTextChanged(self, userInput)
        end
    end)
    output:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    output:SetScript("OnMouseUp", function(self) self:HighlightText() end)

    ownerCheck:SetScript("OnClick", handleCommonOptionChanged)
    copySpellCheck:SetScript("OnClick", handleCommonOptionChanged)
    copyTabCheck:SetScript("OnClick", handleCommonOptionChanged)
    previousScope:SetScript("OnClick", cycleScope)
    nextScope:SetScript("OnClick", cycleScope)
    previousExpiration:SetScript("OnClick", function() cycleExpiration(-1) end)
    nextExpiration:SetScript("OnClick", function() cycleExpiration(1) end)
    generateButton:SetScript("OnClick", generateExport)
    selectButton:SetScript("OnClick", function()
        if frame.exportText and frame.exportText ~= "" then
            output:SetFocus()
            output:HighlightText()
        end
    end)
    return frame
end

local function resetState(spellbook, scope, tabID, spell)
    state.spellbook = spellbook
    state.scope = scope
    state.tabID = tabID
    state.spell = spell
    state.expirationIndex = 1
    state.tabFilterMode = "blacklist"
    state.spellFilterMode = "blacklist"
    state.selectedTabs = {}
    state.selectedSpells = {}
end

local function openWindow()
    window = window or createWindow()
    window.ownerCheck:SetChecked(true)
    window.copySpellCheck:SetChecked(false)
    window.copyTabCheck:SetChecked(false)
    window.tabFilterSection.page = 1
    window.spellFilterSection.page = 1
    window.title:SetText(addon.L(state.scope == "spell" and "EXPORT_ABILITY_TITLE" or "EXPORT_CONTENT_TITLE"))
    updateExpiration()
    updateScopeLabels()
    layoutWindow()
    window:Show()
    addon.UIFactory.BringToFront(window)
    generateExport()
    return true
end

function addon.ExportWindow.OpenSpell(spellbook, spell)
    if type(spellbook) ~= "table" or type(spell) ~= "table" then
        addon.Logger.Error(addon.L("INVALID_ABILITY"))
        return false
    end
    resetState(spellbook, "spell", nil, spell)
    return openWindow()
end

function addon.ExportWindow.OpenTab(spellbook, tabID)
    local tab = type(spellbook) == "table" and type(spellbook.tabs) == "table" and spellbook.tabs[tabID] or nil
    if type(tab) ~= "table" then
        addon.Logger.Error(addon.L("TAB_NOT_FOUND"))
        return false
    end
    resetState(spellbook, "tab", tabID, nil)
    return openWindow()
end

function addon.ExportWindow.OpenBook(spellbook, activeTabID)
    local tab = type(spellbook) == "table" and type(spellbook.tabs) == "table" and spellbook.tabs[activeTabID] or nil
    if type(spellbook) ~= "table" or type(tab) ~= "table" then
        addon.Logger.Error(addon.L("ACTIVE_BOOK_UNAVAILABLE"))
        return false
    end
    resetState(spellbook, "book", activeTabID, nil)
    return openWindow()
end
