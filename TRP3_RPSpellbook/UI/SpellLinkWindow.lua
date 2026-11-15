local _, addon = ...

addon.SpellLinkWindow = {}

local window
local state = {}

local function insertCurrentSpell()
    if not state.spell or not state.owner then
        return
    end
    local success, errorMessage = addon.ChatInsert.InsertSpell(state.owner, state.spell)
    if not success then
        addon.Logger.Error(errorMessage or addon.L("CHAT_INSERT_FAILED"))
    end
end

local function createWindow()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("LINK_DETAILS_TITLE"),
        theme.Sizes.linkWindowWidth,
        theme.Sizes.linkWindowHeight
    )

    local detailsView = addon.SpellDetailsView.Create(frame, {
        onBack = function()
            frame:Hide()
        end,
        onInsertChat = insertCurrentSpell,
        onWhisper = function()
            if state.spell then
                addon.SpellWhisperDialog.Open(state.spell)
            end
        end,
    })
    detailsView:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.sm, -theme.Spacing.xl - theme.Spacing.md)
    detailsView:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.sm, theme.Spacing.sm)

    local unknownTitle = addon.UIFactory.CreateLabel(frame, theme.Fonts.header, "", theme.Colors.gold)
    unknownTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.xl, -theme.Sizes.linkUnknownTopOffset)
    unknownTitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.xl, -theme.Sizes.linkUnknownTopOffset)
    unknownTitle:SetJustifyH("LEFT")

    local unknownMessage = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, "", theme.Colors.text)
    unknownMessage:SetPoint("TOPLEFT", unknownTitle, "BOTTOMLEFT", 0, -theme.Spacing.lg)
    unknownMessage:SetPoint("TOPRIGHT", unknownTitle, "BOTTOMRIGHT", 0, -theme.Spacing.lg)
    unknownMessage:SetJustifyH("LEFT")
    unknownMessage:SetJustifyV("TOP")
    unknownMessage:SetWordWrap(true)

    frame.detailsView = detailsView
    frame.unknownMessage = unknownMessage
    frame.unknownTitle = unknownTitle
    return frame
end

function addon.SpellLinkWindow.OpenSpell(reference, spell)
    if type(reference) ~= "table" or type(spell) ~= "table" then
        return false
    end

    window = window or createWindow()
    state.owner = reference.owner
    state.spell = spell
    window.title:SetText(addon.L("LINK_DETAILS_TITLE"))
    window.unknownTitle:Hide()
    window.unknownMessage:Hide()
    window.detailsView:Show()
    addon.SpellDetailsView.SetSpell(window.detailsView, spell, false)
    window:Show()
    addon.UIFactory.BringToFront(window)
    return true
end

function addon.SpellLinkWindow.OpenUnknown(displayName)
    window = window or createWindow()
    state.owner = nil
    state.spell = nil
    window.detailsView:Hide()
    window.title:SetText(addon.L("UNKNOWN_ABILITY"))
    window.unknownTitle:SetText(addon.ChatLinks.SanitizeDisplayName(displayName))
    window.unknownMessage:SetText(addon.L("UNKNOWN_LINK_MESSAGE"))
    window.unknownTitle:Show()
    window.unknownMessage:Show()
    window:Show()
    addon.UIFactory.BringToFront(window)
end
