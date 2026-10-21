local _, addon = ...

addon.SpellEditorWindow = {}

local constants = addon.Constants
local dialog
local state = {
    applyingTimePreset = false,
    effects = {},
    kindDrafts = {},
    timeSelections = {
        castTime = {},
        cooldown = {},
        duration = {},
    },
    timeModes = {},
}

local function colorComponent(color, index, fallback)
    local value = type(color) == "table" and tonumber(color[index]) or nil
    if value == nil then
        return fallback
    end
    return math.max(0, math.min(1, value))
end

local function setButtonBackground(button, color, accent, blend)
    local amount = tonumber(blend) or 0
    local red = colorComponent(color, 1, 0.08)
    local green = colorComponent(color, 2, 0.06)
    local blue = colorComponent(color, 3, 0.04)
    button:SetBackdropColor(
        red + (colorComponent(accent, 1, red) - red) * amount,
        green + (colorComponent(accent, 2, green) - green) * amount,
        blue + (colorComponent(accent, 3, blue) - blue) * amount,
        0.98
    )
end

local function getPrimaryEffectMode(effects)
    if type(effects) == "table" and effects.debuff == true then
        return "debuff"
    end
    if type(effects) == "table" and effects.buff == true then
        return "buff"
    end
    return nil
end

function addon.SpellEditorWindow.GetNextPrimaryEffectMode(mode)
    if mode == "buff" then return "debuff" end
    if mode == "debuff" then return nil end
    return "buff"
end

local function getStorage()
    return state.storage or addon.Database
end

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$")
end

local function isStructuredTag(key)
    return key == constants.MAGIC_TAG_ENABLED
        or key == constants.MAGIC_TAG_TYPE
        or key == constants.MAGIC_TAG_SCHOOL
        or key == constants.SPELL_TAG_KIND
        or key == constants.SPELL_TAG_DAMAGE_TYPE
        or key == constants.SPELL_TAG_CAST_ROUNDS
        or key == "Magisch"
        or key == "Magieart"
        or key == "Magieschule"
end

local function copyLegacyTags(tags)
    local legacy = {}
    if type(tags) == "table" then
        for key, value in pairs(tags) do
            if not isStructuredTag(key) then
                legacy[key] = value
            end
        end
    end
    return legacy
end

local function getSpellKind(spell)
    local tags = type(spell) == "table" and spell.tags or {}
    local explicit = tags[constants.SPELL_TAG_KIND]
    if explicit == constants.SPELL_KIND_MAGIC
        or explicit == constants.SPELL_KIND_ABILITY
    then
        return explicit
    end
    if tags[constants.MAGIC_TAG_ENABLED] == "true"
        or tags.Magisch == "Ja"
        or tags.Magisch == "true"
    then
        return constants.SPELL_KIND_MAGIC
    end
    return constants.SPELL_KIND_ABILITY
end

local function getAdaptiveKind()
    local spellbook = getStorage().GetActiveSpellbook()
    local magicCount = 0
    local abilityCount = 0
    for _, spell in pairs(spellbook and spellbook.spells or {}) do
        if getSpellKind(spell) == constants.SPELL_KIND_MAGIC then
            magicCount = magicCount + 1
        else
            abilityCount = abilityCount + 1
        end
    end
    if abilityCount > magicCount then
        return constants.SPELL_KIND_ABILITY
    end
    return constants.SPELL_KIND_MAGIC
end

local function setError(message)
    dialog.errorLabel:SetText(message or "")
end

local function ownsBook(storage, original)
    local book = storage.GetActiveSpellbook()
    if not book or not original then return false end
     
    if storage == addon.Database then return book == original end
    return book.id ~= nil and book.id == original.id and book.profileKey == original.profileKey
end

local function checkBook()
    if ownsBook(getStorage(), state.book) then return true end
    setError(addon.L("EDITOR_PROFILE_CHANGED"))
    return false
end

local function draftCallback(callback)
    local token, storage, book = state.token, getStorage(), state.book
    return function(...)
        if state.token == token and ownsBook(storage, book) then
            return callback(...)
        end
    end
end

local function showDialog()
    dialog:Show()
    addon.UIFactory.BringToFront(dialog)
end

local function setSelectedIcon(icon)
    state.icon = icon
    addon.UIFactory.SetIconTexture(
        dialog.iconButton.iconTexture,
        icon,
        constants.DEFAULT_BOOK_ICON
    )
    if dialog.fields then
        local tags = {}
        if state.kind == constants.SPELL_KIND_MAGIC then
            tags[constants.SPELL_TAG_KIND] = constants.SPELL_KIND_MAGIC
            tags[constants.MAGIC_TAG_TYPE] = trim(dialog.fields.magicType:GetText())
        end
        addon.UIFactory.ApplySpellIconEffectFrame(
            dialog.iconButton.iconTexture,
            { effects = state.effects, tags = tags },
            true
        )
    end
end

local function setSelectedNameColor(color)
    state.nameColor = color
    addon.UIFactory.SetColorButton(dialog.colorButton, color)
    addon.UIFactory.SetFontColor(
        dialog.fields.name,
        color,
        addon.Theme.Colors.text
    )
end

local function getSpellbook()
    return getStorage().GetActiveSpellbook()
end

local function getSelectedTabIndex(spellbook)
    for index, tabID in ipairs(spellbook.tabOrder) do
        if tabID == state.selectedTabID then
            return index
        end
    end
    return 1
end

local function refreshSelectedTab()
    local spellbook = getSpellbook()
    if not spellbook or #spellbook.tabOrder == 0 then
        state.selectedTabID = nil
        dialog.tabName:SetText(addon.L("NO_TAB_AVAILABLE"))
        return
    end
    if not spellbook.tabs[state.selectedTabID] then
        state.selectedTabID = spellbook.tabOrder[1]
    end
    local tab = spellbook.tabs[state.selectedTabID]
    dialog.tabName:SetText(tab and tab.name or addon.L("UNKNOWN"))
end

local function cycleTab(direction)
    if not checkBook() then return end
    local spellbook = getSpellbook()
    if not spellbook or #spellbook.tabOrder == 0 then
        return
    end
    local index = getSelectedTabIndex(spellbook) + direction
    if index < 1 then
        index = #spellbook.tabOrder
    elseif index > #spellbook.tabOrder then
        index = 1
    end
    state.selectedTabID = spellbook.tabOrder[index]
    refreshSelectedTab()
end

local function createTypeButton(parent, text)
    local theme = addon.Theme
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(theme.Sizes.buttonHeight)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button.label = addon.UIFactory.CreateLabel(
        button,
        theme.Fonts.body,
        text,
        theme.Colors.text
    )
    button.label:SetPoint("CENTER")
    button:SetScript("OnEnter", function(self)
        if not self.active then
            local editorTheme = self.editorTheme or {}
            setButtonBackground(
                self,
                editorTheme.background,
                editorTheme.accent,
                0.22
            )
        end
    end)
    button:SetScript("OnLeave", function(self)
        if not self.active then
            local editorTheme = self.editorTheme or {}
            setButtonBackground(
                self,
                editorTheme.background,
                editorTheme.accent,
                0.08
            )
        end
    end)
    return button
end

local function setTypeButtonActive(button, active)
    local theme = addon.Theme
    local editorTheme = button.editorTheme or {}
    local accent = editorTheme.accent or theme.Colors.gold
    local border = editorTheme.border or theme.Colors.border
    local text = editorTheme.text or theme.Colors.text
    button.active = active
    if active then
        setButtonBackground(button, editorTheme.background, accent, 0.28)
        button:SetBackdropBorderColor(
            colorComponent(accent, 1, 1),
            colorComponent(accent, 2, 0.72),
            colorComponent(accent, 3, 0.08),
            colorComponent(accent, 4, 1)
        )
        button.label:SetTextColor(
            colorComponent(accent, 1, 1),
            colorComponent(accent, 2, 0.82),
            colorComponent(accent, 3, 0),
            1
        )
    else
        setButtonBackground(button, editorTheme.background, accent, 0.08)
        button:SetBackdropBorderColor(
            colorComponent(border, 1, theme.Colors.border[1]),
            colorComponent(border, 2, theme.Colors.border[2]),
            colorComponent(border, 3, theme.Colors.border[3]),
            colorComponent(border, 4, theme.Colors.border[4] or 1)
        )
        button.label:SetTextColor(
            colorComponent(text, 1, theme.Colors.text[1]),
            colorComponent(text, 2, theme.Colors.text[2]),
            colorComponent(text, 3, theme.Colors.text[3]),
            colorComponent(text, 4, theme.Colors.text[4] or 1)
        )
    end
end

local function refreshEditorTheme()
    local themes = addon.SpellCreationThemes
    if not dialog or not dialog.fields or not themes
        or type(themes.Apply) ~= "function"
    then
        return
    end
    local selectedTheme = addon.SpellCreationSettings.GetEditorTheme()
    local spec, resolvedID = themes.Apply(
        dialog,
        selectedTheme,
        state.kind,
        trim(dialog.fields.magicType:GetText()),
        trim(dialog.fields.damageType:GetText())
    )
    if type(spec) ~= "table" then
        return
    end
    dialog.resolvedEditorTheme = resolvedID
    dialog.magicButton.editorTheme = spec
    dialog.abilityButton.editorTheme = spec
    setTypeButtonActive(
        dialog.magicButton,
        state.kind == constants.SPELL_KIND_MAGIC
    )
    setTypeButtonActive(
        dialog.abilityButton,
        state.kind == constants.SPELL_KIND_ABILITY
    )
end

local function createEffectToggle(parent, labelKey)
    local theme = addon.Theme
    local button = CreateFrame(
        "CheckButton",
        nil,
        parent,
        "UICheckButtonTemplate"
    )
    button:SetSize(24, 24)
    button.label = addon.UIFactory.CreateLabel(
        button,
        theme.Fonts.body,
        addon.L(labelKey),
        theme.Colors.text
    )
    button.label:SetPoint("LEFT", button, "RIGHT", 2, 0)
    button.label:SetJustifyH("LEFT")
    button.debuffMark = addon.UIFactory.CreateLabel(
        button,
        theme.Fonts.body,
        "X",
        theme.Colors.danger
    )
    button.debuffMark:SetPoint("CENTER", button, "CENTER", -1, 0)
    button.debuffMark:Hide()
    button:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 0.82, 0, 1)
    end)
    button:SetScript("OnLeave", function(self)
        if type(self.refreshAppearance) == "function" then
            self:refreshAppearance()
        else
            self.label:SetTextColor(
                theme.Colors.text[1],
                theme.Colors.text[2],
                theme.Colors.text[3],
                theme.Colors.text[4] or 1
            )
        end
    end)
    return button
end

local function setPrimaryEffectAppearance(button, mode)
    local theme = addon.Theme
    local checked = mode == "buff" or mode == "debuff"
    button:SetChecked(checked)
    button.debuffMark:SetShown(mode == "debuff")
    button.label:SetText(addon.L(mode == "debuff" and "EFFECT_DEBUFF" or "EFFECT_BUFF"))
    local texture = type(button.GetCheckedTexture) == "function"
        and button:GetCheckedTexture() or nil
    if texture then
        if type(texture.SetAlpha) == "function" then
            texture:SetAlpha(mode == "debuff" and 0 or 1)
        end
        if type(texture.SetVertexColor) == "function" then
            if mode == "buff" then
                texture:SetVertexColor(0.25, 1, 0.38, 1)
            else
                texture:SetVertexColor(1, 1, 1, 1)
            end
        end
    end
    local color = mode == "buff" and { 0.38, 1, 0.48, 1 }
        or mode == "debuff" and { 1, 0.38, 0.30, 1 }
        or theme.Colors.text
    button.label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end
local function createLabel(parent, labelText, topOffset)
    local theme = addon.Theme
    local label = addon.UIFactory.CreateLabel(
        parent,
        theme.Fonts.body,
        labelText,
        theme.Colors.textMuted
    )
    label:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        theme.Spacing.lg,
        topOffset
    )
    label:SetWidth(theme.Sizes.editorLabelWidth)
    label:SetJustifyH("LEFT")
    return label
end

local function createPresetField(parent, labelText, topOffset, withAmount)
    local theme = addon.Theme
    local label = createLabel(parent, labelText, topOffset)
    local left = theme.Spacing.lg + theme.Sizes.editorLabelWidth
    local arrowWidth = theme.Sizes.inputHeight
    local amountWidth = withAmount and 54 or 0
    local gap = withAmount and theme.Spacing.xs or 0

    local amount
    if withAmount then
        amount = addon.UIFactory.CreateEditBox(parent, false)
        amount:SetPoint("TOPLEFT", parent, "TOPLEFT", left, topOffset + theme.Spacing.xs)
        amount:SetWidth(amountWidth)
        amount:SetNumeric(true)
        amount:SetMaxLetters(5)
    end

    local field = addon.UIFactory.CreateEditBox(parent, false)
    field:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        left + amountWidth + gap,
        topOffset + theme.Spacing.xs
    )
    field:SetWidth(theme.Sizes.editorInputWidth - amountWidth - gap - arrowWidth)

    local dropdown = CreateFrame(
        "Frame",
        nil,
        parent,
        "TRP3_DropdownButtonTemplate"
    )
    dropdown:SetSize(arrowWidth, theme.Sizes.inputHeight)
    dropdown:SetPoint("LEFT", field, "RIGHT", 0, 0)
    dropdown:SetText("")
    return {
        amount = amount,
        dropdown = dropdown,
        field = field,
        label = label,
    }
end

local function attachFieldCursor(field)
    local cursor, blink, cursorX, cursorY, cursorHeight

    local function hideCursor()
        if blink then blink:Stop() end
        if cursor then cursor:Hide() end
    end

    local function showCursor()
        if not field:HasFocus() then return end
        if not cursorX then
            if field:GetText() ~= "" then return end
            local left, _, top = field:GetTextInsets()
            local _, fontHeight = field:GetFont()
            cursorX = left
            cursorHeight = fontHeight
            cursorY = field:IsMultiLine() and -top
                or -(field:GetHeight() - fontHeight) / 2
        end
        if not cursor then
            cursor = field:CreateTexture(nil, "OVERLAY", nil, 7)
            cursor:SetColorTexture(1, 0.92, 0.6, 1)
            blink = cursor:CreateAnimationGroup()
            blink:SetLooping("BOUNCE")
            local fade = blink:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0.25)
            fade:SetDuration(0.5)
        end
        blink:Stop()
        cursor:SetAlpha(1)
        cursor:ClearAllPoints()
        cursor:SetPoint("TOPLEFT", field, "TOPLEFT", cursorX, cursorY)
        cursor:SetSize(2, cursorHeight)
        cursor:Show()
        blink:Play()
    end

    field:HookScript("OnCursorChanged", function(_, x, y, width, height)
        cursorX, cursorY, cursorHeight = x, y, math.max(1, height)
        showCursor()
    end)
    field:HookScript("OnEditFocusGained", showCursor)
    field:HookScript("OnEditFocusLost", hideCursor)
    field:HookScript("OnHide", hideCursor)
    field:HookScript("OnShow", showCursor)
end

local function attachFieldPlaceholder(field)
    local theme = addon.Theme
    local placeholder = addon.UIFactory.CreateLabel(
        field,
        theme.Fonts.body,
        "",
        theme.Colors.textMuted
    )
    placeholder:SetPoint("LEFT", field, "LEFT", theme.Spacing.sm, 0)
    placeholder:SetPoint("RIGHT", field, "RIGHT", -theme.Spacing.sm, 0)
    placeholder:SetJustifyH("LEFT")
    if placeholder.SetWordWrap then placeholder:SetWordWrap(false) end
    if placeholder.SetMaxLines then placeholder:SetMaxLines(1) end
    placeholder:SetHeight(theme.Sizes.inputHeight)
    local function refresh()
        placeholder:SetShown(not field:HasFocus() and field:GetText() == "")
    end
    field:HookScript("OnEditFocusGained", refresh)
    field:HookScript("OnEditFocusLost", refresh)
    field:HookScript("OnTextChanged", refresh)
    field.presetPlaceholder = placeholder
    field.refreshPresetPlaceholder = refresh
end

local function updateTimePlaceholders()
    local suffix = addon.SpellCreationSettings.GetTimeMode() == "time"
        and "TIME"
        or "ROUNDS"
    local fields = {
        dialog.fields.castTime,
        dialog.fields.cooldown,
        dialog.fields.duration,
    }
    for _, field in ipairs(fields) do
        if field then
            field.presetPlaceholder:SetText(
                addon.L("TIME_FIELD_PLACEHOLDER_" .. suffix)
            )
            field.refreshPresetPlaceholder()
        end
    end
end

local function createDescriptionField(parent, topOffset)
    local theme = addon.Theme
    local label = createLabel(
        parent,
        addon.L("FIELD_DESCRIPTION"),
        topOffset
    )
    local field, container = addon.UIFactory.CreateTextArea(parent)
    container:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        theme.Spacing.lg + theme.Sizes.editorLabelWidth,
        topOffset + theme.Spacing.xs
    )
    container:SetWidth(theme.Sizes.editorInputWidth)

    local placeholder = addon.UIFactory.CreateLabel(
        container,
        theme.Fonts.body,
        addon.L("DESCRIPTION_PLACEHOLDER"),
        theme.Colors.textMuted
    )
    placeholder:SetPoint(
        "TOPLEFT",
        container,
        "TOPLEFT",
        theme.Spacing.md,
        -theme.Spacing.md
    )
    placeholder:SetPoint(
        "RIGHT",
        container,
        "RIGHT",
        -theme.Spacing.xl,
        0
    )
    placeholder:SetJustifyH("LEFT")
    placeholder:SetJustifyV("TOP")

    local function updateFocus()
        local focused = field:HasFocus()
        placeholder:SetShown(not focused and field:GetText() == "")
        local color = focused and theme.Colors.gold or theme.Colors.border
        container:SetBackdropBorderColor(
            color[1],
            color[2],
            color[3],
            color[4] or 1
        )
    end
    field:SetTextColor(1, 1, 1, 1)
    field:HookScript("OnEditFocusGained", updateFocus)
    field:HookScript("OnEditFocusLost", updateFocus)
    field:HookScript("OnTextChanged", updateFocus)
    container:HookScript("OnShow", updateFocus)
    field.placeholder = placeholder
    return field, label
end

local function setSimplePresetMenu(control, provider, onSelected, submenuProvider)
    control.dropdown:SetupMenu(function(_, rootDescription)
        for _, item in ipairs(provider()) do
            local parent = item.children and rootDescription:CreateButton(item.label) or rootDescription
            for _, entry in ipairs(item.children or { item }) do
                local current = entry
                local label = current.color and "|cff" .. current.color .. current.label .. "|r" or current.label
                parent:CreateButton(label, draftCallback(function()
                    control.field:SetText(current.label)
                    if onSelected then onSelected(current) end
                end))
            end
        end
        if submenuProvider
            and addon.SpellCreationSettings.ShouldShowMagicSubtypes()
        then
            local submenu = rootDescription:CreateButton(
                addon.L("PRESET_MAGIC_SUBTYPES")
            )
            for _, item in ipairs(submenuProvider()) do
                local current = item
                submenu:CreateButton(current.label, draftCallback(function()
                    control.field:SetText(current.label)
                    if onSelected then
                        onSelected(current)
                    end
                end))
            end
        end
    end)
end

local function selectionCount(selected)
    local count = 0
    for _, enabled in pairs(selected or {}) do
        if enabled then
            count = count + 1
        end
    end
    return count
end

local function setTimePresetMenu(control, selectionKey, provider, valueKind)
    control.field:HookScript("OnTextChanged", function()
        if not state.applyingTimePreset then
            state.timeSelections = state.timeSelections or {}
            state.timeSelections[selectionKey] = {}
        end
    end)
    control.dropdown:SetupMenu(function(_, rootDescription)
        state.timeModes = state.timeModes or {}
        local timeMode = state.timeModes[selectionKey]
            or addon.SpellCreationSettings.GetTimeMode()
        local options = provider(timeMode)
        state.timeSelections = state.timeSelections or {}
        local selected = state.timeSelections[selectionKey] or {}
        state.timeSelections[selectionKey] = selected
        for _, item in ipairs(options) do
            local current = item
            local entry = rootDescription:CreateCheckbox(
                current.label,
                function()
                    return selected[current.value] == true
                end,
                draftCallback(function()
                    if selected[current.value] then
                        selected[current.value] = nil
                    elseif current.exclusive then
                        wipe(selected)
                        selected[current.value] = true
                    elseif selectionCount(selected) < 2 then
                        for _, existing in ipairs(options) do
                            if existing.exclusive then
                                selected[existing.value] = nil
                            end
                        end
                        selected[current.value] = true
                    end
                    state.applyingTimePreset = true
                    control.field:SetText(
                        addon.SpellCreationPresets.FormatTimeSelection(
                            options,
                            selected,
                            timeMode,
                            valueKind
                        )
                    )
                    state.applyingTimePreset = false
                end)
            )
            entry:SetEnabled(function()
                return selected[current.value] == true
                    or current.exclusive == true
                    or selectionCount(selected) < 2
            end)
        end
    end)
end

local function restoreTimeSelection(selectionKey, text, provider, valueKind)
    state.timeModes = state.timeModes or {}
    local timeMode = state.timeModes[selectionKey]
        or addon.SpellCreationSettings.GetTimeMode()
    state.timeSelections[selectionKey] =
        addon.SpellCreationPresets.MatchTimeSelection(
            provider(timeMode),
            text,
            timeMode,
            valueKind
        )
end

local function snapshotResource()
    if not dialog or not state.kind then
        return
    end
    state.kindDrafts[state.kind] = {
        amount = dialog.resourceControl.amount:GetText(),
        amountEnabled = dialog.resourceControl.amount:IsEnabled(),
        resource = dialog.resourceControl.field:GetText(),
    }
end

local function setControlShown(control, shown)
    control.field:SetShown(shown)
    control.dropdown:SetShown(shown)
    control.label:SetShown(shown)
    if control.amount then
        control.amount:SetShown(shown)
    end
end


local function placePresetControl(control, topOffset)
    local theme = addon.Theme
    control.label:ClearAllPoints()
    control.label:SetPoint("TOPLEFT", dialog, "TOPLEFT", theme.Spacing.lg, topOffset)
    control.field:ClearAllPoints()
    control.field:SetPoint(
        "TOPLEFT", dialog, "TOPLEFT",
        theme.Spacing.lg + theme.Sizes.editorLabelWidth,
        topOffset + theme.Spacing.xs
    )
end

local function placeEffectMessage(topOffset)
    local theme = addon.Theme
    dialog.effectMessageLabel:ClearAllPoints()
    dialog.effectMessageLabel:SetPoint(
        "TOPLEFT", dialog, "TOPLEFT", theme.Spacing.lg, topOffset
    )
    dialog.fields.effectMessage:ClearAllPoints()
    dialog.fields.effectMessage:SetPoint(
        "TOPLEFT", dialog, "TOPLEFT",
        theme.Spacing.lg + theme.Sizes.editorLabelWidth,
        topOffset + theme.Spacing.xs
    )
end

local function placeTabSelector(topOffset)
    local theme = addon.Theme
    dialog.tabLabel:ClearAllPoints()
    dialog.tabLabel:SetPoint(
        "TOPLEFT", dialog, "TOPLEFT", theme.Spacing.lg, topOffset
    )
    dialog.previousTab:ClearAllPoints()
    dialog.previousTab:SetPoint(
        "TOPLEFT", dialog, "TOPLEFT",
        theme.Spacing.lg + theme.Sizes.editorLabelWidth,
        topOffset + theme.Spacing.xs
    )
end

local function restoreResource(kind)
    local draft = state.kindDrafts[kind] or {}
    dialog.resourceControl.amount:SetText(draft.amount or "")
    dialog.resourceControl.field:SetText(draft.resource or "")
    dialog.resourceControl.amount:SetEnabled(draft.amountEnabled ~= false)
end

local function updateKindVisibility()
    local magical = state.kind == constants.SPELL_KIND_MAGIC
    setControlShown(dialog.magicTypeControl, magical)
    setControlShown(dialog.magicSchoolControl, magical)
    setControlShown(dialog.damageTypeControl, not magical)
    setTypeButtonActive(dialog.magicButton, magical)
    setTypeButtonActive(dialog.abilityButton, not magical)
end

local function selectKind(kind, preserveCurrent)
    if kind ~= constants.SPELL_KIND_MAGIC
        and kind ~= constants.SPELL_KIND_ABILITY
    then
        return
    end
    if preserveCurrent and state.kind and state.kind ~= kind then
        snapshotResource()
    end
    state.kind = kind
    restoreResource(kind)
    updateKindVisibility()
end

local getDurationTracking
local function updateEffectPreview(enabled)
    local preview = dialog.effectMessagePreview
    if not preview then return 0 end
    local template = trim(dialog.fields.effectMessage:GetText())
    local shown = enabled and template ~= "" and addon.WhisperTemplates ~= nil
    preview:SetShown(shown)
    local height = 0
    if shown then
        local rounds, seconds = getDurationTracking()
        local effects = {
            buff = state.effects.buff, debuff = state.effects.debuff, healing = state.effects.healing,
            duration = dialog.fields.duration:GetText(), durationRounds = rounds, durationSeconds = seconds,
        }
        local spell = { name = dialog.fields.name:GetText(), effects = effects, tags = {
            [constants.MAGIC_TAG_TYPE] = dialog.fields.magicType:GetText(),
            [constants.MAGIC_TAG_SCHOOL] = dialog.fields.magicSchool:GetText(),
        } }
        local message = addon.WhisperTemplates.Render(template, spell, {
            playerID = state.previewPlayer, targetID = state.previewTarget,
        })
        preview:SetText(addon.L("WHISPER_PREVIEW") .. ": " .. (message or ""))
        height = (preview.GetStringHeight and preview:GetStringHeight() or 42) + 12
    end
    dialog:SetHeight(addon.Theme.Sizes.dialogHeight + height)
    return height
end

local function updateEffectVisibility()
    local effects = state.effects or {}
    local mode = getPrimaryEffectMode(effects)
    local timed = mode ~= nil
    local enabled = timed or effects.healing == true
    setPrimaryEffectAppearance(dialog.buffToggle, mode)
    dialog.healingToggle:SetChecked(effects.healing == true)
    setSelectedIcon(state.icon)
    setControlShown(dialog.debuffTypeControl, mode == "debuff")
    setControlShown(dialog.durationControl, timed)
    dialog.effectMessageLabel:SetShown(enabled)
    dialog.fields.effectMessage:SetShown(enabled)

    local row = state.kind == constants.SPELL_KIND_MAGIC and -516 or -482
    if mode == "debuff" then
        placePresetControl(dialog.debuffTypeControl, row)
        row = row - 34
    end
    if timed then
        placePresetControl(dialog.durationControl, row)
        row = row - 34
    end
    if enabled then
        placeEffectMessage(row)
        row = row - 34
    end
    row = row - updateEffectPreview(enabled)
    placeTabSelector(row)

    if enabled then
        local example = addon.WhisperTemplates and addon.WhisperTemplates.Example(state.exampleIndex)
            or addon.L("EFFECT_WHISPER_PLACEHOLDER_BUFF")
        dialog.fields.effectMessage.presetPlaceholder:SetText(example)
        dialog.fields.effectMessage.refreshPresetPlaceholder()
    end
end

getDurationTracking = function()
    local selected = state.timeSelections.duration or {}
    if selected.permanent then return constants.EFFECT_DURATION_PERMANENT, nil end
    local options = addon.SpellCreationPresets.GetDurations(
        state.timeModes.duration
            or addon.SpellCreationSettings.GetTimeMode()
    )
    local maximum
    for _, item in ipairs(options) do
        if selected[item.value] and item.order then
            maximum = math.max(maximum or 0, item.order)
        end
    end
    if maximum then
        if (state.timeModes.duration
            or addon.SpellCreationSettings.GetTimeMode()) == "time"
        then
            return nil, math.floor(maximum)
        end
        return math.floor(maximum), nil
    end
    if trim(dialog.fields.duration:GetText()) == state.originalEffectDuration then
        return state.originalDurationRounds, state.originalDurationSeconds
    end
    local rounds, seconds = addon.SpellPresentation.ParseEffectDuration(dialog.fields.duration:GetText())
    if rounds and rounds > 5 then rounds = constants.EFFECT_DURATION_PERMANENT end
    return rounds, seconds
end

local function buildEffects()
    local effects = state.effects or {}
    local timed = effects.buff == true or effects.debuff == true
    if not timed and effects.healing ~= true then
        return nil
    end
    local durationRounds, durationSeconds = getDurationTracking()
    return {
        buff = effects.buff == true,
        debuff = effects.debuff == true,
        debuffType = effects.debuff and trim(dialog.fields.debuffType:GetText()) or nil,
        duration = timed and (durationRounds == constants.EFFECT_DURATION_PERMANENT
            and constants.EFFECT_DURATION_INFINITY or trim(dialog.fields.duration:GetText())) or nil,
        durationRounds = timed and durationRounds or nil,
        durationSeconds = timed and durationSeconds or nil,
        healing = effects.healing == true,
        whisperTemplate = trim(dialog.fields.effectMessage:GetText()),
    }
end
local function buildTags()
    local tags = {}
    for key, value in pairs(state.legacyTags or {}) do
        tags[key] = value
    end
    tags[constants.SPELL_TAG_KIND] = state.kind
    if state.kind == constants.SPELL_KIND_MAGIC then
        tags[constants.MAGIC_TAG_ENABLED] = "true"
        local magicType = trim(dialog.fields.magicType:GetText())
        local magicSchool = trim(dialog.fields.magicSchool:GetText())
        if magicType ~= "" then
            tags[constants.MAGIC_TAG_TYPE] = magicType
        end
        if magicSchool ~= "" then
            tags[constants.MAGIC_TAG_SCHOOL] = magicSchool
        end
    else
        local damageType = trim(dialog.fields.damageType:GetText())
        if damageType ~= "" then
            tags[constants.SPELL_TAG_DAMAGE_TYPE] = damageType
        end
    end
    local castTime = trim(dialog.fields.castTime:GetText())
    local castRounds = addon.SpellPresentation.GetCastRounds({
        castTime = castTime,
        tags = castTime == state.originalCastTime
            and { [constants.SPELL_TAG_CAST_ROUNDS] = state.originalCastRoundTag } or nil,
    })
    if castRounds then
        tags[constants.SPELL_TAG_CAST_ROUNDS] = tostring(castRounds)
    end
    return tags
end

local function buildResource()
    local resource = trim(dialog.resourceControl.field:GetText())
    local amount = trim(dialog.resourceControl.amount:GetText())
    resource = addon.SpellCreationPresets.FormatResource(resource, amount)
    if resource == "" then
        return ""
    end
    if dialog.resourceControl.amount:IsEnabled() and amount ~= "" then
        return amount .. " " .. resource
    end
    return resource
end

local function saveSpell()
    if not dialog:IsShown() then return end
    setError(nil)
    if not checkBook() then return end
    local book = getStorage().GetActiveSpellbook()
    if not book.tabs[state.selectedTabID] then
        setError(addon.L("INVALID_SELECTED_TAB"))
        return
    end
    snapshotResource()
    local data = {
        name = dialog.fields.name:GetText(),
        icon = state.icon,
        nameColor = state.nameColor,
        resource = buildResource(),
        range = dialog.fields.range:GetText(),
        castTime = dialog.fields.castTime:GetText(),
        cooldown = dialog.fields.cooldown:GetText(),
        description = dialog.fields.description:GetText(),
        effects = buildEffects(),
        tags = buildTags(),
        clearOptionalFields = true,
    }
    local spell, errorMessage
    if state.spellID then
        spell, errorMessage = getStorage().UpdateSpell(state.spellID, data)
        if spell and state.originalTabID ~= state.selectedTabID then
            if not checkBook() then return end
            local moved, moveError = getStorage().MoveSpell(
                state.spellID,
                state.selectedTabID
            )
            if not moved then
                setError(moveError)
                return
            end
        end
    else
        spell, errorMessage = getStorage().CreateSpell(
            state.selectedTabID,
            data
        )
    end
    if not spell then
        setError(errorMessage)
        return
    end
    state.spellID, state.originalTabID = spell.id, state.selectedTabID
    local onChanged, selectedTabID = state.onChanged, state.selectedTabID
    dialog:Hide()
    if addon.Onboarding and addon.Onboarding.OnSpellSaved then
        addon.Onboarding.OnSpellSaved(state, spell)
    end
    if type(onChanged) == "function" then
        onChanged(selectedTabID, spell.id)
    end
end

local function deleteSpell()
    if not state.spellID or not checkBook() then
        return
    end
    local storage, spellID, tabID, onChanged = getStorage(), state.spellID, state.originalTabID, state.onChanged
    local book, token = state.book, state.token
    local resolved = false
    local spell = storage.GetSpell(spellID)
    dialog:Hide()
     
     
    if type(state.onDelete) == "function" then
        local token = state.token
        state.onDelete(function()
            if state.token == token then showDialog() end
        end)
        return
    end
    addon.UIFactory.ShowConfirmation(
        addon.L("DELETE_ABILITY_TITLE"),
        addon.L(
            "DELETE_ABILITY_CONFIRM",
            spell and spell.name or addon.L("UNKNOWN_ABILITY")
        ),
        function()
            if resolved then return end
            resolved = true
            if not ownsBook(storage, book) then
                if state.token == token then
                    showDialog()
                    setError(addon.L("EDITOR_PROFILE_CHANGED"))
                end
                return
            end
            local deleted, errorMessage =
                storage.DeleteSpell(spellID)
            if not deleted then
                if state.token == token then
                    showDialog()
                    setError(errorMessage)
                end
                return
            end
            if type(onChanged) == "function" then
                onChanged(tabID)
            end
        end,
        function()
            if resolved then return end
            resolved = true
            if state.token == token then showDialog() end
        end
    )
end

local function createDialog()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("EDIT_ABILITY"),
        theme.Sizes.dialogWidth,
        theme.Sizes.dialogHeight
    )

    local iconLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.small,
        addon.L("FIELD_ICON_RESET"),
        theme.Colors.textMuted
    )
    iconLabel:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        theme.Spacing.lg,
        -theme.Spacing.xl - theme.Spacing.lg
    )
    local iconButton = addon.UIFactory.CreateIconButton(frame)
    iconButton:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    iconButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            setSelectedIcon(nil)
            return
        end
        local success, errorMessage = addon.TRP3Bridge.OpenIconBrowser(
            state.icon,
            draftCallback(setSelectedIcon),
            nil,
            frame
        )
        if not success then
            setError(errorMessage)
        end
    end)

    local nameLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("FIELD_NAME"),
        theme.Colors.textMuted
    )
    nameLabel:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", theme.Spacing.md, 0)
    local nameField = addon.UIFactory.CreateEditBox(frame, false)
    nameField:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    nameField:SetWidth(
        theme.Sizes.dialogWidth
            - (theme.Spacing.lg * 3)
            - theme.Sizes.editorIcon
            - theme.Sizes.inputHeight
    )
    local colorButton = addon.UIFactory.CreateColorButton(frame)
    colorButton:SetPoint("LEFT", nameField, "RIGHT", theme.Spacing.sm, 0)
    colorButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            setSelectedNameColor(nil)
            return
        end
        local success, errorMessage = addon.TRP3Bridge.OpenColorPicker(
            state.nameColor,
            draftCallback(setSelectedNameColor),
            nil,
            frame
        )
        if not success then
            setError(errorMessage)
        end
    end)
    colorButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addon.L("FIELD_NAME_COLOR"), 1, 0.82, 0)
        GameTooltip:AddLine(addon.L("COLOR_RESET_HINT"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    colorButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local kindLabel = createLabel(frame, addon.L("FIELD_ENTRY_KIND"), -106)
    local magicButton = createTypeButton(frame, addon.L("ENTRY_KIND_MAGIC"))
    magicButton:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        theme.Spacing.lg + theme.Sizes.editorLabelWidth,
        -102
    )
    magicButton:SetWidth((theme.Sizes.editorInputWidth - theme.Spacing.xs) / 2)
    local abilityButton = createTypeButton(
        frame,
        addon.L("ENTRY_KIND_ABILITY")
    )
    abilityButton:SetPoint("LEFT", magicButton, "RIGHT", theme.Spacing.xs, 0)
    abilityButton:SetWidth((theme.Sizes.editorInputWidth - theme.Spacing.xs) / 2)
    magicButton:SetScript("OnClick", function()
        selectKind(constants.SPELL_KIND_MAGIC, true)
        updateEffectVisibility()
        refreshEditorTheme()
    end)
    abilityButton:SetScript("OnClick", function()
        selectKind(constants.SPELL_KIND_ABILITY, true)
        updateEffectVisibility()
        refreshEditorTheme()
    end)
    local buffToggle = createEffectToggle(frame, "EFFECT_BUFF")
    buffToggle:SetPoint(
        "TOPLEFT", frame, "TOPLEFT",
        theme.Spacing.lg + theme.Sizes.editorLabelWidth,
        -134
    )
    buffToggle:SetScript("OnClick", function(self)
        local nextMode = addon.SpellEditorWindow.GetNextPrimaryEffectMode(
            getPrimaryEffectMode(state.effects)
        )
        state.effects.buff = nextMode == "buff"
        state.effects.debuff = nextMode == "debuff"
        updateEffectVisibility()
    end)
    buffToggle.refreshAppearance = function(self)
        setPrimaryEffectAppearance(self, getPrimaryEffectMode(state.effects))
    end
    local healingToggle = createEffectToggle(frame, "EFFECT_HEALING")
    healingToggle:SetPoint("LEFT", buffToggle, "RIGHT", 105, 0)
    healingToggle:SetScript("OnClick", function(self)
        state.effects.healing = self:GetChecked() == true
        updateEffectVisibility()
    end)

    local resourceControl = createPresetField(
        frame,
        addon.L("FIELD_RESOURCE"),
        -174,
        true
    )
    local rangeControl = createPresetField(
        frame,
        addon.L("FIELD_RANGE"),
        -208,
        false
    )
    local castTimeControl = createPresetField(
        frame,
        addon.L("FIELD_CAST_TIME"),
        -242,
        false
    )
    local cooldownControl = createPresetField(
        frame,
        addon.L("FIELD_COOLDOWN"),
        -276,
        false
    )
    attachFieldPlaceholder(castTimeControl.field)
    attachFieldPlaceholder(cooldownControl.field)
    local description, descriptionLabel =
        createDescriptionField(frame, -310)
    local magicTypeControl = createPresetField(
        frame,
        addon.L("FIELD_MAGIC_TYPE"),
        -448,
        false
    )
    local magicSchoolControl = createPresetField(
        frame,
        addon.L("FIELD_MAGIC_SCHOOL"),
        -482,
        false
    )
    local damageTypeControl = createPresetField(
        frame,
        addon.L("FIELD_DAMAGE_TYPE"),
        -448,
        false
    )
    local debuffTypeControl = createPresetField(
        frame,
        addon.L("FIELD_DEBUFF_TYPE"),
        -516,
        false
    )
    local durationControl = createPresetField(
        frame,
        addon.L("FIELD_DURATION"),
        -516,
        false
    )
    attachFieldPlaceholder(durationControl.field)
    local effectMessageLabel = createLabel(
        frame,
        addon.L("FIELD_EFFECT_WHISPER"),
        -550
    )
    local effectMessage = addon.UIFactory.CreateEditBox(frame, false)
    effectMessage:SetPoint(
        "TOPLEFT", frame, "TOPLEFT",
        theme.Spacing.lg + theme.Sizes.editorLabelWidth,
        -546
    )
    effectMessage:SetWidth(theme.Sizes.editorInputWidth)
    effectMessage:SetMaxLetters(300)
    attachFieldPlaceholder(effectMessage)
    local effectMessagePreview = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.small, "", theme.Colors.textMuted
    )
    effectMessagePreview:SetPoint("TOPLEFT", effectMessage, "BOTTOMLEFT", 0, -6)
    effectMessagePreview:SetWidth(theme.Sizes.editorInputWidth)
    effectMessagePreview:SetJustifyH("LEFT")
    if effectMessagePreview.SetWordWrap then effectMessagePreview:SetWordWrap(true) end
    if effectMessagePreview.SetNonSpaceWrap then effectMessagePreview:SetNonSpaceWrap(true) end
    if effectMessagePreview.SetMaxLines then effectMessagePreview:SetMaxLines(3) end
    effectMessagePreview:Hide()

    local function refreshResourceName()
        local field = resourceControl.field
        local text = addon.SpellCreationPresets.FormatResource(
            field:GetText(), resourceControl.amount:GetText()
        )
        if text ~= field:GetText() then field:SetText(text) end
    end
    resourceControl.amount:HookScript("OnTextChanged", refreshResourceName)

    resourceControl.field:HookScript("OnTextChanged", function()
        if not state.applyingResourcePreset
            and not resourceControl.amount:IsEnabled()
        then
            resourceControl.amount:SetEnabled(true)
        end
    end)

    setSimplePresetMenu(
        resourceControl,
        function()
            return addon.SpellCreationPresets.GetResources(state.kind)
        end,
        function(item)
            state.applyingResourcePreset = true
            resourceControl.amount:SetEnabled(item.allowsAmount ~= false)
            if item.allowsAmount == false then
                resourceControl.amount:SetText("")
            end
            refreshResourceName()
            state.applyingResourcePreset = false
        end
    )
    setSimplePresetMenu(
        rangeControl,
        addon.SpellCreationPresets.GetRanges
    )
    setTimePresetMenu(
        castTimeControl,
        "castTime",
        addon.SpellCreationPresets.GetCastTimes,
        "cast"
    )
    setTimePresetMenu(
        cooldownControl,
        "cooldown",
        addon.SpellCreationPresets.GetCooldowns,
        "cooldown"
    )
    setSimplePresetMenu(
        magicTypeControl,
        addon.SpellCreationPresets.GetMagicTypes,
        nil,
        addon.SpellCreationPresets.GetMagicSubtypes
    )
    setSimplePresetMenu(
        magicSchoolControl,
        addon.SpellCreationPresets.GetMagicSchools
    )
    setSimplePresetMenu(
        damageTypeControl,
        addon.SpellCreationPresets.GetDamageTypes
    )
    setSimplePresetMenu(
        debuffTypeControl,
        addon.SpellCreationPresets.GetDebuffTypes
    )
    magicTypeControl.field:HookScript("OnTextChanged", function()
        if dialog and dialog.iconButton then setSelectedIcon(state.icon) end
        refreshEditorTheme()
    end)
    damageTypeControl.field:HookScript("OnTextChanged", function()
        refreshEditorTheme()
    end)
    debuffTypeControl.field:HookScript("OnTextChanged", function()
        if dialog and dialog.iconButton then setSelectedIcon(state.icon) end
    end)
    setTimePresetMenu(
        durationControl,
        "duration",
        addon.SpellCreationPresets.GetDurations,
        "cooldown"
    )


    local tabLabel = createLabel(frame, addon.L("FIELD_TAB"), -584)
    local previousTab = addon.UIFactory.CreateButton(
        frame,
        "<",
        theme.Sizes.pageButtonWidth
    )
    previousTab:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        theme.Spacing.lg + theme.Sizes.editorLabelWidth,
        -580
    )
    previousTab:SetScript("OnClick", function()
        cycleTab(-1)
    end)
    local tabName = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        "",
        theme.Colors.text
    )
    tabName:SetPoint("LEFT", previousTab, "RIGHT", theme.Spacing.sm, 0)
    tabName:SetWidth(
        theme.Sizes.editorInputWidth
            - (theme.Sizes.pageButtonWidth * 2)
            - (theme.Spacing.sm * 2)
    )
    tabName:SetJustifyH("CENTER")
    local nextTab = addon.UIFactory.CreateButton(
        frame,
        ">",
        theme.Sizes.pageButtonWidth
    )
    nextTab:SetPoint("LEFT", tabName, "RIGHT", theme.Spacing.sm, 0)
    nextTab:SetScript("OnClick", function()
        cycleTab(1)
    end)

    local errorLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.small,
        "",
        theme.Colors.error
    )
    errorLabel:SetPoint(
        "BOTTOMLEFT",
        frame,
        "BOTTOMLEFT",
        theme.Spacing.lg,
        54
    )
    errorLabel:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -theme.Spacing.lg,
        54
    )
    errorLabel:SetJustifyH("LEFT")
    local saveButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("SAVE"),
        theme.Sizes.dialogButtonWidth
    )
    saveButton:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -theme.Spacing.lg,
        theme.Spacing.lg
    )
    saveButton:SetScript("OnClick", saveSpell)
    local cancelButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("CANCEL"),
        theme.Sizes.dialogButtonWidth
    )
    cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -theme.Spacing.sm, 0)
    cancelButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    local deleteButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("DELETE"),
        theme.Sizes.deleteButtonWidth
    )
    deleteButton:SetPoint(
        "BOTTOMLEFT",
        frame,
        "BOTTOMLEFT",
        theme.Spacing.lg,
        theme.Spacing.lg
    )
    deleteButton:SetScript("OnClick", deleteSpell)

    frame.abilityButton = abilityButton
    frame.buffToggle = buffToggle
    frame.colorButton = colorButton
    frame.damageTypeLabel = damageTypeControl.label
    frame.damageTypeControl = damageTypeControl
    frame.debuffTypeControl = debuffTypeControl
    frame.deleteButton = deleteButton
    frame.saveButton = saveButton
    frame.errorLabel = errorLabel
    frame.fields = {
        castTime = castTimeControl.field,
        cooldown = cooldownControl.field,
        damageType = damageTypeControl.field,
        debuffType = debuffTypeControl.field,
        description = description,
        duration = durationControl.field,
        effectMessage = effectMessage,
        magicSchool = magicSchoolControl.field,
        magicType = magicTypeControl.field,
        name = nameField,
        range = rangeControl.field,
        resource = resourceControl.field,
    }
    for _, field in pairs(frame.fields) do
        attachFieldCursor(field)
    end
    attachFieldCursor(resourceControl.amount)
    frame.durationControl = durationControl
    frame.effectMessageLabel = effectMessageLabel
    frame.effectMessagePreview = effectMessagePreview
    frame.healingToggle = healingToggle
    frame.iconButton = iconButton
    frame.magicButton = magicButton
    frame.magicSchoolControl = magicSchoolControl
    frame.magicTypeControl = magicTypeControl
    frame.magicSchoolLabel = magicSchoolControl.label
    frame.magicTypeLabel = magicTypeControl.label
    frame.resourceControl = resourceControl
    frame.previousTab = previousTab
    frame.tabName = tabName
    frame.kindLabel = kindLabel
    frame.descriptionLabel = descriptionLabel
    frame.tabLabel = tabLabel
    frame.themeLabels = {
        iconLabel,
        nameLabel,
        kindLabel,
        resourceControl.label,
        rangeControl.label,
        castTimeControl.label,
        cooldownControl.label,
        descriptionLabel,
        magicTypeControl.label,
        magicSchoolControl.label,
        damageTypeControl.label,
        debuffTypeControl.label,
        durationControl.label,
        effectMessageLabel,
        tabLabel,
    }
    frame.themeText = {
        effectMessagePreview,
        nameField,
        magicButton.label,
        abilityButton.label,
        buffToggle.label,
        healingToggle.label,
        resourceControl.field,
        rangeControl.field,
        castTimeControl.field,
        cooldownControl.field,
        description,
        magicTypeControl.field,
        magicSchoolControl.field,
        damageTypeControl.field,
        debuffTypeControl.field,
        durationControl.field,
        effectMessage,
        tabName,
    }
    frame.themeFields = {
        nameField,
        resourceControl.field,
        rangeControl.field,
        castTimeControl.field,
        cooldownControl.field,
        description,
        magicTypeControl.field,
        magicSchoolControl.field,
        damageTypeControl.field,
        debuffTypeControl.field,
        durationControl.field,
        effectMessage,
    }
    frame.themeButtons = {
        previousTab,
        nextTab,
        saveButton,
        cancelButton,
        deleteButton,
    }
    frame:HookScript("OnShow", refreshEditorTheme)
    for _, field in ipairs({ effectMessage, nameField, durationControl.field,
        magicTypeControl.field, magicSchoolControl.field }) do
        field:HookScript("OnTextChanged", function()
            if dialog and not state.loading then updateEffectVisibility() end
        end)
    end
    return frame
end

local function splitResource(value, kind)
    local text = trim(value)
    local amount, resource = text:match("^(%d+)%s+(.+)$")
    local formatted, essence = addon.SpellCreationPresets.FormatResource(resource or text, amount or "")
    if essence then return amount or "", formatted, true 
    end

    for _, item in ipairs(addon.SpellCreationPresets.GetResources(kind)) do
        if text == item.label then
            return "", text, item.allowsAmount
        end
        local amount, resource = text:match("^(%d+)%s+(.+)$")
        if amount and resource == item.label and item.allowsAmount then
            return amount, resource, true
        end
    end
    return "", text, true
end

local function prepareDialog(tabID, spell, onChanged, storage, onDelete, draft)
    state.storage = storage
    state.book = getStorage().GetActiveSpellbook()
    state.bookID = state.book and state.book.id
    state.creationDraft = draft
    state.onDelete, state.token = onDelete, {}
    state.loading = true
    dialog = dialog or createDialog()
    state.exampleIndex = math.random(3)
    local bridge = addon.TRP3Bridge
    state.previewPlayer = addon.GameMasterRoster and addon.GameMasterRoster.GetLocalPlayerID()
        or (bridge.GetExportOwnerInfo and bridge.GetExportOwnerInfo().characterName)
    local candidates = bridge.GetKnownRoleplayProfiles and bridge.GetKnownRoleplayProfiles(80) or {}
    local candidate = #candidates > 0 and candidates[math.random(#candidates)] or nil
    state.previewTarget = candidate and candidate.gameName or state.previewPlayer
    state.spellID = spell and spell.id or nil
    state.originalTabID = spell
        and getStorage().GetSpellTabID(spell.id)
        or tabID
    state.selectedTabID = state.originalTabID
    state.onChanged = onChanged
    local existing = spell
    spell = spell or draft
    state.originalCastTime = trim(spell and spell.castTime)
    state.originalCastRoundTag = type(spell and spell.tags) == "table"
        and spell.tags[constants.SPELL_TAG_CAST_ROUNDS] or nil
    state.timeSelections = {
        castTime = {},
        cooldown = {},
        duration = {},
    }
    state.timeModes = {}
    state.kindDrafts = {}
    state.applyingTimePreset = false
    local effects = type(spell) == "table"
        and type(spell.effects) == "table"
        and spell.effects
        or {}
    state.effects = {
        buff = effects.buff == true,
        debuff = effects.debuff == true,
        healing = effects.healing == true,
    }
    state.icon = spell and spell.icon or nil
    state.originalEffectDuration = trim(effects.duration)
    state.originalDurationRounds = effects.durationRounds
    state.originalDurationSeconds = effects.durationSeconds
    if tonumber(effects.durationRounds) then
        state.timeModes.duration = "rounds"
    elseif tonumber(effects.durationSeconds) then
        state.timeModes.duration = "time"
    end

    dialog.title:SetText(
        existing and addon.L("EDIT_ABILITY") or addon.L("NEW_ABILITY")
    )
    dialog.fields.name:SetText(spell and spell.name or "")
    setSelectedNameColor(spell and spell.nameColor or nil)
    dialog.fields.range:SetText(spell and spell.range or "")
    dialog.fields.castTime:SetText(spell and spell.castTime or "")
    dialog.fields.cooldown:SetText(spell and spell.cooldown or "")
    dialog.fields.description:SetText(spell and spell.description or "")
    dialog.fields.duration:SetText(effects.duration or "")
    dialog.fields.debuffType:SetText(effects.debuffType or "")
    dialog.fields.effectMessage:SetText(effects.whisperTemplate or "")
    dialog.fields.description.scrollFrame:SetVerticalScroll(0)
    restoreTimeSelection(
        "castTime",
        dialog.fields.castTime:GetText(),
        addon.SpellCreationPresets.GetCastTimes,
        "cast"
    )
    restoreTimeSelection(
        "cooldown",
        dialog.fields.cooldown:GetText(),
        addon.SpellCreationPresets.GetCooldowns,
        "cooldown"
    )
    restoreTimeSelection(
        "duration",
        dialog.fields.duration:GetText(),
        addon.SpellCreationPresets.GetDurations,
        "cooldown"
    )
    updateTimePlaceholders()

    local tags = spell and spell.tags or {}
    state.legacyTags = copyLegacyTags(tags)
    local kind = spell and getSpellKind(spell) or getAdaptiveKind()
    local amount, resource, amountEnabled = splitResource(
        spell and spell.resource or "",
        kind
    )
    state.kindDrafts[kind] = {
        amount = amount,
        amountEnabled = amountEnabled,
        resource = resource,
    }
    dialog.fields.magicType:SetText(
        tags[constants.MAGIC_TAG_TYPE] or tags.Magieart or ""
    )
    dialog.fields.magicSchool:SetText(
        tags[constants.MAGIC_TAG_SCHOOL] or tags.Magieschule or ""
    )
    dialog.fields.damageType:SetText(
        tags[constants.SPELL_TAG_DAMAGE_TYPE] or ""
    )
    selectKind(kind, false)
    state.loading = false
    updateEffectVisibility()
    refreshEditorTheme()

    dialog.deleteButton:SetShown(existing ~= nil)
    setError(nil)
    refreshSelectedTab()
    showDialog()
end

function addon.SpellEditorWindow.OpenNew(tabID, onChanged, storage)
    local draft = addon.Onboarding and addon.Onboarding.GetCreationDraft
        and addon.Onboarding.GetCreationDraft(storage)
    prepareDialog(tabID, nil, onChanged, storage, nil, draft)
end

function addon.SpellEditorWindow.GetTutorialContext()
    return dialog, state
end

function addon.SpellEditorWindow.ResumeTutorialDraft(token, storage, book)
    if not dialog or not token or token ~= state.token or getStorage() ~= (storage or addon.Database)
        or not ownsBook(getStorage(), book) or state.bookID ~= book.id
        or (type(InCombatLockdown) == "function" and InCombatLockdown()) then return false end
     
    showDialog()
    return true
end

function addon.SpellEditorWindow.OpenEdit(spellID, onChanged, storage, onDelete)
    local spell = (storage or addon.Database).GetSpell(spellID)
    if not spell then
        addon.Logger.Error(addon.L("ABILITY_NOT_FOUND"))
        return
    end
    prepareDialog(nil, spell, onChanged, storage, onDelete)
end
