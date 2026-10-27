local function invalid(t, validators, input)
    local valid, _, errors = validators.ValidateSpell(input)
    t.eq(valid, false)
    t.eq(type(errors), "table")
    t.eq(#errors > 0, true)
end

return {
    format = 1, area = "validators", count = 6,

    { id = "validators.normalizes-without-mutation", run = function(t, api, F)

        local input = F.spell({
            name = " Spark ", icon = 17, nameColor = " #ab12cd ",
            tags = { school = " arcane " },
            effects = {
                buff = true, debuff = true, healing = true, durationRounds = 3,
            },
        })

        local before = F.copy(input)
        local valid, cleaned, errors = api.validators.ValidateSpell(input)
        t.eq(valid, true)
        t.eq(#errors, 0)
        t.eq(cleaned.name, "Spark")
        t.eq(cleaned.icon, 17)
        t.eq(cleaned.nameColor, "AB12CD")
        t.same(cleaned.tags, { school = "arcane" })
        t.eq(cleaned.effects.buff, false)
        t.eq(cleaned.effects.debuff, true)
        t.eq(cleaned.effects.healing, true)
        t.eq(cleaned.effects.durationRounds, 3)
        t.same(input, before)
    end },

    { id = "validators.bounds-and-invalid-fields", run = function(t, api, F)

        local validators = api.validators
        local maximum = validators.Limits.MAX_SPELL_NAME_LENGTH
        t.eq(validators.ValidateSpell(F.spell({
            name = string.rep("x", maximum),
        })), true)

        invalid(t, validators, nil)
        for _, input in ipairs({
            false, {}, F.spell({ name = " " }),
            F.spell({ name = string.rep("x", maximum + 1) }),
            F.spell({ icon = 0 }), F.spell({ icon = math.huge }),
            F.spell({ nameColor = "#12345G" }),
            F.spell({ tags = { school = 7 } }),
        })
        do

            invalid(t, validators, input)
        end

        local tags = {}
        for index = 1, validators.Limits.MAX_TAGS_PER_SPELL
        do
            tags["tag" .. index] = "value"
        end

        t.eq(validators.ValidateSpell(F.spell({ tags = tags })), true)
        tags.extra = "value"

        invalid(t, validators, F.spell({ tags = tags }))
    end },

    { id = "validators.numeric-effect-duration", run = function(t, api, F)

        local validators = api.validators
        for _, rounds in ipairs({ 0, 100 })
        do

            local valid, cleaned = validators.ValidateSpell(F.spell({
                effects = { buff = true, durationRounds = rounds },
            }))

            t.eq(valid, true)
            t.eq(cleaned.effects.durationRounds, rounds)
            if rounds == 0 then

                t.eq(cleaned.effects.duration, api.constants.EFFECT_DURATION_INFINITY)
            end
        end

        for _, seconds in ipairs({ 1, 31536000 })
        do

            local valid, cleaned = validators.ValidateSpell(F.spell({
                effects = { debuff = true, durationSeconds = seconds },
            }))

            t.eq(valid, true)
            t.eq(cleaned.effects.durationSeconds, seconds)
        end

        for _, effects in ipairs({
            { durationRounds = -1 }, { durationRounds = 101 },
            { durationRounds = 1.5 }, { durationSeconds = 0 },
            { durationSeconds = 31536001 },
            { durationRounds = 0, durationSeconds = 1 },
            { whisperTemplate = "|Hbad" }, { whisperTemplate = "bad\nmessage" },
        })
        do
            effects.buff = true

            invalid(t, validators, F.spell({ effects = effects }))
        end
    end },

    { id = "validators.translates-known-preset-fields", run = function(t, api, F)
        api.setLocale("deDE")
        local translates = F.translates(api)
        local input = F.spell({ name = "Arcane", description = "Arcane magic",
            resource = "3 red essences", range = "Melee", castTime = "1-2 rounds", cooldown = "None",
            tags = { magicType = "arcane", magicSchool = "Evocation", damageType = "Physical" },
            effects = { debuff = true, debuffType = "Curse", durationRounds = 3 } })
        local before = F.copy(input)
        local valid, cleaned = api.validators.ValidateSpell(input)
        t.eq(valid, true)
        if translates then
            t.eq(cleaned.tags.magicType, "Arkan")
            t.eq(cleaned.tags.magicSchool, api.localization.Get("PRESET_SCHOOL_EVOCATION"))
            t.eq(cleaned.tags.damageType, api.localization.Get("PRESET_DAMAGE_PHYSICAL"))
            t.eq(cleaned.effects.debuffType, api.localization.Get("PRESET_DEBUFF_CURSE"))
            t.eq(cleaned.resource, "3 " .. api.localization.Get("PRESET_RESOURCE_ESSENCE_RED_PLURAL"))
            t.eq(cleaned.range, api.localization.Get("PRESET_RANGE_MELEE"))
            t.eq(cleaned.castTime, api.localization.Get("PRESET_TIME_RANGE_ROUNDS", "1", "2"))
            t.eq(cleaned.cooldown, api.localization.Get("PRESET_COOLDOWN_NONE"))
        else
            for _, field in ipairs({ "resource", "range", "castTime", "cooldown" }) do
                t.eq(cleaned[field], input[field])
            end
            t.same(cleaned.tags, input.tags)
            t.eq(cleaned.effects.debuffType, input.effects.debuffType)
        end
        t.eq(cleaned.name, "Arcane")
        t.eq(cleaned.description, "Arcane magic")
        t.same(input, before)
    end },

    { id = "validators.preserves-custom-preset-text", run = function(t, api, F)
        api.setLocale("deDE")
        for _, text in ipairs({ "Arkane Magie", "Arcane magic", "Arcane Fire", "Superarcane", "Arkan!" }) do
            local valid, cleaned = api.validators.ValidateSpell(F.spell({ tags = { magicType = text } }))
            t.eq(valid, true)
            t.eq(cleaned.tags.magicType, text)
        end
    end },

    { id = "validators.isolates-locale-per-case", run = function(t, api, F)
        t.eq(api.localization.GetLocale(), "enUS")
        api.setLocale("frFR")
        t.eq(api.localization.GetLocale(), "frFR")
        local valid, cleaned = api.validators.ValidateSpell(F.spell({ resource = "ENERGY",
            tags = { magicType = "ARKAN" } }))
        t.eq(valid, true)
        if F.translates(api) then
            t.eq(cleaned.resource, api.localization.Get("PRESET_RESOURCE_ENERGY"))
            t.eq(cleaned.tags.magicType, api.localization.Get("PRESET_MAGIC_ARCANE"))
        else
            t.eq(cleaned.resource, "ENERGY")
            t.eq(cleaned.tags.magicType, "ARKAN")
        end
        if type(api.localization.SetLanguage) == "function" then
            t.eq(api.localization.SetLanguage("unsupported"), false)
        end
        t.eq(api.localization.GetLocale(), "frFR")
    end },
}
