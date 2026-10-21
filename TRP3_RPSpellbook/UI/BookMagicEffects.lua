local _, addon = ...

local effects = {}
addon.BookMagicEffects = effects

local function profile(family, ink, glow, writing)
    return { family = family, ink = ink, glow = glow, writing = writing }
end

local profiles = {
    arcane = profile("arcane", { 0.48, 0.16, 0.80 }, { 0.38, 0.66, 1 }, "center"),
    light = profile("light", { 0.68, 0.39, 0.09 }, { 1, 0.88, 0.52 }, "center"),
    nature = profile("nature", { 0.15, 0.42, 0.08 }, { 0.49, 0.78, 0.24 }, "vine"),
    elemental = profile("elemental", { 0.15, 0.40, 0.58 }, { 0.38, 0.78, 1 }, "ripple"),
    shadow = profile("shadow", { 0.16, 0.06, 0.25 }, { 0.54, 0.29, 0.74 }, "reverse"),
    demonic = profile("demonic", { 0.13, 0.25, 0.035 }, { 0.48, 0.79, 0.12 }, "brand"),
    necromancy = profile("necromancy", { 0.09, 0.22, 0.19 }, { 0.43, 0.69, 0.60 }, "rise"),
    chi = profile("chi", { 0.08, 0.39, 0.32 }, { 0.37, 0.83, 0.68 }, "breath"),
}

 
local parents = {
    runes = "arcane", technomancy = "arcane", blood = "necromancy",
    chronomancy = "arcane", domination = "shadow", drust = "nature",
    hex = "demonic", moonlight = "light", resonance = "chi",
    shadowflame = "demonic", solar = "light", voodoo = "necromancy", anti_magic = "shadow",
}

local function resolveKey(key)
    return profiles[key] or profiles[parents[key]], key
end

function effects.Resolve(value)
    if type(value) ~= "string" then return end
    local _, id = addon.SpellCreationThemes.Resolve("dynamic", "magic", value)
    local key = id and id:match("^dynamic:(.+)$")
    if profiles[key] or parents[key] then return resolveKey(key) end
    key = value:lower():match("^%s*(.-)%s*$")
    if profiles[key] or parents[key] then return resolveKey(key) end
    local presets = addon.SpellCreationPresets
    for _, option in ipairs(presets and presets.GetMagicSubtypes and presets.GetMagicSubtypes() or {}) do
        if option.label:lower() == key then return resolveKey(option.value) end
    end
end

local elements = {
    { 0.94, 0.39, 0.07 }, { 0.28, 0.68, 0.94 }, { 0.57, 0.79, 0.76 }, { 0.50, 0.34, 0.14 },
}

 
 
function effects.Sample(spec, progress, lane, creation)
    local p = math.max(0, math.min(1, progress))
    local envelope = math.sin(p * math.pi) ^ 2
    local mix, pulse = 0.70, 1
    local light = spec.glow
    if spec.family == "arcane" then
        mix = 0.5 + 0.4 * math.sin(p * math.pi * 2 + lane * 0.7)
    elseif spec.family == "demonic" then
        mix, pulse = 0.64, 0.65 + 0.35 * math.sin(p * math.pi * 3 + lane) ^ 2
    elseif spec.family == "shadow" then
        mix = 0.20 + 0.50 * p
    elseif spec.family == "necromancy" then
        mix, pulse = 0.18 + 0.70 * p, 0.72 + 0.28 * math.sin(p * math.pi) ^ 2
    elseif spec.family == "nature" then
        mix = 0.35 + 0.45 * p
    elseif spec.family == "elemental" then
        light, mix = elements[(lane - 1) % 4 + 1], 0.90
    elseif spec.family == "chi" then
        pulse = 0.6 + 0.4 * math.cos(p * math.pi * 2) ^ 2
    end
    local ink = spec.ink
    return ink[1] + (light[1] - ink[1]) * mix,
        ink[2] + (light[2] - ink[2]) * mix,
        ink[3] + (light[3] - ink[3]) * mix,
        envelope * pulse * (creation and 0.96 or 0.78)
end

function effects.WritingDelay(spec, column, regionIndex)
    local position = (column - 1) / 7
    if spec.writing == "center" then position = math.abs(position - 0.5) * 2
    elseif spec.writing == "reverse" then position = 1 - position
    elseif spec.writing == "rise" then position = 1 - position * 0.4
    elseif spec.writing == "brand" then position = math.floor(position * 3) / 3
    elseif spec.writing == "ripple" then position = math.sin(position * math.pi) end
    return position * 0.36 + (regionIndex - 1) * 0.10
end

 
function effects.Reveal(spec, progress)
    local p = math.max(0, math.min(1, progress))
    if spec.writing == "brand" then
        p = p - math.sin(p * math.pi * 6) * 0.025
    elseif spec.writing == "breath" then
        p = p - math.sin(p * math.pi * 2) * 0.07
    end
    if spec.writing == "center" then return (1 - p) / 2, p end
    if spec.writing == "reverse" then return 1 - p, p end
    return 0, p
end
