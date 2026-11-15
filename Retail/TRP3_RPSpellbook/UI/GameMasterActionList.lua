local _, addon = ...

addon.GameMasterActionList = {}

local actionLabels = {
    prepare = "GAMEMASTER_ACTION_PREPARE",
    cast = "GAMEMASTER_ACTION_CAST",
    channel = "GAMEMASTER_ACTION_CHANNEL",
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function setFontSize(fontString, size)
    addon.GameMasterWidgets.SetFontSize(fontString, size)
end

local function getTargetText(target)
    local text = target and target.label or ""
    if not target or (target.kind ~= "player" and target.kind ~= "npc") or not target.icon then
        return text
    end
    local texture = addon.TRP3Bridge.ResolveIconTexture(target.icon)
    if not texture then
        return text
    end
    return string.format("|T%s:12:12|t %s", tostring(texture), text)
end

local function createSpellButton(parent, list)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("LEFT", button, "LEFT", 2, 0)
    button.name = addon.UIFactory.CreateLabel(
        button,
        addon.Theme.Fonts.small,
        "",
        addon.Theme.Colors.text
    )
    button.name:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
    button.name:SetPoint("RIGHT", button, "RIGHT", -3, 0)
    button.name:SetJustifyH("LEFT")
    button.name:SetWordWrap(false)
    button:SetScript("OnEnter", function(self)
        local action = self.action
        if not action or not action.spell then
            return
        end
        addon.SpellTooltip.Show(
            self,
            action.spell,
            false,
            "ANCHOR_RIGHT",
            { showChatHint = true }
        )
        if action.emote and action.emote.text then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(
                addon.L("GAMEMASTER_LINKED_EMOTE"),
                0.65, 0.72, 0.82
            )
            GameTooltip:AddLine(action.emote.text, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", addon.SpellTooltip.Hide)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        local action = self.action
        if action and addon.ChatInsert.HandleSpellClick(mouseButton,
            action.playerID, action.spell) then return end
        if type(list.onActionClick) == "function"
            and list.onActionClick(action, mouseButton) == true
        then
            return
        end
        if action and action.spell then
            addon.SpellLinkWindow.OpenSpell(
                { owner = action.playerID or action.spell.ownerKey },
                action.spell
            )
        end
    end)
    return button
end

local function showTargets(owner, targets)
    if type(targets) ~= "table" or #targets == 0 then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(addon.L("GAMEMASTER_TARGET_OVERVIEW"), 1, 0.82, 0)
    for index, target in ipairs(targets) do
        local color = target.color
        local red, green, blue = 0.86, 0.82, 0.72
        if type(color) == "string" and color:match("^%x%x%x%x%x%x$") then
            red = tonumber(color:sub(1, 2), 16) / 255
            green = tonumber(color:sub(3, 4), 16) / 255
            blue = tonumber(color:sub(5, 6), 16) / 255
        end
        GameTooltip:AddDoubleLine(
            tostring(index) .. ".",
            getTargetText(target),
            0.62, 0.56, 0.46,
            red, green, blue
        )
    end
    GameTooltip:Show()
end

local function createView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetClipsChildren(true)
    view.action = addon.UIFactory.CreateLabel(
        view,
        addon.Theme.Fonts.small,
        "",
        addon.Theme.Colors.text
    )
    view.action:SetJustifyH("LEFT")
    view.action:SetJustifyV("MIDDLE")
    view.action:SetWordWrap(false)
    view.spell = createSpellButton(view, parent)
    view.targets = CreateFrame("Button", nil, view)
    view.targets:SetScript("OnEnter", function(self)
        showTargets(self, view.targetOverview)
    end)
    view.targets:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    view.targetLabels = {}
    for index = 1, 8 do
        local label = addon.UIFactory.CreateLabel(
            view.targets,
            addon.Theme.Fonts.small,
            "",
            addon.Theme.Colors.textMuted
        )
        label:SetJustifyH("LEFT")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(false)
        view.targetLabels[index] = label
    end
    return view
end

function addon.GameMasterActionList.Create(parent)
    local list = CreateFrame("Frame", nil, parent)
    list:SetClipsChildren(true)
    list.views = {}
    for index = 1, addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER do
        list.views[index] = createView(list)
    end
    return list
end

local function setSpell(view, action)
    view.spell.action = action
    local spell = action and action.spell
    if not spell then
        addon.UIFactory.ClearSpellIconEffectFrame(view.spell.icon)
        view.spell.icon:Hide()
        view.spell.name:SetText(addon.L("GAMEMASTER_NO_ACTION"))
        view.spell:Disable()
        return
    end
    view.spell:Enable()
    view.spell.icon:Show()
    addon.UIFactory.SetSpellIcon(
        view.spell.icon, spell, addon.Constants.DEFAULT_BOOK_ICON, true
    )
    view.spell.name:SetText(spell.name or addon.L("UNKNOWN_ABILITY"))
    addon.UIFactory.SetFontColor(
        view.spell.name,
        spell.nameColor,
        addon.Theme.Colors.text
    )
end

function addon.GameMasterActionList.SetSubmission(list, submission)
    local actions = addon.GameMasterActionCollection.Get(submission)
    list.submission = submission
    list.actionCount = math.max(1, #actions)
    list.measuredTotal = nil
    list.measuredWidth = nil
    list.measuredFontSize = nil
    list.measuredActionCount = nil
    for index, view in ipairs(list.views) do
        local action = actions[index]
        view.actionData = action
        if index <= list.actionCount then
            local actionText = action
                and addon.L(actionLabels[action.action])
                or addon.L("GAMEMASTER_NO_ACTION")
            local preparation = addon.GameMasterActionPresentation
                .FormatPreparation(action)
            view.action:SetText(preparation or actionText)
            setSpell(view, action)
            view.targetOverview = addon.GameMasterActionPresentation
                .GetTargetOverview(action)
            for targetIndex, label in ipairs(view.targetLabels) do
                local target = view.targetOverview[targetIndex]
                local text = getTargetText(target)
                if targetIndex == 8 and #view.targetOverview > 8 then
                    text = text .. " " .. addon.L(
                        "GAMEMASTER_MORE_TARGETS",
                        #view.targetOverview - 8
                    )
                end
                label:SetText(text)
                label:SetShown(target ~= nil)
                if target then
                    addon.UIFactory.SetFontColor(
                        label,
                        target.color,
                        addon.Theme.Colors.textMuted
                    )
                end
            end
            view:Show()
        else
            view.actionData = nil
            view.targetOverview = nil
            view:Hide()
        end
    end
end

local function getTargetGrid(targetCount, targetWidth, fontSize)
    targetCount = math.min(8, math.max(0, targetCount or 0))
    if targetCount == 0 then
        return 0, 1, 0
    end
    local columns = targetCount >= 3 and targetWidth >= 190 * fontSize / 12 and 2 or 1
    local rows = columns == 2
        and math.max(2, math.ceil(targetCount / 2))
        or math.min(4, targetCount)
    local visible = columns == 1 and math.min(4, targetCount) or targetCount
    return math.min(4, rows), columns, visible
end

local function updateTargetLabels(view, visibleCount)
    local targets = view.targetOverview or {}
    for index, label in ipairs(view.targetLabels) do
        local target = index <= visibleCount and targets[index] or nil
        local text = getTargetText(target)
        if target and index == visibleCount and #targets > visibleCount then
            text = text .. " " .. addon.L(
                "GAMEMASTER_MORE_TARGETS",
                #targets - visibleCount
            )
        end
        label:SetText(text)
        label:SetShown(target ~= nil)
    end
end

local function measureLabel(label, fontSize, text)
    if not label then return 0 end
    setFontSize(label, fontSize)
    local width = label:GetWidth()
    local previousText = text and label:GetText()
    if text then label:SetText(text) end
    label:SetWidth(0)
    local desired = math.ceil(label:GetStringWidth())
    label:SetWidth(width)
    if text then label:SetText(previousText) end
    return desired
end

 
function addon.GameMasterActionList.PlanColumns(lists, width, fontSize)
    width = math.max(1, tonumber(width) or 1)
    fontSize = math.max(8, math.min(24, tonumber(fontSize) or 12))
    local scale = fontSize / 12
    local actionWidth, desiredSpell, desiredTarget = 65 * scale, 90 * scale, 85 * scale
    local hasTargets = false
    for _, list in ipairs(lists or {}) do
        for index = 1, list.actionCount or 1 do
            local view = list.views[index]
            if view and view.actionData and view.actionData.spell then
                actionWidth = math.max(actionWidth, measureLabel(view.action, fontSize) + 5)
                desiredSpell = math.max(desiredSpell,
                    measureLabel(view.spell and view.spell.name, fontSize) + fontSize + 9)
                local count = #(view.targetOverview or {})
                hasTargets = hasTargets or count > 0
                for targetIndex = 1, math.min(8, count) do
                    local targetWidth = measureLabel(view.targetLabels and view.targetLabels[targetIndex], math.max(8, fontSize - 2),
                        getTargetText(view.targetOverview[targetIndex])) + 4
                    desiredTarget = math.max(desiredTarget, count >= 3 and targetWidth * 2 + 4 or targetWidth)
                end
            end
        end
    end
    actionWidth = clamp(actionWidth, 65 * scale, 190 * scale)
    desiredSpell = clamp(desiredSpell, 90 * scale, 260 * scale)
    desiredTarget = clamp(desiredTarget, 85 * scale, 300 * scale)
    local stackControls = width < actionWidth + 90 * scale + 4
    local horizontal = not stackControls
        and (not hasTargets or width >= actionWidth + 175 * scale + 8)
    local spellWidth, targetWidth = 0, 0
    if stackControls then
        actionWidth, spellWidth = width, width
        targetWidth = hasTargets and width or 0
    elseif horizontal and hasTargets then
        local available = width - actionWidth - 8
        spellWidth = clamp(available - desiredTarget, 90 * scale,
            math.min(desiredSpell, available - 85 * scale))
        targetWidth = available - spellWidth
    else
        spellWidth = math.min(desiredSpell, width - actionWidth - 4)
        targetWidth = hasTargets and width or 0
    end
    return {
        width = width, fontSize = fontSize,
        actionWidth = actionWidth, spellWidth = spellWidth, targetWidth = targetWidth,
        horizontal = horizontal, stackControls = stackControls,
    }
end

 
function addon.GameMasterActionList.CreateColumnPlanner(lists, fontSize)
    local budgets = {}
    return function(width)
        width = math.max(1, tonumber(width) or 1)
        if not budgets[width] then
            budgets[width] = addon.GameMasterActionList.PlanColumns(lists, width, fontSize)
        end
        return budgets[width]
    end
end

local function resolveColumns(list, width, fontSize, columns)
    if type(columns) == "table" and columns.width == width and columns.fontSize == fontSize then
        return columns
    end
    return addon.GameMasterActionList.PlanColumns({ list }, width, fontSize)
end

local function columnKey(columns)
    return table.concat({ columns.actionWidth, columns.spellWidth, columns.targetWidth,
        tostring(columns.horizontal), tostring(columns.stackControls) }, ":")
end

local function buildPlan(view, width, fontSize, columns)
    local lineHeight = fontSize + 4
    local targetCount = math.min(8, #(view.targetOverview or {}))
    local empty = not (view.actionData and view.actionData.spell)
    if empty then
        return {
            actionWidth = width,
            empty = true,
            height = lineHeight,
            horizontal = true,
            lineHeight = lineHeight,
            spellWidth = 1,
            stackControls = false,
            targetColumns = 1,
            targetCount = 0,
            targetHeight = 0,
            targetRows = 0,
            targetWidth = 1,
        }
    end
    local actionWidth, spellWidth, targetWidth = columns.actionWidth, columns.spellWidth, columns.targetWidth
    local horizontal, stackControls = columns.horizontal, columns.stackControls
    local targetRows, targetColumns, visibleTargetCount = getTargetGrid(
        targetCount,
        targetWidth,
        fontSize
    )
    local targetLineHeight = math.max(14, fontSize + 1)
    local targetHeight = targetRows * targetLineHeight
    return {
        actionWidth = actionWidth,
        height = horizontal
            and math.max(lineHeight, targetHeight)
            or (stackControls and lineHeight * 2 + 2 or lineHeight)
                + (targetHeight > 0 and targetHeight + 2 or 0),
        horizontal = horizontal,
        lineHeight = lineHeight,
        spellWidth = spellWidth,
        stackControls = stackControls,
        targetColumns = targetColumns,
        targetCount = visibleTargetCount or 0,
        targetHeight = targetHeight,
        targetLineHeight = targetLineHeight,
        targetRows = targetRows,
        targetWidth = targetWidth,
    }
end

function addon.GameMasterActionList.Measure(list, width, fontSize, columns)
    width = math.max(1, tonumber(width) or 1)
    fontSize = math.max(8, math.min(24, tonumber(fontSize) or 12))
    columns = resolveColumns(list, width, fontSize, columns)
    local plans = {}
    local total = 0
    local count = math.max(1, tonumber(list.actionCount) or 1)
    for index = 1, count do
        local plan = buildPlan(list.views[index], width, fontSize, columns)
        plans[index] = plan
        total = total + plan.height + (index > 1 and 3 or 0)
    end
    list.plans = plans
    list.measuredActionCount = count
    list.measuredFontSize = fontSize
    list.measuredTotal = total
    list.measuredWidth = width
    list.measuredColumnKey = columnKey(columns)
    return total
end

function addon.GameMasterActionList.Layout(list, width, fontSize, columns)
    width = math.max(1, tonumber(width) or 1)
    fontSize = math.max(8, math.min(24, tonumber(fontSize) or 12))
    columns = resolveColumns(list, width, fontSize, columns)
    local actionCount = math.max(1, tonumber(list.actionCount) or 1)
    local total = list.measuredWidth == width
        and list.measuredFontSize == fontSize
        and list.measuredActionCount == actionCount
        and list.measuredColumnKey == columnKey(columns)
        and list.measuredTotal
        or addon.GameMasterActionList.Measure(list, width, fontSize, columns)
    list:SetSize(width, math.max(1, total))
    local offset = 0
    for index = 1, actionCount do
        local view = list.views[index]
        local plan = list.plans[index]
        if index > 1 then
            offset = offset + 3
        end
        view:ClearAllPoints()
        view:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -offset)
        view:SetSize(width, plan.height)
        view.action:ClearAllPoints()
        view.spell:ClearAllPoints()
        view.targets:ClearAllPoints()
        view.action:SetSize(plan.actionWidth, plan.lineHeight)
        view.action:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
        view.spell:SetShown(not plan.empty)
        view.spell:SetSize(plan.spellWidth, plan.lineHeight)
        if plan.stackControls then
            view.spell:SetPoint(
                "TOPLEFT", view, "TOPLEFT", 0, -(plan.lineHeight + 2)
            )
        else
            view.spell:SetPoint("LEFT", view.action, "RIGHT", 4, 0)
        end
        local iconSize = math.min(math.max(12, plan.lineHeight - 4), math.max(1, plan.spellWidth - 4))
        view.spell.icon:SetSize(iconSize, iconSize)
        local showIcon = not plan.empty and list.showIcons ~= false and plan.spellWidth >= iconSize + 12
        view.spell.icon:SetShown(showIcon)
        addon.UIFactory.ApplySpellIconEffectFrame(
            view.spell.icon,
            view.actionData and view.actionData.spell,
            showIcon
        )
        view.spell.name:ClearAllPoints()
        view.spell.name:SetPoint("LEFT", view.spell, "LEFT", showIcon and iconSize + 6 or 4, 0)
        view.spell.name:SetPoint("RIGHT", view.spell, "RIGHT", -3, 0)
        view.spell.name:SetShown(plan.spellWidth > 7)
        if plan.horizontal then
            view.targets:SetPoint("TOPLEFT", view.spell, "TOPRIGHT", 4, 0)
        else
            view.targets:SetPoint(
                "TOPLEFT",
                view,
                "TOPLEFT",
                0,
                -((plan.stackControls and plan.lineHeight * 2 + 2
                    or plan.lineHeight) + 2)
            )
        end
        view.targets:SetSize(
            math.max(1, plan.targetWidth),
            math.max(1, plan.targetHeight)
        )
        view.targets:SetShown(plan.targetCount > 0)
        local cellWidth = math.max(
            1,
            math.floor((plan.targetWidth - ((plan.targetColumns - 1) * 4))
                / plan.targetColumns)
        )
        updateTargetLabels(view, plan.targetCount)
        for targetIndex, label in ipairs(view.targetLabels) do
            label:ClearAllPoints()
            if targetIndex <= plan.targetCount then
                local column = math.floor((targetIndex - 1) / plan.targetRows)
                local row = (targetIndex - 1) % plan.targetRows
                label:SetSize(cellWidth, plan.targetLineHeight)
                label:SetPoint(
                    "TOPLEFT",
                    view.targets,
                    "TOPLEFT",
                    column * (cellWidth + 4),
                    -(row * plan.targetLineHeight)
                )
                label:SetShown(true)
            else
                label:Hide()
            end
            setFontSize(label, math.max(8, fontSize - 2))
        end
        setFontSize(view.action, fontSize)
        setFontSize(view.spell.name, fontSize)
        offset = offset + plan.height
    end
    return total
end

function addon.GameMasterActionList.ApplyStyle(list, style, showBorder)
    local border = showBorder and style.rowBorder or { 0, 0, 0, 0 }
    for _, view in ipairs(list.views) do
        view.spell:SetBackdropColor(
            style.rowBackgroundOdd[1],
            style.rowBackgroundOdd[2],
            style.rowBackgroundOdd[3],
            style.rowBackgroundOdd[4]
        )
        view.spell:SetBackdropBorderColor(
            border[1], border[2], border[3], border[4]
        )
    end
end
