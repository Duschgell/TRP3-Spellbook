local _, addon = ...

addon.GameMasterActionDialog = {}

local function setSpellIcon(icon, spell)
    if type(addon.UIFactory.SetSpellIcon) == "function" then
        return addon.UIFactory.SetSpellIcon(
            icon, spell, addon.Constants.DEFAULT_BOOK_ICON, true
        )
    end
    return addon.UIFactory.SetIconTexture(
        icon, spell and spell.icon, addon.Constants.DEFAULT_BOOK_ICON
    )
end

local dialog
local selectedSpell
local selectedTargets = {}

function addon.GameMasterActionDialog.GetTutorialContext()
    return dialog, selectedTargets, selectedSpell
end

local actionOptions = {
    { labelKey = "GAMEMASTER_ACTION_PREPARE", value = "prepare" },
    { labelKey = "GAMEMASTER_ACTION_CAST", value = "cast" },
    { labelKey = "GAMEMASTER_ACTION_CHANNEL", value = "channel" },
}

local immediateActionOptions = {
    { labelKey = "GAMEMASTER_ACTION_CAST", value = "cast" },
    { labelKey = "GAMEMASTER_ACTION_CHANNEL", value = "channel" },
}

local readyActionOptions = {
    { labelKey = "GAMEMASTER_ACTION_CAST", value = "cast" },
}

local targetTypeOptions = {
    { labelKey = "GAMEMASTER_TARGET_NONE", value = "none" },
    { labelKey = "GAMEMASTER_TARGET_PLAYER", value = "player" },
    { labelKey = "GAMEMASTER_TARGET_NPC", value = "npc" },
    { labelKey = "GAMEMASTER_TARGET_TEXT", value = "text" },
    { labelKey = "GAMEMASTER_TARGET_MARKER", value = "marker" },
}

local function localizeOptions(source)
    local result = {}
    for _, option in ipairs(source) do
        result[#result + 1] = {
            label = addon.L(option.labelKey),
            value = option.value,
        }
    end
    return result
end

local function setError(message)
    dialog.errorLabel:SetText(message or "")
end

local function makeCheck(parent, labelText)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    local label = addon.UIFactory.CreateLabel(
        parent, addon.Theme.Fonts.small, labelText, addon.Theme.Colors.text
    )
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.label = label
    return check
end

local function getOptionLabel(selector, value)
    for _, option in ipairs(selector.options or {}) do
        if option.value == value then
            return option.label
        end
    end
    return tostring(value or "")
end

local function targetKey(target)
    return target.kind .. ":" .. tostring(target.value):lower()
end

local function refreshSelectedTargets()
    local lines = {}
    for index, target in ipairs(selectedTargets) do
        if index > 4 then break end
        lines[#lines + 1] = string.format(
            "%d. %s",
            index,
            target.label or tostring(target.value)
        )
    end
    if #selectedTargets > 4 then
        lines[#lines + 1] = addon.L(
            "GAMEMASTER_MORE_TARGETS",
            #selectedTargets - 4
        )
    end
    dialog.selectedTargets:SetText(#lines > 0
        and table.concat(lines, "\n")
        or addon.L("GAMEMASTER_NO_SELECTED_TARGETS"))
    dialog.targetCount:SetText(addon.L(
        "GAMEMASTER_TARGET_COUNT",
        #selectedTargets,
        addon.Constants.GAMEMASTER_MAX_TARGETS
    ))
    dialog.removeTarget:SetEnabled(#selectedTargets > 0)
    dialog.clearTargets:SetEnabled(#selectedTargets > 0)
end

local function getCurrentTarget()
    local targetType = dialog.targetTypeSelector:GetValue()
    if targetType == "none" then
        return nil
    end
    if targetType == "player" then
        local value = dialog.playerSelector:GetValue()
        local available = false
        for _, member in ipairs(addon.GameMasterService.GetActionMembers()) do
            if member.playerID == value then available = true; break end
        end
        if not available then return false end
        return value and {
            kind = "player",
            label = getOptionLabel(dialog.playerSelector, value),
            value = value,
        } or false
    end
    if targetType == "npc" then
        local value = dialog.npcSelector:GetValue()
        local available = false
        for _, actor in ipairs(addon.GameMasterService.GetActionNPCs()) do
            if (actor.id or actor.playerKey) == value and actor.released ~= false then available = true; break end
        end
        if not available then return false end
        return value and {
            kind = "npc",
            label = getOptionLabel(dialog.npcSelector, value),
            value = value,
        } or false
    end
    if targetType == "marker" then
        local value = dialog.markerSelector:GetValue()
        return value and {
            kind = "marker",
            label = getOptionLabel(dialog.markerSelector, value),
            value = value,
        } or false
    end
    local value = addon.Runtime.Trim(dialog.textField:GetText())
    return value and value ~= "" and {
        kind = "text",
        label = value,
        value = value,
    } or false
end

local function addCurrentTarget()
    setError(nil)
    local target = getCurrentTarget()
    if target == false or target == nil then
        setError(addon.L("GAMEMASTER_INVALID_TARGET"))
        return false
    end
    if #selectedTargets >= addon.Constants.GAMEMASTER_MAX_TARGETS then
        setError(addon.L(
            "GAMEMASTER_TARGET_LIMIT",
            addon.Constants.GAMEMASTER_MAX_TARGETS
        ))
        return false
    end
    local key = targetKey(target)
    for _, existing in ipairs(selectedTargets) do
        if targetKey(existing) == key then
            setError(addon.L("GAMEMASTER_TARGET_ALREADY_SELECTED"))
            return false
        end
    end
    selectedTargets[#selectedTargets + 1] = target
    if target.kind == "text" then
        dialog.textField:SetText("")
    end
    refreshSelectedTargets()
    return true
end

local function getTargetTypeOptions(hasMarkers, hasNPCs)
    local options = {}
    for _, option in ipairs(targetTypeOptions) do
        if (option.value ~= "marker" or hasMarkers)
            and (option.value ~= "npc" or hasNPCs) then
            options[#options + 1] = option
        end
    end
    return localizeOptions(options)
end

local function updateTargetVisibility()
    local action = dialog.actionSelector:GetValue()
    local targetType = dialog.targetTypeSelector:GetValue()
    local targetEnabled = action ~= "prepare"
    local aoe = targetEnabled and dialog.aoeCheck:GetChecked()

    dialog.aoeCheck:SetShown(targetEnabled)
    dialog.aoeCheck.label:SetShown(targetEnabled)
    dialog.targetTypeLabel:SetShown(targetEnabled)
    dialog.targetTypeSelector:SetShown(targetEnabled)
    dialog.playerSelector:SetShown(targetEnabled and targetType == "player")
    dialog.npcSelector:SetShown(targetEnabled and targetType == "npc")
    dialog.currentTarget:SetShown(targetEnabled and targetType == "player")
    dialog.textField:SetShown(targetEnabled and targetType == "text")
    dialog.historySelector:SetShown(
        targetEnabled and targetType == "text" and dialog.hasHistory
    )
    dialog.markerSelector:SetShown(targetEnabled and targetType == "marker")
    dialog.addTarget:SetShown(aoe and targetType ~= "none")
    dialog.selectedSection:SetShown(aoe)
    dialog.preparationCheck:SetShown(
        not dialog.npcActorID and action == "prepare" and dialog.castRounds > 0
    )
    dialog.preparationCheck.label:SetShown(
        not dialog.npcActorID and action == "prepare" and dialog.castRounds > 0
    )
end

local function refreshTargetOptions(selector, options)
    local previous = selector:GetValue()
    selector:SetOptions(options, previous)
     
     
    if dialog.targetsInitialized then selector:SetValue(previous, true) end
end

local function refreshTargets()
    local playerOptions = {}
    for _, member in ipairs(addon.GameMasterService.GetActionMembers()) do
        local label = string.format(
            "%s (%s)",
            member.rpName or member.gameName or member.playerID,
            member.gameName or member.playerID
        )
        if member.isMock then
            label = addon.L("GAMEMASTER_TEST_MEMBER_FORMAT", label)
        end
        playerOptions[#playerOptions + 1] = {
            color = member.profileColor,
            icon = member.profileIcon,
            label = label,
            value = member.playerID,
        }
    end
    refreshTargetOptions(dialog.playerSelector, playerOptions)

    local npcOptions = {}
    local service = addon.GameMasterService
    for _, actor in ipairs(type(service.GetActionNPCs) == "function"
        and service.GetActionNPCs() or {}) do
        if actor.released ~= false then
            local id = actor.id or actor.playerKey
            local label = actor.name or actor.rpName or id
            if actor.markerIndex then
                label = label .. " (" .. addon.GameMasterRoster.GetWorldMarkerLabel(actor.markerIndex) .. ")"
            else
                label = label .. " [" .. (id:match("(%d+)$") or id) .. "]"
            end
            npcOptions[#npcOptions + 1] = {
                label = label,
                value = id,
                color = actor.nameColor or actor.profileColor,
                icon = actor.icon or actor.profileIcon,
            }
        end
    end
    refreshTargetOptions(dialog.npcSelector, npcOptions)

    local markerOptions = {}
    for _, marker in ipairs(addon.GameMasterService.GetActionWorldMarkers()) do
        markerOptions[#markerOptions + 1] = {
            label = marker.label,
            value = marker.index,
        }
    end
    dialog.targetTypeSelector:SetOptions(
        getTargetTypeOptions(#markerOptions > 0 or dialog.targetTypeSelector:GetValue() == "marker",
            #npcOptions > 0 or dialog.targetTypeSelector:GetValue() == "npc"),
        dialog.targetTypeSelector:GetValue() or "none"
    )
    refreshTargetOptions(dialog.markerSelector, markerOptions)
    dialog.targetsInitialized = true

    local context = dialog.npcActorID
        and service.GetNPCSubmissionContext(dialog.npcActorID)
        or (not dialog.npcActorID and service.GetSubmissionContext())
    local historyOptions = {}
    for _, value in ipairs(addon.GameMasterPlayerState.GetTextTargets(
        context and context.sessionID
    )) do
        historyOptions[#historyOptions + 1] = { label = value, value = value }
    end
    dialog.historySelector:SetOptions(historyOptions)
    dialog.hasHistory = #historyOptions > 0
    updateTargetVisibility()
end

local function collectTargets(action)
    if action == "prepare" then
        return {}
    end
    if dialog.aoeCheck:GetChecked() then
        if #selectedTargets == 0 then
            local current = getCurrentTarget()
            if current == false then return nil end
            if current and current ~= false then
                selectedTargets[1] = current
            end
        end
        return selectedTargets
    end
    local current = getCurrentTarget()
    if current == false then
        return nil
    end
    return current and { current } or {}
end

local function isOpenedContext(context, opened)
    return context and opened and context.sessionID == opened.sessionID
        and context.roundID == opened.roundID and context.activationID == opened.activationID
        and context.phase == opened.phase
end

local function isPlayerOriginCurrent()
    local database = addon.Database
    if database and database.GetActiveProfileKey
        and database.GetActiveProfileKey() ~= dialog.playerProfileKey then return false end
    return not database or not database.GetActiveSpellbook
        or database.GetActiveSpellbook() == dialog.playerBook
end

local function submit(mode)
    setError(nil)
    if not dialog.npcActorID and (not isOpenedContext(
        addon.GameMasterService.GetSubmissionContext(), dialog.playerContext) or not isPlayerOriginCurrent()) then
        setError(addon.L("GAMEMASTER_DELAYED_CONTEXT_CHANGED"))
        return
    end
    local action = dialog.actionSelector:GetValue()
    local targets = collectTargets(action)
    if not targets then
        setError(addon.L("GAMEMASTER_INVALID_TARGET"))
        return
    end
    if dialog.npcActorID then
        local context = addon.GameMasterService.GetNPCSubmissionContext(dialog.npcActorID)
        local opened = dialog.npcContext
        if not isOpenedContext(context, opened) or context.npcRevision ~= opened.npcRevision then
            setError(addon.L("GAMEMASTER_NPC_CONTEXT_CHANGED"))
            return
        end
        local sent, errorMessage = addon.GameMasterService.SubmitNPC(
            dialog.npcActorID, selectedSpell.id, action, targets,
            { aoe = dialog.aoeCheck:GetChecked() == true, mode = mode, context = opened })
        if not sent then
            setError(errorMessage or addon.L("GAMEMASTER_INVALID_SUBMISSION"))
            return
        end
        dialog:Hide()
        return
    end
    addon.GameMasterPlayerState.SetSendAfterEmote(
        dialog.emoteCheck:GetChecked()
    )
    addon.GameMasterPlayerState.SetAutomatePreparation(
        dialog.preparationCheck:GetChecked()
    )
    local sent, errorMessage
    if dialog.emoteCheck:GetChecked() then
        sent, errorMessage = addon.GameMasterDelayedSubmission.Queue(
            selectedSpell,
            action,
            targets,
            dialog.aoeCheck:GetChecked(),
            mode
        )
    else
        sent, errorMessage = addon.GameMasterService.Submit(
            selectedSpell,
            action,
            targets,
            {
                aoe = dialog.aoeCheck:GetChecked(),
                mode = mode,
            }
        )
    end
    if not sent then
        setError(errorMessage)
        return
    end
    dialog:Hide()
    addon.GameMasterActionStatus.Open()
end

function addon.GameMasterActionDialog.GetTutorialTarget()
    if not dialog or not dialog:IsShown() or dialog.actionSelector:GetValue() == "prepare" then return nil end
    if dialog.aoeCheck:GetChecked() then return selectedTargets[1] end
    local target = getCurrentTarget()
    return target or nil
end

local function updateActionModeButtons()
    if not dialog then
        return
    end
    local service = addon.GameMasterService
    local context = dialog.npcActorID and service.GetNPCSubmissionContext(dialog.npcActorID)
        or (not dialog.npcActorID and service.GetSubmissionContext())
    local existing = context and context.lastSubmission
    if not dialog.npcActorID and addon.GameMasterDelayedSubmission
        and addon.GameMasterDelayedSubmission.GetProjectedSubmission then
        existing = addon.GameMasterDelayedSubmission.GetProjectedSubmission()
    end
    local actionCount = addon.GameMasterActionCollection.Count(existing)
    dialog.existingActionCount = actionCount
    dialog.existingPreparation = addon.GameMasterActionCollection.ContainsPreparation(existing)
    dialog.submitButton:SetText(addon.L(actionCount > 0 and "GAMEMASTER_REPLACE_ACTION" or "GAMEMASTER_SEND"))
    local canAppend = actionCount > 0
        and actionCount < addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER
        and dialog.existingPreparation ~= true
        and dialog.actionSelector:GetValue() ~= "prepare"
    dialog.addActionButton:SetShown(canAppend)
    dialog.addActionButton:SetEnabled(canAppend)
    dialog.cancelButton:ClearAllPoints()
    dialog.cancelButton:SetPoint(
        "RIGHT",
        canAppend and dialog.addActionButton or dialog.submitButton,
        "LEFT",
        -addon.Theme.Spacing.sm,
        0
    )
end

local function createDialog()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("GAMEMASTER_SUBMIT_ACTION"), 640, 570
    )

    local spellSection = addon.GameMasterWidgets.CreateSection(frame)
    spellSection:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -45)
    spellSection:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.lg, -45)
    spellSection:SetHeight(62)
    local icon = spellSection:CreateTexture(nil, "ARTWORK")
    icon:SetSize(44, 44)
    icon:SetPoint("LEFT", spellSection, "LEFT", theme.Spacing.sm, 0)
    local spellName = addon.UIFactory.CreateLabel(
        spellSection, theme.Fonts.header, "", theme.Colors.gold
    )
    spellName:SetPoint("TOPLEFT", icon, "TOPRIGHT", theme.Spacing.md, -2)
    local roundLabel = addon.UIFactory.CreateLabel(
        spellSection, theme.Fonts.small, "", theme.Colors.textMuted
    )
    roundLabel:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", theme.Spacing.md, 2)

    local actionLabel = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.body, addon.L("GAMEMASTER_ACTION"), theme.Colors.gold
    )
    actionLabel:SetPoint("TOPLEFT", spellSection, "BOTTOMLEFT", 0, -14)
    local actionSelector = addon.GameMasterWidgets.CreateSelector(frame, 250)
    actionSelector:SetPoint("TOPLEFT", actionLabel, "BOTTOMLEFT", 0, -3)
    actionSelector:SetOptions(localizeOptions(actionOptions), "cast")
    local aoeCheck = makeCheck(frame, addon.L("GAMEMASTER_AOE"))
    aoeCheck:SetPoint("LEFT", actionSelector, "RIGHT", 28, 0)

    local targetTypeLabel = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.body, addon.L("GAMEMASTER_TARGET_TYPE"), theme.Colors.gold
    )
    targetTypeLabel:SetPoint("TOPLEFT", actionSelector, "BOTTOMLEFT", 0, -14)
    local targetTypeSelector = addon.GameMasterWidgets.CreateSelector(frame, 250)
    targetTypeSelector:SetPoint("TOPLEFT", targetTypeLabel, "BOTTOMLEFT", 0, -3)
    targetTypeSelector:SetOptions(getTargetTypeOptions(false), "none")

    local playerSelector = addon.GameMasterWidgets.CreateSelector(frame, 225)
    playerSelector:SetPoint("LEFT", targetTypeSelector, "RIGHT", 12, 0)
    local currentTarget = addon.UIFactory.CreateButton(
        frame, addon.L("GAMEMASTER_CURRENT_WOW_TARGET"), 100
    )
    currentTarget:SetPoint("LEFT", playerSelector, "RIGHT", 5, 0)
    currentTarget:SetScript("OnClick", function()
        local name, realm = UnitFullName("target")
        if not name then
            setError(addon.L("GAMEMASTER_CURRENT_TARGET_INVALID"))
            return
        end
        local playerID = realm and realm ~= ""
            and string.format("%s-%s", name, realm)
            or name
        local member = addon.GameMasterRoster.FindMember(playerID)
        local available = false
        for _, candidate in ipairs(addon.GameMasterService.GetActionMembers()) do
            if member and candidate.playerID == member.playerID then available = true; break end
        end
        if not available then
            setError(addon.L("GAMEMASTER_CURRENT_TARGET_INVALID"))
            return
        end
        playerSelector:SetValue(member.playerID)
        setError(nil)
    end)
    local markerSelector = addon.GameMasterWidgets.CreateSelector(frame, 250)
    markerSelector:SetAllPoints(playerSelector)
    local npcSelector = addon.GameMasterWidgets.CreateSelector(frame, 225)
    npcSelector:SetAllPoints(playerSelector)
    local textField = addon.UIFactory.CreateEditBox(frame, false)
    textField:SetPoint("TOPLEFT", playerSelector, "TOPLEFT", 0, 0)
    textField:SetWidth(270)
    local historySelector = addon.GameMasterWidgets.CreateSelector(
        frame, 54, addon.L("GAMEMASTER_HISTORY_SHORT")
    )
    historySelector:SetPoint("LEFT", textField, "RIGHT", 6, 0)
    historySelector:SetOnValueChanged(function(value)
        if value then
            textField:SetText(value)
            textField:SetFocus()
        end
    end)

    local addTarget = addon.UIFactory.CreateButton(
        frame, addon.L("GAMEMASTER_ADD_TARGET"), 120
    )
    addTarget:SetPoint("TOPLEFT", targetTypeSelector, "BOTTOMLEFT", 0, -10)
    addTarget:SetScript("OnClick", addCurrentTarget)

    local selectedSection = addon.GameMasterWidgets.CreateSection(frame)
    selectedSection:SetPoint("TOPLEFT", addTarget, "BOTTOMLEFT", 0, -9)
    selectedSection:SetPoint("RIGHT", spellSection, "RIGHT", 0, 0)
    selectedSection:SetHeight(112)
    local selectedTitle = addon.UIFactory.CreateLabel(
        selectedSection, theme.Fonts.small,
        addon.L("GAMEMASTER_SELECTED_TARGETS"), theme.Colors.gold
    )
    selectedTitle:SetPoint("TOPLEFT", selectedSection, "TOPLEFT", 8, -7)
    local targetCount = addon.UIFactory.CreateLabel(
        selectedSection, theme.Fonts.small, "", theme.Colors.textMuted
    )
    targetCount:SetPoint("TOPRIGHT", selectedSection, "TOPRIGHT", -8, -7)
    local selectedTargetsLabel = addon.UIFactory.CreateLabel(
        selectedSection, theme.Fonts.small, "", theme.Colors.text
    )
    selectedTargetsLabel:SetPoint("TOPLEFT", selectedTitle, "BOTTOMLEFT", 0, -5)
    selectedTargetsLabel:SetPoint("BOTTOMRIGHT", selectedSection, "BOTTOMRIGHT", -190, 8)
    selectedTargetsLabel:SetJustifyV("TOP")
    local removeTarget = addon.UIFactory.CreateButton(
        selectedSection, addon.L("GAMEMASTER_REMOVE_LAST_TARGET"), 160
    )
    removeTarget:SetPoint("BOTTOMRIGHT", selectedSection, "BOTTOMRIGHT", -8, 35)
    removeTarget:SetScript("OnClick", function()
        table.remove(selectedTargets)
        refreshSelectedTargets()
    end)
    local clearTargets = addon.UIFactory.CreateButton(
        selectedSection, addon.L("GAMEMASTER_CLEAR_TARGETS"), 160
    )
    clearTargets:SetPoint("BOTTOMRIGHT", selectedSection, "BOTTOMRIGHT", -8, 8)
    clearTargets:SetScript("OnClick", function()
        selectedTargets = {}
        refreshSelectedTargets()
    end)

    local emoteCheck = makeCheck(frame, addon.L("GAMEMASTER_SEND_AFTER_EMOTE"))
    emoteCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", theme.Spacing.lg, 80)
    local preparationCheck = makeCheck(
        frame, addon.L("GAMEMASTER_AUTOMATE_PREPARATION")
    )
    preparationCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", theme.Spacing.lg, 54)
    emoteCheck:SetScript("OnClick", function(self)
        addon.GameMasterPlayerState.SetSendAfterEmote(self:GetChecked())
    end)
    preparationCheck:SetScript("OnClick", function(self)
        addon.GameMasterPlayerState.SetAutomatePreparation(self:GetChecked())
    end)

    local errorLabel = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.small, "", theme.Colors.error
    )
    errorLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", theme.Spacing.lg, 35)
    errorLabel:SetPoint("RIGHT", frame, "RIGHT", -250, 0)

    local submitButton = addon.UIFactory.CreateButton(
        frame, addon.L("GAMEMASTER_SEND"), 120
    )
    submitButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)
    submitButton:SetScript("OnClick", function()
        submit("replace")
    end)
    local addActionButton = addon.UIFactory.CreateButton(
        frame, addon.L("GAMEMASTER_ADD_ACTION"), 120
    )
    addActionButton:SetPoint(
        "RIGHT", submitButton, "LEFT", -theme.Spacing.sm, 0
    )
    addActionButton:SetScript("OnClick", function()
        submit("append")
    end)
    local cancelButton = addon.UIFactory.CreateButton(frame, addon.L("CANCEL"), 110)
    cancelButton:SetPoint(
        "RIGHT", addActionButton, "LEFT", -theme.Spacing.sm, 0
    )
    cancelButton:SetScript("OnClick", function() frame:Hide() end)

    frame.actionSelector = actionSelector
    frame.addActionButton = addActionButton
    frame.addTarget = addTarget
    frame.aoeCheck = aoeCheck
    frame.castRounds = 0
    frame.cancelButton = cancelButton
    frame.clearTargets = clearTargets
    frame.currentTarget = currentTarget
    frame.emoteCheck = emoteCheck
    frame.errorLabel = errorLabel
    frame.historySelector = historySelector
    frame.hasHistory = false
    frame.icon = icon
    frame.markerSelector = markerSelector
    frame.npcSelector = npcSelector
    frame.playerSelector = playerSelector
    frame.preparationCheck = preparationCheck
    frame.removeTarget = removeTarget
    frame.roundLabel = roundLabel
    frame.selectedSection = selectedSection
    frame.selectedTargets = selectedTargetsLabel
    frame.spellName = spellName
    frame.submitButton = submitButton
    frame.targetCount = targetCount
    frame.targetTypeLabel = targetTypeLabel
    frame.targetTypeSelector = targetTypeSelector
    frame.textField = textField

    actionSelector:SetOnValueChanged(function()
        updateTargetVisibility()
        updateActionModeButtons()
    end)
    targetTypeSelector:SetOnValueChanged(updateTargetVisibility)
    aoeCheck:SetScript("OnClick", updateTargetVisibility)
    frame:RegisterEvent("RAID_TARGET_UPDATE")
    frame:SetScript("OnEvent", function(self)
        if self:IsShown() then refreshTargets() end
    end)
    return frame
end

function addon.GameMasterActionDialog.Open(spell, options)
    options = type(options) == "table" and options or {}
    local npcActorID = options.npcActorID
    local service = addon.GameMasterService
    local context
    if npcActorID then
        if type(service.GetNPCSubmissionContext) ~= "function"
            or type(service.SubmitNPC) ~= "function"
            or not service.CanSubmitNPC(npcActorID) then return false end
        context = service.GetNPCSubmissionContext(npcActorID)
        if not context or options.npcSessionID and context.sessionID ~= options.npcSessionID then return false end
    elseif not service.CanSubmit() then
        return false
    else
        context = service.GetSubmissionContext()
    end
    if type(spell) ~= "table" then
        return false
    end
    dialog = dialog or createDialog()
    dialog.npcActorID = npcActorID
    local opened
    if context then
        opened = {}
        for key, value in pairs(context) do opened[key] = value end
    end
    dialog.npcContext = npcActorID and opened or nil
    dialog.playerContext = not npcActorID and opened or nil
    local database = addon.Database
    dialog.playerProfileKey = not npcActorID and database and database.GetActiveProfileKey
        and database.GetActiveProfileKey() or nil
    dialog.playerBook = not npcActorID and database and database.GetActiveSpellbook
        and database.GetActiveSpellbook() or nil
    dialog.targetsInitialized = false
    dialog.playerSelector:SetValue(nil, true)
    dialog.npcSelector:SetValue(nil, true)
    dialog.markerSelector:SetValue(nil, true)
    selectedSpell = spell
    selectedTargets = {}
    dialog.castRounds = addon.SpellPresentation.GetCastRounds(spell) or 0
    local preparationReady = options.preparationReady == true
    local availableActions = preparationReady
        and readyActionOptions
        or (dialog.castRounds > 0 and actionOptions or immediateActionOptions)
    local selectedAction = preparationReady
        and "cast"
        or (options.forcedAction or "cast")
    if selectedAction == "prepare" and dialog.castRounds < 1 then
        selectedAction = "cast"
    end
    local actionCount = context
        and addon.GameMasterActionCollection.Count(context.lastSubmission)
        or 0
    setSpellIcon(dialog.icon, spell)
    dialog.spellName:SetText(spell.name or addon.L("UNKNOWN_ABILITY"))
    dialog.roundLabel:SetText(addon.L(
        "GAMEMASTER_ROUND_LABEL",
        context and context.roundNumber or 0,
        context and context.sessionName or ""
    ))
    if npcActorID then
        local actor = service.GetNPCActor(npcActorID, context.sessionID)
        dialog.roundLabel:SetText((actor and actor.name or npcActorID)
            .. " | " .. dialog.roundLabel:GetText())
    end
    dialog.actionSelector:SetOptions(
        localizeOptions(availableActions),
        selectedAction
    )
    dialog.actionSelector:SetValue(selectedAction, true)
    dialog.actionSelector:SetEnabled(not preparationReady)
    local tutorial = service.IsTutorialActive and service.IsTutorialActive()
    dialog.targetTypeSelector:SetValue(
        service.IsTestMode() and not tutorial and "player" or "none",
        true
    )
    dialog.textField:SetText("")
    dialog.aoeCheck:SetChecked(false)
    dialog.emoteCheck:SetChecked(
        not npcActorID and not tutorial and addon.GameMasterPlayerState.ShouldSendAfterEmote()
    )
    dialog.preparationCheck:SetChecked(
        not npcActorID and addon.GameMasterPlayerState.ShouldAutomatePreparation()
    )
    dialog.emoteCheck:SetShown(not npcActorID)
    dialog.emoteCheck:SetEnabled(true)
    dialog.emoteCheck.label:SetShown(not npcActorID)
    dialog.existingActionCount = actionCount
    dialog.existingPreparation =
        addon.GameMasterActionCollection.ContainsPreparation(
            context and context.lastSubmission
        )
    dialog.preparationReady = preparationReady
    dialog.submitButton:SetText(actionCount > 0
        and addon.L("GAMEMASTER_REPLACE_ACTION")
        or addon.L("GAMEMASTER_SEND"))
    updateActionModeButtons()
    refreshTargets()
    refreshSelectedTargets()
    updateTargetVisibility()
    setError(nil)
    dialog:Show()
    addon.UIFactory.BringToFront(dialog)
    return true
end

addon.GameMasterService.RegisterListener(function(reason)
    if dialog and dialog:IsShown() and (reason == "npcs" or reason == "visibility") then refreshTargets() end
    if dialog and dialog:IsShown() then updateActionModeButtons() end
end)

addon.GameMasterDelayedSubmission.RegisterListener(function()
    if dialog and dialog:IsShown() then updateActionModeButtons() end
end)
