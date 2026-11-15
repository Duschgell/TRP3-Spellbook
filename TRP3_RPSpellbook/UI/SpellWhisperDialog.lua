local _, addon = ...

addon.SpellWhisperDialog = {}

local dialog
local state = {}

local function canAccess(value)
    if type(_G.canaccessvalue) ~= "function" then
        return true
    end
    local success, accessible = pcall(_G.canaccessvalue, value)
    return success and accessible == true
end

local function getUnitPlayerID(unit)
    if type(_G.UnitIsPlayer) ~= "function" then
        return nil
    end
    local playerSuccess, isPlayer = pcall(_G.UnitIsPlayer, unit)
    if not playerSuccess
        or not canAccess(isPlayer)
        or isPlayer ~= true
    then
        return nil
    end
    local name
    local realm
    if type(_G.UnitFullName) == "function" then
        local success
        success, name, realm = pcall(_G.UnitFullName, unit)
        if not success or not canAccess(name) or not canAccess(realm) then
            name = nil
            realm = nil
        end
    end
    if type(name) ~= "string" or name == "" then
        if type(_G.UnitName) == "function" then
            local success
            success, name = pcall(_G.UnitName, unit)
            if not success or not canAccess(name) then
                name = nil
            end
        end
    end
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return type(realm) == "string" and realm ~= ""
        and (name .. "-" .. realm)
        or name
end

local function updatePreviewLayout(frame)
    local theme = addon.Theme
    local width = math.max(
        1,
        frame.previewScroll:GetWidth() - theme.Spacing.sm
    )
    frame.previewChild:SetWidth(width)
    frame.previewText:SetWidth(width)
    local height = math.max(
        frame.previewScroll:GetHeight(),
        frame.previewText:GetStringHeight() + theme.Spacing.md
    )
    frame.previewChild:SetHeight(height)
    frame.previewScroll:UpdateScrollChildRect()
end

local function refreshPreview(frame, messages)
    frame.previewText:SetText(table.concat(messages or {}, "\n"))
    frame.previewScroll:SetVerticalScroll(0)
    updatePreviewLayout(frame)
end

local function sendCurrentSpell()
    if not dialog or type(state.spell) ~= "table" then
        return
    end
    local target = dialog.targetEdit:GetText()
    local success, result =
        addon.ChatFallbacks.SendSpellWhisper(state.spell, target)
    if not success then
        addon.Logger.Error(result or addon.L("CHAT_FALLBACK_SEND_FAILED"))
        return
    end
    addon.Logger.Info(addon.L(
        "CHAT_FALLBACK_SENT",
        result,
        target
    ))
    dialog:Hide()
end

local function createDialog()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("CHAT_FALLBACK_WHISPER_TITLE"),
        590,
        430
    )

    local groupLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("CHAT_FALLBACK_GROUP_MEMBER"),
        theme.Colors.gold
    )
    groupLabel:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        theme.Spacing.lg,
        -theme.Spacing.xl - theme.Spacing.lg
    )

    local groupSelector = addon.GameMasterWidgets.CreateSelector(
        frame,
        360,
        addon.L("CHAT_FALLBACK_NO_GROUP_TARGET")
    )
    groupSelector:SetPoint(
        "TOPLEFT",
        groupLabel,
        "BOTTOMLEFT",
        0,
        -theme.Spacing.xs
    )

    local targetLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("CHAT_FALLBACK_TARGET"),
        theme.Colors.gold
    )
    targetLabel:SetPoint(
        "TOPLEFT",
        groupSelector,
        "BOTTOMLEFT",
        0,
        -theme.Spacing.md
    )

    local targetEdit = addon.UIFactory.CreateEditBox(frame, false)
    targetEdit:SetPoint(
        "TOPLEFT",
        targetLabel,
        "BOTTOMLEFT",
        0,
        -theme.Spacing.xs
    )
    targetEdit:SetPoint(
        "RIGHT",
        frame,
        "RIGHT",
        -theme.Spacing.lg,
        0
    )
    targetEdit:SetScript("OnEnterPressed", sendCurrentSpell)
    groupSelector:SetOnValueChanged(function(value)
        if type(value) == "string" and value ~= "" then
            targetEdit:SetText(value)
        end
    end)

    local previewLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("CHAT_FALLBACK_PREVIEW"),
        theme.Colors.gold
    )
    previewLabel:SetPoint(
        "TOPLEFT",
        targetEdit,
        "BOTTOMLEFT",
        0,
        -theme.Spacing.md
    )

    local preview = addon.UIFactory.CreateBackdropFrame(
        frame,
        theme.Colors.parchmentDark,
        theme.Colors.border
    )
    preview:SetPoint(
        "TOPLEFT",
        previewLabel,
        "BOTTOMLEFT",
        0,
        -theme.Spacing.xs
    )
    preview:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -theme.Spacing.lg,
        theme.Spacing.xl + theme.Sizes.buttonHeight
    )
    preview:SetClipsChildren(true)

    local previewScroll = CreateFrame(
        "ScrollFrame",
        nil,
        preview,
        "UIPanelScrollFrameTemplate"
    )
    previewScroll:SetPoint(
        "TOPLEFT",
        preview,
        "TOPLEFT",
        theme.Spacing.sm,
        -theme.Spacing.sm
    )
    previewScroll:SetPoint(
        "BOTTOMRIGHT",
        preview,
        "BOTTOMRIGHT",
        -theme.Spacing.xl,
        theme.Spacing.sm
    )

    local previewChild = CreateFrame("Frame", nil, previewScroll)
    previewChild:SetPoint("TOPLEFT")
    previewChild:SetSize(1, 1)
    previewScroll:SetScrollChild(previewChild)

    local previewText = addon.UIFactory.CreateLabel(
        previewChild,
        theme.Fonts.body,
        "",
        theme.Colors.text
    )
    previewText:SetPoint("TOPLEFT")
    previewText:SetJustifyH("LEFT")
    previewText:SetJustifyV("TOP")
    previewText:SetWordWrap(true)

    local sendButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("CHAT_FALLBACK_SEND"),
        theme.Sizes.dialogButtonWidth
    )
    sendButton:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -theme.Spacing.lg,
        theme.Spacing.lg
    )
    sendButton:SetScript("OnClick", sendCurrentSpell)

    local cancelButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("CANCEL"),
        theme.Sizes.dialogButtonWidth
    )
    cancelButton:SetPoint(
        "RIGHT",
        sendButton,
        "LEFT",
        -theme.Spacing.sm,
        0
    )
    cancelButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame.groupSelector = groupSelector
    frame.previewChild = previewChild
    frame.previewScroll = previewScroll
    frame.previewText = previewText
    frame.targetEdit = targetEdit
    previewScroll:SetScript("OnSizeChanged", function()
        updatePreviewLayout(frame)
    end)
    frame:SetScript("OnHide", function()
        targetEdit:ClearFocus()
        state.spell = nil
    end)
    return frame
end

function addon.SpellWhisperDialog.Open(spell)
    local messages, cleanedOrError =
        addon.ChatFallbacks.BuildSpellMessages(spell)
    if not messages then
        addon.Logger.Error(cleanedOrError or addon.L("INVALID_ABILITY"))
        return false
    end

    dialog = dialog or createDialog()
    state.spell = spell
    local targets = addon.ChatFallbacks.GetGroupTargets()
    local suggested = getUnitPlayerID("target")
    local selected
    for _, option in ipairs(targets) do
        if addon.Runtime.NormalizePlayerID(option.value)
            == addon.Runtime.NormalizePlayerID(suggested)
        then
            selected = option.value
            break
        end
    end
    selected = selected or (targets[1] and targets[1].value)
    dialog.groupSelector:SetOptions(targets, selected)
    dialog.targetEdit:SetText(suggested or selected or "")
    refreshPreview(dialog, messages)
    dialog:Show()
    addon.UIFactory.BringToFront(dialog)
    if dialog.targetEdit:GetText() == "" then
        dialog.targetEdit:SetFocus()
    end
    return true
end
