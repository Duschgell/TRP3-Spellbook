local _, addon = ...

addon.SpellbookPanel = {}

local FANCY_INSETS = {
    left = 76,
    right = 46,
    top = 34,
    bottom = 18,
}
local FANCY_OUTSET = {
    left = 4,
    right = 20,
    top = 20,
    bottom = 20,
}

local function shiftDown()
    return type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
end

local function altDown()
    return type(IsAltKeyDown) == "function" and IsAltKeyDown()
end

local function canArrange(panel)
    if panel.readOnly then return false end
    if panel.bookControlsEnabled then
        return altDown()
    end
    return panel.editMode == true
end

local function animate(panel, frame, kind, callback, direction)
    if panel.bookClosing and kind ~= "close" then return end
    if panel.fancyPresentation and addon.BookScene
        and (kind == "page" or kind == "open" or kind == "close") then
        return addon.BookScene.Play(panel, kind, callback, direction)
    end
    if panel.fancyPresentation and addon.BookAnimation then
        return addon.BookAnimation.Play(frame, kind, callback, direction)
    end
    if callback then callback() end
end

local function setButtonEnabled(button, enabled)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

local function setSlotAppearance(panel, slot, isTarget)
    local theme = addon.Theme
    local selected = panel.bulkSelection
        and slot.spellID
        and panel.bulkSelection[slot.spellID] == true
    local color = isTarget and theme.Colors.dropTarget
        or (selected and theme.Colors.danger)
        or (panel.editMode and theme.Colors.editSlot
            or (panel.activeTabThemeSpec and panel.activeTabThemeSpec.slotBorder)
            or theme.Colors.gridSlotBorder)
    slot:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
end

local function setBackdropColors(frame, background, border)
    if type(frame.SetBackdropColor) == "function" then
        frame:SetBackdropColor(
            background[1], background[2], background[3], background[4]
        )
    end
    if type(frame.SetBackdropBorderColor) == "function" then
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end

local function styleFancyButton(button, fancy)
    if addon.UIFactory and type(addon.UIFactory.ApplyButtonStyle) == "function" then
        addon.UIFactory.ApplyButtonStyle(
            button,
            fancy and "book" or "modern",
            fancy and nil or false
        )
    end
    if type(button.SetAlpha) == "function" then
        button:SetAlpha(fancy and 0.92 or 1)
    end
    local fontString = type(button.GetFontString) == "function"
        and button:GetFontString() or nil
    if addon.UIFactory and type(addon.UIFactory.ApplyBookFont) == "function" then
        addon.UIFactory.ApplyBookFont(fontString, false, 0)
    end
    if fontString and type(fontString.SetTextColor) == "function" then
        if fancy then
            fontString:SetTextColor(0.10, 0.045, 0.015, 1)
        else
            fontString:SetTextColor(1, 0.82, 0, 1)
        end
    end
end

local function styleSpellEntry(slot, fancy)
    local theme = addon.Theme
    slot.icon:ClearAllPoints()
    slot.name:ClearAllPoints()
    if fancy then
        slot.icon:SetSize(36, 36)
        slot.icon:SetPoint("LEFT", slot, "LEFT", theme.Spacing.xs, 0)
        slot.name:SetPoint(
            "TOPLEFT", slot.icon, "TOPRIGHT", theme.Spacing.sm + 2, -2
        )
        slot.name:SetPoint(
            "BOTTOMRIGHT", slot, "BOTTOMRIGHT", -theme.Spacing.xs, 4
        )
    else
        slot.icon:SetSize(theme.Sizes.iconLarge, theme.Sizes.iconLarge)
        slot.icon:SetPoint("LEFT", slot, "LEFT", theme.Spacing.xs, 0)
        slot.name:SetPoint(
            "TOPLEFT", slot.icon, "TOPRIGHT",
            theme.Spacing.sm, -theme.Spacing.xs
        )
        slot.name:SetPoint(
            "BOTTOMRIGHT", slot, "BOTTOMRIGHT",
            -theme.Spacing.xs, theme.Spacing.xs
        )
    end
    if slot.inkLine then
        slot.inkLine:Hide()
    end
    if addon.UIFactory and type(addon.UIFactory.ApplyBookFont) == "function" then
        addon.UIFactory.ApplyBookFont(slot.name, fancy, 2)
        addon.UIFactory.ApplyBookFont(slot.favorite, false, 0)
    end
    if slot.excerpt then slot.excerpt:Hide() end
    if slot.name.SetMaxLines then slot.name:SetMaxLines(0) end
    slot.name:SetJustifyV("MIDDLE")
    if not fancy then slot.bookLayout = nil end
    if not fancy and addon.BookLayout then
        addon.BookLayout.IconInk(slot.icon, false)
        addon.BookLayout.TextInk(slot.name, false)
        addon.BookLayout.TextInk(slot.excerpt, false)
    end
end

local function applyPanelPresentation(panel, fancy)
    local bookControls = not panel.archiveMode and not panel.readOnly
    if panel.fancyPresentation == fancy and panel.bookControlsEnabled == bookControls then
        return false
    end
    if addon.BookAnimation then
        addon.BookAnimation.Stop(panel)
        addon.BookAnimation.Stop(panel.content)
        addon.BookAnimation.Stop(panel.detailsView)
        addon.BookAnimation.Stop(panel.header)
    end
    if addon.BookScene then addon.BookScene.Stop(panel) end
    if addon.FancyBookControls then addon.FancyBookControls.Stop(panel) end
    if panel.cancelDrag then panel.cancelDrag() end
    panel.bookClosing = nil
    panel.fancyPresentation = fancy
    panel.bookControlsEnabled = bookControls
    if bookControls and panel.editMode then
        panel.editMode = false
        panel.bulkSelection = {}
        panel.searchBox:Enable()
        panel.arrangeHint:Hide()
        panel.arrangeButton:SetText(addon.L("ARRANGE"))
    end
    local theme = addon.Theme

    panel.header:ClearAllPoints()
    panel.bookSurface:ClearAllPoints()
    panel.title:ClearAllPoints()
    panel.profile:ClearAllPoints()
    panel.searchBox:ClearAllPoints()
    panel.newSpellButton:ClearAllPoints()
    panel.newTabButton:ClearAllPoints()
    panel.editTabButton:ClearAllPoints()
    panel.exportBookButton:ClearAllPoints()
    panel.copyTabButton:ClearAllPoints()
    panel.tabBar:ClearAllPoints()
    panel.content:ClearAllPoints()
    panel.favoriteFilterButton:ClearAllPoints()
    panel.bulkDeleteButton:ClearAllPoints()
    panel.nextPageButton:ClearAllPoints()
    panel.pageNumber:ClearAllPoints()
    panel.previousPageButton:ClearAllPoints()
    panel.detailsView:ClearAllPoints()

    if fancy then
        if panel.extendFancySurface then
            panel.bookSurface:SetPoint(
                "TOPLEFT", panel, "TOPLEFT",
                -FANCY_OUTSET.left, FANCY_OUTSET.top
            )
            panel.bookSurface:SetPoint(
                "BOTTOMRIGHT", panel, "BOTTOMRIGHT",
                FANCY_OUTSET.right, -FANCY_OUTSET.bottom
            )
        else
            panel.bookSurface:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
            panel.bookSurface:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        end
        panel.bookIcon:Hide()
        panel.title:SetPoint("TOPLEFT", panel.header, "TOPLEFT", 18, -4)
        panel.profile:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
        panel.header:SetPoint(
            "TOPLEFT", panel.bookSurface, "TOPLEFT",
            FANCY_INSETS.left, -FANCY_INSETS.top
        )
        panel.header:SetPoint(
            "TOPRIGHT", panel.bookSurface, "TOPRIGHT", -FANCY_INSETS.right,
            -FANCY_INSETS.top
        )
        panel.header:SetHeight(44)
        panel.searchBox:SetPoint("TOPLEFT", panel.header, "BOTTOMLEFT", 0, -8)
        panel.newSpellButton:SetPoint(
            "TOPLEFT", panel.searchBox, "BOTTOMLEFT", 0, -6
        )
        panel.newTabButton:SetPoint(
            "LEFT", panel.newSpellButton, "RIGHT", theme.Spacing.sm, 0
        )
        panel.editTabButton:SetPoint(
            "LEFT", panel.newTabButton, "RIGHT", theme.Spacing.sm, 0
        )
        panel.exportBookButton:SetPoint(
            "LEFT", panel.editTabButton, "RIGHT", theme.Spacing.sm, 0
        )
        panel.copyTabButton:SetPoint(
            "TOPLEFT", panel.searchBox, "BOTTOMLEFT", 0, -6
        )
        panel.tabBar:SetPoint("TOPLEFT", panel.newSpellButton, "BOTTOMLEFT", 0, -6)
        panel.tabBar:SetPoint(
            "TOPRIGHT", panel.bookSurface, "TOPRIGHT", -FANCY_INSETS.right, 0
        )
        panel.content:SetPoint("TOPLEFT", panel.searchBox, "BOTTOMLEFT", 0, -26)
        panel.content:SetPoint(
            "BOTTOMRIGHT", panel.bookSurface, "BOTTOMRIGHT",
            -FANCY_INSETS.right, 58
        )
        panel.favoriteFilterButton:SetPoint(
            "BOTTOMLEFT", panel.bookSurface, "BOTTOMLEFT",
            FANCY_INSETS.left, FANCY_INSETS.bottom
        )
        panel.bulkDeleteButton:SetPoint(
            "BOTTOMLEFT", panel.bookSurface, "BOTTOMLEFT",
            FANCY_INSETS.left, FANCY_INSETS.bottom
        )
        panel.nextPageButton:SetPoint(
            "BOTTOMRIGHT", panel.bookSurface, "BOTTOMRIGHT",
            -FANCY_INSETS.right, FANCY_INSETS.bottom
        )
        panel.pageNumber:SetPoint(
            "RIGHT", panel.nextPageButton, "LEFT", -theme.Spacing.sm, 0
        )
        panel.previousPageButton:SetPoint(
            "RIGHT", panel.pageNumber, "LEFT", -theme.Spacing.sm, 0
        )
        panel.detailsView:SetPoint(
            "TOPLEFT", panel.header, "BOTTOMLEFT", 0, -theme.Spacing.md
        )
        panel.detailsView:SetPoint(
            "BOTTOMRIGHT", panel.bookSurface, "BOTTOMRIGHT",
            -FANCY_INSETS.right, 46
        )
        setBackdropColors(panel.header, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
        setBackdropColors(panel.detailsView, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    else
        panel.bookSurface:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        panel.bookSurface:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        panel.bookIcon:Show()
        panel.title:SetPoint(
            "TOPLEFT", panel.bookIcon, "TOPRIGHT",
            theme.Spacing.md, -theme.Spacing.xs
        )
        panel.profile:SetPoint(
            "BOTTOMLEFT", panel.bookIcon, "BOTTOMRIGHT",
            theme.Spacing.md, theme.Spacing.xs
        )
        panel.header:SetPoint(
            "TOPLEFT", panel, "TOPLEFT", theme.Spacing.lg, -theme.Spacing.lg
        )
        panel.header:SetPoint(
            "TOPRIGHT", panel, "TOPRIGHT", -theme.Spacing.lg, -theme.Spacing.lg
        )
        panel.header:SetHeight(theme.Sizes.headerHeight)
        panel.searchBox:SetPoint(
            "TOPLEFT", panel.header, "BOTTOMLEFT", theme.Spacing.xs, -theme.Spacing.md
        )
        panel.newSpellButton:SetPoint(
            "LEFT", panel.searchBox, "RIGHT", theme.Spacing.sm, 0
        )
        panel.newTabButton:SetPoint(
            "LEFT", panel.newSpellButton, "RIGHT", theme.Spacing.sm, 0
        )
        panel.editTabButton:SetPoint(
            "LEFT", panel.newTabButton, "RIGHT", theme.Spacing.sm, 0
        )
        panel.exportBookButton:SetPoint(
            "LEFT", panel.editTabButton, "RIGHT", theme.Spacing.sm, 0
        )
        panel.copyTabButton:SetPoint(
            "LEFT", panel.searchBox, "RIGHT", theme.Spacing.sm, 0
        )
        panel.tabBar:SetPoint(
            "TOPLEFT", panel.searchBox, "BOTTOMLEFT", 0, -theme.Spacing.md
        )
        panel.tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -theme.Spacing.lg, 0)
        panel.content:SetPoint(
            "TOPLEFT", panel.tabBar, "BOTTOMLEFT", 0, -theme.Spacing.xs
        )
        panel.content:SetPoint(
            "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -theme.Spacing.lg, 46
        )
        panel.favoriteFilterButton:SetPoint(
            "TOPLEFT", panel.content, "BOTTOMLEFT", 0, -theme.Spacing.sm
        )
        panel.bulkDeleteButton:SetPoint(
            "TOPLEFT", panel.content, "BOTTOMLEFT", 0, -theme.Spacing.sm
        )
        panel.nextPageButton:SetPoint(
            "TOPRIGHT", panel.content, "BOTTOMRIGHT", 0, -theme.Spacing.sm
        )
        panel.pageNumber:SetPoint(
            "RIGHT", panel.nextPageButton, "LEFT", -theme.Spacing.sm, 0
        )
        panel.previousPageButton:SetPoint(
            "RIGHT", panel.pageNumber, "LEFT", -theme.Spacing.sm, 0
        )
        panel.detailsView:SetPoint(
            "TOPLEFT", panel.header, "BOTTOMLEFT", theme.Spacing.xs, -theme.Spacing.md
        )
        panel.detailsView:SetPoint(
            "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg
        )
        setBackdropColors(panel.header, theme.Colors.dark, theme.Colors.border)
        setBackdropColors(
            panel.detailsView, theme.Colors.parchmentDark, theme.Colors.border
        )
    end

    if bookControls and not fancy then
         
        panel.title:ClearAllPoints()
        panel.title:SetPoint("LEFT", panel.bookIcon, "RIGHT", theme.Spacing.md, 0)
        panel.content:ClearAllPoints()
        panel.content:SetPoint("TOPLEFT", panel.searchBox, "BOTTOMLEFT", 0, -theme.Spacing.md)
        panel.content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -theme.Spacing.lg, 46)
    end
    panel.profile:SetShown(not bookControls)
    if panel.title.SetJustifyH then panel.title:SetJustifyH(bookControls and "LEFT" or "CENTER") end
    if addon.FancyBookControls then addon.FancyBookControls.SetVisible(panel, bookControls) end
    for _, button in ipairs(panel.presentationButtons or {}) do
        styleFancyButton(button, fancy)
    end
    if addon.UIFactory and type(addon.UIFactory.ApplyBookFont) == "function" then
        addon.UIFactory.ApplyBookFont(panel.title, fancy, 3)
        addon.UIFactory.ApplyBookFont(panel.profile, false, 0)
        addon.UIFactory.ApplyBookFont(panel.searchBox, false, 0)
        addon.UIFactory.ApplyBookFont(panel.emptyState, fancy, 1)
        addon.UIFactory.ApplyBookFont(panel.pageNumber, false, 0)
        for _, button in ipairs(panel.tabButtons or {}) do
            addon.UIFactory.ApplyBookFont(button.label, false, 0)
        end
    end
    if addon.UIFactory and type(addon.UIFactory.ApplyBookFieldStyle) == "function" then
        addon.UIFactory.ApplyBookFieldStyle(panel.searchBox, fancy)
    end
    for _, slot in ipairs(panel.spellSlots or {}) do
        styleSpellEntry(slot, fancy)
    end
    return true
end

addon.SpellbookPanel.ApplyPresentation = applyPanelPresentation

local function getDetailThemeID(panel, spellID, spell)
    if panel.fancyPresentation or panel.readOnly or panel.archiveMode then return nil end
    local settings = addon.SpellCreationSettings
    if settings and settings.GetEditorTheme and settings.GetEditorTheme() == "dynamic" then
        local tags = type(spell.tags) == "table" and spell.tags or {}
        local constants = addon.Constants
        return select(2, addon.SpellCreationThemes.Resolve(
            "dynamic", addon.SpellPresentation.GetKind(tags),
            tags[constants.MAGIC_TAG_TYPE] or tags.Magieart,
            tags[constants.SPELL_TAG_DAMAGE_TYPE]
        ))
    end
     
    local book = panel.spellbook
    for _, tabID in ipairs(book.tabOrder or {}) do
        local tab = book.tabs[tabID]
        for _, id in ipairs(tab and tab.spellIds or {}) do
            if id == spellID then
                return tab.themeID ~= "fancy" and tab.themeID or "default"
            end
        end
    end
    return "default"
end

local function applyDetailTheme(panel, spellID, spell)
    if spell and addon.SpellDetailsView.ApplyTheme then
        addon.SpellDetailsView.ApplyTheme(
            panel.detailsView, panel.activeTabThemeSpec,
            panel.fancyPresentation == true, spell,
            getDetailThemeID(panel, spellID, spell)
        )
    end
end

local function applyActiveTabTheme(panel, tab)
    local previousMaxColumns = panel.activeTabThemeSpec
        and panel.activeTabThemeSpec.maxColumns
    local fancy = not panel.archiveMode and not panel.readOnly and addon.SpellCreationSettings
        and type(addon.SpellCreationSettings.IsFancyMode) == "function"
        and addon.SpellCreationSettings.IsFancyMode()
        or false
    local selectedTheme = fancy and "fancy" or (tab and tab.themeID or "default")
    if not fancy and selectedTheme == "fancy" then
        selectedTheme = "default"
    end
    local presentationChanged = applyPanelPresentation(panel, fancy)
    local animationToken = tostring(panel.activeTabID or "")
        .. ":" .. tostring(panel.currentPage or 1)
    local spec, themeID
    if fancy then
        addon.SpellCreationThemes.ClearBook(panel.content)
        panel.bookSurface:Show()
        spec, themeID = addon.SpellCreationThemes.ApplyBook(
            panel.bookSurface, selectedTheme, animationToken
        )
    else
        addon.SpellCreationThemes.ClearBook(panel.bookSurface)
        panel.bookSurface:Hide()
        spec, themeID = addon.SpellCreationThemes.ApplyBook(
            panel.content, selectedTheme, animationToken
        )
    end
    panel.activeTabThemeSpec = spec
    panel.activeTabThemeID = themeID
    if addon.BookNavigationStyle then addon.BookNavigationStyle.Refresh() end
    panel.emptyState:SetTextColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4])
    panel.pageNumber:SetTextColor(
        spec.textMuted[1], spec.textMuted[2], spec.textMuted[3], spec.textMuted[4]
    )
    panel.title:SetTextColor(spec.accent[1], spec.accent[2], spec.accent[3], spec.accent[4])
    panel.profile:SetTextColor(
        spec.textMuted[1], spec.textMuted[2], spec.textMuted[3], spec.textMuted[4]
    )
    if panel.bookControlsEnabled then
        local name = addon.TRP3Bridge.GetActiveCharacterFirstName()
        panel.title:SetText(addon.L("BOOK_OWNER_TITLE", name or addon.L("UNKNOWN")))
    else
        panel.title:SetText(panel.spellbook.name or addon.L("DEFAULT_BOOK_NAME"))
    end
    if panel.detailSpellID and addon.SpellDetailsView.ApplyTheme then
        local spell = panel.spellbook
            and panel.spellbook.spells
            and panel.spellbook.spells[panel.detailSpellID]
        applyDetailTheme(panel, panel.detailSpellID, spell)
    end
    if (presentationChanged or previousMaxColumns ~= spec.maxColumns)
        and panel.requestLayout
    then
        panel.requestLayout()
    end
end
local function createGridSlots(content)
    local theme = addon.Theme
    local slots = {}

    for index = 1, theme.Sizes.maxGridSlots do
        local slot = CreateFrame("Button", nil, content, "BackdropTemplate")
            slot:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            slot:SetBackdropColor(theme.Colors.gridSlot[1], theme.Colors.gridSlot[2], theme.Colors.gridSlot[3], theme.Colors.gridSlot[4])
            slot:SetBackdropBorderColor(theme.Colors.gridSlotBorder[1], theme.Colors.gridSlotBorder[2], theme.Colors.gridSlotBorder[3], theme.Colors.gridSlotBorder[4])
            slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            slot.slotIndex = index

            local icon = slot:CreateTexture(nil, "ARTWORK")
            icon:SetSize(theme.Sizes.iconLarge, theme.Sizes.iconLarge)
            icon:SetPoint("LEFT", slot, "LEFT", theme.Spacing.xs, 0)

            local name = addon.UIFactory.CreateLabel(slot, theme.Fonts.body, "", theme.Colors.text)
            name:SetPoint("TOPLEFT", icon, "TOPRIGHT", theme.Spacing.sm, -theme.Spacing.xs)
            name:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -theme.Spacing.xs, theme.Spacing.xs)
            name:SetJustifyH("LEFT")
            name:SetJustifyV("MIDDLE")
            name:SetWordWrap(true)

            local inkLine = slot:CreateTexture(nil, "BORDER")
            inkLine:SetColorTexture(0.22, 0.12, 0.05, 0.20)
            inkLine:SetPoint("BOTTOMLEFT", name, "BOTTOMLEFT", 0, -1)
            inkLine:SetPoint(
                "BOTTOMRIGHT", slot, "BOTTOMRIGHT", -theme.Spacing.xs, 3
            )
            inkLine:SetHeight(1)
            inkLine:Hide()

            local favorite = addon.UIFactory.CreateLabel(
                slot,
                theme.Fonts.body,
                "*",
                theme.Colors.gold
            )
            favorite:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -theme.Spacing.xs, -theme.Spacing.xs)
            favorite:Hide()

            slot.icon = icon
            slot.name = name
            slot.favorite = favorite
            slot.inkLine = inkLine
            slot.excerpt = addon.UIFactory.CreateLabel(slot, theme.Fonts.body, "")
            slot.excerpt:SetJustifyH("LEFT")
            slot.excerpt:SetJustifyV("TOP")
            slot.excerpt:SetWordWrap(true)
            slot.excerpt:SetTextColor(0.19, 0.095, 0.035, 1)
            slot.excerpt:SetShadowColor(0, 0, 0, 0)
            slot.excerpt:SetShadowOffset(0, 0)
            slot.excerpt:Hide()
            slot:Hide()
            slots[#slots + 1] = slot
    end

    return slots
end

local function layoutPanel(panel)
    local theme = addon.Theme
    local contentWidth = math.max(1, panel.content:GetWidth())
    local contentHeight = math.max(1, panel.content:GetHeight())
    local gridPadding = panel.fancyPresentation
        and theme.Spacing.xs or theme.Spacing.lg
    local availableWidth = math.max(1, contentWidth - (gridPadding * 2))
    local availableHeight = math.max(1, contentHeight - (gridPadding * 2))
    local maxColumns = panel.fancyPresentation and 2
        or theme.Sizes.gridColumns
    local columns = math.min(
        maxColumns,
        math.max(1, math.floor(
            (availableWidth + theme.Spacing.md)
                / (theme.Sizes.minSpellSlotWidth + theme.Spacing.md)
        ))
    )
    local rows = math.min(
        theme.Sizes.gridRows,
        math.max(1, math.floor(
            (availableHeight + theme.Spacing.sm)
                / (theme.Sizes.spellRowHeight + theme.Spacing.sm)
        ))
    )
    local capacity = columns * rows
    local slotWidth = math.max(
        1,
        (availableWidth - ((columns - 1) * theme.Spacing.md)) / columns
    )

    panel.gridColumns = columns
    panel.gridRows = rows
    panel.gridCapacity = capacity
    local bookLayout = panel.fancyPresentation and addon.BookLayout.Plan(availableWidth, availableHeight, columns, rows)

    if panel.title and panel.profile then
        local gameMasterWidth = panel.showGameMasterControl
            and (
                theme.Sizes.importLibraryButtonWidth
                + theme.Spacing.sm
            )
            or 0
        local compactWidth = panel.showCompactCombat
            and (
                theme.Sizes.importLibraryButtonWidth
                + theme.Spacing.sm
            )
            or 0
        local headerActionWidth = (panel.archiveMode or panel.bookControlsEnabled) and 0
            or (
                theme.Sizes.arrangeButtonWidth
                + gameMasterWidth
                + compactWidth
                + (theme.Spacing.sm * 2)
            )
        panel.compactButton:ClearAllPoints()
        panel.compactButton:SetPoint(
            "RIGHT",
            panel.showGameMasterControl and panel.gameMasterButton or panel.arrangeButton,
            "LEFT",
            -theme.Spacing.sm,
            0
        )
        local headerWidth = type(panel.header.GetWidth) == "function"
            and math.max(1, panel.header:GetWidth()) or panel:GetWidth()
        local iconWidth = panel.fancyPresentation and 0
            or (theme.Sizes.iconLarge + theme.Spacing.md)
        local headerTextWidth = math.max(
            theme.Sizes.searchMinWidth,
            headerWidth
                - iconWidth
                - headerActionWidth - (panel.fancyPresentation and 20 or 0)
        )
        panel.title:SetWidth(headerTextWidth)
        panel.profile:SetWidth(headerTextWidth)
        if addon.FancyBookControls then addon.FancyBookControls.UpdateTitleHitbox(panel) end
    end

    if panel.searchBox then
        if panel.bookControlsEnabled then
            local width = type(panel.header.GetWidth) == "function"
                and panel.header:GetWidth()
                or (panel:GetWidth() - 102)
            panel.searchBox:SetWidth(math.max(theme.Sizes.searchMinWidth, width))
        else
        local actionWidth = panel.archiveMode
            and (
                panel.allowTabCopy and (theme.Sizes.spellActionButtonWidth + theme.Spacing.sm) or 0
            )
            or (
            theme.Sizes.spellActionButtonWidth
                + theme.Sizes.tabCreateButtonWidth
                + theme.Sizes.tabActionButtonWidth
                + theme.Sizes.exportActionButtonWidth
                + (theme.Spacing.sm * 4)
        )
        local controlsWidth = panel:GetWidth() - (theme.Spacing.lg * 2) - theme.Spacing.xs
        panel.searchBox:SetWidth(math.max(theme.Sizes.searchMinWidth, controlsWidth - actionWidth))
        end
    end

    for index, slot in ipairs(panel.spellSlots) do
        slot:ClearAllPoints()
        if index <= capacity then
            local column = ((index - 1) % columns) + 1
            local row = math.floor((index - 1) / columns) + 1
            slot:SetSize(bookLayout and bookLayout.width or slotWidth,
                bookLayout and bookLayout.height or theme.Sizes.spellRowHeight)
            slot:SetPoint(
                "TOPLEFT",
                panel.content,
                "TOPLEFT",
                gridPadding + (bookLayout and (bookLayout.left + (column - 1) * bookLayout.columnPitch)
                    or ((column - 1) * (slotWidth + theme.Spacing.md))),
                -gridPadding - (bookLayout and (bookLayout.top + (row - 1) * bookLayout.rowPitch)
                    or ((row - 1) * (theme.Sizes.spellRowHeight + theme.Spacing.sm)))
            )
            if bookLayout then addon.BookLayout.Entry(slot, bookLayout) end
        else
            slot:Hide()
        end
    end
end
local function getFilteredSpellIDs(panel)
    return addon.Search.FindSpellIDs(
        panel.spellbook,
        panel.activeTabID,
        panel.searchBox:GetText(),
        { favoritesOnly = panel.favoritesOnly == true }
    )
end

local function showSpellTooltip(slot)
    local panel = slot.ownerPanel
    local spell = panel and panel.spellbook and panel.spellbook.spells[slot.spellID]
    local shown = addon.SpellTooltip.Show(slot, spell, panel and not panel.readOnly, "ANCHOR_RIGHT",
        { showChatHint = not panel.bookControlsEnabled })
    if shown and panel.bookControlsEnabled then
        GameTooltip:AddLine(addon.L("BOOK_MOVE_HINT"), 0.76, 0.69, 0.56, true)
        GameTooltip:Show()
    end
    return shown
end

local function insertSpellLink(panel, spellID)
    local spellbook = panel and panel.spellbook
    local spell = spellbook and spellbook.spells and spellbook.spells[spellID]
    if type(spellbook) ~= "table" or type(spell) ~= "table" then
        addon.Logger.Error(addon.L("ABILITY_NOT_FOUND"))
        return false
    end

    local success, errorMessage = addon.ChatInsert.InsertSpell(spellbook.profileKey, spell)
    if success and addon.Onboarding and addon.Onboarding.RecordAction then
        addon.Onboarding.RecordAction("share_large", spell.id, spellbook)
    end
    if not success then
        addon.Logger.Error(errorMessage or addon.L("CHAT_INSERT_FAILED"))
    end
    return success
end

local function whisperSpell(panel, spellID)
    local spellbook = panel and panel.spellbook
    local spell = spellbook
        and spellbook.spells
        and spellbook.spells[spellID]
        or nil
    if type(spell) ~= "table" then
        addon.Logger.Error(addon.L("ABILITY_NOT_FOUND"))
        return false
    end
    return addon.SpellWhisperDialog.Open(spell)
end

local function selectActiveTab(panel, requestedTabID)
    local spellbook = panel.spellbook
    if requestedTabID and spellbook.tabs[requestedTabID] then
        panel.activeTabID = requestedTabID
    elseif not spellbook.tabs[panel.activeTabID] then
        panel.activeTabID = spellbook.tabOrder[1]
    end
end

local function renderTabs(panel)
    if panel.bookControlsEnabled and addon.FancyBookControls then
        panel.tabBar:Hide()
        addon.FancyBookControls.RenderBookmarks(panel)
        return
    end
    local theme = addon.Theme
    local spellbook = panel.spellbook
    local tabCount = #spellbook.tabOrder
    local width = math.max(1, panel.tabBar:GetWidth())
    local withoutArrows = math.max(
        1,
        math.floor(
            (width + theme.Spacing.xs)
                / (theme.Sizes.tabButtonWidth + theme.Spacing.xs)
        )
    )
    local overflow = tabCount > withoutArrows
    local reserved = overflow
        and ((theme.Sizes.pageButtonWidth + theme.Spacing.xs) * 2) or 0
    local visibleCount = math.max(
        1,
        math.min(
            theme.Sizes.maxVisibleTabButtons,
            math.floor(
                (width - reserved + theme.Spacing.xs)
                    / (theme.Sizes.tabButtonWidth + theme.Spacing.xs)
            )
        )
    )
    panel.tabOffset = math.max(1, math.min(panel.tabOffset or 1, math.max(1, tabCount - visibleCount + 1)))
    if not panel.scrollingTabs then
        local activeIndex = 1
        for index, tabID in ipairs(spellbook.tabOrder) do
            if tabID == panel.activeTabID then activeIndex = index break end
        end
        if activeIndex < panel.tabOffset then panel.tabOffset = activeIndex end
        if activeIndex >= panel.tabOffset + visibleCount then panel.tabOffset = activeIndex - visibleCount + 1 end
    end
    panel.scrollingTabs = nil
    panel.previousTabButton:SetShown(overflow)
    panel.nextTabButton:SetShown(overflow)
    setButtonEnabled(panel.previousTabButton, overflow and panel.tabOffset > 1)
    setButtonEnabled(panel.nextTabButton, overflow and panel.tabOffset + visibleCount - 1 < tabCount)
    local anchor = overflow and panel.previousTabButton or panel.tabBar
    local anchorPoint = overflow and "RIGHT" or "LEFT"
    for buttonIndex, button in ipairs(panel.tabButtons) do
        local tabIndex = panel.tabOffset + buttonIndex - 1
        local tabID = buttonIndex <= visibleCount and spellbook.tabOrder[tabIndex] or nil
        button:ClearAllPoints()
        if tabID then
            local tab = spellbook.tabs[tabID]
            button.tabID = tabID
            button:SetPoint(
                "LEFT", anchor, anchorPoint, theme.Spacing.xs, 0
            )
            button:SetWidth(theme.Sizes.tabButtonWidth)
            button.label:SetText(tab and tab.name or "?")
            addon.UIFactory.SetIconTexture(button.icon, tab and tab.icon, addon.Constants.DEFAULT_TAB_ICON)
            if panel.fancyPresentation then
                button:SetBackdropColor(0, 0, 0, 0)
                local ink = panel.activeTabThemeSpec
                    and panel.activeTabThemeSpec.text
                    or { 0.18, 0.10, 0.045, 1 }
                button.label:SetTextColor(ink[1], ink[2], ink[3], ink[4])
            else
                local color = theme.Colors.parchmentDark
                button:SetBackdropColor(color[1], color[2], color[3], color[4])
                button.label:SetTextColor(
                    theme.Colors.text[1], theme.Colors.text[2],
                    theme.Colors.text[3], theme.Colors.text[4]
                )
            end
            if button.inkLine then
                button.inkLine:SetShown(panel.fancyPresentation)
                if panel.fancyPresentation then
                    local lineColor = tabID == panel.activeTabID
                        and panel.activeTabThemeSpec.accent
                        or { 0.22, 0.12, 0.05, 0.24 }
                    button.inkLine:SetColorTexture(
                        lineColor[1], lineColor[2], lineColor[3],
                        lineColor[4] or 1
                    )
                end
            end
            if panel.fancyPresentation then
                button:SetBackdropBorderColor(0, 0, 0, 0)
            elseif tabID == panel.activeTabID then
                local color = panel.activeTabThemeSpec and panel.activeTabThemeSpec.accent
                    or theme.Colors.gold
                button:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
            elseif panel.fancyPresentation then
                button:SetBackdropBorderColor(0.22, 0.12, 0.05, 0.16)
            else
                button:SetBackdropBorderColor(theme.Colors.border[1], theme.Colors.border[2], theme.Colors.border[3], 1)
            end
            button:Show()
            anchor = button
            anchorPoint = "RIGHT"
        else
            button.tabID = nil
            button:Hide()
        end
    end
end
local setListVisible
local function renderPanel(panel)
    local spellbook = panel.spellbook
    if type(spellbook) ~= "table" then
        return
    end

     
     
    local inscriptions = {}
    if addon.BookMagic then
        for _, slot in ipairs(panel.spellSlots) do
            inscriptions[slot] = addon.BookMagic.PauseInscription(slot)
        end
    end
    selectActiveTab(panel)
    local tab = spellbook.tabs[panel.activeTabID]
    applyActiveTabTheme(panel, tab)
    layoutPanel(panel)
    local filteredSpellIDs = getFilteredSpellIDs(panel)
    local canCreate = panel.bookControlsEnabled and not panel.readOnly and tab ~= nil
        and not panel.favoritesOnly and panel.searchBox:GetText() == "" and not panel.editMode
    local spellsPerPage = math.max(1, panel.gridCapacity or (addon.Theme.Sizes.gridColumns * addon.Theme.Sizes.gridRows))
    panel.spellsPerPage = spellsPerPage
    local pageCount = math.max(1, math.ceil(#filteredSpellIDs / spellsPerPage))
     
     
    local canAppendPage = canCreate and #filteredSpellIDs > 0 and #filteredSpellIDs % spellsPerPage == 0
    if canAppendPage and (panel.currentPage or 1) > pageCount then pageCount = pageCount + 1 end
    panel.canCopyActiveTab = panel.archiveMode
        and type(addon.ArchiveCopy) == "table"
        and addon.ArchiveCopy.CanCopyTab(spellbook, panel.activeTabID)
        or false
    panel.copyTabButton:SetShown(panel.canCopyActiveTab == true)
    panel.currentPage = math.max(1, math.min(panel.currentPage or 1, pageCount))
    renderTabs(panel)
    panel.pageNumber:SetText(addon.L("PAGE_FORMAT", panel.currentPage, pageCount))
    panel.emptyState:SetShown(#filteredSpellIDs == 0 and not canCreate)
    panel.emptyState:SetText(
        panel.favoritesOnly and addon.L("NO_FAVORITES")
            or (panel.searchBox:GetText() ~= ""
                and addon.L("NO_SEARCH_RESULTS") or addon.L("EMPTY_BOOK"))
    )

    local firstIndex = ((panel.currentPage - 1) * spellsPerPage) + 1
    local occupied = math.max(0, math.min(spellsPerPage, #filteredSpellIDs - firstIndex + 1))
    local placeholderIndex = canCreate and occupied < spellsPerPage and (occupied + 1)
    local placeholderSlot
    for slotIndex, slot in ipairs(panel.spellSlots) do
        if addon.FancyBookControls then addon.FancyBookControls.CancelInscription(slot) end
        if addon.BookMagic then addon.BookMagic.StopText(slot) end
        local targetIndex = firstIndex + slotIndex - 1
        local spellID = slotIndex <= spellsPerPage and filteredSpellIDs[targetIndex] or nil
        local spell = spellID and spellbook.spells[spellID]
        slot.ownerPanel = panel
        slot.targetIndex = slotIndex <= spellsPerPage and targetIndex or nil
        local slotColor = panel.activeTabThemeSpec
            and panel.activeTabThemeSpec.slotBackground
            or addon.Theme.Colors.gridSlot
        slot:SetBackdropColor(slotColor[1], slotColor[2], slotColor[3], slotColor[4])
        if type(slot.name.SetShadowColor) == "function"
            and type(slot.name.SetShadowOffset) == "function"
        then
            slot.name:SetShadowColor(0, 0, 0, 0)
            slot.name:SetShadowOffset(0, 0)
        end
        setSlotAppearance(panel, slot, false)
        if spell then
            slot.spellID = spellID
            slot.name:SetText(spell.name)
            if panel.fancyPresentation then
                slot.excerpt:SetText(addon.BookLayout.Excerpt(spell))
                addon.BookLayout.Entry(slot, slot.bookLayout)
            end
            addon.BookLayout.SetNameColor(
                slot.name,
                spell.nameColor,
                panel.activeTabThemeSpec.text,
                panel.fancyPresentation
            )
            addon.BookLayout.SetSpellIcon(
                slot.icon, spell, addon.Constants.DEFAULT_BOOK_ICON, true, panel.fancyPresentation
            )
            slot.favorite:SetShown(
                type(spellbook.favorites) == "table"
                    and spellbook.favorites[spellID] == true
            )
            slot:Show()
            if addon.BookMagic then
                addon.BookMagic.SetText(slot, slot.name, spell, panel.fancyPresentation, panel, slot.excerpt)
            end
        elseif canCreate and slotIndex == placeholderIndex then
            slot.spellID = nil
            slot.targetIndex = targetIndex
            slot:Hide()
            addon.UIFactory.ClearSpellIconEffectFrame(slot.icon)
            placeholderSlot = slot
        elseif panel.editMode and slotIndex <= spellsPerPage then
            slot.spellID = nil
            slot.name:SetText(addon.L("DROP_HERE"))
            slot.excerpt:Hide()
            addon.UIFactory.SetFontColor(
                slot.name,
                nil,
                panel.activeTabThemeSpec.textMuted
            )
            slot.icon:SetTexture(nil)
            addon.UIFactory.ClearSpellIconEffectFrame(slot.icon)
            slot.favorite:Hide()
            slot:Show()
        else
            slot.spellID = nil
            addon.UIFactory.ClearSpellIconEffectFrame(slot.icon)
            slot.favorite:Hide()
            slot:Hide()
        end
    end

    panel.createTargetIndex = placeholderSlot and placeholderSlot.targetIndex
    if addon.FancyBookControls then addon.FancyBookControls.Placeholder(panel, placeholderSlot) end
    if setListVisible then setListVisible(panel, not panel.detailSpellID) end
    if addon.BookMagic then
        for slot, snapshot in pairs(inscriptions) do addon.BookMagic.ResumeInscription(slot, snapshot) end
    end
    setButtonEnabled(panel.previousPageButton, panel.currentPage > 1)
    setButtonEnabled(panel.nextPageButton, panel.currentPage < pageCount or (canAppendPage and occupied == spellsPerPage))
    setButtonEnabled(panel.arrangeButton, not panel.readOnly and tab ~= nil)
    setButtonEnabled(panel.newSpellButton, not panel.readOnly and tab ~= nil)
    setButtonEnabled(panel.newTabButton, not panel.readOnly)
    setButtonEnabled(panel.editTabButton, not panel.readOnly and tab ~= nil)
    setButtonEnabled(panel.exportBookButton, not panel.readOnly and tab ~= nil)
    setButtonEnabled(panel.copyTabButton, panel.canCopyActiveTab == true)
end

setListVisible = function(panel, visible)
    for _, region in ipairs(panel.listRegions or {}) do
        local hiddenByArchive = panel.archiveMode
            and panel.archiveHiddenRegions
            and panel.archiveHiddenRegions[region]
        local hiddenArrangeHint = region == panel.arrangeHint and not panel.editMode
        local hiddenGameMaster = region == panel.gameMasterButton
            and not panel.showGameMasterControl
        local hiddenCompact = region == panel.compactButton
            and not panel.showCompactCombat
        local hiddenArchiveCopy = region == panel.copyTabButton
            and panel.canCopyActiveTab ~= true
        local hiddenBulkDelete = region == panel.bulkDeleteButton
            and not panel.editMode
        local hiddenFavoriteFilter = region == panel.favoriteFilterButton
            and (panel.editMode or panel.readOnly or panel.fancyPresentation)
        local hiddenBookControl = panel.bookControlsEnabled and panel.bookHiddenRegions
            and panel.bookHiddenRegions[region]
        region:SetShown(
            visible and not hiddenByArchive and not hiddenArrangeHint
                and not hiddenGameMaster and not hiddenCompact
                and not hiddenArchiveCopy and not hiddenBulkDelete
                and not hiddenFavoriteFilter
                and not hiddenBookControl and region ~= panel.libraryButton
        )
    end
    if addon.FancyBookControls then
        addon.FancyBookControls.SetVisible(panel, panel.bookControlsEnabled == true)
    end
end


local function populateDetail(panel, spellID, spell)
    addon.SpellDetailsView.SetSpell(
        panel.detailsView,
        spell,
        not panel.readOnly,
        not panel.readOnly and addon.GameMasterService.CanSubmit(),
        panel.archiveMode and addon.ArchiveCopy
            and addon.ArchiveCopy.CanCopySpell(panel.spellbook, spellID),
        not panel.readOnly and addon.Database.IsSpellFavorite(spellID)
    )
    applyDetailTheme(panel, spellID, spell)
end

local function showDetail(panel, spellID, zoomed)
    local spell = panel.spellbook and panel.spellbook.spells[spellID]
    if type(spell) ~= "table" then
        addon.Logger.Error(addon.L("ABILITY_NOT_FOUND"))
        return false
    end
    if panel.fancyPresentation and addon.BookScene and not zoomed and not panel.detailSpellID then
        return addon.BookScene.Zoom(panel, spellID, function() showDetail(panel, spellID, true) end,
            function()
                populateDetail(panel, spellID, spell)
                return panel.detailsView
            end)
    end
    panel.detailSpellID = spellID
    if addon.BookAnimation then addon.BookAnimation.Stop(panel.detailsView) end
    setListVisible(panel, false)
    panel.detailsView:Show()
    populateDetail(panel, spellID, spell)
    if zoomed and addon.SpellDetailsView.RevealReading then addon.SpellDetailsView.RevealReading(panel.detailsView) end
    GameTooltip:Hide()
    return true
end

local function toggleDetailFavorite(panel)
    local spellID = panel.detailSpellID
    if not spellID or panel.readOnly then
        return
    end
    local changed, value = addon.Database.ToggleSpellFavorite(spellID)
    if not changed then
        addon.Logger.Error(value or addon.L("ABILITY_NOT_FOUND"))
        return
    end
    showDetail(panel, spellID)
end

local function closeDetail(panel)
    local function finish()
        panel.detailSpellID = nil
        panel.detailsView:Hide()
        setListVisible(panel, true)
        renderPanel(panel)
    end
    if panel.fancyPresentation and addon.BookScene then
        addon.BookScene.Unzoom(panel, finish)
    else
        finish()
    end
end
local function refreshFromDatabase(panel, requestedTabID, preservePage)
    if addon.BookScene then addon.BookScene.Stop(panel) end
    local spellbook = addon.Database.GetActiveSpellbook()
    if not spellbook then
        return
    end

    panel.detailSpellID = nil
    panel.detailsView:Hide()
    setListVisible(panel, true)
    panel.spellbook = spellbook
    panel.readOnly = false
    selectActiveTab(panel, requestedTabID)
    panel.currentPage = preservePage and panel.currentPage or 1
    renderPanel(panel)
end

local function exportDetailSpell(panel)
    local spellID = panel.detailSpellID
    local spell = spellID and panel.spellbook and panel.spellbook.spells[spellID]
    if type(spell) ~= "table" or panel.readOnly then
        return
    end
    addon.ExportWindow.OpenSpell(panel.spellbook, spell)
end

local function deleteBookSpell(panel, spellID, onCancel)
    local spell = spellID and panel.spellbook and panel.spellbook.spells[spellID]
    if type(spell) ~= "table" or panel.readOnly then
        return
    end
    if panel.deleteConfirmation or (panel.bookBurn and panel.bookBurn.playing) then return end

    local book = panel.spellbook
    local tabID = panel.activeTabID
    local token = {}
    panel.deleteConfirmation = token
    local function ownsBook()
        return panel.spellbook == book and addon.Database.GetActiveSpellbook() == book
            and not panel.readOnly
    end
    local function acceptConfirmation()
        if panel.deleteConfirmation ~= token then return false end
        panel.deleteConfirmation = nil
        if not ownsBook() then return false end
        if book.spells[spellID] ~= spell then
            if book.spells[spellID] and panel.detailSpellID == spellID then
                showDetail(panel, spellID)
            elseif not panel.detailSpellID or panel.detailSpellID == spellID then
                refreshFromDatabase(panel, tabID, true)
            end
            return false
        end
        return true
    end
     
     
    addon.UIFactory.ShowConfirmation(
        addon.L("DELETE_ABILITY_TITLE"),
        addon.L("DELETE_ABILITY_CONFIRM", spell.name or addon.L("UNKNOWN_ABILITY")),
        function()
            if not acceptConfirmation() then return end
            local source
            if panel.detailSpellID == spellID and panel.detailsView:IsVisible() then
                source = panel.detailsView
            elseif not panel.detailSpellID then
                for _, slot in ipairs(panel.spellSlots) do
                    if slot.spellID == spellID and slot:IsVisible() then source = slot; break end
                end
            end
            local deleted, errorMessage = addon.Database.DeleteSpell(spellID)
            if not deleted then
                if onCancel then onCancel() end
                addon.Logger.Error(errorMessage)
                return
            end
            local function finish()
                if not ownsBook() then return end
                if panel.detailSpellID and panel.detailSpellID ~= spellID then return end
                refreshFromDatabase(panel, panel.activeTabID, true)
            end
            if source and panel.fancyPresentation and addon.BookMagic then
                addon.BookMagic.Burn(panel, source, finish)
            else
                finish()
            end
        end,
        function()
            if acceptConfirmation() and onCancel then onCancel() end
        end
    )
end

local function editBookSpell(panel, spellID)
    if not spellID or panel.readOnly then return end
    local book, spell, reading = panel.spellbook, panel.spellbook.spells[spellID], panel.detailSpellID == spellID
    local function ownsSpell()
        return panel.spellbook == book and addon.Database.GetActiveSpellbook() == book
            and not panel.readOnly and book.spells[spellID] == spell
    end
    addon.SpellEditorWindow.OpenEdit(spellID, function(tabID)
        if panel.spellbook ~= book or addon.Database.GetActiveSpellbook() ~= book then return end
        refreshFromDatabase(panel, tabID)
        if reading and panel.spellbook.spells[spellID] then showDetail(panel, spellID) end
    end, nil, function(onCancel)
        if ownsSpell() then deleteBookSpell(panel, spellID, onCancel) end
    end)
end


local function setEditMode(panel, enabled)
    panel.editMode = enabled == true
    panel.bulkSelection = {}
    panel.favoritesOnly = false
    panel.arrangeButton:SetText(panel.editMode and addon.L("DONE") or addon.L("ARRANGE"))
    if panel.editMode then
        panel.searchBox:SetText("")
        panel.searchBox:Disable()
        panel.arrangeHint:Show()
    else
        panel.searchBox:Enable()
        panel.arrangeHint:Hide()
    end
    panel.currentPage = 1
    renderPanel(panel)
    panel.bulkDeleteButton:SetShown(panel.editMode)
    panel.favoriteFilterButton:SetShown(not panel.editMode and not panel.readOnly)
end

local function getSelectedSpellIDs(panel)
    local result = {}
    for spellID, selected in pairs(panel.bulkSelection or {}) do
        if selected and panel.spellbook.spells[spellID] then
            result[#result + 1] = spellID
        end
    end
    table.sort(result)
    return result
end

local function deleteSelectedSpells(panel)
    local spellIDs = getSelectedSpellIDs(panel)
    if #spellIDs == 0 then
        addon.Logger.Info(addon.L("BULK_DELETE_EMPTY"))
        return
    end
    addon.UIFactory.ShowConfirmation(
        addon.L("BULK_DELETE_TITLE"),
        addon.L("BULK_DELETE_CONFIRM", #spellIDs),
        function()
            local deleted, errorMessage = addon.Database.DeleteSpells(spellIDs)
            if not deleted then
                addon.Logger.Error(errorMessage)
                return
            end
            panel.bulkSelection = {}
            refreshFromDatabase(panel, panel.activeTabID)
            setEditMode(panel, true)
        end
    )
end

local function finishSpellDrag(panel)
    local sourceSlot = panel.dragSourceSlot
    local targetSlot = panel.dragTargetSlot
    local targetTabID = panel.dragTargetTabID
    local spellID = panel.draggedSpellID
    panel.dragSourceSlot = nil
    panel.dragTargetSlot = nil
    panel.draggedSpellID = nil
    panel.dragTargetTabID = nil
    if sourceSlot then sourceSlot:SetAlpha(1) end
    if not spellID then return end
    local activeBook = addon.Database.GetActiveSpellbook()
    if panel.readOnly or not activeBook or activeBook.id ~= panel.bookID then return end
    if panel.bookControlsEnabled and not altDown() then renderPanel(panel) return end
    local snapshot = panel.fancyPresentation and addon.BookAnimation.Capture(panel.spellSlots, "spellID")
    local destinationTabID = targetTabID or panel.activeTabID
    local targetIndex = targetTabID and nil or (targetSlot and targetSlot.targetIndex)
    if panel.bookControlsEnabled and not targetTabID and targetSlot and targetSlot.spellID then
         
        destinationTabID = addon.Database.GetSpellTabID(targetSlot.spellID)
        local destination = destinationTabID and activeBook.tabs[destinationTabID]
        if not destination then return end
        for index, id in ipairs(destination.spellIds) do
            if id == targetSlot.spellID then targetIndex = index break end
        end
    end
    if not targetTabID and not targetIndex then return end
    local moved, errorMessage = addon.Database.MoveSpell(spellID, destinationTabID, targetIndex)
    if not moved then addon.Logger.Error(errorMessage) return end
    panel.spellbook = addon.Database.GetActiveSpellbook()
    if targetTabID then
        panel.activeTabID = targetTabID
        local targetTab = panel.spellbook.tabs[targetTabID]
        panel.currentPage = math.max(1, math.ceil(#targetTab.spellIds / math.max(1, panel.spellsPerPage or 1)))
    end
    renderPanel(panel)
    if snapshot then addon.BookAnimation.Reflow(panel.spellSlots, snapshot, "spellID") end
    panel.suppressSpellClick = true
    C_Timer.After(0, function() panel.suppressSpellClick = nil end)
end

local function finishTabDrag(panel)
    local sourceButton = panel.dragSourceTabButton
    local targetButton = panel.dragTargetTabButton
    local sourceTabID = panel.draggedTabID
    local targetTabID = targetButton and targetButton.tabID

    panel.dragSourceTabButton = nil
    panel.dragTargetTabButton = nil
    panel.draggedTabID = nil
    if sourceButton then
        sourceButton:SetAlpha(1)
    end
    local activeBook = addon.Database.GetActiveSpellbook()
    if panel.readOnly or not activeBook or activeBook.id ~= panel.bookID then return end
    if panel.bookControlsEnabled and not altDown() then renderTabs(panel) return end
    local bookmarks = panel.fancyControls and panel.fancyControls.bookmarks
    local snapshot = panel.fancyPresentation and addon.BookAnimation.Capture(bookmarks, "tabID")

    panel.suppressTabClick = true
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            panel.suppressTabClick = nil
        end)
    else
        panel.suppressTabClick = nil
    end

    if not sourceTabID or not targetTabID or sourceTabID == targetTabID then
        renderTabs(panel)
        return
    end

    local targetIndex
    for index, tabID in ipairs(panel.spellbook.tabOrder) do
        if tabID == targetTabID then
            targetIndex = index
            break
        end
    end
    if not targetIndex then
        renderTabs(panel)
        return
    end

    local moved, errorMessage = addon.Database.MoveTab(sourceTabID, targetIndex)
    if not moved then
        addon.Logger.Error(errorMessage)
    end
    panel.spellbook = addon.Database.GetActiveSpellbook()
    renderPanel(panel)
    if snapshot then addon.BookAnimation.Reflow(bookmarks, snapshot, "tabID") end
end

local function cycleTab(panel, direction)
    local spellbook = panel.spellbook
    if not spellbook or #spellbook.tabOrder == 0 then
        return
    end

    local currentIndex = 1
    for index, tabID in ipairs(spellbook.tabOrder) do
        if tabID == panel.activeTabID then
            currentIndex = index
            break
        end
    end
    currentIndex = currentIndex + direction
    if currentIndex < 1 then
        currentIndex = #spellbook.tabOrder
    elseif currentIndex > #spellbook.tabOrder then
        currentIndex = 1
    end
    panel.activeTabID = spellbook.tabOrder[currentIndex]
    panel.currentPage = 1
    renderPanel(panel)
end

local function getActiveProfileLabel()
    local profileName = addon.TRP3Bridge.GetActiveProfileName()
    return addon.L("PROFILE_PREFIX") .. (profileName or addon.L("UNKNOWN"))
end

local function getImportedProfileLabel(book)
    local owner = addon.Import.GetOwnerDisplayName(book and book.owner)
    local parts = { addon.L("IMPORTED_FROM_FORMAT", owner), addon.L("IMPORTED_CONTENT_VIEW_ONLY") }
    if addon.Database.IsImportedBookExpired(book) then
        parts[#parts + 1] = addon.L("IMPORT_EXPIRED")
    elseif type(book) == "table" and tonumber(book.expiresAt) and tonumber(book.expiresAt) > 0 then
        local expiresAt = tonumber(book.expiresAt)
        local value = tostring(expiresAt)
        if type(date) == "function" then
            local success, result = pcall(date, "%Y-%m-%d %H:%M", expiresAt)
            if success and type(result) == "string" then
                value = result
            end
        end
        parts[#parts + 1] = addon.L("IMPORT_EXPIRES_AT", value)
    end
    return table.concat(parts, " • ")
end

local function openImportedBook(panel, book)
    if type(book) ~= "table" then return end
    addon.SpellbookPanel.Refresh(panel, book, getImportedProfileLabel(book))
end

local function openOwnBook(panel)
    local spellbook = addon.Database.GetActiveSpellbook()
    if not spellbook then
        addon.Logger.Error(addon.L("ACTIVE_BOOK_UNAVAILABLE"))
        return
    end
    addon.SpellbookPanel.Refresh(panel, spellbook, getActiveProfileLabel())
end

function addon.SpellbookPanel.Create(parent, options)
    local theme = addon.Theme
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.extendFancySurface = type(options) == "table"
        and options.extendFancySurface == true

    local bookSurface = addon.UIFactory.CreateBackdropFrame(
        panel,
        { 0, 0, 0, 0 },
        { 0, 0, 0, 0 }
    )
    bookSurface:SetAllPoints(panel)
    if type(bookSurface.SetClipsChildren) == "function" then
        bookSurface:SetClipsChildren(true)
    end
    bookSurface.bookAnimationManaged = true
    bookSurface:Hide()

    local header = addon.UIFactory.CreateBackdropFrame(panel, theme.Colors.dark, theme.Colors.border)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", theme.Spacing.lg, -theme.Spacing.lg)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -theme.Spacing.lg, -theme.Spacing.lg)
    header:SetHeight(theme.Sizes.headerHeight)
    if type(header.SetClipsChildren) == "function" then
        header:SetClipsChildren(true)
    end

    local bookIcon = header:CreateTexture(nil, "ARTWORK")
    bookIcon:SetSize(theme.Sizes.iconLarge, theme.Sizes.iconLarge)
    bookIcon:SetPoint("LEFT", header, "LEFT", theme.Spacing.sm, 0)

    local title = addon.UIFactory.CreateLabel(header, theme.Fonts.header, "", theme.Colors.gold)
    title:SetPoint("TOPLEFT", bookIcon, "TOPRIGHT", theme.Spacing.md, -theme.Spacing.xs)

    local profile = addon.UIFactory.CreateLabel(header, theme.Fonts.small, "", theme.Colors.textMuted)
    profile:SetPoint("BOTTOMLEFT", bookIcon, "BOTTOMRIGHT", theme.Spacing.md, theme.Spacing.xs)
    profile:SetWordWrap(false)
    title:SetWordWrap(false)
    if type(profile.SetMaxLines) == "function" then
        profile:SetMaxLines(1)
    end
    if type(title.SetMaxLines) == "function" then
        title:SetMaxLines(1)
    end

    local arrangeButton = addon.UIFactory.CreateButton(header, addon.L("ARRANGE"), theme.Sizes.arrangeButtonWidth)
    arrangeButton:SetPoint("RIGHT", header, "RIGHT", -theme.Spacing.sm, 0)

    local libraryButton = addon.UIFactory.CreateButton(header, addon.L("IMPORT_ARCHIVE"), theme.Sizes.importLibraryButtonWidth)
    libraryButton:SetPoint("RIGHT", arrangeButton, "LEFT", -theme.Spacing.sm, 0)
    libraryButton:Hide()

    local gameMasterButton = addon.UIFactory.CreateButton(
        header,
        addon.L("GAMEMASTER_CONTROL"),
        theme.Sizes.importLibraryButtonWidth
    )
    gameMasterButton:SetPoint("RIGHT", arrangeButton, "LEFT", -theme.Spacing.sm, 0)
    gameMasterButton:Hide()

    local compactButton = addon.UIFactory.CreateButton(
        header,
        addon.L("GAMEMASTER_COMPACT_BUTTON"),
        theme.Sizes.importLibraryButtonWidth
    )
    compactButton:SetPoint("RIGHT", gameMasterButton, "LEFT", -theme.Spacing.sm, 0)
    compactButton:Hide()

    local arrangeHint = addon.UIFactory.CreateLabel(header, theme.Fonts.small, addon.L("DRAG_ACTIVE"), theme.Colors.gold)
    arrangeHint:SetPoint("RIGHT", compactButton, "LEFT", -theme.Spacing.sm, 0)
    arrangeHint:Hide()

    local searchBox = addon.UIFactory.CreateSearchBox(panel)
    searchBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", theme.Spacing.xs, -theme.Spacing.md)
    searchBox:SetWidth(theme.Sizes.searchWidth)

    local newSpellButton = addon.UIFactory.CreateButton(panel, addon.L("NEW_ABILITY"), theme.Sizes.spellActionButtonWidth)
    newSpellButton:SetPoint("LEFT", searchBox, "RIGHT", theme.Spacing.sm, 0)

    local newTabButton = addon.UIFactory.CreateButton(panel, addon.L("NEW_TAB"), theme.Sizes.tabCreateButtonWidth)
    newTabButton:SetPoint("LEFT", newSpellButton, "RIGHT", theme.Spacing.sm, 0)

    local editTabButton = addon.UIFactory.CreateButton(panel, addon.L("EDIT_TAB"), theme.Sizes.tabActionButtonWidth)
    editTabButton:SetPoint("LEFT", newTabButton, "RIGHT", theme.Spacing.sm, 0)

    local exportBookButton = addon.UIFactory.CreateButton(panel, addon.L("EXPORT"), theme.Sizes.exportActionButtonWidth)
    exportBookButton:SetPoint("LEFT", editTabButton, "RIGHT", theme.Spacing.sm, 0)

    local copyTabButton = addon.UIFactory.CreateButton(panel, addon.L("ARCHIVE_COPY_TAB"), theme.Sizes.spellActionButtonWidth)
    copyTabButton:SetPoint("LEFT", searchBox, "RIGHT", theme.Spacing.sm, 0)
    copyTabButton:Hide()

    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -theme.Spacing.md)
    tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -theme.Spacing.lg, 0)
    tabBar:SetHeight(theme.Sizes.tabHeight)

    local previousTabButton = addon.UIFactory.CreateButton(tabBar, "<", theme.Sizes.pageButtonWidth)
    previousTabButton:SetPoint("LEFT", tabBar, "LEFT", 0, 0)

    local nextTabButton = addon.UIFactory.CreateButton(tabBar, ">", theme.Sizes.pageButtonWidth)
    nextTabButton:SetPoint("RIGHT", tabBar, "RIGHT", 0, 0)

    local tabButtons = {}
    for index = 1, theme.Sizes.maxVisibleTabButtons do
        local button = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        button:SetSize(theme.Sizes.tabButtonWidth, theme.Sizes.tabHeight)
        button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        button:SetBackdropColor(theme.Colors.parchmentDark[1], theme.Colors.parchmentDark[2], theme.Colors.parchmentDark[3], theme.Colors.parchmentDark[4])
        button:SetBackdropBorderColor(theme.Colors.gold[1], theme.Colors.gold[2], theme.Colors.gold[3], theme.Colors.gold[4])
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(theme.Sizes.tabIcon, theme.Sizes.tabIcon)
        icon:SetPoint("LEFT", button, "LEFT", theme.Spacing.xs, 0)
        local label = addon.UIFactory.CreateLabel(button, theme.Fonts.body, "", theme.Colors.text)
        label:SetPoint("LEFT", icon, "RIGHT", theme.Spacing.xs, 0)
        label:SetPoint("RIGHT", button, "RIGHT", -theme.Spacing.xs, 0)
        label:SetJustifyH("CENTER")
        local inkLine = button:CreateTexture(nil, "BORDER")
        inkLine:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 5, 1)
        inkLine:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 1)
        inkLine:SetHeight(1)
        inkLine:SetColorTexture(0.22, 0.12, 0.05, 0.24)
        inkLine:Hide()
        button.icon = icon
        button.inkLine = inkLine
        button.label = label
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnClick", function(self)
            if panel.suppressTabClick then
                return
            end
            if self.tabID then
                panel.activeTabID = self.tabID
                panel.currentPage = 1
                renderPanel(panel)
            end
        end)
        button:SetScript("OnEnter", function(self)
            if panel.draggedSpellID then
                panel.dragTargetTabID = self.tabID
                local color = theme.Colors.dropTarget
                self:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
            elseif panel.draggedTabID and self.tabID ~= panel.draggedTabID then
                panel.dragTargetTabButton = self
                local color = theme.Colors.dropTarget
                self:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
            end
        end)
        button:SetScript("OnLeave", function(self)
            if panel.dragTargetTabID == self.tabID then panel.dragTargetTabID = nil end
            if panel.dragTargetTabButton == self then panel.dragTargetTabButton = nil end
            local color = self.tabID == panel.activeTabID
                and panel.activeTabThemeSpec
                and panel.activeTabThemeSpec.accent
                or (panel.fancyPresentation and { 0.22, 0.12, 0.05, 0.16 })
                or theme.Colors.border
            self:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
        end)
        button:SetScript("OnDragStart", function(self)
            if panel.editMode and not panel.readOnly and self.tabID then
                panel.draggedTabID = self.tabID
                panel.dragSourceTabButton = self
                panel.dragTargetTabButton = self
                self:SetAlpha(0.45)
            end
        end)
        button:SetScript("OnDragStop", function()
            finishTabDrag(panel)
        end)
        button:Hide()
        tabButtons[index] = button
    end
    local content = addon.UIFactory.CreateBackdropFrame(panel, theme.Colors.parchment, theme.Colors.border)
    content:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -theme.Spacing.lg, 46)
    panel.content = content
    panel.spellSlots = createGridSlots(content)

    local emptyState = addon.UIFactory.CreateLabel(content, theme.Fonts.body, addon.L("EMPTY_BOOK"), theme.Colors.text)
    emptyState:SetPoint("CENTER")

    local nextPageButton = addon.UIFactory.CreateButton(panel, ">", theme.Sizes.pageButtonWidth)
    nextPageButton:SetPoint("TOPRIGHT", content, "BOTTOMRIGHT", 0, -theme.Spacing.sm)

    local pageNumber = addon.UIFactory.CreateLabel(panel, theme.Fonts.body, addon.L("PAGE_NUMBER"), theme.Colors.textMuted)
    pageNumber:SetPoint("RIGHT", nextPageButton, "LEFT", -theme.Spacing.sm, 0)

    local previousPageButton = addon.UIFactory.CreateButton(panel, "<", theme.Sizes.pageButtonWidth)
    previousPageButton:SetPoint("RIGHT", pageNumber, "LEFT", -theme.Spacing.sm, 0)

    local favoriteFilterButton = addon.UIFactory.CreateButton(
        panel,
        addon.L("FAVORITES_ONLY"),
        120
    )
    favoriteFilterButton:SetPoint("TOPLEFT", content, "BOTTOMLEFT", 0, -theme.Spacing.sm)

    local bulkDeleteButton = addon.UIFactory.CreateButton(
        panel,
        addon.L("BULK_DELETE"),
        150
    )
    bulkDeleteButton:SetPoint("TOPLEFT", content, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    bulkDeleteButton:Hide()

    local detailsView = addon.SpellDetailsView.Create(panel, {
        onBack = function()
            closeDetail(panel)
        end,
        onEdit = function()
            editBookSpell(panel, panel.detailSpellID)
        end,
        onDelete = function()
            deleteBookSpell(panel, panel.detailSpellID)
        end,
        onFavorite = function()
            toggleDetailFavorite(panel)
        end,
        onExport = function()
            exportDetailSpell(panel)
        end,
        onCopy = function(spellID)
            addon.ArchiveCopyDialog.OpenSpell(panel.spellbook, spellID)
        end,

        onInsertChat = function(spellID)
            insertSpellLink(panel, spellID)
        end,
        onWhisper = function(spellID)
            whisperSpell(panel, spellID)
        end,
        onGameMasterAction = function(spellID)
            local spell = panel.spellbook
                and panel.spellbook.spells
                and panel.spellbook.spells[spellID]
                or nil
            if spell then
                addon.GameMasterService.OpenAction(spell)
            end
        end,
    })
    detailsView:SetPoint("TOPLEFT", header, "BOTTOMLEFT", theme.Spacing.xs, -theme.Spacing.md)
    detailsView:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)

    panel.arrangeButton = arrangeButton
    panel.arrangeHint = arrangeHint
    panel.bookIcon = bookIcon
    panel.bookSurface = bookSurface
    panel.header = header
    panel.detailsView = detailsView
    detailsView.ownerPanel = panel

    panel.libraryButton = libraryButton
    panel.bulkDeleteButton = bulkDeleteButton
    panel.editTabButton = editTabButton
    panel.compactButton = compactButton
    panel.gameMasterButton = gameMasterButton
    panel.copyTabButton = copyTabButton
    panel.exportBookButton = exportBookButton
    panel.emptyState = emptyState
    panel.newSpellButton = newSpellButton
    panel.newTabButton = newTabButton
    panel.nextPageButton = nextPageButton
    panel.nextTabButton = nextTabButton
    panel.pageNumber = pageNumber
    panel.previousPageButton = previousPageButton
    panel.previousTabButton = previousTabButton
    panel.profile = profile
    panel.searchBox = searchBox
    panel.favoriteFilterButton = favoriteFilterButton
    panel.tabBar = tabBar
    panel.tabButtons = tabButtons
    panel.title = title
    panel.presentationButtons = {
        arrangeButton,
        libraryButton,
        gameMasterButton,
        compactButton,
        newSpellButton,
        newTabButton,
        editTabButton,
        exportBookButton,
        copyTabButton,
        favoriteFilterButton,
        bulkDeleteButton,
        previousTabButton,
        nextTabButton,
        previousPageButton,
        nextPageButton,
    }

    if type(panel.GetFrameLevel) == "function" then
        local baseLevel = panel:GetFrameLevel()
        if type(bookSurface.SetFrameLevel) == "function" then
            bookSurface:SetFrameLevel(baseLevel)
        end
        for _, control in ipairs({
            header,
            searchBox,
            newSpellButton,
            newTabButton,
            editTabButton,
            exportBookButton,
            copyTabButton,
            tabBar,
            content,
            favoriteFilterButton,
            bulkDeleteButton,
            nextPageButton,
            previousPageButton,
            detailsView,
        }) do
            if type(control.SetFrameLevel) == "function" then
                control:SetFrameLevel(baseLevel + 2)
            end
        end
    end
    panel.listRegions = {
        arrangeButton,
        arrangeHint,
        libraryButton,
        gameMasterButton,
        compactButton,
        searchBox,
        newSpellButton,
        newTabButton,
        editTabButton,
        exportBookButton,
        copyTabButton,
        favoriteFilterButton,
        bulkDeleteButton,

        tabBar,
        content,
        previousPageButton,
        pageNumber,
        nextPageButton,
    }
    panel.archiveHiddenRegions = {
        [arrangeButton] = true,
        [arrangeHint] = true,
        [libraryButton] = true,
        [gameMasterButton] = true,
        [compactButton] = true,
        [newSpellButton] = true,
        [newTabButton] = true,
        [editTabButton] = true,
        [exportBookButton] = true,

    }

    panel.bookHiddenRegions = {
        [arrangeButton] = true, [arrangeHint] = true, [gameMasterButton] = true,
        [compactButton] = true, [newSpellButton] = true, [newTabButton] = true,
        [editTabButton] = true, [exportBookButton] = true,
        [bulkDeleteButton] = true, [tabBar] = true,
    }
    arrangeButton:SetScript("OnClick", function()
        setEditMode(panel, not panel.editMode)
    end)
    favoriteFilterButton:SetScript("OnClick", function()
        panel.favoritesOnly = not panel.favoritesOnly
        favoriteFilterButton:SetText(
            panel.favoritesOnly and addon.L("SHOW_ALL")
                or addon.L("FAVORITES_ONLY")
        )
        panel.currentPage = 1
        renderPanel(panel)
    end)
    bulkDeleteButton:SetScript("OnClick", function()
        deleteSelectedSpells(panel)
    end)
    libraryButton:SetScript("OnClick", function()
        if panel.spellbook and panel.spellbook.imported == true then
            openOwnBook(panel)
        elseif addon.TRP3Integration and addon.TRP3Integration.OpenImportedLibrary
            and addon.TRP3Integration.OpenImportedLibrary()
        then
            return
        else
            addon.ImportedBooksWindow.Open(function(book)
                openImportedBook(panel, book)
            end)
        end
    end)
    compactButton:SetScript("OnClick", function()
        addon.GameMasterCompactSpellbook.Open()
    end)
    searchBox:HookScript("OnTextChanged", function()
        if addon.BookScene then addon.BookScene.Stop(panel) end
        panel.currentPage = 1
        renderPanel(panel)
    end)
    copyTabButton:SetScript("OnClick", function()
        local copiedTab, errorMessage = addon.ArchiveCopy.CopyTab(panel.spellbook, panel.activeTabID)
        if not copiedTab then
            addon.Logger.Error(errorMessage or addon.L("ARCHIVE_COPY_FAILED"))
            return
        end
        addon.Logger.Info(addon.L("ARCHIVE_TAB_COPIED", copiedTab.name))
    end)
    previousTabButton:SetScript("OnClick", function()
        panel.tabOffset = math.max(1, (panel.tabOffset or 1) - 1)
        panel.scrollingTabs = true
        renderTabs(panel)
    end)
    nextTabButton:SetScript("OnClick", function()
        panel.tabOffset = (panel.tabOffset or 1) + 1
        panel.scrollingTabs = true
        renderTabs(panel)
    end)
    previousPageButton:SetScript("OnClick", function()
        animate(panel, panel, "page", function()
            panel.currentPage = panel.currentPage - 1
            renderPanel(panel)
        end, -1)
    end)
    nextPageButton:SetScript("OnClick", function()
        animate(panel, panel, "page", function()
            panel.currentPage = panel.currentPage + 1
            renderPanel(panel)
        end, 1)
    end)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        if delta == 0 or panel.detailSpellID or panel.bookClosing
            or panel.draggedSpellID or panel.draggedTabID
            or (panel.bookBurn and panel.bookBurn.playing)
            or (addon.BookScene and addon.BookScene.IsPlaying(panel)) then
            return
        end
        local button = delta > 0 and previousPageButton or nextPageButton
        if button:IsVisible() and button:IsEnabled() then
            button:Click()
        end
    end)
    newSpellButton:SetScript("OnClick", function()
        addon.SpellEditorWindow.OpenNew(panel.activeTabID, function(tabID)
            refreshFromDatabase(panel, tabID)
        end)
    end)
    newTabButton:SetScript("OnClick", function()
        addon.TabEditor.OpenNew(function(tabID)
            refreshFromDatabase(panel, tabID)
        end)
    end)
    editTabButton:SetScript("OnClick", function()
        addon.TabEditor.OpenEdit(panel.activeTabID, function(tabID)
            refreshFromDatabase(panel, tabID)
        end)
    end)
    exportBookButton:SetScript("OnClick", function()
        if not panel.readOnly then
            addon.ExportWindow.OpenBook(panel.spellbook, panel.activeTabID)
        end
    end)

    for _, slot in ipairs(panel.spellSlots) do
        slot:RegisterForDrag("LeftButton")
        slot:SetScript("OnEnter", function(self)
            if panel.draggedSpellID then
                panel.dragTargetSlot = self
                setSlotAppearance(panel, self, true)
            else
                showSpellTooltip(self)
            end
        end)
        slot:SetScript("OnLeave", function(self)
            if panel.dragTargetSlot == self then panel.dragTargetSlot = nil end
            setSlotAppearance(panel, self, false)
            addon.SpellTooltip.Hide()
        end)
        slot:SetScript("OnDragStart", function(self)
            if canArrange(panel) and self.spellID then
                panel.draggedSpellID = self.spellID
                panel.dragSourceSlot = self
                panel.dragTargetSlot = self
                self:SetAlpha(0.45)
                addon.SpellTooltip.Hide()
            end
        end)
        slot:SetScript("OnDragStop", function()
            finishSpellDrag(panel)
        end)
        slot:SetScript("OnClick", function(self, button)
            if panel.suppressSpellClick then return end
            if addon.BookScene and addon.BookScene.IsPlaying(panel) then return end
            if panel.bookControlsEnabled and button == "LeftButton" and altDown() and not panel.readOnly then
                if panel.draggedSpellID then
                    panel.dragTargetSlot = self
                    finishSpellDrag(panel)
                elseif self.spellID then
                    panel.draggedSpellID = self.spellID
                    panel.dragSourceSlot = self
                    self:SetAlpha(0.5)
                end
                return
            end
            if button == "LeftButton" and self.spellID and not panel.editMode then
                if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
                    insertSpellLink(panel, self.spellID)
                else
                    showDetail(panel, self.spellID)
                end
            elseif button == "LeftButton" and panel.editMode and self.spellID then
                panel.bulkSelection[self.spellID] =
                    not panel.bulkSelection[self.spellID]
                setSlotAppearance(panel, self, false)
            elseif button == "RightButton" and not panel.readOnly and self.spellID then
                editBookSpell(panel, self.spellID)
            end
        end)
    end

    addon.FancyBookControls.Create(panel, {
        newTab = function()
            if not panel.readOnly then
                animate(panel, panel.fancyControls.bookmarkHost, "focus")
                newTabButton:Click()
            end
        end,
        export = function()
            if not panel.readOnly then
                animate(panel, panel.header, "focus")
                exportBookButton:Click()
            end
        end,
        favorite = function()
            animate(panel, panel.content, "page", function() favoriteFilterButton:Click() end)
        end,
        newSpell = function()
            if panel.readOnly or not panel.createTargetIndex then return end
            if altDown() then
                if panel.draggedSpellID then
                    panel.dragTargetSlot = panel.fancyControls.placeholder.slot
                    finishSpellDrag(panel)
                end
                return
            end
            local bookID, tabID = panel.bookID, panel.activeTabID
            local insertAt, page = panel.createTargetIndex, panel.currentPage
            animate(panel, panel.fancyControls.placeholder, "write")
            addon.SpellEditorWindow.OpenNew(tabID, function(savedTabID, spellID)
                local book = addon.Database.GetActiveSpellbook()
                if not book or book.id ~= bookID then return end
                if spellID and savedTabID == tabID then
                    local moved, err = addon.Database.MoveSpell(spellID, savedTabID, insertAt)
                    if not moved then addon.Logger.Error(err) end
                end
                refreshFromDatabase(panel, savedTabID)
                local ids = book.tabs[savedTabID] and book.tabs[savedTabID].spellIds or {}
                for i, id in ipairs(ids) do
                    if id == spellID then page = math.ceil(i / panel.spellsPerPage) break end
                end
                panel.currentPage = page
                renderPanel(panel)
                for _, slot in ipairs(panel.spellSlots) do
                    if slot.spellID == spellID then
                        C_Timer.After(0, function()
                            if panel.spellbook == book and not panel.detailSpellID and panel.activeTabID == savedTabID
                                and slot.spellID == spellID and panel.fancyPresentation and panel:IsVisible() then
                                animate(panel, slot, "write")
                                addon.FancyBookControls.Inscribe(slot)
                            end
                        end)
                    end
                end
            end)
        end,
        tab = function(button, mouseButton)
            if panel.suppressTabClick or not button.tabID then return end
            if addon.BookScene and addon.BookScene.IsPlaying(panel) then return end
            if mouseButton == "LeftButton" and altDown() and not panel.readOnly then
                if panel.draggedSpellID then
                    panel.dragTargetTabID = button.tabID
                    finishSpellDrag(panel)
                elseif panel.draggedTabID then
                    panel.dragTargetTabButton = button
                    finishTabDrag(panel)
                else
                    panel.draggedTabID, panel.dragSourceTabButton = button.tabID, button
                    button:SetAlpha(0.5)
                end
            elseif mouseButton == "RightButton" and not panel.readOnly then
                addon.TabEditor.OpenEdit(button.tabID, function(tabID) refreshFromDatabase(panel, tabID) end)
            elseif mouseButton == "LeftButton" and button.tabID ~= panel.activeTabID then
                local target, direction, previous = button.tabID, 1, false
                for _, id in ipairs(panel.spellbook.tabOrder) do
                    if id == panel.activeTabID then previous = true end
                    if id == target then direction = previous and 1 or -1 break end
                end
                animate(panel, panel, "page", function()
                    panel.activeTabID, panel.currentPage = target, 1
                    renderPanel(panel)
                end, direction)
            end
        end,
        hoverTab = function(button)
            if panel.draggedSpellID then panel.dragTargetTabID = button.tabID end
            if panel.draggedTabID then panel.dragTargetTabButton = button end
        end,
        leaveTab = function(button)
            if panel.dragTargetTabID == button.tabID then panel.dragTargetTabID = nil end
            if panel.dragTargetTabButton == button then panel.dragTargetTabButton = nil end
        end,
        dragTab = function(button)
            if canArrange(panel) then
                panel.draggedTabID, panel.dragSourceTabButton = button.tabID, button
                panel.dragTargetTabButton = button
                button:SetAlpha(0.5)
            end
        end,
        dropTab = function() finishTabDrag(panel) end,
    })

    local function cancelDrag()
        if panel.dragSourceSlot then panel.dragSourceSlot:SetAlpha(1) end
        if panel.dragSourceTabButton then panel.dragSourceTabButton:SetAlpha(1) end
        panel.dragSourceSlot, panel.dragSourceTabButton = nil, nil
        panel.dragTargetSlot, panel.dragTargetTabButton = nil, nil
        panel.draggedSpellID, panel.draggedTabID, panel.dragTargetTabID = nil, nil, nil
    end
    panel.cancelDrag = cancelDrag
    panel:RegisterEvent("MODIFIER_STATE_CHANGED")
    panel:SetScript("OnEvent", function(_, _, key, state)
        if panel.bookControlsEnabled and (key == "LALT" or key == "RALT")
            and state == 0 and not altDown() then cancelDrag() end
    end)
    panel:HookScript("OnHide", function()
        cancelDrag()
        if addon.BookMagic then
            addon.BookMagic.StopText(panel.detailsView)
            for _, slot in ipairs(panel.spellSlots) do addon.BookMagic.StopText(slot) end
        end
        addon.FancyBookControls.CloseAfterHide(panel)
        addon.FancyBookControls.Stop(panel, true)
        addon.BookAnimation.Stop(panel)
        addon.BookAnimation.Stop(panel.header)
        addon.BookAnimation.Stop(panel.content)
        addon.BookAnimation.Stop(panel.detailsView)
        for _, slot in ipairs(panel.spellSlots) do
            addon.BookAnimation.Stop(slot)
            addon.FancyBookControls.CancelInscription(slot)
        end
    end)
    panel.RequestClose = function(callback)
        if panel.bookClosing then return end
        panel.bookClosing = true
        animate(panel, panel, "close", function()
            panel.bookClosing = nil
            panel.bookCloseCompleted = true
            callback()
            panel.bookCloseCompleted = nil
        end)
    end

    local layoutPending = false
    local function refreshLayout()
        if panel.spellbook and not panel.detailSpellID then renderPanel(panel)
        else
            if panel.spellbook then
                applyActiveTabTheme(panel, panel.spellbook.tabs[panel.activeTabID])
            end
            layoutPanel(panel)
        end
    end
    local function requestLayout()
        if layoutPending then return end
        layoutPending = true
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                layoutPending = false
                refreshLayout()
            end)
        else
            layoutPending = false
            refreshLayout()
        end
    end
    panel.requestLayout = requestLayout
    panel:SetScript("OnSizeChanged", function()
        addon.FancyBookControls.StopOutgoing(panel)
        requestLayout()
    end)
    panel:SetScript("OnShow", function()
        panel.bookClosing = nil
        addon.FancyBookControls.StopOutgoing(panel)
        requestLayout()
        if panel.detailSpellID and panel.spellbook then
            applyActiveTabTheme(panel, panel.spellbook.tabs[panel.activeTabID])
        end
        animate(panel, panel, "open")
    end)
    content:SetScript("OnSizeChanged", requestLayout)
    refreshLayout()
    requestLayout()

    addon.GameMasterService.RegisterListener(function()
        if not panel.spellbook then
            return
        end
        panel.showGameMasterControl = false
        panel.showCompactCombat = not panel.archiveMode
            and not panel.readOnly
            and addon.GameMasterService.IsSessionActive()
        if panel.detailSpellID then
            local spell = panel.spellbook.spells[panel.detailSpellID]
            if spell then
                addon.SpellDetailsView.SetSpell(
                    panel.detailsView,
                    spell,
                    not panel.readOnly,
                    not panel.readOnly and addon.GameMasterService.CanSubmit(),
                    panel.archiveMode and addon.ArchiveCopy
                        and addon.ArchiveCopy.CanCopySpell(panel.spellbook, panel.detailSpellID),
                    not panel.readOnly
                        and addon.Database.IsSpellFavorite(panel.detailSpellID)
                )
            end
        else
            setListVisible(panel, true)
        end
        requestLayout()
    end)
    if addon.SpellCreationSettings
        and type(addon.SpellCreationSettings.RegisterListener) == "function"
    then
        addon.SpellCreationSettings.RegisterListener(function()
            if panel.spellbook then
                addon.FancyBookControls.StopOutgoing(panel)
                if panel.fancyPresentation and addon.SpellCreationSettings.ShouldReduceBookMotion
                    and addon.SpellCreationSettings.ShouldReduceBookMotion() then
                    addon.BookScene.Finish(panel)
                    addon.BookScene.Stop(panel)
                    addon.FancyBookControls.Stop(panel)
                    addon.SpellDetailsView.StopReadingReveal(panel.detailsView)
                    for _, frame in ipairs({ panel, panel.header, panel.content, panel.detailsView }) do
                        addon.BookAnimation.Finish(frame)
                    end
                    for _, slot in ipairs(panel.spellSlots) do
                        addon.BookAnimation.Finish(slot)
                        addon.FancyBookControls.CancelInscription(slot)
                    end
                end
                if addon.BookMagic then addon.BookMagic.FinishBurn(panel) end
                renderPanel(panel)
            end
        end)
    end
    return panel
end

function addon.SpellbookPanel.RevealTutorialCreation(panel)
    if panel.readOnly or not panel.spellbook then return false end
    if panel.cancelDrag then panel.cancelDrag() end
    if addon.BookScene then addon.BookScene.Stop(panel) end
    panel.detailSpellID, panel.editMode, panel.favoritesOnly = nil, false, false
    panel.detailsView:Hide()
    panel.searchBox:SetText("")
    panel.favoriteFilterButton:SetText(addon.L("FAVORITES_ONLY"))
    setListVisible(panel, true)
    renderPanel(panel)
    local tab = panel.spellbook.tabs[panel.activeTabID]
    if not tab then return false end
    panel.currentPage = math.floor(#tab.spellIds / panel.spellsPerPage) + 1
    renderPanel(panel)
    return panel.createTargetIndex ~= nil
end

function addon.SpellbookPanel.Refresh(panel, spellbook, profileLabel, requestedTabID, options)
    local constants = addon.Constants
    if type(spellbook) ~= "table" then
        return
    end
    addon.FancyBookControls.StopOutgoing(panel)

    local bookChanged = panel.bookID ~= spellbook.id or panel.spellbook ~= spellbook
        or panel.bookProfileKey ~= spellbook.profileKey
    if addon.BookMagic then addon.BookMagic.FinishBurn(panel) end
    if bookChanged then panel.deleteConfirmation = nil end
    if bookChanged and panel.cancelDrag then panel.cancelDrag() end
    if bookChanged and addon.BookAnimation then
        addon.BookAnimation.Stop(panel)
        addon.BookAnimation.Stop(panel.detailsView)
        panel.bookClosing = nil
    end
    if bookChanged and addon.BookScene then addon.BookScene.Stop(panel) end
    panel.bookID = spellbook.id
    panel.bookProfileKey = spellbook.profileKey
    panel.spellbook = spellbook
    panel.profileLabel = profileLabel or ""
    panel.archiveMode = type(options) == "table" and options.archiveMode == true
    panel.allowTabCopy = panel.archiveMode
        and type(spellbook.copyPermissions) == "table"
        and spellbook.copyPermissions.tabs == true
    panel.readOnly = panel.archiveMode or spellbook.profileKey == "preview" or spellbook.imported == true
    panel.showGameMasterControl = false
    panel.showCompactCombat = not panel.archiveMode
        and not panel.readOnly
        and addon.GameMasterService.IsSessionActive()
    if bookChanged then
        panel.activeTabID = nil
        panel.currentPage = 1
        panel.detailSpellID = nil
        panel.editMode = false
        panel.bulkSelection = {}
        panel.favoritesOnly = false
        panel.favoriteFilterButton:SetText(addon.L("FAVORITES_ONLY"))
        panel.arrangeButton:SetText(addon.L("ARRANGE"))
        panel.arrangeHint:Hide()
        panel.searchBox:Enable()
        panel.tabOffset = 1
        panel.searchBox:SetText("")
    end
    selectActiveTab(panel, requestedTabID)

    panel.title:SetText(type(spellbook.name) == "string" and spellbook.name ~= "" and spellbook.name or addon.L("DEFAULT_BOOK_NAME"))
    addon.UIFactory.SetIconTexture(panel.bookIcon, spellbook.icon, constants.DEFAULT_BOOK_ICON)
    panel.profile:SetText(panel.profileLabel)
    panel.libraryButton:SetText(spellbook.imported == true and addon.L("MY_SPELLBOOK") or addon.L("IMPORT_ARCHIVE"))
    if panel.archiveMode then
        panel.editMode = false
        panel.arrangeButton:SetText(addon.L("ARRANGE"))
        panel.arrangeHint:Hide()
        panel.searchBox:Enable()
    end
    if panel.detailSpellID and spellbook.spells[panel.detailSpellID] then
        applyActiveTabTheme(panel, spellbook.tabs[panel.activeTabID])
        showDetail(panel, panel.detailSpellID)
    else
        panel.detailSpellID = nil
        panel.detailsView:Hide()
        setListVisible(panel, true)
        renderPanel(panel)
    end
    if panel.requestLayout then panel.requestLayout() end
end
