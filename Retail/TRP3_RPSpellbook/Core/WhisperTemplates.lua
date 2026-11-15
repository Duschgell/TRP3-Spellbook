local _, addon = ...

addon.WhisperTemplates = {}
local templates = addon.WhisperTemplates
local aliases = {}
local function alias(key, ...)
    for index = 1, select("#", ...) do aliases[select(index, ...)] = key end
end
alias("spell", "zauber", "spell", "sort")
alias("player", "spieler", "player", "caster", "joueur")
alias("target", "ziel", "target", "cible")
alias("playerLastName", "spielernachname", "playerlastname", "nomdefamillejoueur")
alias("targetLastName", "zielnachname", "targetlastname", "nomdefamillecible")
alias("playerFullName", "spielervollname", "playerfullname", "nomcompletjoueur")
alias("targetFullName", "zielvollname", "targetfullname", "nomcompletcible")
alias("playerRace", "spielerrasse", "playerrace", "racejoueur")
alias("targetRace", "zielrasse", "targetrace", "racecible")
alias("playerClass", "spielerklasse", "playerclass", "classejoueur")
alias("targetClass", "zielklasse", "targetclass", "classecible")
alias("playerTitle", "spielertitel", "playertitle", "titrejoueur")
alias("targetTitle", "zieltitel", "targettitle", "titrecible")
alias("effectType", "effektart", "effekart", "effecttype", "typeeffet")
alias("magicType", "magieart", "magictype", "typemagie")
alias("magicSchool", "magieschule", "magicschool", "ecolemagie", "écolemagie", "Écolemagie")
alias("duration", "dauer", "duration", "durée", "duree")

function templates.GetVariableKey(name)
    return type(name) == "string" and aliases[name:lower():gsub("É", "é")] or nil
end

local function clean(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
        :gsub("[%c]", " "):match("^%s*(.-)%s*$")
end

local function identity(id, supplied)
    if type(supplied) == "table" then return supplied end
    local bridge = addon.TRP3Bridge
    if bridge and bridge.GetWhisperIdentity then return bridge.GetWhisperIdentity(id) end
    local name = clean(id):match("^[^-]+") or ""
    return { firstName = name, lastName = name, fullName = name }
end

function templates.Duration(effects, seconds)
    effects = effects or {}
    local text = clean(effects.duration)
    local normalized = text:lower()
    if seconds == nil and (effects.durationRounds == 0
        or text == addon.Constants.EFFECT_DURATION_INFINITY or normalized == "permanent"
        or normalized == "unendlich" or normalized == "infinite" or normalized == "infini") then
        return addon.L("WHISPER_DURATION_ALL_ROUNDS")
    end
    if seconds == nil and text ~= "" then return text end
    seconds = seconds or effects.durationSeconds
    if type(seconds) == "number" and seconds > 0 and seconds < math.huge then
        local minutes = seconds / 60
        if minutes == math.floor(minutes) then
            return addon.L(minutes == 1 and "WHISPER_DURATION_MINUTE" or "WHISPER_DURATION_MINUTES", minutes)
        end
        return addon.L(seconds == 1 and "WHISPER_DURATION_SECOND" or "WHISPER_DURATION_SECONDS", seconds)
    end
    local rounds = effects.durationRounds
    if type(rounds) == "number" and rounds > 0 and rounds < math.huge then
        return addon.L(rounds == 1 and "WHISPER_DURATION_ROUND" or "WHISPER_DURATION_ROUNDS", rounds)
    end
    return ""
end

function templates.Default(effects)
    effects = effects or {}
    local key = effects.debuff and (effects.healing and "DEBUFF_HEALING" or "DEBUFF")
        or effects.buff and (effects.healing and "BOTH" or "BUFF") or "HEALING"
    return addon.L("EFFECT_WHISPER_DEFAULT_" .. key)
end

function templates.Example(index)
    return addon.L("WHISPER_EXAMPLE_" .. (1 + ((index or 1) - 1) % 3))
end

 
local function fitMessage(text, maximum)
    if #text <= maximum then return text end
    local parts, length, position = {}, 0, 1
    while position <= #text do
        local token = text:sub(position):match("^(%[TRP3:[^%s%c%[%]|]+%])")
        local part = token or text:sub(position):match("^[%z\1-\127\194-\244][\128-\191]*")
        if not part or length + #part > maximum - 3 then break end
        parts[#parts + 1], length, position = part, length + #part, position + #part
    end
    return table.concat(parts):gsub("%s+$", "") .. "..."
end

function templates.Render(template, spell, context)
    context = context or {}
    spell = spell or {}
    local effects, tags = spell.effects or {}, spell.tags or {}
    template = clean(template)
    if template == "" then template = templates.Default(effects) end
    local player = identity(context.playerID, context.playerIdentity)
    local target = identity(context.targetID, context.targetIdentity)
    local values = {
        spell = context.spellLink or clean(spell.name),
        player = clean(player.firstName), target = clean(target.firstName),
        playerLastName = clean(player.lastName), targetLastName = clean(target.lastName),
        playerFullName = clean(player.fullName), targetFullName = clean(target.fullName),
        playerRace = clean(player.race), targetRace = clean(target.race),
        playerClass = clean(player.class), targetClass = clean(target.class),
        playerTitle = clean(player.title), targetTitle = clean(target.title),
        effectType = addon.L(effects.debuff and "EFFECT_DEBUFF" or effects.buff and "EFFECT_BUFF" or "EFFECT_HEALING"),
        magicType = clean(tags[addon.Constants.MAGIC_TAG_TYPE] or tags.Magieart),
        magicSchool = clean(tags[addon.Constants.MAGIC_TAG_SCHOOL] or tags.Magieschule),
        duration = templates.Duration(effects, context.durationSeconds),
    }
    local message = template:gsub("{([^{}]+)}", function(name)
        local key = templates.GetVariableKey(name)
        return key and values[key] or ("{" .. name .. "}")
    end)
    message = message:gsub("^%s*%*", ""):gsub("%*%s*$", ""):match("^%s*(.-)%s*$")
    message = fitMessage(message, 250)
    return message ~= "" and ("*" .. message .. "*") or nil
end

function templates.Build(spell, context)
    context = context or {}
    local template = spell.effects and spell.effects.whisperTemplate or ""
    if clean(template) == "" then template = templates.Default(spell.effects) end
    local needsLink = false
    template:gsub("{([^{}]+)}", function(name)
        if templates.GetVariableKey(name) == "spell" then needsLink = true end
    end)
    local resolved = {}
    for key, value in pairs(context) do resolved[key] = value end
    if needsLink and addon.ChatLinks and type(addon.ChatLinks.CreateSnapshot) == "function"
        and addon.TRP3Bridge and addon.TRP3Bridge.CreateSpellChatLink then
        local owner = spell.ownerKey or context.ownerKey
        local snapshot = addon.ChatLinks.CreateSnapshot(owner, spell)
         
        if snapshot then resolved.spellLink = addon.TRP3Bridge.CreateSpellChatLink(snapshot) end
    end
    return templates.Render(template, spell, resolved)
end
