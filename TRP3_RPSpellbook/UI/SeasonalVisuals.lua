local _, addon = ...

addon.SeasonalVisuals = {}
local Visuals = addon.SeasonalVisuals
local advance
local states = setmetatable({}, { __mode = "k" })
local kinds = { book = true, npc = true, import = true, settings = true }
local initialized, shuttingDown = false, false
local function decorationLevel(owner, state)
    return math.max(0, owner:GetFrameLevel() - 1)
end
local positions = { 0.04, 0.14, 0.24, 0.34, 0.44, 0.54, 0.64, 0.74, 0.84, 0.94, 0.29, 0.69 }
local MAX_PARTICLES = 48
local batPositions, batHeights = { 0.08, 0.82, 0.2 }, { 0.22, 0.62, 0.78 }
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
    local calendar = addon.SeasonalCalendar
    return calendar and addon.SeasonalStyles.Resolve(calendar.GetActiveThemes()) or nil
end

local function stop(state)
    state.active = false
    if not state.host then return end
    state.host:SetScript("OnUpdate", nil)
    for _, sprite in ipairs(state.sprites) do
        if sprite.group then sprite.group:Stop() end
        if sprite.flipGroup then sprite.flipGroup:Stop() end
        if sprite.swayGroup then sprite.swayGroup:Stop() end
        sprite.texture:Hide()
    end
    if state.light then
        if state.light.group then state.light.group:Stop() end
        for _, moon in ipairs(state.light.moons or {}) do if moon.group then moon.group:Stop() end end
        state.light.frame:Hide()
    end
    for _, item in ipairs(state.navigation or {}) do
        item.texture:Hide()
        if item.label then item.label:SetAlpha(item.alpha) end
    end
    if state.ribbon then state.ribbon:Hide() end
    addon.SeasonalCorners.Hide(state.host)
    state.host:Hide()
    if state.garland then state.garland:Hide() end
end

local function sprite(host)
    local texture = host:CreateTexture(nil, "ARTWORK")
    local result = { texture = texture, endpoint = {} }
    if type(texture.CreateAnimationGroup) == "function" then
        result.group = texture:CreateAnimationGroup()
        result.group:SetLooping("REPEAT")
        result.move = result.group:CreateAnimation("Translation")
        result.fall = result.group:CreateAnimation("Translation")
        result.fadeIn = result.group:CreateAnimation("Alpha")
        result.fadeOut = result.group:CreateAnimation("Alpha")
        result.turn = result.group:CreateAnimation("Rotation")
        result.move:SetOrder(1)
        result.fall:SetOrder(1)
        result.fadeIn:SetOrder(1)
        result.fadeOut:SetOrder(1)
        result.turn:SetOrder(1)
        result.fadeIn:SetFromAlpha(0)
        result.fadeOut:SetToAlpha(0)
    end
    return result
end

local function createHost(owner, state)
    local host = CreateFrame("Frame", nil, owner)
    host:SetAllPoints(owner)
    host:SetFrameLevel(decorationLevel(owner, state))
    host.behindContent = true
    host:SetClipsChildren(true)
    host:EnableMouse(false)
    host:EnableMouseWheel(false)
    host.bookAnimationManaged = true
    host:Hide()
    state.host, state.sprites = host, {}
    host.particles = CreateFrame("Frame", nil, host)
    if host.behindContent then host.particles:SetFrameLevel(host:GetFrameLevel()) end
    host.particles:SetAllPoints(host)
    host.particles:EnableMouse(false)
    host.particles:EnableMouseWheel(false)
    host.particles.bookAnimationManaged = true
    host.sprites = state.sprites
    owner.seasonalDecoration = host
    state.onUpdate = function(_, elapsed) advance(state, elapsed) end
    host.RequestPoseUpdate = function()
        if state.active and host:IsVisible() then host:SetScript("OnUpdate", state.onUpdate) end
    end
end

local function particlePose(item, host)
    local age = math.max(0, item.elapsed)
    local progress = math.min(1, age / item.duration)
    local travel = item.heart and progress * (1.6 - 0.6 * progress) or progress
    local wave = math.sin(age * item.waveRate + item.phase) * math.sin(progress * math.pi)
    item.texture:SetPoint("TOPLEFT", host, "TOPLEFT", item.x + item.dx * travel + item.swayAmount * wave,
        item.y + item.dy * travel)
    item.texture:SetAlpha(math.max(0, math.min(1, age / item.fadeInTime, (item.duration - age) / item.fadeOutTime)))
    item.texture:SetRotation((item.degrees * progress + wave * item.flutter) * math.pi / 180)
end

local function flight(item, state, spec, index)
    local particle, width, height = spec.particle, state.width, state.height
    local motion, size = particle.motion, particle.size
    local x = math.random() * math.max(0, width - size)
    local y = size
    local dx = (math.random() - 0.5) * width * 0.07
    local dy = -height - size * 2
    local duration = (height + size * 2) / (28 + math.random() * 12)
    local degrees, swayAmount = 0, 0
    local texture = particle.alternate and index % 3 == 0 and particle.alternate or particle.texture
    local heart = particle.alternate ~= nil and texture == particle.alternate
    if motion == "snow" then
        duration = 10 + math.random() * 5
        swayAmount = 4 + math.random() * 5
    elseif motion == "bubbles" then
        size = 8 + math.random() * 6
        y = -height + math.min(64, height * 0.2)
        if index <= (particle.cornerCount or 0) then x, y = 30 + math.random() * 22, -height + math.min(98, height * 0.4) end
        dx, dy = (math.random() - 0.5) * 20, -y
        duration = math.max(16, dy / (18 + math.random() * 6)) * (0.95 + math.random() * 0.1)
        duration = math.max(16, duration)
    elseif motion == "embers" then
        size = 7 + math.random() * 5
        x, y = math.min(width * 0.2, 18 + math.random() * 45), -height + math.min(60, height * 0.32)
        dx, dy = math.max(0, width - size) * (0.04 + math.random() * 0.92) - x, height * (0.65 + math.random() * 0.25)
        duration = 12 + math.random() * 6
        swayAmount = 6 + math.random() * 12
    elseif motion == "petals" then
        degrees, swayAmount = (math.random() - 0.5) * 80, 8 + math.random() * 8
        if heart then
            y = -height + math.min(80, height * 0.25)
            dx, dy = (math.random() - 0.5) * 50, height * 0.83
            duration = 9 + math.random() * 2
            swayAmount = 0
        else duration = (height + size * 2) / (30 + math.random() * 8) end
    elseif motion == "leaves" then
        local direction = math.random() < 0.5 and -1 or 1
        dx = direction * width * (0.06 + math.random() * 0.06)
        duration = (height + size * 2) / (23 + math.random() * 8)
        degrees = direction * (80 + math.random() * 70)
        swayAmount = -direction * (10 + math.random() * 10)
    elseif motion == "motes" then
        y = -math.random() * math.max(0, height - size)
        dx, dy = (math.random() - 0.5) * width * 0.14, height * (0.12 + math.random() * 0.08)
        duration = 5 + math.random() * 3
    end
    local delay = 0
    if spec.bats then
        x, y = width * batPositions[index], -height * batHeights[index]
        duration = 10 + index * 1.5
        dx, dy = width * (index % 2 == 0 and -0.62 or 0.56), height * (index == 1 and -0.1 or 0.12)
        delay = (index - 1) * 0.7
    end
    item.spec, item.width, item.height = spec, width, height
    item.endpoint[1], item.endpoint[2] = dx, dy
    item.texture:ClearAllPoints()
    item.texture:SetPoint("TOPLEFT", state.host, "TOPLEFT", x, y)
    item.texture:SetSize(size, size)
    item.texture:SetAlpha(item.group and 0 or 1)
    item.texture:SetTexture(texture)
    item.texture:SetRotation(0)
    item.hasSway = false
    item.manual = not spec.bats
    if item.manual then
        item.x, item.y, item.dy, item.duration = x, y, dy, duration
        item.distance = height + size * 2
        item.dx, item.swayAmount, item.degrees = dx, swayAmount, degrees
        item.flutter = motion == "leaves" and 18 or motion == "petals" and 8 or 0
        item.phase, item.waveRate = math.random() * math.pi * 2, 0.8 + math.random()
        item.fadeInTime = math.min(0.6, duration * 0.2)
        item.fadeOutTime = motion == "bubbles" and 0.12 or motion == "embers" and 2.5 or math.min(1.2, duration * 0.2)
        item.elapsed, item.size, item.heart = 0, size, heart
        return
    end
    if not item.group then return end
    item.move:SetOffset(dx, dy)
    item.move:SetSmoothing("NONE")
    item.move:SetDuration(duration)
    item.move:SetStartDelay(delay)
    item.fall:SetOffset(0, 0)
    item.fall:SetDuration(duration * 0.55)
    item.fall:SetStartDelay(delay + duration * 0.45)
    item.fall:SetSmoothing("IN")
    item.fadeIn:SetStartDelay(delay)
    item.fadeIn:SetDuration(1.2)
    item.fadeIn:SetToAlpha(1)
    local fadeDuration = 1.4
    item.fadeOut:SetStartDelay(delay + duration - fadeDuration)
    item.fadeOut:SetDuration(fadeDuration)
    item.fadeOut:SetFromAlpha(1)
    item.turn:SetDuration(duration)
    item.turn:SetStartDelay(delay)
    item.turn:SetDegrees(degrees)
    item.group:SetLooping("REPEAT")
end

advance = function(state, elapsed)
    local host = state.host
    if not state.active or not host:IsVisible() then stop(state); return end
    if type(elapsed) ~= "number" or elapsed ~= elapsed or elapsed <= 0 or elapsed == math.huge then return end
    state.elapsed = (state.elapsed or 0) + elapsed
    if state.elapsed >= 1 / 30 then
        addon.SeasonalCorners.Update(host, state.elapsed)
        state.elapsed = 0
    end
    local moving = addon.SeasonalCorners.HasMotion(host)
    for index, item in ipairs(state.sprites) do
        if not state.reduced and item.enabled and item.manual then
            moving = true
            item.elapsed = item.elapsed + elapsed
            if item.elapsed >= item.duration then
                local remainder = item.elapsed - item.duration
                flight(item, state, item.spec, index)
                if remainder >= item.duration then item.elapsed = math.random() * item.duration
                else item.elapsed = remainder - 0.08 - math.random() * 0.45 end
            end
            particlePose(item, host)
        end
    end
    if not moving then host:SetScript("OnUpdate", nil) end
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
        local frame = CreateFrame("Frame", nil, state.owner)
        frame.bookAnimationManaged = true
        frame:SetAllPoints(state.host)
        frame:SetClipsChildren(true)
        frame:EnableMouse(false)
        frame:EnableMouseWheel(false)
        light = { frame = frame, bands = {}, rays = {}, moons = {} }
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
            pulse:SetDuration(8)
            pulse:SetSmoothing("IN_OUT")
        end
        state.light, state.host.light = light, light
        light.shade = frame:CreateTexture(nil, "BACKGROUND")
        light.shade:SetAllPoints(frame)
        light.shade:SetColorTexture(0.015, 0.025, 0.08, 0.06)
        for index = 1, 3 do
            local ray = frame:CreateTexture(nil, "ARTWORK")
            ray:SetTexture(1117076)
            ray:SetTexCoord(0, 0.55, 0, 0.25)
            ray:SetBlendMode("ADD")
            ray:SetVertexColor(0.46, 0.68, 1, 0.09)
            ray:SetRotation(math.pi / 2 + (index - 2) * 0.08)
            light.rays[index] = ray
        end
        light.orbitClip = CreateFrame("Frame", nil, frame)
        light.orbitClip:EnableMouse(false)
        light.orbitClip:EnableMouseWheel(false)
        light.orbitClip:SetClipsChildren(true)
        light.orbitClip.bookAnimationManaged = true
        light.orbitFrame = CreateFrame("Frame", nil, light.orbitClip)
        light.orbitFrame:SetAllPoints(frame)
        light.orbitFrame:EnableMouse(false)
        light.orbitFrame:EnableMouseWheel(false)
        light.orbitFrame.bookAnimationManaged = true
        for index = 1, 2 do
            local moon = { texture = light.orbitFrame:CreateTexture(nil, "ARTWORK") }
            moon.texture:SetTexture(186179)
            moon.texture:SetBlendMode("BLEND")
            moon.texture:SetVertexColor(index == 1 and 0.4 or 0.72, index == 1 and 0.6 or 0.86, 1,
                index == 1 and 0.28 or 0.36)
            if type(moon.texture.CreateAnimationGroup) == "function" then
                moon.group = moon.texture:CreateAnimationGroup()
                moon.group:SetLooping("REPEAT")
                moon.orbit = moon.group:CreateAnimation("Rotation")
                moon.orbit:SetOrder(1)
                moon.orbit:SetDegrees(360)
                moon.orbit:SetDuration(60)
                moon.orbit:SetSmoothing("NONE")
            end
            light.moons[index] = moon
        end
    end
    light.frame:SetFrameLevel(decorationLevel(state.owner, state))
    light.orbitClip:SetFrameLevel(light.frame:GetFrameLevel())
    light.orbitFrame:SetFrameLevel(light.frame:GetFrameLevel())
    light.orbitClip:ClearAllPoints()
    light.orbitClip:SetPoint("TOPLEFT", light.frame, "TOPLEFT", 0, -math.min(86, height * 0.18))
    light.orbitClip:SetPoint("BOTTOMRIGHT", light.frame, "BOTTOMRIGHT", 0, 0)
    local bandHeight = height * 0.9 / #light.bands
    for index, texture in ipairs(light.bands) do
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", light.frame, "TOPLEFT", 0, -(index - 1) * bandHeight)
        texture:SetSize(width, bandHeight)
    end
    for index, ray in ipairs(light.rays) do
        ray:ClearAllPoints()
        ray:SetPoint("CENTER", light.frame, "TOPLEFT", width * (0.22 + (index - 1) * 0.28), -height * 0.36)
        ray:SetSize(height * 0.78, width * 0.2)
    end
    for index, moon in ipairs(light.moons) do
        moon.texture:ClearAllPoints()
        local radius = math.min(width * 0.48, height * 0.53)
        local angle = index == 1 and -math.pi * 0.7 or -math.pi * 0.3
        local ox, oy = radius * math.cos(angle), radius * math.sin(angle)
        moon.texture:SetPoint("CENTER", light.orbitFrame, "TOPLEFT", width * 0.5 + ox, height * 0.3 + oy)
        local size = math.min(index == 1 and 24 or 32, width * 0.06)
        moon.texture:SetSize(size, size)
        if moon.orbit then moon.orbit:SetOrigin("CENTER", -ox, -oy) end
    end
    light.frame:Show()
end

local function navigation(owner, state, kind)
    local previous, following = owner.previousPageButton, owner.nextPageButton
    if not previous or not following then return end
    if kind == "hearts" then
        state.navigation = state.navigation or {}
        for index, button in ipairs({ previous, following }) do
            local item = state.navigation[index]
            if not item then
                item = { texture = button:CreateTexture(nil, "OVERLAY") }
                item.texture:SetTexture(166311)
                item.texture:SetSize(18, 18)
                item.texture:SetPoint("CENTER", button, "CENTER")
                item.texture:SetVertexColor(1, 0.32, 0.48, 0.95)
                item.texture:SetRotation(index == 1 and -math.pi / 2 or math.pi / 2)
                state.navigation[index] = item
                if type(button.IsEnabled) == "function" then
                    local function sync() item.texture:SetAlpha(button:IsEnabled() and 1 or 0.3) end
                    button:HookScript("OnEnable", sync)
                    button:HookScript("OnDisable", sync)
                end
            end
            item.label = type(button.GetFontString) == "function" and button:GetFontString() or nil
            if item.label then item.alpha = item.label:GetAlpha(); item.label:SetAlpha(0) end
            local enabled = type(button.IsEnabled) ~= "function" or button:IsEnabled()
            item.texture:SetAlpha(enabled and 1 or 0.3)
            item.texture:Show()
        end
    elseif kind == "ribbon" then
        if not state.ribbon then
            local frame = CreateFrame("Frame", nil, owner)
            frame:EnableMouse(false)
            frame:EnableMouseWheel(false)
            frame.lines = {}
            for index = 1, 8 do
                local line = frame:CreateLine(nil, "OVERLAY")
                line:SetThickness(1.7)
                line:SetColorTexture(0.68, 0.08, 0.06, 0.85)
                frame.lines[index] = line
            end
            state.ribbon = frame
        end
        local frame = state.ribbon
        frame:SetFrameLevel(math.max(previous:GetFrameLevel(), following:GetFrameLevel()))
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", previous, "TOPLEFT", -3, 3)
        frame:SetPoint("BOTTOMRIGHT", following, "BOTTOMRIGHT", 3, -3)
        for index, corners in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            frame.lines[index]:SetStartPoint(corners[1], frame, 0, 0)
            frame.lines[index]:SetEndPoint(corners[2], frame, 0, 0)
        end
        local bow = { { -9, 5, 0, 0 }, { 0, 0, 9, 5 }, { -9, 5, -6, -1 }, { 9, 5, 6, -1 } }
        for index, points in ipairs(bow) do
            frame.lines[index + 4]:SetStartPoint("TOP", frame, points[1], points[2])
            frame.lines[index + 4]:SetEndPoint("TOP", frame, points[3], points[4])
        end
        frame:Show()
    end
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
    trim:SetFrameLevel(math.max(0, decorationLevel(owner, state) - 1))
    trim:ClearAllPoints()
    trim:SetPoint("TOPLEFT", owner, "TOPLEFT", 6, (ornament.lanterns and 18 or 10) + (ornament.lift or 0))
    local length = math.max(1, width - 34)
    trim:SetSize(length, ornament.height)
    for index, line in ipairs(trim.wire) do
        local first, last = (index - 1) / #trim.wire, index / #trim.wire
        line:SetStartPoint("TOPLEFT", trim, length * first, -10 - math.sin(first * math.pi) * 4 + (ornament.wireLift or 0))
        line:SetEndPoint("TOPLEFT", trim, length * last, -10 - math.sin(last * math.pi) * 4 + (ornament.wireLift or 0))
    end
    local count = ornament.count
    local custom = (not ornament.models or ornament.floral) and ornament.motif ~= "lights" and ornament.motif ~= "lanterns"
    for index, bulb in ipairs(trim.bulbs) do
        local shown = not custom and not ornament.models and index <= count
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
        if states[parent] then return parent end
        parent = parent:GetParent()
    end
    return false
end

local function layoutSurface(owner, state)
    local layers = state.layers
    if not layers then return end
    local root = nested(owner) or owner
    local backgroundLevel = math.max(0, root:GetFrameLevel() - 3)
    for _, frame in pairs(layers.backgrounds or {}) do
        if frame:GetFrameLevel() ~= backgroundLevel then frame:SetFrameLevel(backgroundLevel) end
    end
    for _, frame in pairs(layers.foreground or {}) do
        if frame:GetFrameLevel() ~= owner:GetFrameLevel() then frame:SetFrameLevel(owner:GetFrameLevel()) end
    end
end

local function update(owner, state, selected)
    if not selected or not visible(owner) or nested(owner) then stop(state); return end
    local width, height = owner:GetWidth(), owner:GetHeight()
    if width <= 0 or height <= 0 then stop(state); return end
    local settings = addon.SpellCreationSettings
    local reduced = settings.ShouldReduceBookMotion and settings.ShouldReduceBookMotion() == true or false
    local level, scale, parent = owner:GetFrameLevel(), owner:GetEffectiveScale(), owner:GetParent()
    if state.active and state.theme == selected and state.reduced == reduced
        and state.width == width and state.height == height
        and state.level == level and state.scale == scale and state.parent == parent then return end
    stop(state)
    if not state.host then createHost(owner, state) end
    state.theme, state.reduced, state.width, state.height = selected, reduced, width, height
    state.level, state.scale, state.parent = level, scale, parent
    local host = state.host
    host.theme = selected
    host:SetFrameLevel(decorationLevel(owner, state))
    if host.behindContent then host.particles:SetFrameLevel(host:GetFrameLevel()) end
    local spec = addon.SeasonalStyles.Get(selected)
    local ornament = spec.ornament
    if ornament.hanging and not ornament.banner then garland(owner, state, width, ornament) end
    if spec.navigation then navigation(owner, state, spec.navigation) end
    local particle = spec.particle
    local count = particle.count or #positions
    count = type(count) == "number" and count == count and math.floor(math.max(0, math.min(MAX_PARTICLES, count))) or 0
    if reduced or spec.moonlight then count = 0
    elseif spec.bats then count = #batPositions end
    for index = #state.sprites + 1, count do state.sprites[index] = sprite(host.particles) end
    for index = count + 1, #state.sprites do
        state.sprites[index].enabled = false
        state.sprites[index].texture:SetShown(false)
    end
    for index = 1, count do
        local item = state.sprites[index]
        item.enabled = true
        local texture = item.texture
        texture:ClearAllPoints()
        texture:SetSize(particle.size, particle.size)
        texture:SetTexture(particle.texture)
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetBlendMode(particle.blend)
        texture:SetVertexColor(particle.color[1], particle.color[2], particle.color[3], particle.alpha)
        texture:Show()
        if spec.bats then batAnimation(item, index, reduced) end
        if not spec.bats and item.manual and item.spec == spec and item.width == width and item.height == height then
            texture:SetSize(item.size, item.size)
            texture:SetTexture(particle.alternate and index % 3 == 0 and particle.alternate or particle.texture)
        else
            flight(item, state, spec, index)
            if item.manual then item.elapsed = item.duration * (index - 1 + math.random()) / count end
        end
        if item.manual then particlePose(item, host) end
    end
    if spec.webTexture then
        edgeWebs(host, spec.webTexture, width, height)
    elseif host.webs then
        for _, texture in ipairs(host.webs) do texture:SetShown(false) end
    end
    if spec.moonlight then moonlight(state, width, height) end
    state.active = true
    host:Show()
    addon.SeasonalCorners.Refresh(host, spec, width, height, reduced)
    if not reduced then
        for index = 1, count do
            local item = state.sprites[index]
            if item.group and not item.manual then item.group:Play() end
            if item.hasSway and not item.manual then item.swayGroup:Play() end
            if spec.bats and item.flipGroup then item.flipGroup:Play() end
        end
        if spec.moonlight and state.light.group then
            state.light.group:Play()
            for _, moon in ipairs(state.light.moons) do if moon.group then moon.group:Play() end end
        end
    end
    local moving = addon.SeasonalCorners.HasMotion(host)
    for _, item in ipairs(state.sprites) do moving = moving or not reduced and item.enabled and item.manual end
    if moving then
        state.elapsed = 0
        host:SetScript("OnUpdate", state.onUpdate)
    end
end

function Visuals.Refresh()
    if not initialized then return end
    local selected = theme()
    for owner, state in pairs(states) do
        if state.layers and not nested(owner) then
            local parent = owner:GetParent()
            local minimum = (parent and parent:GetFrameLevel() or 0) + 4
            if owner:GetFrameLevel() < minimum then owner:SetFrameLevel(minimum) end
        end
    end
    for owner, state in pairs(states) do layoutSurface(owner, state) end
    for owner, state in pairs(states) do update(owner, state, selected) end
end

function Visuals.GetThemes() return addon.SeasonalStyles.GetThemes() end

function Visuals.RefreshSettings()
    if not initialized then return end
    local settings, calendar = addon.SpellCreationSettings, addon.SeasonalCalendar
    if calendar and calendar.SetEnabled then
        calendar.SetEnabled(not shuttingDown and settings.ShouldUseSeasonalThemes() == true)
    end
    Visuals.Refresh()
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

function Visuals.Attach(owner, kind, layers)
    if not owner or not kinds[kind] or states[owner] or type(owner.HookScript) ~= "function" then return false end
    local state = { owner = owner, kind = kind, layers = layers }
    states[owner] = state
    owner:HookScript("OnShow", Visuals.Refresh)
    owner:HookScript("OnHide", function() stop(state) end)
    owner:HookScript("OnSizeChanged", Visuals.Refresh)
    if initialized then Visuals.Refresh() end
    return true
end
