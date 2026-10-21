local _, addon = ...

addon.GameMasterCompactSpellbook = {}

local window
local sessionWasActive = false
local state = {
    activeTabID = nil,
    favoritesOnly = false,
    results = {},
    tabOffset = 1,
}
local tutorialFilters

function addon.GameMasterCompactSpellbook.GetTutorialContext() return window, state end

function addon.GameMasterCompactSpellbook.SetTutorialFilters(enabled)
    if enabled then
        if tutorialFilters then return end
        tutorialFilters = { activeTabID = state.activeTabID, favoritesOnly = state.favoritesOnly,
            tabOffset = state.tabOffset, query = window and window.searchBox:GetText() or "" }
        state.activeTabID, state.favoritesOnly, state.tabOffset = nil, false, 1
        if window then window.searchBox:SetText(""); window.favoriteFilter:SetText("*") end
    elseif tutorialFilters then
        local saved = tutorialFilters
        tutorialFilters = nil
        state.activeTabID, state.favoritesOnly, state.tabOffset = saved.activeTabID, saved.favoritesOnly, saved.tabOffset
        if window then
            window.searchBox:SetText(saved.query)
            window.favoriteFilter:SetText(saved.favoritesOnly and "x" or "*")
        end
    end
end

local DEFAULT_WIDTH = 380
local DEFAULT_HEIGHT = 500
local COLLAPSED_WIDTH = 300
local COLLAPSED_HEIGHT = 38
local MIN_WIDTH = 175
local MIN_HEIGHT = 165
local MAX_WIDTH = 1600
local MAX_HEIGHT = 1600
local MAX_VISIBLE_ROWS = 320
local LOCKED_TEXTURE = "Interface\\Buttons\\LockButton-Locked-Up"
local UNLOCKED_TEXTURE = "Interface\\Buttons\\LockButton-Unlocked-Up"
local VISIBLE_TABS = 2

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function setEnabled(button, enabled)
    addon.GameMasterWidgets.SetEnabled(button, enabled == true)
end

local function getBook()
    if state.actorID then
        local actor = addon.GameMasterService.GetNPCActor(state.actorID)
        if actor then
            local book = { id = actor.id, profileKey = "npc-register", name = actor.name, icon = actor.icon,
                spells = {}, tabs = { companion = { id = "companion", name = actor.name, spellIds = {} } }, tabOrder = { "companion" } }
            for _, spell in ipairs(actor.spells or {}) do
                book.spells[spell.id] = spell
                book.tabs.companion.spellIds[#book.tabs.companion.spellIds + 1] = spell.id
            end
            return book
        end
        state.actorID, state.activeTabID = nil, nil
    end
    return addon.GameMasterService.GetActionSpellbook and addon.GameMasterService.GetActionSpellbook()
        or addon.Database.GetActiveSpellbook()
end

local function getMetrics()
    return addon.GameMasterSettings.GetWindowMetrics(
        "compactSpellbook", window, 12
    )
end

local function getCollectionMetrics()
    local metrics = getMetrics()
    if not window or not window.listViewport then
        return nil
    end
    return addon.GameMasterLayout.GetCollectionMetrics(
        "compactSpellbook",
        math.max(1, (tonumber(window.listViewport:GetWidth()) or 1) - 28),
        math.max(1, (tonumber(window.listViewport:GetHeight()) or 1) - 8),
        #state.results,
        metrics and metrics.fontSize or 12,
        addon.GameMasterSettings.GetCompactStyle()
    )
end

local function getRowHeight()
    local grid = window and window.collectionMetrics
        or getCollectionMetrics()
    return grid and grid.rowHeight or 30
end
local function getVisibleTabCount()
    local metrics = getMetrics()
    if window and window:GetWidth() < 300 then
        return 1
    end
    return VISIBLE_TABS
end
local function getActiveTab(book)
    if type(book) ~= "table"
        or type(book.tabs) ~= "table"
        or type(book.tabOrder) ~= "table"
    then
        return nil
    end
    if state.activeTabID and book.tabs[state.activeTabID] then
        return state.activeTabID
    end
    state.activeTabID = book.tabOrder[1]
    return state.activeTabID
end

local function getScrollMaximum()
    if not window then
        return 0
    end
    local grid = getCollectionMetrics()
    if not grid then
        return 0
    end
    return math.max(
        0,
        grid.contentHeight
            - math.max(1, window.listViewport:GetHeight() - 8)
    )
end
local function setScroll(value)
    local offset = clamp(value, 0, getScrollMaximum())
    window.listScroll:SetVerticalScroll(offset)
    return offset
end

local function scrollBy(delta)
    setScroll(
        window.listScroll:GetVerticalScroll()
            - (delta * getRowHeight() * 3)
    )
    window.refreshRows()
end

local function setSpellRow(row, spell)
    row.spell = spell
    if type(spell) ~= "table" then
        addon.UIFactory.ClearSpellIconEffectFrame(row.icon)
        if row.favorite then
            row.favorite:Hide()
        end
        row:Hide()
        return
    end

    addon.UIFactory.SetSpellIcon(
        row.icon, spell, addon.Constants.DEFAULT_BOOK_ICON,
        type(row.icon.IsShown) ~= "function" or row.icon:IsShown()
    )
    row.name:SetText(spell.name or addon.L("UNKNOWN_ABILITY"))
    addon.UIFactory.SetFontColor(
        row.name,
        spell.nameColor,
        addon.Theme.Colors.text
    )
    row.favorite:SetShown(not state.actorID and addon.GameMasterService.IsActionSpellFavorite(spell.id))
    local canSubmit = state.actorID and addon.GameMasterService.CanSubmitNPC(state.actorID)
        or not state.actorID and addon.GameMasterService.CanSubmit()
    row:SetAlpha(canSubmit and 1 or 0.55)
    row:Show()
end

local function refreshRows()
    if not window then
        return
    end

    local book = getBook()
    local grid = getCollectionMetrics()
    if not grid then
        return
    end
    window.collectionMetrics = grid
    local rowStride = grid.rowHeight + grid.gap
    local viewportHeight = math.max(1, window.listViewport:GetHeight() - 8)
    local visibleGridRows = math.max(
        1,
        math.ceil(viewportHeight / rowStride) + 1
    )
    local visibleCount = math.min(
        MAX_VISIBLE_ROWS,
        visibleGridRows * grid.columns
    )
    local offset = setScroll(window.listScroll:GetVerticalScroll())
    local firstGridRow = math.floor(offset / rowStride)
    local first = (firstGridRow * grid.columns) + 1
    local remainder = offset % rowStride
    local style = addon.Theme.GetGameMasterStyle(
        addon.GameMasterSettings.GetCompactStyle()
    )
    local showIcons = addon.GameMasterSettings.ShouldShowCompactIcons()
    local showBorder = addon.GameMasterSettings
        .ShouldShowWindowBorder("compactSpellbook")
    local rowBorder = showBorder
        and style.rowBorder or { 0, 0, 0, 0 }

    for index, row in ipairs(window.rows) do
        row:ClearAllPoints()
        if index <= visibleCount then
            local resultIndex = first + index - 1
            local spellID = state.results[resultIndex]
            local spell = spellID
                and type(book) == "table"
                and type(book.spells) == "table"
                and book.spells[spellID]
                or nil
            local localIndex = index - 1
            local column = localIndex % grid.columns
            local gridRow = math.floor(localIndex / grid.columns)
            row:SetSize(grid.cardWidth, grid.rowHeight)
            row:SetPoint(
                "TOPLEFT",
                window.listViewport,
                "TOPLEFT",
                4 + (column * (grid.cardWidth + grid.gap)),
                -4 - remainder - (gridRow * rowStride)
            )
            local background = resultIndex % 2 == 0
                and style.rowBackgroundEven
                or style.rowBackgroundOdd
            row:SetBackdropColor(
                background[1], background[2], background[3], background[4]
            )
            row:SetBackdropBorderColor(
                rowBorder[1], rowBorder[2], rowBorder[3], rowBorder[4]
            )
            row.icon:SetSize(grid.rowHeight - 6, grid.rowHeight - 6)
            row.icon:SetShown(showIcons)
            row.name:ClearAllPoints()
            if showIcons then
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            else
                row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
            end
            row.name:SetPoint("RIGHT", row, "RIGHT", -18, 0)
            addon.GameMasterWidgets.SetFontSize(row.name, grid.fontSize)
            setSpellRow(row, spell)
        else
            row:Hide()
        end
    end

    window.scrollChild:SetHeight(math.max(
        viewportHeight,
        grid.contentHeight
    ))
    window.scrollChild:SetWidth(
        math.max(1, window.listScroll:GetWidth())
    )
    window.listScroll:UpdateScrollChildRect()
    window.empty:SetShown(#state.results == 0)
end
local function updateResults(resetScroll)
    if not window then
        return
    end
    local book = getBook()
    local activeTabID = getActiveTab(book)
    state.results = addon.Search.FindSpellIDs(
        book,
        activeTabID,
        window.searchBox:GetText(),
        { favoritesOnly = state.favoritesOnly }
    )
    if resetScroll then
        window.listScroll:SetVerticalScroll(0)
    end
    refreshRows()
end

local function ensureActiveTabVisible(book)
    local visibleTabs = getVisibleTabCount()
    local activeIndex = 1
    for index, tabID in ipairs(book.tabOrder or {}) do
        if tabID == state.activeTabID then
            activeIndex = index
            break
        end
    end
    if activeIndex < state.tabOffset then
        state.tabOffset = activeIndex
    elseif activeIndex >= state.tabOffset + visibleTabs then
        state.tabOffset = activeIndex - visibleTabs + 1
    end
end
local function refreshTabs()
    if not window then
        return
    end
    local book = getBook()
    if type(book) ~= "table" then
        return
    end

    getActiveTab(book)
    local tabCount = #(book.tabOrder or {})
    local visibleTabs = getVisibleTabCount()
    state.tabOffset = clamp(
        state.tabOffset,
        1,
        math.max(1, tabCount - visibleTabs + 1)
    )
    ensureActiveTabVisible(book)

    local activeIndex = 1
    for index, tabID in ipairs(book.tabOrder or {}) do
        if tabID == state.activeTabID then
            activeIndex = index
            break
        end
    end
    local arrowsVisible = tabCount > visibleTabs
    window.previousTab:SetShown(arrowsVisible)
    window.nextTab:SetShown(arrowsVisible)
    setEnabled(window.previousTab, arrowsVisible and activeIndex > 1)
    setEnabled(
        window.nextTab,
        arrowsVisible and activeIndex < tabCount
    )

    local availableWidth = math.max(80, window.tabBar:GetWidth())
    local reserved = arrowsVisible and 56 or 0
    local buttonWidth = math.max(
        70,
        math.floor((availableWidth - reserved - 4) / visibleTabs)
    )
    local anchor = arrowsVisible and window.previousTab or window.tabBar
    local anchorPoint = arrowsVisible and "RIGHT" or "LEFT"
    local style = addon.Theme.GetGameMasterStyle(
        addon.GameMasterSettings.GetCompactStyle()
    )
    for buttonIndex, button in ipairs(window.tabButtons) do
        local tabID = buttonIndex <= visibleTabs
            and book.tabOrder[state.tabOffset + buttonIndex - 1]
            or nil
        button:ClearAllPoints()
        if tabID then
            local tab = book.tabs[tabID]
            button.tabID = tabID
            button:SetWidth(buttonWidth)
            button:SetPoint("LEFT", anchor, anchorPoint, 2, 0)
            button.label:SetText(tab and tab.name or "?")
            addon.UIFactory.SetIconTexture(
                button.icon,
                tab and tab.icon,
                addon.Constants.DEFAULT_TAB_ICON
            )
            local selected = tabID == state.activeTabID
            local background = buttonIndex % 2 == 0
                and style.rowBackgroundEven
                or style.rowBackgroundOdd
            button:SetBackdropColor(
                background[1],
                background[2],
                background[3],
                background[4]
            )
            local border = selected
                and addon.Theme.Colors.gold
                or style.rowBorder
            button:SetBackdropBorderColor(
                border[1],
                border[2],
                border[3],
                border[4]
            )
            button:Show()
            anchor = button
            anchorPoint = "RIGHT"
        else
            button.tabID = nil
            button:Hide()
        end
    end
end

local function applyFontSettings()
    if not window then
        return
    end
    local metrics = getMetrics()
    local size = metrics and metrics.fontSize
        or addon.GameMasterSettings.GetCompactFontSize()
    addon.GameMasterWidgets.SetFontSize(window.title, size, 2)
    addon.GameMasterWidgets.SetFontSize(window.status, size, -1)
    for _, button in ipairs(window.tabButtons) do
        addon.GameMasterWidgets.SetFontSize(button.label, size, -1)
    end
    for _, row in ipairs(window.rows) do
        addon.GameMasterWidgets.SetFontSize(row.name, size)
    end
end

local function applyStyle()
    if not window then
        return
    end
    local styleName = addon.GameMasterSettings.GetCompactStyle()
    local style = addon.Theme.GetGameMasterStyle(styleName)
    local minimal = styleName == "minimal"
    local windowWidth = window:GetWidth() or DEFAULT_WIDTH
    local hideBookIcon = minimal or windowWidth < 225
    window:SetBackdropColor(
        style.frameBackground[1],
        style.frameBackground[2],
        style.frameBackground[3],
        style.frameBackground[4]
    )
    local showBorder = addon.GameMasterSettings
        .ShouldShowWindowBorder("compactSpellbook")
    local frameBorder = showBorder
        and style.frameBorder or { 0, 0, 0, 0 }
    window:SetBackdropBorderColor(
        frameBorder[1],
        frameBorder[2],
        frameBorder[3],
        frameBorder[4]
    )
    window.listViewport:SetBackdropColor(
        style.panelBackground[1],
        style.panelBackground[2],
        style.panelBackground[3],
        style.panelBackground[4]
    )
    local panelBorder = showBorder
        and style.panelBorder or { 0, 0, 0, 0 }
    window.listViewport:SetBackdropBorderColor(
        panelBorder[1],
        panelBorder[2],
        panelBorder[3],
        panelBorder[4]
    )
    window.title:Hide()
    window.bookIcon:SetShown(not hideBookIcon)
    if not hideBookIcon then
        window.bookIcon:ClearAllPoints()
        window.bookIcon:SetPoint("TOPLEFT", window, "TOPLEFT", 34, -7)
    end
    for _, button in ipairs(window.styleButtons) do
        addon.UIFactory.ApplyButtonStyle(button, styleName)
    end
    addon.UIFactory.ApplyButtonStyle(window.collapseButton, styleName)
    window:SetAlpha(addon.GameMasterSettings.GetCompactOpacity())
    applyFontSettings()
end
local function saveLayout(saveSize)
    addon.GameMasterLayout.SaveFrameLayout(
        "compactSpellbook", window, saveSize
    )
end

local function updateResizeLock()
    if not window then
        return
    end
    local collapsed = addon.GameMasterStore.IsCompactCollapsed()
    local locked = addon.GameMasterStore.IsCompactLocked()
    window:SetResizable(not collapsed and not locked)
    window.resize:SetShown(not collapsed and not locked)
    window.lockTexture:SetTexture(
        locked and LOCKED_TEXTURE or UNLOCKED_TEXTURE
    )
    window.lockButton:SetAlpha(locked and 0.95 or 0.72)
end

local function anchorTopLeft()
    local left = window:GetLeft()
    local top = window:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then
        return false
    end
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return true
end

local function anchorTopRight()
    local right = window:GetRight()
    local top = window:GetTop()
    if type(right) ~= "number" or type(top) ~= "number" then
        return false
    end
    window:ClearAllPoints()
    window:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    return true
end

local function updateCollapsed()
    local collapsed = addon.GameMasterStore.IsCompactCollapsed()
    local changed = window.appliedCollapsed ~= collapsed
    if collapsed then
        if changed then
            saveLayout(true)
            anchorTopRight()
            window.appliedCollapsed = true
            window:SetSize(COLLAPSED_WIDTH, COLLAPSED_HEIGHT)
        end
    elseif changed then
        local module = addon.GameMasterLayout.GetModule(
            "compactSpellbook"
        )
        local layout = module and module.layout or {}
        anchorTopRight()
        window.appliedCollapsed = false
        window:SetSize(
            clamp(layout.width or DEFAULT_WIDTH, MIN_WIDTH, MAX_WIDTH),
            clamp(layout.height or DEFAULT_HEIGHT, MIN_HEIGHT, MAX_HEIGHT)
        )
    end
    window.appliedCollapsed = collapsed
    if window.actorSelector then window.actorSelector:SetShown(not collapsed and #(window.actorSelector.options or {}) > 1) end
    for _, region in ipairs(window.expandableRegions) do
        region:SetShown(not collapsed)
    end
    addon.UIFactory.SetWindowMinimizeState(window.collapseButton, collapsed)
    updateResizeLock()

    if changed and not collapsed then
        refreshTabs()
        updateResults(false)
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                if window
                    and window:IsShown()
                    and not addon.GameMasterStore.IsCompactCollapsed()
                then
                    refreshTabs()
                    updateResults(false)
                end
            end)
        end
    end
end

local function refreshStatus()
    if state.actorID and addon.GameMasterService.CanSubmitNPC(state.actorID)
        or not state.actorID and addon.GameMasterService.CanSubmit() then
        local context = state.actorID and addon.GameMasterService.GetNPCSubmissionContext(state.actorID)
            or addon.GameMasterService.GetSubmissionContext()
        window.status:SetText(addon.L(
            "GAMEMASTER_COMPACT_ROUND",
            context and context.roundNumber or 0
        ))
        window.status:SetTextColor(0.38, 0.85, 0.45, 1)
    else
        window.status:SetText(addon.L("GAMEMASTER_NO_OPEN_ROUND"))
        window.status:SetTextColor(0.76, 0.69, 0.56, 1)
    end
end

local function refresh()
    if not window then
        return
    end
    if not addon.GameMasterService.IsSessionActive() then
        window:Hide()
        return
    end
    if window.actorSelector then
        local actors = addon.GameMasterService.GetControlledNPCs and addon.GameMasterService.GetControlledNPCs() or {}
        local options = { { label = addon.L("GAMEMASTER_NPC_SELF"), value = "self" } }
        local found = not state.actorID
        for _, actor in ipairs(actors) do
            options[#options + 1] = { label = actor.name, value = actor.id, icon = actor.icon }
            if state.actorID == actor.id then found = true end
        end
        if not found then state.actorID, state.activeTabID = nil, nil end
        window.actorSelector:SetOptions(options, state.actorID or "self")
        window.actorSelector:SetShown(#actors > 0 and not addon.GameMasterStore.IsCompactCollapsed())
        window.searchBox:ClearAllPoints()
        window.searchBox:SetPoint("TOPLEFT", window, "TOPLEFT", addon.Theme.Spacing.sm, #actors > 0 and -66 or -38)
        window.searchBox:SetPoint("TOPRIGHT", window, "TOPRIGHT", -38, #actors > 0 and -66 or -38)
    end
    local book = getBook()
    if type(book) ~= "table" then
        window:Hide()
        return
    end

    local visibility = addon.GameMasterService.GetVisibility()
    window.visibilityButton:SetVisibilityMode(visibility)
    window.visibilityButton:SetShown(
        visibility ~= "hidden"
            and not addon.GameMasterService.IsActiveGameMaster()
    )

    applyStyle()
    updateCollapsed()
    if state.actorID then state.favoritesOnly = false end
    window.favoriteFilter:SetEnabled(not state.actorID)
    window.favoriteFilter:SetText(state.favoritesOnly and "x" or "*")
    addon.UIFactory.SetIconTexture(
        window.bookIcon,
        book.icon,
        addon.Constants.DEFAULT_BOOK_ICON
    )
    refreshStatus()
    refreshTabs()
    updateResults(false)
end

local function restoreLayout()
    addon.GameMasterLayout.ApplyFrameLayout(
        "compactSpellbook",
        window,
        true
    )
end

local function createWindow()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("GAMEMASTER_COMPACT_TITLE"),
        DEFAULT_WIDTH,
        DEFAULT_HEIGHT
    )
    addon.UIFactory.ConfigureInformationWindow(frame)
    frame:SetResizable(true)
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    else
        frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
        frame:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
    end

    local bookIcon = frame:CreateTexture(nil, "ARTWORK")
    bookIcon:SetSize(24, 24)
    bookIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 34, -7)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", bookIcon, "RIGHT", theme.Spacing.sm, 0)
    frame.title:SetWidth(175)
    frame.title:SetWordWrap(false)
    frame.title:Hide()

    local collapseButton = addon.UIFactory.CreateWindowMinimizeButton(frame, function()
        addon.GameMasterStore.SetCompactCollapsed(
            not addon.GameMasterStore.IsCompactCollapsed()
        )
        updateCollapsed()
        saveLayout(false)
    end)

    local lockButton = CreateFrame("Button", nil, frame)
    lockButton:SetSize(22, 22)
    lockButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -6)
    local lockTexture = lockButton:CreateTexture(nil, "ARTWORK")
    lockTexture:SetAllPoints()
    lockButton:SetScript("OnClick", function()
        addon.GameMasterStore.SetCompactLocked(
            not addon.GameMasterStore.IsCompactLocked()
        )
        updateResizeLock()
    end)
    lockButton:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(addon.L(
            addon.GameMasterStore.IsCompactLocked()
                and "GAMEMASTER_COMPACT_SIZE_UNLOCK"
                or "GAMEMASTER_COMPACT_SIZE_LOCK"
        ))
        GameTooltip:Show()
    end)
    lockButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
        updateResizeLock()
    end)

    local settingsButton = addon.UIFactory.CreateTextureButton(
        frame,
        "Interface\\Buttons\\UI-OptionsButton",
        22
    )
    settingsButton:SetPoint(
        "RIGHT",
        collapseButton,
        "LEFT",
        -theme.Spacing.xs,
        0
    )
    settingsButton:SetScript("OnClick", function()
        addon.GameMasterSettings.Open()
    end)
    settingsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(addon.L("SETTINGS"))
        GameTooltip:Show()
    end)
    settingsButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    local visibilityButton = addon.GameMasterVisibilityButton.Create(
        frame,
        function()
            addon.GameMasterSharedActions.Open()
        end,
        "GAMEMASTER_SHARED_ACTIONS_BUTTON_HELP"
    )
    visibilityButton:SetPoint(
        "RIGHT",
        settingsButton,
        "LEFT",
        -theme.Spacing.xs,
        0
    )

    local actorSelector = addon.GameMasterWidgets.CreateSelector(frame, 160)
    actorSelector:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.sm, -36)
    actorSelector:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.sm, -36)
    actorSelector:Hide()
    actorSelector:SetOnValueChanged(function(value)
        state.actorID = value ~= "self" and value or nil
        state.activeTabID, state.tabOffset, state.favoritesOnly = nil, 1, false
        refresh()
    end)
    local searchBox = addon.UIFactory.CreateSearchBox(frame)
    searchBox:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        theme.Spacing.sm,
        -38
    )
    searchBox:SetPoint(
        "TOPRIGHT",
        frame,
        "TOPRIGHT",
        -38,
        -38
    )

    local favoriteFilter = addon.UIFactory.CreateButton(frame, "*", 26)
    favoriteFilter:SetPoint("LEFT", searchBox, "RIGHT", theme.Spacing.xs, 0)
    favoriteFilter:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addon.L("FAVORITES_ONLY"))
        GameTooltip:Show()
    end)
    favoriteFilter:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    favoriteFilter:SetScript("OnClick", function()
        if state.actorID then return end
        state.favoritesOnly = not state.favoritesOnly
        favoriteFilter:SetText(state.favoritesOnly and "x" or "*")
        updateResults(true)
    end)

    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint(
        "TOPLEFT",
        searchBox,
        "BOTTOMLEFT",
        0,
        -theme.Spacing.xs
    )
    tabBar:SetPoint("RIGHT", searchBox, "RIGHT", 0, 0)
    tabBar:SetHeight(26)

    local previousTab = addon.UIFactory.CreateButton(tabBar, "<", 26)
    previousTab:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
    local nextTab = addon.UIFactory.CreateButton(tabBar, ">", 26)
    nextTab:SetPoint("RIGHT", tabBar, "RIGHT", 0, 0)

    local tabButtons = {}
    for index = 1, VISIBLE_TABS do
        local button = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        button:SetHeight(26)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        button:SetBackdropColor(0.11, 0.08, 0.045, 0.84)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", button, "LEFT", 4, 0)
        local label = addon.UIFactory.CreateLabel(
            button,
            theme.Fonts.small,
            "",
            theme.Colors.text
        )
        label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        label:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)

        button.icon = icon
        button.label = label
        button:SetScript("OnClick", function(self)
            if self.tabID then
                state.activeTabID = self.tabID
                updateResults(true)
                refreshTabs()
            end
        end)
        tabButtons[index] = button
    end

    previousTab:SetScript("OnClick", function()
        local book = getBook()
        local activeTabID = getActiveTab(book)
        for index, tabID in ipairs(book and book.tabOrder or {}) do
            if tabID == activeTabID and index > 1 then
                state.activeTabID = book.tabOrder[index - 1]
                updateResults(true)
                refreshTabs()
                break
            end
        end
    end)
    nextTab:SetScript("OnClick", function()
        local book = getBook()
        local activeTabID = getActiveTab(book)
        for index, tabID in ipairs(book and book.tabOrder or {}) do
            if tabID == activeTabID and index < #book.tabOrder then
                state.activeTabID = book.tabOrder[index + 1]
                updateResults(true)
                refreshTabs()
                break
            end
        end
    end)

    local status = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.small,
        "",
        theme.Colors.textMuted
    )
    status:SetPoint(
        "BOTTOMLEFT",
        frame,
        "BOTTOMLEFT",
        theme.Spacing.sm,
        theme.Spacing.sm
    )
    status:SetPoint("RIGHT", frame, "RIGHT", -32, 0)
    status:SetWordWrap(false)

    local listViewport = addon.GameMasterWidgets.CreateSection(frame)
    listViewport:SetPoint(
        "TOPLEFT",
        tabBar,
        "BOTTOMLEFT",
        0,
        -theme.Spacing.xs
    )
    listViewport:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -theme.Spacing.sm,
        34
    )
    listViewport:SetClipsChildren(true)

    local listScroll = addon.GameMasterWidgets.CreateScrollViewport(listViewport)
    listScroll:SetPoint("TOPLEFT", listViewport, "TOPLEFT", 0, 0)
    listScroll:SetPoint(
        "BOTTOMRIGHT",
        listViewport,
        "BOTTOMRIGHT",
        -2,
        0
    )

    local scrollChild = CreateFrame("Frame", nil, listScroll)
    scrollChild:SetPoint("TOPLEFT", listScroll, "TOPLEFT", 0, 0)
    scrollChild:SetSize(1, 1)
    listScroll:SetScrollChild(scrollChild)
    listScroll:EnableMouseWheel(true)

    local rows = {}
    for index = 1, MAX_VISIBLE_ROWS do
        local row = CreateFrame(
            "Button",
            nil,
            listViewport,
            "BackdropTemplate"
        )
        row:SetFrameLevel(listScroll:GetFrameLevel() + 3)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("LEFT", row, "LEFT", 3, 0)
        local name = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.small,
            "",
            theme.Colors.text
        )
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetPoint("RIGHT", row, "RIGHT", -18, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)

        row.icon = icon
        row.name = name
        local favorite = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.body,
            "*",
            theme.Colors.gold
        )
        favorite:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.favorite = favorite
        row:SetScript("OnEnter", function(self)
            if self.spell then
                addon.SpellTooltip.Show(
                    self,
                    self.spell,
                    false,
                    "ANCHOR_RIGHT",
                    { showChatHint = true }
                )
            end
        end)
        row:SetScript("OnLeave", function()
            addon.SpellTooltip.Hide()
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            if self.spell and button == "LeftButton" and IsShiftKeyDown() then
                local book = getBook()
                local inserted, errorMessage = addon.ChatInsert.InsertSpell(book and book.profileKey, self.spell)
                if inserted and addon.Onboarding and addon.Onboarding.RecordAction then
                    addon.Onboarding.RecordAction("share_compact", self.spell.id)
                end
                if not inserted then addon.Logger.Error(errorMessage) end
            elseif self.spell and button == "RightButton" then
                if state.actorID then return end
                local changed, errorMessage = addon.GameMasterService.ToggleActionSpellFavorite(
                    self.spell.id
                )
                if not changed then
                    addon.Logger.Error(errorMessage)
                end
                updateResults(false)
            elseif self.spell then
                if state.actorID then
                    addon.GameMasterActionDialog.Open(self.spell, { npcActorID = state.actorID })
                else addon.GameMasterService.OpenAction(self.spell) end
            end
        end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            scrollBy(delta)
        end)
        rows[index] = row
    end

    local empty = addon.UIFactory.CreateLabel(
        listViewport,
        theme.Fonts.body,
        addon.L("NO_SEARCH_RESULTS"),
        theme.Colors.textMuted
    )
    empty:SetPoint("CENTER")

    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(18, 18)
    resize:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    local resizeTexture = resize:CreateTexture(nil, "ARTWORK")
    resizeTexture:SetAllPoints()
    resizeTexture:SetTexture(
        "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
    )
    resize:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton"
            or addon.GameMasterStore.IsCompactLocked()
            or addon.GameMasterStore.IsCompactCollapsed()
        then
            return
        end
        anchorTopLeft()
        frame.isUserResizing = true
        frame:StartSizing("BOTTOMRIGHT", true)
    end)
    resize:SetScript("OnMouseUp", function()
        if not frame.isUserResizing then
            return
        end
        frame:StopMovingOrSizing()
        frame.isUserResizing = false
        saveLayout(true)
        refreshTabs()
        updateResults(false)
    end)

    frame.bookIcon = bookIcon
    frame.collapseButton = collapseButton
    frame.empty = empty
    frame.favoriteFilter = favoriteFilter
    frame.expandableRegions = {
        searchBox,
        favoriteFilter,
        tabBar,
        listViewport,
        status,
        resize,
    }
    frame.lockButton = lockButton
    frame.lockTexture = lockTexture
    frame.listScroll = listScroll
    frame.listViewport = listViewport
    frame.nextTab = nextTab
    frame.previousTab = previousTab
    frame.refreshRows = refreshRows
    frame.resize = resize
    frame.rows = rows
    frame.scrollChild = scrollChild
    frame.searchBox = searchBox
    frame.actorSelector = actorSelector
    frame.settingsButton = settingsButton
    frame.visibilityButton = visibilityButton
    frame.status = status
    frame.styleButtons = {
        collapseButton,
        previousTab,
        nextTab,
    }
    frame.tabBar = tabBar
    frame.tabButtons = tabButtons

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveLayout(false)
    end)
    frame:SetScript("OnSizeChanged", function()
        if frame:IsShown()
            and not addon.GameMasterStore.IsCompactCollapsed()
        then
            applyStyle()
            refreshTabs()
            refreshRows()
        end
    end)
    frame:HookScript("OnHide", function(self)
        if self.isUserResizing then
            self:StopMovingOrSizing()
            self.isUserResizing = false
        end
    end)
    listScroll:SetScript("OnMouseWheel", function(_, delta)
        scrollBy(delta)
    end)
    listScroll:SetScript("OnVerticalScroll", function(self, offset)
        self:SetVerticalScroll(offset)
        refreshRows()
    end)
    listViewport:SetScript("OnSizeChanged", refreshRows)
    tabBar:SetScript("OnSizeChanged", refreshTabs)
    searchBox:HookScript("OnTextChanged", function()
        updateResults(true)
    end)
    return frame
end

function addon.GameMasterCompactSpellbook.Open(restoreWindow)
    if not addon.GameMasterService.IsSessionActive() then
        addon.Logger.Error(addon.L("GAMEMASTER_COMPACT_INACTIVE"))
        return false
    end
    window = window or createWindow()
    if restoreWindow == true then
        addon.GameMasterStore.SetCompactCollapsed(false)
    end
    local book = getBook()
    if type(book) ~= "table" then
        addon.Logger.Error(addon.L("ACTIVE_BOOK_UNAVAILABLE"))
        return false
    end

    window.appliedCollapsed = nil
    restoreLayout()
    getActiveTab(book)
    refresh()
    window:Show()
    addon.UIFactory.BringToFront(window)
    return true
end

function addon.GameMasterCompactSpellbook.Hide()
    if window then
        window:Hide()
    end
end

function addon.GameMasterCompactSpellbook.IsShown()
    return window ~= nil and window:IsShown() or false
end

function addon.GameMasterCompactSpellbook.Toggle()
    if window and window:IsShown() then
        window:Hide()
        return false
    end
    return addon.GameMasterCompactSpellbook.Open()
end

function addon.GameMasterCompactSpellbook.Refresh()
    if window and window:IsShown() then
        refresh()
    end
end

addon.GameMasterService.RegisterListener(function()
    local active = addon.GameMasterService.IsSessionActive()
    if active and not sessionWasActive
        and addon.GameMasterSettings.ShouldAutoOpenWindow(
            "compactSpellbook"
        )
    then
        addon.GameMasterCompactSpellbook.Open()
    elseif not active and sessionWasActive then
        addon.GameMasterCompactSpellbook.Hide()
    else
        addon.GameMasterCompactSpellbook.Refresh()
    end
    sessionWasActive = active
end)

addon.GameMasterSettings.RegisterListener(function()
    addon.GameMasterCompactSpellbook.Refresh()
end)

addon.GameMasterLayout.RegisterListener(function(moduleID)
    if moduleID ~= nil or not window then
        return
    end
    window.appliedCollapsed = nil
    restoreLayout()
    addon.GameMasterCompactSpellbook.Refresh()
end)
