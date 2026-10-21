local _, addon = ...

local controls = {}
 
addon.FancyBookControls = controls
local unpackValues = unpack or table.unpack
local BOOKMARK_WIDTH, BOOKMARK_HEIGHT, PEEK = 176, 32, 36
 
local BOOKMARK_SCENE_LEVEL = 50
local function reducedMotion()
    local settings = addon.SpellCreationSettings
    return settings and settings.ShouldReduceBookMotion and settings.ShouldReduceBookMotion() or false
end
local colors = {
    { 0.22, 0.42, 0.43 }, { 0.49, 0.20, 0.16 }, { 0.27, 0.33, 0.53 },
    { 0.37, 0.23, 0.44 }, { 0.25, 0.39, 0.20 }, { 0.51, 0.36, 0.16 },
    { 0.48, 0.25, 0.34 }, { 0.22, 0.34, 0.37 },
}

local function tooltip(owner, title, hint)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText(title, 1, 0.87, 0.60)
    if hint then GameTooltip:AddLine(hint, 0.9, 0.85, 0.75, true) end
    GameTooltip:Show()
end

local function isTransitioning(panel)
    return panel.bookClosing or (addon.BookScene and addon.BookScene.IsPlaying(panel))
end

local function pulse(texture, delay)
    local group = texture:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local brighten = group:CreateAnimation("Alpha")
    brighten:SetOrder(1)
    brighten:SetFromAlpha(0.25)
    brighten:SetToAlpha(0.90)
    brighten:SetDuration(0.85)
    brighten:SetStartDelay(delay or 0)
    brighten:SetSmoothing("IN_OUT")
    local dim = group:CreateAnimation("Alpha")
    dim:SetOrder(2)
    dim:SetFromAlpha(0.90)
    dim:SetToAlpha(0.25)
    dim:SetDuration(1.1)
    dim:SetSmoothing("IN_OUT")
    return group
end

local function setPulses(button, active)
    active = active and not reducedMotion()
    if active and not button:IsVisible() then return end
    for _, group in ipairs(button.pulses or {}) do
        if active then
            if not group:IsPlaying() then group:Play() end
        else
            group:Stop()
        end
    end
end

local function placeBookmark(button, reveal)
    local width = PEEK + (button.fullWidth - PEEK) * reveal
    button.reveal = reveal
    button.sleeve:SetWidth(width)
    button.sleeve:ClearAllPoints()
    button.sleeve:SetPoint("TOPLEFT", button.host, "TOPLEFT",
        button.inward and -(width - PEEK) or 0, button.rowY)
    button:ClearAllPoints()
     
    button:SetPoint("TOPLEFT", button.sleeve, "TOPLEFT", width - button.fullWidth, 0)
end

local function updateBookmark(button, expanded, animate)
    animate = animate and not reducedMotion()
    button:SetScript("OnUpdate", nil)
    button.expanded = expanded
    local target, from = expanded and 1 or 0, button.reveal or 0
    if not animate or from == target then placeBookmark(button, target) return end
    local elapsed = 0
    button:SetScript("OnUpdate", function(self, delta)
        elapsed = math.min(0.18, elapsed + delta)
        local t = elapsed / 0.18
        placeBookmark(self, from + (target - from) * (1 - (1 - t) ^ 3))
        if t >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

local function createBookmark(panel, parent, index)
    local sleeve = CreateFrame("Frame", nil, parent)
    sleeve:SetClipsChildren(true)
    sleeve:SetSize(BOOKMARK_WIDTH, BOOKMARK_HEIGHT + 5)
    local button = CreateFrame("Button", nil, sleeve, "BackdropTemplate")
    button.sleeve = sleeve
    button.host, button.rowY = parent, -(index - 1) * 37
    button.motionID = "bookmark" .. index
    button.fullWidth = BOOKMARK_WIDTH
    button:SetSize(BOOKMARK_WIDTH, BOOKMARK_HEIGHT)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    local cloth = button:CreateTexture(nil, "BORDER")
    cloth:SetAllPoints()
    cloth:SetTexture(375503)
    cloth:SetTexCoord(0.095, 0.13, 0.08, 0.54)
    cloth:SetDesaturated(true)
    cloth:SetAlpha(0.27)
    local seam = button:CreateTexture(nil, "ARTWORK")
    seam:SetColorTexture(1, 0.86, 0.59, 0.28)
    seam:SetPoint("TOPLEFT", 2, -2)
    seam:SetPoint("TOPRIGHT", -2, -2)
    seam:SetHeight(1)
    local shadow = button:CreateTexture(nil, "BACKGROUND")
    shadow:SetColorTexture(0, 0, 0, 0.55)
    shadow:SetPoint("TOPLEFT", 2, -2)
    shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(23, 23)
    button.icon:SetPoint("RIGHT", -7, 0)
    button.label = addon.UIFactory.CreateLabel(button, addon.Theme.Fonts.body, "")
    button.label:SetPoint("LEFT", 10, 0)
    button.label:SetPoint("RIGHT", button.icon, "LEFT", -8, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetWordWrap(false)
    button.label:SetTextColor(1, 0.91, 0.72, 1)
    button.label:SetShadowColor(0, 0, 0, 1)
    button.label:SetShadowOffset(1, -1)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:EnableMouseWheel(true)
    button:SetScript("OnMouseWheel", function(_, delta)
        if isTransitioning(panel) then return end
        panel.bookmarkOffset = math.max(1, (panel.bookmarkOffset or 1) - delta)
        controls.RenderBookmarks(panel, true)
    end)
    button:SetScript("OnEnter", function(self)
        updateBookmark(self, true, panel.fancyPresentation)
        if self.tabID then panel.bookActions.hoverTab(self) end
        tooltip(self, self.isNew and addon.L("NEW_TAB") or self.label:GetText(),
            self.isNew and nil or addon.L("BOOK_BOOKMARK_HINT"))
    end)
    button:SetScript("OnLeave", function(self)
        panel.bookActions.leaveTab(self)
        updateBookmark(self, self.tabID ~= nil and self.tabID == panel.activeTabID, panel.fancyPresentation)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(self, mouseButton)
        if isTransitioning(panel) then return end
        if self.isNew then
            if mouseButton == "LeftButton" then panel.bookActions.newTab() end
        else
            panel.bookActions.tab(self, mouseButton)
        end
    end)
    button:SetScript("OnDragStart", function(self)
        if isTransitioning(panel) then return end
        if self.tabID then panel.bookActions.dragTab(self) end
    end)
    button:SetScript("OnDragStop", function() panel.bookActions.dropTab() end)
    return button
end

function controls.PlanBookmarks(order, activeID, height, offset, scrolling)
    local count = #order
    local capacity = math.max(1, math.floor((height - 40) / 37))
    offset = math.max(1, math.min(offset or 1, math.max(1, count - capacity + 1)))
    local activeIndex
    for i, id in ipairs(order) do if id == activeID then activeIndex = i break end end
    if activeIndex and not scrolling then
        if activeIndex < offset then offset = activeIndex end
        if activeIndex >= offset + capacity then offset = activeIndex - capacity + 1 end
    end
    local indices = {}
    for i = offset, math.min(count, offset + capacity - 1) do indices[#indices + 1] = i end
    if scrolling and activeIndex and (activeIndex < offset or activeIndex >= offset + capacity) then
        indices[#indices] = activeIndex
        table.sort(indices)
    end
    return indices, offset
end

local function bookmarkGeometry(panel)
    local surface = panel.fancyPresentation and panel.bookSurface or panel.content
    local right, scale = surface:GetRight(), surface:GetEffectiveScale()
    local screenRight = UIParent:GetRight()
    if not right or not screenRight or not scale or scale <= 0 then return end
    local room = screenRight * UIParent:GetEffectiveScale() / scale - right
    return room, surface:GetHeight()
end

local function positionBookmarks(panel, force)
    local ui = panel.fancyControls
    local room, height = bookmarkGeometry(panel)
    if not room then return end
    if not force and ui.edgeRoom == room and ui.edgeHeight == height then return end
    ui.edgeRoom, ui.edgeHeight = room, height
    local fullWidth = math.max(PEEK, math.min(BOOKMARK_WIDTH, room + 12))
    local inward = fullWidth < 130
    fullWidth = inward and BOOKMARK_WIDTH or fullWidth
    ui.bookmarkHost:ClearAllPoints()
    local surface = panel.fancyPresentation and panel.bookSurface or panel.content
    ui.bookmarkHost:SetPoint("TOPLEFT", surface, "TOPRIGHT", math.min(-12, room - PEEK),
        panel.fancyPresentation and -110 or 0)
    for _, button in ipairs(ui.bookmarks) do
        button.inward, button.fullWidth = inward, fullWidth
        button:SetWidth(fullWidth)
        addon.BookAnimation.Stop(button)
        updateBookmark(button, button.expanded, false)
    end
end

function controls.SyncBookmarks(panel)
    local ui = panel.fancyControls
    if not ui or not panel.bookControlsEnabled or not panel.spellbook then return end
    local _, height = bookmarkGeometry(panel)
    if height and height ~= ui.edgeHeight then
        controls.RenderBookmarks(panel, true)
    else
        positionBookmarks(panel, false)
    end
end

local function stopGeometryWatch(ui)
    ui.geometryToken = nil
    if ui.geometryTicker then ui.geometryTicker:Cancel(); ui.geometryTicker = nil end
end

local function watchGeometry(panel)
    local ui = panel.fancyControls
    if ui.geometryTicker or not panel:IsVisible() or not ui.bookmarkHost:IsShown() then return end
    controls.SyncBookmarks(panel)
     
     
    local token = {}
    ui.geometryToken = token
    ui.geometryTicker = C_Timer.NewTicker(0.10, function()
        if ui.geometryToken ~= token then return end
        if not panel.bookControlsEnabled or not ui.bookmarkHost:IsVisible() then
            stopGeometryWatch(ui)
            return
        end
        controls.SyncBookmarks(panel)
    end)
end

function controls.RenderBookmarks(panel, scrolling)
    local ui = panel.fancyControls
    if not ui or not panel.bookControlsEnabled then return end
    ui.bookmarkHost:SetFrameLevel(panel:GetFrameLevel() + (panel.fancyPresentation and BOOKMARK_SCENE_LEVEL or 8))
    local order = panel.spellbook.tabOrder
    local height = panel.fancyPresentation and (panel.bookSurface:GetHeight() - 138)
        or panel.content:GetHeight()
    local indices, offset = controls.PlanBookmarks(order, panel.activeTabID,
        math.max(90, height), panel.bookmarkOffset, scrolling)
    panel.bookmarkOffset = offset
    for visibleIndex = 1, #indices + 1 do
        local button = ui.bookmarks[visibleIndex]
        if not button then
            button = createBookmark(panel, ui.bookmarkHost, visibleIndex)
            ui.bookmarks[visibleIndex] = button
        end
        local orderIndex = indices[visibleIndex]
        local tabID = orderIndex and order[orderIndex]
        local tab = tabID and panel.spellbook.tabs[tabID]
        button.tabID, button.isNew = tabID, not tabID
        button.sleeve:SetFrameLevel(ui.bookmarkHost:GetFrameLevel() + #indices + 2 - visibleIndex)
        local hash = 0
        for i = 1, #(tabID or "") do hash = (hash * 31 + tabID:byte(i)) % 65521 end
        local color = tab and colors[hash % #colors + 1] or { 0.045, 0.04, 0.035 }
        local depth = orderIndex and (1 - math.min(0.22, (orderIndex - 1) * 0.009)) or 1
        button:SetBackdropColor(color[1] * depth, color[2] * depth, color[3] * depth, 1)
        button.label:SetText(tab and tab.name or addon.L("NEW_TAB"))
        addon.UIFactory.SetIconTexture(button.icon, tab and tab.icon, addon.Constants.DEFAULT_TAB_ICON)
        button.icon:SetShown(tab ~= nil)
        button.sleeve:SetShown(tab ~= nil or not panel.readOnly)
        button:Show()
        updateBookmark(button, (tabID ~= nil and tabID == panel.activeTabID) or button:IsMouseOver(), false)
    end
    for i = #indices + 2, #ui.bookmarks do ui.bookmarks[i].sleeve:Hide() end
    positionBookmarks(panel, true)
end

function controls.UpdateTitleHitbox(panel)
    local ui, label = panel.fancyControls, panel.title
    if not ui or not label then return end
    local width = label.GetStringWidth and label:GetStringWidth() or 0
    local height = label.GetStringHeight and label:GetStringHeight() or 0
    ui.title:ClearAllPoints()
    ui.title:SetPoint("LEFT", label, "LEFT", -2, 0)
    ui.title:SetSize(math.max(1, math.min(width, label:GetWidth()) + 4), math.max(1, height + 4))
end

function controls.Create(panel, actions)
    panel.bookActions = actions
    local ui = { bookmarks = {} }
    panel.fancyControls = ui
    ui.bookmarkHost = CreateFrame("Frame", nil, panel)
    ui.bookmarkHost:SetPoint("TOPLEFT", panel.bookSurface, "TOPRIGHT", -12, -110)
    ui.bookmarkHost:SetSize(BOOKMARK_WIDTH, 1)
    ui.bookmarkHost:SetFrameLevel(panel:GetFrameLevel() + (panel.fancyPresentation and BOOKMARK_SCENE_LEVEL or 8))
    ui.bookmarkHost:SetScript("OnShow", function() watchGeometry(panel) end)
    ui.bookmarkHost:SetScript("OnHide", function() stopGeometryWatch(ui) end)
    ui.title = CreateFrame("Button", nil, panel.header)
    controls.UpdateTitleHitbox(panel)
    ui.title:SetScript("OnClick", actions.export)
    ui.title:SetScript("OnEnter", function(self)
        tooltip(self, panel.title:GetText(), not panel.readOnly and addon.L("BOOK_TITLE_HINT") or nil)
    end)
    ui.title:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ui.ribbon = CreateFrame("Button", nil, panel)
    ui.ribbon:SetFrameLevel(panel:GetFrameLevel() + 6)
    ui.ribbon:SetScript("OnClick", actions.favorite)
    ui.ribbon:SetScript("OnEnter", function(self)
        tooltip(self, addon.L("FAVORITES_ONLY"), addon.L("BOOK_RIBBON_HINT"))
    end)
    ui.ribbon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.ribbon.tint = ui.ribbon:CreateTexture(nil, "OVERLAY")
    ui.ribbon.tint:SetAllPoints()
    ui.ribbon.tint:SetTexture(375503)
    ui.ribbon.tint:SetTexCoord(0.075, 0.105, 0.04, 0.64)
    ui.ribbon.tint:SetBlendMode("ADD")
    ui.ribbon.tint:SetVertexColor(1, 0.57, 0.16, 0.55)

    ui.placeholder = CreateFrame("Button", nil, panel.content)
    ui.placeholder:SetClipsChildren(true)
    ui.placeholder:SetScript("OnClick", actions.newSpell)
    ui.placeholder:SetScript("OnEnter", function(self)
        if panel.draggedSpellID then panel.dragTargetSlot = self.slot end
        local color = panel.fancyPresentation and { 0.8, 0.55, 0.18, 1 }
            or panel.activeTabThemeSpec.accent
        for _, rune in ipairs(self.glyphs) do rune:SetVertexColor(unpackValues(color)) end
        tooltip(self, addon.L("NEW_ABILITY"), addon.L("BOOK_INSCRIBE_HINT"))
    end)
    ui.placeholder:SetScript("OnLeave", function(self)
        if panel.dragTargetSlot == self.slot then panel.dragTargetSlot = nil end
        local color = panel.fancyPresentation and { 0.10, 0.35, 0.32, 0.8 }
            or panel.activeTabThemeSpec.text
        for _, rune in ipairs(self.glyphs) do rune:SetVertexColor(unpackValues(color)) end
        GameTooltip:Hide()
    end)
    ui.placeholder.pulses = {}
    ui.placeholder.glyphs = {}
    for i = 1, 7 do
        local rune = ui.placeholder:CreateTexture(nil, "ARTWORK")
        rune:SetTexture("Interface\\Spellbook\\UI-Glyph-Rune-" .. ((i * 3) % 10 + 1))
        rune:SetSize(i == 1 and 34 or 17, i == 1 and 34 or 19)
        rune:SetPoint("LEFT", i == 1 and 4 or 51 + (i - 2) * 20, 0)
        rune:SetVertexColor(0.10, 0.35, 0.32, 0.8)
        ui.placeholder.glyphs[i] = rune
        ui.placeholder.pulses[i] = pulse(rune, (i - 1) * 0.18)
    end
    ui.placeholder.label = addon.UIFactory.CreateLabel(ui.placeholder, addon.Theme.Fonts.body, addon.L("NEW_ABILITY"))
    ui.placeholder.label:SetPoint("LEFT", ui.placeholder.glyphs[1], "RIGHT", 8, 0)
    ui.placeholder.label:SetPoint("RIGHT", ui.placeholder, "RIGHT", -8, 0)
    ui.placeholder.label:SetJustifyH("LEFT")
    ui.placeholder:SetScript("OnShow", function(self) setPulses(self, panel.fancyPresentation) end)
    ui.placeholder:SetScript("OnHide", function(self) setPulses(self, false) end)
    ui.placeholder:Hide()
    controls.SetVisible(panel, false)
    return ui
end

function controls.SetVisible(panel, visible)
    local ui = panel.fancyControls
    if not ui then return end
    ui.bookmarkHost:SetShown(visible and not panel.detailSpellID)
    if visible and not panel.detailSpellID then watchGeometry(panel) else stopGeometryWatch(ui) end
    ui.title:SetShown(visible)
    ui.ribbon:SetShown(visible and panel.fancyPresentation and not panel.readOnly)
    if not visible or panel.detailSpellID then ui.placeholder:Hide() end
    if visible then
        controls.UpdateTitleHitbox(panel)
    end
    if visible and panel.fancyPresentation then
        local ribbon = panel.bookSurface._fancyRibbonHost
        ui.ribbon:ClearAllPoints()
        if ribbon then
            ui.ribbon:SetAllPoints(ribbon)
        else
            ui.ribbon:SetPoint("TOPLEFT", panel.bookSurface, "TOPLEFT", 0, -12)
            ui.ribbon:SetSize(18, math.min(280, panel.bookSurface:GetHeight() * 0.62))
        end
        ui.ribbon.tint:SetShown(panel.favoritesOnly == true)
    end
end

function controls.Placeholder(panel, slot)
    local ui = panel.fancyControls
    if not ui then return end
    local visible = panel.bookControlsEnabled and slot ~= nil and not panel.detailSpellID
    ui.placeholder.slot = slot
    ui.placeholder:SetShown(visible)
    if visible then
        ui.placeholder:ClearAllPoints()
        ui.placeholder:SetAllPoints(slot)
        ui.placeholder.label:SetShown(not panel.fancyPresentation)
        addon.UIFactory.SetFontColor(ui.placeholder.label, nil, panel.activeTabThemeSpec.text)
        local color = panel.fancyPresentation and { 0.10, 0.35, 0.32, 0.8 }
            or panel.activeTabThemeSpec.text
        for i, rune in ipairs(ui.placeholder.glyphs) do
            rune:SetShown(panel.fancyPresentation or i == 1)
            rune:SetVertexColor(unpackValues(color))
        end
        local plan = slot.bookLayout
        if panel.fancyPresentation and plan then
            for i, rune in ipairs(ui.placeholder.glyphs) do
                local size = i == 1 and plan.iconSize or plan.titleSize
                rune:SetSize(size, size)
                rune:ClearAllPoints()
                rune:SetPoint("TOPLEFT", ui.placeholder, "TOPLEFT",
                    i == 1 and 2 or plan.iconSize + 12 + (i - 2) * (plan.titleSize + 3), -3)
            end
        elseif not panel.fancyPresentation then
            local rune = ui.placeholder.glyphs[1]
            rune:ClearAllPoints()
            rune:SetSize(28, 28)
            rune:SetPoint("LEFT", ui.placeholder, "LEFT", 8, 0)
        end
        setPulses(ui.placeholder, panel.fancyPresentation)
    end
end

function controls.StopOutgoing(panel)
    local ghost = panel.bookClosingGhost
    if not ghost then return end
    ghost.bookSceneOwnerValid = nil
    if addon.BookScene then addon.BookScene.Stop(ghost) end
    ghost:Hide()
end

function controls.Stop(panel, preserveOutgoing)
    if not preserveOutgoing then controls.StopOutgoing(panel) end
    local ui = panel.fancyControls
    if not ui then return end
    stopGeometryWatch(ui)
    setPulses(ui.placeholder, false)
    addon.BookAnimation.Stop(ui.placeholder)
    addon.BookAnimation.Stop(ui.bookmarkHost)
    for _, button in ipairs(ui.bookmarks) do
        button:SetScript("OnUpdate", nil)
        addon.BookAnimation.Stop(button)
    end
end

function controls.CancelInscription(slot)
    local writing = slot.bookInscription
    if not writing then return end
    if writing.cancel then writing.cancel(); return end
    slot.bookInscription = nil
    if writing.timer then writing.timer:Cancel() end
    if slot.spellID == writing.id then slot.name:SetText(writing.text) end
end

function controls.Inscribe(slot)
    controls.CancelInscription(slot)
    if reducedMotion() then return end
    if addon.BookMagic and addon.BookMagic.Inscribe(slot) then return end
    local text = slot.name:GetText() or ""
    local writing = { id = slot.spellID, text = text }
    slot.bookInscription = writing
    local ends, position = {}, 1
    while position <= #text do
        local byte = text:byte(position)
        position = position + (byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1)
        ends[#ends + 1] = position - 1
    end
    if #ends == 0 or not C_Timer.NewTicker then slot.bookInscription = nil return end
    slot.name:SetText("")
    local step, ticks = 0, math.min(32, #ends)
    writing.timer = C_Timer.NewTicker(1.1 / ticks, function()
        if slot.bookInscription ~= writing then return end
        if reducedMotion() or slot.spellID ~= writing.id or not slot:IsVisible() then
            controls.CancelInscription(slot)
            return
        end
        step = step + 1
        local count = math.min(#ends, math.ceil(#ends * step / ticks))
        slot.name:SetText(text:sub(1, ends[count]))
        if step >= ticks then controls.CancelInscription(slot) end
    end, ticks)
end

 
 
function controls.CloseAfterHide(panel)
    controls.StopOutgoing(panel)
    if not panel.fancyPresentation or panel.bookCloseCompleted or reducedMotion() then return end
    for _, slot in ipairs(panel.spellSlots) do controls.CancelInscription(slot) end
    local surface = panel.bookSurface
    local left, bottom = surface:GetLeft(), surface:GetBottom()
    if not left or not bottom or surface:GetWidth() < 1 then return end
    local ghost = panel.bookClosingGhost
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ghost:EnableMouse(false)
        ghost:EnableMouseWheel(false)
        ghost.bookSceneInputFree = true
        ghost:SetFrameStrata("DIALOG")
        ghost.labels, ghost.icons = {}, {}
        ghost.bookAnimationManaged = true
        panel.bookClosingGhost = ghost
    end
    local book, profileKey = panel.spellbook, panel.spellbook and panel.spellbook.profileKey
    ghost.bookSceneOwnerValid = function()
        return not panel:IsVisible() and panel.fancyPresentation and panel.spellbook == book
            and book and book.profileKey == profileKey
            and addon.Database.GetActiveSpellbook() == book
            and addon.SpellCreationSettings.IsFancyMode()
            and not reducedMotion()
    end
    addon.BookAnimation.Stop(ghost)
    ghost:SetScale(panel:GetEffectiveScale() / UIParent:GetEffectiveScale())
    ghost:ClearAllPoints()
    ghost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    ghost:SetSize(surface:GetWidth(), surface:GetHeight())
    ghost:Show()
    addon.SpellCreationThemes.ApplyBook(ghost, "fancy")
    local labels, icons = {}, {}
    labels[#labels + 1] = panel.title
    if panel.detailSpellID then
        icons[#icons + 1] = panel.detailsView.icon
        for _, key in ipairs({ "name", "descriptionTitle", "description", "tagsTitle", "tags" }) do
            if panel.detailsView[key] then labels[#labels + 1] = panel.detailsView[key] end
        end
    else
        for _, slot in ipairs(panel.spellSlots) do
            if slot.spellID and slot:IsShown() then
                labels[#labels + 1], icons[#icons + 1] = slot.name, slot.icon
                if slot.excerpt and slot.excerpt:IsShown() then labels[#labels + 1] = slot.excerpt end
            end
        end
    end
    local function locate(copy, source)
        local x, y = source:GetLeft(), source:GetTop()
        if not x or not y then copy:Hide() return false end
        copy:ClearAllPoints()
        copy:SetPoint("TOPLEFT", ghost, "BOTTOMLEFT", x - left, y - bottom)
        copy:SetSize(source:GetWidth(), source:GetHeight())
        copy:Show()
        return true
    end
    for i, source in ipairs(labels) do
        local copy = ghost.labels[i] or ghost:CreateFontString(nil, "OVERLAY")
        ghost.labels[i] = copy
        if locate(copy, source) then
            copy:SetFont(source:GetFont())
            copy:SetText(source:GetText())
            copy:SetTextColor(source:GetTextColor())
            copy:SetAlpha(source:GetAlpha())
            copy:SetJustifyH(source:GetJustifyH())
            copy:SetJustifyV(source:GetJustifyV())
            copy:SetWordWrap(true)
            copy:SetMaxLines(source.GetMaxLines and source:GetMaxLines() or 0)
            if source.GetShadowColor then copy:SetShadowColor(source:GetShadowColor()) end
            if source.GetShadowOffset then copy:SetShadowOffset(source:GetShadowOffset()) end
        end
    end
    for i = #labels + 1, #ghost.labels do ghost.labels[i]:Hide() end
    for i, source in ipairs(icons) do
        local copy = ghost.icons[i] or ghost:CreateTexture(nil, "OVERLAY")
        ghost.icons[i] = copy
        if locate(copy, source) then
            copy:SetTexture(source:GetTexture())
            copy:SetTexCoord(source:GetTexCoord())
            copy:SetBlendMode(source:GetBlendMode())
            copy:SetDesaturation(source:GetDesaturation())
            copy:SetVertexColor(source:GetVertexColor())
            copy:SetAlpha(source:GetAlpha())
            if addon.UIFactory.CopySpellIconEffectFrame then
                addon.UIFactory.CopySpellIconEffectFrame(source, copy)
            end
        else
            addon.UIFactory.ClearSpellIconEffectFrame(copy)
        end
    end
    for i = #icons + 1, #ghost.icons do
        ghost.icons[i]:Hide()
        addon.UIFactory.ClearSpellIconEffectFrame(ghost.icons[i])
    end
    if addon.BookScene then
        addon.BookScene.Play(ghost, "close", function()
            ghost.bookSceneOwnerValid = nil
            ghost:Hide()
        end)
    else
        ghost:Hide()
    end
end
