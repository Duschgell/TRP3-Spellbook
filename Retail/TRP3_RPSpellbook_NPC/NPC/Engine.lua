local _, private = ...
local addon = private.Shared or private
local archive = addon.NPCArchive
local pending, cache, cacheOrder = {}, {}, {}
local pendingCount, windowStart, requestCount = 0, 0, 0

 
local function accessible(value)
    if type(issecretvalue) ~= "function" then return false end
    if issecretvalue(value) then return false end
    if type(canaccessvalue) == "function" and not canaccessvalue(value) then return false end
    return true
end

local function number(value, maximum)
    if not accessible(value) or type(value) ~= "number" then return nil end
    if value ~= value or value < 0 or value > maximum then return nil end
    return value
end

local function spellID(value)
    local result = number(value, 2147483647)
    if not result or result == 0 or result ~= math.floor(result) then return nil end
    return result
end

local function plain(value, limit)
    if not accessible(value) or type(value) ~= "string" then return nil end
     
    local result = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|", ""):gsub("[%z\1-\8\11-\31\127]", "")
    if #result > limit then return nil end
    return result
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil, "UNAVAILABLE" end
    local ok, value = pcall(fn, ...)
    if not ok then return nil, "UNAVAILABLE" end
    if not accessible(value) then return nil, "SECRET" end
    return value
end

local function field(value, key)
    if not accessible(value) or type(value) ~= "table" then return nil end
    if type(canaccesstable) == "function" and not canaccesstable(value) then return nil end
    local ok, result = pcall(function() return value[key] end)
    if not ok or not accessible(result) then return nil end
    return result
end

local function unitToken(value)
    if not accessible(value) or type(value) ~= "string" then return nil end
    if value == "target" or (#value <= 18 and value:match("^nameplate[1-9]%d*$")) then return value end
end

local function identity(unit, allowPeaceful)
    if call(UnitExists, unit) ~= true or call(UnitIsPlayer, unit) ~= false
        or call(UnitPlayerControlled, unit) ~= false
        or (not allowPeaceful and call(UnitIsDeadOrGhost, unit) ~= false)
        or (not allowPeaceful and (call(UnitIsEnemy, "player", unit) ~= true
            or call(UnitCanAttack, "player", unit) ~= true)) then
        return nil, "TARGET"
    end
    if C_Secrets and type(C_Secrets.ShouldUnitIdentityBeSecret) == "function"
        and call(C_Secrets.ShouldUnitIdentityBeSecret, unit) ~= false then
        return nil, "SECRET"
    end
    local value, err = call(UnitCreatureID, unit)
    local creatureID = spellID(value)
    if not creatureID then return nil, err or "SECRET" end
    local name = plain(call(UnitName, unit), 120)
    if not creatureID or not name or name == "" then return nil, "SECRET" end
    return creatureID, name
end

local function target() return identity("target", true) end

local function appearance(unit)
     
     
    return { creatureType = plain(call(UnitCreatureType, unit), 80),
        classification = plain(call(UnitClassification, unit), 20) }
end

local function resolveNPCID(value)
    local id = spellID(value)
    if not id then return nil end
    if type(archive.ResolveNPCID) == "function" then return spellID(archive.ResolveNPCID(id)) end
    return id
end

local function archiveIdentity(npcID)
    if type(archive.GetIdentity) == "function" then return archive.GetIdentity(npcID) end
    return archive.Get(npcID)
end

 
archive.EngineRead = { Accessible = accessible, ID = spellID, Call = call,
    UnitToken = unitToken, ResolveNPCID = resolveNPCID, GetIdentity = archiveIdentity }

function archive.ReadCombatObservation(value, spellValue)
    if not accessible(value) or not accessible(spellValue) then return nil, "SECRET" end
    local unit, spell = unitToken(value), spellID(spellValue)
    if not unit then return nil, "TARGET" end
    if not spell then return nil, "INVALID" end
    local fighting, combatError = call(UnitAffectingCombat, unit)
    if fighting ~= true then return nil, combatError or "TARGET" end
    local npcID, name = identity(unit)
    if not npcID then return nil, name end
    local details = appearance(unit)
    local checkID, checkName = identity(unit)
    if checkID ~= npcID or checkName ~= name then return nil, "TARGET" end
    return { id = npcID, name = name, creatureType = details.creatureType,
        classification = details.classification, abilities = { spell } }
end

local STOCK_PORTRAIT = "Interface\\CharacterFrame\\TemporaryPortrait-Monster"

local function objectMethod(object, key)
    if not accessible(object) then return nil end
    local kind = type(object)
    if kind ~= "table" and kind ~= "userdata" then return nil end
    if kind == "table" and type(canaccesstable) == "function" and not canaccesstable(object) then return nil end
    local ok, method = pcall(function() return object[key] end)
    if ok and accessible(method) and type(method) == "function" then return method end
end

function archive.ApplyPortrait(texture, value)
    local setTexture = objectMethod(texture, "SetTexture")
    if type(setTexture) ~= "function" then return false, "FALLBACK" end
    pcall(setTexture, texture, STOCK_PORTRAIT)
    local npcID = resolveNPCID(value)
    local npc = npcID and archiveIdentity(npcID)
    if not npc or npc.source == "authored" then return false, "FALLBACK" end
    local liveID = target()
    if liveID and (liveID == (npc.creatureID or npc.id)
        or (archive.ResolveCreatureNPCID and archive.ResolveCreatureNPCID(liveID) == npcID))
        and type(SetPortraitTexture) == "function"
        and (type(IsUnitModelReadyForUI) ~= "function" or call(IsUnitModelReadyForUI, "target") == true) then
        local ok = pcall(SetPortraitTexture, texture, "target")
        if ok and target() == liveID then return true, "TARGET" end
        pcall(setTexture, texture, STOCK_PORTRAIT)
    end
    local displayID = spellID(field(npc, "displayID"))
    if displayID and type(SetPortraitTextureFromCreatureDisplayID) == "function" then
        local ok = pcall(SetPortraitTextureFromCreatureDisplayID, texture, displayID)
        if ok then return true, "DISPLAY" end
        pcall(setTexture, texture, STOCK_PORTRAIT)
    end
    return false, "FALLBACK"
end

local powerPresets = {
    MANA = "mana", RAGE = "rage", FOCUS = "focus", ENERGY = "energy",
    RUNIC_POWER = "runic_power", SOUL_SHARDS = "soul_shards", HOLY_POWER = "holy_power",
    MAELSTROM = "maelstrom", ARCANE_CHARGES = "arcane_charges",
}

local function resource(spell)
    local costs = call(C_Spell and C_Spell.GetSpellPowerCost, spell)
    local found, labels = {}, {}
    for index = 1, 8 do
        local cost = field(costs, index)
        if not cost then break end
        local name = plain(field(cost, "name"), 80)
        local key = name and powerPresets[name]
        if key and not found[key] then
            for _, kind in ipairs({ "magic", "ability" }) do
                for _, option in ipairs(addon.SpellCreationPresets.GetResources(kind)) do
                    if option.value == key then labels[#labels + 1] = option.label end
                end
            end
            found[key] = true
        elseif not key and name and name:match("^[A-Z_]+$") and not found[name] then
            labels[#labels + 1] = plain(_G[name], 80) or name
            found[name] = true
        end
    end
    local result = table.concat(labels, ", ")
    return #result <= 80 and result or ""
end

local function metadata(spell)
    if C_Spell and type(C_Spell.IsSpellDataCached) == "function"
        and call(C_Spell.IsSpellDataCached, spell) ~= true then return nil end
    local info = call(C_Spell and C_Spell.GetSpellInfo, spell)
    local name = plain(field(info, "name"), 80)
    if not name or name == "" then return nil end
    return {
        name = name, icon = spellID(field(info, "originalIconID")) or spellID(field(info, "iconID")),
        castTime = number(field(info, "castTime"), 3600000),
        minRange = number(field(info, "minRange"), 100000), maxRange = number(field(info, "maxRange"), 100000),
        resource = resource(spell),
        description = plain(call(C_Spell and C_Spell.GetSpellDescription, spell), 2000) or "",
        source = "C_Spell", capturedAt = time(),
    }
end

local function now() return GetTime() end

local function remember(spell, data)
    if not cache[spell] then cacheOrder[#cacheOrder + 1] = spell end
    cache[spell] = { data = data, expires = now() + 60 }
    while #cacheOrder > 64 do cache[table.remove(cacheOrder, 1)] = nil end
end

local function finish(spell, request, data)
    if pending[spell] ~= request then return end
    pending[spell], pendingCount = nil, pendingCount - 1
    if data then remember(spell, data) end
    for _, waiter in ipairs(request.waiters) do
        archive.SetMetadata(waiter.npcID, spell, waiter.token, data, data and "READY" or "UNAVAILABLE")
    end
end

function archive.RequestMetadata(npcID, value)
    local spell = spellID(value)
    if not spell then return nil, "INVALID" end
    local token = archive.MetadataToken(npcID, spell)
    if not token then return nil, "INVALID" end
    local entry = cache[spell]
    if entry and entry.expires > now() then
        archive.SetMetadata(npcID, spell, token, entry.data, "READY")
        return true
    end
    local request = pending[spell]
    if request then
        for _, waiter in ipairs(request.waiters) do if waiter.token == token then return true end end
        if #request.waiters >= 50 then return nil, "BUSY" end
        request.waiters[#request.waiters + 1] = { npcID = npcID, token = token }
        archive.SetMetadata(npcID, spell, token, nil, "LOADING")
        return true
    end
    local data = metadata(spell)
    if data then
        remember(spell, data)
        archive.SetMetadata(npcID, spell, token, data, "READY")
        return true
    end
    if now() - windowStart >= 60 then windowStart, requestCount = now(), 0 end
    if pendingCount >= 16 or requestCount >= 32 then return nil, "BUSY" end
    if not C_Spell or type(C_Spell.RequestLoadSpellData) ~= "function"
        or not C_Timer or type(C_Timer.After) ~= "function" then return nil, "UNAVAILABLE" end
    request = { waiters = { { npcID = npcID, token = token } } }
    pending[spell], pendingCount, requestCount = request, pendingCount + 1, requestCount + 1
    archive.SetMetadata(npcID, spell, token, nil, "LOADING")
    C_Timer.After(8, function() finish(spell, request, nil) end)
    local ok = pcall(C_Spell.RequestLoadSpellData, spell)
    if not ok then finish(spell, request, nil); return nil, "UNAVAILABLE" end
    return true
end

function archive.OnSpellDataResult(value, success)
    local spell = spellID(value)
    if not spell or not accessible(success) or type(success) ~= "boolean" then return end
    local request = pending[spell]
    if request then finish(spell, request, success and metadata(spell) or nil) end
end

function archive.CaptureTarget()
    local npcID, name = target()
    if not npcID then return nil, name end
    local details = appearance("target")
    local reaction = number(call(UnitReaction, "target", "player"), 8)
    if reaction and reaction >= 1 and reaction == math.floor(reaction) then
        details.relationship = reaction <= 3 and "hostile" or reaction == 4 and "neutral" or "friendly"
    end
    details.area = plain(call(GetZoneText), 120)
    local checkID, checkName = target()
    if checkID ~= npcID or checkName ~= name then return nil, "TARGET" end
    local stored, err = archive.StoreTarget(npcID, name, details)
    if stored and type(archive.OnTargetCaptured) == "function" then
         
        pcall(archive.OnTargetCaptured, stored)
    end
    return stored, err
end

function archive.AddManual(npcID, value, note)
    if not accessible(value) then return nil, "INVALID" end
    local spell = type(value) == "string" and value:match("^%d+$") and tonumber(value) or value
    spell = spellID(spell)
    if not spell then return nil, "INVALID" end
    local stored, err = archive.StoreAbility(npcID, spell, "manual", note)
    if not stored then return nil, err end
    local ok, loadError = archive.RequestMetadata(npcID, spell)
    return spell, not ok and loadError or nil
end

local function currentSpell(fn, position)
    if type(fn) ~= "function" then return nil end
    local function extract(ok, ...)
        if not ok then return nil end
        return spellID(select(position, ...))
    end
    return extract(pcall(fn, "target"))
end

function archive.ObserveTarget(expectedNPC)
    local npcID, name = target()
    if not npcID then return nil, name end
    local canonical = archive.ResolveCreatureNPCID(npcID)
    if not canonical or canonical ~= resolveNPCID(expectedNPC) or not archiveIdentity(canonical) then return nil, "TARGET" end
    local spell = currentSpell(UnitCastingInfo, 9) or currentSpell(UnitChannelInfo, 8)
    if not spell then return nil, "NO_CAST" end
    local details = appearance("target")
    local checkID, checkName = target()
    if checkID ~= npcID or checkName ~= name then return nil, "TARGET" end
     
     
    local committed, commitError = archive.CommitObservation({ id = npcID, name = name,
        creatureType = details.creatureType, classification = details.classification, abilities = { spell } })
    if not committed then return nil, commitError end
    local stored, storeError = archive.StoreAbility(committed, spell, "target-cast")
    if not stored then return nil, storeError end
    local ok, loadError = archive.RequestMetadata(committed, spell)
    return spell, not ok and loadError or nil, committed
end
