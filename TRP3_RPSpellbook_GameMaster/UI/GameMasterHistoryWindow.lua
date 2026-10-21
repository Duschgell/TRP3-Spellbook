local _, addon = ...
addon = addon.Shared or addon

addon.GameMasterHistoryWindow = {}

local window
local selectedSessionID
local selectedRoundIndex
local sessionPage = 1
local sessionsPerPage = 7
local maxParticipantRows = 40
local participantFontSize = 12

local function setEnabled(button, enabled)
    addon.GameMasterWidgets.SetEnabled(button, enabled == true)
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

local function getSessions()
    local sessions = addon.GameMasterService.ListSessions()
    sessions = type(sessions) == "table" and sessions or {}
    local query = window and window.searchBox
        and string.lower(addon.Runtime.Trim(window.searchBox:GetText()) or "")
        or ""
    if query == "" then
        return sessions
    end

    local function contains(value)
        return type(value) == "string"
            and string.lower(value):find(query, 1, true) ~= nil
    end
    local filtered = {}
    for _, session in ipairs(sessions) do
        local match = contains(session.name)
        for _, participant in pairs(
            type(session.participants) == "table"
                and session.participants or {}
        ) do
            if contains(participant.rpName)
                or contains(participant.gameName)
            then
                match = true
                break
            end
        end
        if not match then
            for _, round in ipairs(
                type(session.rounds) == "table" and session.rounds or {}
            ) do
                for _, submission in pairs(round.submissions or {}) do
                    if contains(submission.rpName) then
                        match = true
                        break
                    end
                    for _, action in ipairs(
                        addon.GameMasterActionCollection.Get(submission)
                    ) do
                        if contains(action.spell and action.spell.name) then
                            match = true
                            break
                        end
                        for _, target in ipairs(action.targets or {}) do
                            if contains(target.label)
                                or contains(target.name)
                                or contains(target.value)
                            then
                                match = true
                                break
                            end
                        end
                        if match then break end
                    end
                    if match then break end
                end
                if match then break end
            end
        end
        if match then
            filtered[#filtered + 1] = session
        end
    end
    return filtered
end

local function findSession(sessions, sessionID)
    for _, session in ipairs(sessions) do
        if session.id == sessionID then
            return session
        end
    end
    return nil
end

local function getRounds(session)
    return type(session) == "table" and type(session.rounds) == "table"
        and session.rounds
        or {}
end

local function getParticipants(session)
    return type(session) == "table"
        and type(session.participants) == "table"
        and session.participants
        or {}
end

local function getParticipantOrder(session)
    return type(session) == "table"
        and type(session.participantOrder) == "table"
        and session.participantOrder
        or {}
end

local function layoutParticipantRows()
    if not window then
        return
    end
    local width = math.max(
        180,
        tonumber(window.rosterScroll:GetWidth()) or 0
    )
    local offset = 0
    local headerHeight = 20
    local style = addon.Theme.GetGameMasterStyle("modern")
    for _, row in ipairs(window.participantRows) do
        if row:IsShown() then
            local actionWidth = math.max(80, width - 18)
            local actionHeight = addon.GameMasterActionList.Measure(
                row.actionList,
                actionWidth,
                participantFontSize
            )
            local rowHeight = headerHeight + actionHeight + 8
            row:ClearAllPoints()
            row:SetPoint(
                "TOPLEFT", window.rosterContent, "TOPLEFT", 0, -offset
            )
            row:SetSize(width, rowHeight)
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
            row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -3)
            row.name:SetHeight(headerHeight)
            row.actionList:ClearAllPoints()
            row.actionList:SetPoint(
                "TOPLEFT", row, "TOPLEFT", 12, -(headerHeight + 4)
            )
            addon.GameMasterActionList.Layout(
                row.actionList,
                actionWidth,
                participantFontSize
            )
            addon.GameMasterActionList.ApplyStyle(
                row.actionList,
                style,
                true
            )
            offset = offset + rowHeight + 3
        end
    end
    window.rosterContent:SetHeight(math.max(
        1,
        window.rosterScroll:GetHeight(),
        offset
    ))
    window.rosterContent:SetWidth(math.max(1, window.rosterScroll:GetWidth()))
    window.rosterScroll:UpdateScrollChildRect()
end

local function refreshParticipants(session, round)
    local order = getParticipantOrder(session)
    local participants = getParticipants(session)
    local submissions = type(round) == "table"
        and type(round.submissions) == "table"
        and round.submissions
        or {}

    for index, row in ipairs(window.participantRows) do
        local playerKey = order[index]
        local participant = playerKey and participants[playerKey] or nil
        local submission = playerKey and submissions[playerKey] or nil
        if type(participant) == "table" or type(submission) == "table" then
            row.name:SetText(
                (submission and submission.rpName)
                or (participant and participant.rpName)
                or (participant and participant.gameName)
                or playerKey
                or addon.L("UNKNOWN")
            )
            row.submission = submission
            addon.GameMasterActionList.SetSubmission(
                row.actionList,
                submission
            )
            row:Show()
        else
            row.submission = nil
            addon.GameMasterActionList.SetSubmission(row.actionList, nil)
            row:Hide()
        end
    end
    layoutParticipantRows()
end

local function selectSession(sessionID)
    local sessions = getSessions()
    local session = findSession(sessions, sessionID)
    selectedSessionID = session and session.id or nil
    selectedRoundIndex = session and #getRounds(session) or nil
end

local function refreshSessionList(sessions)
    local pageCount = math.max(
        1,
        math.ceil(#sessions / sessionsPerPage)
    )
    sessionPage = math.max(1, math.min(sessionPage, pageCount))
    local first = ((sessionPage - 1) * sessionsPerPage) + 1

    for rowIndex, row in ipairs(window.sessionRows) do
        local session = sessions[first + rowIndex - 1]
        row.sessionID = session and session.id or nil
        if session then
            row.name:SetText(session.name or addon.L("GAMEMASTER_UNNAMED_SESSION"))
            row.meta:SetText(addon.L(
                "GAMEMASTER_HISTORY_SESSION_META",
                #getRounds(session),
                formatTimestamp(session.updatedAt)
            ))
            row.settings:Show()
            local color = session.id == selectedSessionID
                and addon.Theme.Colors.archiveRowSelected
                or addon.Theme.Colors.archiveRow
            row:SetBackdropColor(
                color[1],
                color[2],
                color[3],
                color[4]
            )
            row:Show()
        else
            row:Hide()
        end
    end

    window.sessionPage:SetText(string.format(
        "%d / %d",
        sessionPage,
        pageCount
    ))
    setEnabled(window.previousSessionPage, sessionPage > 1)
    setEnabled(window.nextSessionPage, sessionPage < pageCount)
end

local function refresh()
    if not window then
        return
    end

    local sessions = getSessions()
    local session = findSession(sessions, selectedSessionID)
    if not session and sessions[1] then
        session = sessions[1]
        selectedSessionID = session.id
        selectedRoundIndex = #getRounds(session)
    end

    refreshSessionList(sessions)
    window.empty:SetShown(#sessions == 0)
    window.details:SetShown(session ~= nil)
    if not session then
        refreshParticipants(nil, nil)
        return
    end

    local rounds = getRounds(session)
    selectedRoundIndex = math.max(
        0,
        math.min(tonumber(selectedRoundIndex) or #rounds, #rounds)
    )
    local round = rounds[selectedRoundIndex]

    window.sessionName:SetText(
        session.name or addon.L("GAMEMASTER_UNNAMED_SESSION")
    )
    window.sessionMeta:SetText(addon.L(
        "GAMEMASTER_HISTORY_LAST_CHANGED",
        formatTimestamp(session.updatedAt)
    ))
    window.roundLabel:SetText(
        round
        and addon.L(
            round.status == "open"
                and "GAMEMASTER_ROUND_OPEN"
                or "GAMEMASTER_ROUND_CLOSED",
            tonumber(round.number) or selectedRoundIndex
        )
        or addon.L("GAMEMASTER_NO_ROUND")
    )
    window.roundPosition:SetText(addon.L(
        "GAMEMASTER_HISTORY_POSITION",
        selectedRoundIndex,
        #rounds
    ))
    setEnabled(window.previousRound, selectedRoundIndex > 1)
    setEnabled(
        window.nextRound,
        selectedRoundIndex > 0 and selectedRoundIndex < #rounds
    )
    refreshParticipants(session, round)
end

local function changeRound(direction)
    local session = findSession(getSessions(), selectedSessionID)
    local rounds = getRounds(session)
    if #rounds == 0 then
        return
    end
    selectedRoundIndex = math.max(
        1,
        math.min(#rounds, (selectedRoundIndex or #rounds) + direction)
    )
    refresh()
end

local function createWindow()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("GAMEMASTER_HISTORY_TITLE"),
        760,
        520
    )
    frame:SetFrameStrata("HIGH")

    local sessionSection = addon.GameMasterWidgets.CreateSection(frame)
    sessionSection:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        theme.Spacing.lg,
        -48
    )
    sessionSection:SetPoint(
        "BOTTOMLEFT",
        frame,
        "BOTTOMLEFT",
        theme.Spacing.lg,
        theme.Spacing.lg
    )
    sessionSection:SetWidth(220)

    local sessionHeader = addon.UIFactory.CreateLabel(
        sessionSection,
        theme.Fonts.header,
        addon.L("GAMEMASTER_HISTORY_ENCOUNTERS"),
        theme.Colors.gold
    )
    sessionHeader:SetPoint(
        "TOPLEFT",
        sessionSection,
        "TOPLEFT",
        theme.Spacing.sm,
        -theme.Spacing.sm
    )

    local searchBox = addon.UIFactory.CreateSearchBox(
        sessionSection,
        "GAMEMASTER_HISTORY_SEARCH"
    )
    searchBox:SetPoint(
        "TOPLEFT",
        sessionHeader,
        "BOTTOMLEFT",
        0,
        -theme.Spacing.xs
    )
    searchBox:SetPoint("RIGHT", sessionSection, "RIGHT", -theme.Spacing.sm, 0)

    local sessionRows = {}
    for index = 1, sessionsPerPage do
        local row = addon.GameMasterWidgets.CreateSection(
            sessionSection,
            theme.Colors.archiveRow
        )
        row:SetPoint(
            "TOPLEFT",
            sessionSection,
            "TOPLEFT",
            theme.Spacing.sm,
            -66 - ((index - 1) * 48)
        )
        row:SetPoint("RIGHT", sessionSection, "RIGHT", -theme.Spacing.sm, 0)
        row:SetHeight(42)
        row:EnableMouse(true)

        local name = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.body,
            "",
            theme.Colors.text
        )
        name:SetPoint(
            "TOPLEFT",
            row,
            "TOPLEFT",
            theme.Spacing.sm,
            -theme.Spacing.xs
        )
        name:SetPoint("RIGHT", row, "RIGHT", -theme.Spacing.sm, 0)
        name:SetWordWrap(false)

        local meta = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.small,
            "",
            theme.Colors.textMuted
        )
        meta:SetPoint(
            "BOTTOMLEFT",
            row,
            "BOTTOMLEFT",
            theme.Spacing.sm,
            theme.Spacing.xs
        )
        meta:SetPoint("RIGHT", row, "RIGHT", -60, 0)
        meta:SetWordWrap(false)

        name:ClearAllPoints()
        name:SetPoint(
            "TOPLEFT",
            row,
            "TOPLEFT",
            theme.Spacing.sm,
            -theme.Spacing.xs
        )
        name:SetPoint("RIGHT", row, "RIGHT", -60, 0)

        local settings = addon.UIFactory.CreateTextureButton(
            row,
            "Interface\\Buttons\\UI-OptionsButton",
            24
        )
        settings:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        settings:SetScript("OnClick", function()
            if row.sessionID then
                addon.GameMasterSceneSettingsDialog.OpenEdit(
                    row.sessionID,
                    refresh
                )
            end
        end)

        local deleteButton = addon.UIFactory.CreateButton(row, "x", 22)
        deleteButton:SetPoint("RIGHT", settings, "LEFT", -2, 0)
        deleteButton:SetScript("OnClick", function()
            if not row.sessionID then
                return
            end
            local sessionID = row.sessionID
            local session = findSession(getSessions(), sessionID)
            addon.UIFactory.ShowConfirmation(
                addon.L("GAMEMASTER_HISTORY_DELETE_TITLE"),
                addon.L(
                    "GAMEMASTER_HISTORY_DELETE_CONFIRM",
                    session and session.name
                        or addon.L("GAMEMASTER_UNNAMED_SESSION")
                ),
                function()
                    local deleted, errorMessage =
                        addon.GameMasterService.DeleteSession(sessionID)
                    if not deleted then
                        addon.Logger.Error(errorMessage)
                        return
                    end
                    if selectedSessionID == sessionID then
                        selectedSessionID = nil
                        selectedRoundIndex = nil
                    end
                    refresh()
                end
            )
        end)

        row:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" and row.sessionID then
                selectSession(row.sessionID)
                refresh()
            end
        end)
        row.name = name
        row.meta = meta
        row.settings = settings
        row.deleteButton = deleteButton
        sessionRows[index] = row
    end

    local previousSessionPage = addon.UIFactory.CreateButton(
        sessionSection,
        "<",
        34
    )
    previousSessionPage:SetPoint(
        "BOTTOMLEFT",
        sessionSection,
        "BOTTOMLEFT",
        theme.Spacing.sm,
        theme.Spacing.sm
    )
    previousSessionPage:SetScript("OnClick", function()
        sessionPage = sessionPage - 1
        refresh()
    end)

    local sessionPageLabel = addon.UIFactory.CreateLabel(
        sessionSection,
        theme.Fonts.body,
        "",
        theme.Colors.text
    )
    sessionPageLabel:SetPoint(
        "LEFT",
        previousSessionPage,
        "RIGHT",
        theme.Spacing.sm,
        0
    )

    local nextSessionPage = addon.UIFactory.CreateButton(
        sessionSection,
        ">",
        34
    )
    nextSessionPage:SetPoint(
        "LEFT",
        sessionPageLabel,
        "RIGHT",
        theme.Spacing.sm,
        0
    )
    nextSessionPage:SetScript("OnClick", function()
        sessionPage = sessionPage + 1
        refresh()
    end)

    local details = addon.GameMasterWidgets.CreateSection(frame)
    details:SetPoint(
        "TOPLEFT",
        sessionSection,
        "TOPRIGHT",
        theme.Spacing.sm,
        0
    )
    details:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -theme.Spacing.lg,
        theme.Spacing.lg
    )

    local sessionName = addon.UIFactory.CreateLabel(
        details,
        theme.Fonts.header,
        "",
        theme.Colors.gold
    )
    sessionName:SetPoint(
        "TOPLEFT",
        details,
        "TOPLEFT",
        theme.Spacing.md,
        -theme.Spacing.sm
    )
    sessionName:SetPoint("RIGHT", details, "RIGHT", -theme.Spacing.md, 0)
    sessionName:SetWordWrap(false)

    local sessionMeta = addon.UIFactory.CreateLabel(
        details,
        theme.Fonts.small,
        "",
        theme.Colors.textMuted
    )
    sessionMeta:SetPoint(
        "TOPLEFT",
        sessionName,
        "BOTTOMLEFT",
        0,
        -theme.Spacing.tiny
    )

    local roundLabel = addon.UIFactory.CreateLabel(
        details,
        theme.Fonts.body,
        "",
        theme.Colors.text
    )
    roundLabel:SetPoint(
        "TOPLEFT",
        sessionMeta,
        "BOTTOMLEFT",
        0,
        -theme.Spacing.sm
    )

    local previousRound = addon.UIFactory.CreateButton(details, "<", 34)
    previousRound:SetPoint(
        "TOPRIGHT",
        details,
        "TOPRIGHT",
        -132,
        -theme.Spacing.sm
    )
    previousRound:SetScript("OnClick", function()
        changeRound(-1)
    end)

    local roundPosition = addon.UIFactory.CreateLabel(
        details,
        theme.Fonts.body,
        "",
        theme.Colors.text
    )
    roundPosition:SetPoint(
        "LEFT",
        previousRound,
        "RIGHT",
        theme.Spacing.sm,
        0
    )

    local nextRound = addon.UIFactory.CreateButton(details, ">", 34)
    nextRound:SetPoint(
        "LEFT",
        roundPosition,
        "RIGHT",
        theme.Spacing.sm,
        0
    )
    nextRound:SetScript("OnClick", function()
        changeRound(1)
    end)

    local rosterSection = addon.GameMasterWidgets.CreateSection(details)
    rosterSection:SetPoint(
        "TOPLEFT",
        details,
        "TOPLEFT",
        theme.Spacing.sm,
        -76
    )
    rosterSection:SetPoint(
        "BOTTOMRIGHT",
        details,
        "BOTTOMRIGHT",
        -theme.Spacing.sm,
        theme.Spacing.sm
    )

    local rosterScroll = CreateFrame(
        "ScrollFrame",
        nil,
        rosterSection,
        "UIPanelScrollFrameTemplate"
    )
    rosterScroll:SetPoint(
        "TOPLEFT",
        rosterSection,
        "TOPLEFT",
        theme.Spacing.xs,
        -theme.Spacing.xs
    )
    rosterScroll:SetPoint(
        "BOTTOMRIGHT",
        rosterSection,
        "BOTTOMRIGHT",
        -theme.Spacing.xl,
        theme.Spacing.xs
    )

    local rosterContent = CreateFrame("Frame", nil, rosterScroll)
    rosterContent:SetPoint("TOPLEFT", rosterScroll, "TOPLEFT", 0, 0)
    rosterContent:SetSize(1, 1)
    rosterScroll:SetScrollChild(rosterContent)

    local participantRows = {}
    for index = 1, maxParticipantRows do
        local row = addon.GameMasterWidgets.CreateSection(
            rosterContent,
            index % 2 == 0 and theme.Colors.archiveRow or theme.Colors.dark
        )
        row:SetPoint("TOPLEFT", rosterContent, "TOPLEFT", 0, 0)
        row:SetHeight(1)

        local name = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.small,
            "",
            theme.Colors.text
        )
        name:SetPoint("LEFT", row, "LEFT", theme.Spacing.xs, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)

        row.actionList = addon.GameMasterActionList.Create(row)
        row.name = name
        participantRows[index] = row
    end

    local empty = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("GAMEMASTER_HISTORY_EMPTY"),
        theme.Colors.textMuted
    )
    empty:SetPoint("CENTER", details, "CENTER", 0, 0)

    frame.details = details
    frame.empty = empty
    frame.nextRound = nextRound
    frame.nextSessionPage = nextSessionPage
    frame.participantRows = participantRows
    frame.previousRound = previousRound
    frame.previousSessionPage = previousSessionPage
    frame.rosterContent = rosterContent
    frame.rosterScroll = rosterScroll
    frame.roundLabel = roundLabel
    frame.roundPosition = roundPosition
    frame.sessionMeta = sessionMeta
    frame.sessionName = sessionName
    frame.sessionPage = sessionPageLabel
    frame.sessionRows = sessionRows
    frame.searchBox = searchBox

    rosterScroll:SetScript("OnSizeChanged", layoutParticipantRows)
    searchBox:HookScript("OnTextChanged", function()
        sessionPage = 1
        selectedSessionID = nil
        selectedRoundIndex = nil
        refresh()
    end)
    frame:SetScript("OnShow", refresh)
    return frame
end

function addon.GameMasterHistoryWindow.Open(sessionID)
    window = window or createWindow()
    sessionPage = 1
    if sessionID then
        selectSession(sessionID)
    else
        selectedSessionID = nil
        selectedRoundIndex = nil
    end
    refresh()
    window:Show()
    addon.UIFactory.BringToFront(window)
    return true
end
