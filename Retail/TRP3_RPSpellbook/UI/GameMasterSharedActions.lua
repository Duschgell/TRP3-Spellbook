local _, addon = ...

addon.GameMasterSharedActions = {}

local MODULE_ID = "roundOverview"
local MAX_ROW_BUFFS = 3
local MINIMIZED_HEIGHT = 38
local window
function addon.GameMasterSharedActions.GetTutorialContext() return window end
local manuallyHidden = false
local restoredForGameMaster = false
local previousMode = "hidden"
local wasGameMaster = false

local ACTOR_TABS_HEIGHT = 24

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

function addon.GameMasterSharedActions.IsNPCEntry(entry)
    return type(entry) == "table" and (entry.kind == "npc" or entry.actorKind == "npc")
end

function addon.GameMasterSharedActions.FilterActorList(entries, selected)
    local result, counts = {}, { players = 0, enemies = 0 }
    local allies = {}
    for _, entry in ipairs(entries or {}) do
        local group = addon.GameMasterSharedActions.IsNPCEntry(entry)
            and entry.side ~= "players" and "enemies" or "players"
        counts[group] = counts[group] + 1
        if group == selected then
            result[#result + 1] = entry
            if group == "players" and addon.GameMasterSharedActions.IsNPCEntry(entry)
                and entry.ownerPlayerKey then
                local owned = allies[entry.ownerPlayerKey] or {}
                allies[entry.ownerPlayerKey] = owned
                owned[#owned + 1] = entry
            end
        end
    end
    if selected == "players" and next(allies) then
        local ordered, placed = {}, {}
        for _, entry in ipairs(result) do
            if not addon.GameMasterSharedActions.IsNPCEntry(entry) then
                ordered[#ordered + 1] = entry
                local key = entry.playerKey or entry.id
                    or (addon.Runtime.NormalizePlayerID and addon.Runtime.NormalizePlayerID(entry.playerID))
                    or entry.playerID
                for _, actor in ipairs(allies[key] or {}) do
                    if not placed[actor] then
                        ordered[#ordered + 1], placed[actor] = actor, true
                    end
                end
            end
        end
         
        for _, entry in ipairs(result) do
            if addon.GameMasterSharedActions.IsNPCEntry(entry) and not placed[entry] then
                ordered[#ordered + 1] = entry
            end
        end
        result = ordered
    end
    return result, counts
end

function addon.GameMasterSharedActions.ResolveActorList(state, context)
    context = context or {}
    local phase = context.phase == "enemies" and "enemies" or "players"
    local previous = state.selected
    if state.phase ~= phase or state.sessionID ~= context.sessionID
        or state.activationID ~= context.activationID or state.roundID ~= context.roundID then
        state.selected = phase
    end
    state.phase, state.sessionID = phase, context.sessionID
    state.activationID, state.roundID = context.activationID, context.roundID
    state.selected = state.selected == "enemies" and "enemies" or "players"
    return state.selected, previous ~= state.selected
end

 
function addon.GameMasterSharedActions.CreateActorTabs(parent, onSelected)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(ACTOR_TABS_HEIGHT)
    bar.buttons = {}
    for _, group in ipairs({ "players", "enemies" }) do
        local value = group
        local button = addon.UIFactory.CreateButton(bar, "", 96)
        button:SetHeight(22)
        button:SetScript("OnClick", function() onSelected(value) end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(addon.L("GAMEMASTER_ENCOUNTER_LIST_HINT"))
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.buttons[value] = button
    end
    function bar:Update(selected, counts)
        for group, button in pairs(self.buttons) do
            button:SetText(addon.L(group == "enemies"
                and "GAMEMASTER_ENCOUNTER_ENEMIES" or "GAMEMASTER_ENCOUNTER_PLAYERS", counts[group] or 0))
            button:SetEnabled(group ~= selected)
        end
    end
    function bar:Layout(width)
        width = math.max(1, tonumber(width) or 1)
        self:SetWidth(width)
        local gap = math.min(4, width / 3)
        local buttonWidth = math.min(104, math.max(1, (width - gap) / 2))
        for index, group in ipairs({ "players", "enemies" }) do
            local button = self.buttons[group]
            button:ClearAllPoints()
            button:SetSize(buttonWidth, 22)
            button:SetPoint("TOPLEFT", self, "TOPLEFT", (index - 1) * (buttonWidth + gap), 0)
            local label = type(button.GetFontString) == "function" and button:GetFontString()
            if label then
                label:SetWidth(math.max(1, buttonWidth - 10))
                label:SetWordWrap(false)
            end
        end
    end
    return bar
end

local actionLabels = {
    prepare = "GAMEMASTER_ACTION_PREPARE",
    cast = "GAMEMASTER_ACTION_CAST",
    channel = "GAMEMASTER_ACTION_CHANNEL",
}

local turnStatusTextures = {
    completed = "Interface\\RaidFrame\\ReadyCheck-Ready",
    inactive = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

local function getTurnStatus(entry)
    if entry.online == false then
        return "inactive", addon.L("GAMEMASTER_PARTICIPANT_OFFLINE")
    end
    if entry.active == false then
        return "inactive", addon.L("GAMEMASTER_PARTICIPANT_PAUSE")
    end
    if entry.completed == true then
        return "completed", addon.L("GAMEMASTER_TURN_COMPLETED")
    end
    return "waiting", addon.L("GAMEMASTER_TURN_WAITING")
end

local function getTurnStatusIcon(entry, size)
    local status = getTurnStatus(entry)
    return string.format(
        "|T%s:%d:%d|t ",
        turnStatusTextures[status],
        size,
        size
    )
end

addon.GameMasterSharedActions.GetTurnStatus = getTurnStatus
addon.GameMasterSharedActions.GetTurnStatusIcon = getTurnStatusIcon

local function getParticipantDisplayName(participant)
    if participant.kind == "npc" or participant.actorKind == "npc" then
        local profile = participant.npcProfile
        return profile and profile.name or participant.rpName or participant.playerID or ""
    end
    return addon.GameMasterParticipantPresentation.FormatName(
        participant,
        addon.GameMasterSettings.GetWindowOption(
            MODULE_ID,
            "nameMode",
            "trp_full"
        )
    )
end

local function setBackdrop(frame, background, border)
    if not frame or type(frame.SetBackdropColor) ~= "function" then
        return
    end
    frame:SetBackdropColor(
        background[1], background[2], background[3], background[4]
    )
    frame:SetBackdropBorderColor(
        border[1], border[2], border[3], border[4]
    )
end

local function anchorTopLeft(frame)
    local left = frame:GetLeft()
    local top = frame:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return true
end

local function saveLayout(saveSize)
    if window then
        addon.GameMasterLayout.SaveFrameLayout(
            MODULE_ID,
            window,
            saveSize
        )
    end
end

local function restoreLayout()
    if window then
        addon.GameMasterLayout.ApplyFrameLayout(MODULE_ID, window, true)
    end
end

local function createSpellButton(parent)
    local theme = addon.Theme
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(28)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button:SetBackdropColor(0.08, 0.06, 0.04, 0.62)
    button:SetBackdropBorderColor(
        theme.Colors.border[1],
        theme.Colors.border[2],
        theme.Colors.border[3],
        theme.Colors.border[4]
    )
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", button, "LEFT", 2, 0)
    local name = addon.UIFactory.CreateLabel(
        button, theme.Fonts.small, "", theme.Colors.text
    )
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    button.icon = icon
    button.name = name
    return button
end

local function getBuffRemaining(entry)
    local context = addon.GameMasterService.GetSubmissionContext()
    if entry.spell and entry.spell.effects and entry.spell.effects.durationRounds == 0 then
        return addon.Constants.EFFECT_DURATION_INFINITY
    end
    if entry.expiresRound then
        return addon.L(
            "GAMEMASTER_BUFF_REMAINING_ROUNDS",
            math.max(0, entry.expiresRound - (context and context.roundNumber or 0))
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
    return ""
end

local function showBuffTooltip(owner, entry)
    if not entry or not entry.spell then return end
    addon.SpellTooltip.Show(
        owner,
        entry.spell,
        false,
        "ANCHOR_RIGHT",
        { showChatHint = true }
    )
    local remaining = getBuffRemaining(entry)
    if remaining ~= "" then
        GameTooltip:AddLine(remaining, 0.62, 0.85, 0.62)
        GameTooltip:Show()
    end
end

local function showBuffOverview(owner, entries)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(addon.L("GAMEMASTER_TOOLTIP_BUFFS"))
    for _, entry in ipairs(entries or {}) do
        local spell = entry.spell or {}
        local red, green, blue = addon.UIFactory.GetColorRGB(spell.nameColor)
        GameTooltip:AddDoubleLine(
            spell.name or addon.L("UNKNOWN_ABILITY"),
            getBuffRemaining(entry),
            red, green, blue,
            0.62, 0.85, 0.62
        )
    end
    GameTooltip:Show()
end

local function updateRowBuffs(row, playerID)
    local entries = playerID
        and addon.GameMasterService.GetActiveBuffsForPlayer(playerID)
        or {}
    row.buffEntries = entries
    local overflow = #entries > MAX_ROW_BUFFS
    local visibleCount = overflow and (MAX_ROW_BUFFS - 1)
        or math.min(#entries, MAX_ROW_BUFFS)
    for index, button in ipairs(row.buffButtons) do
        local entry = index <= visibleCount and entries[index] or nil
        button.entry = entry
        button:SetShown(entry ~= nil)
        if entry and entry.spell then
            setSpellIcon(button.icon, entry.spell, true)
        else
            clearSpellIconFrame(button.icon)
        end
    end
    row.buffOverflow:SetShown(overflow)
    if overflow then
        row.buffOverflow.text:SetText("+" .. tostring(#entries - visibleCount))
    end
    row.buffVisibleCount = visibleCount
    row.buffOffset = (visibleCount * 18) + (overflow and 28 or 0)
end

local function showTargetOverview(owner, entry)
    local overview = addon.GameMasterActionPresentation
        .GetTargetOverview(entry)
    if #overview == 0 then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(
        addon.L("GAMEMASTER_TARGET_OVERVIEW"),
        1, 0.82, 0
    )
    GameTooltip:AddLine(
        addon.L("GAMEMASTER_TARGET_OVERVIEW_COUNT", #overview),
        0.76, 0.69, 0.56
    )
    GameTooltip:AddLine(" ")
    for index, target in ipairs(overview) do
        local red, green, blue = 1, 1, 1
        if target.color then
            red, green, blue = addon.UIFactory.GetColorRGB(target.color)
        end
        GameTooltip:AddDoubleLine(
            tostring(index) .. ".",
            target.label,
            0.62, 0.56, 0.46,
            red, green, blue
        )
    end
    GameTooltip:Show()
end

local function getMetrics()
    return addon.GameMasterWidgets.GetContentMetrics(
        MODULE_ID, window
    )
end

local function getCollectionMetrics(itemCount, mode, measure)
    local metrics = getMetrics()
    if not window or not window.scroll then
        return nil
    end
    local scale = (metrics and metrics.fontSize or 12) / 12
    return addon.GameMasterWidgets.GetMeasuredGrid(
        window.scroll:GetWidth(), window.scroll:GetHeight(), itemCount,
        metrics.fontSize, (mode == "full" and 350 or 220) * scale,
        mode == "full" and 3 or 4, measure
    )
end

local function layoutRowBuffIcons(row, fontSize)
    local size = math.max(14, fontSize + 1)
    for index, button in ipairs(row.buffButtons) do
        button:ClearAllPoints()
        button:SetSize(size, size)
        button:SetPoint("TOPLEFT", row, "TOPLEFT", 6 + (index - 1) * (size + 2), -3)
    end
    row.buffOverflow:ClearAllPoints()
    row.buffOverflow:SetPoint("TOPLEFT", row, "TOPLEFT",
        6 + (row.buffVisibleCount or 0) * (size + 2), -3)
    row.buffOverflow:SetHeight(size)
    addon.GameMasterWidgets.SetFontSize(row.buffOverflow.text, fontSize, -2)
end

local function getRowBuffHeight(row, fontSize)
    return (row.buffVisibleCount or 0) > 0 and math.max(14, fontSize + 1) + 3 or 0
end

local function layoutRows(mode)
    local visibleRows = {}
    for _, row in ipairs(window.rows) do
        if row:IsShown() then visibleRows[#visibleRows + 1] = row end
    end
    local fontSize = getMetrics().fontSize
    local function measureCard(row, width)
        local available = math.max(1, width - 12)
        local nameWidth = addon.GameMasterWidgets.MeasureTextWidth(row.name, row.name:GetText(), fontSize) + 2
        local detailWidth = addon.GameMasterWidgets.MeasureTextWidth(row.target, row.target:GetText(), fontSize - 1) + 2
        local inline = nameWidth + detailWidth + 10 <= available
        nameWidth = inline and nameWidth or available
        detailWidth = inline and available - nameWidth - 10 or available
        local nameHeight = addon.GameMasterWidgets.MeasureText(
            row.name, row.name:GetText(), nameWidth, fontSize, true
        )
        local detailHeight = addon.GameMasterWidgets.MeasureText(
            row.target, row.target:GetText(), detailWidth, fontSize - 1, true
        )
        local buffHeight = getRowBuffHeight(row, fontSize)
        return {
            nameWidth = nameWidth,
            nameHeight = nameHeight,
            detailWidth = detailWidth,
            detailHeight = detailHeight,
            detailLeft = inline and nameWidth + 16 or 6,
            detailTop = 3 + buffHeight + (inline and 0 or nameHeight + 2),
            buffHeight = buffHeight,
            height = buffHeight + 6 + (inline and math.max(nameHeight, detailHeight)
                or nameHeight + detailHeight + 2),
        }
    end
    local grid = getCollectionMetrics(#visibleRows, mode, function(index, width)
        return measureCard(visibleRows[index], width).height
    end)
    if not grid then return end
    window.collectionMetrics = grid
    for index, row in ipairs(visibleRows) do
        local position = grid.positions[index]
        local plan = measureCard(row, grid.cardWidth)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window.content, "TOPLEFT",
            position.column * (grid.cardWidth + grid.gap), -position.offset)
        row:SetSize(grid.cardWidth, position.height)
        row.action:Hide()
        row.spellButton:Hide()
        row.actionList:Hide()
        row.targetButton:Show()
        row.targetButton:EnableMouse(mode ~= "hidden")
        layoutRowBuffIcons(row, fontSize)
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3 - plan.buffHeight)
        row.name:SetSize(plan.nameWidth, plan.nameHeight)
        row.name:SetJustifyV("TOP")
        row.targetButton:ClearAllPoints()
        row.targetButton:SetPoint("TOPLEFT", row, "TOPLEFT", plan.detailLeft, -plan.detailTop)
        row.targetButton:SetSize(plan.detailWidth, plan.detailHeight)
        row.target:SetPoint("TOPLEFT", row.targetButton, "TOPLEFT", 0, 0)
        row.target:SetSize(plan.detailWidth, plan.detailHeight)
        row.target:SetJustifyV("TOP")
    end
    window.content:SetHeight(math.max(window.scroll:GetHeight(), grid.contentHeight))
    window.content:SetWidth(math.max(1, window.scroll:GetWidth()))
    window.scroll:UpdateScrollChildRect()
    addon.GameMasterWidgets.ClampScroll(window.scroll, grid.contentHeight)
end
local function layoutAdaptiveRows(mode)
    if not window then return end
    if mode ~= "full" then
        layoutRows(mode)
        return
    end
    local visibleRows = {}
    for _, row in ipairs(window.rows) do
        if row:IsShown() then
            row.actionList.showIcons = addon.GameMasterSettings.GetWindowOption(MODULE_ID, "showIcons", true)
            visibleRows[#visibleRows + 1] = row
        end
    end
    local fontSize = getMetrics().fontSize
    local sharedIdentityWidth = 0
    local actionLists = {}
    for _, row in ipairs(visibleRows) do
        actionLists[#actionLists + 1] = row.actionList
        sharedIdentityWidth = math.max(sharedIdentityWidth,
            addon.GameMasterWidgets.MeasureTextWidth(row.name, row.name:GetText(), fontSize) + 2)
    end
    sharedIdentityWidth = math.max(80, math.min(250 * fontSize / 12, sharedIdentityWidth))
    local planColumns = addon.GameMasterActionList.CreateColumnPlanner(actionLists, fontSize)
    local function measureCard(row, cardWidth)
        local scale = fontSize / 12
        local columns = addon.GameMasterLayout.GetParticipantCardColumns(cardWidth, {
            gap = 6, identityRatio = 0.2, inset = 6,
            maxIdentityWidth = sharedIdentityWidth,
            minDetailWidth = 260 * scale,
            minIdentityWidth = math.min(135 * scale, sharedIdentityWidth),
        })
        local identityWidth = columns.inline and columns.identityWidth or cardWidth - 12
        local headerHeight = addon.GameMasterWidgets.MeasureText(
            row.name, row.name:GetText(), identityWidth, fontSize, true
        )
        local buffHeight = getRowBuffHeight(row, fontSize)
        local identityHeight = headerHeight + buffHeight
        local actionLeft = columns.inline and columns.detailLeft or 14
        local actionWidth = columns.inline and columns.detailWidth
            or math.max(1, cardWidth - actionLeft - 6)
        local actionHeight = addon.GameMasterActionList.Measure(
            row.actionList, actionWidth, fontSize, planColumns(actionWidth))
        return {
            actionLeft = actionLeft, actionWidth = actionWidth,
            actionTop = columns.inline and 3 or identityHeight + 4,
            identityWidth = identityWidth, headerHeight = headerHeight,
            nameTop = 3 + buffHeight, inline = columns.inline,
            height = columns.inline and math.max(identityHeight, actionHeight) + 6
                or identityHeight + actionHeight + 8,
        }
    end
    local grid = getCollectionMetrics(#visibleRows, mode, function(index, cardWidth)
        return measureCard(visibleRows[index], cardWidth).height
    end)
    if not grid then return end
    window.collectionMetrics = grid
    local rowHeights = {}
    local plans = {}
    for index, row in ipairs(visibleRows) do
        plans[index] = measureCard(row, grid.cardWidth)
        rowHeights[index] = plans[index].height
    end
    local packed = addon.GameMasterLayout.GetVariableRowLayout(
        grid.columns,
        rowHeights,
        grid.gap
    )
    for index, row in ipairs(visibleRows) do
        local position = packed.positions[index]
        local plan = plans[index]
        row:ClearAllPoints()
        row:SetPoint(
            "TOPLEFT",
            window.content,
            "TOPLEFT",
            position.column * (grid.cardWidth + grid.gap),
            -position.offset
        )
        row:SetSize(grid.cardWidth, position.height)
        row.action:Hide()
        row.spellButton:Hide()
        row.targetButton:Hide()
        row.actionList:Show()
        row.name:ClearAllPoints()
        row.name:SetPoint(
            "TOPLEFT",
            row,
            "TOPLEFT",
            6,
            -plan.nameTop
        )
        row.name:SetWidth(math.max(
            40,
            plan.identityWidth
        ))
        row.name:SetHeight(plan.headerHeight)
        row.name:SetJustifyV("TOP")
        layoutRowBuffIcons(row, fontSize)
        row.actionList:ClearAllPoints()
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
            grid.fontSize,
            planColumns(plan.actionWidth)
        )
        addon.GameMasterWidgets.SetFontSize(row.name, grid.fontSize)
    end
    window.content:SetHeight(math.max(
        1,
        window.scroll:GetHeight(),
        packed.contentHeight
    ))
    window.content:SetWidth(math.max(1, window.scroll:GetWidth()))
    window.scroll:UpdateScrollChildRect()
    addon.GameMasterWidgets.ClampScroll(window.scroll, packed.contentHeight)
end
local function layoutChrome()
    if not window then
        return
    end
    local metrics = getMetrics()
    local padding = metrics and metrics.padding or addon.Theme.Spacing.lg
    local width = math.max(1, window:GetWidth() or 1)
    local size = metrics.fontSize
    local fullTitle = string.format("%s - %s", window.baseTitle,
        window.roundText or addon.L("GAMEMASTER_NO_ACTIVE_ROUND"))
    local available = math.max(1, width - padding - 64)
    window.title:ClearAllPoints()
    window.title:SetWidth(0)
    window.title:SetText(fullTitle)
    window.title:SetWordWrap(false)
    local compactHeader = window.title:GetStringWidth() <= available
    window.round:ClearAllPoints()
    window.section:ClearAllPoints()
    window.title:SetPoint("TOPLEFT", window, "TOPLEFT", padding, -6)
    window.title:SetWidth(available)
    window.title:SetJustifyH("LEFT")
    if compactHeader then
        window.title:SetText(fullTitle)
        window.round:Hide()
    else
        window.title:SetText(window.baseTitle)
        window.round:SetPoint("TOPLEFT", window, "TOPLEFT", padding, -(size + 14))
        window.round:SetPoint("RIGHT", window, "RIGHT", -padding, 0)
        window.round:SetHeight(size + 4)
        window.round:SetWordWrap(false)
        window.round:SetJustifyH("LEFT")
        window.round:Show()
    end
    local contentTop = compactHeader and math.max(28, size + 20) or size * 2 + 23
    window.actorTabs:ClearAllPoints()
    window.actorTabs:SetPoint("TOPLEFT", window, "TOPLEFT", padding, -contentTop)
    window.actorTabs:Layout(width - padding * 2)
    window.section:SetPoint(
        "TOPLEFT", window, "TOPLEFT", padding,
        -(contentTop + window.actorTabs:GetHeight())
    )
    window.section:SetPoint(
        "BOTTOMRIGHT", window, "BOTTOMRIGHT", -padding, padding
    )
end
local function applyFonts()
    if not window then
        return
    end
    local metrics = getMetrics()
    local size = metrics and metrics.fontSize
        or addon.GameMasterSettings.GetWindowFontSize(MODULE_ID, 12)
    addon.GameMasterWidgets.SetFontSize(window.title, size, 2)
    addon.GameMasterWidgets.SetFontSize(window.round, size)
    addon.GameMasterWidgets.SetFontSize(window.empty, size)
    for _, row in ipairs(window.rows) do
        addon.GameMasterWidgets.SetFontSize(row.name, size)
        addon.GameMasterWidgets.SetFontSize(row.action, size, -1)
        addon.GameMasterWidgets.SetFontSize(row.spellButton.name, size, -1)
        addon.GameMasterWidgets.SetFontSize(row.target, size, -1)
        addon.GameMasterWidgets.SetFontSize(row.buffOverflow.text, size, -2)
        for _, view in ipairs(row.actionList and row.actionList.views or {}) do
            addon.GameMasterWidgets.SetFontSize(view.action, size, -1)
            addon.GameMasterWidgets.SetFontSize(view.spell.name, size, -1)
        end
    end
end

local function applyStyle()
    if not window then
        return
    end
    local styleName = addon.GameMasterSettings.GetWindowStyle(
        MODULE_ID,
        "modern"
    )
    local style = addon.Theme.GetGameMasterStyle(styleName)
    local showBorder = addon.GameMasterSettings
        .ShouldShowWindowBorder(MODULE_ID)
    local emptyBorder = { 0, 0, 0, 0 }
    setBackdrop(
        window,
        style.frameBackground,
        showBorder and style.frameBorder or emptyBorder
    )
    setBackdrop(
        window.section,
        style.panelBackground,
        showBorder and style.panelBorder or emptyBorder
    )
    for index, row in ipairs(window.rows) do
        local background = index % 2 == 0
            and style.rowBackgroundEven
            or style.rowBackgroundOdd
        local border = showBorder and style.rowBorder or emptyBorder
        setBackdrop(row, background, border)
        setBackdrop(row.spellButton, background, border)
        addon.GameMasterActionList.ApplyStyle(
            row.actionList,
            style,
            showBorder
        )
    end
    addon.UIFactory.ApplyButtonStyle(window.minimizeButton, styleName)
    for _, button in pairs(window.actorTabs.buttons) do
        addon.UIFactory.ApplyButtonStyle(button, styleName)
    end
    window:SetAlpha(addon.GameMasterSettings.GetWindowOpacity(
        MODULE_ID,
        0.95
    ))
    applyFonts()
end

local function refresh()
    if not window then
        return
    end
    local mode = addon.GameMasterService.GetVisibility()
    local context = addon.GameMasterService.GetSubmissionContext()
    local allEntries = addon.GameMasterService.GetSharedActions()
    local selected, changed = addon.GameMasterSharedActions.ResolveActorList(window.actorListState, context)
    local entries, counts = addon.GameMasterSharedActions.FilterActorList(allEntries, selected)
    window.actorTabs:Update(selected, counts)
    if changed then window.scroll:SetVerticalScroll(0) end
    local useProfileColors = addon.GameMasterSettings
        .ShouldUseSharedProfileColors()
    local iconSize = math.max(10, (getMetrics().fontSize or 12) - 1)
    window.visibility:SetVisibilityMode(mode)
    window.roundText = context and addon.L(
        "GAMEMASTER_ROUND_OPEN",
        context.roundNumber or 0
    ) or addon.L("GAMEMASTER_NO_ACTIVE_ROUND")
    if context and addon.GameMasterService.GetEncounterOptions().enemyPhases then
        window.roundText = window.roundText .. " | " .. addon.GameMasterService.GetPhaseLabel()
    end
    window.round:SetText(window.roundText)


    for index, row in ipairs(window.rows) do
        local entry = entries[index]
        if row.entry and row.entry.npcProfile and (not entry
            or entry.playerKey ~= row.entry.playerKey or not entry.npcProfile) then
            addon.GameMasterNPCTooltip.Hide(row.nameButton)
        end
        if entry then
            row.entry = entry
            updateRowBuffs(row, addon.GameMasterSharedActions.IsNPCEntry(entry)
                and entry.playerKey or entry.playerID)
            row.name:SetText(string.format(
                "%d. %s%s",
                index,
                getTurnStatusIcon(entry, iconSize),
                getParticipantDisplayName(entry)
            ))
            addon.UIFactory.SetFontColor(
                row.name,
                useProfileColors and (entry.npcProfile and entry.npcProfile.nameColor or entry.profileColor) or nil,
                addon.Theme.Colors.text
            )
            row.action:SetText(entry.action
                and addon.L(actionLabels[entry.action])
                or "")
            if entry.spell then
                setSpellIcon(row.spellButton.icon, entry.spell, true)
                row.spellButton.name:SetText(
                    entry.spell.name or addon.L("UNKNOWN_ABILITY")
                )
                row.spellButton:Enable()
            else
                clearSpellIconFrame(row.spellButton.icon)
                row.spellButton.name:SetText(
                    addon.L("GAMEMASTER_NO_ACTION")
                )
                row.spellButton:Disable()
            end
            if mode == "hidden" then
                local _, statusText = getTurnStatus(entry)
                row.target:SetText(statusText)
                local statusColor = entry.completed == true
                    and addon.Theme.Colors.success
                    or addon.Theme.Colors.textMuted
                row.target:SetTextColor(
                    statusColor[1], statusColor[2], statusColor[3], statusColor[4]
                )
            else
                row.target:SetText(
                    addon.GameMasterActionPresentation.FormatTargets(entry, 20)
                )
                local textColor = addon.Theme.Colors.text
                row.target:SetTextColor(
                    textColor[1], textColor[2], textColor[3], textColor[4]
                )
            end
            addon.GameMasterActionList.SetSubmission(
                row.actionList,
                mode == "full" and entry or nil
            )
            row.actionList:SetShown(mode == "full")
            row.action:SetShown(mode ~= "full")
            row.spellButton:SetShown(mode ~= "full")
            row.targetButton:SetShown(mode ~= "full")
            row:Show()
        else
            row.entry = nil
            row.buffEntries = {}
            row.buffOffset = 0
            row.buffVisibleCount = 0
            addon.GameMasterActionList.SetSubmission(row.actionList, nil)
            row:Hide()
        end
    end
    window.visibleRowCount = #entries
    window.empty:SetText(addon.L(selected == "enemies"
        and "GAMEMASTER_ENCOUNTER_ENEMIES_EMPTY" or "GAMEMASTER_SHARED_ACTIONS_EMPTY"))
    window.empty:SetShown(#entries == 0)
    applyStyle()
    if not window.windowMinimized then
        layoutChrome()
        layoutAdaptiveRows(mode)
    end
end

local function setWindowMinimized(minimized)
    if not window then return end
    minimized = minimized == true
    local changed = minimized ~= (window.windowMinimized == true)

    if minimized then
        if changed then saveLayout(false) end
        anchorTopLeft(window)
        window.windowMinimized = true
        window:SetHeight(MINIMIZED_HEIGHT)
    else
        window.windowMinimized = false
        if changed then restoreLayout() end
    end
    for _, region in ipairs(window.expandableRegions or {}) do
        region:SetShown(not minimized)
    end
    window:SetResizable(not minimized)
    addon.UIFactory.SetWindowMinimizeState(window.minimizeButton, minimized)
    if changed and not minimized then refresh() end
end

local function createWindow()
    local theme = addon.Theme
    local definition = addon.GameMasterLayout.GetDefinition(MODULE_ID)
    local frame = addon.UIFactory.CreateDialog(
        addon.L("GAMEMASTER_SHARED_ACTIONS_TITLE"),
        definition.defaultWidth,
        definition.defaultHeight
    )
    addon.UIFactory.ConfigureInformationWindow(frame)
    frame.baseTitle = addon.L("GAMEMASTER_SHARED_ACTIONS_TITLE")
    frame.title:SetWordWrap(false)
    frame:SetResizable(true)
    frame:SetClipsChildren(true)
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizeBounds(
            definition.minWidth,
            definition.minHeight,
            definition.maxWidth,
            definition.maxHeight
        )
    else
        frame:SetMinResize(definition.minWidth, definition.minHeight)
        frame:SetMaxResize(definition.maxWidth, definition.maxHeight)
    end
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveLayout(false)
    end)
    local minimizeButton = addon.UIFactory.CreateWindowMinimizeButton(frame, function()
        setWindowMinimized(not window.windowMinimized)
    end)

    local visibility = addon.GameMasterVisibilityButton.Create(frame)
    visibility:SetPoint(
        "RIGHT",
        minimizeButton,
        "LEFT",
        -theme.Spacing.xs,
        0
    )
    visibility:EnableMouse(false)

    local round = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.body, "", theme.Colors.gold
    )
    round:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -43)
    local mode = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.small, "", theme.Colors.textMuted
    )
    mode:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.lg, -45)
    mode:Hide()

    local section = addon.GameMasterWidgets.CreateSection(frame)
    section:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -68)
    section:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -theme.Spacing.lg,
        theme.Spacing.lg
    )
    frame.actorListState = {}
    local actorTabs = addon.GameMasterSharedActions.CreateActorTabs(frame, function(selected)
        frame.actorListState.selected = selected
        if frame.scroll then frame.scroll:SetVerticalScroll(0) end
        refresh()
    end)

    local scroll = addon.GameMasterWidgets.CreateScrollViewport(section)
    scroll:SetPoint("TOPLEFT", section, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -4, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local rows = {}
    for index = 1, addon.Constants.GAMEMASTER_MAX_VISIBLE_ACTORS or 60 do
        local row = addon.GameMasterWidgets.CreateSection(
            content,
            index % 2 == 0
                and theme.Colors.archiveRow
                or theme.Colors.dark
        )
        row:SetHeight(30)
        local name = addon.UIFactory.CreateLabel(
            row, theme.Fonts.small, "", theme.Colors.text
        )
        name:SetWordWrap(false)
        name:SetJustifyH("LEFT")
        local nameButton = CreateFrame("Button", nil, row)
        nameButton:SetAllPoints(name)
        nameButton:SetScript("OnEnter", function(self)
            local profile = row.entry and row.entry.npcProfile
            if profile then addon.GameMasterNPCTooltip.Show(self, profile) end
        end)
        nameButton:SetScript("OnLeave", function(self) addon.GameMasterNPCTooltip.Hide(self) end)
        row.nameButton = nameButton
        row:HookScript("OnHide", function()
            if addon.GameMasterNPCTooltip then addon.GameMasterNPCTooltip.Hide(nameButton) end
        end)
        local buffButtons = {}
        for buffIndex = 1, MAX_ROW_BUFFS do
            local buffButton = CreateFrame("Button", nil, row)
            buffButton:SetSize(16, 16)
            buffButton.icon = buffButton:CreateTexture(nil, "ARTWORK")
            buffButton.icon:SetAllPoints()
            buffButton:SetScript("OnEnter", function(self)
                showBuffTooltip(self, self.entry)
            end)
            buffButton:SetScript("OnLeave", addon.SpellTooltip.Hide)
            buffButton:SetScript("OnClick", function(self, mouseButton)
                if self.entry and self.entry.spell then
                    if addon.ChatInsert.HandleSpellClick(mouseButton, nil, self.entry.spell) then return end
                    addon.SpellLinkWindow.OpenSpell({}, self.entry.spell)
                end
            end)
            buffButton:Hide()
            buffButtons[buffIndex] = buffButton
        end
        local buffOverflow = CreateFrame("Button", nil, row)
        buffOverflow:SetSize(26, 16)
        buffOverflow.text = addon.UIFactory.CreateLabel(
            buffOverflow, theme.Fonts.small, "", theme.Colors.textMuted
        )
        buffOverflow.text:SetAllPoints()
        buffOverflow.text:SetJustifyH("CENTER")
        buffOverflow:SetScript("OnEnter", function(self)
            showBuffOverview(self, row.buffEntries)
        end)
        buffOverflow:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        buffOverflow:Hide()
        local action = addon.UIFactory.CreateLabel(
            row, theme.Fonts.small, "", theme.Colors.textMuted
        )
        action:SetWordWrap(false)
        action:SetJustifyH("LEFT")
        local spellButton = createSpellButton(row)
        local targetButton = CreateFrame("Button", nil, row)
        local target = addon.UIFactory.CreateLabel(
            targetButton, theme.Fonts.small, "", theme.Colors.text
        )
        target:SetAllPoints()
        target:SetWordWrap(false)
        target:SetJustifyH("LEFT")

        spellButton:SetScript("OnEnter", function(self)
            if row.entry and row.entry.spell then
                addon.SpellTooltip.Show(
                    self,
                    row.entry.spell,
                    false,
                    "ANCHOR_RIGHT",
                    { showChatHint = true }
                )
            end
        end)
        spellButton:SetScript("OnLeave", function()
            addon.SpellTooltip.Hide()
        end)
        spellButton:SetScript("OnClick", function(_, mouseButton)
            if row.entry and row.entry.spell then
                if addon.ChatInsert.HandleSpellClick(mouseButton, row.entry.playerID, row.entry.spell) then return end
                addon.SpellLinkWindow.OpenSpell(
                    { owner = row.entry.playerID },
                    row.entry.spell
                )
            end
        end)
        targetButton:SetScript("OnEnter", function(self)
            if row.entry then
                showTargetOverview(self, row.entry)
            end
        end)
        targetButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row.action = action
        row.buffButtons = buffButtons
        row.buffOverflow = buffOverflow
        row.name = name
        row.spellButton = spellButton
        row.target = target
        row.targetButton = targetButton
        row.actionList = addon.GameMasterActionList.Create(row)
        rows[index] = row
    end

    local empty = addon.UIFactory.CreateLabel(
        section,
        theme.Fonts.body,
        addon.L("GAMEMASTER_SHARED_ACTIONS_EMPTY"),
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
        if button ~= "LeftButton" then
            return
        end
        anchorTopLeft(frame)
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
        layoutAdaptiveRows(addon.GameMasterService.GetVisibility())
    end)

    frame.content = content
    frame.actorTabs = actorTabs
    frame.empty = empty
    frame.mode = mode
    frame.resize = resize
    frame.round = round
    frame.rows = rows
    frame.scroll = scroll
    frame.section = section
    frame.visibility = visibility
    frame.expandableRegions = {
        actorTabs,
        mode,
        resize,
        round,
        section,
        visibility,
    }
    frame:SetScript("OnSizeChanged", function()
        if not frame.windowMinimized then
            applyFonts()
            layoutChrome()
            layoutAdaptiveRows(addon.GameMasterService.GetVisibility())
        end
    end)
    frame:HookScript("OnHide", function(self)
        if self.isUserResizing then
            self:StopMovingOrSizing()
            self.isUserResizing = false
        end
    end)
    scroll:SetScript("OnSizeChanged", function()
        layoutAdaptiveRows(addon.GameMasterService.GetVisibility())
    end)
    return frame
end

function addon.GameMasterSharedActions.Open(restoreWindow)
    if not addon.GameMasterService.IsSessionActive()
        or (restoreWindow ~= true and not restoredForGameMaster
            and addon.GameMasterService.IsActiveGameMaster()
            and not addon.GameMasterService.IsTestMode())
    then
        return false
    end
    window = window or createWindow()
    manuallyHidden = false
    if restoreWindow == true then
        restoredForGameMaster = addon.GameMasterService.IsActiveGameMaster()
    end
    if restoreWindow == true then window.windowMinimized = false end
    restoreLayout()
    refresh()
    setWindowMinimized(window.windowMinimized)
    window:Show()
    addon.UIFactory.BringToFront(window)
    return true
end

function addon.GameMasterSharedActions.IsShown()
    return window ~= nil and window:IsShown() or false
end

function addon.GameMasterSharedActions.Hide()
    manuallyHidden, restoredForGameMaster = true, false
    if window then window:Hide() end
end

function addon.GameMasterSharedActions.Refresh()
    refresh()
end

addon.GameMasterService.RegisterListener(function(reason)
    local mode = addon.GameMasterService.GetVisibility()
    local activeGameMaster = addon.GameMasterService.IsActiveGameMaster()
    local active = addon.GameMasterService.IsSessionActive()
    if not active then restoredForGameMaster = false end
    if activeGameMaster and not addon.GameMasterService.IsTestMode() and not restoredForGameMaster then
        if window then window:Hide() end
        previousMode = mode
        wasGameMaster = true
        return
    end
    local autoOpen = addon.GameMasterSettings.ShouldAutoOpenWindow(MODULE_ID)
    if not active then
        if window then window:Hide() end
        manuallyHidden = false
    elseif autoOpen
        and (wasGameMaster or not window or not window:IsShown())
        and (reason == "round" or reason == "remote"
            or reason == "restored" or reason == "session")
        and not manuallyHidden
    then
        addon.GameMasterSharedActions.Open()
    elseif window and window:IsShown() then
        refresh()
    end
    previousMode = mode
    wasGameMaster = false
end)

addon.GameMasterSettings.RegisterListener(function()
    if window and window:IsShown() then
        refresh()
    end
end)

addon.GameMasterLayout.RegisterListener(function(moduleID)
    if moduleID ~= nil or not window then
        return
    end
    restoreLayout()
    setWindowMinimized(window.windowMinimized)
    if window:IsShown() then
        refresh()
    end
end)

addon.GameMasterEffects.RegisterListener(function(reason)
    if reason == "expired" and window and window:IsShown() then
        refresh()
    end
end)
