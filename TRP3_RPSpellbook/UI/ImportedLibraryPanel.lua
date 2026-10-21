local _, addon = ...

addon.ImportedLibraryPanel = {}

local function setButtonEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end

local function selectButton(button, selected)
    local theme = addon.Theme
    local background = selected and theme.Colors.archiveRowSelected or theme.Colors.archiveRow
    local border = selected and theme.Colors.gold or theme.Colors.archiveRowBorder
    button:SetBackdropColor(background[1], background[2], background[3], background[4])
    button:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

local function createDirectoryRow(parent, showMetadata)
    local theme = addon.Theme
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local label = addon.UIFactory.CreateLabel(button, theme.Fonts.body, "", theme.Colors.gold)
    if showMetadata then
        label:SetPoint("TOPLEFT", button, "TOPLEFT", theme.Spacing.sm, -theme.Spacing.xs)
        label:SetPoint("TOPRIGHT", button, "TOPRIGHT", -theme.Spacing.sm, -theme.Spacing.xs)
    else
        label:SetPoint("LEFT", button, "LEFT", theme.Spacing.sm, 0)
        label:SetPoint("RIGHT", button, "RIGHT", -theme.Spacing.sm, 0)
    end
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    button:SetFontString(label)

    if showMetadata then
        local metadata = addon.UIFactory.CreateLabel(button, theme.Fonts.small, "", theme.Colors.textMuted)
        metadata:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", theme.Spacing.sm, theme.Spacing.xs)
        metadata:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -theme.Spacing.sm, theme.Spacing.xs)
        metadata:SetJustifyH("LEFT")
        metadata:SetWordWrap(false)
        button.metadata = metadata
    end

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetColorTexture(theme.Colors.gold[1], theme.Colors.gold[2], theme.Colors.gold[3], 0.12)
    selectButton(button, false)
    return button
end

local function createListSection(parent, titleText, rowHeight, showMetadata)
    local theme = addon.Theme
    local section = addon.UIFactory.CreateBackdropFrame(parent, theme.Colors.parchmentDark, theme.Colors.border)
    section.rowHeight = rowHeight or theme.Sizes.archiveRowHeight
    local title = addon.UIFactory.CreateLabel(section, theme.Fonts.body, titleText, theme.Colors.gold)
    title:SetPoint("TOPLEFT", section, "TOPLEFT", theme.Spacing.sm, -theme.Spacing.sm)

    local buttons = {}
    for index = 1, theme.Sizes.archiveMaxVisibleRows do
        local button = createDirectoryRow(section, showMetadata)
        button:SetHeight(section.rowHeight)
        button:SetPoint("TOPLEFT", section, "TOPLEFT", theme.Spacing.sm, -(theme.Sizes.archiveSectionHeaderHeight + ((index - 1) * (section.rowHeight + theme.Spacing.xs))))
        button:SetPoint("TOPRIGHT", section, "TOPRIGHT", -theme.Spacing.sm, -(theme.Sizes.archiveSectionHeaderHeight + ((index - 1) * (section.rowHeight + theme.Spacing.xs))))
        button:Hide()
        buttons[index] = button
    end

    local previousButton = addon.UIFactory.CreateButton(section, "<", theme.Sizes.pageButtonWidth)
    previousButton:SetPoint("BOTTOMLEFT", section, "BOTTOMLEFT", theme.Spacing.sm, theme.Spacing.sm)
    local pageLabel = addon.UIFactory.CreateLabel(section, theme.Fonts.small, "", theme.Colors.textMuted)
    pageLabel:SetPoint("LEFT", previousButton, "RIGHT", theme.Spacing.sm, 0)
    local nextButton = addon.UIFactory.CreateButton(section, ">", theme.Sizes.pageButtonWidth)
    nextButton:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -theme.Spacing.sm, theme.Spacing.sm)
    local emptyLabel = addon.UIFactory.CreateLabel(section, theme.Fonts.small, "", theme.Colors.textMuted)
    emptyLabel:SetPoint("LEFT", section, "LEFT", theme.Spacing.sm, -theme.Spacing.sm)
    emptyLabel:SetPoint("RIGHT", section, "RIGHT", -theme.Spacing.sm, -theme.Spacing.sm)
    emptyLabel:SetWordWrap(true)
    emptyLabel:SetJustifyH("CENTER")

    section.buttons = buttons
    section.previousButton = previousButton
    section.nextButton = nextButton
    section.pageLabel = pageLabel
    section.emptyLabel = emptyLabel
    section.page = 1
    section.visibleRows = 1
    return section
end

local function getPageData(section, items)
    local pageCount = math.max(1, math.ceil(#items / section.visibleRows))
    section.page = math.max(1, math.min(section.page, pageCount))
    local firstIndex = ((section.page - 1) * section.visibleRows) + 1
    section.pageLabel:SetText(addon.L("PAGE_FORMAT", section.page, pageCount))
    setButtonEnabled(section.previousButton, section.page > 1)
    setButtonEnabled(section.nextButton, section.page < pageCount)
    return firstIndex
end

local function formatImportDate(importedAt)
    local timestamp = tonumber(importedAt)
    if timestamp and timestamp >= 0 and type(date) == "function" then
        local success, result = pcall(date, addon.L("ARCHIVE_DATE_FORMAT"), timestamp)
        if success and type(result) == "string" and result ~= "" then
            return result
        end
    end
    return addon.L("UNKNOWN")
end

local function formatRemainingDuration(expiresAt)
    local remaining = math.max(0, math.ceil((tonumber(expiresAt) or 0) - addon.Runtime.GetTimestamp()))
    local days = math.floor(remaining / 86400)
    local hours = math.floor((remaining % 86400) / 3600)
    local minutes = math.ceil((remaining % 3600) / 60)

    if days > 0 then
        return addon.L("ARCHIVE_DURATION_DAYS_HOURS", days, hours)
    end
    if hours > 0 then
        return addon.L("ARCHIVE_DURATION_HOURS_MINUTES", hours, minutes)
    end
    return addon.L("ARCHIVE_DURATION_MINUTES", math.max(1, minutes))
end

local function getRemainingLabel(bookGroup)
    local expiresAt = tonumber(bookGroup and bookGroup.expiresAt) or 0
    if expiresAt <= 0 then
        return nil
    end
    return addon.L("ARCHIVE_AVAILABLE_FOR", formatRemainingDuration(expiresAt))
end

local function getArchiveProfileLabel(bookGroup)
    local parts = {
        addon.L("IMPORTED_FROM_FORMAT", bookGroup.ownerDisplayName or addon.L("UNKNOWN")),
        addon.L("ARCHIVE_SPELL_COUNT", bookGroup.spellCount),
        addon.L("ARCHIVE_IMPORTED_AT", formatImportDate(bookGroup.latestImportedAt)),
    }
    local remainingLabel = getRemainingLabel(bookGroup)
    if remainingLabel then
        parts[#parts + 1] = remainingLabel
    end
    return table.concat(parts, " - ")
end

local function renderSelectedBook(panel)
    local owner = panel.owners[panel.selectedOwnerIndex]
    local bookGroup = owner and owner.books[panel.selectedBookIndex]
    panel.selectedBookGroup = bookGroup
    setButtonEnabled(panel.deleteButton, bookGroup ~= nil)
    local virtualBook = bookGroup and addon.ImportedLibrary.GetVirtualBook(bookGroup)
    if not virtualBook then
        panel.bookPanel:Hide()
        panel.emptyState:Show()
        return
    end

    panel.emptyState:Hide()
    panel.bookPanel:Show()
    addon.SpellbookPanel.Refresh(
        panel.bookPanel,
        virtualBook,
        getArchiveProfileLabel(bookGroup),
        nil,
        { archiveMode = true }
    )
end

local function renderBooks(panel)
    local owner = panel.owners[panel.selectedOwnerIndex]
    local books = owner and owner.books or {}
    local section = panel.bookSection
    local firstIndex = getPageData(section, books)

    for rowIndex, button in ipairs(section.buttons) do
        local bookIndex = rowIndex <= section.visibleRows and firstIndex + rowIndex - 1 or nil
        local bookGroup = bookIndex and books[bookIndex] or nil
        button.bookIndex = bookGroup and bookIndex or nil
        if bookGroup then
            button:SetText(bookGroup.displayName)
            if button.metadata then
                local remainingLabel = getRemainingLabel(bookGroup)
                if remainingLabel then
                    button.metadata:SetText(addon.L(
                        "ARCHIVE_IMPORT_ROW_EXPIRING",
                        formatRemainingDuration(bookGroup.expiresAt),
                        bookGroup.spellCount
                    ))
                else
                    button.metadata:SetText(addon.L(
                        "ARCHIVE_IMPORT_ROW_META",
                        formatImportDate(bookGroup.latestImportedAt),
                        bookGroup.spellCount
                    ))
                end
            end
            selectButton(button, bookIndex == panel.selectedBookIndex)
            button:Show()
        else
            if button.metadata then
                button.metadata:SetText("")
            end
            selectButton(button, false)
            button:Hide()
        end
    end
    section.emptyLabel:SetText(addon.L("ARCHIVE_NO_BOOKS"))
    section.emptyLabel:SetShown(#books == 0)
    renderSelectedBook(panel)
end

local function renderOwners(panel)
    local section = panel.ownerSection
    local firstIndex = getPageData(section, panel.owners)
    for rowIndex, button in ipairs(section.buttons) do
        local ownerIndex = rowIndex <= section.visibleRows and firstIndex + rowIndex - 1 or nil
        local owner = ownerIndex and panel.owners[ownerIndex] or nil
        button.ownerIndex = owner and ownerIndex or nil
        if owner then
            button:SetText(owner.displayName)
            selectButton(button, ownerIndex == panel.selectedOwnerIndex)
            button:Show()
        else
            selectButton(button, false)
            button:Hide()
        end
    end
    local hasSearch = panel.ownerSearchBox and panel.ownerSearchBox:GetText() ~= ""
    section.emptyLabel:SetText(
        hasSearch and addon.L("ARCHIVE_NO_CHARACTER_RESULTS") or addon.L("NO_IMPORTED_BOOKS")
    )
    section.emptyLabel:SetShown(#panel.owners == 0)
end

local function findPreferredSelection(owners, preferredImportID, previousOwnerKey, previousImportID)
    local fallbackOwnerIndex = #owners > 0 and 1 or nil
    local fallbackBookIndex = fallbackOwnerIndex and #owners[fallbackOwnerIndex].books > 0 and 1 or nil
    for ownerIndex, owner in ipairs(owners) do
        if owner.key == previousOwnerKey and #owner.books > 0 then
            fallbackOwnerIndex = ownerIndex
            fallbackBookIndex = 1
        end
        for bookIndex, bookGroup in ipairs(owner.books) do
            if preferredImportID and bookGroup.importIDs[preferredImportID] then
                return ownerIndex, bookIndex
            end
            if not preferredImportID
                and owner.key == previousOwnerKey
                and bookGroup.importID == previousImportID
            then
                return ownerIndex, bookIndex
            end
        end
    end
    return fallbackOwnerIndex, fallbackBookIndex
end

local function selectVisiblePages(panel)
    local ownerIndex = panel.selectedOwnerIndex or 1
    local bookIndex = panel.selectedBookIndex or 1
    panel.ownerSection.page = math.floor((ownerIndex - 1) / panel.ownerSection.visibleRows) + 1
    panel.bookSection.page = math.floor((bookIndex - 1) / panel.bookSection.visibleRows) + 1
end

local function updateOwnerFilter(panel, preferredImportID, previousOwnerKey, previousImportID)
    panel.owners = addon.ImportedLibrary.FilterOwners(panel.allOwners, panel.ownerSearchBox:GetText())
    panel.selectedOwnerIndex, panel.selectedBookIndex = findPreferredSelection(
        panel.owners,
        preferredImportID,
        previousOwnerKey,
        previousImportID
    )
    selectVisiblePages(panel)
    renderOwners(panel)
    renderBooks(panel)
end

local function layoutPanel(panel)
    local theme = addon.Theme
    local width = math.max(1, panel:GetWidth())
    local height = math.max(1, panel:GetHeight())
    local desiredDirectoryWidth = math.max(
        theme.Sizes.archiveDirectoryMinWidth,
        math.min(theme.Sizes.archiveDirectoryWidth, math.floor(width * theme.Sizes.archiveDirectoryRatio))
    )
    local maximumDirectoryWidth = math.max(1, width - theme.Sizes.archiveContentMinWidth - theme.Spacing.md)
    local directoryWidth = math.max(1, math.min(desiredDirectoryWidth, maximumDirectoryWidth))
    local storageHeight = panel.storageStats and type(panel.storageStats.GetStringHeight) == "function"
        and math.max(42, math.ceil(panel.storageStats:GetStringHeight())) or 42
    if panel.storageStats then panel.storageStats:SetHeight(storageHeight) end
    local contentTop = theme.Sizes.archiveHeaderHeight + theme.Spacing.lg + storageHeight
    panel.directory:SetPoint("TOPLEFT", panel, "TOPLEFT", theme.Spacing.lg, -contentTop)
    local availableHeight = math.max(1, height - contentTop - theme.Spacing.lg)
    local searchHeight = theme.Sizes.inputHeight + theme.Spacing.sm
    local listHeight = math.max(1, availableHeight - searchHeight)
    local ownerHeight = math.floor((listHeight - theme.Spacing.md) * theme.Sizes.archiveOwnerListRatio)
    ownerHeight = math.max(theme.Sizes.archiveSectionMinHeight, ownerHeight)

    panel.directory:SetWidth(directoryWidth)
    panel.ownerSection:SetHeight(ownerHeight)

    for _, section in ipairs({ panel.ownerSection, panel.bookSection }) do
        local usableHeight = math.max(1, section:GetHeight() - theme.Sizes.archiveSectionHeaderHeight - theme.Sizes.archiveSectionFooterHeight)
        section.visibleRows = math.max(1, math.min(theme.Sizes.archiveMaxVisibleRows, math.floor(usableHeight / (section.rowHeight + theme.Spacing.xs))))
    end
end

local function cancelExpirationTimer(panel)
    local timer = panel.expirationTimer
    panel.expirationTimer = nil
    if timer and type(timer.Cancel) == "function" then
        timer:Cancel()
    end
end

local function scheduleExpirationRefresh(panel)
    cancelExpirationTimer(panel)
    if not panel:IsShown()
        or not C_Timer
        or type(C_Timer.NewTimer) ~= "function"
    then
        return
    end

    local expiresAt = addon.Database.GetNextImportedBookExpiration()
    if not expiresAt then
        return
    end
    local delay = math.max(1, math.min(60, expiresAt - addon.Runtime.GetTimestamp()))
    panel.expirationTimer = C_Timer.NewTimer(delay, function()
        panel.expirationTimer = nil
        if panel:IsShown() then
            addon.ImportedLibraryPanel.Refresh(panel)
        end
    end)
end

function addon.ImportedLibraryPanel.Create(parent)
    local theme = addon.Theme
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.owners = {}
    panel.allOwners = {}

    local title = addon.UIFactory.CreateLabel(panel, theme.Fonts.header, addon.L("IMPORT_ARCHIVE"), theme.Colors.gold)
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", theme.Spacing.lg, -theme.Spacing.lg)
    local importButton = addon.UIFactory.CreateButton(panel, addon.L("IMPORT"), theme.Sizes.importActionButtonWidth)
    importButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -theme.Spacing.lg, -theme.Spacing.lg)
    local deleteButton = addon.UIFactory.CreateButton(panel, addon.L("DELETE_IMPORT"), theme.Sizes.deleteButtonWidth)
    deleteButton:SetPoint("RIGHT", importButton, "LEFT", -theme.Spacing.sm, 0)
    deleteButton:Disable()
    title:SetPoint("TOPRIGHT", deleteButton, "TOPLEFT", -theme.Spacing.sm, 0)
    title:SetWordWrap(false)
    local intro = addon.UIFactory.CreateLabel(panel, theme.Fonts.small, addon.L("IMPORT_ARCHIVE_HINT"), theme.Colors.textMuted)
    intro:SetPoint("TOPLEFT", panel, "TOPLEFT", theme.Spacing.lg, -(theme.Spacing.lg + theme.Sizes.buttonHeight + theme.Spacing.xs))
    intro:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -theme.Spacing.lg, 0)
    intro:SetWordWrap(true)
    intro:SetJustifyH("LEFT")

    local storageStats = addon.UIFactory.CreateLabel(panel, theme.Fonts.small, "", theme.Colors.textMuted)
    storageStats:SetPoint("TOPLEFT", panel, "TOPLEFT", theme.Spacing.lg, -theme.Sizes.archiveHeaderHeight)
    storageStats:SetPoint("RIGHT", panel, "RIGHT", -theme.Spacing.lg, 0)
    storageStats:SetHeight(42)
    storageStats:SetWordWrap(true)
    storageStats:SetJustifyH("LEFT")
    storageStats:SetJustifyV("TOP")
    panel.storageStats = storageStats

    local directory = CreateFrame("Frame", nil, panel)
    directory:SetPoint("TOPLEFT", panel, "TOPLEFT", theme.Spacing.lg, -(theme.Sizes.archiveHeaderHeight + theme.Spacing.lg + 42))
    directory:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", theme.Spacing.lg, theme.Spacing.lg)

    local ownerSearchBox = addon.UIFactory.CreateSearchBox(directory, "CHARACTER_SEARCH_PLACEHOLDER")
    ownerSearchBox:SetPoint("TOPLEFT", directory, "TOPLEFT")
    ownerSearchBox:SetPoint("TOPRIGHT", directory, "TOPRIGHT")

    local ownerSection = createListSection(directory, addon.L("ARCHIVE_CHARACTERS"), theme.Sizes.archiveRowHeight, false)
    ownerSection:SetPoint("TOPLEFT", ownerSearchBox, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    ownerSection:SetPoint("TOPRIGHT", ownerSearchBox, "BOTTOMRIGHT", 0, -theme.Spacing.sm)
    local bookSection = createListSection(directory, addon.L("ARCHIVE_SPELLBOOKS"), theme.Sizes.archiveBookRowHeight, true)
    bookSection:SetPoint("TOPLEFT", ownerSection, "BOTTOMLEFT", 0, -theme.Spacing.md)
    bookSection:SetPoint("TOPRIGHT", ownerSection, "BOTTOMRIGHT", 0, -theme.Spacing.md)
    bookSection:SetPoint("BOTTOM", directory, "BOTTOM")

    local bookHost = CreateFrame("Frame", nil, panel)
    bookHost:SetPoint("TOPLEFT", directory, "TOPRIGHT", theme.Spacing.md, 0)
    bookHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)
    local bookPanel = addon.SpellbookPanel.Create(bookHost)
    bookPanel:Hide()

    local emptyState = addon.UIFactory.CreateLabel(bookHost, theme.Fonts.body, addon.L("ARCHIVE_SELECT_BOOK"), theme.Colors.textMuted)
    emptyState:SetPoint("LEFT", bookHost, "LEFT", theme.Spacing.lg, 0)
    emptyState:SetPoint("RIGHT", bookHost, "RIGHT", -theme.Spacing.lg, 0)
    emptyState:SetWordWrap(true)
    emptyState:SetJustifyH("CENTER")

    panel.directory = directory
    panel.ownerSearchBox = ownerSearchBox
    panel.deleteButton = deleteButton
    panel.ownerSection = ownerSection
    panel.bookSection = bookSection
    panel.bookPanel = bookPanel
    panel.emptyState = emptyState

    importButton:SetScript("OnClick", function()
        addon.ImportWindow.Open(function(book)
            addon.ImportedLibraryPanel.Refresh(panel, book and book.id)
        end)
    end)

    deleteButton:SetScript("OnClick", function()
        local bookGroup = panel.selectedBookGroup
        if not bookGroup or not bookGroup.importID then
            return
        end

        addon.UIFactory.ShowConfirmation(
            addon.L("DELETE_IMPORT_TITLE"),
            addon.L(
                "DELETE_IMPORT_CONFIRM",
                bookGroup.displayName .. " - " .. formatImportDate(bookGroup.latestImportedAt)
            ),
            function()
                local deleted, errorMessage = addon.Database.DeleteImportedBook(bookGroup.importID)
                if not deleted then
                    addon.Logger.Error(errorMessage or addon.L("IMPORTED_BOOK_NOT_FOUND"))
                    return
                end
                addon.ImportedLibraryPanel.Refresh(panel)
            end
        )
    end)

    ownerSearchBox:HookScript("OnTextChanged", function()
        local previousOwner = panel.owners[panel.selectedOwnerIndex]
        local previousBook = previousOwner and previousOwner.books[panel.selectedBookIndex]
        panel.ownerSection.page = 1
        panel.bookSection.page = 1
        updateOwnerFilter(
            panel,
            nil,
            previousOwner and previousOwner.key,
            previousBook and previousBook.importID
        )
    end)

    for _, button in ipairs(ownerSection.buttons) do
        button:SetScript("OnClick", function(self)
            if not self.ownerIndex then return end
            panel.selectedOwnerIndex = self.ownerIndex
            panel.selectedBookIndex = 1
            panel.bookSection.page = 1
            renderOwners(panel)
            renderBooks(panel)
        end)
    end
    for _, button in ipairs(bookSection.buttons) do
        button:SetScript("OnClick", function(self)
            if not self.bookIndex then return end
            panel.selectedBookIndex = self.bookIndex
            renderBooks(panel)
        end)
    end
    ownerSection.previousButton:SetScript("OnClick", function()
        ownerSection.page = ownerSection.page - 1
        renderOwners(panel)
    end)
    ownerSection.nextButton:SetScript("OnClick", function()
        ownerSection.page = ownerSection.page + 1
        renderOwners(panel)
    end)
    bookSection.previousButton:SetScript("OnClick", function()
        bookSection.page = bookSection.page - 1
        renderBooks(panel)
    end)
    bookSection.nextButton:SetScript("OnClick", function()
        bookSection.page = bookSection.page + 1
        renderBooks(panel)
    end)

    local layoutPending = false
    local function requestLayout()
        if layoutPending then return end
        layoutPending = true
        local function update()
            layoutPending = false
            layoutPanel(panel)
            selectVisiblePages(panel)
            renderOwners(panel)
            renderBooks(panel)
        end
        if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, update) else update() end
    end
    panel:SetScript("OnSizeChanged", requestLayout)
    panel:SetScript("OnShow", function()
        requestLayout()
        addon.ImportedLibraryPanel.Refresh(panel)
    end)
    panel:SetScript("OnHide", function()
        cancelExpirationTimer(panel)
        ownerSearchBox:ClearFocus()
    end)
    ownerSection:SetScript("OnSizeChanged", requestLayout)
    bookSection:SetScript("OnSizeChanged", requestLayout)
    panel.requestLayout = requestLayout
    layoutPanel(panel)
    return panel
end

function addon.ImportedLibraryPanel.Refresh(panel, preferredImportID)
    local previousOwner = panel.owners[panel.selectedOwnerIndex]
    local previousBook = previousOwner and previousOwner.books[panel.selectedBookIndex]
    panel.allOwners = addon.ImportedLibrary.BuildIndex(addon.Database.ListImportedBooks())
    if panel.storageStats then
        local stats = addon.Database.GetStorageStats()
        local summary = addon.L("REVIEW_STORAGE_STATS", stats.profiles, stats.imports,
            stats.personalSpells + stats.importedSpells, stats.scenes, stats.rounds,
            stats.estimatedBytes / (1024 * 1024))
        if stats.partial then summary = addon.L("REVIEW_STORAGE_PARTIAL") .. " " .. summary end
        if stats.warning then summary = summary .. "\n" .. addon.L("REVIEW_STORAGE_WARNING") end
        panel.storageStats:SetText(summary)
        local color = stats.warning and addon.Theme.Colors.error or addon.Theme.Colors.textMuted
        panel.storageStats:SetTextColor(unpack(color))
    end
    updateOwnerFilter(
        panel,
        preferredImportID,
        previousOwner and previousOwner.key,
        previousBook and previousBook.importID
    )
    if panel.requestLayout then panel.requestLayout() end
    scheduleExpirationRefresh(panel)
end
