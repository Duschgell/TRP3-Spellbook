local _, addon = ...

addon.SpellCreationThemes = {}

local themes = addon.SpellCreationThemes
local function reducedMotion()
    local settings = addon.SpellCreationSettings
    return settings and settings.ShouldReduceBookMotion and settings.ShouldReduceBookMotion() or false
end
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local FANCY_PAGE_TEXTURE = 375503
local FANCY_PAGE_END_TEXTURE = 375504
local BACKDROP = {
    bgFile = WHITE_TEXTURE,
    edgeFile = WHITE_TEXTURE,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function rgba(red, green, blue, alpha)
    return { red, green, blue, alpha }
end

local function spec(background, border, accent, text, textMuted, decoration)
    return {
        background = background,
        border = border,
        accent = accent,
        text = text,
        textMuted = textMuted,
        topAccentAlpha = decoration == false and 0 or 0.10,
        bottomShadeAlpha = decoration == false and 0 or 0.16,
         
        backgroundImage = nil,
    }
end

local catalog = {
    default = spec(
        rgba(0.055, 0.045, 0.035, 0.98), rgba(0.86, 0.66, 0.29, 1),
        rgba(0.86, 0.66, 0.29, 1), rgba(0.96, 0.87, 0.68, 1),
        rgba(0.76, 0.69, 0.56, 1), false
    ),
    midnight = spec(
        rgba(0.018, 0.026, 0.055, 0.985), rgba(0.18, 0.38, 0.62, 1),
        rgba(0.34, 0.68, 0.96, 1), rgba(0.86, 0.92, 1, 1),
        rgba(0.57, 0.68, 0.82, 1)
    ),
    parchment = spec(
        rgba(0.16, 0.115, 0.060, 0.985), rgba(0.62, 0.43, 0.19, 1),
        rgba(0.96, 0.74, 0.34, 1), rgba(1, 0.91, 0.70, 1),
        rgba(0.80, 0.68, 0.49, 1)
    ),
    emerald = spec(
        rgba(0.018, 0.065, 0.052, 0.985), rgba(0.12, 0.46, 0.32, 1),
        rgba(0.34, 0.86, 0.54, 1), rgba(0.87, 0.98, 0.90, 1),
        rgba(0.57, 0.76, 0.64, 1)
    ),
    titan = spec(
        rgba(0.075, 0.068, 0.053, 0.985), rgba(0.61, 0.42, 0.19, 1),
        rgba(0.30, 0.77, 0.82, 1), rgba(0.96, 0.92, 0.81, 1),
        rgba(0.74, 0.72, 0.63, 1)
    ),
}
catalog.titan.titanGeometry = true

catalog.fancy = spec(
    rgba(0, 0, 0, 0), rgba(0.52, 0.38, 0.16, 0.45),
    rgba(0.035, 0.34, 0.30, 1), rgba(0.18, 0.10, 0.045, 1),
    rgba(0.38, 0.27, 0.15, 1), false
)
catalog.fancy.fancy = true
catalog.fancy.backgroundImage = {
    texture = FANCY_PAGE_TEXTURE,
    alpha = 1,
    stretch = true,
    texCoords = { 0.20, 0.90, 0.13, 0.84 },
}
catalog.fancy.pageEndTexture = FANCY_PAGE_END_TEXTURE

local function dynamic(background, border, accent, text, textMuted)
    return spec(
        rgba(background[1], background[2], background[3], 0.985),
        rgba(border[1], border[2], border[3], 1),
        rgba(accent[1], accent[2], accent[3], 1),
        rgba(text[1], text[2], text[3], 1),
        rgba(textMuted[1], textMuted[2], textMuted[3], 1)
    )
end

catalog["dynamic:neutral"] = dynamic(
    { 0.045, 0.047, 0.052 }, { 0.34, 0.35, 0.38 }, { 0.70, 0.72, 0.76 },
    { 0.94, 0.94, 0.95 }, { 0.67, 0.68, 0.71 }
)
catalog["dynamic:arcane"] = dynamic(
    { 0.075, 0.025, 0.10 }, { 0.50, 0.16, 0.58 }, { 0.90, 0.31, 0.96 },
    { 0.98, 0.89, 1 }, { 0.76, 0.59, 0.81 }
)
catalog["dynamic:light"] = dynamic(
    { 0.105, 0.080, 0.025 }, { 0.63, 0.49, 0.18 }, { 0.98, 0.90, 0.55 },
    { 1, 0.97, 0.84 }, { 0.82, 0.75, 0.54 }
)
catalog["dynamic:demonic"] = dynamic(
    { 0.025, 0.070, 0.015 }, { 0.17, 0.42, 0.06 }, { 0.48, 0.91, 0.18 },
    { 0.91, 0.99, 0.84 }, { 0.62, 0.77, 0.51 }
)
catalog["dynamic:nature"] = dynamic(
    { 0.018, 0.068, 0.035 }, { 0.10, 0.46, 0.19 }, { 0.27, 0.84, 0.30 },
    { 0.88, 0.99, 0.88 }, { 0.56, 0.77, 0.58 }
)
catalog["dynamic:necromancy"] = dynamic(
    { 0.055, 0.035, 0.043 }, { 0.31, 0.20, 0.24 }, { 0.65, 0.44, 0.51 },
    { 0.96, 0.89, 0.91 }, { 0.70, 0.59, 0.63 }
)
catalog["dynamic:shadow"] = dynamic(
    { 0.035, 0.020, 0.075 }, { 0.28, 0.14, 0.49 }, { 0.55, 0.32, 0.84 },
    { 0.94, 0.88, 1 }, { 0.66, 0.56, 0.78 }
)
catalog["dynamic:elemental"] = dynamic(
    { 0.035, 0.050, 0.060 }, { 0.22, 0.42, 0.54 }, { 0.91, 0.54, 0.20 },
    { 0.92, 0.96, 0.94 }, { 0.62, 0.73, 0.72 }
)
catalog["dynamic:chi"] = dynamic(
    { 0.025, 0.070, 0.050 }, { 0.18, 0.49, 0.31 }, { 0.45, 0.94, 0.49 },
    { 0.89, 1, 0.92 }, { 0.58, 0.79, 0.64 }
)
catalog["dynamic:physical"] = dynamic(
    { 0.070, 0.058, 0.045 }, { 0.45, 0.35, 0.24 }, { 0.76, 0.62, 0.43 },
    { 0.97, 0.92, 0.83 }, { 0.72, 0.66, 0.56 }
)
catalog["dynamic:shot"] = dynamic(
    { 0.045, 0.055, 0.060 }, { 0.32, 0.43, 0.49 }, { 0.62, 0.80, 0.85 },
    { 0.92, 0.97, 0.98 }, { 0.64, 0.73, 0.76 }
)
catalog["dynamic:poison"] = dynamic(
    { 0.025, 0.065, 0.022 }, { 0.18, 0.43, 0.11 }, { 0.38, 0.82, 0.20 },
    { 0.91, 0.99, 0.87 }, { 0.60, 0.76, 0.53 }
)
catalog["dynamic:explosion"] = dynamic(
    { 0.090, 0.035, 0.014 }, { 0.58, 0.21, 0.08 }, { 1, 0.48, 0.12 },
    { 1, 0.93, 0.84 }, { 0.83, 0.63, 0.47 }
)
catalog["dynamic:bleed"] = dynamic(
    { 0.080, 0.018, 0.018 }, { 0.52, 0.08, 0.08 }, { 0.88, 0.19, 0.19 },
    { 1, 0.89, 0.87 }, { 0.79, 0.54, 0.52 }
)
catalog["dynamic:stun"] = dynamic(
    { 0.075, 0.060, 0.018 }, { 0.51, 0.38, 0.08 }, { 0.94, 0.76, 0.17 },
    { 1, 0.96, 0.82 }, { 0.80, 0.71, 0.48 }
)

local talentBackgrounds = {
    ["dynamic:arcane"] = "bg-mage-arcane",
    ["dynamic:light"] = "bg-priest-discipline",
    ["dynamic:demonic"] = "bg-warlock-demonology",
    ["dynamic:nature"] = "bg-druid-restoration",
    ["dynamic:necromancy"] = "bg-deathknight-unholy",
    ["dynamic:shadow"] = "bg-warlock-affliction",
    ["dynamic:elemental"] = "bg-shaman-elemental",
    ["dynamic:chi"] = "bg-monk-mistweaver",
    ["dynamic:physical"] = "bg-warrior-protection",
    ["dynamic:shot"] = "bg-hunter-marksman",
    ["dynamic:poison"] = "bg-rogue-combat",
    ["dynamic:explosion"] = "bg-warlock-destruction",
    ["dynamic:bleed"] = "bg-warrior-fury",
    ["dynamic:stun"] = "bg-paladin-retribution",
}
for themeID, background in pairs(talentBackgrounds) do
    catalog[themeID].backgroundImage = {
        texture = "Interface\\TALENTFRAME\\" .. background,
        alpha = 0.28,
        aspectRatio = 1,
    }
end

themes.StaticPresetIDs = { "default", "midnight", "parchment", "emerald", "titan" }

local tabThemeOptions = {
    { value = "default", labelKey = "SPELL_CREATION_EDITOR_THEME_DEFAULT" },
    { value = "midnight", labelKey = "SPELL_CREATION_EDITOR_THEME_MIDNIGHT" },
    { value = "parchment", labelKey = "SPELL_CREATION_EDITOR_THEME_PARCHMENT" },
    { value = "emerald", labelKey = "SPELL_CREATION_EDITOR_THEME_EMERALD" },
    { value = "titan", labelKey = "SPELL_CREATION_EDITOR_THEME_TITAN" },
    { value = "dynamic:arcane", labelKey = "PRESET_MAGIC_ARCANE" },
    { value = "dynamic:light", labelKey = "PRESET_MAGIC_LIGHT" },
    { value = "dynamic:demonic", labelKey = "PRESET_MAGIC_DEMONIC" },
    { value = "dynamic:nature", labelKey = "PRESET_MAGIC_NATURE" },
    { value = "dynamic:necromancy", labelKey = "PRESET_MAGIC_NECROMANCY" },
    { value = "dynamic:shadow", labelKey = "PRESET_MAGIC_SHADOW" },
    { value = "dynamic:elemental", labelKey = "PRESET_MAGIC_ELEMENTAL" },
    { value = "dynamic:chi", labelKey = "PRESET_MAGIC_CHI" },
    { value = "dynamic:physical", labelKey = "PRESET_DAMAGE_PHYSICAL" },
    { value = "dynamic:shot", labelKey = "PRESET_DAMAGE_SHOT" },
    { value = "dynamic:poison", labelKey = "PRESET_DAMAGE_POISON" },
    { value = "dynamic:explosion", labelKey = "PRESET_DAMAGE_EXPLOSION" },
    { value = "dynamic:bleed", labelKey = "PRESET_DAMAGE_BLEED" },
    { value = "dynamic:stun", labelKey = "PRESET_DAMAGE_STUN" },
}

local staticAliases = {
    default = "default", standard = "default",
    fancy = "fancy", grimoire = "fancy", grimoiretheme = "fancy",
    midnight = "midnight", mitternacht = "midnight",
    parchment = "parchment", pergament = "parchment",
    emerald = "emerald", smaragd = "emerald",
    emeralddream = "emerald", smaragdgruenertraum = "emerald",
    titan = "titan", titanic = "titan", titanisch = "titan",
}
local magicAliases = {
    arcane = "arcane", arkan = "arcane",
    light = "light", licht = "light", holy = "light", heilig = "light",
    demonic = "demonic", daemonisch = "demonic",
    nature = "nature", natur = "nature",
    necromancy = "necromancy", nekromantie = "necromancy",
    shadow = "shadow", schatten = "shadow",
    elemental = "elemental", elementar = "elemental",
    chi = "chi",
}
local damageAliases = {
    physical = "physical", physisch = "physical",
    shot = "shot", schuss = "shot",
    poison = "poison", gift = "poison",
    explosion = "explosion",
    bleed = "bleed", blutung = "bleed",
    stun = "stun", betaeubung = "stun",
}
local kindAliases = {
    magic = "magic", magie = "magic", spell = "magic", zauber = "magic",
    ability = "ability", faehigkeit = "ability", skill = "ability",
}
local localizedAliasesReady = false

local function normalize(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then
        return nil
    end
    value = value:gsub("Ä", "Ae"):gsub("Ö", "Oe"):gsub("Ü", "Ue")
        :gsub("ä", "ae"):gsub("ö", "oe"):gsub("ü", "ue")
        :gsub("ß", "ss")
    value = string.lower(value)
    value = value:gsub("[%s_%-:]+", "")
    return value
end

local function addLocalizedAliases(target, options)
    if type(options) ~= "table" then
        return
    end
    for _, option in ipairs(options) do
        local key = normalize(option and option.label)
        local value = normalize(option and option.value)
        if key and value and target[value] then
            target[key] = target[value]
        end
    end
end

local function refreshLocalizedAliases()
    if localizedAliasesReady then
        return
    end
    local presets = addon.SpellCreationPresets
    if type(presets) ~= "table" then
        return
    end
    local magicReady = false
    local damageReady = false
    if type(presets.GetMagicTypes) == "function" then
        local success, options = pcall(presets.GetMagicTypes)
        if success then
            addLocalizedAliases(magicAliases, options)
            magicReady = true
        end
    end
    if type(presets.GetDamageTypes) == "function" then
        local success, options = pcall(presets.GetDamageTypes)
        if success then
            addLocalizedAliases(damageAliases, options)
            damageReady = true
        end
    end
    localizedAliasesReady = magicReady and damageReady
end

local function copyColor(color)
    return { color[1], color[2], color[3], color[4] }
end

local function copySpec(source)
    local result = {
        background = copyColor(source.background),
        border = copyColor(source.border),
        accent = copyColor(source.accent),
        text = copyColor(source.text),
        textMuted = copyColor(source.textMuted),
        topAccentAlpha = source.topAccentAlpha,
        bottomShadeAlpha = source.bottomShadeAlpha,
        fancy = source.fancy == true,
        titanGeometry = source.titanGeometry == true,
        pageEndTexture = source.pageEndTexture,
    }
    if type(source.backgroundImage) == "table" then
        result.backgroundImage = {
            texture = source.backgroundImage.texture,
            atlas = source.backgroundImage.atlas,
            alpha = source.backgroundImage.alpha,
            aspectRatio = source.backgroundImage.aspectRatio,
            stretch = source.backgroundImage.stretch == true,
            texCoords = type(source.backgroundImage.texCoords) == "table" and {
                source.backgroundImage.texCoords[1],
                source.backgroundImage.texCoords[2],
                source.backgroundImage.texCoords[3],
                source.backgroundImage.texCoords[4],
            } or nil,
        }
    end
    return result
end


local resetTexture
local getLayer

local fancyRunes = {
    {
        texture = "Interface\\Spellbook\\UI-Glyph-Rune-1",
        y = 0.34,
        fromAlpha = 0.18,
        toAlpha = 0.58,
        duration = 2.8,
        delay = 0,
    },
    {
        texture = "Interface\\Spellbook\\UI-Glyph-Rune-4",
        y = 0.42,
        fromAlpha = 0.14,
        toAlpha = 0.50,
        duration = 3.2,
        delay = 0.35,
    },
    {
        texture = "Interface\\Spellbook\\UI-Glyph-Rune-8",
        y = 0.50,
        fromAlpha = 0.16,
        toAlpha = 0.54,
        duration = 3.0,
        delay = 0.7,
    },
}

local fancyParticles = {
    { x = 0.30, y = 0.30, width = 5, height = 7, alpha = 0.10, duration = 4.8, dx = 2, dy = 8 },
    { x = 0.52, y = 0.36, width = 7, height = 9, alpha = 0.13, duration = 5.4, dx = -2, dy = 11 },
    { x = 0.76, y = 0.42, width = 5, height = 6, alpha = 0.09, duration = 4.5, dx = 2, dy = 7 },
    { x = 0.40, y = 0.48, width = 6, height = 8, alpha = 0.11, duration = 5.8, dx = -1, dy = 10 },
    { x = 0.67, y = 0.54, width = 5, height = 7, alpha = 0.09, duration = 5.1, dx = 1, dy = 8 },
}

local fancySliceKeys = {
    "fancyTopLeft", "fancyTop", "fancyTopRight",
    "fancyLeft", "fancyRight",
    "fancyBottomLeft", "fancyBottom", "fancyBottomRight",
}

local function animationCall(target, method, ...)
    if target and type(target[method]) == "function" then
        pcall(target[method], target, ...)
    end
end

local function stopAnimation(target)
    if target and target._fancyAnimation then
        animationCall(target._fancyAnimation, "Stop")
    end
end

local function createFancyAnimation(texture, definition)
    if not texture or texture._fancyAnimation
        or type(texture.CreateAnimationGroup) ~= "function"
    then
        return texture and texture._fancyAnimation
    end
    local success, group = pcall(texture.CreateAnimationGroup, texture)
    if not success or not group then
        return nil
    end
    texture._fancyAnimation = group
    animationCall(group, "SetLooping", "BOUNCE")

    local alphaSuccess, alpha = pcall(group.CreateAnimation, group, "Alpha")
    if alphaSuccess and alpha then
        animationCall(alpha, "SetFromAlpha", definition.fromAlpha or 0.03)
        animationCall(alpha, "SetToAlpha", definition.toAlpha or definition.alpha or 0.12)
        animationCall(alpha, "SetDuration", definition.duration or 3)
        animationCall(alpha, "SetStartDelay", definition.delay or 0)
        animationCall(alpha, "SetSmoothing", "IN_OUT")
    end
    if definition.dx or definition.dy then
        local moveSuccess, movement = pcall(group.CreateAnimation, group, "Translation")
        if moveSuccess and movement then
            animationCall(movement, "SetOffset", definition.dx or 0, definition.dy or 0)
            animationCall(movement, "SetDuration", definition.duration or 3)
            animationCall(movement, "SetStartDelay", definition.delay or 0)
            animationCall(movement, "SetSmoothing", "IN_OUT")
        end
    end
    return group
end

local function setFancyEffectsVisible(frame, visible)
    local layers = frame and frame._spellCreationThemeLayers
    if not layers then
        return
    end
    if frame._fancyRevealAnimation then
        animationCall(frame._fancyRevealAnimation, "Stop")
    end
    local glow = layers.fancyGlow
    stopAnimation(glow)
    if glow and type(glow.SetShown) == "function" then
        glow:SetShown(visible)
    elseif glow and visible and type(glow.Show) == "function" then
        glow:Show()
    elseif glow and type(glow.Hide) == "function" then
        glow:Hide()
    end
    local pageEnd = layers.fancyPageEnd
    if pageEnd and type(pageEnd.SetShown) == "function" then
        pageEnd:SetShown(visible)
    elseif pageEnd and visible and type(pageEnd.Show) == "function" then
        pageEnd:Show()
    elseif pageEnd and type(pageEnd.Hide) == "function" then
        pageEnd:Hide()
    end
    for index = 1, #fancyRunes do
        local rune = layers["fancyRune" .. index]
        stopAnimation(rune)
        if rune and type(rune.SetShown) == "function" then
            rune:SetShown(visible)
        elseif rune and visible and type(rune.Show) == "function" then
            rune:Show()
        elseif rune and type(rune.Hide) == "function" then
            rune:Hide()
        end
    end
    for index = 1, #fancyParticles do
        local particle = layers["fancyParticle" .. index]
        stopAnimation(particle)
        if particle and type(particle.SetShown) == "function" then
            particle:SetShown(visible)
        elseif particle and visible and type(particle.Show) == "function" then
            particle:Show()
        elseif particle and type(particle.Hide) == "function" then
            particle:Hide()
        end
    end
    for _, key in ipairs(fancySliceKeys) do
        local slice = layers[key]
        if slice and type(slice.SetShown) == "function" then
            slice:SetShown(visible)
        elseif slice and visible and type(slice.Show) == "function" then
            slice:Show()
        elseif slice and type(slice.Hide) == "function" then
            slice:Hide()
        end
    end
    local ribbonHost = frame._fancyRibbonHost
    if ribbonHost and ribbonHost ~= frame and type(ribbonHost.SetShown) == "function" then
        ribbonHost:SetShown(visible)
    end
end

local function startFancyAnimation(texture)
    local group = texture and texture._fancyAnimation
    if not group then
        return
    end
    if reducedMotion() then
        animationCall(group, "Stop")
        return
    end
    if type(group.IsPlaying) == "function" then
        local success, playing = pcall(group.IsPlaying, group)
        if success and playing then
            return
        end
    end
    animationCall(group, "Play")
end

local function applyFancySlice(texture, frame, coords, points, width, height)
    if not texture then
        return
    end
    resetTexture(texture)
    animationCall(texture, "SetTexture", FANCY_PAGE_TEXTURE)
    animationCall(texture, "SetSnapToPixelGrid", false)
    animationCall(texture, "SetTexelSnappingBias", 0)
    animationCall(texture, "SetTexCoord", coords[1], coords[2], coords[3], coords[4])
    for _, point in ipairs(points) do
        animationCall(
            texture, "SetPoint",
            point[1], frame, point[2], point[3], point[4]
        )
    end
    if width and height then
        animationCall(texture, "SetSize", width, height)
    elseif width then
        animationCall(texture, "SetWidth", width)
    elseif height then
        animationCall(texture, "SetHeight", height)
    end
    animationCall(texture, "SetAlpha", 1)
    animationCall(texture, "Show")
end

local function applyFancyPageSlices(frame, width, height)
    width = math.max(1, width)
    height = math.max(1, height)
    local leftWidth = math.min(
        math.max(42, math.min(72, width * 0.115)),
        math.max(1, width * 0.45)
    )
    local rightWidth = math.min(
        math.max(24, math.min(40, width * 0.060)),
        math.max(1, width - leftWidth - 1)
    )
    local topHeight = math.min(
        math.max(34, math.min(58, height * 0.105)),
        math.max(1, height * 0.45)
    )
    local bottomHeight = math.min(
        math.max(38, math.min(62, height * 0.115)),
        math.max(1, height - topHeight - 1)
    )
    local left, centerLeft, centerRight, right = 0.085, 0.20, 0.90, 0.965
    local top, centerTop, centerBottom, bottom = 0.01, 0.13, 0.84, 0.965

    local center = frame._spellCreationThemeLayers
        and frame._spellCreationThemeLayers.image
    if center then
        animationCall(center, "ClearAllPoints")
        animationCall(
            center, "SetPoint", "TOPLEFT", frame, "TOPLEFT",
            leftWidth, -topHeight
        )
        animationCall(
            center, "SetPoint", "BOTTOMRIGHT", frame, "BOTTOMRIGHT",
            -rightWidth, bottomHeight
        )
    end

    applyFancySlice(
        getLayer(frame, "fancyTopLeft", "BORDER", -7), frame,
        { left, centerLeft, top, centerTop },
        { { "TOPLEFT", "TOPLEFT", 0, 0 } }, leftWidth, topHeight
    )
    applyFancySlice(
        getLayer(frame, "fancyTop", "BORDER", -7), frame,
        { centerLeft, centerRight, top, centerTop },
        {
            { "TOPLEFT", "TOPLEFT", leftWidth, 0 },
            { "TOPRIGHT", "TOPRIGHT", -rightWidth, 0 },
        }, nil, topHeight
    )
    applyFancySlice(
        getLayer(frame, "fancyTopRight", "BORDER", -7), frame,
        { centerRight, right, top, centerTop },
        { { "TOPRIGHT", "TOPRIGHT", 0, 0 } }, rightWidth, topHeight
    )
    applyFancySlice(
        getLayer(frame, "fancyLeft", "BORDER", -7), frame,
        { left, centerLeft, centerTop, centerBottom },
        {
            { "TOPLEFT", "TOPLEFT", 0, -topHeight },
            { "BOTTOMLEFT", "BOTTOMLEFT", 0, bottomHeight },
        }, leftWidth, nil
    )
    applyFancySlice(
        getLayer(frame, "fancyRight", "BORDER", -7), frame,
        { centerRight, right, centerTop, centerBottom },
        {
            { "TOPRIGHT", "TOPRIGHT", 0, -topHeight },
            { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, bottomHeight },
        }, rightWidth, nil
    )
    applyFancySlice(
        getLayer(frame, "fancyBottomLeft", "BORDER", -7), frame,
        { left, centerLeft, centerBottom, bottom },
        { { "BOTTOMLEFT", "BOTTOMLEFT", 0, 0 } }, leftWidth, bottomHeight
    )
    applyFancySlice(
        getLayer(frame, "fancyBottom", "BORDER", -7), frame,
        { centerLeft, centerRight, centerBottom, bottom },
        {
            { "BOTTOMLEFT", "BOTTOMLEFT", leftWidth, 0 },
            { "BOTTOMRIGHT", "BOTTOMRIGHT", -rightWidth, 0 },
        }, nil, bottomHeight
    )
    applyFancySlice(
        getLayer(frame, "fancyBottomRight", "BORDER", -7), frame,
        { centerRight, right, centerBottom, bottom },
        { { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 } }, rightWidth, bottomHeight
    )
    return leftWidth, rightWidth, topHeight, bottomHeight
end

local function getFancyRibbonHost(
    frame,
    leftWidth,
    topHeight,
    bottomHeight,
    height
)
    local host = frame._fancyRibbonHost
    if not host and type(CreateFrame) == "function" then
        local success, created = pcall(CreateFrame, "Frame", nil, frame)
        if success then
            host = created
            frame._fancyRibbonHost = host
        end
    end
    host = host or frame
    if host ~= frame then
        animationCall(host, "ClearAllPoints")
        animationCall(
            host, "SetPoint", "TOPLEFT", frame, "TOPLEFT",
            0, -topHeight * 0.20
        )
        animationCall(
            host, "SetPoint", "BOTTOMLEFT", frame, "BOTTOMLEFT",
            0, math.max(bottomHeight, height * 0.30)
        )
        animationCall(host, "SetWidth", math.max(16, leftWidth * 0.22))
        animationCall(host, "Show")
    end
    return host
end

local function applyFancyEffects(frame, enabled, animationToken)
    frame._fancyCompositionEnabled = enabled == true
    if not enabled then
        setFancyEffectsVisible(frame, false)
        frame._fancyAnimationToken = nil
        return
    end

    if not frame._fancyOnHideHooked and type(frame.HookScript) == "function" then
        frame._fancyOnHideHooked = true
        frame:HookScript("OnHide", function(hiddenFrame)
            setFancyEffectsVisible(hiddenFrame, false)
            hiddenFrame._fancyAnimationToken = nil
            animationCall(hiddenFrame, "SetAlpha", 1)
        end)
        local function restoreComposition(shownFrame)
             
             
            if shownFrame._fancyCompositionEnabled then
                applyFancyEffects(shownFrame, true)
            end
        end
        frame:HookScript("OnShow", restoreComposition)
        frame:HookScript("OnSizeChanged", restoreComposition)
    end

    local visible = true
    if type(frame.IsVisible) == "function" then
        local success, result = pcall(frame.IsVisible, frame)
        visible = not success or result == true
    end
    if not visible then
        setFancyEffectsVisible(frame, false)
        return
    end

    local width = type(frame.GetWidth) == "function" and tonumber(frame:GetWidth()) or 0
    local height = type(frame.GetHeight) == "function" and tonumber(frame:GetHeight()) or 0
    local leftWidth, _, topHeight, bottomHeight = applyFancyPageSlices(frame, width, height)
    local ribbonHost = getFancyRibbonHost(
        frame, leftWidth, topHeight, bottomHeight, height
    )
    local ribbonWidth = type(ribbonHost.GetWidth) == "function"
        and (tonumber(ribbonHost:GetWidth()) or leftWidth) or leftWidth
    local ribbonHeight = type(ribbonHost.GetHeight) == "function"
        and (tonumber(ribbonHost:GetHeight()) or height * 0.72) or height * 0.72
    local pageEnd = getLayer(frame, "fancyPageEnd", "BORDER", -5)
    if pageEnd then
        resetTexture(pageEnd)
        animationCall(pageEnd, "SetTexture", FANCY_PAGE_END_TEXTURE)
        animationCall(pageEnd, "SetPoint", "TOPRIGHT", frame, "TOPRIGHT", -1, -1)
        animationCall(pageEnd, "SetPoint", "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        animationCall(pageEnd, "SetWidth", 12)
        animationCall(pageEnd, "SetAlpha", 0.96)
        animationCall(pageEnd, "Show")
    end

    local glow = getLayer(frame, "fancyGlow", "BORDER", -5, ribbonHost)
    if glow then
        resetTexture(glow)
        animationCall(glow, "SetTexture", "Interface\\Cooldown\\star4")
        animationCall(glow, "SetBlendMode", "ADD")
        animationCall(glow, "SetVertexColor", 0.10, 0.92, 0.88, 1)
        animationCall(
            glow, "SetSize", math.max(18, ribbonWidth * 1.15),
            math.max(80, ribbonHeight * 0.44)
        )
        animationCall(
            glow, "SetPoint", "CENTER", ribbonHost, "BOTTOM",
            0, ribbonHeight * 0.38
        )
        animationCall(glow, "SetAlpha", 0.08)
        animationCall(glow, "Show")
        createFancyAnimation(glow, {
            fromAlpha = 0.04,
            toAlpha = 0.14,
            duration = 3.6,
        })
        startFancyAnimation(glow)
    end

    local runeSize = math.max(12, math.min(18, height * 0.04))
    for index, definition in ipairs(fancyRunes) do
        local rune = getLayer(frame, "fancyRune" .. index, "BORDER", -4, ribbonHost)
        if rune then
            resetTexture(rune)
            animationCall(rune, "SetTexture", definition.texture)
            animationCall(rune, "SetBlendMode", "ADD")
            animationCall(rune, "SetVertexColor", 0.18, 1, 0.92, 1)
            animationCall(rune, "SetSize", runeSize, runeSize)
            animationCall(
                rune, "SetPoint", "CENTER", ribbonHost, "BOTTOM",
                0, ribbonHeight * definition.y
            )
            animationCall(rune, "SetAlpha", definition.fromAlpha)
            animationCall(rune, "Show")
            createFancyAnimation(rune, definition)
            startFancyAnimation(rune)
        end
    end

    for index, definition in ipairs(fancyParticles) do
        local particle = getLayer(frame, "fancyParticle" .. index, "BORDER", -4, ribbonHost)
        if particle then
            resetTexture(particle)
            animationCall(particle, "SetTexture", "Interface\\Cooldown\\star4")
            animationCall(particle, "SetBlendMode", "ADD")
            animationCall(particle, "SetVertexColor", 0.22, 0.92, 0.84, 1)
            animationCall(particle, "SetSize", definition.width, definition.height)
            animationCall(
                particle,
                "SetPoint",
                "CENTER", ribbonHost, "BOTTOMLEFT",
                ribbonWidth * definition.x, ribbonHeight * definition.y
            )
            animationCall(particle, "SetAlpha", definition.alpha)
            animationCall(particle, "Show")
            createFancyAnimation(particle, definition)
            startFancyAnimation(particle)
        end
    end

    if reducedMotion() and frame._fancyRevealAnimation then
        animationCall(frame._fancyRevealAnimation, "Stop")
        animationCall(frame, "SetAlpha", 1)
    end
    if not reducedMotion() and not frame.bookAnimationManaged and animationToken ~= nil
        and frame._fancyAnimationToken ~= animationToken
        and type(frame.CreateAnimationGroup) == "function"
    then
        frame._fancyAnimationToken = animationToken
        if not frame._fancyRevealAnimation then
            local success, group = pcall(frame.CreateAnimationGroup, frame)
            if success and group then
                frame._fancyRevealAnimation = group
                local alphaSuccess, alpha = pcall(group.CreateAnimation, group, "Alpha")
                if alphaSuccess and alpha then
                    animationCall(alpha, "SetFromAlpha", 0)
                    animationCall(alpha, "SetToAlpha", 1)
                    animationCall(alpha, "SetDuration", 0.35)
                    animationCall(alpha, "SetSmoothing", "OUT")
                end
            end
        end
        if frame._fancyRevealAnimation then
            animationCall(frame._fancyRevealAnimation, "Stop")
            animationCall(frame._fancyRevealAnimation, "Play")
        end
    end
end

local function resolveStatic(selectedTheme)
    local normalized = normalize(selectedTheme)
    if not normalized then
        return "default"
    end
    return staticAliases[normalized]
end

local function isDynamic(selectedTheme)
    local normalized = normalize(selectedTheme)
    return normalized == "dynamic" or normalized == "dynamisch"
        or normalized == "automatic" or normalized == "automatisch"
end

function themes.Resolve(selectedTheme, kind, magicType, damageType)
    refreshLocalizedAliases()
    local selectedKey = normalize(selectedTheme)
    if selectedKey and selectedKey:match("^dynamic") then
        for themeID in pairs(catalog) do
            if themeID:match("^dynamic:") and normalize(themeID) == selectedKey then
                return copySpec(catalog[themeID]), themeID
            end
        end
    end
    local resolvedID = resolveStatic(selectedTheme)
    if not isDynamic(selectedTheme) then
        resolvedID = resolvedID or "default"
        return copySpec(catalog[resolvedID]), resolvedID
    end

    local resolvedKind = kindAliases[normalize(kind)]
    local themeType
    if resolvedKind == "magic" then
        themeType = magicAliases[normalize(magicType)]
    elseif resolvedKind == "ability" then
        themeType = damageAliases[normalize(damageType)]
    end
    resolvedID = themeType and ("dynamic:" .. themeType) or "dynamic:neutral"
    return copySpec(catalog[resolvedID]), resolvedID
end

local function setColor(target, method, color)
    local targetType = type(target)
    if (targetType == "table" or targetType == "userdata")
        and type(target[method]) == "function"
    then
        target[method](target, color[1], color[2], color[3], color[4])
    end
end

resetTexture = function(texture)
    if not texture then
        return
    end
    if type(texture.ClearAllPoints) == "function" then
        texture:ClearAllPoints()
    end
    if type(texture.SetTexture) == "function" then
        texture:SetTexture(nil)
    end
    if type(texture.SetTexCoord) == "function" then
        texture:SetTexCoord(0, 1, 0, 1)
    end
    if type(texture.SetAlpha) == "function" then
        texture:SetAlpha(0)
    end
    if type(texture.Hide) == "function" then
        texture:Hide()
    end
end

getLayer = function(frame, key, drawLayer, subLevel, owner)
    frame._spellCreationThemeLayers = frame._spellCreationThemeLayers or {}
    local layer = frame._spellCreationThemeLayers[key]
    local textureOwner = owner or frame
    if not layer and type(textureOwner.CreateTexture) == "function" then
        layer = textureOwner:CreateTexture(nil, drawLayer or "BACKGROUND", nil, subLevel)
        frame._spellCreationThemeLayers[key] = layer
    end
    return layer
end

local function applyColorLayer(texture, color, point, height)
    if not texture then
        return
    end
    resetTexture(texture)
    if not tonumber(color[4]) or color[4] <= 0 then
        return
    end
    if type(texture.SetColorTexture) ~= "function"
        or type(texture.SetPoint) ~= "function"
        or type(texture.SetHeight) ~= "function"
    then
        return
    end
    texture:SetColorTexture(color[1], color[2], color[3], color[4])
    texture:SetPoint(point, 1, point == "TOP" and -1 or 1)
    texture:SetPoint(point .. "LEFT", 1, point == "TOP" and -1 or 1)
    texture:SetPoint(point .. "RIGHT", -1, point == "TOP" and -1 or 1)
    texture:SetHeight(height)
    if type(texture.Show) == "function" then
        texture:Show()
    end
end

local function validImage(image)
    if type(image) ~= "table" then
        return false
    end
    local hasTexture = (type(image.texture) == "string" and image.texture ~= "")
        or (type(image.texture) == "number" and image.texture > 0)
    local hasAtlas = type(image.atlas) == "string" and image.atlas ~= ""
    return hasTexture or hasAtlas
end

local function layoutImage(frame, texture, image)
    if type(texture.ClearAllPoints) == "function" then texture:ClearAllPoints() end
    if type(texture.SetPoint) == "function" then
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    elseif type(texture.SetAllPoints) == "function" then
        texture:SetAllPoints(frame)
    end
    if type(texture.SetTexCoord) == "function" then
        local coords = type(image.texCoords) == "table" and image.texCoords
            or { 0, 1, 0, 1 }
        local left = tonumber(coords[1]) or 0
        local right = tonumber(coords[2]) or 1
        local top = tonumber(coords[3]) or 0
        local bottom = tonumber(coords[4]) or 1
        texture:SetTexCoord(left, right, top, bottom)

        local width = type(frame.GetWidth) == "function"
            and math.max(0, (tonumber(frame:GetWidth()) or 0) - 2) or 0
        local height = type(frame.GetHeight) == "function"
            and math.max(0, (tonumber(frame:GetHeight()) or 0) - 2) or 0
        local imageAspect = tonumber(image.aspectRatio) or 0
        if not image.stretch
            and type(frame.GetWidth) == "function"
            and type(frame.GetHeight) == "function"
            and width > 0 and height > 0 and imageAspect > 0
        then
            local frameAspect = width / height
            local sourceWidth = math.max(0.001, right - left)
            local sourceHeight = math.max(0.001, bottom - top)
            local sourceAspect = imageAspect * sourceWidth / sourceHeight
            if frameAspect < sourceAspect then
                local visibleWidth = sourceWidth * frameAspect / sourceAspect
                local cropLeft = left + ((sourceWidth - visibleWidth) / 2)
                texture:SetTexCoord(cropLeft, cropLeft + visibleWidth, top, bottom)
            elseif frameAspect > sourceAspect then
                local visibleHeight = sourceHeight * sourceAspect / frameAspect
                local cropTop = top + ((sourceHeight - visibleHeight) / 2)
                if image.focusY then
                    cropTop = math.max(top, math.min(bottom - visibleHeight,
                        image.focusY - visibleHeight * (image.anchorY or 0.5)))
                end
                texture:SetTexCoord(left, right, cropTop, cropTop + visibleHeight)
            end
        end
    end
end

local function refreshImageGeometry(frame)
    local image = frame._spellCreationThemeImage
    local texture = frame._spellCreationThemeLayers and frame._spellCreationThemeLayers.image
    if image and texture then layoutImage(frame, texture, image) end
end

local function applyImage(frame, image)
    local layers = frame._spellCreationThemeLayers
    local texture = layers and layers.image
    frame._spellCreationThemeImage = nil
    resetTexture(texture)
    if not validImage(image) then return false end
    texture = texture or getLayer(frame, "image", "BORDER", -8)
    if not texture then return false end

    local applied = false
    if type(image.atlas) == "string" and image.atlas ~= ""
        and type(texture.SetAtlas) == "function"
    then
        local success, result = pcall(texture.SetAtlas, texture, image.atlas, false)
        applied = success and result ~= false
    elseif ((type(image.texture) == "string" and image.texture ~= "")
            or (type(image.texture) == "number" and image.texture > 0))
        and type(texture.SetTexture) == "function"
    then
        local success, result = pcall(texture.SetTexture, texture, image.texture)
        applied = success and result ~= false
    end
    if not applied then
        resetTexture(texture)
        return false
    end
    layoutImage(frame, texture, image)
     
    if not image.stretch then
        frame._spellCreationThemeImage = image
        if not frame._spellCreationImageHooks and type(frame.HookScript) == "function" then
            frame._spellCreationImageHooks = true
            frame:HookScript("OnSizeChanged", refreshImageGeometry)
            frame:HookScript("OnShow", refreshImageGeometry)
        end
    end
    if type(texture.SetAlpha) == "function" then
        local alpha = tonumber(image.alpha) or 0.12
        texture:SetAlpha(math.max(0, math.min(1, alpha)))
    end
    if type(texture.Show) == "function" then
        texture:Show()
    end
    return true
end

local vignetteEdges = {
    {
        key = "vignetteLeft",
        orientation = "HORIZONTAL",
        points = {
            { "TOPLEFT", "TOPLEFT", 1, -1 },
            { "BOTTOMLEFT", "BOTTOMLEFT", 1, 1 },
        },
        sizeMethod = "SetWidth",
        reverse = false,
    },
    {
        key = "vignetteRight",
        orientation = "HORIZONTAL",
        points = {
            { "TOPRIGHT", "TOPRIGHT", -1, -1 },
            { "BOTTOMRIGHT", "BOTTOMRIGHT", -1, 1 },
        },
        sizeMethod = "SetWidth",
        reverse = true,
    },
    {
        key = "vignetteTop",
        orientation = "VERTICAL",
        points = {
            { "TOPLEFT", "TOPLEFT", 1, -1 },
            { "TOPRIGHT", "TOPRIGHT", -1, -1 },
        },
        sizeMethod = "SetHeight",
        reverse = true,
    },
    {
        key = "vignetteBottom",
        orientation = "VERTICAL",
        points = {
            { "BOTTOMLEFT", "BOTTOMLEFT", 1, 1 },
            { "BOTTOMRIGHT", "BOTTOMRIGHT", -1, 1 },
        },
        sizeMethod = "SetHeight",
        reverse = false,
    },
}

local function applyVignette(frame, vignette)
    local layers = frame._spellCreationThemeLayers
    local colorFactory = type(CreateColor) == "function" and CreateColor
        or (type(TRP3_API) == "table" and TRP3_API.CreateColor)
    local valid = type(vignette) == "table"
        and type(vignette.color) == "table"
        and type(colorFactory) == "function"

    for _, edge in ipairs(vignetteEdges) do
        local texture = layers and layers[edge.key]
        resetTexture(texture)
        if valid then
            texture = texture or getLayer(frame, edge.key, "BORDER", -6)
            local size = edge.sizeMethod == "SetWidth"
                and (tonumber(vignette.horizontalSize) or 32)
                or (tonumber(vignette.verticalSize) or 24)
            if texture
                and type(texture.SetColorTexture) == "function"
                and type(texture.SetGradient) == "function"
                and type(texture.SetPoint) == "function"
                and type(texture[edge.sizeMethod]) == "function"
            then
                local color = vignette.color
                local opaque = colorFactory(
                    color[1], color[2], color[3], tonumber(color[4]) or 0.72
                )
                local transparent = colorFactory(color[1], color[2], color[3], 0)
                texture:SetColorTexture(1, 1, 1, 1)
                local success = pcall(
                    texture.SetGradient,
                    texture,
                    edge.orientation,
                    edge.reverse and transparent or opaque,
                    edge.reverse and opaque or transparent
                )
                if success then
                    for _, point in ipairs(edge.points) do
                        texture:SetPoint(
                            point[1], frame, point[2], point[3], point[4]
                        )
                    end
                    texture[edge.sizeMethod](texture, size)
                    texture:Show()
                end
            end
        end
    end
end

local titanCorners = {
    { point = "TOPLEFT", x = 1, y = -1 },
    { point = "TOPRIGHT", x = -1, y = -1 },
    { point = "BOTTOMLEFT", x = 1, y = 1 },
    { point = "BOTTOMRIGHT", x = -1, y = 1 },
}

local function applyTitanGeometry(frame, enabled)
    frame._spellCreationTitanGeometry = enabled == true
    local layers = frame._spellCreationThemeLayers
    if not enabled and not layers then return end
    local width = type(frame.GetWidth) == "function" and frame:GetWidth() or 0
    local height = type(frame.GetHeight) == "function" and frame:GetHeight() or 0
     
    local span = math.min(36, math.max(0, math.min(width, height) / 2 - 16))
    local bronze, cyan = catalog.titan.border, catalog.titan.accent
    for index, corner in ipairs(titanCorners) do
        for part = 1, 4 do
            local key = "titanCorner" .. index .. "Part" .. part
            local texture = layers and layers[key]
            resetTexture(texture)
            if enabled and span >= 12 then
                texture = texture or getLayer(frame, key, "BORDER", -5)
                local metal, horizontal = part <= 2, part % 2 == 1
                local color = metal and bronze or cyan
                local inset, thickness = metal and 10 or 16, metal and 2 or 1
                local length = metal and span or span * 0.45
                animationCall(texture, "SetColorTexture", color[1], color[2], color[3], metal and 0.70 or 0.48)
                animationCall(texture, "SetPoint", corner.point, frame, corner.point,
                    corner.x * inset, corner.y * inset)
                animationCall(texture, "SetSize", horizontal and length or thickness,
                    horizontal and thickness or length)
                animationCall(texture, "Show")
            end
        end
    end
    if enabled and not frame._spellCreationTitanHooks and type(frame.HookScript) == "function" then
        frame._spellCreationTitanHooks = true
        local function refreshGeometry(changedFrame)
            if changedFrame._spellCreationTitanGeometry then applyTitanGeometry(changedFrame, true) end
        end
        frame:HookScript("OnSizeChanged", refreshGeometry)
        frame:HookScript("OnShow", refreshGeometry)
    end
end

local function applyResolved(frame, resolvedSpec, resolvedID, animationToken)
    local frameType = type(frame)
    if frameType ~= "table" and frameType ~= "userdata" then
        return resolvedSpec, resolvedID
    end

    if type(frame.SetBackdrop) == "function" then
        frame:SetBackdrop(BACKDROP)
    end
    setColor(frame, "SetBackdropColor", resolvedSpec.background)
    setColor(frame, "SetBackdropBorderColor", resolvedSpec.border)

    setColor(frame.title, "SetTextColor", resolvedSpec.accent)
    if type(frame.themeLabels) == "table" then
        for _, label in ipairs(frame.themeLabels) do
            setColor(label, "SetTextColor", resolvedSpec.textMuted)
        end
    end
    local fancy = resolvedSpec.fancy == true
    local factory = addon.UIFactory
    if factory and type(factory.ApplyBookFont) == "function" then
        factory.ApplyBookFont(frame.title, fancy, 2)
        for _, region in ipairs(frame.themeLabels or {}) do
            factory.ApplyBookFont(region, false, 0)
        end
        for _, region in ipairs(frame.themeText or {}) do
            factory.ApplyBookFont(region, false, 0)
        end
    end
    if factory and type(factory.ApplyBookFieldStyle) == "function" then
        for _, field in ipairs(frame.themeFields or {}) do
            factory.ApplyBookFieldStyle(field, fancy)
        end
    end
    if factory and type(factory.ApplyButtonStyle) == "function" then
        for _, button in ipairs(frame.themeButtons or {}) do
            factory.ApplyButtonStyle(
                button,
                fancy and "book" or "modern",
                fancy and nil or false
            )
            local fontString = type(button.GetFontString) == "function"
                and button:GetFontString() or nil
            if type(factory.ApplyBookFont) == "function" then
                factory.ApplyBookFont(fontString, false, 0)
            end
        end
    end

    local topColor = copyColor(resolvedSpec.accent)
    topColor[4] = resolvedSpec.topAccentAlpha or 0
    local bottomColor = copyColor(resolvedSpec.background)
    bottomColor[1], bottomColor[2], bottomColor[3], bottomColor[4] =
        0, 0, 0, resolvedSpec.bottomShadeAlpha or 0
    applyColorLayer(getLayer(frame, "top", "BORDER", -7), topColor, "TOP", 30)
    applyColorLayer(getLayer(frame, "bottom", "BORDER", -7), bottomColor, "BOTTOM", 22)
    local imageApplied = applyImage(frame, resolvedSpec.backgroundImage)
    applyVignette(frame, resolvedSpec.vignette)
    applyFancyEffects(
        frame,
        fancy and imageApplied == true,
        animationToken
    )
    applyTitanGeometry(frame, resolvedSpec.titanGeometry)

    frame._spellCreationThemeID = resolvedID
    return resolvedSpec, resolvedID
end

function themes.Apply(frame, selectedTheme, kind, magicType, damageType)
    local resolvedSpec, resolvedID = themes.Resolve(
        selectedTheme, kind, magicType, damageType
    )
    return applyResolved(frame, resolvedSpec, resolvedID)
end

function themes.GetTabThemeOptions()
    local options = {}
    for index, option in ipairs(tabThemeOptions) do
        local label = addon.L(option.labelKey)
        if option.value:match("^dynamic:") then
            label = addon.L("TAB_THEME_FORMAT", label)
        end
        options[index] = { value = option.value, label = label }
    end
    return options
end

function themes.ClearBook(frame)
    local frameType = type(frame)
    if frameType ~= "table" and frameType ~= "userdata" then
        return false
    end
    frame._spellCreationThemeImage = nil
    if type(frame.SetBackdrop) == "function" then
        frame:SetBackdrop(BACKDROP)
    end
    setColor(frame, "SetBackdropColor", rgba(0, 0, 0, 0))
    setColor(frame, "SetBackdropBorderColor", rgba(0, 0, 0, 0))
    local layers = frame._spellCreationThemeLayers
    if layers then
        for _, key in ipairs({
            "top", "bottom", "image",
            "vignetteLeft", "vignetteRight", "vignetteTop", "vignetteBottom",
        }) do
            resetTexture(layers[key])
        end
    end
    applyFancyEffects(frame, false)
    applyTitanGeometry(frame, false)
    animationCall(frame, "SetAlpha", 1)
    frame._spellCreationThemeID = nil
    return true
end

function themes.ApplyBook(frame, selectedTheme, animationToken)
    local resolvedSpec, resolvedID
    if selectedTheme ~= nil and selectedTheme ~= "default" then
        resolvedSpec, resolvedID = themes.Resolve(selectedTheme)
    end
    if resolvedID == nil or resolvedID == "default" then
        local uiTheme = addon.Theme
        resolvedSpec = spec(
            copyColor(uiTheme.Colors.parchment),
            copyColor(uiTheme.Colors.border),
            copyColor(uiTheme.Colors.gold),
            copyColor(uiTheme.Colors.text),
            copyColor(uiTheme.Colors.textMuted),
            false
        )
        resolvedID = "default"
        resolvedSpec.slotBorder = copyColor(uiTheme.Colors.gridSlotBorder)
        resolvedSpec.slotBackground = copyColor(uiTheme.Colors.gridSlot)
    elseif resolvedID == "fancy" then
        resolvedSpec.slotBorder = rgba(0, 0, 0, 0)
        resolvedSpec.slotBackground = rgba(0, 0, 0, 0)
        resolvedSpec.border[4] = 0
        resolvedSpec.topAccentAlpha = 0
        resolvedSpec.bottomShadeAlpha = 0
        resolvedSpec.vignette = nil
        resolvedSpec.maxColumns = 2
    else
        local uiTheme = addon.Theme
        resolvedSpec.slotBorder = copyColor(resolvedSpec.border)
        resolvedSpec.slotBorder[4] = 0.30
        resolvedSpec.slotBackground = copyColor(resolvedSpec.accent)
        resolvedSpec.slotBackground[4] = 0.045
        resolvedSpec.border = copyColor(uiTheme.Colors.border)
        resolvedSpec.border[4] = 0.58
        resolvedSpec.topAccentAlpha = 0
        resolvedSpec.bottomShadeAlpha = 0
        if resolvedSpec.backgroundImage then
             
             
            resolvedSpec.backgroundImage.alpha = 0.34
            resolvedSpec.backgroundImage.texCoords = { 0, 1, 0, 0.64 }
            resolvedSpec.backgroundImage.focusY = 0.32
            resolvedSpec.backgroundImage.anchorY = 0.55
        end
        resolvedSpec.vignette = {
            color = {
                uiTheme.Colors.dark[1],
                uiTheme.Colors.dark[2],
                uiTheme.Colors.dark[3],
                0.82,
            },
            horizontalSize = 38,
            verticalSize = 28,
        }
    end
    return applyResolved(frame, resolvedSpec, resolvedID, animationToken)
end
