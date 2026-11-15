local _, addon = ...
addon = addon.Shared or addon

addon.GameMasterTestDialog = {}

local dialog

local function setEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end

local function refresh()
    if not dialog then return end
    local active = addon.GameMasterService.IsTestMode()
    local anySession = addon.GameMasterService.IsSessionActive()
    local round = addon.GameMasterService.GetActiveRound()
    dialog.count:SetText(tostring(
        addon.GameMasterTestMode.GetParticipantCount()
    ))
    dialog.autoActions:SetChecked(
        addon.GameMasterTestMode.ShouldGenerateActions()
    )
    dialog.status:SetText(addon.L(
        active and "GAMEMASTER_TEST_STATUS_ACTIVE"
            or "GAMEMASTER_TEST_STATUS_INACTIVE"
    ))
    setEnabled(dialog.startButton, not anySession)
    setEnabled(dialog.stopButton, active)
    setEnabled(dialog.regenerateButton,
        active and round ~= nil and round.status == "open" and round.phase ~= "enemies")
    setEnabled(dialog.overviewButton,
        active and round ~= nil)
    setEnabled(dialog.minus, not active)
    setEnabled(dialog.plus, not active)
    setEnabled(dialog.autoActions, not active)
    dialog.encounterOptions.locked = anySession
    dialog.encounterOptions:UpdateEnabled()
end

local function createDialog()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("GAMEMASTER_TEST_TITLE"),
        430,
        518
    )
    frame:SetFrameStrata("FULLSCREEN_DIALOG")

    local description = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("GAMEMASTER_TEST_DESCRIPTION"),
        theme.Colors.text
    )
    description:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -48)
    description:SetPoint("RIGHT", frame, "RIGHT", -22, 0)
    description:SetJustifyH("LEFT")
    description:SetWordWrap(true)

    local countLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("GAMEMASTER_TEST_PARTICIPANTS"),
        theme.Colors.gold
    )
    countLabel:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -22)

    local minus = addon.UIFactory.CreateButton(frame, "-", 28)
    minus:SetPoint("LEFT", countLabel, "RIGHT", 18, 0)
    local count = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        "5",
        theme.Colors.text
    )
    count:SetPoint("LEFT", minus, "RIGHT", 12, 0)
    count:SetWidth(30)
    count:SetJustifyH("CENTER")
    local plus = addon.UIFactory.CreateButton(frame, "+", 28)
    plus:SetPoint("LEFT", count, "RIGHT", 12, 0)

    local autoActions = CreateFrame(
        "CheckButton",
        nil,
        frame,
        "UICheckButtonTemplate"
    )
    autoActions:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", 0, -18)
    local autoLabel = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.body,
        addon.L("GAMEMASTER_TEST_AUTO_ACTIONS"),
        theme.Colors.text
    )
    autoLabel:SetPoint("LEFT", autoActions, "RIGHT", 4, 0)

    local encounterOptions = addon.GameMasterWidgets.CreateEncounterOptions(frame)
    encounterOptions:SetPoint("TOPLEFT", autoActions, "BOTTOMLEFT", 0, -10)
    encounterOptions:SetPoint("RIGHT", frame, "RIGHT", -22, 0)
    local status = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.small,
        "",
        theme.Colors.textMuted
    )
    status:SetPoint("TOPLEFT", encounterOptions, "BOTTOMLEFT", 4, -8)

    local startButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("GAMEMASTER_TEST_START"),
        120
    )
    startButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 20)
    local regenerateButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("GAMEMASTER_TEST_REGENERATE"),
        145
    )
    regenerateButton:SetPoint("LEFT", startButton, "RIGHT", 8, 0)
    local stopButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("GAMEMASTER_TEST_STOP"),
        90
    )
    stopButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 20)
    local overviewButton = addon.UIFactory.CreateButton(
        frame,
        addon.L("GAMEMASTER_TEST_OVERVIEW"),
        145
    )
    overviewButton:SetPoint("BOTTOMLEFT", startButton, "TOPLEFT", 0, 10)

    minus:SetScript("OnClick", function()
        addon.GameMasterTestMode.SetParticipantCount(
            addon.GameMasterTestMode.GetParticipantCount() - 1
        )
        refresh()
    end)
    plus:SetScript("OnClick", function()
        addon.GameMasterTestMode.SetParticipantCount(
            addon.GameMasterTestMode.GetParticipantCount() + 1
        )
        refresh()
    end)
    autoActions:SetScript("OnClick", function(self)
        addon.GameMasterTestMode.SetGenerateActions(self:GetChecked())
        refresh()
    end)
    startButton:SetScript("OnClick", function()
        local started, errorMessage = addon.GameMasterService.StartTestMode(
            addon.GameMasterTestMode.GetParticipantCount(),
            encounterOptions:GetOptions()
        )
        if not started then
            addon.Logger.Error(errorMessage)
            refresh()
            return
        end
        frame:Hide()
        addon.TRP3Bridge.CloseMainFrame()
    end)
    regenerateButton:SetScript("OnClick", function()
        local generated, errorMessage =
            addon.GameMasterService.RegenerateTestActions()
        if not generated then
            addon.Logger.Error(errorMessage)
        end
        refresh()
    end)
    stopButton:SetScript("OnClick", function()
        addon.GameMasterService.Stop()
        refresh()
    end)
    overviewButton:SetScript("OnClick", function()
        addon.GameMasterSharedActions.Open()
    end)

    frame.autoActions = autoActions
    frame.encounterOptions = encounterOptions
    frame.count = count
    frame.minus = minus
    frame.overviewButton = overviewButton
    frame.plus = plus
    frame.regenerateButton = regenerateButton
    frame.startButton = startButton
    frame.status = status
    frame.stopButton = stopButton
    frame:SetScript("OnShow", refresh)
    addon.GameMasterService.RegisterListener(refresh)
    return frame
end

function addon.GameMasterTestDialog.Open()
    dialog = dialog or createDialog()
    refresh()
    dialog:Show()
    addon.UIFactory.BringToFront(dialog)
    return true
end
