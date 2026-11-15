local _, addon = ...
addon = addon.Shared or addon

addon.GameMasterSceneSettingsDialog = {}

local dialog
function addon.GameMasterSceneSettingsDialog.GetTutorialContext() return dialog end

local function updateNPCSummary()
    if not dialog or not dialog.npcSummary then return end
    local pending = #(dialog.pendingNPCs or {})
    local count = pending
    if dialog.sessionID and type(addon.GameMasterService.ListNPCs) == "function" then
        count = count + #(addon.GameMasterService.ListNPCs(dialog.sessionID) or {})
    end
    dialog.npcSummary:SetText(addon.L("GAMEMASTER_NPC_SCENE_COUNT", count))
end

local visibilityOptions = {
    { labelKey = "GAMEMASTER_VISIBILITY_FULL", value = "full" },
    { labelKey = "GAMEMASTER_VISIBILITY_TARGETS", value = "targets" },
    { labelKey = "GAMEMASTER_VISIBILITY_HIDDEN", value = "hidden" },
}

local function createCheck(parent, label)
    local check = CreateFrame(
        "CheckButton",
        nil,
        parent,
        "UICheckButtonTemplate"
    )
    local text = addon.UIFactory.CreateLabel(
        check,
        addon.Theme.Fonts.small,
        label,
        addon.Theme.Colors.text
    )
    text:SetPoint("LEFT", check, "RIGHT", 0, 0)
    check.label = text
    return check
end

local function getMemberOptions()
    local options = {}
    for _, member in ipairs(addon.GameMasterRoster.GetMembers()) do
        options[#options + 1] = {
            label = string.format(
                "%s (%s)",
                member.rpName or member.gameName or member.playerID,
                member.playerID
            ),
            value = member.playerID,
        }
    end
    table.sort(options, function(left, right)
        return left.label < right.label
    end)
    return options
end

local function getVisibilityOptions()
    local options = {}
    for _, option in ipairs(visibilityOptions) do
        options[#options + 1] = {
            label = addon.L(option.labelKey),
            value = option.value,
        }
    end
    return options
end

local function setPage(page)
    if not dialog then
        return
    end
    local assistants = page == "assistants"
    dialog.assistantPage:SetShown(assistants)
    dialog.visibilityPage:SetShown(page == "visibility")
    dialog.flowPage:SetShown(page == "flow")
    dialog.assistantTab:SetEnabled(not assistants)
    dialog.visibilityTab:SetEnabled(page ~= "visibility")
    dialog.flowTab:SetEnabled(page ~= "flow")
end

local function configureMemberSelector(row, options)
    row.memberSelector:SetOptions(options)
    row.memberSelector:SetValue(nil, true)
    row.memberSelector:SetOnValueChanged(function(playerID)
        if playerID then
            row.playerField:SetText(playerID)
        end
    end)
end

local function setAssistantRow(row, entry)
    row.playerField:SetText(entry and entry.playerID or "")
    row.memberSelector:SetValue(nil, true)
    row.rounds:SetChecked(
        not entry or entry.rights.rounds == true
    )
    row.participants:SetChecked(
        not entry or entry.rights.participants == true
    )
    row.visibility:SetChecked(
        not entry or entry.rights.visibility == true
    )
end

local function setVisibilityRow(row, entry)
    row.playerField:SetText(entry and entry.playerID or "")
    row.memberSelector:SetValue(nil, true)
    row.visibilitySelector:SetValue(
        entry and entry.visibility or "hidden",
        true
    )
end

local function populate(name, access, options, locked)
    local memberOptions = getMemberOptions()
    dialog.nameField:SetText(name or "")
    dialog.errorLabel:SetText("")
    dialog.defaultVisibility:SetOptions(getVisibilityOptions())
    dialog.defaultVisibility:SetValue(
        access.defaultVisibility,
        true
    )

    for index, row in ipairs(dialog.assistantRows) do
        configureMemberSelector(row, memberOptions)
        setAssistantRow(row, access.assistants[index])
    end
    for index, row in ipairs(dialog.visibilityRows) do
        configureMemberSelector(row, memberOptions)
        row.visibilitySelector:SetOptions(getVisibilityOptions())
        setVisibilityRow(row, access.visibilityOverrides[index])
    end
    dialog.encounterOptions:SetOptions(options, locked)
    setPage("flow")
end

local function collectPlayers(rows, buildEntry)
    local entries = {}
    local seen = {}
    for _, row in ipairs(rows) do
        local raw = addon.Runtime.Trim(row.playerField:GetText())
        if raw and raw ~= "" then
            local playerID, playerKey =
                addon.Runtime.NormalizeFullPlayerID(raw)
            if not playerID then
                return nil, addon.L(
                    "GAMEMASTER_SCENE_INVALID_PLAYER",
                    raw
                )
            end
            if seen[playerKey] then
                return nil, addon.L(
                    "GAMEMASTER_SCENE_DUPLICATE_PLAYER",
                    playerID
                )
            end
            seen[playerKey] = true
            entries[#entries + 1] = buildEntry(
                row,
                playerID,
                playerKey
            )
        end
    end
    return entries
end

local function save()
    local name = addon.Runtime.Trim(dialog.nameField:GetText())
    if not name or name == "" then
        dialog.errorLabel:SetText(
            addon.L("GAMEMASTER_INVALID_SESSION_NAME")
        )
        return
    end

    local assistants, assistantError = collectPlayers(
        dialog.assistantRows,
        function(row, playerID, playerKey)
            return {
                playerID = playerID,
                playerKey = playerKey,
                rights = {
                    participants =
                        row.participants:GetChecked() == true,
                    rounds = row.rounds:GetChecked() == true,
                    visibility =
                        row.visibility:GetChecked() == true,
                },
            }
        end
    )
    if not assistants then
        dialog.errorLabel:SetText(assistantError)
        return
    end

    local localKey = addon.Runtime.NormalizePlayerID(
        addon.GameMasterRoster.GetLocalPlayerID()
    )
    for _, assistant in ipairs(assistants) do
        if assistant.playerKey == localKey then
            dialog.errorLabel:SetText(
                addon.L("GAMEMASTER_SCENE_PRIMARY_ASSISTANT")
            )
            return
        end
    end
    local overrides, visibilityError = collectPlayers(
        dialog.visibilityRows,
        function(row, playerID, playerKey)
            return {
                playerID = playerID,
                playerKey = playerKey,
                visibility =
                    row.visibilitySelector:GetValue() or "hidden",
            }
        end
    )
    if not overrides then
        dialog.errorLabel:SetText(visibilityError)
        return
    end

    local access = {
        assistants = assistants,
        defaultVisibility =
            dialog.defaultVisibility:GetValue() or "hidden",
        visibilityOverrides = overrides,
    }
    local success, result
    if dialog.sessionID then
        success, result =
            addon.GameMasterService.UpdateSessionSettings(
                dialog.sessionID,
                name,
                access,
                dialog.encounterOptions:GetOptions()
            )
    else
        success, result = addon.GameMasterService.CreateSession(
            name,
            access,
            dialog.encounterOptions:GetOptions()
        )
    end
    if not success then
        dialog.errorLabel:SetText(
            result or addon.L("GAMEMASTER_SESSION_NOT_FOUND")
        )
        return
    end

    if #(dialog.pendingNPCs or {}) > 0 then
        local sessionID = type(result) == "table" and result.id or dialog.sessionID
        if not sessionID or type(addon.GameMasterService.AddNPCToSession) ~= "function" then
            dialog.errorLabel:SetText(addon.L("GAMEMASTER_NPC_UNAVAILABLE"))
            return
        end
         
        dialog.sessionID = sessionID
        while #dialog.pendingNPCs > 0 do
            local actor, err = addon.GameMasterService.AddNPCToSession(dialog.pendingNPCs[1], sessionID)
            if not actor then
                dialog.errorLabel:SetText(err or addon.L("GAMEMASTER_NPC_UNAVAILABLE"))
                updateNPCSummary()
                return
            end
            table.remove(dialog.pendingNPCs, 1)
        end
    end

    local callback = dialog.onSaved
    dialog.onSaved = nil
    dialog:Hide()
    if type(callback) == "function" then
        callback(result)
    end
end

local function createAssistantPage(parent)
    local theme = addon.Theme
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local help = addon.UIFactory.CreateLabel(
        page,
        theme.Fonts.small,
        addon.L("GAMEMASTER_SCENE_ASSISTANTS_HELP"),
        theme.Colors.textMuted
    )
    help:SetPoint("TOPLEFT", page, "TOPLEFT", theme.Spacing.sm, -8)
    help:SetPoint("RIGHT", page, "RIGHT", -theme.Spacing.sm, 0)
    help:SetWordWrap(true)

    local rows = {}
    for index = 1, addon.Constants.GAMEMASTER_MAX_ASSISTANTS do
        local row = addon.GameMasterWidgets.CreateSection(
            page,
            index % 2 == 0
                and theme.Colors.archiveRow
                or theme.Colors.dark
        )
        row:SetPoint(
            "TOPLEFT",
            page,
            "TOPLEFT",
            theme.Spacing.sm,
            -55 - ((index - 1) * 72)
        )
        row:SetPoint("RIGHT", page, "RIGHT", -theme.Spacing.sm, 0)
        row:SetHeight(66)

        local playerField = addon.UIFactory.CreateEditBox(row, false)
        playerField:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -7)
        playerField:SetWidth(270)

        local selector = addon.GameMasterWidgets.CreateSelector(
            row,
            250,
            addon.L("GAMEMASTER_SCENE_SELECT_MEMBER")
        )
        selector:SetPoint("LEFT", playerField, "RIGHT", 8, 0)

        local clear = addon.UIFactory.CreateButton(row, "X", 30)
        clear:SetPoint("LEFT", selector, "RIGHT", 6, 0)
        clear:SetScript("OnClick", function()
            setAssistantRow(row, nil)
        end)

        local rounds = createCheck(
            row,
            addon.L("GAMEMASTER_ASSISTANT_RIGHT_ROUNDS")
        )
        rounds:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 4)
        local participants = createCheck(
            row,
            addon.L("GAMEMASTER_ASSISTANT_RIGHT_PARTICIPANTS")
        )
        participants:SetPoint("LEFT", rounds, "LEFT", 150, 0)
        local visibility = createCheck(
            row,
            addon.L("GAMEMASTER_ASSISTANT_RIGHT_VISIBILITY")
        )
        visibility:SetPoint("LEFT", rounds, "LEFT", 335, 0)

        row.memberSelector = selector
        row.participants = participants
        row.playerField = playerField
        row.rounds = rounds
        row.visibility = visibility
        rows[index] = row
    end
    return page, rows
end

local function createVisibilityPage(parent)
    local theme = addon.Theme
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local defaultLabel = addon.UIFactory.CreateLabel(
        page,
        theme.Fonts.body,
        addon.L("GAMEMASTER_SCENE_DEFAULT_VISIBILITY"),
        theme.Colors.gold
    )
    defaultLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -14)
    local defaultVisibility = addon.GameMasterWidgets.CreateSelector(
        page,
        250,
        addon.L("GAMEMASTER_VISIBILITY_HIDDEN")
    )
    defaultVisibility:SetPoint("LEFT", defaultLabel, "RIGHT", 12, 0)

    local help = addon.UIFactory.CreateLabel(
        page,
        theme.Fonts.small,
        addon.L("GAMEMASTER_SCENE_VISIBILITY_HELP"),
        theme.Colors.textMuted
    )
    help:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -50)
    help:SetPoint("RIGHT", page, "RIGHT", -10, 0)
    help:SetWordWrap(true)

    local rows = {}
    for index = 1, addon.Constants.GAMEMASTER_MAX_ASSISTANTS do
        local row = addon.GameMasterWidgets.CreateSection(
            page,
            index % 2 == 0
                and theme.Colors.archiveRow
                or theme.Colors.dark
        )
        row:SetPoint(
            "TOPLEFT",
            page,
            "TOPLEFT",
            10,
            -92 - ((index - 1) * 58)
        )
        row:SetPoint("RIGHT", page, "RIGHT", -10, 0)
        row:SetHeight(52)

        local playerField = addon.UIFactory.CreateEditBox(row, false)
        playerField:SetPoint("LEFT", row, "LEFT", 8, 0)
        playerField:SetWidth(230)
        local selector = addon.GameMasterWidgets.CreateSelector(
            row,
            210,
            addon.L("GAMEMASTER_SCENE_SELECT_MEMBER")
        )
        selector:SetPoint("LEFT", playerField, "RIGHT", 8, 0)
        local visibility = addon.GameMasterWidgets.CreateSelector(
            row,
            160,
            addon.L("GAMEMASTER_VISIBILITY_HIDDEN")
        )
        visibility:SetPoint("LEFT", selector, "RIGHT", 8, 0)
        local clear = addon.UIFactory.CreateButton(row, "X", 30)
        clear:SetPoint("LEFT", visibility, "RIGHT", 6, 0)
        clear:SetScript("OnClick", function()
            setVisibilityRow(row, nil)
        end)

        row.memberSelector = selector
        row.playerField = playerField
        row.visibilitySelector = visibility
        rows[index] = row
    end
    return page, rows, defaultVisibility
end

local function createDialog()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("GAMEMASTER_SCENE_SETTINGS_TITLE"),
        720,
        610
    )

    local nameLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("GAMEMASTER_SESSION_NAME"),
        theme.Colors.gold
    )
    nameLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -48)
    local nameField = addon.UIFactory.CreateEditBox(frame, false)
    nameField:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    nameField:SetPoint("RIGHT", frame, "RIGHT", -18, 0)

    local assistantTab = addon.UIFactory.CreateButton(
        frame,
        addon.L("GAMEMASTER_SCENE_ASSISTANTS_TAB"),
        180
    )
    assistantTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -84)
    local visibilityTab = addon.UIFactory.CreateButton(
        frame,
        addon.L("GAMEMASTER_SCENE_VISIBILITY_TAB"),
        180
    )
    visibilityTab:SetPoint("LEFT", assistantTab, "RIGHT", 8, 0)
    local flowTab = addon.UIFactory.CreateButton(frame,
        addon.L("GAMEMASTER_SCENE_FLOW_TAB"), 180)
    flowTab:SetPoint("LEFT", visibilityTab, "RIGHT", 8, 0)

    local content = addon.GameMasterWidgets.CreateSection(frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -120)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 66)

    local assistantPage, assistantRows =
        createAssistantPage(content)
    local visibilityPage, visibilityRows, defaultVisibility =
        createVisibilityPage(content)
    local flowPage = CreateFrame("Frame", nil, content)
    flowPage:SetAllPoints()
    local encounterOptions = addon.GameMasterWidgets.CreateEncounterOptions(flowPage)
    encounterOptions:SetPoint("TOPLEFT", flowPage, "TOPLEFT", 12, -12)
    encounterOptions:SetPoint("RIGHT", flowPage, "RIGHT", -12, 0)
    local npcButton = addon.UIFactory.CreateButton(flowPage, addon.L("GAMEMASTER_NPC_ADD"), 146)
    npcButton:SetEnabled(addon.GameMasterNPCDialog ~= nil)
    npcButton:SetPoint("TOPLEFT", encounterOptions, "BOTTOMLEFT", 0, -16)
    local npcSummary = addon.UIFactory.CreateLabel(flowPage, theme.Fonts.small, "", theme.Colors.textMuted)
    npcSummary:SetPoint("LEFT", npcButton, "RIGHT", 12, 0)
    npcSummary:SetPoint("RIGHT", flowPage, "RIGHT", -12, 0)
    npcSummary:SetWordWrap(false)
    npcButton:SetScript("OnClick", function()
        if dialog.sessionID and #(dialog.pendingNPCs or {}) == 0 then
            addon.GameMasterNPCDialog.Open(dialog.sessionID)
        else
            addon.GameMasterNPCDialog.OpenDraft(dialog.pendingNPCs, updateNPCSummary)
        end
    end)
    flowTab:SetScript("OnClick", function() setPage("flow") end)

    assistantTab:SetScript("OnClick", function()
        setPage("assistants")
    end)
    visibilityTab:SetScript("OnClick", function()
        setPage("visibility")
    end)

    local saveButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("SAVE"),
        120
    )
    saveButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 20)
    saveButton:SetScript("OnClick", save)
    local cancelButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("CANCEL"),
        120
    )
    cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -8, 0)
    cancelButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local errorLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.small,
        "",
        theme.Colors.error
    )
    errorLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 26)
    errorLabel:SetPoint("RIGHT", cancelButton, "LEFT", -10, 0)
    errorLabel:SetWordWrap(false)

    frame.assistantPage = assistantPage
    frame.assistantRows = assistantRows
    frame.assistantTab = assistantTab
    frame.defaultVisibility = defaultVisibility
    frame.errorLabel = errorLabel
    frame.nameField = nameField
    frame.saveButton = saveButton
    frame.visibilityPage = visibilityPage
    frame.visibilityRows = visibilityRows
    frame.visibilityTab = visibilityTab
    frame.flowPage = flowPage
    frame.flowTab = flowTab
    frame.encounterOptions = encounterOptions
    frame.npcSummary = npcSummary
    frame:HookScript("OnHide", function()
        if addon.GameMasterNPCDialog then addon.GameMasterNPCDialog.HideDraft(frame.pendingNPCs) end
    end)
    return frame
end

function addon.GameMasterSceneSettingsDialog.OpenCreate(
    initialName,
    onSaved,
    initialOptions
)
    if not addon.GameMasterService.CanControl() then
        return false
    end
    dialog = dialog or createDialog()
    if addon.GameMasterNPCDialog then addon.GameMasterNPCDialog.HideDraft(dialog.pendingNPCs) end
    dialog.sessionID = nil
    dialog.pendingNPCs = {}
    dialog.onSaved = onSaved
    dialog.title:SetText(addon.L("GAMEMASTER_SCENE_CREATE_TITLE"))
    populate(initialName, {
        assistants = {},
        defaultVisibility =
            addon.GameMasterSettings.GetDefaultVisibility(),
        visibilityOverrides = {},
    }, initialOptions)
    updateNPCSummary()
    dialog:Show()
    addon.UIFactory.BringToFront(dialog)
    return true
end

function addon.GameMasterSceneSettingsDialog.OpenEdit(
    sessionID,
    onSaved
)
    local session = addon.GameMasterService.GetActiveSession()
    if not session or session.id ~= sessionID then session = addon.GameMasterStore.GetSession(sessionID) end
    local access = addon.GameMasterService.GetSceneAccess(sessionID)
    if not session or not access then
        return false
    end
    dialog = dialog or createDialog()
    if addon.GameMasterNPCDialog then addon.GameMasterNPCDialog.HideDraft(dialog.pendingNPCs) end
    dialog.sessionID = sessionID
    dialog.pendingNPCs = {}
    dialog.onSaved = onSaved
    dialog.title:SetText(addon.L("GAMEMASTER_SCENE_SETTINGS_TITLE"))
    populate(session.name, access,
        addon.GameMasterService.GetEncounterOptions(sessionID), session.currentRoundID ~= nil)
    updateNPCSummary()
    dialog:Show()
    addon.UIFactory.BringToFront(dialog)
    return true
end

addon.GameMasterService.RegisterListener(function()
    if dialog and dialog:IsShown() then updateNPCSummary() end
end)
