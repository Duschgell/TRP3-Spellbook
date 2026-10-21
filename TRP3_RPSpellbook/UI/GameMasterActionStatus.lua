local _, addon = ...

addon.GameMasterActionStatus = {}

local MODULE_ID = "currentAction"
local BUFF_ROW_HEIGHT = 20
local MAX_VISIBLE_BUFFS = 3
local MAX_INCOMING_PER_ROUND = 300
local MINIMIZED_HEIGHT = 38
local window
function addon.GameMasterActionStatus.GetTutorialContext() return window end
local manuallyHidden = false
local explicitlyRestored = false
local turnState = { visible = false, completed = false, enabled = false }
local turnCompletedHandler
local incomingNotice = { rounds = {} }

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

local actionLabels = {
    cast = "GAMEMASTER_ACTION_CAST",
    channel = "GAMEMASTER_ACTION_CHANNEL",
    prepare = "GAMEMASTER_ACTION_PREPARE",
}

local function getIncomingActions()
    local service = addon.GameMasterService
    local entries = service.GetIncomingActions and service.GetIncomingActions() or {}
    entries = type(entries) == "table" and entries or {}
    local groups = { {}, {}, overflow = math.max(0, #entries - MAX_INCOMING_PER_ROUND * 2) }
    local seen = {}
     
     
    for index = 1, math.min(#entries, MAX_INCOMING_PER_ROUND * 2) do
        local entry = entries[index]
        if type(entry) == "table" and type(entry.id) == "string"
            and type(entry.roundID) == "string" and type(entry.spell) == "table" then
            local group = groups[entry.previous == true and 2 or 1]
            local key = entry.roundID .. ":" .. entry.id
            if not seen[key] then
                seen[key] = true
                if #group < MAX_INCOMING_PER_ROUND then
                    group[#group + 1] = entry
                else
                    groups.overflow = groups.overflow + 1
                end
            end
        end
    end
    return groups
end

local function incomingIdentity(context)
    if not context or not context.sessionID or not context.activationID then return nil end
    return table.concat({ context.sessionID, context.activationID,
        addon.GameMasterRoster.GetLocalPlayerID() or "" }, ":")
end

local function observeIncoming(reason, groups)
    local context = addon.GameMasterService.GetSubmissionContext()
    local identity = incomingIdentity(context)
    local sound = addon.GameMasterTurnSound
    if not identity then
        incomingNotice = { rounds = {} }
        if sound then sound.Stop("incoming") end
        return
    end
    local baseline = identity ~= incomingNotice.identity
    if baseline then
        incomingNotice = { identity = identity, rounds = {},
            awaitingVisibility = addon.GameMasterService.GetRemoteSession() ~= nil }
        if sound then sound.Stop("incoming") end
    end
    local silent = baseline or reason == "restored" or incomingNotice.awaitingVisibility
    local options = addon.GameMasterService.GetEncounterOptions
        and addon.GameMasterService.GetEncounterOptions() or {}
    local legacyReveal = options.enemyPhases == true and options.enemyFirst == false
        and options.deferEnemyActions ~= false and context.phase == "players"
    local rounds, newIncoming = {}, false
    if context.roundID then
        rounds[context.roundID] = incomingNotice.rounds[context.roundID] or { count = 0, ids = {} }
    end
    for _, group in ipairs(groups) do
        for _, entry in ipairs(group) do
            local seen = rounds[entry.roundID] or incomingNotice.rounds[entry.roundID]
                or { count = 0, ids = {} }
            rounds[entry.roundID] = seen
            if not seen.ids[entry.id] and seen.count < MAX_INCOMING_PER_ROUND then
                seen.ids[entry.id] = true
                seen.count = seen.count + 1
                 
                newIncoming = newIncoming or entry.previous ~= true
                    or legacyReveal and entry.phase == "enemies"
            end
        end
    end
    incomingNotice.rounds = rounds
    if reason == "visibility" then incomingNotice.awaitingVisibility = false end
    if not silent and newIncoming and sound then sound.Play(nil, "incoming") end
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

local function getCurrent()
    local pending = addon.GameMasterDelayedSubmission
        and addon.GameMasterDelayedSubmission.GetPending()
        or nil
    if pending then
        return pending, addon.L("GAMEMASTER_WAITING_FOR_EMOTE"), true
    end
    local context = addon.GameMasterService.GetSubmissionContext()
    local submission = context
        and (context.pendingSubmission or context.lastSubmission)
        or nil
    if submission then
        return submission, context.pendingSubmission
            and addon.L("GAMEMASTER_SUBMISSION_PENDING")
            or addon.L("GAMEMASTER_SUBMISSION_ACCEPTED"), false
    end
    return nil
end

local function getOwnActions()
    local service = addon.GameMasterService
    local context = service.GetSubmissionContext()
    local groups = service.GetOwnActionGroups and service.GetOwnActionGroups()
        or { { submission = context and context.lastSubmission } }
    local delayed = addon.GameMasterDelayedSubmission
    local projected = delayed and delayed.GetPending() and delayed.GetProjectedSubmission
        and delayed.GetProjectedSubmission()
    if projected then
        local combined = { { submission = projected } }
        for _, group in ipairs(groups) do
            if group.name then combined[#combined + 1] = group end
        end
        groups = combined
    end
    local entries = {}
    local limit = (1 + (addon.GameMasterNPCActors and addon.GameMasterNPCActors.MAX_ACTORS or 40))
        * addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER
    for _, group in ipairs(groups) do
        for _, action in ipairs(addon.GameMasterActionCollection.Get(group.submission)) do
            if #entries >= limit then return entries, projected ~= nil end
            entries[#entries + 1] = { action = action, actorID = group.actorID, actorName = group.name }
        end
    end
    return entries, projected ~= nil
end

local function getBuffRemaining(entry)
    local remote = addon.GameMasterService.GetRemoteSession()
    local round = addon.GameMasterService.GetActiveRound()
    local roundNumber = round and round.number
        or (remote and remote.roundNumber)
        or 0
    if entry.spell and entry.spell.effects and entry.spell.effects.durationRounds == 0 then
        return addon.Constants.EFFECT_DURATION_INFINITY
    end
    if entry.expiresRound then
        local remaining = math.max(0, entry.expiresRound - roundNumber)
        return addon.L("GAMEMASTER_BUFF_REMAINING_ROUNDS", remaining), remaining == 1
    end
    if entry.expiresAt then
        local seconds = math.max(0, entry.expiresAt - addon.Runtime.GetTimestamp())
        local formatted = type(_G.SecondsToTime) == "function"
            and _G.SecondsToTime(seconds)
            or (tostring(math.ceil(seconds)) .. "s")
        return addon.L("GAMEMASTER_BUFF_REMAINING_TIME", formatted), false
    end
    return "", false
end

local function getLocalBuffs()
    local playerID = addon.GameMasterRoster.GetLocalPlayerID()
    local buffs = playerID
        and addon.GameMasterService.GetActiveBuffsForPlayer(playerID)
        or {}
    local finalRound = false
    for _, entry in ipairs(buffs) do
        local _, isFinal = getBuffRemaining(entry)
        finalRound = finalRound or isFinal
    end
    return buffs, finalRound
end

local function getInlineIcon(spell, size)
    local resolved = addon.TRP3Bridge.ResolveIconTexture(
        type(spell) == "table" and spell.icon
            or addon.Constants.DEFAULT_BOOK_ICON
    )
    local texture = resolved and tostring(resolved):gsub("[|:]", "") or ""
    if texture == "" then
        return ""
    end
    size = math.max(8, math.floor(tonumber(size) or 14))
    return string.format("|T%s:%d:%d|t ", texture, size, size)
end

local function showBuffCollectionTooltip(owner)
    if not window or type(window.activeBuffs) ~= "table" then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(addon.L("GAMEMASTER_TOOLTIP_BUFFS"))
    for _, entry in ipairs(window.activeBuffs) do
        local spell = type(entry) == "table" and entry.spell or {}
        local red, green, blue = addon.UIFactory.GetColorRGB(spell.nameColor)
        GameTooltip:AddDoubleLine(
            getInlineIcon(spell, 14)
                .. (spell.name or addon.L("UNKNOWN_ABILITY")),
            getBuffRemaining(entry),
            red, green, blue,
            0.62, 0.85, 0.62
        )
    end
    GameTooltip:Show()
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

local function getMetrics()
    return addon.GameMasterWidgets.GetContentMetrics(
        MODULE_ID, window
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
    addon.GameMasterWidgets.SetFontSize(window.spell, size, 2)
    addon.GameMasterWidgets.SetFontSize(window.detail, size)
    addon.GameMasterWidgets.SetFontSize(window.targets, size, -1)
    addon.GameMasterWidgets.SetFontSize(window.status, size, -1)
    for _, row in ipairs(window.buffRows or {}) do
        addon.GameMasterWidgets.SetFontSize(row.name, size, -1)
        addon.GameMasterWidgets.SetFontSize(row.remaining, size, -2)
    end
    addon.GameMasterWidgets.SetFontSize(window.buffOverflow.text, size, -1)
end

local function layoutBuffs(width, fontSize)
    local entries = window.activeBuffs or {}
    local iconSize = math.max(12, fontSize + 1)
    local textLeft = iconSize + 5
    local textWidth = math.max(1, width - textLeft)
    local offset = 0
    local visibleCount = math.min(#entries, MAX_VISIBLE_BUFFS)
    local overflowCount = math.max(0, #entries - visibleCount)
    window.buffContainer:SetWidth(width)

    for index, row in ipairs(window.buffRows) do
        local entry = index <= visibleCount and entries[index] or nil
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            local spell = entry.spell or {}
            setSpellIcon(row.icon, spell, true)
            row.name:SetText(spell.name or addon.L("UNKNOWN_ABILITY"))
            addon.UIFactory.SetFontColor(
                row.name,
                spell.nameColor,
                addon.Theme.Colors.gold
            )
            local remaining, isFinal = getBuffRemaining(entry)
            row.remaining:SetText(remaining)
            if isFinal then
                if not row.pulse:IsPlaying() then row.pulse:Play() end
            else
                row.pulse:Stop()
                row.icon:SetAlpha(1)
            end
            local nameWidth = addon.GameMasterWidgets.MeasureTextWidth(
                row.name, row.name:GetText(), fontSize - 1) + 2
            local remainingWidth = addon.GameMasterWidgets.MeasureTextWidth(
                row.remaining, remaining, fontSize - 2) + 2
            local inline = nameWidth + remainingWidth + 6 <= textWidth
            local nameHeight = addon.GameMasterWidgets.MeasureText(
                row.name, row.name:GetText(), inline and nameWidth or textWidth, fontSize - 1, true
            )
            local remainingHeight = addon.GameMasterWidgets.MeasureText(
                row.remaining, remaining, inline and remainingWidth or textWidth, fontSize - 2, true
            )
            local hasRemaining = remaining ~= ""
            local textHeight = inline and math.max(nameHeight, remainingHeight)
                or nameHeight + (hasRemaining and remainingHeight + 2 or 0)
            local rowHeight = math.max(iconSize, textHeight) + 4
            row:ClearAllPoints()
            row:SetPoint(
                "TOPLEFT",
                window.buffContainer,
                "TOPLEFT",
                0,
                -offset
            )
            row:SetPoint("RIGHT", window.buffContainer, "RIGHT", 0, 0)
            row:SetHeight(rowHeight)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.icon:SetSize(iconSize, iconSize)
            row.name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -2)
            row.name:SetSize(inline and nameWidth or textWidth, nameHeight)
            row.name:SetJustifyV("TOP")
            row.remaining:SetPoint("TOPLEFT", row, "TOPLEFT",
                inline and textLeft + nameWidth + 6 or textLeft,
                inline and -2 or -nameHeight - 4)
            row.remaining:SetSize(inline and remainingWidth or textWidth, remainingHeight)
            row.remaining:SetShown(hasRemaining)
            row.remaining:SetJustifyH("LEFT")
            row.remaining:SetJustifyV("TOP")
            offset = offset + rowHeight
        else
            row.pulse:Stop()
            row.icon:SetAlpha(1)
        end
    end

    window.buffOverflow:SetShown(overflowCount > 0)
    if overflowCount > 0 then
        local overflowHeight = addon.GameMasterWidgets.MeasureText(
            window.buffOverflow.text, addon.L("GAMEMASTER_MORE_BUFFS", overflowCount),
            textWidth, fontSize - 1, true
        )
        window.buffOverflow.text:SetPoint("TOPLEFT", window.buffOverflow, "TOPLEFT", textLeft, -2)
        window.buffOverflow.text:SetHeight(overflowHeight)
        window.buffOverflow:ClearAllPoints()
        window.buffOverflow:SetPoint(
            "TOPLEFT",
            window.buffContainer,
            "TOPLEFT",
            0,
            -offset
        )
        window.buffOverflow:SetPoint(
            "RIGHT", window.buffContainer, "RIGHT", 0, 0
        )
        window.buffOverflow:SetHeight(overflowHeight + 4)
        offset = offset + overflowHeight + 4
    end

    local displayRows = visibleCount + (overflowCount > 0 and 1 or 0)
    local displayHeight = offset
    window.buffContainer:SetHeight(math.max(1, displayHeight))
    window.buffContainer:SetShown(displayRows > 0)
    window.buffContainer.displayHeight = displayHeight
    return displayHeight
end

local function createIncomingRow()
    local row = CreateFrame("Button", nil, window.body)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.spell = addon.UIFactory.CreateLabel(row, addon.Theme.Fonts.body, "", addon.Theme.Colors.gold)
    row.caster = addon.UIFactory.CreateLabel(row, addon.Theme.Fonts.small, "", addon.Theme.Colors.textMuted)
    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.entry.spell.name or addon.L("UNKNOWN_ABILITY"))
        GameTooltip:AddLine(self.caster:GetText(), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnHide", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    return row
end

local function layoutOwnActions(width, fontSize, offset)
    local entries = window.ownActions or {}
    local used = window.showOwnList and #entries or 0
    for index = 1, used do
        local row = window.ownRows[index]
        if not row then
            row = createIncomingRow()
            row.targets = addon.UIFactory.CreateLabel(row, addon.Theme.Fonts.small, "", addon.Theme.Colors.textMuted)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnEnter", function(self)
                if self.entry then addon.SpellTooltip.Show(self, self.entry.action.spell, false,
                    "ANCHOR_RIGHT", { showChatHint = true }) end
            end)
            row:SetScript("OnLeave", addon.SpellTooltip.Hide)
            row:SetScript("OnClick", function(self, button)
                if not self.entry then return end
                local spell = self.entry.action.spell
                if addon.ChatInsert.HandleSpellClick(button, nil, spell) then return end
                addon.SpellLinkWindow.OpenSpell({}, spell)
            end)
            window.ownRows[index] = row
        end
        local entry = entries[index]
        if row.entry ~= entry and GameTooltip:IsOwned(row) then addon.SpellTooltip.Hide() end
        row.entry = entry
        local action, spell = entry.action, entry.action.spell
        local iconSize = math.min(32, fontSize + 14)
        local showIcon = addon.GameMasterSettings.ShouldShowActionIcon()
        local left = showIcon and iconSize + 6 or 0
        local description = addon.GameMasterActionPresentation.FormatPreparation(action)
            or addon.L(actionLabels[action.action] or "GAMEMASTER_NO_ACTION")
        if entry.actorName then description = entry.actorName .. " - " .. description end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window.body, "TOPLEFT", 0, -offset)
        row:SetWidth(width)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetShown(showIcon)
        setSpellIcon(row.icon, spell, showIcon)
        local texts = { spell.name or addon.L("UNKNOWN_ABILITY"), description,
            addon.GameMasterActionPresentation.FormatTargets(action, 5) }
        local height = 0
        for fieldIndex, label in ipairs({ row.spell, row.caster, row.targets }) do
            local text = texts[fieldIndex] or ""
            label:SetShown(text ~= "")
            if text ~= "" then
                local measured = addon.GameMasterWidgets.MeasureText(label, text,
                    math.max(1, width - left), fontSize + (fieldIndex == 1 and 1 or -1), true)
                label:SetPoint("TOPLEFT", row, "TOPLEFT", left, -height)
                label:SetHeight(measured)
                label:SetJustifyH("LEFT")
                label:SetJustifyV("TOP")
                height = height + measured + 2
            else
                label:SetText("")
            end
        end
        height = math.max(height, showIcon and iconSize or 0) + 6
        addon.UIFactory.SetFontColor(row.spell, spell.nameColor or spell.color, addon.Theme.Colors.gold)
        row:SetHeight(height)
        row:Show()
        offset = offset + height
    end
    for index = used + 1, #window.ownRows do
        local row = window.ownRows[index]
        row.entry = nil
        row:Hide()
    end
    return offset
end

local function layoutIncoming(width, fontSize, offset)
    local used = 0
    for groupIndex, group in ipairs(window.incomingGroups or { {}, {} }) do
        local heading = window.incomingHeadings[groupIndex]
        heading:SetShown(#group > 0)
        if #group > 0 then
            offset = offset + (offset > 0 and 6 or 0)
            local title = addon.L(groupIndex == 1 and "GAMEMASTER_INCOMING_CURRENT"
                or "GAMEMASTER_INCOMING_PREVIOUS", tonumber(group[1].roundNumber) or 0)
            local height = addon.GameMasterWidgets.MeasureText(heading, title, width, fontSize - 1, true)
            heading:SetPoint("TOPLEFT", window.body, "TOPLEFT", 0, -offset)
            heading:SetHeight(height)
            heading:SetJustifyH("LEFT")
            offset = offset + height + 3
            for _, entry in ipairs(group) do
                used = used + 1
                local row = window.incomingRows[used] or createIncomingRow()
                window.incomingRows[used] = row
                if row.entry ~= entry and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
                row.entry = entry
                local spell = entry.spell
                local showIcon = addon.GameMasterSettings.ShouldShowActionIcon()
                local iconSize = math.min(24, fontSize + 5)
                local left = showIcon and iconSize + 5 or 0
                local textWidth = math.max(1, width - left)
                local spellText = spell.name or addon.L("UNKNOWN_ABILITY")
                local casterText = addon.L("GAMEMASTER_INCOMING_CASTER",
                    entry.casterName or entry.casterID or "",
                    addon.L(actionLabels[entry.action] or "GAMEMASTER_NO_ACTION"))
                local plan = row.incomingLayout
                 
                 
                if not plan or plan.textWidth ~= textWidth or plan.fontSize ~= fontSize
                    or plan.spellText ~= spellText or plan.casterText ~= casterText then
                    local spellWidth = addon.GameMasterWidgets.MeasureTextWidth(row.spell, spellText, fontSize) + 2
                    local casterWidth = addon.GameMasterWidgets.MeasureTextWidth(row.caster, casterText, fontSize - 1) + 2
                    local inline = spellWidth + casterWidth + 8 <= textWidth
                    plan = {
                        textWidth = textWidth, fontSize = fontSize, spellText = spellText, casterText = casterText,
                        spellWidth = spellWidth, inline = inline,
                        spellHeight = addon.GameMasterWidgets.MeasureText(row.spell, spellText,
                            inline and spellWidth or textWidth, fontSize, true),
                        casterHeight = addon.GameMasterWidgets.MeasureText(row.caster, casterText,
                            inline and casterWidth or textWidth, fontSize - 1, true),
                    }
                    row.incomingLayout = plan
                end
                local spellWidth, inline = plan.spellWidth, plan.inline
                local spellHeight, casterHeight = plan.spellHeight, plan.casterHeight
                local height = math.max(showIcon and iconSize or 0, inline
                    and math.max(spellHeight, casterHeight) or spellHeight + casterHeight + 1) + 5
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", window.body, "TOPLEFT", 0, -offset)
                row:SetSize(width, height)
                row.icon:ClearAllPoints()
                row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
                row.icon:SetSize(iconSize, iconSize)
                row.icon:SetShown(showIcon)
                setSpellIcon(row.icon, spell, showIcon)
                row.spell:SetPoint("TOPLEFT", row, "TOPLEFT", left, 0)
                row.spell:SetHeight(spellHeight)
                row.caster:SetPoint("TOPLEFT", row, "TOPLEFT", inline and left + spellWidth + 8 or left,
                    inline and 0 or -spellHeight - 1)
                row.caster:SetHeight(casterHeight)
                for _, label in ipairs({ row.spell, row.caster }) do
                    label:SetJustifyH("LEFT")
                    label:SetJustifyV("TOP")
                end
                addon.UIFactory.SetFontColor(row.spell, spell.nameColor or spell.color, addon.Theme.Colors.gold)
                addon.UIFactory.SetFontColor(row.caster, entry.casterColor, addon.Theme.Colors.textMuted)
                row:Show()
                offset = offset + height
            end
        end
    end
    for index = used + 1, #window.incomingRows do
        local row = window.incomingRows[index]
        row.entry = nil
        row.incomingLayout = nil
        row.spell:SetText("")
        row.caster:SetText("")
        row:Hide()
    end
    local overflow = window.incomingGroups and window.incomingGroups.overflow or 0
    window.incomingOverflow:SetShown(overflow > 0)
    if overflow > 0 then
        local height = addon.GameMasterWidgets.MeasureText(window.incomingOverflow,
            addon.L("GAMEMASTER_INCOMING_OVERFLOW", overflow), width, fontSize - 1, true)
        window.incomingOverflow:SetPoint("TOPLEFT", window.body, "TOPLEFT", 0, -offset)
        window.incomingOverflow:SetHeight(height)
        offset = offset + height + 3
    end
    return offset
end

local function layoutContent()
    if not window or window.isLayingOut or window.windowMinimized then
        return
    end
    window.isLayingOut = true
    local metrics = getMetrics()
    local padding = metrics.padding
    local fontSize = metrics.fontSize
    local width = math.max(1, window:GetWidth() or 320)
    local headerHeight = math.max(26, fontSize + 18)
    local showCancel = window.cancel:IsShown()
    local showTurn = turnState.visible == true
    local hasStatus = (window.status:GetText() or "") ~= ""
    local footerHeight = (showCancel or showTurn or hasStatus)
        and math.max(22, fontSize + 8) or 0
    window.title:ClearAllPoints()
    window.title:SetPoint("TOPLEFT", window, "TOPLEFT", padding, -6)
    window.title:SetWidth(math.max(1, width - padding - 32))
    window.title:SetWordWrap(false)
    window.title:SetJustifyH("LEFT")
    window.scroll:ClearAllPoints()
    window.scroll:SetPoint("TOPLEFT", window, "TOPLEFT", padding, -headerHeight)
    window.scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -padding, padding + footerHeight)
    window.status:ClearAllPoints()
    window.cancel:ClearAllPoints()
    window.turnCompleted:ClearAllPoints()
    window.turnCompleted:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -18, padding)
    window.turnCompleted:SetShown(showTurn)
    window.turnCompleted:SetChecked(turnState.completed == true)
    window.turnCompleted:SetEnabled(turnState.enabled == true and turnCompletedHandler ~= nil)
    local footerRight = showTurn and 44 or 18
    if showCancel then
        local cancelWidth = math.min(132, math.max(70, width - footerRight - 70))
        window.cancel:SetSize(cancelWidth, 22)
        window.cancel:SetPoint(
            "BOTTOMRIGHT", window, "BOTTOMRIGHT", -footerRight, padding
        )
        footerRight = footerRight + cancelWidth + 4
        local label = window.cancel:GetFontString()
        if label then
            label:SetWidth(math.max(1, cancelWidth - 12))
            label:SetWordWrap(false)
        end
    end
    window.status:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", padding, padding + 3)
    window.status:SetPoint("RIGHT", window, "RIGHT", -footerRight, 0)
    window.status:SetHeight(fontSize + 4)
    window.status:SetJustifyH("LEFT")
    window.status:SetShown(hasStatus)

    local bodyWidth = math.max(1, width - padding * 2)
    window.body:SetWidth(bodyWidth)
    local hasAction = window.currentSpell ~= nil and (not window.showOwnList or window.queuedAction)
    local iconSize = math.min(32, fontSize + 14)
    local showIcon = hasAction and addon.GameMasterSettings.ShouldShowActionIcon()
    local textLeft = showIcon and iconSize + 6 or 0
    window.iconButton:ClearAllPoints()
    window.iconButton:SetSize(iconSize, iconSize)
    window.iconButton:SetPoint("TOPLEFT", window.body, "TOPLEFT", 0, 0)
    window.iconButton:SetShown(showIcon)
    local offset = 0
    for _, field in ipairs({ window.spell, window.detail, window.targets }) do
        local text = field:GetText() or ""
        local shown = hasAction and text ~= ""
        field:SetShown(shown)
        if shown then
            local size = field == window.spell and fontSize + 1 or fontSize
            local measured = addon.GameMasterWidgets.MeasureText(
                field, text, bodyWidth - textLeft, size, true
            )
            field:SetPoint("TOPLEFT", window.body, "TOPLEFT", textLeft, -offset)
            field:SetHeight(measured)
            field:SetJustifyH("LEFT")
            field:SetJustifyV("TOP")
            offset = offset + measured + 2
        end
    end
    offset = math.max(offset, showIcon and iconSize or 0)
    offset = layoutOwnActions(bodyWidth, fontSize, offset)
    if hasAction and #(window.activeBuffs or {}) > 0 then offset = offset + 5 end
    window.buffContainer:ClearAllPoints()
    window.buffContainer:SetPoint("TOPLEFT", window.body, "TOPLEFT", 0, -offset)
    offset = offset + layoutBuffs(bodyWidth, fontSize)
    offset = layoutIncoming(bodyWidth, fontSize, offset)
    window.body:SetHeight(math.max(1, offset))
    window.scroll:UpdateScrollChildRect()
    addon.GameMasterWidgets.ClampScroll(window.scroll, offset)
    window.isLayingOut = false
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
    setBackdrop(
        window,
        style.frameBackground,
        showBorder and style.frameBorder or { 0, 0, 0, 0 }
    )
    addon.UIFactory.ApplyButtonStyle(window.minimizeButton, styleName)
    addon.UIFactory.ApplyButtonStyle(window.cancel, styleName)
    window:SetAlpha(addon.GameMasterSettings.GetWindowOpacity(
        MODULE_ID,
        0.95
    ))
    applyFonts()
    layoutContent()
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
    if changed and not minimized then
        addon.GameMasterActionStatus.Refresh()
        layoutContent()
    end
end

local function createWindow()
    local theme = addon.Theme
    local definition = addon.GameMasterLayout.GetDefinition(MODULE_ID)
    local frame = addon.UIFactory.CreateDialog(
        addon.L("GAMEMASTER_CURRENT_ACTION"),
        definition.defaultWidth,
        definition.defaultHeight
    )
    addon.UIFactory.ConfigureInformationWindow(frame)
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
    addon.UIFactory.CreateWindowMinimizeButton(frame, function()
        setWindowMinimized(not window.windowMinimized)
    end)

    local scroll = addon.GameMasterWidgets.CreateScrollViewport(frame)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)

    local iconButton = CreateFrame("Button", nil, frame)
    iconButton:SetSize(38, 38)
    iconButton:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        theme.Spacing.lg,
        -43
    )
    local icon = iconButton:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    iconButton:SetScript("OnEnter", function(self)
        if frame.currentSpell then
            addon.SpellTooltip.Show(
                self,
                frame.currentSpell,
                false,
                "ANCHOR_RIGHT",
                { showChatHint = true }
            )
        end
    end)
    iconButton:SetScript("OnLeave", function()
        addon.SpellTooltip.Hide()
    end)
    iconButton:SetScript("OnClick", function(_, mouseButton)
        if frame.currentSpell then
            if addon.ChatInsert.HandleSpellClick(mouseButton, nil, frame.currentSpell) then return end
            addon.SpellLinkWindow.OpenSpell({}, frame.currentSpell)
        end
    end)

    local spell = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.header, "", theme.Colors.gold
    )
    spell:SetWordWrap(false)

    local detail = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.body, "", theme.Colors.text
    )
    detail:SetPoint("TOPLEFT", spell, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    detail:SetPoint("RIGHT", frame, "RIGHT", -theme.Spacing.lg, 0)
    detail:SetWordWrap(false)

    local targets = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.small, "", theme.Colors.textMuted
    )
    targets:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    targets:SetPoint("RIGHT", frame, "RIGHT", -theme.Spacing.lg, 0)
    targets:SetPoint("BOTTOM", frame, "BOTTOM", 0, 48)
    targets:SetJustifyH("LEFT")
    targets:SetJustifyV("TOP")
    targets:SetWordWrap(true)

    local status = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.small, "", theme.Colors.success
    )
    status:SetPoint(
        "BOTTOMLEFT",
        frame,
        "BOTTOMLEFT",
        theme.Spacing.lg,
        theme.Spacing.lg
    )
    status:SetPoint("RIGHT", frame, "CENTER", 0, 0)
    status:SetWordWrap(false)

    local buffContainer = CreateFrame("Frame", nil, frame)
    local buffRows = {}
    for index = 1, MAX_VISIBLE_BUFFS do
        local row = CreateFrame("Button", nil, buffContainer)
        row:SetHeight(BUFF_ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.name = addon.UIFactory.CreateLabel(
            row, theme.Fonts.small, "", theme.Colors.gold
        )
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.remaining = addon.UIFactory.CreateLabel(
            row, theme.Fonts.small, "", theme.Colors.success
        )
        row.remaining:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.remaining:SetJustifyH("RIGHT")
        row.remaining:SetWordWrap(false)
        row.name:SetPoint("RIGHT", row.remaining, "LEFT", -8, 0)
        row:SetScript("OnEnter", function(self)
            local entry = self.entry
            if not entry or not entry.spell then return end
            addon.SpellTooltip.Show(
                self,
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
        end)
        row:SetScript("OnLeave", addon.SpellTooltip.Hide)
        row:SetScript("OnClick", function(self, mouseButton)
            if self.entry and self.entry.spell then
                if addon.ChatInsert.HandleSpellClick(mouseButton, nil, self.entry.spell) then return end
                addon.SpellLinkWindow.OpenSpell({}, self.entry.spell)
            end
        end)
        row.pulse = row.icon:CreateAnimationGroup()
        row.pulse:SetLooping("BOUNCE")
        local pulseAlpha = row.pulse:CreateAnimation("Alpha")
        pulseAlpha:SetFromAlpha(1)
        pulseAlpha:SetToAlpha(0.48)
        pulseAlpha:SetDuration(0.75)
        row:Hide()
        buffRows[index] = row
    end

    local buffOverflow = CreateFrame("Button", nil, buffContainer)
    buffOverflow:SetHeight(BUFF_ROW_HEIGHT)
    buffOverflow.text = addon.UIFactory.CreateLabel(
        buffOverflow, theme.Fonts.small, "", theme.Colors.textMuted
    )
    buffOverflow.text:SetPoint("LEFT", buffOverflow, "LEFT", 21, 0)
    buffOverflow.text:SetPoint("RIGHT", buffOverflow, "RIGHT", 0, 0)
    buffOverflow.text:SetJustifyH("LEFT")
    buffOverflow.text:SetWordWrap(false)
    buffOverflow:SetScript("OnEnter", showBuffCollectionTooltip)
    buffOverflow:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    buffOverflow:Hide()

    local cancel = addon.UIFactory.CreateButton(
        frame, addon.L("GAMEMASTER_CANCEL_PREPARATION"), 150
    )
    cancel:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -theme.Spacing.lg,
        theme.Spacing.sm
    )
    cancel:SetScript("OnClick", function()
        addon.GameMasterPreparation.Cancel()
    end)

    local turnCompleted = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    turnCompleted:SetSize(22, 22)
    turnCompleted:Hide()
    turnCompleted:SetScript("OnClick", function(self)
        local requested = self:GetChecked() == true
        self:SetChecked(turnState.completed == true)
        if turnState.enabled and type(turnCompletedHandler) == "function" then
            turnCompletedHandler(requested)
        end
    end)
    turnCompleted:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(addon.L("GAMEMASTER_TURN_COMPLETED"))
        GameTooltip:AddLine(addon.L("GAMEMASTER_TURN_COMPLETED_HINT"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    turnCompleted:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local turnHint = turnCompleted:CreateTexture(nil, "OVERLAY")
    turnHint:SetAllPoints()
    turnHint:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    turnHint:Hide()
    turnCompleted:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        turnHint:Hide()
    end)

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
        layoutContent()
    end)

    frame.cancel = cancel
    frame.activeBuffs = {}
    frame.buffContainer = buffContainer
    frame.buffOverflow = buffOverflow
    frame.buffRows = buffRows
    frame.detail = detail
    frame.icon = icon
    frame.iconButton = iconButton
    frame.resize = resize
    frame.spell = spell
    frame.status = status
    frame.targets = targets
    frame.body = body
    frame.scroll = scroll
    frame.turnCompleted = turnCompleted
    frame.turnHint = turnHint
    frame.expandableRegions = {
        cancel,
        resize,
        scroll,
        turnCompleted,
    }
    frame.incomingGroups = { {}, {} }
    frame.incomingRows = {}
    frame.ownRows = {}
    frame.incomingHeadings = {
        addon.UIFactory.CreateLabel(body, theme.Fonts.small, "", theme.Colors.textMuted),
        addon.UIFactory.CreateLabel(body, theme.Fonts.small, "", theme.Colors.textMuted),
    }
    frame.incomingOverflow = addon.UIFactory.CreateLabel(body, theme.Fonts.small, "", theme.Colors.textMuted)
    iconButton:SetParent(body)
    spell:SetParent(body)
    detail:SetParent(body)
    targets:SetParent(body)
    buffContainer:SetParent(body)
    frame:HookScript("OnHide", function(self)
        if self.isUserResizing then
            self:StopMovingOrSizing()
            self.isUserResizing = false
        end
        addon.GameMasterEffects.SetCountdownVisible(MODULE_ID, false)
        addon.SpellTooltip.Hide()
    end)
    frame:HookScript("OnShow", function()
        addon.GameMasterEffects.SetCountdownVisible(MODULE_ID, true)
    end)
    frame:SetScript("OnSizeChanged", function()
        if not frame.windowMinimized then
            applyFonts()
            layoutContent()
        end
    end)
    restoreLayout()
    applyStyle()
    return frame
end

function addon.GameMasterActionStatus.Refresh(incomingGroups)
    if addon.GameMasterService.IsSessionActive and not addon.GameMasterService.IsSessionActive() then
        explicitlyRestored = false
    end
    if not window then
        return
    end
    local submission, status, queued = getCurrent()
    local projected
    window.ownActions, projected = getOwnActions()
    window.queuedAction = queued and not projected
    window.showOwnList = #window.ownActions > 1
        or #window.ownActions == 1 and window.ownActions[1].actorName ~= nil
        or queued and #window.ownActions > 0
    local buffs = getLocalBuffs()
    local buffCount = #buffs
    window.activeBuffs = buffs
    window.incomingGroups = incomingGroups or getIncomingActions()
    local identity = incomingIdentity(addon.GameMasterService.GetSubmissionContext())
    if window.incomingIdentity ~= identity then
        window.incomingIdentity = identity
        window.scroll:SetVerticalScroll(0)
        addon.SpellTooltip.Hide()
    end
    local hasIncoming = #window.incomingGroups[1] + #window.incomingGroups[2] > 0
    if not submission then
        window.currentSpell = nil
        window.iconButton:Hide()
        window.spell:SetText("")
        window.detail:SetText("")
        window.targets:SetText("")
        window.status:SetText(addon.GameMasterService.GetPhase() == "enemies"
            and addon.GameMasterService.GetPhaseLabel() or "")
        window.cancel:Hide()
        applyStyle()
        window.iconButton:Hide()
        if buffCount == 0 and #window.ownActions == 0 and not turnState.visible
            and not hasIncoming and not explicitlyRestored then
            window:Hide()
            return
        end
        if not manuallyHidden
            and addon.GameMasterSettings.ShouldAutoOpenWindow(MODULE_ID)
        then
            window:Show()
        end
        return
    end
    local spell = submission.spell or {}
    local preparation = addon.GameMasterActionPresentation
        .FormatPreparation(submission)
    local action = addon.L(
        actionLabels[submission.action] or "GAMEMASTER_NO_ACTION"
    )
    window.currentSpell = spell
    setSpellIcon(window.icon, spell, true)
    window.spell:SetText(spell.name or addon.L("UNKNOWN_ABILITY"))
    addon.UIFactory.SetFontColor(window.spell, spell.nameColor or spell.color, addon.Theme.Colors.gold)
    window.detail:SetText(preparation or action)
    window.targets:SetText(
        addon.GameMasterActionPresentation.FormatTargets(submission, 5)
    )
    window.status:SetText(status or "")
    local activePreparation = addon.GameMasterPlayerState.GetPreparation()
    window.cancel:SetShown(activePreparation ~= nil and not window.windowMinimized)
    applyStyle()
    if (not manuallyHidden or queued)
        and addon.GameMasterSettings.ShouldAutoOpenWindow(MODULE_ID)
    then
        window:Show()
        addon.UIFactory.BringToFront(window)
    end
end

local function refreshBuffCountdowns()
     
     
    layoutContent()
end

function addon.GameMasterActionStatus.Open(force)
    if force ~= true
        and not addon.GameMasterSettings.ShouldAutoOpenWindow(MODULE_ID)
    then
        return false
    end
    window = window or createWindow()
    manuallyHidden = false
    if force == true and addon.GameMasterService.IsSessionActive then
        explicitlyRestored = addon.GameMasterService.IsSessionActive()
    end
    if force == true then window.windowMinimized = false end
    restoreLayout()
    addon.GameMasterActionStatus.Refresh()
    setWindowMinimized(window.windowMinimized)
    if force == true
        and (explicitlyRestored or window.currentSpell or #(window.activeBuffs or {}) > 0 or turnState.visible
            or #window.incomingGroups[1] + #window.incomingGroups[2] > 0)
    then
        window:Show()
        addon.UIFactory.BringToFront(window)
    end
    return true
end

function addon.GameMasterActionStatus.Hide()
    manuallyHidden = true
    explicitlyRestored = false
    if window then window:Hide() end
    return true
end

function addon.GameMasterActionStatus.IsShown()
    return window ~= nil and window:IsShown() or false
end

 
 
function addon.GameMasterActionStatus.SetTurnCompletedHandler(callback)
    turnCompletedHandler = type(callback) == "function" and callback or nil
    if window then layoutContent() end
end

function addon.GameMasterActionStatus.SetTurnState(state)
    state = type(state) == "table" and state or {}
    turnState = {
        visible = state.visible == true,
        enabled = state.enabled == true,
        completed = state.completed == true,
    }
    if window and (turnState.completed or not turnState.visible) then
        window.turnCompleted:SetScript("OnUpdate", nil)
        window.turnHint:Hide()
    end
    if turnState.visible and not window then
        addon.GameMasterActionStatus.Open()
    else
        addon.GameMasterActionStatus.Refresh()
    end
end

function addon.GameMasterActionStatus.HintTurnCompletion()
    if not window or not window:IsShown() or not turnState.visible
        or turnState.completed or not turnState.enabled then return end
    local remaining = 5
    window.turnHint:Show()
    window.turnCompleted:SetScript("OnUpdate", function(self, elapsed)
        remaining = remaining - elapsed
        if remaining <= 0 then
            self:SetScript("OnUpdate", nil)
            window.turnHint:Hide()
        else
            window.turnHint:SetAlpha(0.55 + 0.45 * math.abs(math.sin(remaining * 5)))
        end
    end)
end

addon.GameMasterService.RegisterListener(function(reason)
    local groups = getIncomingActions()
    observeIncoming(reason, groups)
    if not window and (#groups[1] + #groups[2] > 0 or #getOwnActions() > 0) then
        addon.GameMasterActionStatus.Open()
    elseif window then
         
        addon.GameMasterActionStatus.Refresh(groups)
    end
end)

addon.GameMasterDelayedSubmission.RegisterListener(function(reason)
    if reason == "queued" or reason == "sent" then
        addon.GameMasterActionStatus.Open()
    else
        addon.GameMasterActionStatus.Refresh()
    end
end)

addon.GameMasterSettings.RegisterListener(function()
    local state = addon.GameMasterPlayerState
    if addon.GameMasterTurnSound and state.ShouldPlayIncomingActionSound
        and not state.ShouldPlayIncomingActionSound() then
        addon.GameMasterTurnSound.Stop("incoming")
    end
    if window then
        addon.GameMasterActionStatus.Refresh()
    end
end)

addon.GameMasterLayout.RegisterListener(function(moduleID)
    if moduleID ~= nil or not window then
        return
    end
    restoreLayout()
    setWindowMinimized(window.windowMinimized)
    addon.GameMasterActionStatus.Refresh()
end)

addon.GameMasterEffects.RegisterListener(function(reason)
    if window and window:IsShown() then
        if reason == "countdown" then
            refreshBuffCountdowns()
        else
            addon.GameMasterActionStatus.Refresh()
        end
    end
end)
