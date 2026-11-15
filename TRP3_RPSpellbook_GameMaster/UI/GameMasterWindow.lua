local _, addon = ...
addon = addon.Shared or addon

addon.GameMasterWindow = {}

local MODULE_ID = "gameMaster"
local window
function addon.GameMasterWindow.GetTutorialContext() return window end
local collapsedHeight = 40
local minHeight = 260
local minWidth = 230
local expandedHeight = 390
local expandedWidth = 560
local maxHeight = 1600
local maxWidth = 2000
local displayedRoundID
local modernRowHeight = 36
local minimalRowHeight = 28
local buffRowHeight = 14
local actionLabels = {
    prepare = "GAMEMASTER_ACTION_PREPARE",
    cast = "GAMEMASTER_ACTION_CAST",
    channel = "GAMEMASTER_ACTION_CHANNEL",
}

local function setSpellIcon(icon, spell, visible)
    if type(addon.UIFactory.SetSpellIcon) == "function" then
        return addon.UIFactory.SetSpellIcon(
            icon, spell, addon.Constants.DEFAULT_BOOK_ICON, visible
        )
    end
    return addon.UIFactory.SetIconTexture(
        icon, spell and spell.icon, addon.Constants.DEFAULT_BOOK_ICON
    )
end

local function clearSpellIconFrame(icon)
    if type(addon.UIFactory.ClearSpellIconEffectFrame) == "function" then
        addon.UIFactory.ClearSpellIconEffectFrame(icon)
    end
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function getTextWidth(fontString)
    if not fontString then
        return 0
    end
    local measure = type(fontString.GetUnboundedStringWidth) == "function"
        and fontString.GetUnboundedStringWidth
        or fontString.GetStringWidth
    if type(measure) ~= "function" then
        return 0
    end
    local success, width = pcall(measure, fontString)
    return success and type(width) == "number"
        and math.max(0, width)
        or 0
end

local function setEnabled(button, enabled)
    addon.GameMasterWidgets.SetEnabled(button, enabled)
end

local function getDisplayedRound(session)
    if type(session) ~= "table" then
        return nil, 0
    end
    if displayedRoundID then
        for index, round in ipairs(session.rounds) do
            if round.id == displayedRoundID then
                return round, index
            end
        end
    end
    local index = #session.rounds
    return session.rounds[index], index
end

local function getMetrics()
    return addon.GameMasterSettings.GetWindowMetrics(
        "gameMaster", window, 12
    )
end
local function applyFontSettings()
    if not window then
        return
    end
    local metrics = getMetrics()
    local size = metrics and metrics.fontSize
        or addon.GameMasterSettings.GetFontSize()
    addon.GameMasterWidgets.SetFontSize(window.title, size, 2)
    for _, label in ipairs(window.fontStrings) do
        addon.GameMasterWidgets.SetFontSize(label, size)
    end
    for _, row in ipairs(window.rows) do
        addon.GameMasterWidgets.SetFontSize(row.indexLabel, size)
        addon.GameMasterWidgets.SetFontSize(row.name, size)
        for _, button in ipairs(row.buffButtons or {}) do
            addon.GameMasterWidgets.SetFontSize(
                button.label,
                math.max(8, size - 3)
            )
        end
        addon.GameMasterWidgets.SetFontSize(
            row.version,
            math.max(8, size - 3)
        )
        addon.GameMasterWidgets.SetFontSize(row.action, size)
        addon.GameMasterWidgets.SetFontSize(row.spellName, size)
        addon.GameMasterWidgets.SetFontSize(row.target, size)
        for _, view in ipairs(row.actionList and row.actionList.views or {}) do
            addon.GameMasterWidgets.SetFontSize(view.action, size)
            addon.GameMasterWidgets.SetFontSize(view.spell.name, size)
        end
    end
end

local function getCollectionMetrics(itemCount)
    local metrics = getMetrics()
    if not window or not window.rosterScroll then
        return nil
    end
    return addon.GameMasterLayout.GetCollectionMetrics(
        "gameMaster",
        math.max(1, tonumber(window.rosterScroll:GetWidth()) or 1),
        math.max(1, tonumber(window.rosterScroll:GetHeight()) or 1),
        itemCount or window.visibleRowCount or 0,
        metrics and metrics.fontSize or addon.GameMasterSettings.GetFontSize(),
        addon.GameMasterSettings.GetStyle()
    )
end

local function getRowHeight()
    local grid = window and window.collectionMetrics
    if grid then
        return grid.rowHeight
    end
    local metrics = getMetrics()
    return metrics and metrics.rowHeight
        or (addon.GameMasterSettings.GetStyle() == "minimal"
            and minimalRowHeight or modernRowHeight)
end
local function setBackdropStyle(frame, background, border)
    if not frame
        or type(frame.SetBackdropColor) ~= "function"
        or type(frame.SetBackdropBorderColor) ~= "function"
    then
        return
    end
    frame:SetBackdropColor(
        background[1],
        background[2],
        background[3],
        background[4]
    )
    frame:SetBackdropBorderColor(
        border[1],
        border[2],
        border[3],
        border[4]
    )
end

local function applyStyle()
    if not window then
        return
    end
    local styleName = addon.GameMasterSettings.GetStyle()
    local style = addon.Theme.GetGameMasterStyle(styleName)
    local showBorder = addon.GameMasterSettings
        .ShouldShowWindowBorder("gameMaster")
    local emptyBorder = { 0, 0, 0, 0 }
    setBackdropStyle(
        window,
        style.frameBackground,
        showBorder and style.frameBorder or emptyBorder
    )
    setBackdropStyle(
        window.controls,
        style.panelBackground,
        showBorder and style.panelBorder or emptyBorder
    )
    setBackdropStyle(
        window.rosterSection,
        style.panelBackground,
        showBorder and style.panelBorder or emptyBorder
    )
    for index, row in ipairs(window.rows) do
        local background = index % 2 == 0
            and style.rowBackgroundEven
            or style.rowBackgroundOdd
        local rowBorder = showBorder and style.rowBorder or emptyBorder
        setBackdropStyle(row, background, rowBorder)
        setBackdropStyle(row.spellButton, background, rowBorder)
        if row.actionList then
            addon.GameMasterActionList.ApplyStyle(
                row.actionList,
                style,
                showBorder
            )
        end
    end
    for _, button in ipairs(window.styleButtons) do
        addon.UIFactory.ApplyButtonStyle(button, styleName)
    end
    addon.UIFactory.ApplyButtonStyle(window.collapseButton, styleName)
end

local function anchorWindowTopLeft()
    local left = window:GetLeft()
    local top = window:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then
        return false
    end
    window:ClearAllPoints()
    window:SetPoint(
        "TOPLEFT",
        UIParent,
        "BOTTOMLEFT",
        left,
        top
    )
    return true
end

local function updateCollapsedState()
    local collapsed = addon.GameMasterStore.IsCollapsed()
    local module = addon.GameMasterLayout.GetModule("gameMaster")
    local layout = module and module.layout or {}
    local targetHeight = collapsed
        and collapsedHeight
        or clamp(layout.height, minHeight, maxHeight)
    local targetWidth = clamp(layout.width, minWidth, maxWidth)
    if collapsed and window.appliedCollapsed ~= true then
        window.appliedCollapsed = true
        addon.GameMasterLayout.SaveFrameLayout(
            "gameMaster",
            window,
            true
        )
    end
    if math.abs(window:GetHeight() - targetHeight) > 0.5
        or math.abs(window:GetWidth() - targetWidth) > 0.5
    then
        anchorWindowTopLeft()
        window:SetSize(targetWidth, targetHeight)
    end
    for _, region in ipairs(window.expandableRegions) do
        region:SetShown(not collapsed)
    end
    window.npcButton:SetShown(not collapsed and addon.GameMasterService.IsPrimaryGameMaster())
    window:SetResizable(not collapsed)
    window.resize:SetShown(not collapsed)
    addon.UIFactory.SetWindowMinimizeState(window.collapseButton, collapsed)
    window.title:ClearAllPoints()
    window.title:SetPoint(
        collapsed and "LEFT" or "TOPLEFT",
        window,
        collapsed and "LEFT" or "TOPLEFT",
        addon.Theme.Spacing.lg,
        collapsed and 0 or -addon.Theme.Spacing.md
    )
    window.title:SetWidth(math.max(46, targetWidth - 142))
    window.appliedCollapsed = collapsed
end

local function savePosition()
    addon.GameMasterLayout.SaveFrameLayout("gameMaster", window, false)
end

local function restorePosition()
    addon.GameMasterLayout.ApplyFrameLayout(
        "gameMaster",
        window,
        true
    )
end

local function getParticipantDisplayName(participant)
    return addon.GameMasterParticipantPresentation.FormatName(
        participant,
        addon.GameMasterSettings.GetNameMode()
    )
end

local function getCompatibilityText(participant)
    local status, version = addon.GameMasterService.GetCompatibility(
        participant.playerID
    )
    if status == "compatible" then
        return string.format("|cff62d972v%s|r", version or "?")
    end
    if status == "incompatible" then
        return string.format("|cffff7a59v%s|r", version or "?")
    end
    return "|cffaaa08e?|r"
end

local function updateSpellButton(row, submission)
    row.submission = submission
    local spell = submission and submission.spell or nil
    if not spell then
        clearSpellIconFrame(row.spellIcon)
        row.spellIcon:Hide()
        row.spellName:SetText(addon.L("GAMEMASTER_NO_ACTION"))
        row.spellButton:Disable()
        return
    end
    row.spellButton:Enable()
    row.spellIcon:Show()
    setSpellIcon(row.spellIcon, spell, true)
    row.spellName:SetText(spell.name or addon.L("UNKNOWN_ABILITY"))
end

local function getBuffRemainingText(entry, round)
    if entry.spell and entry.spell.effects and entry.spell.effects.durationRounds == 0 then
        return addon.Constants.EFFECT_DURATION_INFINITY
    end
    if entry.expiresRound and round then
        return addon.L(
            "GAMEMASTER_BUFF_REMAINING_ROUNDS",
            math.max(0, entry.expiresRound - round.number)
        )
    end
    if entry.expiresAt then
        local seconds = math.max(
            0,
            entry.expiresAt - addon.Runtime.GetTimestamp()
        )
        local formatted = type(_G.SecondsToTime) == "function"
            and _G.SecondsToTime(seconds)
            or (tostring(math.ceil(seconds)) .. "s")
        return addon.L("GAMEMASTER_BUFF_REMAINING_TIME", formatted)
    end
    return nil
end

local function getBuffInlineRemainingText(entry, round)
    if entry.spell and entry.spell.effects and entry.spell.effects.durationRounds == 0 then
        return addon.Constants.EFFECT_DURATION_INFINITY
    end
    if entry.expiresRound and round then
        local remaining = math.max(0, entry.expiresRound - round.number)
        return addon.L(
            remaining == 1
                and "GAMEMASTER_BUFF_ROUND_COMPACT"
                or "GAMEMASTER_BUFF_ROUNDS_COMPACT",
            remaining
        )
    end
    if entry.expiresAt then
        local seconds = math.max(
            0,
            entry.expiresAt - addon.Runtime.GetTimestamp()
        )
        return type(_G.SecondsToTime) == "function"
            and _G.SecondsToTime(seconds)
            or (tostring(math.ceil(seconds)) .. "s")
    end
    return nil
end

local function createRosterBuffButton(row)
    local button = CreateFrame("Button", nil, row.buffContainer)
    button:SetHeight(buffRowHeight)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(12, 12)
    button.icon:SetPoint("LEFT", button, "LEFT", 0, 0)
    button.label = addon.UIFactory.CreateLabel(
        button,
        addon.Theme.Fonts.small,
        "",
        addon.Theme.Colors.gold
    )
    button.label:SetPoint("LEFT", button.icon, "RIGHT", 3, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", 0, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetJustifyV("MIDDLE")
    button.label:SetWordWrap(false)
    button:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry or not entry.spell then
            return
        end
        addon.SpellTooltip.Show(
            self,
            entry.spell,
            false,
            "ANCHOR_RIGHT",
            { showChatHint = true }
        )
        local remaining = getBuffRemainingText(entry, self.round)
        if remaining then
            GameTooltip:AddLine(remaining, 0.62, 0.85, 0.62)
        end
        if addon.GameMasterService.HasControlRight("participants") then
            GameTooltip:AddLine(
                addon.L("GAMEMASTER_BUFF_REMOVE_HINT"),
                0.86, 0.66, 0.29
            )
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", addon.SpellTooltip.Hide)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if self.entry and addon.ChatInsert.HandleSpellClick(mouseButton, nil, self.entry.spell) then return end
        if self.entry and self.entry.spell
            and mouseButton == "RightButton"
            and row.playerKey
        then
            addon.UIFactory.ShowConfirmation(
                addon.L("GAMEMASTER_BUFF_REMOVE_TITLE"),
                addon.L(
                    "GAMEMASTER_BUFF_REMOVE_CONFIRM",
                    self.entry.spell.name or addon.L("UNKNOWN_ABILITY")
                ),
                function()
                    local removed, errorMessage =
                        addon.GameMasterService.RemoveBuff(
                            row.playerKey,
                            self.entry.sourcePlayerKey,
                            self.entry.spell.id
                        )
                    if not removed then
                        addon.Logger.Error(errorMessage)
                    end
                end
            )
        elseif self.entry and self.entry.spell then
            addon.SpellLinkWindow.OpenSpell(
                { owner = self.entry.spell.ownerKey },
                self.entry.spell
            )
        end
    end)
    row.buffButtons[#row.buffButtons + 1] = button
    return button
end

local function updateBuffButtons(row, session, round, playerKey)
    local currentRound = addon.GameMasterStore.GetCurrentRound(session)
    local entries = round == currentRound
        and addon.GameMasterEffects
        and addon.GameMasterEffects.GetActiveBuffs(
            session,
            playerKey,
            round and round.number,
            true
        )
        or {}
    while #row.buffButtons < #entries do
        createRosterBuffButton(row)
    end
    for index, button in ipairs(row.buffButtons) do
        local entry = entries[index]
        button.entry = entry
        button.round = round
        button:SetShown(entry ~= nil)
        if entry and entry.spell then
            setSpellIcon(button.icon, entry.spell, true)
            local remaining = getBuffInlineRemainingText(entry, round)
            button.label:SetText(
                (entry.spell.name or addon.L("UNKNOWN_ABILITY"))
                    .. (remaining and (" (" .. remaining .. ")") or "")
            )
            addon.UIFactory.SetFontColor(
                button.label,
                entry.spell.nameColor,
                addon.Theme.Colors.gold
            )
        else
            clearSpellIconFrame(button.icon)
            button.label:SetText("")
        end
    end
    row.buffCount = #entries
end
local function layoutRows()
    if not window then
        return
    end
    local itemCount = window.visibleRowCount or 0
    if itemCount == 0 then
        for _, row in ipairs(window.rows) do
            if row:IsShown() then
                itemCount = itemCount + 1
            end
        end
    end
    local metrics = getMetrics()
    local grid = getCollectionMetrics(itemCount)
    if not grid then
        return
    end
    window.collectionMetrics = grid
    local rowHeight = grid.rowHeight
    local rowLines = grid.rowLines
    local showProfileIcons = addon.GameMasterSettings.ShouldShowProfileIcons()
    local showMoveButtons = not addon.GameMasterStore.IsOrderLocked()
        and window.actorListState.selected ~= "enemies"
    local moveWidth = showMoveButtons and 38 or 0
    local showVersions = addon.GameMasterSettings.ShouldShowVersions()
    local versionWidth = showVersions and 31 or 0
    local lineHeight = math.max(
        18,
        math.floor((rowHeight - (rowLines == 1 and 4 or 6)) / rowLines)
    )
    local visibleRows = {}
    local rowHeights = {}
    for _, row in ipairs(window.rows) do
        if row:IsShown() then
            visibleRows[#visibleRows + 1] = row
            local count = math.max(0, tonumber(row.buffCount) or 0)
            row.buffLayoutHeight = count > 0
                and (count * buffRowHeight) + 2
                or 0
            rowHeights[#rowHeights + 1] = rowHeight
                + row.buffLayoutHeight
        end
    end
    local packed = addon.GameMasterLayout.GetVariableRowLayout(
        grid.columns,
        rowHeights,
        grid.gap
    )

    for visibleIndex, row in ipairs(visibleRows) do
            local position = packed.positions[visibleIndex]
            local column = position.column
            local buffHeight = row.buffLayoutHeight or 0
            local contentOffset = buffHeight
            row:ClearAllPoints()
            row:SetPoint(
                "TOPLEFT",
                window.rosterContent,
                "TOPLEFT",
                column * (grid.cardWidth + grid.gap),
                -position.offset
            )
            row:SetSize(grid.cardWidth, position.height)

            row.indexLabel:ClearAllPoints()
            row.activeToggle:ClearAllPoints()
            row.moveUp:ClearAllPoints()
            row.moveDown:ClearAllPoints()
            row.profileIcon:ClearAllPoints()
            row.name:ClearAllPoints()
            row.buffContainer:ClearAllPoints()
            row.version:ClearAllPoints()
            row.action:ClearAllPoints()
            row.spellButton:ClearAllPoints()
            row.targetButton:ClearAllPoints()

            row.indexLabel:SetSize(24, lineHeight)
            row.indexLabel:SetPoint(
                "TOPLEFT",
                row,
                "TOPLEFT",
                2,
                -(contentOffset + 2)
            )
            row.activeToggle:SetSize(18, 18)
            row.activeToggle:SetPoint(
                "LEFT", row.indexLabel, "RIGHT", 1, 0
            )
            row.moveUp:SetSize(18, 18)
            row.moveDown:SetSize(18, 18)
            row.moveUp:SetShown(showMoveButtons)
            row.moveDown:SetShown(showMoveButtons)
            row.moveUp:SetPoint(
                "LEFT", row.activeToggle, "RIGHT", 1, 0
            )
            row.moveDown:SetPoint("LEFT", row.moveUp, "RIGHT", 1, 0)

            local nameAnchor = showMoveButtons and row.moveDown
                or row.activeToggle
            local iconSize = math.max(
                14,
                math.min(lineHeight - 3, metrics and metrics.iconSize or 20)
            )
            if showProfileIcons then
                row.profileIcon:SetSize(iconSize, iconSize)
                row.profileIcon:SetPoint(
                    "LEFT", nameAnchor, "RIGHT", 3, 0
                )
                nameAnchor = row.profileIcon
            end
            row.name:SetHeight(lineHeight)
            row.name:SetPoint("LEFT", nameAnchor, "RIGHT", 4, 0)

            local hasBuffs = (row.buffCount or 0) > 0
            local controlWidth = 2 + 24 + 1 + 18 + moveWidth
                + (showProfileIcons and iconSize + 3 or 0) + 4
            row.buffContainer:SetShown(hasBuffs)
            row.version:SetSize(versionWidth, lineHeight)
            row.version:SetShown(showVersions)
            row.action:SetHeight(lineHeight)
            row.action:SetWordWrap(false)
            local fieldHeight = math.max(18, lineHeight - 2)
            row.spellButton:SetHeight(fieldHeight)
            row.targetButton:SetHeight(fieldHeight)
            row.spellIcon:SetSize(
                math.max(14, math.min(fieldHeight - 4, 22)),
                math.max(14, math.min(fieldHeight - 4, 22))
            )

            if rowLines == 1 then
                local fieldGaps = (3 + (showVersions and 1 or 0)) * 4
                local fieldWidth = math.max(
                    1,
                    grid.cardWidth - controlWidth - versionWidth
                        - fieldGaps - 4
                )
                local actionWidth = clamp(
                    math.floor(fieldWidth * 0.2),
                    100,
                    165
                )
                local spellWidth = clamp(
                    math.floor(fieldWidth * 0.25),
                    90,
                    230
                )
                local targetWidth = clamp(
                    math.floor(fieldWidth * 0.2),
                    55,
                    200
                )
                local nameWidth = fieldWidth - actionWidth
                    - spellWidth - targetWidth
                if nameWidth < 48 then
                    local missing = 48 - nameWidth
                    local reduction = math.min(
                        missing,
                        math.max(0, targetWidth - 40)
                    )
                    targetWidth = targetWidth - reduction
                    missing = missing - reduction
                    reduction = math.min(
                        missing,
                        math.max(0, spellWidth - 80)
                    )
                    spellWidth = spellWidth - reduction
                    missing = missing - reduction
                    actionWidth = actionWidth - math.min(
                        missing,
                        math.max(0, actionWidth - 90)
                    )
                    nameWidth = fieldWidth - actionWidth
                        - spellWidth - targetWidth
                end
                row.name:SetWidth(nameWidth)
                local metadataEnd = row.name
                if showVersions then
                    row.version:SetPoint(
                        "LEFT", metadataEnd, "RIGHT", 4, 0
                    )
                    metadataEnd = row.version
                end
                row.action:SetWidth(actionWidth)
                row.action:SetPoint(
                    "LEFT", metadataEnd, "RIGHT", 4, 0
                )
                row.spellButton:SetWidth(spellWidth)
                row.spellButton:SetPoint(
                    "LEFT", row.action, "RIGHT", 4, 0
                )
                row.targetButton:SetWidth(targetWidth)
                row.targetButton:SetPoint(
                    "LEFT", row.spellButton, "RIGHT", 4, 0
                )
            elseif rowLines == 2 then
                if showVersions then
                    row.version:SetPoint(
                        "TOPRIGHT",
                        row,
                        "TOPRIGHT",
                        -4,
                        -(contentOffset + 2)
                    )
                    row.name:SetPoint(
                        "RIGHT", row.version, "LEFT", -4, 0
                    )
                else
                    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                end

                local actionWidth = clamp(
                    math.floor(grid.cardWidth * 0.27),
                    100,
                    135
                )
                local spellWidth = clamp(
                    math.floor(grid.cardWidth * 0.32),
                    100,
                    180
                )
                row.action:SetWidth(actionWidth)
                row.action:SetPoint(
                    "TOPLEFT",
                    row,
                    "TOPLEFT",
                    4,
                    -(contentOffset + lineHeight + 3)
                )
                row.spellButton:SetWidth(spellWidth)
                row.spellButton:SetPoint(
                    "LEFT", row.action, "RIGHT", 4, 0
                )
                row.targetButton:SetWidth(math.max(
                    40,
                    grid.cardWidth - actionWidth - spellWidth - 20
                ))
                row.targetButton:SetPoint(
                    "LEFT", row.spellButton, "RIGHT", 4, 0
                )
            else
                if showVersions then
                    row.version:SetPoint(
                        "TOPRIGHT",
                        row,
                        "TOPRIGHT",
                        -4,
                        -(contentOffset + 2)
                    )
                    row.name:SetPoint(
                        "RIGHT", row.version, "LEFT", -4, 0
                    )
                else
                    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                end

                local actionWidth = clamp(
                    math.floor(grid.cardWidth * 0.4),
                    100,
                    130
                )
                row.action:SetWidth(actionWidth)
                row.action:SetPoint(
                    "TOPLEFT",
                    row,
                    "TOPLEFT",
                    4,
                    -(contentOffset + lineHeight + 3)
                )
                row.spellButton:SetPoint(
                    "LEFT", row.action, "RIGHT", 4, 0
                )
                row.spellButton:SetWidth(math.max(
                    50,
                    grid.cardWidth - actionWidth - 16
                ))
                row.targetButton:SetWidth(math.max(
                    40,
                    grid.cardWidth - 8
                ))
                row.targetButton:SetPoint(
                    "TOPLEFT",
                    row,
                    "TOPLEFT",
                    4,
                    -(contentOffset + (lineHeight * 2) + 4)
                )
            end

            if hasBuffs then
                row.buffContainer:SetHeight(buffHeight)
                row.buffContainer:SetWidth(math.max(
                    80,
                    grid.cardWidth - controlWidth - 4
                ))
                row.buffContainer:SetPoint(
                    "BOTTOMLEFT", row.name, "TOPLEFT", 0, 0
                )
                for buffIndex, button in ipairs(row.buffButtons) do
                    button:ClearAllPoints()
                    button:SetSize(
                        row.buffContainer:GetWidth(),
                        buffRowHeight
                    )
                    button:SetPoint(
                        "TOPLEFT",
                        row.buffContainer,
                        "TOPLEFT",
                        0,
                        -((buffIndex - 1) * buffRowHeight)
                    )
                    button:SetShown(button.entry ~= nil)
                    addon.GameMasterWidgets.SetFontSize(
                        button.label,
                        math.max(8, grid.fontSize - 3)
                    )
                end
            else
                for _, button in ipairs(row.buffButtons) do
                    button:Hide()
                end
            end

            addon.GameMasterWidgets.SetFontSize(
                row.indexLabel, grid.fontSize
            )
            addon.GameMasterWidgets.SetFontSize(row.name, grid.fontSize)
            addon.GameMasterWidgets.SetFontSize(
                row.version,
                math.max(8, grid.fontSize - 3)
            )
            addon.GameMasterWidgets.SetFontSize(row.action, grid.fontSize)
            addon.GameMasterWidgets.SetFontSize(
                row.spellName, grid.fontSize
            )
            addon.GameMasterWidgets.SetFontSize(row.target, grid.fontSize)
    end

    window.rosterContent:SetHeight(math.max(
        1,
        window.rosterScroll:GetHeight(),
        packed.contentHeight
    ))
    window.rosterContent:SetWidth(math.max(1, window.rosterScroll:GetWidth()))
    window.rosterScroll:UpdateScrollChildRect()
end

local function layoutAdaptiveRows()
    if not window then
        return
    end
    local metrics = getMetrics()
    local fontSize = metrics and metrics.fontSize
        or addon.GameMasterSettings.GetFontSize()
    local showProfileIcons = addon.GameMasterSettings.ShouldShowProfileIcons()
    local showMoveButtons = not addon.GameMasterStore.IsOrderLocked()
        and window.actorListState.selected ~= "enemies"
    local showVersions = addon.GameMasterSettings.ShouldShowVersions()
    local visibleRows = {}
    local participants = {}
    local actionLists = {}

    for _, row in ipairs(window.rows) do
        if row:IsShown() then
            visibleRows[#visibleRows + 1] = row
            actionLists[#actionLists + 1] = row.actionList
            local buffCount = math.max(0, tonumber(row.buffCount) or 0)
            participants[#participants + 1] = {
                buffHeight = buffCount > 0
                    and (buffCount * buffRowHeight) + 2
                    or 0,
                hasProfileIcon = showProfileIcons
                    and row.profileIcon:IsShown(),
                nameWidth = addon.GameMasterWidgets.MeasureTextWidth(
                    row.name,
                    row.name:GetText(),
                    fontSize
                ),
            }
        end
    end

    local planColumns = addon.GameMasterActionList.CreateColumnPlanner(actionLists, fontSize)
    local windowPlan = addon.GameMasterLayout.PlanGameMasterWindow({
        buttonHeight = addon.Theme.Sizes.buttonHeight,
        fontSize = fontSize,
        height = math.max(1, window:GetHeight() - window.actorTabs:GetHeight()),
        iconSize = metrics and metrics.iconSize or 20,
        measureAction = function(index, width, size)
            return addon.GameMasterActionList.Measure(
                visibleRows[index].actionList,
                width,
                size,
                planColumns(width)
            )
        end,
        participants = participants,
        showMoveButtons = showMoveButtons,
        showVersions = showVersions,
        styleName = addon.GameMasterSettings.GetStyle(),
        padding = metrics and metrics.padding or 6,
        width = window:GetWidth(),
    })
    local grid = windowPlan.participants
    window.chromeLayout = windowPlan.chrome
    window.collectionMetrics = grid
    window.participantLayout = grid
    for visibleIndex, row in ipairs(visibleRows) do
        local position = grid.positions[visibleIndex]
        local plan = grid.plans[visibleIndex]
        local column = position.column
        row:ClearAllPoints()
        row:SetPoint(
            "TOPLEFT",
            window.rosterContent,
            "TOPLEFT",
            column * (grid.cardWidth + grid.gap),
            -position.offset
        )
        row:SetSize(grid.cardWidth, position.height)

        row.indexLabel:ClearAllPoints()
        row.activeToggle:ClearAllPoints()
        row.moveUp:ClearAllPoints()
        row.moveDown:ClearAllPoints()
        row.profileIcon:ClearAllPoints()
        row.name:ClearAllPoints()
        row.version:ClearAllPoints()
        row.buffContainer:ClearAllPoints()
        row.actionList:ClearAllPoints()

        local headerTop = plan.buffHeight + 3
        row.indexLabel:SetSize(plan.indexWidth, plan.headerHeight)
        row.indexLabel:SetPoint(
            "TOPLEFT", row, "TOPLEFT", 2, -headerTop
        )
        row.activeToggle:SetSize(18, 18)
        row.activeToggle:SetPoint("LEFT", row.indexLabel, "RIGHT", 1, 0)
        row.moveUp:SetSize(18, 18)
        row.moveDown:SetSize(18, 18)
        row.moveUp:SetShown(showMoveButtons and not row.npcActor)
        row.moveDown:SetShown(showMoveButtons and not row.npcActor)
        row.moveUp:SetPoint("LEFT", row.activeToggle, "RIGHT", 1, 0)
        row.moveDown:SetPoint("LEFT", row.moveUp, "RIGHT", 1, 0)

        local nameAnchor = showMoveButtons and row.moveDown or row.activeToggle
        if plan.profileIcon then
            row.profileIcon:SetSize(plan.iconSize, plan.iconSize)
            row.profileIcon:SetPoint("LEFT", nameAnchor, "RIGHT", 3, 0)
            nameAnchor = row.profileIcon
        end
        row.name:SetHeight(plan.headerHeight)
        row.name:SetPoint(
            "TOPLEFT",
            row,
            "TOPLEFT",
            plan.controlWidth,
            -headerTop
        )
        local versionWidth = showVersions and 31 or 0
        row.name:SetWidth(math.max(
            20,
            plan.identityWidth - plan.controlWidth - versionWidth
                - (showVersions and 6 or 3)
        ))
        if showVersions then
            row.version:SetSize(31, plan.headerHeight)
            row.version:SetPoint(
                "TOPLEFT",
                row,
                "TOPLEFT",
                plan.identityWidth - 34,
                -headerTop
            )
        end

        if plan.buffHeight > 0 then
            row.buffContainer:SetPoint(
                "TOPLEFT", row, "TOPLEFT", plan.controlWidth, -2
            )
            row.buffContainer:SetSize(
                math.max(
                    20,
                    plan.identityWidth - plan.controlWidth - 3
                ),
                plan.buffHeight
            )
            for buffIndex, button in ipairs(row.buffButtons) do
                button:ClearAllPoints()
                button:SetSize(row.buffContainer:GetWidth(), buffRowHeight)
                button:SetPoint(
                    "TOPLEFT",
                    row.buffContainer,
                    "TOPLEFT",
                    0,
                    -((buffIndex - 1) * buffRowHeight)
                )
                button:SetShown(button.entry ~= nil)
                addon.GameMasterWidgets.SetFontSize(
                    button.label,
                    math.max(8, fontSize - 3)
                )
            end
        end

        row.actionList:SetPoint(
            "TOPLEFT",
            row,
            "TOPLEFT",
            plan.actionLeft,
            -plan.actionTop
        )
        addon.GameMasterActionList.Layout(
            row.actionList,
            plan.actionWidth,
            fontSize,
            planColumns(plan.actionWidth)
        )
        addon.GameMasterWidgets.SetFontSize(row.indexLabel, fontSize)
        addon.GameMasterWidgets.SetFontSize(row.name, fontSize)
        addon.GameMasterWidgets.SetFontSize(
            row.version,
            math.max(8, fontSize - 3)
        )
    end

    window.rosterContent:SetHeight(math.max(
        1,
        grid.viewportHeight,
        grid.contentHeight
    ))
    window.rosterContent:SetWidth(grid.viewportWidth)
    window.rosterScroll:UpdateScrollChildRect()
    addon.GameMasterWidgets.ClampScroll(window.rosterScroll, grid.contentHeight)
end

local function setControlButtonWidth(button, width)
    width = math.max(44, math.floor(tonumber(width) or 44))
    button:SetWidth(width)
    if type(button.SetClipsChildren) == "function" then
        button:SetClipsChildren(true)
    end
    local label = type(button.GetFontString) == "function"
        and button:GetFontString()
        or nil
    if label then
        label:SetWidth(math.max(20, width - 10))
        label:SetWordWrap(false)
    end
end

local function layoutChrome()
    if not window then
        return
    end
    local metrics = getMetrics()
    local padding = clamp(
        metrics and metrics.padding or addon.Theme.Spacing.lg,
        6,
        10
    )
    local width = math.max(1, window:GetWidth() or expandedWidth)
    local height = math.max(1, window:GetHeight() or expandedHeight)
    local buttonHeight = addon.Theme.Sizes.buttonHeight or 22
    local chrome = addon.GameMasterLayout.GetGameMasterChromeLayout(
        width,
        height,
        padding,
        buttonHeight,
        metrics and metrics.fontSize
    )
    local compact = chrome.compact
    window.chromeLayout = chrome
    window.previousRound:ClearAllPoints()
    window.previousRound:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", padding, padding)
    window.npcButton:ClearAllPoints()
    window.npcButton:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -padding, padding)
    window.historyLabel:SetWordWrap(false)
    window.historyLabel:SetWidth(math.max(20, math.min(getTextWidth(window.historyLabel),
        width - padding * 2 - 68 - addon.Theme.Spacing.sm * 2
            - (window.npcButton:IsShown() and 50 or 0))))
    window.title:SetWidth(math.max(46, width - 142))

    window.sessionName:ClearAllPoints()
    window.roundLabel:ClearAllPoints()
    window.sessionButton:ClearAllPoints()
    window.assistantsButton:ClearAllPoints()
    window.controls:ClearAllPoints()
    window.startRound:ClearAllPoints()
    window.lockRound:ClearAllPoints()
    window.orderLock:ClearAllPoints()
    window.stopButton:ClearAllPoints()
    window.sessionButton:SetHeight(buttonHeight)
    window.assistantsButton:SetHeight(buttonHeight)
    window.startRound:SetHeight(buttonHeight)
    window.lockRound:SetHeight(buttonHeight)
    window.orderLock:SetHeight(buttonHeight)
    window.stopButton:SetHeight(buttonHeight)
    window.sessionName:SetJustifyH("LEFT")
    window.sessionName:SetHeight(chrome.metadataLineHeight)
    window.roundLabel:SetHeight(chrome.metadataLineHeight)
    window.roundLabel:SetWidth(chrome.metadataWidth)
    window.roundLabel:SetWordWrap(false)
    if compact then
        window.sessionName:SetPoint(
            "TOPLEFT", window, "TOPLEFT", padding, -chrome.metadataTop
        )
        window.sessionName:SetWidth(math.max(60, width - (padding * 2)))
        window.roundLabel:SetPoint(
            "TOPLEFT", window, "TOPLEFT", padding,
            -chrome.metadataTop - chrome.metadataLineHeight
        )

        local available = math.max(1, width - (padding * 2))
        local secondaryGap = 4
        local assistantsWidth = math.min(105, math.floor(
            (available - secondaryGap) * 0.56
        ))
        local sessionWidth = math.min(
            88,
            available - secondaryGap - assistantsWidth
        )
        local secondaryWidth = assistantsWidth + secondaryGap + sessionWidth
        local secondaryX = math.max(0, math.floor(
            (available - secondaryWidth) / 2
        ))
        setControlButtonWidth(window.assistantsButton, assistantsWidth)
        setControlButtonWidth(window.sessionButton, sessionWidth)
        window.assistantsButton:SetPoint(
            "TOPLEFT", window, "TOPLEFT", padding + secondaryX, -chrome.secondaryTop
        )
        window.sessionButton:SetPoint(
            "LEFT", window.assistantsButton, "RIGHT", 4, 0
        )
    else
        window.sessionName:SetPoint(
            "TOPLEFT", window, "TOPLEFT", padding, -chrome.metadataTop
        )
        window.sessionName:SetWidth(chrome.metadataWidth)
        window.roundLabel:SetPoint(
            "TOPLEFT", window, "TOPLEFT", padding,
            -chrome.metadataTop - chrome.metadataLineHeight
        )
        setControlButtonWidth(window.sessionButton, 88)
        setControlButtonWidth(window.assistantsButton, 105)
        window.sessionButton:SetPoint(
            "TOPRIGHT", window, "TOPRIGHT", -padding, -chrome.secondaryTop
        )
        window.assistantsButton:SetPoint(
            "RIGHT", window.sessionButton, "LEFT", -addon.Theme.Spacing.sm, 0
        )
    end

    window.controls:ClearAllPoints()
    window.controls:SetPoint(
        "TOPLEFT", window, "TOPLEFT", padding, -chrome.controlsTop
    )
    window.controls:SetPoint(
        "TOPRIGHT", window, "TOPRIGHT", -padding, -chrome.controlsTop
    )
    window.controls:SetHeight(chrome.controlsHeight)
    local buttons = {
        window.startRound,
        window.lockRound,
        window.orderLock,
        window.stopButton,
    }
    for index, button in ipairs(buttons) do
        local plan = chrome.controlButtons[index]
        button:ClearAllPoints()
        button:SetHeight(buttonHeight)
        setControlButtonWidth(button, plan.width)
        button:SetPoint(
            "TOPLEFT",
            window.controls,
            "TOPLEFT",
            plan.x,
            -plan.y
        )
    end

    window.rosterSection:ClearAllPoints()
    window.rosterSection:SetPoint(
        "TOPLEFT",
        window.controls,
        "BOTTOMLEFT",
        0,
        -addon.Theme.Spacing.xs
    )
    window.rosterSection:SetPoint(
        "BOTTOMRIGHT",
        window,
        "BOTTOMRIGHT",
        -padding,
        chrome.contentBottom - 4
    )
    window.actorTabs:ClearAllPoints()
    window.actorTabs:SetPoint("TOPLEFT", window.rosterSection, "TOPLEFT", 4, -4)
    window.actorTabs:Layout(math.max(1, width - padding * 2 - 8))
    window.rosterScroll:SetPoint("TOPLEFT", window.rosterSection, "TOPLEFT",
        addon.Theme.Spacing.xs, -addon.Theme.Spacing.xs - window.actorTabs:GetHeight())
end

local function requestResponsiveLayout()
    if not window or window.layoutPending then
        return
    end
    window.layoutPending = true
    C_Timer.After(0, function()
        local activeWindow = window
        if not activeWindow then
            return
        end
        if activeWindow:IsShown()
            and not addon.GameMasterStore.IsCollapsed()
        then
            applyFontSettings()
            layoutChrome()
            layoutAdaptiveRows()
        end
        activeWindow.layoutPending = false
    end)
end

local function refreshRows(session, round, canChangeParticipants, canReorder)
    local orderLocked = addon.GameMasterStore.IsOrderLocked()
    local showProfileIcons =
        addon.GameMasterSettings.ShouldShowProfileIcons()
    local useProfileColors =
        addon.GameMasterSettings.ShouldUseProfileColors()
    local showVersions = addon.GameMasterSettings.ShouldShowVersions()
    local entries = {}
    for orderIndex, playerKey in ipairs(session and session.participantOrder or {}) do
        local participant = session.participants[playerKey]
        if participant and not (session.gmParticipates == false and playerKey == session.ownerKey) then
            entries[#entries + 1] = { id = playerKey, participant = participant,
            kind = "player", orderIndex = orderIndex } end
    end
    for index, entry in ipairs(entries) do
        entry.canMoveUp, entry.canMoveDown = index > 1, index < #entries
    end
    local primary = addon.GameMasterService.IsPrimaryGameMaster()
    local npcEntries = addon.GameMasterNPCDialog
        and addon.GameMasterNPCDialog.GetRosterEntries(session, round, primary) or {}
    for _, entry in ipairs(npcEntries) do
        local actor = entry.actor
        entry.participant = { playerID = actor.id, playerKey = actor.id, rpName = actor.name,
            gameName = actor.name, profileIcon = actor.icon, profileColor = actor.nameColor, online = true }
        entry.kind = "npc"
        entry.side = actor.side
        entry.ownerPlayerKey = actor.ownerPlayerKey or session.ownerKey
        entries[#entries + 1] = entry
    end
    local context = { sessionID = session and session.id, roundID = round and round.id,
        phase = round and round.phase }
    local selected, changed = addon.GameMasterSharedActions.ResolveActorList(window.actorListState, context)
    local counts
    entries, counts = addon.GameMasterSharedActions.FilterActorList(entries, selected)
    window.actorTabs:Update(selected, counts)
    if changed then window.rosterScroll:SetVerticalScroll(0) end
    for index, row in ipairs(window.rows) do
        local entry = entries[index]
        local playerKey = entry and entry.id
        local participant = entry and entry.participant
        if row.npcActor and (not entry or not entry.actor or row.npcActor.id ~= entry.actor.id) then
            addon.GameMasterNPCTooltip.Hide(row.nameButton)
        end
        row.npcActor = entry and entry.actor
        row.sessionID = session and session.id
        if participant then
            local enemyPhase = round and round.phase == "enemies"
            local narrator = playerKey == session.ownerKey
                and session.gmParticipates == false
            local submission = round
                and round.submissions[playerKey]
                or nil
            if narrator then submission = nil end
            if row.npcActor then submission = entry.submission end
            row.playerKey = playerKey
            row.indexLabel:SetText(index)
            local turn = {
                online = participant.online ~= false,
                active = row.npcActor and entry.active or not row.npcActor
                    and not narrator and addon.GameMasterStore.IsParticipantTurnActive(session, round, playerKey),
                completed = row.npcActor and entry.completed or not row.npcActor
                    and addon.GameMasterStore.IsTurnCompleted(round, playerKey),
            }
            row.turnStatus = turn
            local indicator = round and not narrator
                and addon.GameMasterSharedActions.GetTurnStatusIcon(turn, 14) or ""
            row.name:SetText(indicator .. (narrator
                and addon.GameMasterStore.GetEncounterOptions(session).narratorName
                or getParticipantDisplayName(participant)))
            row.version:SetText(getCompatibilityText(participant))
            row.version:SetShown(showVersions and not row.npcActor)
            addon.UIFactory.SetFontColor(
                row.name,
                not narrator and useProfileColors and participant.profileColor or nil,
                participant.online
                    and addon.Theme.Colors.text
                    or addon.Theme.Colors.textMuted
            )
            local hasProfileIcon = not narrator and showProfileIcons
                and ((type(participant.profileIcon) == "string" and participant.profileIcon ~= "")
                    or type(participant.profileIcon) == "number"
                    or (row.npcActor and tonumber(row.npcActor.templateID) ~= nil))
            row.profileIcon:SetShown(hasProfileIcon)
            if hasProfileIcon then
                addon.UIFactory.SetIconTexture(
                    row.profileIcon,
                    participant.profileIcon,
                    addon.Constants.DEFAULT_BOOK_ICON
                )
            end
            addon.UIFactory.SetNPCPortrait(row, row.profileIcon,
                hasProfileIcon and row.npcActor and row.npcActor.templateID or nil,
                participant.profileIcon)
            updateBuffButtons(row, session, round, playerKey)
            local active = not enemyPhase and not narrator
                and addon.GameMasterStore.IsParticipantActive(round, playerKey)
            if row.npcActor then active = entry.active end
            row.activeToggle:SetChecked(row.npcActor and row.npcActor.released or (not row.npcActor and active))
            setEnabled(row.activeToggle, row.npcActor and primary
                and round == addon.GameMasterService.GetActiveRound()
                or (not row.npcActor and not narrator and canChangeParticipants and not enemyPhase))
            row:SetAlpha(active and (participant.online and 1 or 0.65) or 0.32)
            row.submission = submission
            addon.GameMasterActionList.SetSubmission(
                row.actionList,
                submission
            )
            setEnabled(row.moveUp,
                not row.npcActor and canReorder and not orderLocked and entry.canMoveUp)
            setEnabled(
                row.moveDown,
                not row.npcActor and canReorder and not orderLocked
                    and entry.canMoveDown
            )
            row:Show()
        else
            row:SetAlpha(1)
            row.playerKey = nil
            row.submission = nil
            row.targetOverview = nil
            addon.GameMasterActionList.SetSubmission(row.actionList, nil)
            row:Hide()
        end
    end
    window.visibleRowCount = #entries
    window.empty:SetText(addon.L(selected == "enemies"
        and "GAMEMASTER_ENCOUNTER_ENEMIES_EMPTY" or "GAMEMASTER_ENCOUNTER_PLAYERS_EMPTY"))
    window.empty:SetShown(#entries == 0)
end

local function refresh()
    if not window then
        return
    end
    local session = addon.GameMasterService.GetActiveSession()
    if not session or not addon.GameMasterService.IsActiveGameMaster() then
        window:Hide()
        return
    end

    local primary = addon.GameMasterService.IsPrimaryGameMaster()
    local testMode = addon.GameMasterService.IsTestMode()
    local canControlRounds =
        addon.GameMasterService.HasControlRight("rounds")
    local canManageParticipants =
        addon.GameMasterService.HasControlRight("participants")
    local round, roundIndex = getDisplayedRound(session)
    local activeRound = addon.GameMasterService.GetActiveRound()
    addon.GameMasterEffects.Prune(
        session,
        activeRound and activeRound.number,
        addon.Runtime.GetTimestamp()
    )
    window.sessionName:SetText(string.format(
        "%s - %s",
        session.name,
        addon.L(testMode and "GAMEMASTER_TEST_ROLE"
            or (primary and "GAMEMASTER_PRIMARY_ROLE"
                or "GAMEMASTER_ASSISTANT_ROLE"))
    ))
    window.roundLabel:SetText(
        round
        and addon.L(
            round.status == "open"
                and "GAMEMASTER_ROUND_OPEN"
                or "GAMEMASTER_ROUND_CLOSED",
            round.number
        )
        or addon.L("GAMEMASTER_NO_ROUND")
    )
    if round and session.enemyPhases then
        window.roundLabel:SetText(window.roundLabel:GetText() .. " | " .. addon.L(
            round.phase == "enemies" and "GAMEMASTER_PHASE_ENEMIES" or "GAMEMASTER_PHASE_PLAYERS"))
    end
    window.historyLabel:SetText(addon.L(
        "GAMEMASTER_HISTORY_POSITION",
        roundIndex,
        #session.rounds
    ))
    window.startRound:SetText(addon.GameMasterService.GetNextPhaseLabel())
    window.lockRound:SetText(
        activeRound and activeRound.status == "locked"
            and addon.L("GAMEMASTER_UNLOCK_ACTIONS")
            or addon.L("GAMEMASTER_LOCK_ACTIONS")
    )
    setEnabled(window.startRound, canControlRounds)
    setEnabled(window.lockRound, canControlRounds and activeRound ~= nil)
    setEnabled(window.previousRound, roundIndex > 1)
    setEnabled(window.nextRound, roundIndex > 0 and roundIndex < #session.rounds)
    window.orderLock:SetText(
        addon.GameMasterStore.IsOrderLocked()
        and addon.L("GAMEMASTER_UNLOCK_ORDER")
        or addon.L("GAMEMASTER_LOCK_ORDER")
    )
    refreshRows(
        session,
        round,
        canManageParticipants
            and round ~= nil
            and round == activeRound,
        canManageParticipants and (activeRound == nil or round == activeRound)
    )
    window.visibilityButton:SetVisibilityMode(
        addon.GameMasterService.GetVisibility()
    )
    window:SetAlpha(addon.GameMasterSettings.GetOpacity())
    local canChangeVisibility =
        addon.GameMasterService.HasControlRight("visibility")
    if canChangeVisibility then
        window.visibilityButton:Enable()
    else
        window.visibilityButton:Disable()
    end
    window.visibilityButton:SetAlpha(canChangeVisibility and 1 or 0.35)
    setEnabled(window.orderLock, canManageParticipants)
    window.assistantsButton:SetShown(primary)
    window.sessionButton:SetShown(primary and not testMode)
    window.stopButton:SetShown(primary)
    applyStyle()
    applyFontSettings()
    updateCollapsedState()
    layoutChrome()
    layoutAdaptiveRows()
end

local function changeDisplayedRound(direction)
    local session = addon.GameMasterService.GetActiveSession()
    if not session then
        return
    end
    local _, index = getDisplayedRound(session)
    local target = math.max(1, math.min(#session.rounds, index + direction))
    displayedRoundID = session.rounds[target] and session.rounds[target].id or nil
    refresh()
end

local function createSpellButton(parent)
    local theme = addon.Theme
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(26)
    if type(button.SetClipsChildren) == "function" then
        button:SetClipsChildren(true)
    end
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button:SetBackdropColor(0.08, 0.06, 0.04, 0.6)
    button:SetBackdropBorderColor(
        theme.Colors.border[1],
        theme.Colors.border[2],
        theme.Colors.border[3],
        theme.Colors.border[4]
    )
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", button, "LEFT", 2, 0)
    local name = addon.UIFactory.CreateLabel(
        button,
        theme.Fonts.small,
        "",
        theme.Colors.text
    )
    name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    name:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    name:SetJustifyH("LEFT")
    name:SetJustifyV("MIDDLE")
    name:SetWordWrap(false)
    button.icon = icon
    button.name = name
    return button
end

local function createWindow()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("GAMEMASTER_WINDOW_TITLE"),
        expandedWidth,
        expandedHeight
    )
    addon.UIFactory.ConfigureInformationWindow(frame)
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    else
        frame:SetMinResize(minWidth, minHeight)
        frame:SetMaxResize(maxWidth, maxHeight)
    end
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    local collapseButton = addon.UIFactory.CreateWindowMinimizeButton(frame, function()
        addon.GameMasterStore.SetCollapsed(
            not addon.GameMasterStore.IsCollapsed()
        )
        updateCollapsedState()
    end)
    local settingsButton = addon.UIFactory.CreateTextureButton(
        frame,
        "Interface\\Buttons\\UI-OptionsButton",
        22
    )
    settingsButton:SetPoint(
        "RIGHT", collapseButton, "LEFT", -theme.Spacing.xs, 0
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
        function(self)
            local changed, result =
                addon.GameMasterService.CycleVisibility()
            if changed
                and addon.Constants.GAMEMASTER_VISIBILITY_MODES[result] then
                self:SetVisibilityMode(result)
            elseif result then
                addon.Logger.Error(result)
            end
        end
    )
    visibilityButton:SetPoint(
        "RIGHT", settingsButton, "LEFT", -theme.Spacing.xs, 0
    )
    frame.title:SetWidth(200)
    frame.title:SetWordWrap(false)
    local sessionName = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.header,
        "",
        theme.Colors.gold
    )
    sessionName:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -43)
    sessionName:SetWidth(290)
    sessionName:SetWordWrap(false)

    local roundLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        "",
        theme.Colors.text
    )
    roundLabel:SetPoint("TOPLEFT", sessionName, "BOTTOMLEFT", 0, -theme.Spacing.tiny)

    local sessionButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("GAMEMASTER_SESSIONS"),
        80
    )
    sessionButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.lg, -45)
    sessionButton:SetScript("OnClick", function()
        addon.GameMasterSessionDialog.Open()
    end)
    local assistantsButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("GAMEMASTER_ASSISTANTS_BUTTON"),
        105
    )
    assistantsButton:SetPoint(
        "RIGHT", sessionButton, "LEFT", -theme.Spacing.sm, 0
    )
    assistantsButton:SetScript("OnClick", function()
        addon.GameMasterAssistantsDialog.Open()
    end)

    local controls = addon.GameMasterWidgets.CreateSection(frame)
    controls:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -82)
    controls:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.lg, -82)
    controls:SetHeight(34)

    local startRound = addon.UIFactory.CreateButton(
        controls,
        addon.L("GAMEMASTER_START_ROUND"),
        104
    )
    startRound:SetPoint("LEFT", controls, "LEFT", theme.Spacing.sm, 0)
    startRound:SetScript("OnClick", function()
        local started, errorMessage = addon.GameMasterService.AdvancePhase()
        if not started then
            addon.Logger.Error(errorMessage)
            return
        end
        local round = addon.GameMasterService.GetActiveRound()
        displayedRoundID = round and round.id or nil
        refresh()
    end)

    local lockRound = addon.UIFactory.CreateButton(
        controls,
        addon.L("GAMEMASTER_LOCK_ACTIONS"),
        106
    )
    lockRound:SetPoint("LEFT", startRound, "RIGHT", theme.Spacing.sm, 0)
    lockRound:SetScript("OnClick", function()
        local activeRound = addon.GameMasterService.GetActiveRound()
        local changed, errorMessage
        if activeRound and activeRound.status == "locked" then
            changed, errorMessage = addon.GameMasterService.UnlockRound()
        else
            changed, errorMessage = addon.GameMasterService.LockRound()
        end
        if not changed then
            addon.Logger.Error(errorMessage)
        end
        local round = addon.GameMasterService.GetActiveRound()
        displayedRoundID = round and round.id or displayedRoundID
        refresh()
    end)

    local orderLock = addon.UIFactory.CreateButton(
        controls,
        addon.L("GAMEMASTER_UNLOCK_ORDER"),
        154
    )
    orderLock:SetPoint("LEFT", lockRound, "RIGHT", theme.Spacing.sm, 0)
    orderLock:SetScript("OnClick", function()
        addon.GameMasterService.SetOrderLocked(
            not addon.GameMasterStore.IsOrderLocked()
        )
        refresh()
    end)

    local stopButton = addon.UIFactory.CreateButton(
        controls,
        addon.L("GAMEMASTER_STOP"),
        68
    )
    stopButton:SetPoint("RIGHT", controls, "RIGHT", -theme.Spacing.sm, 0)
    stopButton:SetScript("OnClick", function()
        addon.UIFactory.ShowConfirmation(
            addon.L("GAMEMASTER_STOP"),
            addon.L("GAMEMASTER_STOP_CONFIRM"),
            function()
                addon.GameMasterService.Stop()
            end
        )
    end)

    local rosterSection = addon.GameMasterWidgets.CreateSection(frame)
    rosterSection:SetPoint("TOPLEFT", controls, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    rosterSection:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, 52)
    frame.actorListState = {}
    local actorTabs = addon.GameMasterSharedActions.CreateActorTabs(rosterSection, function(selected)
        frame.actorListState.selected = selected
        if frame.rosterScroll then frame.rosterScroll:SetVerticalScroll(0) end
        refresh()
    end)

    local rosterScroll = addon.GameMasterWidgets.CreateScrollViewport(rosterSection)
    rosterScroll:SetPoint("TOPLEFT", rosterSection, "TOPLEFT", theme.Spacing.xs, -theme.Spacing.xs)
    rosterScroll:SetPoint("BOTTOMRIGHT", rosterSection, "BOTTOMRIGHT", -theme.Spacing.xs, theme.Spacing.xs)
    local rosterContent = CreateFrame("Frame", nil, rosterScroll)
    rosterContent:SetPoint("TOPLEFT", rosterScroll, "TOPLEFT", 0, 0)
    rosterContent:SetSize(1, 1)
    rosterScroll:SetScrollChild(rosterContent)
    local empty = addon.UIFactory.CreateLabel(rosterScroll, theme.Fonts.small, "", theme.Colors.textMuted)
    empty:SetPoint("TOPLEFT", rosterScroll, "TOPLEFT", 6, -6)
    empty:SetPoint("RIGHT", rosterScroll, "RIGHT", -6, 0)
    empty:SetWordWrap(true)

    local rows = {}
    for index = 1, addon.Constants.GAMEMASTER_MAX_VISIBLE_ACTORS or 60 do
        local row = addon.GameMasterWidgets.CreateSection(
            rosterContent,
            index % 2 == 0 and theme.Colors.archiveRow or theme.Colors.dark
        )
        if type(row.SetClipsChildren) == "function" then
            row:SetClipsChildren(true)
        end
        row:SetPoint("TOPLEFT", rosterContent, "TOPLEFT", 0, -((index - 1) * modernRowHeight))
        row:SetHeight(modernRowHeight - 2)

        local activeToggle = addon.UIFactory.CreateButton(row, "", 20)
        function activeToggle:SetChecked(active)
            self.active = active == true
            self:SetText(self.active and "X" or "+")
        end
        function activeToggle:GetChecked()
            return self.active == true
        end
        activeToggle:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(addon.L(row.npcActor
                and (self:GetChecked() and "GAMEMASTER_NPC_HIDE" or "GAMEMASTER_NPC_RELEASE")
                or (self:GetChecked()
                    and "GAMEMASTER_PARTICIPANT_EXCLUDE"
                    or "GAMEMASTER_PARTICIPANT_INCLUDE")
            ))
            GameTooltip:Show()
        end)
        activeToggle:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        local indexLabel = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.body,
            "",
            theme.Colors.textMuted
        )
        indexLabel:SetJustifyH("CENTER")
        indexLabel:SetWordWrap(false)
        local moveUp = addon.UIFactory.CreateButton(row, "^", 20)
        local moveDown = addon.UIFactory.CreateButton(row, "v", 20)
        local profileIcon = row:CreateTexture(nil, "ARTWORK")
        profileIcon:SetSize(20, 20)
        local name = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.small,
            "",
            theme.Colors.text
        )
        name:SetJustifyH("LEFT")
        name:SetJustifyV("MIDDLE")
        name:SetWordWrap(false)
        local nameButton = CreateFrame("Button", nil, row)
        nameButton:SetAllPoints(name)
        nameButton:SetScript("OnEnter", function(self)
            if row.npcActor then addon.GameMasterNPCTooltip.Show(self, row.npcActor)
            elseif row.turnStatus then
                local _, text = addon.GameMasterSharedActions.GetTurnStatus(row.turnStatus)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(text)
                GameTooltip:Show()
            end
        end)
        nameButton:SetScript("OnLeave", function(self)
            addon.GameMasterNPCTooltip.Hide(self)
            GameTooltip:Hide()
        end)
        nameButton:SetScript("OnClick", function()
            if row.npcActor then addon.GameMasterNPCDialog.Open(row.sessionID, row.npcActor.id) end
        end)
        row.nameButton = nameButton
        row:HookScript("OnHide", function()
            if addon.GameMasterNPCTooltip then addon.GameMasterNPCTooltip.Hide(nameButton) end
        end)
        local buffContainer = CreateFrame("Frame", nil, row)
        local buffButtons = {}
        local version = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.small,
            "",
            theme.Colors.textMuted
        )
        version:SetJustifyH("LEFT")
        version:SetJustifyV("MIDDLE")
        version:SetWordWrap(false)
        local action = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.small,
            "",
            theme.Colors.text
        )
        action:SetJustifyH("LEFT")
        action:SetJustifyV("MIDDLE")
        action:SetWordWrap(false)
        local spellButton = createSpellButton(row)
        local targetButton = CreateFrame("Button", nil, row)
        local target = addon.UIFactory.CreateLabel(
            targetButton,
            theme.Fonts.small,
            "",
            theme.Colors.textMuted
        )
        target:SetPoint("LEFT", targetButton, "LEFT", 0, 0)
        target:SetPoint("RIGHT", targetButton, "RIGHT", 0, 0)
        target:SetJustifyH("LEFT")
        target:SetJustifyV("MIDDLE")
        target:SetWordWrap(false)
        targetButton:SetScript("OnEnter", function(self)
            local overview = row.targetOverview
            if type(overview) ~= "table" or #overview == 0 then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(
                addon.L("GAMEMASTER_TARGET_OVERVIEW"),
                1, 0.82, 0
            )
            GameTooltip:AddLine(
                addon.L("GAMEMASTER_TARGET_OVERVIEW_COUNT", #overview),
                0.76, 0.69, 0.56
            )
            GameTooltip:AddLine(" ")
            for targetIndex, entry in ipairs(overview) do
                local red, green, blue = 1, 1, 1
                if entry.color then
                    red, green, blue =
                        addon.UIFactory.GetColorRGB(entry.color)
                end
                GameTooltip:AddDoubleLine(
                    tostring(targetIndex) .. ".",
                    entry.label,
                    0.62, 0.56, 0.46,
                    red, green, blue
                )
            end
            GameTooltip:Show()
        end)
        targetButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        activeToggle:SetScript("OnClick", function(self)
            if row.npcActor then
                addon.GameMasterService.SetNPCReleased(row.npcActor.id, not row.npcActor.released, row.sessionID)
                refresh()
                return
            end
            if row.playerKey then
                local active = not self:GetChecked()
                self:SetChecked(active)
                addon.GameMasterService.SetParticipantActive(
                    row.playerKey,
                    active
                )
                refresh()
            end
        end)
        moveUp:SetScript("OnClick", function()
            if row.playerKey and not row.npcActor then
                addon.GameMasterService.MoveParticipant(row.playerKey, -1)
            end
        end)
        moveDown:SetScript("OnClick", function()
            if row.playerKey and not row.npcActor then
                addon.GameMasterService.MoveParticipant(row.playerKey, 1)
            end
        end)
        spellButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        spellButton:SetScript("OnEnter", function(self)
            if row.submission and row.submission.spell then
                addon.SpellTooltip.Show(
                    self,
                    row.submission.spell,
                    false,
                    "ANCHOR_RIGHT",
                    { showChatHint = true }
                )
                if row.submission.preparation
                    and addon.GameMasterService.HasControlRight("participants")
                then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(
                        addon.L("GAMEMASTER_INTERRUPT_PREPARATION_HINT"),
                        0.95, 0.72, 0.25, true
                    )
                end
                if row.submission.emote and row.submission.emote.text then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(addon.L("GAMEMASTER_LINKED_EMOTE"), 0.65, 0.72, 0.82)
                    GameTooltip:AddLine(row.submission.emote.text, 1, 1, 1, true)
                end
                GameTooltip:Show()
            end
        end)
        spellButton:SetScript("OnLeave", function()
            addon.SpellTooltip.Hide()
        end)
        spellButton:SetScript("OnClick", function(_, mouseButton)
            if row.submission and row.submission.spell then
                if addon.ChatInsert.HandleSpellClick(mouseButton,
                    row.submission.playerID, row.submission.spell) then return end
                if mouseButton == "RightButton"
                    and row.submission.preparation
                    and row.playerKey
                    and addon.GameMasterService.HasControlRight("participants")
                then
                    addon.GameMasterService.InterruptPreparation(row.playerKey)
                    return
                end
                addon.SpellLinkWindow.OpenSpell(
                    { owner = row.submission.playerID },
                    row.submission.spell
                )
            end
        end)
        row.buffButtons = buffButtons
        row.buffContainer = buffContainer

        row.activeToggle = activeToggle
        row.action = action
        row.indexLabel = indexLabel
        row.moveDown = moveDown
        row.moveUp = moveUp
        row.name = name
        row.profileIcon = profileIcon
        row.spellButton = spellButton
        row.spellIcon = spellButton.icon
        row.spellName = spellButton.name
        row.target = target
        row.targetButton = targetButton
        row.version = version
        row.actionList = addon.GameMasterActionList.Create(row)
        row.actionList.onActionClick = function(actionData, mouseButton)
            if mouseButton == "RightButton"
                and not row.npcActor
                and actionData
                and actionData.preparation
                and row.playerKey
                and addon.GameMasterService.HasControlRight("participants")
            then
                addon.GameMasterService.InterruptPreparation(row.playerKey)
                return true
            end
            return false
        end
        action:Hide()
        spellButton:Hide()
        targetButton:Hide()
        rows[index] = row
    end

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
            or addon.GameMasterStore.IsCollapsed()
        then
            return
        end
        anchorWindowTopLeft()
        frame.isUserResizing = true
        frame:StartSizing("BOTTOMRIGHT", true)
    end)
    resize:SetScript("OnMouseUp", function()
        if not frame.isUserResizing then
            return
        end
        frame:StopMovingOrSizing()
        frame.isUserResizing = false
        addon.GameMasterLayout.SaveFrameLayout(
            "gameMaster", frame, true
        )
        applyFontSettings()
        layoutChrome()
        layoutAdaptiveRows()
    end)

    local previousRound = addon.UIFactory.CreateButton(frame, "<", 34)
    previousRound:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", theme.Spacing.lg, theme.Spacing.lg)
    previousRound:SetScript("OnClick", function()
        changeDisplayedRound(-1)
    end)
    local historyLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        "",
        theme.Colors.text
    )
    historyLabel:SetPoint("LEFT", previousRound, "RIGHT", theme.Spacing.sm, 0)
    local nextRound = addon.UIFactory.CreateButton(frame, ">", 34)
    nextRound:SetPoint("LEFT", historyLabel, "RIGHT", theme.Spacing.sm, 0)
    nextRound:SetScript("OnClick", function()
        changeDisplayedRound(1)
    end)

    local npcButton = addon.UIFactory.CreateButton(frame, addon.L("GAMEMASTER_NPC_SHORT"), 42)
    npcButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)
    npcButton:SetScript("OnClick", function() addon.GameMasterNPCDialog.Open() end)

    local styleButtons = {
        actorTabs.buttons.players,
        actorTabs.buttons.enemies,
        npcButton,
        collapseButton,
        sessionButton,
        assistantsButton,
        startRound,
        lockRound,
        orderLock,
        stopButton,
        previousRound,
        nextRound,
    }
    for _, row in ipairs(rows) do
        styleButtons[#styleButtons + 1] = row.moveUp
        styleButtons[#styleButtons + 1] = row.moveDown
    end

    frame.collapseButton = collapseButton
    frame.expandableRegions = {
        npcButton,
        sessionName,
        roundLabel,
        sessionButton,
        assistantsButton,
        controls,
        rosterSection,
        previousRound,
        historyLabel,
        nextRound,
        resize,
    }
    frame.fontStrings = {
        sessionName,
        roundLabel,
        historyLabel,
    }
    frame.controls = controls
    frame.actorTabs = actorTabs
    frame.empty = empty
    frame.npcButton = npcButton
    frame.assistantsButton = assistantsButton
    frame.sessionButton = sessionButton
    frame.startRound = startRound
    frame.stopButton = stopButton
    frame.historyLabel = historyLabel
    frame.lockRound = lockRound
    frame.nextRound = nextRound
    frame.orderLock = orderLock
    frame.previousRound = previousRound
    frame.resize = resize
    frame.rosterContent = rosterContent
    frame.rosterSection = rosterSection
    frame.rosterScroll = rosterScroll
    frame.roundLabel = roundLabel
    frame.rows = rows
    frame.sessionName = sessionName
    frame.visibilityButton = visibilityButton
    frame.styleButtons = styleButtons
    rosterScroll:SetScript("OnSizeChanged", requestResponsiveLayout)
    frame:SetScript("OnSizeChanged", requestResponsiveLayout)
    frame:HookScript("OnHide", function(self)
        if self.isUserResizing then
            self:StopMovingOrSizing()
            self.isUserResizing = false
        end
        addon.GameMasterEffects.SetCountdownVisible(MODULE_ID, false)
    end)
    frame:HookScript("OnShow", function()
        addon.GameMasterEffects.SetCountdownVisible(MODULE_ID, true)
    end)
    return frame
end

function addon.GameMasterWindow.Open(restoreWindow)
    if not addon.GameMasterService.IsActiveGameMaster() then
        return false
    end
    if restoreWindow == true then
        addon.GameMasterStore.SetCollapsed(false)
    end
    window = window or createWindow()
    displayedRoundID = addon.GameMasterService.GetActiveRound()
        and addon.GameMasterService.GetActiveRound().id
        or nil
    restorePosition()
    refresh()
    window:Show()
    addon.UIFactory.BringToFront(window)
    return true
end

function addon.GameMasterWindow.Hide()
    if window then
        window:Hide()
    end
end

function addon.GameMasterWindow.IsShown()
    return window ~= nil and window:IsShown() or false
end

function addon.GameMasterWindow.Refresh()
    if window and window:IsShown() then
        refresh()
    end
end

local function refreshBuffCountdowns()
    if not window then
        return
    end
    for _, row in ipairs(window.rows or {}) do
        if row:IsShown() then
            for _, button in ipairs(row.buffButtons or {}) do
                local entry = button.entry
                if button:IsShown() and entry and entry.spell then
                    local remaining = getBuffInlineRemainingText(
                        entry,
                        button.round
                    )
                    button.label:SetText(
                        (entry.spell.name or addon.L("UNKNOWN_ABILITY"))
                            .. (remaining and (" (" .. remaining .. ")") or "")
                    )
                end
            end
        end
    end
end

addon.GameMasterService.RegisterListener(function(reason)
    if reason == "round" then
        local round = addon.GameMasterService.GetActiveRound()
        displayedRoundID = round and round.id or displayedRoundID
    end
    addon.GameMasterWindow.Refresh()
end)

addon.GameMasterEffects.RegisterListener(function(reason)
    if window and window:IsShown() then
        if reason == "countdown" then
            refreshBuffCountdowns()
        else
            addon.GameMasterWindow.Refresh()
        end
    end
end)

addon.GameMasterSettings.RegisterListener(function()
    addon.GameMasterWindow.Refresh()
end)

addon.GameMasterLayout.RegisterListener(function(moduleID)
    if moduleID ~= nil or not window then
        return
    end
    restorePosition()
    addon.GameMasterWindow.Refresh()
end)
