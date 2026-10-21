local _, private = ...
local addon = private.Shared or private
local archive = addon.NPCArchive
local db
local MAX_NPCS, MAX_ABILITIES = 50, 24
local MAX_VARIANTS = 8
local defaults = { width = 540, height = 460, scale = 1, trackingMode = "off" }
local preferenceBounds = { width = { 360, 1100 }, height = { 320, 1000 }, scale = { 0.6, 1.25 } }
local splitVariant
local identityTokens, nextIdentityToken = setmetatable({}, { __mode = "k" }), 0

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end

local function id(value)
    return type(value) == "number" and value == value and value > 0
        and value <= 2147483647 and value == math.floor(value)
end

local function creatureIdentity(npc)
    if npc.source == "authored" then return nil end
    return npc.creatureID or npc.id
end

local function text(value, limit)
    if type(value) ~= "string" or #value > limit or value:find("|")
        or value:find("[%z\1-\8\11-\31\127]") then return nil end
    return value:match("^%s*(.-)%s*$")
end

local function count(values)
    local n = 0
    for _ in pairs(values) do n = n + 1 end
    return n
end

local function timestamp()
    return type(time) == "function" and time() or 0
end

local function cleanTime(value)
    return type(value) == "number" and value == value and value >= 0 and value <= 9007199254740991 and value or nil
end

local function validPreference(key, value)
    if key == "trackingMode" then return value == "off" or value == "target" or value == "background" end
    local bounds = preferenceBounds[key]
    return bounds and type(value) == "number" and value == value and value >= bounds[1] and value <= bounds[2]
end

local function cleanIdentity(data)
    data = type(data) == "table" and data or {}
    return { creatureID = id(data.creatureID) and data.creatureID or nil,
        displayID = id(data.displayID) and data.displayID or nil,
        creatureType = text(data.creatureType, 80), classification = text(data.classification, 20) }
end

local function cleanEngine(data)
    data = type(data) == "table" and data or {}
    local result = { source = "C_Spell", description = text(data.description, 2000) or "",
        name = text(data.name, 80), resource = text(data.resource, 80),
        icon = id(data.icon) and data.icon or nil, capturedAt = cleanTime(data.capturedAt) }
    for _, key in ipairs({ "castTime", "minRange", "maxRange" }) do
        local value = data[key]
        if type(value) == "number" and value == value and value >= 0 and value <= 3600000 then result[key] = value end
    end
    return result
end

local function cleanRP(data)
    if type(data) ~= "table" then return nil end
    local result = {}
    for _, field in ipairs({ "name", "description", "resource", "range", "castTime", "icon" }) do
        local value = data[field]
        if field == "icon" and id(value) then
            result.icon = value
        else
            result[field] = text(value or "", field == "description" and 2000 or (field == "icon" and 255 or 80))
            if not result[field] then return nil end
        end
    end
    if result.name == "" or result.resource:find("[%d%%]") then return nil end
    if data.kind ~= "" and data.kind ~= "magic" and data.kind ~= "ability" then return nil end
    result.kind = data.kind
    return result
end

local function getNPC(npcID)
    return db and id(npcID) and db.npcs[npcID] or nil
end

local function getAbility(npcID, spellID)
    local npc = getNPC(npcID)
    return npc and id(spellID) and npc.abilities[spellID] or nil
end

function archive.Notify()
    if type(archive.OnChanged) == "function" then archive.OnChanged() end
end

function archive.Initialize()
    if db then return true end
    local saved = _G.TRP3_RPSpellbookNPCDB
    if saved ~= nil and (type(saved) ~= "table" or (saved.version ~= 1 and saved.version ~= 2 and saved.version ~= 3)) then
        return nil, "NOT_READY"
    end
    if saved and saved.version == 3 and not archive.InitializeRegister then return nil, "NOT_READY" end
    local clean = { version = 2, npcs = {}, preferences = clone(defaults) }
    for key in pairs(defaults) do
        local value = saved and type(saved.preferences) == "table" and saved.preferences[key]
        if validPreference(key, value) then clean.preferences[key] = value end
    end
    local scanned = 0
    for npcID, npc in pairs(saved and type(saved.npcs) == "table" and saved.npcs or {}) do
        scanned = scanned + 1
        if scanned > MAX_NPCS then break end
        if id(npcID) and type(npc) == "table" and text(npc.name, 120) and npc.name ~= "" then
            local entry = { id = npcID, name = text(npc.name, 120), source = "target", abilities = {}, lastSeen = cleanTime(npc.lastSeen) }
            local identity = cleanIdentity(npc)
            entry.displayID, entry.creatureType = identity.displayID, identity.creatureType
            if npc.source == "authored" then entry.source = "authored" end
            entry.creatureID = entry.source ~= "authored" and (identity.creatureID or npcID) or nil
            entry.classification = identity.classification
            if npc.source == "combat" then entry.source = "combat" end
            entry.variants = {}
            clean.npcs[npcID] = entry
            local seen = 0
            for spellID, ability in pairs(type(npc.abilities) == "table" and npc.abilities or {}) do
                seen = seen + 1
                if seen > MAX_ABILITIES then break end
                local rp = type(ability) == "table" and cleanRP(ability.rp)
                if id(spellID) and rp then
                    local evidence = type(ability.evidence) == "table" and ability.evidence or {}
                    local observed = evidence.observed == "target-cast" or evidence.observed == "combat"
                    entry.abilities[spellID] = {
                        spellID = spellID, rp = rp, edited = ability.edited == true,
                        reviewed = ability.reviewed == true and rp.kind ~= "" and rp.description ~= "",
                        observed = ability.observed == true and observed,
                        evidence = {
                            observed = observed and evidence.observed or nil,
                            lastObserved = cleanTime(evidence.lastObserved),
                            manual = text(evidence.manual, 300),
                        },
                        engine = cleanEngine(ability.engine),
                        status = "UNAVAILABLE",
                    }
                end
            end
        end
    end
     
    local owners, ordered = {}, {}
    for npcID in pairs(clean.npcs) do ordered[#ordered + 1] = npcID; owners[npcID] = npcID end
    table.sort(ordered)
    for _, npcID in ipairs(ordered) do
        local npc, original = clean.npcs[npcID], saved and saved.npcs and saved.npcs[npcID]
        if npc.source == "combat" and type(original.variants) == "table" then
            local scannedVariants = 0
            for variantID, variant in pairs(original.variants) do
                scannedVariants = scannedVariants + 1
                if scannedVariants >= MAX_VARIANTS then break end
                if id(variantID) and not owners[variantID] and type(variant) == "table" then
                    local name = text(variant.name, 120)
                    if name and name ~= "" then
                        npc.variants[variantID] = { id = variantID, name = name,
                            creatureID = id(variant.creatureID) and variant.creatureID or variantID,
                            lastSeen = cleanTime(variant.lastSeen) }
                        owners[variantID] = npcID
                    end
                end
            end
        end
    end
    if archive.InitializeRegister then archive.InitializeRegister(clean, saved) end
    db = clean
    _G.TRP3_RPSpellbookNPCDB = clean
    return true
end

function archive.GetPreferences()
    return clone(db and db.preferences or defaults)
end

function archive.SavePreferences(patch)
    if not db then return nil, "NOT_READY" end
    if type(patch) ~= "table" then return nil, "INVALID" end
    for key, value in pairs(patch) do
        if not validPreference(key, value) then return nil, "INVALID" end
    end
    for key, value in pairs(patch) do db.preferences[key] = value end
    return true
end

local function summary(npc)
    return { id = npc.id, creatureID = creatureIdentity(npc), name = npc.name, source = npc.source,
        title = npc.title, description = npc.description, nameColor = npc.nameColor,
        icon = npc.icon or (npc.source == "authored" and "Interface\\Icons\\INV_Misc_QuestionMark" or nil),
        relationship = npc.relationship, area = npc.area,
        lastSeen = npc.lastSeen, abilityCount = archive.SpellbookStorage and npc.spellIDs
            and #npc.spellIDs or count(npc.abilities),
        displayID = npc.displayID, creatureType = npc.creatureType,
        classification = npc.classification, variantCount = 1 + count(npc.variants) }
end

function archive.GetIdentity(npcID)
    local npc = getNPC(npcID)
    return npc and summary(npc) or nil
end

function archive.List()
    local result = {}
    for _, npc in pairs(db and db.npcs or {}) do
        result[#result + 1] = summary(npc)
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function archive.Get(npcID) return clone(getNPC(npcID)) end
function archive.GetAbility(npcID, spellID) return clone(getAbility(npcID, spellID)) end

function archive.ResolveNPCID(npcID)
    if getNPC(npcID) then return npcID end
    if not db or not id(npcID) then return nil end
    for key, npc in pairs(db.npcs) do if npc.variants[npcID] then return key end end
end

function archive.ResolveCreatureNPCID(creatureID)
    if not db or not id(creatureID) then return nil end
    local direct = getNPC(creatureID)
    if direct and creatureIdentity(direct) == creatureID then return creatureID end
    local selected, variantKey
    for npcID, npc in pairs(db.npcs) do
        if creatureIdentity(npc) == creatureID and (not selected or npcID < selected) then
            selected, variantKey = npcID, nil
        end
        for key, variant in pairs(npc.variants) do
            if (variant.creatureID or key) == creatureID and (not selected or npcID < selected) then
                selected, variantKey = npcID, key
            end
        end
    end
    return selected, variantKey
end

local function freeArchiveID()
    local candidate = 2147483647
    while archive.ResolveNPCID(candidate) do candidate = candidate - 1 end
    return candidate
end

function archive.CreateProfile(data)
    if not db or not archive.ValidateTransferProfile then return nil, "NOT_READY" end
    if type(data) ~= "table" then return nil, "INVALID" end
    if count(db.npcs) >= MAX_NPCS then return nil, "FULL" end
    local candidate = { id = freeArchiveID(), source = "authored", profileEdited = true }
    for _, key in ipairs({ "name", "title", "description", "area", "relationship", "icon", "nameColor" }) do
        candidate[key] = data[key]
    end
    local npc = archive.ValidateTransferProfile(candidate)
    if not npc then return nil, "INVALID" end
    npc.spellIDs = {}
    db.npcs[npc.id] = npc
    archive.Notify()
    return archive.Get(npc.id)
end

function archive.StoreTarget(npcID, name, metadata)
    if not db then return nil, "NOT_READY" end
    name = text(name, 120)
    if not id(npcID) or not name or name == "" then return nil, "INVALID" end
    local creatureID = npcID
    local canonical, variantKey = archive.ResolveCreatureNPCID(creatureID)
    if canonical then
        npcID = variantKey or canonical
        local ok, err = splitVariant(canonical, npcID)
        if not ok then return nil, err end
    elseif archive.ResolveNPCID(npcID) then
         
        npcID = freeArchiveID()
    end
    local npc = db.npcs[npcID]
    local created = not npc
    if not npc then
        if count(db.npcs) >= MAX_NPCS then return nil, "FULL" end
        npc = { id = npcID, abilities = {}, source = "target", variants = {} }
        db.npcs[npcID] = npc
    end
    if not npc.profileEdited then npc.name = name end
    npc.lastSeen = timestamp()
    npc.creatureID = creatureID
    npc.source = "target"
    local identity = cleanIdentity(metadata)
    if identity.displayID then npc.displayID = identity.displayID end
    if identity.creatureType then npc.creatureType = identity.creatureType end
    if identity.classification then npc.classification = identity.classification end
    if archive.ApplyCaptureMetadata then archive.ApplyCaptureMetadata(npc, metadata, created) end
    archive.Notify()
    return npcID
end

local function newAbility(spellID)
    return {
        spellID = spellID, evidence = {}, observed = false, reviewed = false, edited = false,
        status = "UNAVAILABLE", engine = {},
        rp = { name = "Spell " .. spellID, kind = "", icon = "", resource = "", range = "", castTime = "", description = "" },
    }
end

local function observe(npc, spellID, source)
    local ability = npc.abilities[spellID] or newAbility(spellID)
    npc.abilities[spellID] = ability
    ability.observed, ability.evidence.observed = true, source
    ability.evidence.lastObserved = timestamp()
end

function archive.StoreAbility(npcID, spellID, source, note)
    local npc = getNPC(npcID)
    if not npc or not id(spellID) then return nil, "INVALID" end
    if source ~= "target-cast" and source ~= "combat" and source ~= "manual" then return nil, "INVALID" end
    if source == "manual" then
        note = text(note, 300)
        if not note or note == "" then return nil, "INVALID" end
    end
    local ability = npc.abilities[spellID]
    if not ability then
        if count(npc.abilities) >= MAX_ABILITIES then return nil, "FULL" end
        if next(npc.variants) then
            local ok, err = splitVariant(npcID, npcID)
            if not ok then return nil, err end
        end
        ability = newAbility(spellID)
        npc.abilities[spellID] = ability
    end
    if source == "target-cast" or source == "combat" then
        observe(npc, spellID, source)
    else
        ability.evidence.manual = note
    end
    archive.Notify()
    return spellID
end

local function copyObserved(npc, identity)
    local result = { id = identity.id, creatureID = identity.creatureID or identity.id,
        name = identity.name, source = "combat", variants = {}, spellIDs = {},
        abilities = {}, displayID = npc.displayID, creatureType = npc.creatureType,
        classification = npc.classification, lastSeen = identity.lastSeen }
    for spellID, ability in pairs(npc.abilities) do
        if ability.observed then
            local copy = clone(ability)
            copy.reviewed, copy.evidence.manual = false, nil
             
            copy.status = type(copy.engine.name) == "string" and copy.engine.name ~= "" and "READY" or "UNAVAILABLE"
            result.abilities[spellID] = copy
        end
    end
    return result
end

 
splitVariant = function(canonical, npcID)
    local npc = getNPC(canonical)
    if not npc then return nil, "INVALID" end
    if not next(npc.variants) then return true end
    if count(db.npcs) >= MAX_NPCS then return nil, "FULL" end
    if canonical ~= npcID then
        local identity = npc.variants[npcID]
        if not identity then return nil, "INVALID" end
        db.npcs[npcID] = copyObserved(npc, identity)
        npc.variants[npcID] = nil
    else
        local first
        for variantID in pairs(npc.variants) do if not first or variantID < first then first = variantID end end
        local replacement = copyObserved(npc, npc.variants[first])
        for variantID, identity in pairs(npc.variants) do
            if variantID ~= first then replacement.variants[variantID] = identity end
        end
        db.npcs[first], npc.variants = replacement, {}
    end
    return true
end

local function matchingGroup(identity, spells)
    if not identity.creatureType or identity.creatureType == "" or identity.classification ~= "normal" then return nil end
    local selected
    local spellCount = count(spells)
    for npcID, npc in pairs(db.npcs) do
        local sameAppearance = identity.displayID and identity.displayID == npc.displayID
        local normalVariants = identity.classification == "normal" and npc.classification == "normal" and spellCount >= 2
        local appearanceMismatch = identity.displayID and npc.displayID and identity.displayID ~= npc.displayID
        if npc.source == "combat" and not appearanceMismatch and (sameAppearance or normalVariants)
            and npc.creatureType == identity.creatureType and npc.classification == identity.classification
            and count(npc.variants) < MAX_VARIANTS - 1 and count(npc.abilities) == spellCount then
            local matches = true
            for spellID, ability in pairs(npc.abilities) do
                if not spells[spellID] or not ability.observed or ability.edited
                    or ability.reviewed or ability.evidence.manual then matches = false; break end
            end
            if matches and (not selected or npcID < selected) then selected = npcID end
        end
    end
    return selected
end

function archive.CommitObservation(record)
    if not db then return nil, "NOT_READY" end
    if type(record) ~= "table" or not id(record.id) or type(record.abilities) ~= "table" then return nil, "INVALID" end
    local name, spells, scanned = text(record.name, 120), {}, 0
    if not name or name == "" then return nil, "INVALID" end
    for index, spellID in pairs(record.abilities) do
        scanned = scanned + 1
        if scanned > MAX_ABILITIES or not id(index) or index > MAX_ABILITIES or not id(spellID) then return nil, "INVALID" end
        spells[spellID] = true
    end
    if scanned == 0 then return nil, "NO_CAST" end
    local identity = cleanIdentity(record)
    local canonical, variantKey = archive.ResolveCreatureNPCID(record.id)
    local npc = canonical and db.npcs[canonical]
    if npc then
        local total, changed = count(npc.abilities), false
        for spellID in pairs(spells) do
            if not npc.abilities[spellID] then total, changed = total + 1, true end
        end
        if total > MAX_ABILITIES then return nil, "FULL" end
        changed = changed or (identity.displayID and npc.displayID and identity.displayID ~= npc.displayID)
            or (identity.creatureType and npc.creatureType and identity.creatureType ~= npc.creatureType)
            or (identity.classification and npc.classification and identity.classification ~= npc.classification)
        if changed and next(npc.variants) then
            local splitID = variantKey or canonical
            local ok, err = splitVariant(canonical, splitID)
            if not ok then return nil, err end
            canonical, npc, variantKey = splitID, db.npcs[splitID], nil
        end
    else
        canonical = matchingGroup(identity, spells)
        npc = canonical and db.npcs[canonical]
        if npc then
            local key = archive.ResolveNPCID(record.id) and freeArchiveID() or record.id
            npc.variants[key] = { id = key, creatureID = record.id, name = name, lastSeen = timestamp() }
            variantKey = key
        else
            if count(db.npcs) >= MAX_NPCS then return nil, "FULL" end
            canonical = archive.ResolveNPCID(record.id) and freeArchiveID() or record.id
            npc = { id = canonical, creatureID = record.id, name = name, source = "combat",
                abilities = {}, variants = {}, spellIDs = {} }
            db.npcs[canonical] = npc
        end
    end
    if not variantKey then
        npc.name = name
        npc.creatureID = record.id
        if identity.displayID then npc.displayID = identity.displayID end
        if identity.creatureType then npc.creatureType = identity.creatureType end
        if identity.classification then npc.classification = identity.classification end
    else
        npc.variants[variantKey].name, npc.variants[variantKey].lastSeen = name, timestamp()
    end
    npc.lastSeen = timestamp()
    for spellID in pairs(spells) do observe(npc, spellID, "combat") end
    archive.Notify()
    return canonical
end

function archive.MakeDraft(spellID, engine)
    local presets = addon.SpellCreationPresets
    local cast = ""
    if type(engine.castTime) == "number" then
        local ms = engine.castTime
        local selection = ms == 0 and { ["0"] = true }
            or ms <= 3000 and { ["0"] = true, ["1"] = true }
            or ms <= 6000 and { ["1"] = true, ["2"] = true }
            or { ["3"] = true }
        cast = presets.FormatTimeSelection(presets.GetCastTimes("rounds"), selection, "rounds", "cast")
    end
    local range = ""
    if engine.maxRange and engine.maxRange > 0 then
        range = (engine.minRange and engine.minRange > 0 and (engine.minRange .. "-") or "")
            .. engine.maxRange .. " yd"
    end
    return { name = engine.name or ("Spell " .. spellID), icon = engine.icon or "", kind = "",
        resource = engine.resource or "", range = range, castTime = cast, description = "" }
end

 
function archive.MetadataToken(npcID, spellID) return getAbility(npcID, spellID) end
function archive.SetMetadata(npcID, spellID, token, engine, status)
    local ability = getAbility(npcID, spellID)
    if not ability or ability ~= token then return false end
    ability.status = status
    if engine then
        ability.engine = clone(engine)
        if not ability.edited and not ability.reviewed then ability.rp = archive.MakeDraft(spellID, engine) end
    end
    archive.Notify()
    return true
end

function archive.SaveDraft(npcID, spellID, data)
    local ability = getAbility(npcID, spellID)
    local rp = cleanRP(data)
    if not ability or not rp then return nil, "INVALID" end
    ability.rp, ability.edited, ability.reviewed = rp, true, false
    archive.Notify()
    return true
end

local function spellData(ability)
    local rp = ability.rp
    local tags = { [addon.Constants.SPELL_TAG_KIND] = rp.kind }
    if rp.kind == "magic" then tags[addon.Constants.MAGIC_TAG_ENABLED] = "true" end
    return { name = rp.name, icon = rp.icon, description = rp.description,
        resource = rp.resource, range = rp.range, castTime = rp.castTime, tags = tags }
end

function archive.Review(npcID, spellID, confirmed)
    local ability = getAbility(npcID, spellID)
    if not ability or confirmed ~= true then return nil, "INVALID" end
    if ability.rp.kind == "" or ability.rp.description == "" then return nil, "NEED_REVIEW" end
    local ok = addon.Validators.ValidateSpell(spellData(ability))
    if not ok then return nil, "INVALID" end
    ability.reviewed = true
    archive.Notify()
    return true
end

function archive.CopyToSpellbook(npcID, spellID, tabID)
    local ability = getAbility(npcID, spellID)
    if not ability or not ability.reviewed then return nil, "NEED_REVIEW" end
    return addon.Database.CreateSpell(tabID, spellData(ability))
end

function archive.DeleteAbility(npcID, spellID)
    local npc = getNPC(npcID)
    if not npc or not id(spellID) then return nil, "INVALID" end
    npc.abilities[spellID] = nil
    archive.Notify()
    return true
end

 
function archive.GetIdentityToken(npcID)
    local npc = getNPC(npcID)
    if not npc then return nil end
    if not identityTokens[npc] then
        nextIdentityToken = nextIdentityToken + 1
        identityTokens[npc] = nextIdentityToken
    end
    return identityTokens[npc]
end

function archive.DeleteNPC(npcID, expectedToken)
    if not getNPC(npcID) or (expectedToken ~= nil and archive.GetIdentityToken(npcID) ~= expectedToken) then
        return nil, "INVALID"
    end
    db.npcs[npcID] = nil
    archive.Notify()
    return true
end

 
function archive.ValidateTransferNPC(value)
    if type(value) ~= "table" or not id(value.id) or not text(value.name, 120)
        or text(value.name, 120) == "" or (value.source ~= nil and value.source ~= "target" and value.source ~= "combat" and value.source ~= "authored")
        or (value.profileEdited ~= nil and type(value.profileEdited) ~= "boolean") then return nil end
    local result = { id = value.id, name = text(value.name, 120), source = value.source or "target",
        creatureID = creatureIdentity(value),
        abilities = {}, variants = {}, profileEdited = value.profileEdited == true }
    if result.source == "authored" then
        if value.creatureID ~= nil or value.displayID ~= nil or value.lastSeen ~= nil
            or value.variants ~= nil and (type(value.variants) ~= "table" or next(value.variants) ~= nil) then return nil end
    elseif not id(result.creatureID) or (value.creatureID ~= nil and not id(value.creatureID)) then return nil end
    for _, key in ipairs({ "lastSeen", "displayID", "creatureType", "classification" }) do
        local item = value[key]
        if item ~= nil then
            local valid = key == "lastSeen" and cleanTime(item) or key == "displayID" and (id(item) and item)
                or (key == "creatureType" or key == "classification") and text(item, key == "creatureType" and 80 or 20)
            if not valid then return nil end
            result[key] = valid
        end
    end
    if value.abilities ~= nil and type(value.abilities) ~= "table" then return nil end
    local total = 0
    for spellID, ability in pairs(value.abilities or {}) do
        total = total + 1
        if total > MAX_ABILITIES or not id(spellID) or type(ability) ~= "table"
            or (ability.spellID ~= nil and ability.spellID ~= spellID) then return nil end
        local rp = cleanRP(ability.rp)
        if not rp then return nil end
        for _, key in ipairs({ "edited", "reviewed", "observed" }) do
            if ability[key] ~= nil and type(ability[key]) ~= "boolean" then return nil end
        end
        local evidence = ability.evidence or {}
        if type(evidence) ~= "table" or (evidence.observed ~= nil and evidence.observed ~= "combat"
            and evidence.observed ~= "target-cast") or (evidence.lastObserved ~= nil and not cleanTime(evidence.lastObserved))
            or (evidence.manual ~= nil and not text(evidence.manual, 300)) then return nil end
        if ability.observed and not evidence.observed then return nil end
        if ability.reviewed and (rp.kind == "" or rp.description == "") then return nil end
        if ability.engine ~= nil and type(ability.engine) ~= "table" then return nil end
        local engine = ability.engine or {}
        for _, key in ipairs({ "name", "resource", "description" }) do
            if engine[key] ~= nil and not text(engine[key], key == "description" and 2000 or 80) then return nil end
        end
        if engine.icon ~= nil and not id(engine.icon) then return nil end
        if engine.capturedAt ~= nil and not cleanTime(engine.capturedAt) then return nil end
        for _, key in ipairs({ "castTime", "minRange", "maxRange" }) do
            local item = engine[key]
            if item ~= nil and (type(item) ~= "number" or item ~= item or item < 0 or item > 3600000) then return nil end
        end
        result.abilities[spellID] = { spellID = spellID, rp = rp, engine = cleanEngine(engine),
            evidence = clone(evidence), edited = ability.edited == true, reviewed = ability.reviewed == true,
            observed = ability.observed == true, status = "UNAVAILABLE" }
    end
    if value.variants ~= nil and type(value.variants) ~= "table" then return nil end
    total = 0
    for variantID, variant in pairs(value.variants or {}) do
        total = total + 1
        if total >= MAX_VARIANTS or not id(variantID) or variantID == value.id or type(variant) ~= "table"
            or variant.id ~= variantID or not text(variant.name, 120) or text(variant.name, 120) == ""
            or (variant.lastSeen ~= nil and not cleanTime(variant.lastSeen)) then return nil end
        local creatureID = variant.creatureID or variantID
        if not id(creatureID) or (variant.creatureID ~= nil and not id(variant.creatureID)) then return nil end
        result.variants[variantID] = { id = variantID, creatureID = creatureID,
            name = text(variant.name, 120), lastSeen = variant.lastSeen }
    end
    return result
end
