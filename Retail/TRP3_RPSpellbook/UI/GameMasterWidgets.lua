local _, addon = ...

addon.GameMasterWidgets = {}

function addon.GameMasterWidgets.CreateSelector(parent, width, placeholder)
    local theme = addon.Theme
    local selector = CreateFrame(
        "Frame",
        nil,
        parent,
        "TRP3_DropdownButtonTemplate"
    )
    selector:SetSize(width, theme.Sizes.inputHeight)
    selector.options = {}
    selector.value = nil
    selector.placeholder = placeholder or addon.L("NONE")
    local button = selector.Button
    selector.selectedIcon = button:CreateTexture(nil, "ARTWORK")
    selector.selectedIcon:SetSize(16, 16)
    selector.selectedIcon:Hide()

    local selectorText = button.Text

    local function applySelectedOption(option)
        if not selectorText then
            return
        end
        selectorText:ClearAllPoints()
        selectorText:SetPoint("RIGHT", selector, "RIGHT", -22, 0)
        selectorText:SetJustifyH("LEFT")
        selectorText:SetWordWrap(false)
        local creatureID = option and option.creatureID
        if option and (option.icon or creatureID) then
            selector.selectedIcon:ClearAllPoints()
            selector.selectedIcon:SetPoint("LEFT", selector, "LEFT", 7, 0)
            addon.UIFactory.SetIconTexture(
                selector.selectedIcon,
                option.icon,
                creatureID and "Interface\\CharacterFrame\\TemporaryPortrait-Monster" or addon.Constants.DEFAULT_BOOK_ICON
            )
            selector.selectedIcon:Show()
            selectorText:SetPoint(
                "LEFT", selector.selectedIcon, "RIGHT", 4, 0
            )
        else
            selector.selectedIcon:Hide()
            selectorText:SetPoint("LEFT", selector, "LEFT", 8, 0)
        end
        addon.UIFactory.SetNPCPortrait(button, selector.selectedIcon, creatureID, option and option.icon, 16)
        addon.UIFactory.SetFontColor(
            selectorText,
            option and option.color or nil,
            theme.Colors.text
        )
    end

    local function getMenuLabel(option)
        local label = option.label
        if type(option.color) == "string"
            and option.color:match("^%x%x%x%x%x%x$")
        then
            label = string.format("|cff%s%s|r", option.color, label)
        end
        local texture = option.icon
            and addon.TRP3Bridge.ResolveIconTexture(option.icon)
            or (option.creatureID and "Interface\\CharacterFrame\\TemporaryPortrait-Monster")
        return texture
            and string.format("|T%s:16:16|t %s", tostring(texture), label)
            or label
    end

    function selector:SetValue(value, silent)
        local label = self.placeholder
        local selected
        local selectedOption
        for _, option in ipairs(self.options) do
            if option.value == value then
                label = option.label
                selected = option.value
                selectedOption = option
                break
            end
        end
        self.value = selected
         
         
        self:OverrideText(label)
        applySelectedOption(selectedOption)
        if not silent and type(self.onValueChanged) == "function" then
            self.onValueChanged(selected)
        end
    end

    function selector:GetValue()
        return self.value
    end

    function selector:SetOptions(options, preferredValue)
        self:CloseMenu()
        self.options = type(options) == "table" and options or {}
        local selected
        for _, option in ipairs(self.options) do
            if option.value == preferredValue then
                selected = preferredValue
                break
            end
        end
        if selected == nil and self.options[1] then
            selected = self.options[1].value
        end
        self:SetEnabled(#self.options > 0)
        self:SetValue(selected, true)
        self:GenerateMenu()
    end

    function selector:SetOnValueChanged(callback)
        self.onValueChanged = callback
    end

    function selector:ToggleOptions()
        self:ToggleMenu()
    end

     
     
     
    hooksecurefunc(button, "OnMenuOpened", function(_, menu)
        menu:SetFrameStrata("TOOLTIP")
    end)
    selector:SetupMenu(function(_, rootDescription)
        local maximumWidth = math.max(1, math.min(480, UIParent:GetWidth() - 40))
        rootDescription:SetMinimumWidth(math.min(selector:GetWidth(), maximumWidth))
        rootDescription:SetMaximumWidth(maximumWidth)
        rootDescription:SetScrollMode(math.max(1, math.min(360, UIParent:GetHeight() - 40)))
        for _, option in ipairs(selector.options) do
            local current = option
            local entry = rootDescription:CreateRadio(
                getMenuLabel(current),
                function(value)
                    return selector.value == value
                end,
                function(value)
                    selector:SetValue(value)
                end,
                current.value
            )
            if entry and entry.AddInitializer then
                entry:AddInitializer(function(frame)
                     
                    addon.UIFactory.SetNPCPortrait(frame, frame.fontString, current.creatureID, current.icon, 16)
                end)
            end
        end
    end)
    selector:HookScript("OnHide", function()
        selector:CloseMenu()
    end)
    button:HookScript("OnDisable", function()
        selector:CloseMenu()
    end)
    selector:SetValue(nil, true)
    selector:SetEnabled(false)
    return selector
end

function addon.GameMasterWidgets.SetFontSize(fontString, size, offset)
    if not fontString or type(fontString.GetFont) ~= "function" then
        return
    end
    local font, _, flags = fontString:GetFont()
    if type(font) == "string" and font ~= "" then
        fontString:SetFont(
            font,
            math.max(8, size + (offset or 0)),
            flags
        )
    end
end

function addon.GameMasterWidgets.GetContentMetrics(moduleID, frame, fontSize, options, style)
    local requested = fontSize or addon.GameMasterSettings.GetWindowFontSize(moduleID, 12)
    local metrics
    if fontSize then
        metrics = addon.GameMasterLayout.GetAdaptiveMetrics(
            moduleID, frame:GetWidth(), frame:GetHeight(), requested, options, style
        )
    else
        metrics = addon.GameMasterSettings.GetWindowMetrics(moduleID, frame, requested)
    end
    metrics = metrics or {}
     
    metrics.fontSize = math.min(requested, metrics.fontSize or requested)
    metrics.padding = 6
    metrics.iconSize = math.max(14, metrics.fontSize + 5)
    return metrics
end

function addon.GameMasterWidgets.MeasureTextWidth(label, text, fontSize)
    addon.GameMasterWidgets.SetFontSize(label, fontSize)
    label:ClearAllPoints()
    label:SetSize(0, 0)
    label:SetWordWrap(false)
    label:SetText(text or "")
    return math.ceil(label:GetStringWidth())
end

function addon.GameMasterWidgets.MeasureText(label, text, width, fontSize, wrap)
    addon.GameMasterWidgets.SetFontSize(label, fontSize)
    label:ClearAllPoints()
    label:SetWidth(math.max(1, width))
    label:SetHeight(0)
    label:SetWordWrap(wrap ~= false)
    label:SetText(text or "")
    local measured = type(label.GetStringHeight) == "function"
        and label:GetStringHeight() or fontSize + 3
    return math.ceil(math.max(fontSize + 3, tonumber(measured) or 0))
end

function addon.GameMasterWidgets.ClampScroll(scroll, contentHeight)
    if type(scroll.GetVerticalScroll) ~= "function" then return end
    local maximum = math.max(0, contentHeight - scroll:GetHeight())
    local previous = scroll:GetVerticalScroll() or 0
    local value = math.max(0, math.min(maximum, previous))
    if value ~= previous then scroll:SetVerticalScroll(value) end
end

function addon.GameMasterWidgets.CreateScrollViewport(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetClipsChildren(true)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local maximum = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
        local step = math.max(18, math.min(48, self:GetHeight() / 4))
        self:SetVerticalScroll(math.max(0, math.min(maximum,
            self:GetVerticalScroll() - delta * step)))
    end)
    scroll:SetScript("OnScrollRangeChanged", function(self)
        local child = self:GetScrollChild()
        addon.GameMasterWidgets.ClampScroll(self, child and child:GetHeight() or 0)
    end)
    return scroll
end

function addon.GameMasterWidgets.GetMeasuredGrid(width, height, count, fontSize, minWidth, maxColumns, measure)
    width, height = math.max(1, tonumber(width) or 1), math.max(1, tonumber(height) or 1)
    count = math.min(320, math.max(0, math.floor(tonumber(count) or 0)))
    minWidth = math.max(1, tonumber(minWidth) or width)
    maxColumns = math.min(5, math.max(1, math.floor(tonumber(maxColumns) or 1)))
    local gap = 3
    local maximum = math.max(1, math.min(
        maxColumns, math.max(1, count), math.floor((width + gap) / (minWidth + gap))
    ))
    local best
    for columns = 1, maximum do
        local cardWidth = math.floor((width - (columns - 1) * gap) / columns)
        local heights = {}
        for index = 1, count do
            heights[index] = math.max(1, math.ceil(measure(index, cardWidth, columns)))
        end
        local packed = addon.GameMasterLayout.GetVariableRowLayout(columns, heights, gap)
        local capacity = 0
        for _, position in ipairs(packed.positions) do
            if position.offset + position.height <= height then capacity = capacity + 1 end
        end
        local candidate = {
            columns = columns, cardWidth = cardWidth, fontSize = fontSize, gap = gap,
            capacity = capacity, positions = packed.positions,
            contentHeight = packed.contentHeight, rowHeights = heights,
        }
         
        if not best or candidate.capacity > best.capacity then best = candidate end
        if capacity >= count then break end
    end
    return best
end

function addon.GameMasterWidgets.CreateSection(parent, background)
    local section = addon.UIFactory.CreateBackdropFrame(
        parent,
        background or addon.Theme.Colors.parchmentDark,
        addon.Theme.Colors.border
    )
    if type(section.SetClipsChildren) == "function" then
        section:SetClipsChildren(true)
    end
    return section
end

function addon.GameMasterWidgets.SetEnabled(button, enabled)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

function addon.GameMasterWidgets.CreateEncounterOptions(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetHeight(178)
    local function check(labelKey, y)
        local control = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        control:SetSize(26, 26)
        control:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
        local label = addon.UIFactory.CreateLabel(panel, addon.Theme.Fonts.body,
            addon.L(labelKey), addon.Theme.Colors.text)
        label:SetPoint("LEFT", control, "RIGHT", 3, 0)
        label:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
        label:SetWordWrap(false)
        return control
    end
    panel.participates = check("GAMEMASTER_GM_PARTICIPATES", 0)
    local nameLabel = addon.UIFactory.CreateLabel(panel, addon.Theme.Fonts.small,
        addon.L("GAMEMASTER_NARRATOR_NAME"), addon.Theme.Colors.textMuted)
    nameLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -34)
    panel.narrator = addon.UIFactory.CreateEditBox(panel, false)
    panel.narrator:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -52)
    panel.narrator:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
    panel.narrator:SetMaxLetters(addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH)
    panel.enemies = check("GAMEMASTER_ENEMY_PHASES", 80)
    panel.deferEnemyActions = check("GAMEMASTER_DEFER_ENEMY_ACTIONS", 112)
    panel.lockedHint = addon.UIFactory.CreateLabel(panel, addon.Theme.Fonts.small,
        addon.L("GAMEMASTER_ENCOUNTER_OPTIONS_LOCKED"), addon.Theme.Colors.textMuted)
    panel.lockedHint:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -151)
    panel.lockedHint:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
    panel.lockedHint:SetWordWrap(true)

    function panel:UpdateEnabled()
        self.participates:SetEnabled(not self.locked)
        self.enemies:SetEnabled(not self.locked)
        self.deferEnemyActions:SetEnabled(not self.locked and self.enemies:GetChecked() == true)
        local editable = not self.locked and not self.participates:GetChecked()
        self.narrator:SetEnabled(editable)
        self.narrator:SetAlpha(editable and 1 or 0.5)
        if not editable then self.narrator:ClearFocus() end
        self.lockedHint:SetShown(self.locked)
    end
    function panel:SetOptions(options, locked)
        options = type(options) == "table" and options or {}
        self.locked = locked == true
        self.participates:SetChecked(options.gmParticipates ~= false)
        self.enemies:SetChecked(options.enemyPhases ~= false)
        self.deferEnemyActions:SetChecked(options.deferEnemyActions ~= false)
        self.narrator:SetText(options.narratorName or addon.L("GAMEMASTER_NARRATOR_DEFAULT"))
        self:UpdateEnabled()
    end
    function panel:GetOptions()
        return {
            gmParticipates = self.participates:GetChecked() == true,
            narratorName = self.narrator:GetText(),
            enemyPhases = self.enemies:GetChecked() == true,
            deferEnemyActions = self.deferEnemyActions:GetChecked() == true,
        }
    end
    panel.participates:SetScript("OnClick", function() panel:UpdateEnabled() end)
    panel.enemies:SetScript("OnClick", function() panel:UpdateEnabled() end)
    panel:SetOptions()
    return panel
end
