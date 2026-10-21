local _, addon = ...

addon.Search = {}

local normalizedSpellCache = setmetatable({}, { __mode = "k" })

local function normalize(value)
    if type(value) ~= "string" then
        return ""
    end
    return string.lower(value):match("^%s*(.-)%s*$")
end

local function append(values, value)
    local text = normalize(value)
    if text ~= "" then
        values[#values + 1] = text
    end
end

local function buildSearchData(spell)
    local metadata = {}
    append(metadata, spell.resource)
    append(metadata, spell.range)
    append(metadata, spell.castTime)
    append(metadata, spell.cooldown)

    local tags = {}
    if type(spell.tags) == "table" then
        for key, value in pairs(spell.tags) do
            append(tags, key)
            append(tags, value)
        end
    end
    local buff, buffLabel, debuff = false, "", false
    if type(spell.effects) == "table" then
        if spell.effects.buff == true then
            buff = true
            buffLabel = normalize(addon.L("EFFECT_BUFF"))
        end
        if spell.effects.debuff == true then
            debuff = true
            append(tags, spell.effects.debuffType)
        end
        if spell.effects.healing == true then
            append(tags, addon.L("EFFECT_HEALING"))
        end
    end

    return {
        description = normalize(spell.description),
        buff = buff,
        buffLabel = buffLabel,
        debuff = debuff,
        metadata = table.concat(metadata, "\n"),
        name = normalize(spell.name),
        tags = table.concat(tags, "\n"),
    }
end

local function getSearchData(spell)
    local revision = tonumber(spell.revision)
    local cached = normalizedSpellCache[spell]
    if revision and cached and cached.revision == revision then
        return cached.data
    end
    local data = buildSearchData(spell)
    if revision then
        normalizedSpellCache[spell] = { data = data, revision = revision }
    end
    return data
end

local function scoreValue(value, query, exactScore, prefixScore, matchScore)
    if value == query then
        return exactScore
    end
    local position = value:find(query, 1, true)
    if position == 1 then
        return prefixScore
    end
    return position and matchScore or nil
end

local function scoreTerm(data, query)
    local nameScore = scoreValue(data.name, query, 1000, 800, 600)
    if nameScore then
        return nameScore
    end
    if (data.buff and (query == "buff" or data.buffLabel:find(query, 1, true)))
        or (data.debuff and ("debuff"):find(query, 1, true) == 1)
    then
        return 220
    end
    if data.tags:find(query, 1, true) then
        return 220
    end
    if data.metadata:find(query, 1, true) then
        return 180
    end
    if data.description:find(query, 1, true) then
        return 40
    end
    return nil
end

local function scoreSpell(spell, query)
    if query == "" then
        return 0
    end
    local data = getSearchData(spell)
    local score = 0
    local termCount = 0
    for term in query:gmatch("%S+") do
        local termScore = scoreTerm(data, term)
        if not termScore then
            return nil
        end
        score = score + termScore
        termCount = termCount + 1
    end
    return termCount > 0 and score or 0
end

local function appendTabMatches(
    spellbook,
    tab,
    query,
    results,
    seen,
    favoritesOnly,
    order
)
    if type(tab) ~= "table" or type(tab.spellIds) ~= "table" then
        return
    end
    local favorites = type(spellbook.favorites) == "table"
        and spellbook.favorites or {}
    for _, spellID in ipairs(tab.spellIds) do
        local spell = type(spellbook.spells) == "table"
            and spellbook.spells[spellID] or nil
        if type(spellID) == "string"
            and not seen[spellID]
            and type(spell) == "table"
            and (not favoritesOnly or favorites[spellID] == true)
        then
            local score = scoreSpell(spell, query)
            if score then
                seen[spellID] = true
                order = order + 1
                results[#results + 1] = {
                    id = spellID,
                    order = order,
                    score = score,
                }
            end
        end
    end
    return order
end

function addon.Search.FindSpellIDs(spellbook, activeTabID, searchText, options)
    if type(spellbook) ~= "table" then
        return {}
    end
    options = type(options) == "table" and options or {}
    local query = normalize(searchText)
    local results = {}
    local seen = {}
    local order = 0
    local searchAllTabs = query ~= "" or options.favoritesOnly == true

    if not searchAllTabs then
        local tab = type(spellbook.tabs) == "table"
            and spellbook.tabs[activeTabID] or nil
        appendTabMatches(spellbook, tab, query, results, seen, false, order)
    else
        for _, tabID in ipairs(spellbook.tabOrder or {}) do
            local tab = type(spellbook.tabs) == "table"
                and spellbook.tabs[tabID] or nil
            order = appendTabMatches(
                spellbook,
                tab,
                query,
                results,
                seen,
                options.favoritesOnly == true,
                order
            ) or order
        end
    end

    if query ~= "" then
        table.sort(results, function(left, right)
            return left.score > right.score
                or (left.score == right.score and left.order < right.order)
        end)
    end
    local spellIDs = {}
    for index, result in ipairs(results) do
        spellIDs[index] = result.id
    end
    return spellIDs
end
