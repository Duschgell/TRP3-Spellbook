local _, addon = ...
addon.EffectDisplay = {}
local display = addon.EffectDisplay
local inspected = {}

function display.Text(value, limit)
    if type(value) ~= "string" then return "" end
    return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
        :gsub("[%c]", " "):gsub("%${", "$ {"):sub(1, limit or 2000)
end

function display.UnitPlayerID(unit)
    if type(UnitFullName) ~= "function" or type(UnitIsPlayer) ~= "function" then return nil end
    local function accessible(value)
        return type(canaccessvalue) ~= "function" or canaccessvalue(value)
    end
    local ok, result = pcall(function()
        local player = UnitIsPlayer(unit)
        if not accessible(player) or not player then return nil end
        local name, realm = UnitFullName(unit)
        if not accessible(name) or not accessible(realm) or type(name) ~= "string" or name == "" then return nil end
        if not realm or realm == "" then realm = GetNormalizedRealmName() end
        if not accessible(realm) or type(realm) ~= "string" then return nil end
        return name .. "-" .. realm
    end)
    return ok and result or nil
end

function display.IsSelf(player)
    local key = addon.Runtime.NormalizePlayerID(player)
    return key ~= nil and key == addon.Runtime.NormalizePlayerID(addon.GameMasterRoster.GetLocalPlayerID())
end

function display.Identity(player)
    local profile = addon.TRP3Bridge.GetRoleplayProfileInfo(player) or {}
    local first, last = display.Text(profile.firstName, 100), display.Text(profile.lastName, 100)
    local name = (first .. " " .. last):match("^%s*(.-)%s*$")
    if name == "" then name = display.Text(profile.rpName or player, 200) end
    local color = type(profile.color) == "string" and profile.color:gsub("#", "")
    return { name = name, title = display.Text(profile.title, 150),
        color = color and color:match("^%x%x%x%x%x%x$") and color or nil }
end

function display.RememberInspection(player, auras)
    local key = addon.Runtime.NormalizePlayerID(player)
    if not key or type(auras) ~= "table" then return end
    local entries = {}
    for index, aura in ipairs(auras) do
        if index > 32 then break end
        local base = type(aura) == "table" and type(aura.class) == "table" and aura.class.BA
        local persistent = type(aura) == "table" and aura.persistent
        if type(base) == "table" and type(persistent) == "table" then
            local expiry = persistent.expiry
            if expiry == nil or expiry == math.huge or (type(expiry) == "number" and expiry == expiry
                and expiry > addon.Runtime.GetTimestamp()) then
                entries[#entries + 1] = { id = "extended:" .. index, native = true,
                    expiresAt = expiry, spell = { name = display.Text(base.NA, 200),
                        description = display.Text(base.DE), icon = type(base.IC) == "string" and base.IC:match("^[%w_%-]+$") and base.IC or "INV_Misc_Book_09",
                        effects = { buff = base.HE == true, debuff = base.HE ~= true } } }
            end
        end
    end
    local count = 0
    for other, state in pairs(inspected) do
        if state.untilTime <= addon.Runtime.GetTimestamp() then inspected[other] = nil else count = count + 1 end
    end
    if count >= 40 and not inspected[key] then return end
    inspected[key] = { entries = entries, untilTime = addon.Runtime.GetTimestamp() + 300 }
end

function display.List(player)
    if not player then return {} end
    local entries, seen = {}, {}
    for _, entry in pairs(addon.TimedEffects.GetSnapshot(player)) do
        if entry.combat or entry.expiresAt > addon.Runtime.GetTimestamp() then
            local identity = (entry.source or "") .. "\031" .. entry.spell.id
            seen[identity] = true
            entries[#entries + 1] = entry
        end
    end
    local gm = addon.GameMasterService
    for _, entry in ipairs(gm.GetActiveBuffsForPlayer(player) or {}) do
        if entry.spell then
            local identity = entry.sourcePlayerKey .. "\031" .. entry.spell.id
            if not seen[identity] and not (display.IsSelf(player) and addon.TimedEncounterEffects.IsDismissed(entry.sourcePlayerKey, entry.spell.id, entry)) then
                entries[#entries + 1] = { id = "combat:" .. identity, source = entry.sourcePlayerKey,
                    spell = entry.spell, combat = true, roundEffect = true, expiresAt = entry.expiresAt,
                    expiresRound = entry.expiresRound, sourceRoundID = entry.sourceRoundID, appliedAt = entry.appliedAt,
                    hidden = entry.hidden == true }
                seen[identity] = true
            end
        end
    end
    local nativeReady = true
    if display.IsSelf(player) then
        local extended = _G.TRP3_API and TRP3_API.extended
        local auras = extended and extended.auras
        if auras then
            local nativeEntries = {}
            local ok = pcall(function()
                local count = auras.getCount()
                if type(count) ~= "number" or count ~= count or count < 0 or count == math.huge or count % 1 ~= 0 then
                    error("Invalid native aura count")
                end
                for index = 1, math.min(64, count) do
                    local id = auras.getId(index)
                    local class = extended.getClass(id)
                    local base = class and class.BA
                    if base and not class.rpsbOwner then
                        local duration = auras.getDuration(id)
                        nativeEntries[#nativeEntries + 1] = { id = "native:" .. id, native = true, nativeID = id,
                            cancellable = base.CC == true, public = base.WE == true, expiresAt = addon.Runtime.GetTimestamp() + duration,
                            spell = { name = display.Text(base.NA, 200), description = display.Text(base.DE),
                                icon = base.IC, effects = { buff = base.HE == true, debuff = base.HE ~= true } } }
                    end
                end
            end)
            nativeReady = ok
            if ok then for _, entry in ipairs(nativeEntries) do entries[#entries + 1] = entry end end
        end
    else
        local snapshot = inspected[addon.Runtime.NormalizePlayerID(player)]
        if snapshot and snapshot.untilTime > addon.Runtime.GetTimestamp() then
            local known = {}
            for _, entry in ipairs(entries) do known[entry.spell.name .. tostring(entry.spell.effects.debuff == true)] = true end
            snapshot.mirrored = snapshot.mirrored or {}
            for _, entry in ipairs(snapshot.entries) do
                local identity = entry.spell.name .. tostring(entry.spell.effects.debuff == true)
                if known[identity] then snapshot.mirrored[identity] = true end
            end
            for _, entry in ipairs(snapshot.entries) do
                if not snapshot.mirrored[entry.spell.name .. tostring(entry.spell.effects.debuff == true)]
                    and (not entry.expiresAt or entry.expiresAt > addon.Runtime.GetTimestamp()) then entries[#entries + 1] = entry end
            end
        end
    end
    table.sort(entries, function(a, b)
        local aDebuff, bDebuff = a.spell.effects.debuff == true, b.spell.effects.debuff == true
        if aDebuff ~= bDebuff then return not aDebuff end
        return a.id < b.id
    end)
    return entries, nativeReady
end

function display.PublicEntries(viewer, viewerProfile)
    local player, result = addon.GameMasterRoster.GetLocalPlayerID(), {}
    for _, entry in ipairs(display.List(addon.GameMasterRoster.GetLocalPlayerID())) do
        if not entry.pending and (not entry.native or entry.public)
            and (not entry.hidden or (addon.EffectVisibility and addon.EffectVisibility.CanSee(entry, viewer, viewerProfile))) then
            local spell = entry.spell
            if entry.native then spell = { id = "native" .. (#result + 1), name = spell.name,
                description = spell.description, icon = spell.icon, effects = spell.effects, tags = {} } end
            local permanent = not entry.combat and entry.expiresAt == math.huge
            local cleaned = addon.TimedEffectsStore.ValidateEntry({ id = entry.hidden and entry.id or "display" .. (#result + 1), hidden = entry.hidden,
                source = entry.source or player, spell = spell,
                expiresAt = (entry.combat or permanent) and addon.Runtime.GetTimestamp() + 86400 or entry.expiresAt })
            if cleaned then
                cleaned.combat, cleaned.permanent = entry.combat == true, permanent
                result[#result + 1] = cleaned
            end
            if #result >= 32 then break end
        end
    end
    return result
end

function display.Remove(entry)
    if type(entry) ~= "table" then return false end
    if entry.native then
        local auras = _G.TRP3_API and TRP3_API.extended and TRP3_API.extended.auras
        return entry.nativeID and entry.cancellable and auras and auras.cancel(entry.nativeID) or false
    end
    if entry.roundEffect then return addon.TimedEncounterEffects.Dismiss(entry.source, entry.spell.id, entry) end
    return addon.TimedEffects.Remove(entry.id)
end
