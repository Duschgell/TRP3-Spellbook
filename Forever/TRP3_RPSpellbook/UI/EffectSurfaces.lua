local _, addon = ...
addon.EffectSurfaces = {}
local surfaces = addon.EffectSurfaces
local initialized, targetStrip, inspection, inventory, profileStrip
local plates = setmetatable({}, { __mode = "k" })
local function me() return addon.GameMasterRoster.GetLocalPlayerID() end
local function enabled(key)
    local success, value = pcall(TRP3_API.configuration.getValue, key)
    return success and value == true
end

local function heading(parent, own)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", 24, -16)
    panel:SetPoint("TOPRIGHT", -24, -16)
    panel:SetHeight(26)
    panel.own = own
    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.title:SetFont(addon.BookLayout.Font, 12)
    panel.title:SetPoint("TOPLEFT")
    panel.title:SetPoint("TOPRIGHT")
    panel.title:SetHeight(18)
    panel.title:SetTextColor(0.47, 0.28, 0.12)
    panel.name = panel:CreateFontString(nil, "OVERLAY")
    panel.name:SetFont(addon.BookLayout.Font, 19)
    panel.name:SetPoint("TOPLEFT", 0, -22)
    panel.name:SetPoint("TOPRIGHT", 0, -22)
    panel.name:SetHeight(26)
    panel.strip = addon.EffectIcons.Create(panel, own and 52 or 48, 12, 64)
    return panel
end

local function updateHeading(panel, player)
    local identity = addon.EffectDisplay.Identity(player)
    panel.title:SetText(identity.title)
    local titleHeight = identity.title ~= "" and 22 or 0
    panel.title:SetShown(titleHeight > 0)
    panel.name:ClearAllPoints()
    panel.name:SetPoint("TOPLEFT", 0, -titleHeight)
    panel.name:SetPoint("TOPRIGHT", 0, -titleHeight)
    panel.name:SetText(identity.name)
    local color = identity.color or "392515"
    panel.name:SetTextColor(tonumber(color:sub(1, 2), 16) / 255, tonumber(color:sub(3, 4), 16) / 255, tonumber(color:sub(5, 6), 16) / 255)
    local textHeight = titleHeight + 26
    panel.strip:ClearAllPoints()
    panel.strip:SetPoint("TOP", 0, -textHeight - 10)
    addon.EffectIcons.Configure(panel.strip, { width = math.max(1, panel:GetParent():GetWidth() - 56),
        maxHeight = 104, minSize = 24, maxSize = panel.own and 52 or 48, gap = 6 })
    local count = addon.EffectIcons.Update(panel.strip, player)
    panel:SetHeight(textHeight + (count > 0 and panel.strip:GetHeight() + 10 or 0))
    return 16 + panel:GetHeight() + 14
end

local function updateInspection()
    if addon.EffectIcons.IsSuppressed() then return end
    local frame = _G.TRP3_InspectionFrame
    if frame and frame:IsShown() and frame.current then
        if not inspection then
            inspection = heading(frame)
        end
        if frame.Main.Model.Title then frame.Main.Model.Title:Hide() end
        local top = updateHeading(inspection, frame.current)
        local scale = frame.Main:GetScale()
        frame:SetHeight(top + frame.Main:GetHeight() * scale + 24)
        frame.Main:ClearAllPoints()
        frame.Main:SetPoint("TOP", frame, "TOP", 0, -top / scale)
        addon.TimedEffects.RequestSnapshot(frame.current)
    end
    local page = _G.TRP3_InventoryPage
    if page and page:IsShown() then
        if not inventory then inventory = heading(page, true) end
        local top = updateHeading(inventory, me())
        local available = math.max(1, page:GetHeight() - top - 20)
        page.Main:SetScale(math.min(1, available / page.Main:GetHeight()))
        page.Main:ClearAllPoints()
        page.Main:SetPoint("TOP", page, "TOP", 0, -top / page.Main:GetScale())
    end
end

local function updateTarget()
    local frame = _G.TRP3_TargetFrame
    if not frame then return end
    if not targetStrip then
        targetStrip = addon.EffectIcons.Create(UIParent, 36, 6, 20)
        frame:HookScript("OnHide", function() targetStrip:Hide() end)
    end
    local player = frame:IsShown() and addon.EffectDisplay.UnitPlayerID("target")
    local anchor = frame.Header or frame
    targetStrip:SetScale(frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    addon.EffectIcons.Configure(targetStrip, { width = math.min(300, math.max(160, frame:GetWidth())),
        maxHeight = 80, minSize = 20, maxSize = 36, gap = 5 })
    if player then addon.TimedEffects.RequestSnapshot(player) end
    addon.EffectIcons.Update(targetStrip, player)
    addon.EffectBar.Bind(targetStrip, anchor)
end

local function updateProfile()
    local frame = _G.TRP3_RegisterMain
    if not frame or not frame:IsShown() then return end
     
    if not profileStrip then
        profileStrip = addon.EffectIcons.Create(frame, 34, 8, 16)
        profileStrip:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -40, 8)
        addon.EffectIcons.Configure(profileStrip, { width = 260, maxHeight = 80, minSize = 20, maxSize = 34, gap = 5 })
    end
    local context = TRP3_API.navigation.page.getCurrentContext()
    local player = context and not context.isEditMode and (context.isPlayer and me() or context.unitID)
    if player then addon.TimedEffects.RequestSnapshot(player) end
    addon.EffectIcons.Update(profileStrip, player)
end

local function updatePlates()
    local available = enabled("rpspellbook_aura_nameplates") and enabled("kui_nameplates_enable")
        and _G.KuiNameplates and type(KuiNameplates.Frames) == "function"
    for _, strip in pairs(plates) do strip:Hide() end
    if not available then return end
    if enabled("kui_nameplates_only_in_character") and (not TRP3_API.dashboard or not TRP3_API.dashboard.isPlayerIC()) then return end
    for _, plate in KuiNameplates:Frames() do
        local player = plate.unit and addon.EffectDisplay.UnitPlayerID(plate.unit)
        if player and plate:IsShown() and plate.NameText and plate.NameText:IsShown()
            and plate.state and plate.state.friend and not plate.state.personal then
            local strip = plates[plate]
            if not strip then
                strip = addon.EffectIcons.Create(plate, 20, 8, 8, true)
                addon.EffectIcons.Configure(strip, { width = 132, maxHeight = 22, minSize = 12, maxSize = 20, gap = 4 })
                plates[plate] = strip
            end
            strip:ClearAllPoints()
            strip:SetPoint("BOTTOM", plate.NameText, "TOP", 0, 4)
            addon.TimedEffects.RequestSnapshot(player)
            addon.EffectIcons.Update(strip, player)
        end
    end
end

function surfaces.Refresh()
    if not initialized then return end
    if addon.EffectIcons.IsSuppressed() then addon.EffectIcons.HideAll(); return end
    updateInspection()
    updateTarget()
    updateProfile()
     
    pcall(updatePlates)
end

function surfaces.Initialize()
    if initialized or not _G.TRP3_API then return end
    initialized = true
    local api = TRP3_API
    for _, name in ipairs({ "TRP3_InspectionFrame", "TRP3_InventoryPage", "TRP3_RegisterMain", "TRP3_TargetFrame" }) do
        if _G[name] then _G[name]:HookScript("OnShow", surfaces.Refresh) end
    end
    if api.inventory and api.inventory.requestCharacterInspection then
        hooksecurefunc(api.inventory, "requestCharacterInspection", updateInspection)
    end
    local auras = api.extended and api.extended.auras
    if auras and auras.showInspectAuras then
        hooksecurefunc(auras, "showInspectAuras", function(entries)
            local frame = _G.TRP3_InspectionFrame
            if frame and frame.current then
                addon.EffectDisplay.RememberInspection(frame.current, entries)
                 
                for _, child in ipairs({ frame.Main:GetChildren() }) do
                    if child.aura and child.SetAuraAndShow then child:Hide() end
                end
                updateInspection()
            end
        end)
    end
    addon.TimedEffects.RegisterListener(surfaces.Refresh)
    addon.GameMasterService.RegisterListener(surfaces.Refresh)
    if api.RegisterCallback then
        api.RegisterCallback(_G.TRP3_Addon, "REGISTER_DATA_UPDATED", surfaces.Refresh)
        api.RegisterCallback(_G.TRP3_Addon, "REGISTER_PROFILE_OPENED", surfaces.Refresh)
    end
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE",
        "UNIT_ENTERING_VEHICLE", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "UPDATE_VEHICLE_ACTIONBAR",
        "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, unit)
        addon.EffectIcons.ActivityChanged(event, unit)
        surfaces.Refresh()
    end)
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, surfaces.Refresh) end
    surfaces.Refresh()
end
