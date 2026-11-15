local _, addon = ...
addon = addon.Shared or addon

addon.GameMasterSessionDialog = {}

local dialog
local currentPage = 1
local sessionsPerPage = 7

local function setError(message)
    dialog.errorLabel:SetText(message or "")
end

local function formatTimestamp(timestamp)
    if type(date) == "function" then
        local success, value = pcall(
            date,
            "%Y-%m-%d %H:%M",
            tonumber(timestamp) or 0
        )
        if success and type(value) == "string" then
            return value
        end
    end
    return tostring(timestamp or "")
end

local function refresh()
    local sessions = addon.GameMasterService.ListSessions()
    local pageCount = math.max(1, math.ceil(#sessions / sessionsPerPage))
    currentPage = math.max(1, math.min(currentPage, pageCount))
    local first = ((currentPage - 1) * sessionsPerPage) + 1

    for rowIndex, row in ipairs(dialog.rows) do
        local session = sessions[first + rowIndex - 1]
        row.sessionID = session and session.id or nil
        if session then
            row.name:SetText(session.name)
            row.meta:SetText(addon.L(
                "GAMEMASTER_SESSION_META",
                #session.rounds,
                formatTimestamp(session.updatedAt)
            ))
            row:Show()
        else
            row:Hide()
        end
    end

    dialog.empty:SetShown(#sessions == 0)
    dialog.page:SetText(string.format("%d / %d", currentPage, pageCount))
    addon.GameMasterWidgets.SetEnabled(dialog.previous, currentPage > 1)
    addon.GameMasterWidgets.SetEnabled(dialog.next, currentPage < pageCount)
end

local function createSession()
    setError(nil)
    addon.GameMasterSceneSettingsDialog.OpenCreate(
        dialog.nameField:GetText(),
        function()
            dialog:Hide()
        end
    )
end

local function editSession(sessionID)
    setError(nil)
    if not addon.GameMasterSceneSettingsDialog.OpenEdit(
        sessionID,
        refresh
    ) then
        setError(addon.L("GAMEMASTER_SESSION_NOT_FOUND"))
    end
end

local function resumeSession(sessionID)
    setError(nil)
    local success, errorMessage = addon.GameMasterService.ActivateSession(
        sessionID
    )
    if not success then
        setError(errorMessage)
        return
    end
    dialog:Hide()
end

local function deleteSession(sessionID)
    local session = addon.GameMasterStore.GetSession(sessionID)
    if not session then
        refresh()
        return
    end
    dialog:Hide()
    addon.UIFactory.ShowConfirmation(
        addon.L("GAMEMASTER_DELETE_SESSION"),
        addon.L("GAMEMASTER_DELETE_SESSION_CONFIRM", session.name),
        function()
            local deleted, errorMessage = addon.GameMasterService.DeleteSession(
                sessionID
            )
            dialog:Show()
            if not deleted then
                setError(errorMessage)
            end
            refresh()
        end,
        function()
            dialog:Show()
        end
    )
end

local function createDialog()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("GAMEMASTER_SESSIONS"),
        560,
        490
    )

    local intro = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("GAMEMASTER_SESSION_DIALOG_HINT"),
        theme.Colors.textMuted
    )
    intro:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -48)
    intro:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.lg, -48)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)

    local nameLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("GAMEMASTER_SESSION_NAME"),
        theme.Colors.gold
    )
    nameLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -92)

    local nameField = addon.UIFactory.CreateEditBox(frame, false)
    nameField:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    nameField:SetWidth(390)

    local createButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("GAMEMASTER_CREATE_SESSION"),
        122
    )
    createButton:SetPoint("LEFT", nameField, "RIGHT", theme.Spacing.sm, 0)
    createButton:SetScript("OnClick", createSession)

    local list = addon.GameMasterWidgets.CreateSection(frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -145)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, 62)

    local rows = {}
    for index = 1, sessionsPerPage do
        local row = addon.GameMasterWidgets.CreateSection(
            list,
            theme.Colors.archiveRow
        )
        row:SetPoint(
            "TOPLEFT",
            list,
            "TOPLEFT",
            theme.Spacing.sm,
            -theme.Spacing.sm - ((index - 1) * 43)
        )
        row:SetPoint("RIGHT", list, "RIGHT", -theme.Spacing.sm, 0)
        row:SetHeight(38)

        local name = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.body,
            "",
            theme.Colors.text
        )
        name:SetPoint("TOPLEFT", row, "TOPLEFT", theme.Spacing.sm, -theme.Spacing.xs)
        name:SetPoint("RIGHT", row, "RIGHT", -225, 0)
        name:SetWordWrap(false)

        local meta = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.small,
            "",
            theme.Colors.textMuted
        )
        meta:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", theme.Spacing.sm, theme.Spacing.xs)
        meta:SetPoint("RIGHT", name, "RIGHT", 0, 0)
        meta:SetWordWrap(false)

        local settings = addon.UIFactory.CreateTextureButton(
            row,
            "Interface\\Buttons\\UI-OptionsButton",
            28
        )
        settings:SetPoint("RIGHT", row, "RIGHT", -166, 0)
        settings:SetScript("OnClick", function()
            if row.sessionID then
                editSession(row.sessionID)
            end
        end)
        settings.tooltipText = addon.L("GAMEMASTER_SCENE_EDIT_HELP")

        local resume = addon.UIFactory.CreateButton(
            row,
            addon.L("GAMEMASTER_RESUME"),
            100
        )
        resume:SetPoint("RIGHT", row, "RIGHT", -44, 0)
        resume:SetScript("OnClick", function()
            if row.sessionID then
                resumeSession(row.sessionID)
            end
        end)

        local delete = addon.UIFactory.CreateButton(row, "X", 30)
        delete:SetPoint("LEFT", resume, "RIGHT", theme.Spacing.xs, 0)
        delete:SetScript("OnClick", function()
            if row.sessionID then
                deleteSession(row.sessionID)
            end
        end)

        row.name = name
        row.meta = meta
        rows[index] = row
    end

    local empty = addon.UIFactory.CreateLabel(
        list,
        theme.Fonts.body,
        addon.L("GAMEMASTER_NO_SESSIONS"),
        theme.Colors.textMuted
    )
    empty:SetPoint("CENTER")

    local previous = addon.UIFactory.CreateButton(frame, "<", 34)
    previous:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", theme.Spacing.lg, theme.Spacing.lg)
    previous:SetScript("OnClick", function()
        currentPage = currentPage - 1
        refresh()
    end)
    local page = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, "", theme.Colors.text)
    page:SetPoint("LEFT", previous, "RIGHT", theme.Spacing.sm, 0)
    local nextButton = addon.UIFactory.CreateButton(frame, ">", 34)
    nextButton:SetPoint("LEFT", page, "RIGHT", theme.Spacing.sm, 0)
    nextButton:SetScript("OnClick", function()
        currentPage = currentPage + 1
        refresh()
    end)

    local errorLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.small,
        "",
        theme.Colors.error
    )
    errorLabel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, 23)
    errorLabel:SetPoint("LEFT", nextButton, "RIGHT", theme.Spacing.md, 0)
    errorLabel:SetJustifyH("RIGHT")

    frame.empty = empty
    frame.errorLabel = errorLabel
    frame.nameField = nameField
    frame.next = nextButton
    frame.page = page
    frame.previous = previous
    frame.rows = rows
    return frame
end

function addon.GameMasterSessionDialog.Open()
    if not addon.GameMasterService.CanControl() then
        addon.Logger.Error(addon.L("GAMEMASTER_LEADER_ONLY"))
        return false
    end
    dialog = dialog or createDialog()
    currentPage = 1
    dialog.nameField:SetText("")
    setError(nil)
    refresh()
    dialog:Show()
    addon.UIFactory.BringToFront(dialog)
    return true
end
