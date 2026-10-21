local _, addon = ...

 
 
local Scene = {}
addon.BookScene = Scene
local PAGE = 375503
local states = setmetatable({}, { __mode = "k" })
local durations = { page = 0.56, open = 0.72, close = 0.65, zoom = 0.52, unzoom = 0.44 }

local function reducedMotion()
    local settings = addon.SpellCreationSettings
    return settings and settings.ShouldReduceBookMotion and settings.ShouldReduceBookMotion() or false
end

local function invoke(callback)
    if callback then callback() end
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function smooth(t)
    return t * t * (3 - 2 * t)
end

local function rect(region, surface)
    if not region or not region.GetLeft then return end
    local left, top = region:GetLeft(), region:GetTop()
    local originX, originY = surface:GetLeft(), surface:GetTop()
    if not left or not top or not originX or not originY then return end
    local ratio = region:GetEffectiveScale() / surface:GetEffectiveScale()
    return left * ratio - originX, originY - top * ratio,
        region:GetWidth() * ratio, region:GetHeight() * ratio
end

local function measure(region, surface)
    local x, y, width, height = rect(region, surface)
    if not x or width <= 0 or height <= 0 then return end
    local result = { x = x, y = y, width = width, height = height, alpha = region:GetAlpha() }
    if region.GetFont then
        result.path, result.size, result.flags = region:GetFont()
        if result.size then result.size = result.size * region:GetEffectiveScale() / surface:GetEffectiveScale() end
    end
    return result
end

local function restorePendingView(state)
    local pending = state.pendingView
    state.pendingView = nil
    if not pending then return end
    pending.view:SetAlpha(pending.alpha)
    pending.view:SetShown(pending.shown)
end

local function ensure(panel)
    if states[panel] then return states[panel] end
    local surface = panel.bookSurface or panel
    local host = CreateFrame("Frame", nil, panel)
    host:SetAllPoints(surface)
    host:SetFrameLevel(panel:GetFrameLevel() + 40)
    host:SetClipsChildren(true)
    host:EnableMouse(panel.bookSceneInputFree ~= true)
    host:EnableMouseWheel(false)
    local clip = CreateFrame("Frame", nil, host)
    clip:SetClipsChildren(true)
    local page = CreateFrame("Frame", nil, clip, "BackdropTemplate")
    page.bookAnimationManaged = true
    local ink = CreateFrame("Frame", nil, page)
    ink:SetAllPoints(page)
    local cover = page:CreateTexture(nil, "OVERLAY", nil, 6)
    cover:SetAllPoints(page)
    cover:SetColorTexture(0.07, 0.035, 0.018, 0.72)
    cover:Hide()
    local curl = CreateFrame("Frame", nil, host)
    curl:SetAllPoints(host)
    curl:SetFrameLevel(host:GetFrameLevel() + 8)
    local hero = CreateFrame("Frame", nil, host)
    hero:SetAllPoints(host)
    hero.icon = hero:CreateTexture(nil, "ARTWORK")
    hero.name = hero:CreateFontString(nil, "OVERLAY")
    hero:Hide()
    local strips, shadows = {}, {}
    for i = 1, 16 do
        local texture = curl:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(PAGE)
        strips[i] = texture
    end
    for i = 1, 8 do
        shadows[i] = curl:CreateTexture(nil, "BACKGROUND")
    end
    local state = { panel = panel, surface = surface, host = host, clip = clip,
        page = page, ink = ink, cover = cover, curl = curl, strips = strips, shadows = shadows,
        labels = {}, icons = {}, hero = hero, generation = 0 }
    states[panel] = state
    panel.bookScene = state
    host:Hide()
    panel:HookScript("OnHide", function() Scene.Stop(panel) end)
    panel:HookScript("OnSizeChanged", function()
         
        local callback = state.callback
        Scene.Stop(panel)
        invoke(callback)
    end)
    return state
end

local function copyRegion(state, source, pool, index, isText)
    if not source or not source:IsShown() then return index end
    local x, y, width, height = rect(source, state.surface)
    if not x or width <= 0 or height <= 0 then return index end
    index = index + 1
    local copy = pool[index]
    if not copy then
        copy = isText and state.ink:CreateFontString(nil, "OVERLAY")
            or state.ink:CreateTexture(nil, "ARTWORK")
        pool[index] = copy
    end
    copy:ClearAllPoints()
    copy:SetPoint("TOPLEFT", state.ink, "TOPLEFT", x, -y)
    copy:SetSize(width, height)
    if isText then
        copy:SetFont(source:GetFont())
        copy:SetText(source:GetText())
        copy:SetTextColor(source:GetTextColor())
        copy:SetJustifyH(source:GetJustifyH())
        copy:SetJustifyV(source:GetJustifyV())
        copy:SetWordWrap(true)
        copy:SetMaxLines(source.GetMaxLines and source:GetMaxLines() or 0)
        if source.GetShadowColor then copy:SetShadowColor(source:GetShadowColor()) end
        if source.GetShadowOffset then copy:SetShadowOffset(source:GetShadowOffset()) end
    else
        copy:SetTexture(source:GetTexture())
        copy:SetTexCoord(source:GetTexCoord())
        copy:SetBlendMode(source:GetBlendMode())
        copy:SetDesaturation(source:GetDesaturation())
        copy:SetVertexColor(source:GetVertexColor())
    end
    copy:SetAlpha(source:GetAlpha())
    copy:Show()
    if not isText and addon.UIFactory.CopySpellIconEffectFrame then
        addon.UIFactory.CopySpellIconEffectFrame(source, copy)
    end
    state.copies[source] = copy
    return index
end

local function snapshot(state)
    local panel, labels, icons = state.panel, {}, {}
    if addon.FancyBookControls then
        for _, slot in ipairs(panel.spellSlots or {}) do addon.FancyBookControls.CancelInscription(slot) end
    end
    state.copies = {}
    if panel.title then labels[#labels + 1] = panel.title end
    if panel.detailSpellID and panel.detailsView then
        for _, key in ipairs({ "name", "magicSubtitle", "metadata", "descriptionTitle",
                "description", "tagsTitle", "tags" }) do
            labels[#labels + 1] = panel.detailsView[key]
        end
        icons[#icons + 1] = panel.detailsView.icon
    elseif panel.spellSlots then
        for _, slot in ipairs(panel.spellSlots) do
            if slot.spellID and slot:IsShown() then
                labels[#labels + 1], icons[#icons + 1] = slot.name, slot.icon
                if slot.excerpt then labels[#labels + 1] = slot.excerpt end
            end
        end
        if panel.pageNumber then labels[#labels + 1] = panel.pageNumber end
    else  
        labels, icons = panel.labels or {}, panel.icons or {}
    end
    local count = 0
    for _, source in ipairs(labels) do count = copyRegion(state, source, state.labels, count, true) end
    for i = count + 1, #state.labels do state.labels[i]:Hide() end
    count = 0
    for _, source in ipairs(icons) do count = copyRegion(state, source, state.icons, count, false) end
    for i = count + 1, #state.icons do
        state.icons[i]:Hide()
        addon.UIFactory.ClearSpellIconEffectFrame(state.icons[i])
    end
end

local function transform(state, scale, x, y)
     
    state.page:SetScale(scale)
    state.page:ClearAllPoints()
    state.page:SetPoint("TOPLEFT", state.host, "TOPLEFT", x / scale, -y / scale)
    if addon.UIFactory.RefreshSpellIconEffectFrame then
        for _, icon in ipairs(state.icons) do addon.UIFactory.RefreshSpellIconEffectFrame(icon) end
    end
end

local function setReadingLayer(state, reading)
    local level = state.panel:GetFrameLevel()
    state.reading = reading == true
    state.host:SetFrameLevel(level + (reading and 0 or 40))
    state.clip:SetFrameLevel(level + (reading and 0 or 41))
    state.page:SetFrameLevel(level + (reading and 0 or 42))
    state.ink:SetFrameLevel(level + (reading and 0 or 43))
    state.curl:SetFrameLevel(level + 48)
    state.hero:SetFrameLevel(level + 49)
    state.host:EnableMouse(not reading and state.panel.bookSceneInputFree ~= true)
end

local function prepare(state)
    state.width, state.height = math.max(1, state.surface:GetWidth()), math.max(1, state.surface:GetHeight())
    setReadingLayer(state, false)
    state.host:SetAlpha(1)
    state.host:Show()
    state.clip:ClearAllPoints()
    state.clip:SetPoint("TOPLEFT", state.host, "TOPLEFT", 0, 0)
    state.clip:SetSize(state.width, state.height)
    state.page:SetSize(state.width, state.height)
    transform(state, 1, 0, 0)
    state.ink:SetAlpha(1)
    state.ink:Show()
    state.cover:Hide()
    state.curl:Hide()
    state.hero:Hide()
    addon.SpellCreationThemes.ApplyBook(state.page, "fancy")
    if state.page._fancyRibbonHost then state.page._fancyRibbonHost:Hide() end
    snapshot(state)
    if GameTooltip then GameTooltip:Hide() end
    if addon.SpellTooltip then addon.SpellTooltip.Hide() end
end

local function curl(state, edge, amount, direction, binding)
    local width, height = state.width, state.height
    local breadth = width * (binding and 0.22 or 0.14) * math.sin(math.pi * amount)
    state.curl:SetShown(breadth > 0.5)
    for i, strip in ipairs(state.strips) do
        local t = (i - 0.5) / #state.strips
        local step = breadth / #state.strips
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", state.host, "TOPLEFT",
            edge + (direction == 1 and -breadth or 0) + (i - 1) * step, 0)
        strip:SetSize(math.max(0.01, step + 0.5), height)
         
         
        local u = 0.70 - t * 0.35
        strip:SetTexCoord(u, u - 0.35 / #state.strips, 0.01, 0.965)
        local shade = 0.48 + 0.52 * math.sin(math.pi * t)
        if binding then strip:SetVertexColor(shade * 0.42, shade * 0.31, shade * 0.21)
        else strip:SetVertexColor(shade, shade * 0.96, shade * 0.88) end
    end
    for i, shadow in ipairs(state.shadows) do
        shadow:ClearAllPoints()
        local step = math.max(1, breadth * 0.45 / #state.shadows)
        shadow:SetPoint("TOPLEFT", state.host, "TOPLEFT",
            edge + (direction == 1 and (i - 1) * step or -i * step), 0)
        shadow:SetSize(step + 0.5, height)
        shadow:SetColorTexture(0.055, 0.022, 0.01, (1 - i / 9) * 0.24)
    end
end

local function run(state, kind, update, callback)
    state.generation = state.generation + 1
    local token, elapsed = state.generation, 0
    state.playing, state.kind, state.callback = true, kind, callback
    local function finish()
        if state.generation ~= token or not state.playing then return false end
        update(1)
        if state.generation ~= token or not state.playing then return false end
        state.host:SetScript("OnUpdate", nil)
        state.playing, state.callback, state.finish = false, nil, nil
        if kind ~= "zoom" then state.host:Hide() end
        invoke(callback)
        return true
    end
    state.finish = finish
    update(0)
    state.host:SetScript("OnUpdate", function(_, delta)
        if state.generation ~= token then return end
        if state.panel.bookSceneOwnerValid and not state.panel.bookSceneOwnerValid() then
            Scene.Stop(state.panel)
            state.panel:Hide()
            return
        end
        if reducedMotion() then finish(); return end
        elapsed = elapsed + delta
        local t = math.min(1, elapsed / durations[kind])
        if t < 1 then update(smooth(t)); return end
         
         
        finish()
    end)
end

function Scene.Stop(panel)
    local state = states[panel]
    if not state then return end
    state.generation = state.generation + 1
    state.playing, state.callback, state.finish = false, nil, nil
    state.host:SetScript("OnUpdate", nil)
    state.host:Hide()
    state.hero:Hide()
    restorePendingView(state)
    state.reading = false
    state.zoom = nil
end

 
function Scene.Finish(panel)
    local state = states[panel]
    return state and state.finish and state.finish() or false
end

function Scene.IsPlaying(panel)
    return states[panel] and states[panel].playing == true or false
end

function Scene.Play(panel, kind, callback, direction)
    if reducedMotion() then Scene.Stop(panel); invoke(callback); return false end
    if (kind ~= "page" and kind ~= "open" and kind ~= "close") or not panel:IsVisible() then
        invoke(callback)
        return false
    end
    local state = ensure(panel)
    if state.playing then
        if kind ~= "close" then return false end
        Scene.Stop(panel)
    end
    prepare(state)
    direction = direction == -1 and -1 or 1
    if kind == "page" then
         
         
        local token = state.generation
        state.playing = true
        invoke(callback)
        if state.generation ~= token then return false end
        if not panel:IsVisible() then Scene.Stop(panel) return false end
        run(state, kind, function(t)
            local edge = state.width * (direction == 1 and (1 - t) or t)
            state.clip:ClearAllPoints()
            state.clip:SetPoint("TOPLEFT", state.host, "TOPLEFT", direction == 1 and 0 or edge, 0)
            state.clip:SetSize(math.max(0.01, state.width * (1 - t)), state.height)
            curl(state, edge, t, direction, false)
        end)
    else
         
         
        state.ink:Hide()
        state.cover:Show()
        run(state, kind, function(t)
            local covered = kind == "open" and (1 - t) or t
            state.clip:SetWidth(math.max(0.01, state.width * covered))
            curl(state, state.width * covered, covered, kind == "open" and 1 or -1, true)
        end, callback)
    end
    return true
end

local function placeHero(state, t)
    local hero = state.hero
    for _, key in ipairs({ "icon", "name" }) do
        local item = state.zoom[key]
        if item then
            local region, from, to = hero[key], item.from, item.to
            local function mix(a, b) return a + (b - a) * t end
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", hero, "TOPLEFT", mix(from.x, to.x), -mix(from.y, to.y))
            region:SetSize(mix(from.width, to.width), mix(from.height, to.height))
            if key == "name" and from.size and to.size then
                region:SetFont(to.path, mix(from.size, to.size), to.flags or "")
                local a, b = item.fromColor, item.toColor
                region:SetTextColor(mix(a[1], b[1]), mix(a[2], b[2]), mix(a[3], b[3]), mix(a[4], b[4]))
            end
            region:SetAlpha(mix(from.alpha, to.alpha))
            region:Show()
            if key == "icon" and addon.UIFactory.RefreshSpellIconEffectFrame then
                addon.UIFactory.RefreshSpellIconEffectFrame(region, mix(item.fromScale, item.toScale))
            end
        else
            hero[key]:Hide()
            if key == "icon" then addon.UIFactory.ClearSpellIconEffectFrame(hero.icon) end
        end
    end
end

function Scene.Zoom(panel, spellID, callback, prepareTarget)
    if reducedMotion() then Scene.Stop(panel); invoke(callback); return false end
    if not panel:IsVisible() then invoke(callback) return false end
    local state = ensure(panel)
    if state.playing then return false end
    local source
    for _, slot in ipairs(panel.spellSlots or {}) do
        if slot.spellID == spellID and slot:IsShown() then source = slot break end
    end
    if not source then invoke(callback) return false end
    prepare(state)
    local from = measure(source.icon, state.surface)
    if not from then state.host:Hide() invoke(callback) return false end
    local view = prepareTarget and prepareTarget()
    if view then
        state.pendingView = { view = view, alpha = view:GetAlpha(), shown = view:IsShown() }
        view:SetAlpha(0)
        view:Show()
        if addon.SpellDetailsView.Layout then addon.SpellDetailsView.Layout(view) end
    end
    local target = view and measure(view.icon, state.surface)
    local scale = target and clamp(target.width / from.width, 1, 4) or 2
    local dx = clamp((target and target.x or state.width * 0.15) - from.x * scale, state.width * (1 - scale), 0)
    local dy = clamp((target and target.y or state.height * 0.23) - from.y * scale, state.height * (1 - scale), 0)
    state.zoom = { scale = scale, x = dx, y = dy }
    if target then
        state.zoom.icon = { from = from, to = target,
            fromScale = source.icon:GetEffectiveScale(), toScale = view.icon:GetEffectiveScale() }
        state.hero.icon:SetTexture(source.icon:GetTexture())
        state.hero.icon:SetTexCoord(source.icon:GetTexCoord())
        state.hero.icon:SetBlendMode(source.icon:GetBlendMode())
        state.hero.icon:SetDesaturation(source.icon:GetDesaturation())
        state.hero.icon:SetVertexColor(source.icon:GetVertexColor())
        state.hero.icon:SetAlpha(source.icon:GetAlpha())
        if addon.UIFactory.CopySpellIconEffectFrame then
            addon.UIFactory.CopySpellIconEffectFrame(source.icon, state.hero.icon)
        end
        if state.copies[source.icon] then
            state.copies[source.icon]:Hide()
            addon.UIFactory.ClearSpellIconEffectFrame(state.copies[source.icon])
        end
        local fromName, toName = measure(source.name, state.surface), measure(view.name, state.surface)
        if fromName and toName then
            state.zoom.name = { from = fromName, to = toName,
                fromColor = { source.name:GetTextColor() }, toColor = { view.name:GetTextColor() } }
             
            state.hero.name:SetFont(toName.path, fromName.size, toName.flags or "")
            state.hero.name:SetText(view.name:GetText())
            state.hero.name:SetWordWrap(true)
            state.hero.name:SetTextColor(view.name:GetTextColor())
            state.hero.name:SetAlpha(source.name:GetAlpha())
            state.hero.name:SetJustifyH(view.name:GetJustifyH())
            state.hero.name:SetJustifyV(view.name:GetJustifyV())
            if view.name.GetShadowColor then state.hero.name:SetShadowColor(view.name:GetShadowColor()) end
            if view.name.GetShadowOffset then state.hero.name:SetShadowOffset(view.name:GetShadowOffset()) end
            if state.copies[source.name] then state.copies[source.name]:Hide() end
        end
        state.hero:Show()
    end
    run(state, "zoom", function(t)
        transform(state, 1 + (scale - 1) * t, dx * t, dy * t)
        state.ink:SetAlpha(1 - clamp((t - 0.68) / 0.32, 0, 1))
        placeHero(state, t)
    end, function()
        restorePendingView(state)
        if not state.zoom then invoke(callback) return end
         
         
        setReadingLayer(state, true)
        state.ink:Hide()
        state.host:Show()
        invoke(callback)
        state.hero:Hide()
    end)
    return true
end

function Scene.Unzoom(panel, callback)
    if reducedMotion() then Scene.Stop(panel); invoke(callback); return false end
    local state = states[panel]
    if not state or not state.zoom then invoke(callback) return false end
    if state.playing then return false end
    local zoom = state.zoom
     
    setReadingLayer(state, false)
    state.host:Show()
    state.ink:Show()
    if zoom.icon then state.hero:Show() end
    run(state, "unzoom", function(t)
        transform(state, zoom.scale + (1 - zoom.scale) * t, zoom.x * (1 - t), zoom.y * (1 - t))
        state.ink:SetAlpha(t)
        placeHero(state, 1 - t)
    end, function()
        state.zoom = nil
        invoke(callback)
    end)
    return true
end
