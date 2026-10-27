local _, addon = ...

addon.SpellCreationPresets = {}

local function option(value, labelKey, extra)
    local result = {
        value = value,
        labelKey = labelKey,
    }
    if type(extra) == "table" then
        for key, item in pairs(extra) do
            result[key] = item
        end
    end
    return result
end

local resources = {
    magic = {
        option("mana", "PRESET_RESOURCE_MANA", { allowsAmount = true }),
        option("arcane_charges", "PRESET_RESOURCE_ARCANE_CHARGES", { allowsAmount = true }),
        option("holy_power", "PRESET_RESOURCE_HOLY_POWER", { allowsAmount = true }),
        option("maelstrom", "PRESET_RESOURCE_MAELSTROM", { allowsAmount = true }),
        option("runic_power", "PRESET_RESOURCE_RUNIC_POWER", { allowsAmount = true }),
        option("soul_shards", "PRESET_RESOURCE_SOUL_SHARDS", { allowsAmount = true }),
        option("essence", "PRESET_RESOURCE_ESSENCE", {
            children = {
                option("essence", "PRESET_RESOURCE_ESSENCE", { allowsAmount = true, pluralKey = "PRESET_RESOURCE_ESSENCE_PLURAL" }),
                option("red_essence", "PRESET_RESOURCE_ESSENCE_RED", { allowsAmount = true, pluralKey = "PRESET_RESOURCE_ESSENCE_RED_PLURAL", color = "ff0000" }),
                option("blue_essence", "PRESET_RESOURCE_ESSENCE_BLUE", { allowsAmount = true, pluralKey = "PRESET_RESOURCE_ESSENCE_BLUE_PLURAL", color = "0070dd" }),
                option("black_essence", "PRESET_RESOURCE_ESSENCE_BLACK", { allowsAmount = true, pluralKey = "PRESET_RESOURCE_ESSENCE_BLACK_PLURAL", color = "4f2e00" }),
                option("bronze_essence", "PRESET_RESOURCE_ESSENCE_BRONZE", { allowsAmount = true, pluralKey = "PRESET_RESOURCE_ESSENCE_BRONZE_PLURAL", color = "ff9300" }),
                option("green_essence", "PRESET_RESOURCE_ESSENCE_GREEN", { allowsAmount = true, pluralKey = "PRESET_RESOURCE_ESSENCE_GREEN_PLURAL", color = "00ff00" }),
            },
        }),
        option("reagents", "PRESET_RESOURCE_REAGENTS", { allowsAmount = false }),
    },
    ability = {
        option("stamina", "PRESET_RESOURCE_STAMINA", { allowsAmount = true }),
        option("rage", "PRESET_RESOURCE_RAGE", { allowsAmount = true }),
        option("focus", "PRESET_RESOURCE_FOCUS", { allowsAmount = true }),
        option("energy", "PRESET_RESOURCE_ENERGY", { allowsAmount = true }),
        option("ammunition", "PRESET_RESOURCE_AMMUNITION", { allowsAmount = true }),
    },
}

local ranges = {
    option("melee", "PRESET_RANGE_MELEE"),
    option("10", "PRESET_RANGE_10"),
    option("20", "PRESET_RANGE_20"),
    option("40", "PRESET_RANGE_40"),
    option("100", "PRESET_RANGE_100"),
    option("unlimited", "PRESET_RANGE_UNLIMITED"),
}

local castTimes = {
    rounds = {
        option("instant", "PRESET_CAST_INSTANT", { exclusive = true }),
        option("0", "PRESET_CAST_ROUND_0", { order = 0, rangeValueKey = "PRESET_VALUE_0" }),
        option("1", "PRESET_CAST_ROUND_1", { order = 1, rangeValueKey = "PRESET_VALUE_1" }),
        option("2", "PRESET_CAST_ROUND_2", { order = 2, rangeValueKey = "PRESET_VALUE_2" }),
        option("3", "PRESET_CAST_ROUND_3", { order = 3, rangeValueKey = "PRESET_VALUE_3" }),
    },
    time = {
        option("instant", "PRESET_CAST_INSTANT", { exclusive = true }),
        option("0.5", "PRESET_CAST_SECOND_HALF", { order = 0.5, rangeValueKey = "PRESET_VALUE_HALF" }),
        option("1", "PRESET_CAST_SECOND_1", { order = 1, rangeValueKey = "PRESET_VALUE_1" }),
        option("1.5", "PRESET_CAST_SECOND_ONE_HALF", { order = 1.5, rangeValueKey = "PRESET_VALUE_ONE_HALF" }),
        option("2", "PRESET_CAST_SECOND_2", { order = 2, rangeValueKey = "PRESET_VALUE_2" }),
        option("3", "PRESET_CAST_SECOND_3", { order = 3, rangeValueKey = "PRESET_VALUE_3" }),
        option("5", "PRESET_CAST_SECOND_5", { order = 5, rangeValueKey = "PRESET_VALUE_5" }),
        option("10", "PRESET_CAST_SECOND_10", { order = 10, rangeValueKey = "PRESET_VALUE_10" }),
    },
}

local cooldowns = {
    rounds = {
        option("none", "PRESET_COOLDOWN_NONE", { exclusive = true }),
        option("1", "PRESET_COOLDOWN_ROUND_1", { order = 1, rangeValueKey = "PRESET_VALUE_1" }),
        option("2", "PRESET_COOLDOWN_ROUND_2", { order = 2, rangeValueKey = "PRESET_VALUE_2" }),
        option("3", "PRESET_COOLDOWN_ROUND_3", { order = 3, rangeValueKey = "PRESET_VALUE_3" }),
        option("4", "PRESET_COOLDOWN_ROUND_4", { order = 4, rangeValueKey = "PRESET_VALUE_4" }),
    },
    time = {
        option("none", "PRESET_COOLDOWN_NONE", { exclusive = true }),
        option("30s", "PRESET_COOLDOWN_SECOND_30", { order = 30 }),
        option("1m", "PRESET_COOLDOWN_MINUTE_1", { order = 60 }),
        option("2m", "PRESET_COOLDOWN_MINUTE_2", { order = 120 }),
        option("3m", "PRESET_COOLDOWN_MINUTE_3", { order = 180 }),
        option("10m", "PRESET_COOLDOWN_MINUTE_10", { order = 600 }),
        option("1h", "PRESET_COOLDOWN_HOUR_1", { order = 3600 }),
        option("1d", "PRESET_COOLDOWN_DAY_1", { order = 86400 }),
    },
}

local magicTypes = {
    option("arcane", "PRESET_MAGIC_ARCANE"),
    option("light", "PRESET_MAGIC_LIGHT"),
    option("nature", "PRESET_MAGIC_NATURE"),
    option("elemental", "PRESET_MAGIC_ELEMENTAL"),
    option("shadow", "PRESET_MAGIC_SHADOW"),
    option("demonic", "PRESET_MAGIC_DEMONIC"),
    option("chi", "PRESET_MAGIC_CHI"),
    option("necromancy", "PRESET_MAGIC_NECROMANCY"),
}

local magicSubtypes = {
    option("runes", "PRESET_MAGIC_RUNES"),
    option("prismatic", "PRESET_MAGIC_PRISMATIC"),
    option("technomancy", "PRESET_MAGIC_TECHNOMANCY"),
    option("blood", "PRESET_MAGIC_BLOOD"),
    option("chronomancy", "PRESET_MAGIC_CHRONOMANCY"),
    option("domination", "PRESET_MAGIC_DOMINATION"),
    option("drust", "PRESET_MAGIC_DRUST"),
    option("hex", "PRESET_MAGIC_HEX"),
    option("moonlight", "PRESET_MAGIC_MOONLIGHT"),
    option("resonance", "PRESET_MAGIC_RESONANCE"),
    option("shadowflame", "PRESET_MAGIC_SHADOWFLAME"),
    option("solar", "PRESET_MAGIC_SOLAR"),
    option("voodoo", "PRESET_MAGIC_VOODOO"),
    option("anti_magic", "PRESET_MAGIC_ANTI_MAGIC"),
}

local magicSchools = {
    option("evocation", "PRESET_SCHOOL_EVOCATION"),
    option("abjuration", "PRESET_SCHOOL_ABJURATION"),
    option("divination", "PRESET_SCHOOL_DIVINATION"),
    option("illusion", "PRESET_SCHOOL_ILLUSION"),
    option("conjuration", "PRESET_SCHOOL_CONJURATION"),
    option("transmutation", "PRESET_SCHOOL_TRANSMUTATION"),
    option("enchantment", "PRESET_SCHOOL_ENCHANTMENT"),
}

local damageTypes = {
    option("physical", "PRESET_DAMAGE_PHYSICAL"),
    option("shot", "PRESET_DAMAGE_SHOT"),
    option("poison", "PRESET_DAMAGE_POISON"),
    option("explosion", "PRESET_DAMAGE_EXPLOSION"),
    option("bleed", "PRESET_DAMAGE_BLEED"),
    option("stun", "PRESET_DAMAGE_STUN"),
}

local debuffTypes = {
    option("curse", "PRESET_DEBUFF_CURSE"),
    option("disease", "PRESET_DEBUFF_DISEASE"),
    option("magic", "PRESET_DEBUFF_MAGIC"),
    option("poison", "PRESET_DEBUFF_POISON"),
    option("bleed", "PRESET_DEBUFF_BLEED"),
}

local function localeText(locale, key, ...)
    if not locale then return addon.L(key, ...) end
    local translations = addon.Localization.translations
    local text = (translations[locale] or {})[key]
        or (translations.enUS or {})[key]
    if not text then return nil end
    return select("#", ...) > 0 and string.format(text, ...) or text
end

local function localize(options, locale)
    local localized = {}
    for index, item in ipairs(options or {}) do
        localized[index] = {
            allowsAmount = item.allowsAmount,
            children = item.children and localize(item.children, locale) or nil,
            color = item.color,
            plural = item.pluralKey and localeText(locale, item.pluralKey) or nil,
            exclusive = item.exclusive,
            label = localeText(locale, item.labelKey),
            order = item.order,
            rangeValue = item.rangeValueKey and localeText(locale, item.rangeValueKey) or nil,
            value = item.value,
        }
    end
    return localized
end

function addon.SpellCreationPresets.GetResources(kind)
    local result = localize(resources[kind] or resources.magic)
    for _, text in ipairs(addon.SpellCreationPresets.GetCustomPresets("resource")) do
        result[#result + 1] = {
            value = text, label = text, allowsAmount = true, custom = true,
        }
    end
    return result
end

function addon.SpellCreationPresets.FormatResource(resource, amount)
    for _, group in ipairs(addon.SpellCreationPresets.GetResources("magic")) do
        for _, item in ipairs(group.children or {}) do
            if resource == item.label or resource == item.plural then
                local plural = amount and amount ~= "" and tonumber(amount) ~= 1
                return plural and item.plural or item.label, true
            end
        end
    end
    return resource, false
end

function addon.SpellCreationPresets.GetRanges()
    return localize(ranges)
end

function addon.SpellCreationPresets.GetCastTimes(timeMode)
    return localize(castTimes[timeMode] or castTimes.rounds)
end

function addon.SpellCreationPresets.GetCooldowns(timeMode)
    return localize(cooldowns[timeMode] or cooldowns.rounds)
end
function addon.SpellCreationPresets.GetDurations(timeMode)
    if timeMode == "time" then return localize(cooldowns.time) end
    local options = {}
    for rounds = 1, 5 do
        options[#options + 1] = option(tostring(rounds), "PRESET_COOLDOWN_ROUND_" .. rounds,
            { order = rounds, rangeValueKey = "PRESET_VALUE_" .. rounds })
    end
    options[#options + 1] = option("permanent", "PRESET_EFFECT_PERMANENT", { exclusive = true })
    return localize(options)
end


function addon.SpellCreationPresets.GetMagicTypes()
    return localize(magicTypes)
end

function addon.SpellCreationPresets.GetMagicSubtypes()
    return localize(magicSubtypes)
end

function addon.SpellCreationPresets.GetMagicSchools()
    return localize(magicSchools)
end

function addon.SpellCreationPresets.GetDamageTypes()
    return localize(damageTypes)
end

function addon.SpellCreationPresets.GetDebuffTypes()
    return localize(debuffTypes)
end

function addon.SpellCreationPresets.FormatTimeSelection(options, selected, timeMode, valueKind, locale)
    local chosen = {}
    for _, item in ipairs(options or {}) do
        if selected and selected[item.value] then
            chosen[#chosen + 1] = item
        end
    end
    table.sort(chosen, function(left, right)
        return (left.order or 0) < (right.order or 0)
    end)
    if #chosen == 0 then
        return ""
    end
    if #chosen == 1 or chosen[1].exclusive then
        return chosen[1].label
    end
    if timeMode == "time" and valueKind == "cooldown" then
        return localeText(locale,
            "PRESET_TIME_RANGE_GENERIC",
            chosen[1].label,
            chosen[2].label
        )
    end
    if timeMode == "time" then
        return localeText(locale,
            "PRESET_TIME_RANGE_SECONDS",
            chosen[1].rangeValue or chosen[1].label,
            chosen[2].rangeValue or chosen[2].label
        )
    end
    return localeText(locale,
        "PRESET_TIME_RANGE_ROUNDS",
        chosen[1].rangeValue or chosen[1].label,
        chosen[2].rangeValue or chosen[2].label
    )
end

local translationCaches = {}
local translationLocales = { "enUS", "deDE", "frFR" }

local function foldPresetText(text)
    return text:lower():gsub("\195([\128-\158])", function(byte)
        local value = byte:byte()
        return "\195" .. string.char(value == 151 and value or value + 32)
    end):gsub("\197\146", "\197\147"):gsub("\225\186\158", "\195\159")
end

local function buildTranslations(locale, translations)
    local fields = {}
    local function add(field, source, target, item)
        if not source or not target then return end
        fields[field] = fields[field] or {}
        local key = foldPresetText(source)
        local previous = fields[field][key]
        if previous == false then return end
        if previous and previous.text ~= target then
            fields[field][key] = false
        else
            fields[field][key] = {
                text = target,
                allowsAmount = item and item.allowsAmount,
                singular = item and localeText(locale, item.labelKey),
                plural = item and item.pluralKey and localeText(locale, item.pluralKey),
            }
        end
    end
    local function addOptions(field, options)
        for _, item in ipairs(options) do
            if item.children then
                addOptions(field, item.children)
            else
                for _, sourceLocale in ipairs(translationLocales) do
                    if translations[sourceLocale] then
                        add(field, localeText(sourceLocale, item.labelKey), localeText(locale, item.labelKey), item)
                        if item.pluralKey then
                            add(field, localeText(sourceLocale, item.pluralKey), localeText(locale, item.pluralKey), item)
                        end
                    end
                end
            end
        end
    end
    addOptions("resource", resources.magic)
    addOptions("resource", resources.ability)
    addOptions("range", ranges)
    addOptions("magicType", magicTypes)
    addOptions("magicType", magicSubtypes)
    addOptions("magicSchool", magicSchools)
    addOptions("damageType", damageTypes)
    addOptions("debuffType", debuffTypes)

    for field, modes in pairs({ castTime = castTimes, cooldown = cooldowns }) do
        addOptions(field, modes.rounds)
        addOptions(field, modes.time)
        for mode, options in pairs(modes) do
            for firstIndex, first in ipairs(options) do
                if not first.exclusive then
                    for secondIndex = firstIndex + 1, #options do
                        local second = options[secondIndex]
                        if not second.exclusive then
                            local selected = { [first.value] = true, [second.value] = true }
                            local target = addon.SpellCreationPresets.FormatTimeSelection(
                                localize(options, locale), selected, mode, field, locale)
                            for _, sourceLocale in ipairs(translationLocales) do
                                if translations[sourceLocale] then
                                    local source = addon.SpellCreationPresets.FormatTimeSelection(
                                        localize(options, sourceLocale), selected, mode, field, sourceLocale)
                                    add(field, source, target)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return fields
end

function addon.SpellCreationPresets.NormalizeField(field, text, locale)
    local localization = addon.Localization
    if type(text) ~= "string" or #text > 80 or type(localization) ~= "table"
        or type(localization.translations) ~= "table" then return text end
    local translations = localization.translations
    locale = locale or localization.GetLocale()
    if not translations[locale] then locale = "enUS" end
    local cache = translationCaches[locale]
    if not cache or cache.enUS ~= translations.enUS
        or cache.deDE ~= translations.deDE or cache.frFR ~= translations.frFR then
        cache = { enUS = translations.enUS, deDE = translations.deDE,
            frFR = translations.frFR, fields = buildTranslations(locale, translations) }
        translationCaches[locale] = cache
    end
    local options = cache.fields[field]
    if not options then return text end
    local item = options[foldPresetText(text)]
    if item then return item.text end
    if field == "resource" then
        local amount, name = text:match("^(%d+) (.+)$")
        item = name and options[foldPresetText(name)]
        if item and item.allowsAmount and #amount <= 5 then
            return amount .. " " .. (tonumber(amount) ~= 1 and item.plural or item.singular)
        end
    end
    return text
end

function addon.SpellCreationPresets.NormalizeSpell(spell)
    if type(spell) ~= "table" then return end
    local normalize = addon.SpellCreationPresets.NormalizeField
    for _, field in ipairs({ "resource", "range", "castTime", "cooldown" }) do
        spell[field] = normalize(field, spell[field])
    end
    if type(spell.tags) == "table" then
        for key, field in pairs({ [addon.Constants.MAGIC_TAG_TYPE] = "magicType",
            [addon.Constants.MAGIC_TAG_SCHOOL] = "magicSchool",
            [addon.Constants.SPELL_TAG_DAMAGE_TYPE] = "damageType",
            Magieart = "magicType", Magieschule = "magicSchool" }) do
            spell.tags[key] = normalize(field, spell.tags[key])
        end
    end
    if type(spell.effects) == "table" then
        spell.effects.debuffType = normalize("debuffType", spell.effects.debuffType)
    end
end

function addon.SpellCreationPresets.MatchTimeSelection(
    options,
    text,
    timeMode,
    valueKind
)
    local normalized = addon.Runtime.Trim(text)
    if not normalized or normalized == "" then
        return {}
    end

    for _, item in ipairs(options or {}) do
        if addon.SpellCreationPresets.FormatTimeSelection(
            options,
            { [item.value] = true },
            timeMode,
            valueKind
        ) == normalized then
            return { [item.value] = true }
        end
    end

    for firstIndex = 1, #(options or {}) do
        local first = options[firstIndex]
        if not first.exclusive then
            for secondIndex = firstIndex + 1, #options do
                local second = options[secondIndex]
                if not second.exclusive then
                    local selected = {
                        [first.value] = true,
                        [second.value] = true,
                    }
                    if addon.SpellCreationPresets.FormatTimeSelection(
                        options,
                        selected,
                        timeMode,
                        valueKind
                    ) == normalized then
                        return selected
                    end
                end
            end
        end
    end
    return {}
end

function addon.SpellCreationPresets.GetSelectionMaximum(options, selected)
    local maximum
    for _, item in ipairs(options or {}) do
        if selected and selected[item.value] and item.order then
            maximum = math.max(maximum or 0, item.order)
        end
    end
    return maximum
end

function addon.SpellCreationPresets.IsNoCooldown(value)
    if type(value) ~= "string" then
        return false
    end
    local normalized = value:match("^%s*(.-)%s*$"):lower()
    return normalized == "keine" or normalized == "none" or normalized == "aucun"
        or normalized == addon.L("PRESET_COOLDOWN_NONE"):lower()
end


local customGroups = {
    resource = true,
    range = true,
    magicType = true,
    magicSchool = true,
    debuffType = true,
    damageType = true,
}

local function cleanCustomPreset(group, text)
    if not customGroups[group] or type(text) ~= "string" then return end
    text = addon.Runtime.Trim(text)
    local limit = addon.Validators.Limits.MAX_SHORT_FIELD_LENGTH
    if group == "resource" then limit = limit - 6 end
    if text == "" or #text > limit or text:find("[%c|]") then return end
    return text
end

function addon.SpellCreationPresets.GetCustomPresets(group)
    local root = addon.Database.GetDB()
    local settings = type(root) == "table" and root.settings
    local all = type(settings) == "table" and settings.customPresets
    local source = type(all) == "table" and all[group]
    local result, seen = {}, {}
    for index = 1, 3 do
        local text = type(source) == "table"
            and cleanCustomPreset(group, source[index])
        if text and not seen[text] then
            result[#result + 1], seen[text] = text, true
        end
    end
    return result
end

function addon.SpellCreationPresets.SetCustomPreset(group, previous, text)
    if not customGroups[group] then return false, "CUSTOM_PRESET_INVALID" end
    local list = addon.SpellCreationPresets.GetCustomPresets(group)
    local index
    if previous then
        for position, value in ipairs(list) do
            if value == previous then index = position; break end
        end
        if not index then return false, "CUSTOM_PRESET_CHANGED" end
    end
    if text == nil then
        if not index then return false, "CUSTOM_PRESET_INVALID" end
        table.remove(list, index)
    else
        text = cleanCustomPreset(group, text)
        if not text then return false, "CUSTOM_PRESET_INVALID" end
        for position, value in ipairs(list) do
            if value == text and position ~= index then
                return false, "CUSTOM_PRESET_INVALID"
            end
        end
        if not index and #list >= 3 then return false, "CUSTOM_PRESET_LIMIT" end
        list[index or #list + 1] = text
    end
    local root = addon.Database.GetDB()
    if type(root) ~= "table" then return false, "CUSTOM_PRESET_INVALID" end
    if type(root.settings) ~= "table" then root.settings = {} end
    if type(root.settings.customPresets) ~= "table" then
        root.settings.customPresets = {}
    end
    root.settings.customPresets[group] = list
    return true, text
end
