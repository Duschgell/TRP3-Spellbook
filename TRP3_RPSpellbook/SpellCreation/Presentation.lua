local _, addon = ...

addon.SpellPresentation = {}

local constants = addon.Constants

local debuffColors = {
    ["fluch"] = "9600FF", ["curse"] = "9600FF",
    ["krankheit"] = "966400", ["disease"] = "966400",
    ["magisch"] = "3296FF", ["magic"] = "3296FF",
    ["gift"] = "009600", ["poison"] = "009600",
    ["blutung"] = "C80000", ["bleed"] = "C80000",
}

local buffColors = {
    ["arkan"] = { "E650F5" }, ["arcane"] = { "E650F5" },
    ["licht"] = { "FAE68C" }, ["light"] = { "FAE68C" },
    ["natur"] = { "2DD205" }, ["nature"] = { "2DD205" },
    ["elementar"] = { "3764A0", "E68732", "82AA64" },
    ["elemental"] = { "3764A0", "E68732", "82AA64" },
    ["schatten"] = { "5F32AF" }, ["shadow"] = { "5F32AF" },
    ["dämonisch"] = { "234B00" }, ["demonic"] = { "234B00" },
    ["chi"] = { "73F07D" },
    ["nekromantie"] = { "372328" }, ["necromancy"] = { "372328" },
    ["runen"] = { "61002B" }, ["runes"] = { "61002B" },
    ["blut"] = { "B41419" }, ["blood"] = { "B41419" },
    ["chronomantie"] = { "A57828" }, ["chronomancy"] = { "A57828" },
    ["herrschaft"] = { "00BEC8" }, ["domination"] = { "00BEC8" },
    ["drust"] = { "0A2D32" }, ["hex"] = { "645032" },
    ["mondlicht"] = { "D7DCCD" }, ["moonlight"] = { "D7DCCD" },
    ["schall"] = { "5A5F96" }, ["resonance"] = { "5A5F96" },
    ["schattenflamme"] = { "D73C41" }, ["shadowflame"] = { "D73C41" },
    ["solar"] = { "EBDC73" }, ["voodoo"] = { "B4738C" },
    ["anti-magisch"] = { "191919" }, ["anti-magic"] = { "191919" },
}

local function hasText(value)
    return type(value) == "string" and value ~= ""
end

local function trimmed(value)
    value = hasText(value) and addon.Runtime.Trim(value) or nil
    return value ~= "" and value or nil
end

local function normalized(value)
    value = trimmed(value)
    return value and string.lower(value) or nil
end

local function getBuffType(spell)
    local tags = type(spell) == "table" and spell.tags or nil
    if type(tags) ~= "table" then return nil end
    local magicType = trimmed(tags[constants.MAGIC_TAG_TYPE] or tags.Magieart)
    if magicType then return magicType end
    return trimmed(tags[constants.MAGIC_TAG_SCHOOL] or tags.Magieschule)
end

function addon.SpellPresentation.GetEffectPresentation(spell)
    local effects = type(spell) == "table" and spell.effects or nil
    if type(effects) ~= "table" then return nil end
    local duration = effects.durationRounds == 0 and constants.EFFECT_DURATION_INFINITY or effects.duration
    if effects.debuff == true then
        local label = trimmed(effects.debuffType) or "Debuff"
        local color = debuffColors[normalized(label)]
        return {
            kind = "debuff", label = label,
            colors = color and { color } or {},
            thickness = 2, duration = duration,
        }
    end
    if effects.buff == true then
        local label = getBuffType(spell) or addon.L("EFFECT_BUFF")
        return {
            kind = "buff", label = label,
            colors = buffColors[normalized(label)] or {},
            thickness = 1, duration = duration,
        }
    end
    return nil
end

function addon.SpellPresentation.GetEffectTooltipText(spell)
    local presentation = addon.SpellPresentation.GetEffectPresentation(spell)
    if not presentation then return nil end
    local duration = trimmed(presentation.duration)
    if not duration then return nil end
    local label = addon.L("FIELD_DURATION")
    if presentation.colors[1] then
        label = "|cff" .. presentation.colors[1] .. label .. "|r"
    end
    return label .. ": " .. duration
end

function addon.SpellPresentation.GetMagicTextColor(spell)
    local school = getBuffType(spell)
    local themes = addon.SpellCreationThemes
    if not school or not themes or not themes.Resolve then return nil end
    local magic = addon.BookMagicEffects
    local profile = magic and magic.Resolve and magic.Resolve(school)
    if profile then school = profile.family end
    local spec, id = themes.Resolve("dynamic", "magic", school)
    if not id or id == "dynamic:neutral" then return nil end
    local tint = spec.accent
     
    return { tint[1] * 0.8 + 0.2, tint[2] * 0.8 + 0.2, tint[3] * 0.8 + 0.2 }
end

function addon.SpellPresentation.GetKind(tags)
    tags = type(tags) == "table" and tags or {}
    local explicit = tags[constants.SPELL_TAG_KIND]
    if explicit == constants.SPELL_KIND_MAGIC
        or explicit == constants.SPELL_KIND_ABILITY
    then
        return explicit
    end
    if tags[constants.MAGIC_TAG_ENABLED] == "true"
        or tags.Magisch == "Ja"
        or tags.Magisch == "true"
    then
        return constants.SPELL_KIND_MAGIC
    end
    return constants.SPELL_KIND_ABILITY
end

function addon.SpellPresentation.GetClassificationSummary(tags, effects)
    tags = type(tags) == "table" and tags or {}
    local parts = {}
    if addon.SpellPresentation.GetKind(tags) == constants.SPELL_KIND_MAGIC then
        local magicType = tags[constants.MAGIC_TAG_TYPE] or tags.Magieart
        local magicSchool = tags[constants.MAGIC_TAG_SCHOOL] or tags.Magieschule
        if hasText(magicType) then
            parts[#parts + 1] = magicType
        end
        if hasText(magicSchool) then
            parts[#parts + 1] = magicSchool
        end
    else
        local damageType = tags[constants.SPELL_TAG_DAMAGE_TYPE]
        if hasText(damageType) then
            parts[#parts + 1] = damageType
        end
    end
    effects = type(effects) == "table" and effects or {}
    if effects.buff == true then
        parts[#parts + 1] = addon.L("EFFECT_BUFF")
    end
    if effects.debuff == true then
        parts[#parts + 1] = trimmed(effects.debuffType) or addon.L("EFFECT_DEBUFF")
    end
    if effects.healing == true then
        parts[#parts + 1] = addon.L("EFFECT_HEALING")
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

function addon.SpellPresentation.IsInternalTag(key)
    return key == constants.MAGIC_TAG_ENABLED
        or key == constants.MAGIC_TAG_TYPE
        or key == constants.MAGIC_TAG_SCHOOL
        or key == constants.SPELL_TAG_KIND
        or key == constants.SPELL_TAG_DAMAGE_TYPE
        or key == constants.SPELL_TAG_CAST_ROUNDS
        or key == "Magisch"
        or key == "Magieart"
        or key == "Magieschule"
end

function addon.SpellPresentation.IsRedundantClassificationTag(key, value, tags)
    key, value = normalized(key), normalized(value)
    if not key or key ~= value or type(tags) ~= "table" then return false end
     
     
    if addon.SpellPresentation.GetKind(tags) == constants.SPELL_KIND_MAGIC then
        return value == normalized(tags[constants.MAGIC_TAG_TYPE] or tags.Magieart)
            or value == normalized(tags[constants.MAGIC_TAG_SCHOOL] or tags.Magieschule)
    end
    return value == normalized(tags[constants.SPELL_TAG_DAMAGE_TYPE])
end

function addon.SpellPresentation.ShouldShowCooldown(value)
    return hasText(value)
        and not addon.SpellCreationPresets.IsNoCooldown(value)
end

function addon.SpellPresentation.GetTooltipTiming(spell)
    if type(spell) ~= "table" then return nil, nil end
    local castTime = trimmed(spell.castTime)
    local cooldown = trimmed(spell.cooldown)
    if not addon.SpellPresentation.ShouldShowCooldown(cooldown) then cooldown = nil end
    return castTime and (addon.L("FIELD_CAST_TIME") .. ": " .. castTime) or nil,
        cooldown and (addon.L("FIELD_COOLDOWN") .. ": " .. cooldown) or nil
end

function addon.SpellPresentation.IsBuff(spell)
    return type(spell) == "table"
        and type(spell.effects) == "table"
        and spell.effects.buff == true
end

function addon.SpellPresentation.IsHealing(spell)
    return type(spell) == "table"
        and type(spell.effects) == "table"
        and spell.effects.healing == true
end

function addon.SpellPresentation.IsDebuff(spell)
    return type(spell) == "table"
        and type(spell.effects) == "table"
        and spell.effects.debuff == true
end

function addon.SpellPresentation.GetBuffDuration(spell)
    return addon.SpellPresentation.IsBuff(spell)
        and spell.effects.duration
        or nil
end

function addon.SpellPresentation.GetEffectDuration(spell)
    local presentation = addon.SpellPresentation.GetEffectPresentation(spell)
    return presentation and presentation.duration or nil
end

function addon.SpellPresentation.ParseEffectDuration(value)
    local text = addon.Runtime.Trim(value)
    if not text or text == "" then
        return nil, nil
    end
    if text == constants.EFFECT_DURATION_INFINITY or text:lower() == "permanent" then
        return constants.EFFECT_DURATION_PERMANENT, nil
    end

    for _, timeMode in ipairs({ "rounds", "time" }) do
        local options = addon.SpellCreationPresets.GetDurations(timeMode)
        local selected = addon.SpellCreationPresets.MatchTimeSelection(
            options,
            text,
            timeMode,
            "cooldown"
        )
        if selected.permanent then return constants.EFFECT_DURATION_PERMANENT, nil end
        local maximum = addon.SpellCreationPresets.GetSelectionMaximum(
            options,
            selected
        )
        if maximum then
            if timeMode == "rounds" then
                return math.floor(maximum), nil
            end
            return nil, math.floor(maximum)
        end
    end

    local normalized = string.lower(text)
    local rangeStart, rangeEnd, rangeUnit = normalized:match(
        "^(%d+)%s*%-%s*(%d+)%s+([^%s]+)$"
    )
    local roundUnits = {
        ["runde"] = true,
        ["runden"] = true,
        ["round"] = true,
        ["rounds"] = true,
        ["tour"] = true,
        ["tours"] = true,
    }
    if rangeStart and rangeEnd and roundUnits[rangeUnit] then
        local maximum = math.max(tonumber(rangeStart), tonumber(rangeEnd))
        return maximum > 0 and maximum or nil, nil
    end
    local rounds = normalized:match("^(%d+)%s+runde$")
        or normalized:match("^(%d+)%s+runden$")
        or normalized:match("^(%d+)%s+round$")
        or normalized:match("^(%d+)%s+rounds$")
        or normalized:match("^(%d+)%s+tour$")
        or normalized:match("^(%d+)%s+tours$")
    if rounds then
        rounds = tonumber(rounds)
        return rounds and rounds > 0 and math.floor(rounds) or nil, nil
    end
    local function parseSeconds(segment)
        segment = addon.Runtime.Trim(segment)
        if not segment then
            return nil
        end
        local amount, unit = segment:match("^(%d+[.,]?%d*)%s+(.+)$")
        amount = amount and tonumber((amount:gsub(",", ".")))
        unit = unit and string.lower(unit) or nil
        local multipliers = {
            ["sekunde"] = 1,
            ["sekunden"] = 1,
            ["second"] = 1,
            ["seconds"] = 1,
            ["seconde"] = 1,
            ["secondes"] = 1,
            ["minute"] = 60,
            ["minuten"] = 60,
            ["minutes"] = 60,
            ["stunde"] = 3600,
            ["stunden"] = 3600,
            ["hour"] = 3600,
            ["hours"] = 3600,
            ["heure"] = 3600,
            ["heures"] = 3600,
            ["tag"] = 86400,
            ["tage"] = 86400,
            ["day"] = 86400,
            ["days"] = 86400,
            ["jour"] = 86400,
            ["jours"] = 86400,
        }
        local multiplier = unit and multipliers[unit]
        return amount and multiplier and amount * multiplier or nil
    end
    local first, second = normalized:match("^(.-)%s+%-%s+(.-)$")
    local durationSeconds
    if second then
        local firstSeconds = parseSeconds(first)
        local secondSeconds = parseSeconds(second)
        durationSeconds = firstSeconds and secondSeconds
            and math.max(firstSeconds, secondSeconds)
            or nil
    else
        durationSeconds = parseSeconds(normalized)
    end
    if durationSeconds and durationSeconds > 0 then
        return nil, durationSeconds
    end
    return nil, nil
end

function addon.SpellPresentation.GetCastRounds(spell)
    local tags = type(spell) == "table" and spell.tags or nil
    local tagged = tags and tonumber(tags[constants.SPELL_TAG_CAST_ROUNDS])
    if tagged
        and tagged >= 0
        and tagged <= 100
        and tagged == math.floor(tagged)
    then
        return tagged
    end
    local value = type(spell) == "table" and spell.castTime or nil
    if type(value) ~= "string" then
        return nil
    end
    local normalized = addon.Runtime.Trim(value)
    local presets = addon.SpellCreationPresets
    if presets and type(presets.GetCastTimes) == "function" then
        local options = presets.GetCastTimes("rounds")
        local selected = presets.MatchTimeSelection(options, normalized, "rounds", "cast")
        local maximum = presets.GetSelectionMaximum(options, selected)
        if maximum then return maximum end
    end
    local localized = {
        ["0 Runden"] = 0,
        ["1 Runde"] = 1,
        ["2 Runden"] = 2,
        ["3 Runden"] = 3,
        ["0 rounds"] = 0,
        ["1 round"] = 1,
        ["2 rounds"] = 2,
        ["3 rounds"] = 3,
        ["0 tour"] = 0,
        ["1 tour"] = 1,
        ["2 tours"] = 2,
        ["3 tours"] = 3,
    }
    return localized[normalized]
end
