local _, addon = ...
addon.EffectVisibility = {}
local privacy = addon.EffectVisibility
local initialized = setmetatable({}, { __mode = "k" })
local normalizedSnapshots = setmetatable({}, { __mode = "k" })
local MAX_SHARES, MAX_READERS, MAX_REMOTES = 128, 256, 128
local MAX_READER_BYTES = 20000
local function now() return addon.Runtime.GetTimestamp() end
local function key(player) return addon.Runtime.NormalizePlayerID(player) end
local function valid(value) return addon.Runtime.IsSafeIdentifier(value, 200) end
local function count(value) return addon.Runtime.CountEntries(value) end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for field, item in pairs(value) do result[field] = copy(item) end
    return result
end

local function cachedEntries(snapshot)
    local state = normalizedSnapshots[snapshot]
    if not state or state.entries ~= snapshot.entries then
        local entries = {}
        for _, entry in ipairs(type(snapshot.entries) == "table" and snapshot.entries or {}) do
            if #entries >= 32 then break end
            local clean = addon.TimedEffectsStore.ValidateEntry(entry)
            if clean and clean.hidden and not entry.combat then entries[#entries + 1] = clean end
        end
        snapshot.entries = entries
        state = { entries = entries, deadline = 0 }
        normalizedSnapshots[snapshot] = state
    end
    if now() >= state.deadline then
        state.deadline = math.huge
        for index = #state.entries, 1, -1 do
            local entry = state.entries[index]
            if entry.expiresAt <= now() then table.remove(state.entries, index)
            else state.deadline = math.min(state.deadline, entry.expiresAt) end
        end
    end
    return state.entries
end

function privacy.Profile()
     
    local bridge = addon.TRP3Bridge
    local id = bridge and bridge.GetActiveProfileID and bridge.GetActiveProfileID()
    return valid(id) and "trp3_profile:" .. id or addon.Database.GetActiveProfileKey()
end

function privacy.ReaderKey(player, profile)
    player = key(player)
    if valid(player) and valid(profile) then return player .. "\031" .. profile end
end

function privacy.CleanReaders(value)
    local result, total, bytes = {}, 0, 0
    for identity, allowed in pairs(type(value) == "table" and value or {}) do
        if total >= MAX_READERS then break end
        local player, profile
        if type(identity) == "string" then player, profile = identity:match("^([^\031]+)\031([^\031]+)$") end
        if allowed == true and privacy.ReaderKey(player, profile) == identity and bytes + #identity <= MAX_READER_BYTES then
            result[identity], total = true, total + 1
            bytes = bytes + #identity
        end
    end
    return result
end

local function data()
    local profile = addon.Database.GetActiveProfileData()
    if not profile then return nil end
    if type(profile.effectVisibility) ~= "table" then profile.effectVisibility = {} end
    local state = profile.effectVisibility
    for _, field in ipairs({ "shares", "readers", "received", "cache" }) do
        if type(state[field]) ~= "table" then state[field] = {} end
    end
    if not initialized[state] then
        local limits = { shares = MAX_SHARES, readers = 64, received = MAX_REMOTES, cache = MAX_REMOTES }
        for field, limit in pairs(limits) do
            local kept = 0
            for id, record in pairs(state[field]) do
                if kept >= limit or not valid(id) or type(record) ~= "table" then state[field][id] = nil
                else kept = kept + 1 end
            end
        end
        for id, readers in pairs(state.readers) do state.readers[id] = privacy.CleanReaders(readers) end
        state.serial = tonumber(state.serial) or 0
        if state.serial < 0 or state.serial ~= state.serial or state.serial > 1e12 then state.serial = 0 end
        initialized[state] = true
    end
    return state
end

local function ownEntries()
    local entries = {}
    for _, entry in ipairs(addon.TimedEffectsStore.List()) do entries[entry.id] = entry end
    if addon.TimedEncounterEffects then
        for _, entry in ipairs(addon.TimedEncounterEffects.List()) do entries[entry.id] = entry end
    end
    return entries
end

function privacy.Prune()
    local state = data()
    if not state then return end
    local active = ownEntries()
    for id in pairs(state.readers) do if not active[id] then state.readers[id] = nil end end
    for token, share in pairs(state.shares) do
        local ids = {}
        for _, id in ipairs(type(share.ids) == "table" and share.ids or {}) do
            if #ids >= 32 then break end
            if active[id] and active[id].hidden then ids[#ids + 1] = id end
        end
        if #ids == 0 then state.shares[token] = nil else share.ids = ids end
    end
    for token, receipt in pairs(state.received) do
        if not valid(receipt.sender) or type(receipt.expiresAt) ~= "number"
            or receipt.expiresAt ~= receipt.expiresAt or receipt.expiresAt <= now()
            or receipt.expiresAt > now() + 86400 then state.received[token] = nil end
    end
    for player, snapshot in pairs(state.cache) do
        if not valid(snapshot.profile) or #cachedEntries(snapshot) == 0 then state.cache[player] = nil end
    end
end

function privacy.Audience(id)
    local state = data()
    return state and privacy.CleanReaders(state.readers[id]) or {}
end

function privacy.CanSee(entry, player, profile)
    if not entry.hidden then return true end
    if key(player) == key(addon.GameMasterRoster.GetLocalPlayerID())
        and profile == privacy.Profile() then return true end
    local identity, state = privacy.ReaderKey(player, profile), data()
    return identity ~= nil and state ~= nil and type(state.readers[entry.id]) == "table"
        and state.readers[entry.id][identity] == true
end

 
function privacy.PrepareLink(snapshot, effectID)
    privacy.Prune()
    local state, ids = data(), {}
    if not state then return nil end
    for id, entry in pairs(ownEntries()) do
        if entry.hidden and ((effectID and id == effectID) or (not effectID
            and entry.spell.id == snapshot.spellId and entry.spell.ownerKey == snapshot.owner)) then ids[#ids + 1] = id end
    end
    if #ids == 0 then return nil end
    if count(state.shares) >= MAX_SHARES then return false end
    state.serial = state.serial + 1
    local name = addon.ChatLinks.EncodeTransportName(snapshot.spell.name, 90)
    local stem = name .. string.format("-rpsba-%d-%d-%08x", now(), state.serial, math.random(1, 2147483646))
    return { stem = stem, ids = ids, profile = addon.Database.GetActiveProfileKey() }
end

function privacy.BindLink(prepared, link)
    if not prepared then return true end
    local token = type(link) == "string" and link:match("^%[TRP3:([^%]]+)%]$")
    local state = data()
    if not state or prepared.profile ~= addon.Database.GetActiveProfileKey() or not valid(token)
        or token:sub(1, #prepared.stem + 1) ~= prepared.stem .. ":" then return false end
    state.shares[token] = { ids = prepared.ids, sent = false }
    return true
end

function privacy.MarkSent(token)
    local state = data()
    if not state or not valid(token) then return end
    if state.shares[token] then state.shares[token].sent = true; return end
     
    local stem = token:match("^(.*):%d+$")
    if not stem or count(state.shares) >= MAX_SHARES then return end
    for previous, share in pairs(state.shares) do
        if previous:match("^(.*):%d+$") == stem then
            state.shares[token] = { ids = share.ids, sent = true }
            return
        end
    end
end

function privacy.Grant(token, player, profile)
    privacy.Prune()
    local state, identity = data(), privacy.ReaderKey(player, profile)
    local share = state and state.shares[token]
    if not identity or not share or share.sent ~= true then return false end
    for _, id in ipairs(share.ids) do
        local readers = state.readers[id] or {}
        local bytes = #identity
        for reader in pairs(readers) do bytes = bytes + #reader end
        if not readers[identity] and (count(readers) >= MAX_READERS or bytes > MAX_READER_BYTES) then return false end
    end
    for _, id in ipairs(share.ids) do
        state.readers[id] = state.readers[id] or {}
        state.readers[id][identity] = true
    end
    return true
end

function privacy.ReceiveChat(player, token)
    local state = data()
    if not state or not valid(player) or not valid(token) or not token:match("%-rpsba%-%d+%-%d+%-%x+:%d+$") then return false end
    local receipt = state.received[token]
    if receipt then return key(receipt.sender) == key(player) end
    if count(state.received) >= MAX_REMOTES then return false end
    state.received[token] = { sender = player, expiresAt = now() + 86400 }
    return true
end

function privacy.Receipts()
    local state = data()
    return state and state.received or {}
end

function privacy.Remember(player, ownerProfile, entries)
    local state, playerKey = data(), key(player)
    if not state or not playerKey then return end
    if not valid(ownerProfile) then state.cache[playerKey] = nil; return end
    for _, receipt in pairs(state.received) do
        if key(receipt.sender) == playerKey and receipt.ownerProfile == ownerProfile then receipt.pendingView = nil end
    end
    local result = {}
    for _, entry in ipairs(entries) do if entry.hidden and not entry.combat then result[#result + 1] = entry end end
    if #result == 0 then state.cache[playerKey] = nil
    elseif state.cache[playerKey] or count(state.cache) < MAX_REMOTES then
        state.cache[playerKey] = { profile = ownerProfile, readerProfile = privacy.Profile(), player = player, entries = result }
         
        cachedEntries(state.cache[playerKey])
    end
end

function privacy.Cached(player)
    local state = data()
    local snapshot = state and state.cache[key(player)]
    if not snapshot or not valid(snapshot.profile) or snapshot.readerProfile ~= privacy.Profile() then return {} end
    local known = addon.TRP3Bridge.GetPlayerProfileKey and addon.TRP3Bridge.GetPlayerProfileKey(valid(snapshot.player) and snapshot.player or player)
    if known and known ~= snapshot.profile then return {} end
    local result = {}
    for _, entry in ipairs(cachedEntries(snapshot)) do result[#result + 1] = copy(entry) end
    return result
end

 
function privacy.FilterCombat(states, player, profile, publicOnly)
    local result, identity = {}, privacy.ReaderKey(player, profile)
    for _, state in ipairs(states or {}) do
        local buffs = {}
        for _, entry in ipairs(state.buffs or {}) do
            if not entry.hidden or (not publicOnly
                and ((key(state.playerKey) == key(player) and entry.ownerProfile == profile)
                    or (identity and entry.readers and entry.readers[identity]))) then
                local clean = {}
                for field, value in pairs(entry) do if field ~= "readers" then clean[field] = value end end
                buffs[#buffs + 1] = clean
            end
        end
        if #buffs > 0 then result[#result + 1] = { playerKey = state.playerKey, buffs = buffs } end
    end
    return result
end
