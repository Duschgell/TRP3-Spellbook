local _, addon = ...

local style = {}
addon.BookNavigationStyle = style

local headingFrame, driver, styledText, motionEnabled
local animations = {}
local FANCY_COLOR = { 0.30, 0.88, 0.81 }

local function visible(frame)
    if type(frame.IsVisible) == "function" then return frame:IsVisible() end
    return frame:IsShown()
end

local function luminance(color)
    local value = 0
    for index, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
        local component = color[index]
        value = value + weight * (component <= 0.04045 and component / 12.92
            or ((component + 0.055) / 1.055) ^ 2.4)
    end
    return value
end

function style.GetColor()
    if addon.SpellCreationSettings.IsFancyMode() then
        return FANCY_COLOR[1], FANCY_COLOR[2], FANCY_COLOR[3]
    end
    local root = addon.Database.GetDB()
    local profiles = type(root) == "table" and root.profiles
    local profile = type(profiles) == "table" and profiles[addon.Database.GetActiveProfileKey()]
    local book = type(profile) == "table" and type(profile.spellbook) == "table" and profile.spellbook
    local panel = addon.TRP3Integration and addon.TRP3Integration.GetSpellbookPanel()
    local tabID = panel and panel.spellbook == book and panel.activeTabID
        or (book and type(book.tabOrder) == "table" and book.tabOrder[1])
    local tab = book and type(book.tabs) == "table" and book.tabs[tabID]
    if type(tab) ~= "table" then tab = nil end
    local selected = tab and tab.themeID or "default"
    local spec = addon.SpellCreationThemes.Resolve(selected ~= "fancy" and selected or "default")
    local accent = spec.accent
    local color = { accent[1], accent[2], accent[3] }
    for _ = 1, 20 do
        local dimmed = { color[1] * 0.92, color[2] * 0.92, color[3] * 0.92 }
        if (luminance(dimmed) + 0.05) / (luminance({ 0.24, 0.19, 0.14 }) + 0.05) >= 4.5 then break end
        for index = 1, 3 do color[index] = color[index] + (1 - color[index]) * 0.1 end
    end
    return color[1], color[2], color[3]
end

function style.GetText()
    local red, green, blue = style.GetColor()
    return string.format("|cff%02x%02x%02x%s|r", math.floor(red * 255 + 0.5),
        math.floor(green * 255 + 0.5), math.floor(blue * 255 + 0.5), addon.L("ADDON_TITLE"))
end

local function stop(state)
    if state.playing then
        state.group:Stop()
        state.label:SetAlpha(1)
        state.playing = false
    end
end

local function animate(owner, label)
    local state = animations[owner]
    if not state then
        if not label or type(label.CreateAnimationGroup) ~= "function" or type(owner.HookScript) ~= "function" then return end
        local group = label:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        local alpha = group:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0.92)
        alpha:SetToAlpha(1)
        alpha:SetDuration(2.4)
        alpha:SetSmoothing("IN_OUT")
        state = { label = label, group = group }
        animations[owner] = state
        owner:HookScript("OnHide", function() stop(state) end)
    end
    if not state.playing then
        state.group:Play()
        state.playing = true
    end
end

local function refreshAnimations()
    for owner, state in pairs(animations) do
        if not motionEnabled or not visible(owner)
            or (owner ~= headingFrame and owner:GetText() ~= styledText) then
            stop(state)
        end
    end
    if not motionEnabled then return end
    if headingFrame and visible(headingFrame) then animate(headingFrame, headingFrame.Title) end
    local container = _G.TRP3_MainFrameMenuContainer
    if not container or not visible(container) then return end
    for _, button in ipairs({ container:GetChildren() }) do
        if type(button.GetText) == "function" and type(button.GetFontString) == "function"
            and visible(button) and button:GetText() == styledText then
            animate(button, button:GetFontString())
        end
    end
end

local function onUpdate(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.2 then return end
    self.elapsed = 0
    refreshAnimations()
end

function style.Refresh()
    styledText = style.GetText()
    motionEnabled = addon.SpellCreationSettings.IsFancyMode()
        and not addon.SpellCreationSettings.ShouldReduceBookMotion()
    local api = _G.TRP3_API
    local menu = api and api.navigation and api.navigation.menu
    local changed = false
    if menu and type(menu.getMenuItem) == "function" then
        for _, id in ipairs({ "main_91_config_" .. addon.Constants.GAMEMASTER_SETTINGS_PAGE_ID,
            addon.Constants.NAVIGATION_MENU_ID }) do
            local ok, item = pcall(menu.getMenuItem, id)
            if ok and item and item.text ~= styledText then item.text = styledText; changed = true end
        end
        if changed and type(menu.rebuildMenu) == "function" then menu.rebuildMenu() end
    end
    if headingFrame and headingFrame.Title:GetText() ~= styledText then
        headingFrame.Title:SetText(styledText)
    end
    if driver then
        driver:SetScript("OnUpdate", motionEnabled and onUpdate or nil)
    end
    refreshAnimations()
end

function style.Initialize(frame)
    if headingFrame then return end
    headingFrame = frame
    frame:HookScript("OnShow", style.Refresh)
    addon.SpellCreationSettings.RegisterListener(style.Refresh)
    local container = _G.TRP3_MainFrameMenuContainer
    if container then
        driver = CreateFrame("Frame", nil, container)
        driver:SetScript("OnShow", style.Refresh)
        driver:SetScript("OnHide", function()
            for _, state in pairs(animations) do stop(state) end
        end)
    end
    style.Refresh()
end
