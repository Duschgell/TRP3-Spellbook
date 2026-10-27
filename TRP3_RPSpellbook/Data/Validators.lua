local _, addon = ...

addon.Validators = {}

addon.Validators.Limits = {
    MAX_DESCRIPTION_LENGTH = 2000,
    MAX_EFFECT_MESSAGE_LENGTH = 300,
    MAX_ICON_LENGTH = 255,
    MAX_SHORT_FIELD_LENGTH = 80,
    MAX_SPELL_NAME_LENGTH = 80,
    MAX_TAB_NAME_LENGTH = 40,
    MAX_TAG_KEY_LENGTH = 40,
    MAX_TAG_VALUE_LENGTH = 80,
    MAX_TAGS_PER_SPELL = 20,
}

local validTabThemeIDs = {
    default = true,
    midnight = true,
    parchment = true,
    emerald = true,
    titan = true,
    fancy = true,
    ["dynamic:arcane"] = true,
    ["dynamic:light"] = true,
    ["dynamic:demonic"] = true,
    ["dynamic:nature"] = true,
    ["dynamic:necromancy"] = true,
    ["dynamic:shadow"] = true,
    ["dynamic:elemental"] = true,
    ["dynamic:chi"] = true,
    ["dynamic:physical"] = true,
    ["dynamic:shot"] = true,
    ["dynamic:poison"] = true,
    ["dynamic:explosion"] = true,
    ["dynamic:bleed"] = true,
    ["dynamic:stun"] = true,
}

function addon.Validators.NormalizeTabThemeID(value)
    return validTabThemeIDs[value] and value or "default"
end

local function trim(value)
    if type(value) ~= "string" then
        return nil
    end

    return value:match("^%s*(.-)%s*$")
end

local function addError(errors, message)
    errors[#errors + 1] = message
end

local function cleanRequiredString(value, maximumLength, errors, emptyMessage, longMessage)
    local cleaned = trim(value)
    if not cleaned or cleaned == "" then
        addError(errors, emptyMessage)
        return nil
    end

    if #cleaned > maximumLength then
        addError(errors, longMessage)
        return nil
    end

    return cleaned
end

local function cleanOptionalString(value, maximumLength, errors, fieldName)
    if value == nil then
        return nil
    end

    local cleaned = trim(value)
    if not cleaned or cleaned == "" then
        return nil
    end

    if #cleaned > maximumLength then
        addError(errors, addon.L("FIELD_TOO_LONG", fieldName))
        return nil
    end

    return cleaned
end
local function cleanDuration(value, minimum, maximum, errors)
    if value == nil then return nil end
    local number = tonumber(value)
    if not number or number ~= number or number < minimum or number > maximum
        or number ~= math.floor(number)
    then
        addError(errors, addon.L("INVALID_EFFECT_DURATION"))
        return nil
    end
    return number
end

local function cleanEffects(effects, errors)
    if effects == nil then
        return nil
    end
    if type(effects) ~= "table" then
        addError(errors, addon.L("INVALID_EFFECTS"))
        return nil
    end

    local debuff = effects.debuff == true
    local buff = effects.buff == true and not debuff
    local healing = effects.healing == true
    if not buff and not debuff and not healing then
        return nil
    end

    local limits = addon.Validators.Limits
    local duration = cleanOptionalString(
        effects.duration,
        limits.MAX_SHORT_FIELD_LENGTH,
        errors,
        addon.L("FIELD_DURATION")
    )
    local message = cleanOptionalString(
        effects.whisperTemplate,
        limits.MAX_EFFECT_MESSAGE_LENGTH,
        errors,
        addon.L("FIELD_EFFECT_WHISPER")
    )
    if message and message:find("[%c|]") then
        addError(errors, addon.L("INVALID_EFFECT_MESSAGE"))
        message = nil
    end
    local debuffType = cleanOptionalString(
        effects.debuffType,
        limits.MAX_SHORT_FIELD_LENGTH,
        errors,
        addon.L("FIELD_DEBUFF_TYPE")
    )
    if effects.debuffType ~= nil and type(effects.debuffType) ~= "string" then
        addError(errors, addon.L("INVALID_EFFECTS"))
        debuffType = nil
    elseif debuffType and debuffType:find("[%c|]") then
        addError(errors, addon.L("INVALID_EFFECTS"))
        debuffType = nil
    end

    local durationRounds = cleanDuration(effects.durationRounds, 0, 100, errors)
    local durationSeconds = cleanDuration(effects.durationSeconds, 1, 31536000, errors)
    if durationRounds and durationSeconds then
        addError(errors, addon.L("INVALID_EFFECT_DURATION"))
        durationSeconds = nil
    end
    if (buff or debuff) and duration and not durationRounds and not durationSeconds
        and addon.SpellPresentation
        and type(addon.SpellPresentation.ParseEffectDuration) == "function"
    then
        durationRounds, durationSeconds =
            addon.SpellPresentation.ParseEffectDuration(duration)
        durationRounds = cleanDuration(durationRounds, 0, 100, errors)
        durationSeconds = cleanDuration(durationSeconds, 1, 31536000, errors)
    end
    if not buff and not debuff then
        duration = nil
        durationRounds = nil
        durationSeconds = nil
    end
    if durationRounds == addon.Constants.EFFECT_DURATION_PERMANENT then
        duration = addon.Constants.EFFECT_DURATION_INFINITY
    end
    if not debuff then
        debuffType = nil
    end

    return {
        buff = buff,
        debuff = debuff,
        debuffType = debuffType,
        duration = duration,
        durationRounds = durationRounds,
        durationSeconds = durationSeconds,
        healing = healing,
        whisperTemplate = message,
    }
end

local function cleanIcon(value, errors)
    if value == nil or value == "" then
        return nil
    end

    if type(value) == "number"
        and value == value
        and value > 0
        and value < math.huge
        and value == math.floor(value)
        and value <= addon.Constants.MAX_IMPORT_SAFE_INTEGER
    then
        return value
    end

    if type(value) ~= "string" then
        addError(errors, addon.L("INVALID_ICON"))
        return nil
    end

    local cleaned = trim(value)
    if cleaned == "" then
        return nil
    end

    if #cleaned > addon.Validators.Limits.MAX_ICON_LENGTH then
        addError(errors, addon.L("INVALID_ICON"))
        return nil
    end

    return cleaned
end

local function cleanColor(value, errors)
    if value == nil or value == "" then
        return nil
    end
    if type(value) ~= "string" then
        addError(errors, addon.L("INVALID_COLOR"))
        return nil
    end

    local color = trim(value)
    if color:sub(1, 1) == "#" then
        color = color:sub(2)
    end
    color = string.upper(color)
    if not color:match("^%x%x%x%x%x%x$") then
        addError(errors, addon.L("INVALID_COLOR"))
        return nil
    end
    return color
end

local function cleanTags(tags, errors)
    if tags == nil then
        return nil
    end

    if type(tags) ~= "table" then
        addError(errors, addon.L("INVALID_TAGS"))
        return nil
    end

    local cleaned = {}
    local count = 0
    for key, value in pairs(tags) do
        if type(key) ~= "string" or type(value) ~= "string" then
            addError(errors, addon.L("TAGS_TEXT_ONLY"))
        else
            local cleanedKey = trim(key)
            local cleanedValue = trim(value)
            if cleanedKey and cleanedKey ~= "" and cleanedValue and cleanedValue ~= "" then
                count = count + 1
                if count > addon.Validators.Limits.MAX_TAGS_PER_SPELL then
                    addError(errors, addon.L("TOO_MANY_TAGS"))
                    break
                elseif #cleanedKey > addon.Validators.Limits.MAX_TAG_KEY_LENGTH then
                    addError(errors, addon.L("TAG_KEY_TOO_LONG"))
                elseif #cleanedValue > addon.Validators.Limits.MAX_TAG_VALUE_LENGTH then
                    addError(errors, addon.L("TAG_VALUE_TOO_LONG"))
                else
                    cleaned[cleanedKey] = cleanedValue
                end
            end
        end
    end

    if next(cleaned) == nil then
        return nil
    end

    return cleaned
end

function addon.Validators.ValidateSpell(data)
    local errors = {}
    if type(data) ~= "table" then
        return false, nil, { addon.L("INVALID_ABILITY") }
    end

    local limits = addon.Validators.Limits
    local cleaned = {
        name = cleanRequiredString(
            data.name,
            limits.MAX_SPELL_NAME_LENGTH,
            errors,
            addon.L("NAME_EMPTY"),
            addon.L("NAME_TOO_LONG")
        ),
        icon = cleanIcon(data.icon, errors),
        nameColor = cleanColor(data.nameColor, errors),
        resource = cleanOptionalString(data.resource, limits.MAX_SHORT_FIELD_LENGTH, errors, addon.L("FIELD_RESOURCE")),
        range = cleanOptionalString(data.range, limits.MAX_SHORT_FIELD_LENGTH, errors, addon.L("FIELD_RANGE")),
        castTime = cleanOptionalString(data.castTime, limits.MAX_SHORT_FIELD_LENGTH, errors, addon.L("FIELD_CAST_TIME")),
        cooldown = cleanOptionalString(data.cooldown, limits.MAX_SHORT_FIELD_LENGTH, errors, addon.L("FIELD_COOLDOWN")),
        description = cleanOptionalString(data.description, limits.MAX_DESCRIPTION_LENGTH, errors, addon.L("FIELD_DESCRIPTION")),
        effects = cleanEffects(data.effects, errors),
        tags = cleanTags(data.tags, errors),
    }

    if addon.SpellCreationPresets and addon.SpellCreationPresets.NormalizeSpell then
        addon.SpellCreationPresets.NormalizeSpell(cleaned)
    end

    return #errors == 0, cleaned, errors
end

function addon.Validators.ValidateTab(data)
    local errors = {}
    if type(data) ~= "table" then
        return false, nil, { addon.L("INVALID_TAB") }
    end

    local cleaned = {
        name = cleanRequiredString(
            data.name,
            addon.Validators.Limits.MAX_TAB_NAME_LENGTH,
            errors,
            addon.L("TAB_NAME_EMPTY"),
            addon.L("TAB_NAME_TOO_LONG")
        ),
        icon = cleanIcon(data.icon, errors),
        themeID = data.themeID ~= nil
            and addon.Validators.NormalizeTabThemeID(data.themeID)
            or nil,
        spellIds = {},
    }

    local seen = {}
    if type(data.spellIds) == "table" then
        for _, spellID in ipairs(data.spellIds) do
            if type(spellID) == "string" and spellID ~= "" and not seen[spellID] then
                seen[spellID] = true
                cleaned.spellIds[#cleaned.spellIds + 1] = spellID
            end
        end
    end

    return #errors == 0, cleaned, errors
end

function addon.Validators.GetFirstError(errors)
    if type(errors) == "table" and type(errors[1]) == "string" then
        return errors[1]
    end

    return addon.L("INVALID_INPUT")
end
