local _, addon = ...

addon.EffectBar = {}
local effectBar = addon.EffectBar
local LOCK_KEY = "rpspellbook_effect_bar_locked"
local initialized, bar, anchor, dragging, dragSource, dragPlayer, dragProfile, locked
local hookedIcons = setmetatable({}, { __mode = "k" })

local function settings(create)
    local root = addon.Database.GetDB()
    if type(root) ~= "table" then return end
    if create and type(root.settings) ~= "table" then root.settings = {} end
    return type(root.settings) == "table" and root.settings or nil
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function applyPosition()
    if not bar or dragging then return end
    local data = settings()
    local position = data and data.effectBarPosition
    bar:ClearAllPoints()
    if type(position) == "table" and finite(position.x) and finite(position.y) then
        local halfWidth, halfHeight = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
        local scale = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
        bar:SetPoint("CENTER", UIParent, "CENTER",
            math.max(-halfWidth, math.min(halfWidth, position.x)) / scale,
            math.max(-halfHeight, math.min(halfHeight, position.y)) / scale)
    elseif anchor then
        bar:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -80)
    end
end

local function stopMoving()
    if not bar or not dragging then return end
    dragging = false
    dragSource, dragPlayer, dragProfile = nil, nil, nil
    bar:StopMovingOrSizing()
    local x, y = bar:GetCenter()
    local scale = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local data = settings(true)
    if data and finite(x) and finite(y) and finite(scale) and scale > 0 then
        local offsetX = x * scale - UIParent:GetWidth() / 2
        local offsetY = y * scale - UIParent:GetHeight() / 2
        if finite(offsetX) and finite(offsetY) then
            data.effectBarPosition = { x = offsetX, y = offsetY }
        end
    end
    applyPosition()
end

local function startMoving(source)
    if locked or not bar.player or addon.EffectIcons.IsSuppressed()
        or bar.profile ~= addon.Database.GetActiveProfileKey() then return end
    if source and (source:GetParent() ~= bar or source.effectStrip ~= bar
        or not source.entry and not source.overflow) then return end
    bar:StartMoving()
    dragging, dragSource, dragPlayer, dragProfile = true, source, bar.player, bar.profile
    if source then source.effectBarDragged = true end
end

local function bindIcons()
    if not bar then return end
    for _, icon in ipairs(bar.buttons) do
        if not hookedIcons[icon] then
            hookedIcons[icon] = true
            icon:EnableMouse(true)
            icon:HookScript("OnDragStart", function(self) startMoving(self) end)
            icon:HookScript("OnMouseDown", function(self) self.effectBarDragged = nil end)
            icon:HookScript("OnDragStop", function(self)
                if dragSource == self then stopMoving() end
            end)
            icon:HookScript("OnHide", function(self)
                if dragSource == self then stopMoving() end
            end)
        end
        if locked then icon:RegisterForDrag() else icon:RegisterForDrag("LeftButton") end
    end
end

local function applyLock()
    if not bar then return end
    local configuration = _G.TRP3_API and TRP3_API.configuration
    locked = false
    if configuration and type(configuration.getValue) == "function" then
        local ok, value = pcall(configuration.getValue, LOCK_KEY)
        locked = ok and value == true
    end
    if locked then stopMoving() end
    bar:SetMovable(not locked)
    if locked then bar:RegisterForDrag() else bar:RegisterForDrag("LeftButton") end
    bindIcons()
end

function effectBar.Bind(strip, defaultAnchor)
    anchor = defaultAnchor
    if bar ~= strip then
        bar = strip
        bar:SetClampedToScreen(true)
        bar:EnableMouse(true)
        bar:HookScript("OnDragStart", function() startMoving() end)
        bar:HookScript("OnDragStop", stopMoving)
        bar:HookScript("OnHide", stopMoving)
        bar:HookScript("OnShow", applyPosition)
        applyLock()
    end
    if dragging and (bar.player ~= dragPlayer or bar.profile ~= dragProfile) then stopMoving() end
    applyPosition()
end

function effectBar.ResetPosition()
    if bar and dragging then bar:StopMovingOrSizing() end
    dragging = false
    dragSource, dragPlayer, dragProfile = nil, nil, nil
    local data = settings(true)
    if data then data.effectBarPosition = nil end
    applyPosition()
end

function effectBar.GetSettingsElements()
    local api = _G.TRP3_API
    local loc = api and api.loc
    if not loc then return {} end
    return {
        { inherit = "TRP3_ConfigH1", title = addon.L("TIMED_TITLE") },
        { inherit = "TRP3_ConfigCheck", title = loc.CO_GLANCE_LOCK,
            help = loc.CO_GLANCE_LOCK_TT, configKey = LOCK_KEY },
        { inherit = "TRP3_ConfigButton", title = loc.CO_MINIMAP_BUTTON_RESET,
            text = loc.CO_MINIMAP_BUTTON_RESET_BUTTON, callback = effectBar.ResetPosition },
    }
end

function effectBar.Initialize()
    if initialized then return end
    initialized = true
    addon.SpellCreationSettings.RegisterListener(applyLock)
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function()
        applyPosition()
    end)
    applyLock()
    applyPosition()
end
