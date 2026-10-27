local _, addon = ...

addon.SeasonalVisuals = {}
local Visuals = addon.SeasonalVisuals
local states = setmetatable({}, { __mode = "k" })
local kinds = { book = true, npc = true, import = true, settings = true }
local initialized, shuttingDown = false, false
local debugTheme = "auto"
local DECORATION_LEVEL = 60
local positions = { 0.025, 0.08, 0.90, 0.96 }
local batPositions, batHeights = { 0.08, 0.82, 0.2 }, { 0.22, 0.62, 0.78 }
local snowPositions = { 0.04, 0.14, 0.24, 0.34, 0.44, 0.54, 0.64, 0.74, 0.84, 0.94, 0.29, 0.69 }
local lightColors = {
    { 0.24, 0.58, 1 }, { 1, 0.22, 0.18 }, { 1, 0.8, 0.2 }, { 0.24, 1, 0.35 }, { 1, 0.26, 0.18 },
}

local function visible(owner)
    return owner and type(owner.IsVisible) == "function" and owner:IsVisible()
end

local function theme()
    if shuttingDown or (addon.Core and addon.Core.enabled ~= true) then return nil end
    local settings = addon.SpellCreationSettings
    if not settings or not settings.ShouldUseSeasonalThemes() then return nil end
    local forced = debugTheme
    if forced == "off" then return nil end
    if forced ~= "auto" then return addon.SeasonalStyles.Get(forced) and forced or nil end
    local calendar = addon.SeasonalCalendar
    return calendar and addon.SeasonalStyles.Resolve(calendar.GetActiveThemes()) or nil
end

local function stop(state)
    state.active = false
    if not state.host then return end
    for _, sprite in ipairs(state.sprites) do
        if sprite.group then sprite.group:Stop() end
        if sprite.flipGroup then sprite.flipGroup:Stop() end
    end
    if state.light then
        if state.light.group then state.light.group:Stop() end
        state.light.frame:Hide()
    end
    addon.SeasonalCorners.Hide(state.host)
    state.host:Hide()
    if state.garland then state.garland:Hide() end
end

local function sprite(host)
    local texture = host:CreateTexture(nil, "ARTWORK")
    local result = { texture = texture }
    if type(texture.CreateAnimationGroup) == "function" then
        result.group = texture:CreateAnimationGroup()
        result.group:SetLooping("REPEAT")
        result.move = result.group:CreateAnimation("Translation")
        result.fadeIn = result.group:CreateAnimation("Alpha")
        result.fadeOut = result.group:CreateAnimation("Alpha")
        result.move:SetOrder(1)
        result.fadeIn:SetOrder(1)
        result.fadeOut:SetOrder(1)
        result.fadeIn:SetFromAlpha(0)
        result.fadeOut:SetToAlpha(0)
    end
    return result
end

local function createHost(owner, state)
    local host = CreateFrame("Frame", nil, owner)
    host:SetAllPoints(owner)
    host:SetFrameLevel(owner:GetFrameLevel() + DECORATION_LEVEL)
    host:SetClipsChildren(true)
    host:EnableMouse(false)
    host:EnableMouseWheel(false)
    host.bookAnimationManaged = true
    host:Hide()
    state.host, state.sprites = host, {}
    for index = 1, #positions do state.sprites[index] = sprite(host) end
    host.sprites = state.sprites
    owner.seasonalDecoration = host
end

local function batAnimation(item, index, reduced)
    if not item.flipGroup and type(item.texture.CreateAnimationGroup) == "function" then
        item.flipGroup = item.texture:CreateAnimationGroup()
        item.flipGroup:SetLooping("REPEAT")
        item.flip = item.flipGroup:CreateAnimation("FlipBook")
        item.flip:SetOrder(1)
        item.flip:SetFlipBookRows(4)
        item.flip:SetFlipBookColumns(4)
        item.flip:SetFlipBookFrames(12)
        item.flip:SetFlipBookFrameWidth(0)
        item.flip:SetFlipBookFrameHeight(0)
        item.flip:SetDuration(0.65 + index * 0.05)
    end
    if reduced or not item.flipGroup then
        item.texture:SetTexCoord(0, 0.25, 0, 0.25)
    end
end

local function edgeWebs(host, textureID, width, height)
    if not host.webs then
        host.webs = {}
        for index = 1, 3 do host.webs[index] = host:CreateTexture(nil, "ARTWORK") end
    end
    local size = math.min(72, width * 0.14, height * 0.16)
    for index, texture in ipairs(host.webs) do
        local corner = index == 1 and "TOPLEFT" or index == 2 and "BOTTOMRIGHT" or "BOTTOMLEFT"
        texture:ClearAllPoints()
        texture:SetPoint(corner, host, corner, 0, 0)
        local length = size * (index == 1 and 1 or index == 2 and 0.85 or 0.7)
        texture:SetSize(length, length)
        texture:SetTexture(textureID)
        texture:SetBlendMode("BLEND")
        texture:SetVertexColor(1, 1, 1, 0.25)
        texture:SetAlpha(1)
        texture:SetTexCoord(index == 2 and 1 or 0, index == 2 and 0 or 1,
            index == 1 and 0 or 1, index == 1 and 1 or 0)
        texture:Show()
    end
end

local function moonlight(state, width, height)
    local light = state.light
    if not light then
        local frame = CreateFrame("Frame", nil, state.host)
        frame:SetAllPoints(state.host)
        frame:EnableMouse(false)
        frame:EnableMouseWheel(false)
        light = { frame = frame, bands = {} }
        for index = 1, 24 do
            local texture = frame:CreateTexture(nil, "BACKGROUND")
            texture:SetColorTexture(0.38, 0.65, 1, 0.16 * (1 - (index - 1) / 23) ^ 1.5)
            light.bands[index] = texture
        end
        if type(frame.CreateAnimationGroup) == "function" then
            light.group = frame:CreateAnimationGroup()
            light.group:SetLooping("BOUNCE")
            local pulse = light.group:CreateAnimation("Alpha")
            pulse:SetFromAlpha(0.8)
            pulse:SetToAlpha(1)
            pulse:SetDuration(10)
            pulse:SetSmoothing("IN_OUT")
        end
        state.light, state.host.light = light, light
    end
    light.frame:SetFrameLevel(state.host:GetFrameLevel())
    local bandHeight = height * 0.9 / #light.bands
    for index, texture in ipairs(light.bands) do
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", light.frame, "TOPLEFT", 0, -(index - 1) * bandHeight)
        texture:SetSize(width, bandHeight)
    end
    light.frame:Show()
end

local function garland(owner, state, width, ornament)
    local trim = state.garland
    if not trim then
        trim = CreateFrame("Frame", nil, owner)
        trim:EnableMouse(false)
        trim:EnableMouseWheel(false)
        trim:SetClipsChildren(false)
        trim.bookAnimationManaged = true
        trim.wire, trim.bulbs, trim.motifs = {}, {}, {}
        for index = 1, 8 do
            local line = trim:CreateLine(nil, "ARTWORK")
            line:SetThickness(1.4)
            line:SetColorTexture(0.12, 0.09, 0.045, 0.85)
            trim.wire[index] = line
        end
        for index = 1, 12 do
            local glow = trim:CreateTexture(nil, "ARTWORK")
            glow:SetTexture(166928)
            glow:SetBlendMode("ADD")
            local body = trim:CreateTexture(nil, "OVERLAY")
            local mask = trim:CreateMaskTexture()
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(body)
            body:AddMaskTexture(mask)
            local cap = trim:CreateTexture(nil, "OVERLAY")
            local tassel = trim:CreateTexture(nil, "OVERLAY")
            tassel:SetColorTexture(0.85, 0.6, 0.15, 0.85)
            tassel:SetSize(1.5, 3)
            trim.bulbs[index] = { body = body, glow = glow, cap = cap, tassel = tassel }
        end
        state.garland, owner.seasonalGarland = trim, trim
    end
    trim:SetFrameLevel(owner:GetFrameLevel() + DECORATION_LEVEL + 1)
    trim:ClearAllPoints()
    trim:SetPoint("TOPLEFT", owner, "TOPLEFT", 6, ornament.lanterns and 18 or 10)
    local length = math.max(1, width - 34)
    trim:SetSize(length, ornament.height)
    for index, line in ipairs(trim.wire) do
        local first, last = (index - 1) / #trim.wire, index / #trim.wire
        line:SetStartPoint("TOPLEFT", trim, length * first, -10 - math.sin(first * math.pi) * 4)
        line:SetEndPoint("TOPLEFT", trim, length * last, -10 - math.sin(last * math.pi) * 4)
    end
    local count = ornament.count
    local custom = ornament.motif ~= "lights" and ornament.motif ~= "lanterns"
    for index, bulb in ipairs(trim.bulbs) do
        local shown = not custom and index <= count
        bulb.body:SetShown(shown)
        bulb.cap:SetShown(shown)
        bulb.glow:SetShown(shown)
        bulb.tassel:SetShown(shown and ornament.lanterns == true)
        local color = ornament.lanterns and { 0.85, 0.12, 0.08 } or lightColors[(index - 1) % #lightColors + 1]
        bulb.glow:SetVertexColor(color[1], color[2], color[3], ornament.lanterns and 0.12 or 0.3)
        bulb.glow:SetSize(ornament.lanterns and 24 or 16, ornament.lanterns and 30 or 22)
        bulb.body:SetColorTexture(color[1], color[2], color[3], 0.9)
        bulb.body:SetSize(ornament.lanterns and 14 or 6, ornament.lanterns and 18 or 9)
        bulb.cap:SetColorTexture(ornament.lanterns and 0.85 or 0.2, ornament.lanterns and 0.6 or 0.17, 0.09, 1)
        bulb.cap:SetSize(ornament.lanterns and 10 or 4, 2)
        local fraction = index / (count + 1)
        local x, y = length * fraction, -10 - math.sin(fraction * math.pi) * 4
        bulb.glow:ClearAllPoints()
        bulb.body:ClearAllPoints()
        bulb.cap:ClearAllPoints()
        bulb.tassel:ClearAllPoints()
        bulb.glow:SetPoint("CENTER", trim, "TOPLEFT", x, y - (ornament.lanterns and 9 or 6))
        bulb.body:SetPoint("CENTER", trim, "TOPLEFT", x, y - (ornament.lanterns and 9 or 6))
        bulb.cap:SetPoint("CENTER", trim, "TOPLEFT", x, y - 1)
        bulb.tassel:SetPoint("TOP", bulb.body, "BOTTOM", 0, 0)
    end
    for index = 1, custom and count or 0 do
        local frame = trim.motifs[index]
        if not frame then
            frame = CreateFrame("Frame", nil, trim)
            frame:SetSize(26, 26)
            frame:EnableMouse(false)
            frame:EnableMouseWheel(false)
            trim.motifs[index] = frame
        end
        frame:SetFrameLevel(trim:GetFrameLevel() + 1)
        frame:ClearAllPoints()
        local fraction = index / (count + 1)
        frame:SetPoint("CENTER", trim, "TOPLEFT", length * fraction, -17 - math.sin(fraction * math.pi) * 4)
        addon.SeasonalOrnaments.Paint(frame, ornament.motif, index)
        frame:Show()
    end
    for index = (custom and count or 0) + 1, #trim.motifs do trim.motifs[index]:Hide() end
    trim:Show()
end

local function nested(owner)
    local parent = owner:GetParent()
    for _ = 1, 20 do
        if not parent then return false end
        if states[parent] then return true end
        parent = parent:GetParent()
    end
    return false
end

local function update(owner, state, selected)
    if not selected or not visible(owner) or nested(owner) then stop(state); return end
    local width, height = owner:GetWidth(), owner:GetHeight()
    if width <= 0 or height <= 0 then stop(state); return end
    local settings = addon.SpellCreationSettings
    local reduced = settings.ShouldReduceBookMotion and settings.ShouldReduceBookMotion() == true or false
    if state.active and state.theme == selected and state.reduced == reduced
        and state.width == width and state.height == height then return end
    stop(state)
    if not state.host then createHost(owner, state) end
    state.theme, state.reduced, state.width, state.height = selected, reduced, width, height
    local host = state.host
    host.theme = selected
    host:SetFrameLevel(owner:GetFrameLevel() + DECORATION_LEVEL)
    local spec = addon.SeasonalStyles.Get(selected)
    local ornament = spec.ornament
    if ornament.hanging then garland(owner, state, width, ornament) end
    local particle = spec.particle
    local columns = positions
    if reduced or spec.moonlight then columns = {}
    elseif spec.bats then columns = batPositions
    elseif spec.snowfall then columns = snowPositions end
    for index = #state.sprites + 1, #columns do state.sprites[index] = sprite(host) end
    for index = #columns + 1, #state.sprites do state.sprites[index].texture:SetShown(false) end
    for index, column in ipairs(columns) do
        local item = state.sprites[index]
        local texture = item.texture
        texture:ClearAllPoints()
        local y = particle.drift > 0 and -64 or -8
        if column > 0.5 and particle.drift < 0 then y = -38 end
        y = math.max(-height + particle.size, y - (index % 2) * 10)
        if spec.snowfall then y = -((index * 0.381966) % 1) * math.max(0, height - particle.size) end
        if spec.bats then y = -height * batHeights[index] end
        texture:SetPoint("TOPLEFT", host, "TOPLEFT", width * column, y)
        texture:SetSize(particle.size, particle.size)
        texture:SetTexture(particle.texture)
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetBlendMode(particle.blend)
        texture:SetVertexColor(particle.color[1], particle.color[2], particle.color[3], particle.alpha)
        texture:SetAlpha(1)
        texture:Show()
        if spec.bats then batAnimation(item, index, reduced) end
        if item.group and not reduced then
            local duration, dx, dy = 6 + index * 0.6, index % 2 == 0 and 10 or -10, particle.drift
            if spec.bats then
                duration = 10 + index * 1.5
                dx = width * (index % 2 == 0 and -0.62 or 0.56)
                dy = height * (index == 1 and -0.1 or 0.12)
            elseif spec.snowfall then
                duration, dy = 14 + index * 0.7, -height - particle.size
            end
            local delay = (index - 1) * (spec.snowfall and 0.17 or 0.7)
            item.move:SetDuration(duration)
            item.move:SetStartDelay(delay)
            item.move:SetOffset(dx, dy)
            item.fadeIn:SetStartDelay(delay)
            item.fadeIn:SetDuration(1.2)
            item.fadeIn:SetToAlpha(1)
            item.fadeOut:SetStartDelay(delay + duration - 1.4)
            item.fadeOut:SetDuration(1.4)
            item.fadeOut:SetFromAlpha(1)
        end
    end
    if spec.webTexture then
        edgeWebs(host, spec.webTexture, width, height)
    elseif host.webs then
        for _, texture in ipairs(host.webs) do texture:SetShown(false) end
    end
    if spec.moonlight then moonlight(state, width, height) end
    state.active = true
    host:Show()
    addon.SeasonalCorners.Refresh(host, spec, width, height)
    if not reduced then
        for index = 1, #columns do
            local item = state.sprites[index]
            if item.group then item.group:Play() end
            if spec.bats and item.flipGroup then item.flipGroup:Play() end
        end
        if spec.moonlight and state.light.group then
            state.light.group:Play()
        end
    end
end

function Visuals.Refresh()
    if not initialized then return end
    local selected = theme()
    for owner, state in pairs(states) do update(owner, state, selected) end
end

function Visuals.GetThemes() return addon.SeasonalStyles.GetThemes() end
function Visuals.GetDebugTheme() return debugTheme end

function Visuals.RefreshSettings()
    if not initialized then return end
    local settings, calendar = addon.SpellCreationSettings, addon.SeasonalCalendar
    if calendar and calendar.SetEnabled then
        calendar.SetEnabled(not shuttingDown and settings.ShouldUseSeasonalThemes() == true and debugTheme == "auto")
    end
    Visuals.Refresh()
end

function Visuals.SetDebugTheme(selected)
    if selected ~= "auto" and selected ~= "off" and not addon.SeasonalStyles.Get(selected) then return false end
    debugTheme = selected
    Visuals.RefreshSettings()
    return true
end

function Visuals.Initialize()
    if initialized then return true end
    initialized = true
    local settings = addon.SpellCreationSettings
    if settings and settings.RegisterListener then settings.RegisterListener(Visuals.RefreshSettings) end
    local calendar = addon.SeasonalCalendar
    if calendar and calendar.RegisterListener then calendar.RegisterListener(Visuals.Refresh) end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function()
        shuttingDown = true
        if calendar and calendar.SetEnabled then calendar.SetEnabled(false) end
        for _, state in pairs(states) do stop(state) end
    end)
    Visuals.RefreshSettings()
    return true
end

function Visuals.Attach(owner, kind)
    if not owner or not kinds[kind] or states[owner] or type(owner.HookScript) ~= "function" then return false end
    local state = {}
    states[owner] = state
    owner:HookScript("OnShow", Visuals.Refresh)
    owner:HookScript("OnHide", function() stop(state) end)
    owner:HookScript("OnSizeChanged", function() if initialized then update(owner, state, theme()) end end)
    if initialized then Visuals.Refresh() end
    return true
end
