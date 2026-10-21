local _, addon = ...
addon = addon.Shared or addon

addon.GameMasterAssistantsDialog = {}

local dialog

local function setCheckEnabled(check, enabled)
    if enabled then
        check:Enable()
        check:SetAlpha(1)
    else
        check:Disable()
        check:SetAlpha(0.35)
    end
end

local function getMembers()
    local localKey = addon.Runtime.NormalizePlayerID(
        addon.GameMasterRoster.GetLocalPlayerID()
    )
    local members = {}
    for _, member in ipairs(addon.GameMasterService.GetActionMembers()) do
        if member.playerKey ~= localKey then
            members[#members + 1] = member
        end
    end
    return members
end

local function collectRights(row)
    return {
        participants = row.participants:GetChecked() == true,
        rounds = row.rounds:GetChecked() == true,
        visibility = row.visibility:GetChecked() == true,
    }
end

local function updateAssignment(row, enabled)
    if not row.playerKey then
        return
    end
    local changed, errorMessage = addon.GameMasterService.SetAssistant(
        row.playerKey,
        enabled,
        collectRights(row)
    )
    if not changed and errorMessage then
        addon.Logger.Error(errorMessage)
    end
end

local function refresh()
    if not dialog then
        return
    end
    local members = getMembers()
    for index, row in ipairs(dialog.rows) do
        local member = members[index]
        if member then
            local assigned = addon.GameMasterService.GetAssistantRights(
                member.playerKey
            )
            local compatible = addon.GameMasterService.IsTestMode()
                or addon.GameMasterProtocol.SupportsDelegation(
                    member.playerID
                )
            row.playerKey = member.playerKey
            row.name:SetText(member.rpName or member.gameName)
            row.status:SetText(compatible
                and ""
                or addon.L("GAMEMASTER_ASSISTANT_INCOMPATIBLE_SHORT"))
            row.authorized:SetChecked(assigned ~= nil)
            row.rounds:SetChecked(
                assigned and assigned.rounds == true or false
            )
            row.participants:SetChecked(
                assigned and assigned.participants == true or false
            )
            row.visibility:SetChecked(
                assigned and assigned.visibility == true or false
            )
            setCheckEnabled(row.authorized, compatible)
            setCheckEnabled(row.rounds, compatible and assigned ~= nil)
            setCheckEnabled(
                row.participants,
                compatible and assigned ~= nil
            )
            setCheckEnabled(
                row.visibility,
                compatible and assigned ~= nil
            )
            row:SetAlpha(member.online == false and 0.55 or 1)
            row:Show()
        else
            row.playerKey = nil
            row:Hide()
        end
    end
    dialog.empty:SetShown(#members == 0)
    dialog.content:SetHeight(math.max(1, #members * 36))
    dialog.scroll:UpdateScrollChildRect()
end

local function createHeader(parent, text, x, width)
    local label = addon.UIFactory.CreateLabel(
        parent,
        addon.Theme.Fonts.small,
        text,
        addon.Theme.Colors.gold
    )
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -4)
    label:SetWidth(width)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    return label
end

local function createDialog()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("GAMEMASTER_ASSISTANTS_TITLE"),
        700,
        500
    )

    local intro = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("GAMEMASTER_ASSISTANTS_HELP"),
        theme.Colors.textMuted
    )
    intro:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -48)
    intro:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.lg, -48)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -92)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.xl, -92)
    header:SetHeight(28)
    local nameHeader = addon.UIFactory.CreateLabel(
        header,
        theme.Fonts.small,
        addon.L("GAMEMASTER_ASSISTANT_PLAYER"),
        theme.Colors.gold
    )
    nameHeader:SetPoint("LEFT", header, "LEFT", 8, 0)
    nameHeader:SetWidth(230)
    nameHeader:SetJustifyH("LEFT")
    createHeader(
        header,
        addon.L("GAMEMASTER_ASSISTANT_ENABLED"),
        240,
        80
    )
    createHeader(
        header,
        addon.L("GAMEMASTER_ASSISTANT_RIGHT_ROUNDS"),
        330,
        80
    )
    createHeader(
        header,
        addon.L("GAMEMASTER_ASSISTANT_RIGHT_PARTICIPANTS"),
        420,
        100
    )
    createHeader(
        header,
        addon.L("GAMEMASTER_ASSISTANT_RIGHT_VISIBILITY"),
        535,
        100
    )

    local section = addon.GameMasterWidgets.CreateSection(frame)
    section:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    section:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -theme.Spacing.lg,
        theme.Spacing.lg
    )

    local scroll = CreateFrame(
        "ScrollFrame",
        nil,
        section,
        "UIPanelScrollFrameTemplate"
    )
    scroll:SetPoint("TOPLEFT", section, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -24, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local rows = {}
    for index = 1, addon.Constants.GAMEMASTER_MAX_PARTICIPANTS do
        local row = addon.GameMasterWidgets.CreateSection(
            content,
            index % 2 == 0
                and theme.Colors.archiveRow
                or theme.Colors.dark
        )
        row:SetPoint(
            "TOPLEFT",
            content,
            "TOPLEFT",
            0,
            -((index - 1) * 36)
        )
        row:SetHeight(34)
        row:SetWidth(640)

        local name = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.small,
            "",
            theme.Colors.text
        )
        name:SetPoint("LEFT", row, "LEFT", 8, 0)
        name:SetWidth(155)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        local status = addon.UIFactory.CreateLabel(
            row,
            theme.Fonts.small,
            "",
            theme.Colors.error
        )
        status:SetPoint("LEFT", name, "RIGHT", 4, 0)
        status:SetWidth(70)
        status:SetJustifyH("LEFT")
        status:SetWordWrap(false)

        local authorized = CreateFrame(
            "CheckButton",
            nil,
            row,
            "UICheckButtonTemplate"
        )
        authorized:SetPoint("CENTER", row, "LEFT", 280, 0)
        local rounds = CreateFrame(
            "CheckButton",
            nil,
            row,
            "UICheckButtonTemplate"
        )
        rounds:SetPoint("CENTER", row, "LEFT", 370, 0)
        local participants = CreateFrame(
            "CheckButton",
            nil,
            row,
            "UICheckButtonTemplate"
        )
        participants:SetPoint("CENTER", row, "LEFT", 470, 0)
        local visibility = CreateFrame(
            "CheckButton",
            nil,
            row,
            "UICheckButtonTemplate"
        )
        visibility:SetPoint("CENTER", row, "LEFT", 585, 0)

        authorized:SetScript("OnClick", function(self)
            if self:GetChecked() then
                rounds:SetChecked(true)
                participants:SetChecked(true)
                visibility:SetChecked(true)
                updateAssignment(row, true)
            else
                updateAssignment(row, false)
            end
            refresh()
        end)
        local function updateRights()
            if authorized:GetChecked() then
                updateAssignment(row, true)
            end
            refresh()
        end
        rounds:SetScript("OnClick", updateRights)
        participants:SetScript("OnClick", updateRights)
        visibility:SetScript("OnClick", updateRights)

        row.authorized = authorized
        row.name = name
        row.participants = participants
        row.rounds = rounds
        row.status = status
        row.visibility = visibility
        rows[index] = row
    end

    local empty = addon.UIFactory.CreateLabel(
        section,
        theme.Fonts.body,
        addon.L("GAMEMASTER_ASSISTANTS_EMPTY"),
        theme.Colors.textMuted
    )
    empty:SetPoint("CENTER")

    frame.content = content
    frame.empty = empty
    frame.rows = rows
    frame.scroll = scroll
    return frame
end

function addon.GameMasterAssistantsDialog.Open()
    if not addon.GameMasterService.IsPrimaryGameMaster() then
        addon.Logger.Error(addon.L("GAMEMASTER_PRIMARY_ONLY"))
        return false
    end
    local session = addon.GameMasterService.GetActiveSession()
    if not session then
        return false
    end
    return addon.GameMasterSceneSettingsDialog.OpenEdit(
        session.id
    )
end

addon.GameMasterService.RegisterListener(function()
    if dialog and dialog:IsShown() then
        refresh()
    end
end)
