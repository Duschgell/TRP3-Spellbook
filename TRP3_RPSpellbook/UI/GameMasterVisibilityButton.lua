local _, addon = ...

addon.GameMasterVisibilityButton = {}

local labels = {
    full = "GAMEMASTER_VISIBILITY_FULL",
    targets = "GAMEMASTER_VISIBILITY_TARGETS",
    hidden = "GAMEMASTER_VISIBILITY_HIDDEN",
}

function addon.GameMasterVisibilityButton.Create(parent, onClick, helpKey)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(24, 24)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button:SetBackdropColor(0.08, 0.06, 0.04, 0.86)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\Icons\\Ability_Hunter_EagleEye")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local lid = button:CreateTexture(nil, "OVERLAY")
    lid:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    lid:SetPoint("BOTTOMRIGHT", icon, "RIGHT", 0, 0)
    lid:SetColorTexture(0.04, 0.03, 0.02, 0.82)

    local slash = button:CreateTexture(nil, "OVERLAY")
    slash:SetSize(25, 3)
    slash:SetPoint("CENTER")
    slash:SetColorTexture(0.9, 0.18, 0.12, 0.95)
    if type(slash.SetRotation) == "function" then
        slash:SetRotation(math.rad(42))
    end

    function button:SetVisibilityMode(mode)
        mode = addon.GameMasterVisibility.Normalize(mode)
        self.visibilityMode = mode
        lid:SetShown(mode == "targets")
        slash:SetShown(mode == "hidden")
        icon:SetDesaturated(mode == "hidden")
        icon:SetAlpha(mode == "full" and 1 or (mode == "targets" and 0.72 or 0.32))
        local border = mode == "full"
            and { 0.35, 0.85, 0.42, 1 }
            or (mode == "targets"
                and addon.Theme.Colors.gold
                or addon.Theme.Colors.textMuted)
        self:SetBackdropBorderColor(
            border[1],
            border[2],
            border[3],
            border[4] or 1
        )
    end

    button:SetScript("OnClick", function(self)
        if type(onClick) == "function" then
            onClick(self)
        end
    end)
    button:SetScript("OnEnter", function(self)
        local mode = addon.GameMasterVisibility.Normalize(
            self.visibilityMode
        )
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(addon.L("GAMEMASTER_VISIBILITY"))
        GameTooltip:AddLine(addon.L(labels[mode]), 1, 0.82, 0)
        GameTooltip:AddLine(
            addon.L(
                helpKey
                    or "GAMEMASTER_VISIBILITY_BUTTON_HELP"
            ),
            0.76, 0.69, 0.56, true
        )
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetVisibilityMode("hidden")
    return button
end
