local _, addon = ...

addon.SpellbookWindow = {}

local window

local function createWindow()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateBackdropFrame(UIParent, theme.Colors.dark, theme.Colors.gold)
    frame:SetSize(theme.Sizes.windowWidth, theme.Sizes.windowHeight)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()

    frame.panel = addon.SpellbookPanel.Create(frame)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.xs, -theme.Spacing.xs)
    closeButton:SetScript("OnClick", function()
        frame.panel.RequestClose(function() frame:Hide() end)
    end)

    return frame
end

function addon.SpellbookWindow.GetTutorialContext() return window end

function addon.SpellbookWindow.Open(spellbook, profileLabel, options)
    if not window then
        window = createWindow()
    end

    addon.SpellbookPanel.Refresh(window.panel, spellbook, profileLabel, nil, options)
    window:Show()
end

function addon.SpellbookWindow.Close()
    if window then
        window.panel.RequestClose(function() window:Hide() end)
    end
end
