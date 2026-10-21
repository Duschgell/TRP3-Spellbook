local _, addon = ...

local magic = {}
addon.BookMagic = magic
local unpackValues = unpack or table.unpack
local BURN_DURATION = 3.8
local FIRE = "Interface\\GLUES\\Models\\UI_OrcClan\\T_VFX_Fire_Anim_Stylized_Desat_02"
local SMOKE = "Interface\\GLUES\\Models\\UI_OrcClan\\Smoke_Puffy_Mask"
local SPARK = "Interface\\Cooldown\\star4"

local function reducedMotion()
    local settings = addon.SpellCreationSettings
    return settings and settings.ShouldReduceBookMotion and settings.ShouldReduceBookMotion() or false
end

local function clamp(value, low, high)
    return math.max(low or 0, math.min(high or 1, value))
end

local function clippedCanvas(clip)
    local canvas = CreateFrame("Frame", nil, clip)
    canvas:EnableMouse(false)
    canvas:EnableMouseWheel(false)
    return canvas
end

local function copyText(copy, source)
    local path, size, flags = source:GetFont()
    if not path then return false end
    local ratio = source:GetEffectiveScale() / copy:GetEffectiveScale()
    copy:SetFont(path, size * ratio, flags or "")
    copy:SetText(source:GetText() or "")
    copy:SetJustifyH(source:GetJustifyH())
    copy:SetJustifyV(source:GetJustifyV())
    copy:SetWordWrap(not source.CanWordWrap or source:CanWordWrap())
    if source.GetSpacing then copy:SetSpacing(source:GetSpacing() * ratio) end
    if source.CanNonSpaceWrap then copy:SetNonSpaceWrap(source:CanNonSpaceWrap()) end
    if source.GetIndentedWordWrap then copy:SetIndentedWordWrap(source:GetIndentedWordWrap()) end
    copy:SetMaxLines(source:GetMaxLines())
    copy:SetTextColor(source:GetTextColor())
    copy:SetShadowColor(0, 0, 0, 0)
    copy:SetShadowOffset(0, 0)
    copy:SetAlpha(source:GetAlpha())
    return true
end

local function stopGlow(state)
    state.glowGeneration = (state.glowGeneration or 0) + 1
    if state.panel and state.panel.bookMagicActive == state then state.panel.bookMagicActive = nil end
    state.host:SetScript("OnUpdate", nil)
    state.host:Hide()
end

local function stopText(state)
    if not state then return end
    state.bindingGeneration = (state.bindingGeneration or 0) + 1
    if state.timer then state.timer:Cancel(); state.timer = nil end
    if state.startTimer then state.startTimer:Cancel(); state.startTimer = nil end
    state.active = false
    stopGlow(state)
end

function magic.StopText(owner)
    if not owner then return end
    stopText(owner.bookMagicText)
    stopText(owner.bookMagicBody)
end

local function suspended(state)
    local panel, owner = state.panel, state.owner
    return owner.bookInscription or (owner.readingReveal and #owner.readingReveal.entries > 0)
        or reducedMotion()
        or (panel and (not panel.fancyPresentation or (panel.bookBurn and panel.bookBurn.playing)
            or addon.BookScene.IsPlaying(panel)))
end

local function validText(state)
    return state.active and state.owner:IsVisible() and state.label:IsVisible()
        and state.label:GetText() == state.text
end

 
 
local function glyphColumns(label, measure)
    local text = label:GetText() or ""
    if text == "" or text:find("|", 1, true) then return {} end
    local path, size, flags = label:GetFont()
    if not path then return {} end
    measure:SetFont(path, size, flags or "")
    measure:SetWordWrap(false)
    measure:SetWidth(0)
    local columns, pos, previous, lastBreak = {}, 1, 0, nil
    while pos <= #text and #columns < 80 do
        local byte = text:byte(pos)
        local last = pos + (byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1) - 1
        measure:SetText(text:sub(1, last))
        local width = measure:GetStringWidth()
        if width > label:GetWidth() then
            if lastBreak then
                for i = #columns, lastBreak + 1, -1 do columns[i] = nil end
            end
            break
        end
        if text:sub(pos, last):match("%s") then
            lastBreak = #columns
        elseif width > previous then
            columns[#columns + 1] = { x = previous, width = width - previous }
        end
        previous, pos = width, last + 1
    end
    return columns
end

local function glow(state)
    local label = state.label
    if not validText(state) then
        stopText(state)
        return
    end
    if suspended(state) then return end
    stopGlow(state)
    local columns = glyphColumns(label, state.measure)
    if #columns == 0 then return end
    local index = math.random(#columns)
    if #columns > 1 and index == state.lastIndex then index = index % #columns + 1 end
    state.lastIndex = index
    local column = columns[index]
    state.host:ClearAllPoints()
    state.host:SetPoint("TOPLEFT", label, "TOPLEFT", column.x, 1)
    local _, fontHeight = label:GetFont()
    local lineHeight = label.GetLineHeight and label:GetLineHeight() or fontHeight * 1.2
    state.host:SetSize(column.width, math.min(label:GetHeight(), lineHeight) + 2)
    if not copyText(state.ink, label) then return end
    state.canvas:ClearAllPoints()
    state.canvas:SetAllPoints(label)
    state.ink:ClearAllPoints()
    state.ink:SetAllPoints(label)
     
    local r, g, b = label:GetTextColor()
    state.ink:SetTextColor(r + (1 - r) * 0.24, g + (1 - g) * 0.24, b + (1 - b) * 0.24, 1)
    state.ink:SetShadowColor(0, 0, 0, 0)
    state.host:SetAlpha(0)
    state.host:Show()
    local elapsed = 0
    local token = state.glowGeneration
    state.host:SetScript("OnUpdate", function(_, delta)
        if state.glowGeneration ~= token then return end
        if not validText(state) or suspended(state) then stopGlow(state); return end
        elapsed = elapsed + delta
        state.host:SetAlpha(math.sin(clamp(elapsed / 1.7) * math.pi) ^ 2 * 0.36)
        if elapsed >= 1.7 then stopGlow(state) end
    end)
end

local function textMetrics(label)
    local _, fontHeight = label:GetFont()
    if not fontHeight then return end
    local naturalHeight = label:GetStringHeight()
    local height = math.min(label:GetHeight(), naturalHeight)
    local lineHeight = label.GetLineHeight and label:GetLineHeight() or fontHeight * 1.2
    local spacing = label.GetSpacing and label:GetSpacing() or 0
    local lines = label.GetNumLines and label:GetNumLines()
    lines = lines and lines > 0 and lines or math.max(1, math.ceil(naturalHeight / math.max(1, lineHeight + spacing)))
    lineHeight = naturalHeight / lines
    local visibleLines = math.max(1, math.ceil(height / math.max(1, lineHeight)))
    return height, lineHeight, visibleLines, fontHeight
end

local function textBand(host, bands, index, label)
    local band = bands[index]
    if not band then
        local clip = CreateFrame("Frame", nil, host)
        clip:SetClipsChildren(true)
        clip:EnableMouse(false)
        local canvas = clippedCanvas(clip)
        band = { clip = clip, canvas = canvas, ink = canvas:CreateFontString(nil, "OVERLAY") }
        bands[index] = band
    end
    if not copyText(band.ink, label) then return end
    band.canvas:ClearAllPoints()
    band.canvas:SetAllPoints(label)
    band.ink:ClearAllPoints()
    band.ink:SetAllPoints(label)
    if band.ink.SetFixedColor then band.ink:SetFixedColor(true) end
    band.clip:SetAlpha(0)
    band.clip:Show()
    return band
end

local function flow(state)
    if not validText(state) then stopText(state); return false end
    if suspended(state) then return false end
    local panel = state.panel
    local active = panel and panel.bookMagicActive
    if active then
        if validText(active) and active.host:IsShown() then return false end
        stopGlow(active)
    end
    stopGlow(state)
    local label, host = state.label, state.host
    local width = math.min(label:GetWidth(), label:GetStringWidth())
    local fullHeight, lineHeight, _, fontHeight = textMetrics(label)
    if not fullHeight or width <= 0 or fullHeight <= 0 then return false end
    local height, top = fullHeight, 0
    local viewport = state.owner.scrollFrame
    if viewport and label:GetTop() and viewport:GetTop() and viewport:GetBottom() then
        local ratio = viewport:GetEffectiveScale() / label:GetEffectiveScale()
        top = clamp(label:GetTop() - viewport:GetTop() * ratio, 0, height)
        height = clamp(label:GetTop() - viewport:GetBottom() * ratio, 0, height) - top
    end
    if height <= 0 then return false end
    local scale = label:GetEffectiveScale() / host:GetEffectiveScale()
    width, height, top = width * scale, height * scale, top * scale
    lineHeight, fontHeight = lineHeight * scale, fontHeight * scale
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", label, "TOPLEFT", 0, -top)
    host:SetSize(width, height)
    host:SetAlpha(1)
    local visibleRows = math.max(1, math.floor(height / lineHeight))
    local rows = math.min(2, visibleRows)
    local first = math.random(math.max(1, visibleRows - rows + 1)) - 1
    if visibleRows > rows and first == state.lastRow then first = (first + 1) % (visibleRows - rows + 1) end
    state.lastRow = first
    local y = (math.floor(top / lineHeight) + first) * lineHeight - top
    local stroke = math.max(2, fontHeight * 0.55)
    local begin = math.random() * math.max(0, width * 0.35 - stroke * 4)
    local travel = math.min(width - stroke * 4, width * 0.50)
    for i = 1, rows * 4 do
        local band = textBand(host, state.bands, i, label)
        if not band then stopGlow(state); return false end
        band.clip:SetSize(stroke, lineHeight)
        band.ink:SetShadowColor(0, 0, 0, 0)
    end
    for i = rows * 4 + 1, #state.bands do state.bands[i].clip:Hide() end
    host:Show()
    if panel then panel.bookMagicActive = state end
    local elapsed, lastUpdate, duration = 0, 0, 4.8
    local token = state.glowGeneration
    host:SetScript("OnUpdate", function(_, delta)
        if state.glowGeneration ~= token then return end
        if not validText(state) or suspended(state) then stopGlow(state); return end
        elapsed = elapsed + delta
        if elapsed >= duration then stopGlow(state); return end
        if elapsed - lastUpdate < 1 / 30 then return end
        lastUpdate = elapsed
        for i = 1, rows * 4 do
            local row, part = math.floor((i - 1) / 4), (i - 1) % 4
            local p = clamp((elapsed / duration - row * 0.22 - part * 0.035) / 0.65)
            local direction = state.profile.writing == "reverse" and 1 - p or p
            local x = begin + direction * math.max(0, travel) + part * stroke
            local band = state.bands[i]
            band.clip:ClearAllPoints()
            band.clip:SetPoint("TOPLEFT", host, "TOPLEFT", x, -(y + row * lineHeight))
            local r, g, b, alpha = addon.BookMagicEffects.Sample(state.profile, p, i)
            band.ink:SetTextColor(r, g, b, 1)
            band.clip:SetAlpha(alpha)
        end
    end)
    return true
end

local function bindText(owner, label, spell, panel, profile, id, body)
    local key = body and "bookMagicBody" or "bookMagicText"
    local state = owner[key]
    local text = label and label:GetText() or ""
    if text == "" or not label:IsShown() then stopText(state); return end
    if not state then
        local host = CreateFrame("Frame", nil, label:GetParent())
        host:SetClipsChildren(true)
        host:EnableMouse(false)
        host:Hide()
        state = { host = host, owner = owner, bands = {} }
        if not body then
            state.canvas = clippedCanvas(host)
            state.ink = state.canvas:CreateFontString(nil, "OVERLAY")
            state.measure = host:CreateFontString(nil, "OVERLAY")
            state.measure:Hide()
        end
        owner[key] = state
        owner:HookScript("OnHide", function() stopText(state) end)
        owner:HookScript("OnSizeChanged", function() stopGlow(state) end)
    end
    if state.active and state.timer and state.text == text and state.id == spell.id
        and state.theme == id and state.label == label then return end
    stopText(state)
    state.label, state.text, state.id, state.theme = label, text, spell.id, id
    state.profile, state.panel, state.active = profile, panel, true
    if not owner:IsVisible() or not C_Timer or not C_Timer.NewTicker then return end
    local token = state.bindingGeneration
    state.timer = C_Timer.NewTicker((body and 10 or 6) + math.random() * 4,
        function()
            if state.bindingGeneration ~= token then return end
            if reducedMotion() then stopText(state); return end
            if body then flow(state) else glow(state) end
        end)
    if body then
         
         
        local delay = 1.3 + math.max(0, (owner.slotIndex or 1) - 1) * 0.71 + math.random() * 0.4
        local tries = 0
        state.startTimer = C_Timer.NewTicker(delay, function()
            if state.bindingGeneration ~= token then return end
            if reducedMotion() then stopText(state); return end
            if not validText(state) then stopText(state); return end
            tries = tries + 1
            if not flow(state) and tries < 10 then return end
            if state.startTimer then state.startTimer:Cancel(); state.startTimer = nil end
        end)
    end
end

function magic.SetText(owner, label, spell, enabled, panel, description)
    local tags = spell and spell.tags
    local presentation = addon.SpellPresentation
    if not enabled or reducedMotion() or type(tags) ~= "table" or not presentation.GetKind
        or presentation.GetKind(tags) ~= addon.Constants.SPELL_KIND_MAGIC then
        magic.StopText(owner)
        return
    end
    local profile, id = addon.BookMagicEffects.Resolve(tags[addon.Constants.MAGIC_TAG_TYPE] or tags.Magieart)
    if not profile then magic.StopText(owner); return end
    bindText(owner, label, spell, panel, profile, id, false)
    bindText(owner, description, spell, panel, profile, id, true)
end

local function finishBurn(state)
    if not state.playing then return end
    state.generation = (state.generation or 0) + 1
    state.playing = false
    state.host:SetScript("OnUpdate", nil)
    state.host:Hide()
    for _, entry in ipairs(state.originals) do entry.region:SetAlpha(entry.alpha) end
    state.originals = {}
    state.book = nil
    local callback = state.callback
    state.callback = nil
    if callback then callback() end
end

function magic.FinishBurn(panel)
    if panel.bookBurn then finishBurn(panel.bookBurn) end
end

local function rect(source, host)
    local ratio = source:GetEffectiveScale() / host:GetEffectiveScale()
    local x, y, left, top = source:GetLeft(), source:GetTop(), host:GetLeft(), host:GetTop()
    if not x or not y or not left or not top then return end
    return x * ratio - left, top - y * ratio, source:GetWidth() * ratio, source:GetHeight() * ratio
end

local function makeParticle(host, asset, blend)
    local texture = host:CreateTexture(nil, "OVERLAY")
    local ok, result = pcall(texture.SetTexture, texture, asset)
    if not ok or result == false then
        texture:SetTexture(SPARK)
        texture.bookSingleFrame = true
    end
    texture:SetBlendMode(blend)
    texture:Hide()
    return texture
end

local function ensureBurn(panel)
    if panel.bookBurn then return panel.bookBurn end
    local host = CreateFrame("Frame", nil, panel)
    host:SetAllPoints(panel.bookSurface)
    host:SetFrameLevel(panel:GetFrameLevel() + 80)
    host:SetClipsChildren(true)
    host:EnableMouse(true)
    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", function() end)
    local state = { host = host, panel = panel, slices = {}, originals = {}, particles = {}, runes = {} }
    for i = 1, 24 do
        state.particles[i] = {
            fire = makeParticle(host, FIRE, "ADD"), smoke = makeParticle(host, SMOKE, "BLEND"),
            spark = makeParticle(host, SPARK, "ADD"),
        }
    end
    for i = 1, 7 do
        state.runes[i] = makeParticle(host, "Interface\\Spellbook\\UI-Glyph-Rune-" .. i, "ADD")
    end
    panel.bookBurn = state
    host:Hide()
    panel:HookScript("OnHide", function() finishBurn(state) end)
    panel:HookScript("OnSizeChanged", function() finishBurn(state) end)
    return state
end

local function captureBurn(state, source, isText, count)
    if not source or not source:IsShown() then return count end
    local x, y, width, height = rect(source, state.host)
    if not x or width <= 0 or height <= 0 then return count end
    local alpha = source:GetAlpha()
    state.originals[#state.originals + 1] = { region = source, alpha = alpha }
    for i = 1, 8 do
        count = count + 1
        local slice = state.slices[count]
        if not slice then
            local clip = CreateFrame("Frame", nil, state.host)
            clip:SetClipsChildren(true)
            clip:EnableMouse(false)
            local canvas = clippedCanvas(clip)
            canvas:SetAllPoints(state.host)
            slice = { clip = clip, canvas = canvas, text = canvas:CreateFontString(nil, "OVERLAY"),
                icon = canvas:CreateTexture(nil, "ARTWORK") }
            state.slices[count] = slice
        end
        slice.text:Hide(); slice.icon:Hide()
        local copy = isText and slice.text or slice.icon
        if isText then
            copyText(copy, source)
            if copy.SetFixedColor then copy:SetFixedColor(true) end
        else
            copy:SetTexture(source:GetTexture())
            copy:SetTexCoord(source:GetTexCoord())
            copy:SetDesaturation(source:GetDesaturation())
            copy:SetVertexColor(source:GetVertexColor())
        end
        copy:ClearAllPoints()
        copy:SetPoint("TOPLEFT", state.host, "TOPLEFT", x, -y)
        copy:SetSize(width, height)
        copy:Show()
        local r, g, b = 1, 1, 1
        if isText then r, g, b = source:GetTextColor() else r, g, b = source:GetVertexColor() end
        slice.copy, slice.isText, slice.alpha = copy, isText, alpha
        slice.column = i
        slice.color = { r, g, b }
        slice.delay = (i - 1) * 0.095 + math.random() * 0.12
        slice.x, slice.y = x + (i - 0.5) * width / 8, y + height * (0.25 + ((i - 1) % 3) * 0.25)
        slice.clip:ClearAllPoints()
        slice.clip:SetPoint("TOPLEFT", state.host, "TOPLEFT", x + (i - 1) * width / 8, -y)
        slice.clip:SetSize(width / 8, height)
        slice.clip:Show()
    end
    source:SetAlpha(0)
    return count
end

local function tile(texture, index)
     
    if texture.bookSingleFrame then texture:SetTexCoord(0, 1, 0, 1); return end
    local x, y = index % 2, math.floor(index / 2) % 2
    texture:SetTexCoord(x / 2 + 0.002, (x + 1) / 2 - 0.002, y / 2 + 0.002, (y + 1) / 2 - 0.002)
end

local function place(texture, host, x, y, width, height, alpha, r, g, b)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", host, "TOPLEFT", x, -y)
    texture:SetSize(width, height)
    texture:SetVertexColor(r, g, b, 1)
    texture:SetAlpha(clamp(alpha))
    texture:Show()
end

function magic.Burn(panel, view, callback)
    if reducedMotion() then
        if panel.bookBurn and panel.bookBurn.playing then magic.FinishBurn(panel) else callback() end
        return false
    end
    if not panel.fancyPresentation or not panel:IsVisible() then callback(); return false end
    local state = ensureBurn(panel)
    if state.playing then return false end
    if addon.FancyBookControls then addon.FancyBookControls.CancelInscription(view) end
    magic.StopText(view)
    addon.SpellDetailsView.StopReadingReveal(view)
    state.host:Show()
    state.originals = {}
    local count = captureBurn(state, view.icon, false, 0)
     
     
    for _, key in ipairs({ "name", "excerpt", "magicSubtitle", "metadata",
        "descriptionTitle", "description", "tagsTitle", "tags" }) do
        count = captureBurn(state, view[key], true, count)
    end
    for i = count + 1, #state.slices do state.slices[i].clip:Hide() end
    if count == 0 then state.host:Hide(); callback(); return false end
    local x, y, size = rect(view.icon, state.host)
    local nameX, nameY = rect(view.name, state.host)
    for i, rune in ipairs(state.runes) do
        rune:Hide()
        rune.x, rune.y = i == 1 and x + size / 2 or nameX + (i - 2) * 26 + 10,
            i == 1 and y + size / 2 or nameY + 14
    end
    for i, particle in ipairs(state.particles) do
        local slice = state.slices[1 + math.floor((i - 1) * count / #state.particles)]
        particle.x, particle.y = slice.x, slice.y
        particle.delay = slice.delay + (i % 3) * 0.12
        particle.fire:Hide(); particle.smoke:Hide(); particle.spark:Hide()
    end
    state.playing, state.callback, state.book = true, callback, panel.spellbook
    state.generation = (state.generation or 0) + 1
    local token = state.generation
    local elapsed = 0
    state.host:SetScript("OnUpdate", function(_, delta)
        if state.generation ~= token then return end
        if reducedMotion() then finishBurn(state); return end
        if not panel.fancyPresentation or panel.spellbook ~= state.book or not view:IsVisible() then
            finishBurn(state); return
        end
        elapsed = elapsed + delta
        for i = 1, count do
            local slice = state.slices[i]
            local age = elapsed - slice.delay
            local heat = clamp(age / 0.45)
            local ash = clamp((age - 0.7) / 1.2)
            local c, copy = slice.color, slice.copy
            if slice.isText then
                copy:SetTextColor((c[1] + (1 - c[1]) * heat) * (1 - ash * 0.72),
                    (c[2] + (0.22 - c[2]) * heat) * (1 - ash * 0.65), c[3] * (1 - heat), 1)
                copy:SetShadowColor(1, 0.15, 0, clamp(age * 2) * clamp((3.3 - age) / 2))
                copy:SetShadowOffset(0.6, -0.6)
            else
                copy:SetVertexColor(1, 1 - heat * 0.7, 1 - heat * 0.96, 1)
            end
            local erosion = clamp((age - 0.35) / 0.65)
            local density = slice.alpha * (1 - erosion) + erosion * 0.38 * clamp((3.1 - age) / 2.5)
            copy:SetAlpha(density)
        end
        for i, particle in ipairs(state.particles) do
            local age = elapsed - particle.delay
            if age >= 0 then
                tile(particle.fire, math.floor(age * 12) + i)
                tile(particle.smoke, i)
                local flicker = 0.85 + 0.15 * math.sin(age * 24 + i)
                place(particle.fire, state.host, particle.x + math.sin(age * 8 + i) * 3,
                    particle.y - age * 13, 20 * flicker, 32 * flicker,
                    math.sin(clamp(age / 1.5) * math.pi) * 0.85, 1, 0.38, 0.06)
                place(particle.smoke, state.host, particle.x + math.sin(i) * age * 12,
                    particle.y - 14 - age * 28, 18 + age * 20, 16 + age * 25,
                    math.sin(clamp((age - 0.15) / 2.8) * math.pi) * 0.30, 0.16, 0.12, 0.10)
                place(particle.spark, state.host, particle.x + math.cos(i) * age * 16,
                    particle.y - age * 35, 3, 5, clamp(1 - age / 2) * 0.8, 1, 0.48, 0.08)
            end
        end
        for i, rune in ipairs(state.runes) do
            local alpha = clamp((elapsed - 1.8 - i * 0.08) / 0.7) * clamp((BURN_DURATION - elapsed) / 0.5)
            place(rune, state.host, rune.x, rune.y, i == 1 and size or 21,
                i == 1 and size or 21, alpha * 0.70, 0.12, 0.62, 0.48)
        end
        if elapsed >= BURN_DURATION then finishBurn(state) end
    end)
    return true
end

local function finishWriting(state)
    if not state.playing then return end
    state.generation = (state.generation or 0) + 1
    state.playing = false
    state.host:SetScript("OnUpdate", nil)
    state.host:Hide()
    for _, entry in ipairs(state.originals) do entry.region:SetAlpha(entry.alpha) end
    state.originals = {}
    if state.slot.bookInscription == state then state.slot.bookInscription = nil end
    state.book = nil
end

function magic.PauseInscription(slot)
    local state = slot.bookCreation
    if not state or not state.playing then return end
    local snapshot = { book = state.book, id = state.id, tabID = state.tabID, page = state.page,
        elapsed = state.elapsed or 0, signature = state.signature }
    finishWriting(state)
    return snapshot
end

function magic.ResumeInscription(slot, snapshot)
    local panel = slot.ownerPanel
    if not snapshot or not panel or not panel.fancyPresentation or panel.readOnly or panel.detailSpellID
        or panel.spellbook ~= snapshot.book or panel.activeTabID ~= snapshot.tabID
        or panel.currentPage ~= snapshot.page or slot.spellID ~= snapshot.id then return false end
    local spell = panel.spellbook.spells[snapshot.id]
    if not spell then return false end
    for _, key in ipairs({ "name", "description", "icon", "nameColor" }) do
        if spell[key] ~= snapshot.signature[key] then return false end
    end
    local tags = spell.tags or {}
    if (tags[addon.Constants.MAGIC_TAG_TYPE] or tags.Magieart) ~= snapshot.signature.magicType then return false end
    return magic.Inscribe(slot, snapshot.elapsed)
end

local function writingCanvas(clip)
    local canvas = CreateFrame("Frame", nil, clip)
    canvas:EnableMouse(false)
    return canvas, canvas:CreateFontString(nil, "OVERLAY")
end

local function captureWriting(state, source, regionIndex, count)
    if not source or not source:IsShown() or source:GetText() == "" then return count end
    local height, lineHeight, lines, fontHeight = textMetrics(source)
    local width = math.min(source:GetWidth(), source:GetStringWidth())
    if not height or height <= 0 or width <= 0 then return count end
    local scale = source:GetEffectiveScale() / state.host:GetEffectiveScale()
    height, width, fontHeight = height * scale, width * scale, fontHeight * scale
    lineHeight = lineHeight * scale
    if lines > 12 then lineHeight = height / 12 end
    lines = math.min(lines, 12)
    local rowDuration = clamp(width / math.max(1, fontHeight) * 0.075, 1.4, 2.4)
    local alpha = source:GetAlpha()
    state.originals[#state.originals + 1] = { region = source, alpha = alpha }
    for row = 1, lines do
        count = count + 1
        local entry = state.rows[count]
        if not entry then
            local clip = CreateFrame("Frame", nil, state.host)
            clip:SetClipsChildren(true)
            clip:EnableMouse(false)
            local front = CreateFrame("Frame", nil, clip)
            front:SetClipsChildren(true)
            front:EnableMouse(false)
            local tip = CreateFrame("Frame", nil, front)
            tip:SetClipsChildren(true)
            tip:EnableMouse(false)
            entry = { clip = clip, front = front, tip = tip }
             
            entry.canvas, entry.copy = writingCanvas(clip)
            entry.glowCanvas, entry.glow = writingCanvas(front)
            entry.tipCanvas, entry.highlight = writingCanvas(tip)
            state.rows[count] = entry
        end
        copyText(entry.copy, source)
        copyText(entry.glow, source)
        copyText(entry.highlight, source)
        entry.canvas:ClearAllPoints(); entry.canvas:SetAllPoints(source)
        entry.glowCanvas:ClearAllPoints(); entry.glowCanvas:SetAllPoints(source)
        entry.tipCanvas:ClearAllPoints(); entry.tipCanvas:SetAllPoints(source)
        entry.copy:ClearAllPoints(); entry.copy:SetAllPoints(source)
        entry.glow:ClearAllPoints(); entry.glow:SetAllPoints(source)
        entry.highlight:ClearAllPoints(); entry.highlight:SetAllPoints(source)
        if entry.glow.SetFixedColor then entry.glow:SetFixedColor(true) end
        if entry.highlight.SetFixedColor then entry.highlight:SetFixedColor(true) end
        entry.glow:SetShadowColor(0, 0, 0, 0)
        entry.source, entry.alpha, entry.width = source, alpha, width
        entry.y, entry.stroke = (row - 1) * lineHeight, fontHeight * 2.2
        entry.height = math.min(lineHeight, height - entry.y)
        entry.color, entry.isName = { source:GetTextColor() }, regionIndex == 1
        entry.delay = state.writeCursor
        entry.duration = rowDuration
        state.writeCursor = state.writeCursor + rowDuration + 0.14
        entry.clip:SetAlpha(0)
        entry.clip:Show()
        entry.front:Show()
        entry.tip:Show()
    end
    source:SetAlpha(0)
    return count
end

function magic.Inscribe(slot, resumeElapsed)
    if reducedMotion() then
        if slot.bookCreation then finishWriting(slot.bookCreation) end
        return false
    end
    local panel = slot.ownerPanel
    local spell = panel and panel.spellbook and panel.spellbook.spells[slot.spellID]
    local tags = spell and spell.tags
    if not panel or not panel.fancyPresentation or not slot:IsVisible() or type(tags) ~= "table"
        or addon.SpellPresentation.GetKind(tags) ~= addon.Constants.SPELL_KIND_MAGIC then return false end
    local profile = addon.BookMagicEffects.Resolve(tags[addon.Constants.MAGIC_TAG_TYPE] or tags.Magieart)
    if not profile then return false end
    local state = slot.bookCreation
    if not state then
        local host = CreateFrame("Frame", nil, slot)
        host:SetAllPoints(slot)
        host:SetFrameLevel(slot:GetFrameLevel() + 6)
        host:SetClipsChildren(true)
        host:EnableMouse(false)
        state = { host = host, slot = slot, originals = {}, slices = {}, rows = {} }
        state.cancel = function() finishWriting(state) end
        slot.bookCreation = state
        slot:HookScript("OnHide", state.cancel)
        slot:HookScript("OnSizeChanged", state.cancel)
    end
    finishWriting(state)
    if slot.bookMagicText then stopGlow(slot.bookMagicText) end
    if slot.bookMagicBody then stopGlow(slot.bookMagicBody) end
    state.host:Show()
    local count = captureBurn(state, slot.icon, false, 0)
    for i = 1, count do
        local slice = state.slices[i]
        slice.delay = addon.BookMagicEffects.WritingDelay(profile, slice.column, 1) * 0.7
        slice.copy:SetAlpha(0)
    end
    for i = count + 1, #state.slices do state.slices[i].clip:Hide() end
    state.writeCursor = 0.55
    local rows = captureWriting(state, slot.name, 1, 0)
    state.writeCursor = state.writeCursor + 0.18
    rows = captureWriting(state, slot.excerpt, 2, rows)
    for i = rows + 1, #state.rows do state.rows[i].clip:Hide() end
     
     
    local speed = math.min(1, 11.3 / state.writeCursor)
    for i = 1, rows do
        state.rows[i].delay = state.rows[i].delay * speed
        state.rows[i].duration = state.rows[i].duration * speed
    end
    state.duration = math.max(5, state.writeCursor * speed + 0.7)
    state.id, state.text, state.book = slot.spellID, slot.name:GetText(), panel.spellbook
    state.tabID, state.page = panel.activeTabID, panel.currentPage
    state.signature = { name = spell.name, description = spell.description, icon = spell.icon,
        nameColor = spell.nameColor, magicType = tags[addon.Constants.MAGIC_TAG_TYPE] or tags.Magieart }
    state.playing, slot.bookInscription = true, state
    state.generation = (state.generation or 0) + 1
    local token = state.generation
    local elapsed, lastUpdate, duration = resumeElapsed or 0, -1, state.duration
    local function update(_, delta)
        if state.generation ~= token then return end
        if reducedMotion() or not panel.fancyPresentation or panel.spellbook ~= state.book or slot.spellID ~= state.id
            or not slot:IsVisible() then finishWriting(state); return end
        elapsed = elapsed + delta
        state.elapsed = elapsed
        if elapsed >= duration then finishWriting(state); return end
        if elapsed - lastUpdate < 1 / 30 then return end
        lastUpdate = elapsed
        for i = 1, count do
            local slice = state.slices[i]
            local t = clamp((elapsed - slice.delay) / 0.85)
            slice.copy:SetAlpha(slice.alpha * t * t * (3 - 2 * t))
        end
        for i = 1, rows do
            local entry = state.rows[i]
            local age = elapsed - entry.delay
            local t = clamp(age / entry.duration)
            local _, extent = addon.BookMagicEffects.Reveal(profile, t)
             
            local x, width = 0, extent * entry.width
            entry.clip:ClearAllPoints()
            entry.clip:SetPoint("TOPLEFT", entry.source, "TOPLEFT", x, -entry.y)
            entry.clip:SetSize(math.max(0.01, width), entry.height)
            entry.clip:SetAlpha(t > 0 and 1 or 0)
            entry.copy:SetAlpha(entry.alpha)
            local nib = width - entry.stroke
            entry.front:ClearAllPoints()
            entry.front:SetPoint("TOPLEFT", entry.source, "TOPLEFT", nib, -entry.y)
            entry.front:SetSize(entry.stroke, entry.height)
            entry.tip:ClearAllPoints()
            entry.tip:SetPoint("TOPLEFT", entry.source, "TOPLEFT", width - entry.stroke * 0.20, -entry.y)
            entry.tip:SetSize(entry.stroke * 0.20, entry.height)
            local r, g, b = addon.BookMagicEffects.Sample(profile, t, i, true)
            local light = age > 0 and (0.88 + 0.12 * math.sin(age * 3) ^ 2)
                * (1 - clamp((age - entry.duration) / 0.6)) or 0
            if entry.isName then
                local color = entry.color
                r, g, b = color[1] + (1 - color[1]) * 0.3,
                    color[2] + (1 - color[2]) * 0.3, color[3] + (1 - color[3]) * 0.3
            end
            entry.glow:SetTextColor(r, g, b, 1)
            entry.glow:SetAlpha(light)
            entry.highlight:SetTextColor(r + (1 - r) * 0.55, g + (1 - g) * 0.55, b + (1 - b) * 0.55, 1)
            entry.highlight:SetAlpha(light)
        end
    end
    state.host:SetScript("OnUpdate", update)
    update(state.host, 0)
    return true
end
