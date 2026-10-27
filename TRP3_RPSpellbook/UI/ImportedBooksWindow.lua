local _, addon = ...

addon.ImportedBooksWindow = {}

local window
local state = {
    page = 1,
}

local function setButtonEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end

local function formatBookLabel(book)
    local owner = addon.Import.GetOwnerDisplayName(book.owner)
    local suffix = addon.Database.IsImportedBookExpired(book) and addon.L("IMPORTED_EXPIRED_SUFFIX") or ""
    return string.format("%s — %s%s", book.name or addon.L("UNKNOWN"), owner, suffix)
end

local function render()
    state.books = addon.Database.ListImportedBooks()
    local perPage = addon.Theme.Sizes.importBooksPerPage
    local pageCount = math.max(1, math.ceil(#state.books / perPage))
    state.page = math.max(1, math.min(state.page, pageCount))
    local firstIndex = ((state.page - 1) * perPage) + 1

    for index, button in ipairs(window.bookButtons) do
        local book = state.books[firstIndex + index - 1]
        button.book = book
        if book then
            button:SetText(formatBookLabel(book))
            button:Show()
        else
            button:Hide()
        end
    end
    window.emptyState:SetShown(#state.books == 0)
    window.pageLabel:SetText(addon.L("PAGE_FORMAT", state.page, pageCount))
    setButtonEnabled(window.previousButton, state.page > 1)
    setButtonEnabled(window.nextButton, state.page < pageCount)
end

local function createWindow()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("IMPORTED_BOOKS"),
        theme.Sizes.importLibraryWidth,
        theme.Sizes.importLibraryHeight
    )

    local intro = addon.UIFactory.CreateLabel(frame, theme.Fonts.small, addon.L("IMPORTED_BOOKS_HINT"), theme.Colors.textMuted)
    intro:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -(theme.Spacing.xl + theme.Spacing.lg))
    intro:SetWidth(theme.Sizes.importLibraryWidth - (theme.Spacing.lg * 2))
    intro:SetWordWrap(true)
    intro:SetJustifyH("LEFT")

    local bookButtons = {}
    local anchor = intro
    for index = 1, theme.Sizes.importBooksPerPage do
        local button = addon.UIFactory.CreateButton(frame, "", theme.Sizes.importLibraryWidth - (theme.Spacing.lg * 2))
        button:SetHeight(theme.Sizes.importBookRowHeight)
        button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -theme.Spacing.xs)
        button:SetScript("OnClick", function(self)
            if not self.book then return end
            local callback = state.onSelect
            frame:Hide()
            if type(callback) == "function" then callback(self.book) end
        end)
        bookButtons[index] = button
        anchor = button
    end

    local emptyState = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, addon.L("NO_IMPORTED_BOOKS"), theme.Colors.textMuted)
    emptyState:SetPoint("CENTER")

    local nextButton = addon.UIFactory.CreateButton(frame, ">", theme.Sizes.pageButtonWidth)
    nextButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)
    local pageLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, "", theme.Colors.textMuted)
    pageLabel:SetPoint("RIGHT", nextButton, "LEFT", -theme.Spacing.sm, 0)
    local previousButton = addon.UIFactory.CreateButton(frame, "<", theme.Sizes.pageButtonWidth)
    previousButton:SetPoint("RIGHT", pageLabel, "LEFT", -theme.Spacing.sm, 0)

    frame.bookButtons = bookButtons
    frame.emptyState = emptyState
    frame.nextButton = nextButton
    frame.pageLabel = pageLabel
    frame.previousButton = previousButton
    previousButton:SetScript("OnClick", function() state.page = state.page - 1 render() end)
    nextButton:SetScript("OnClick", function() state.page = state.page + 1 render() end)
    if addon.SeasonalVisuals then addon.SeasonalVisuals.Attach(frame, "import") end
    return frame
end

function addon.ImportedBooksWindow.Open(onSelect)
    window = window or createWindow()
    state.onSelect = onSelect
    state.page = 1
    render()
    window:Show()
    addon.UIFactory.BringToFront(window)
end
