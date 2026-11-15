local _, addon = ...

 
addon.TimedEffectsStore = {}
local store = addon.TimedEffectsStore
local MAX_EFFECTS, MAX_RECEIPTS = 32, 512
local normalizedTransfers = setmetatable({}, { __mode = "k" })
local normalizedRecords = setmetatable({}, { __mode = "k" })
local revision = 0

local function touch(data)
    revision = revision + 1
    local state = normalizedRecords[data]
    if state then state.deadline = 0 end
end

local function validID(value)
    return type(value) == "string" and #value > 0 and #value <= 160
        and not value:find("[%c|~]")
end
store.ValidID = validID

function store.ValidateSpell(value)
    if type(value) ~= "table" or not validID(value.id) or #value.id > 128 then return nil end
    local valid, spell = addon.Validators.ValidateSpell(value)
    if not valid or not spell.effects or not (spell.effects.buff or spell.effects.debuff) then return nil end
    spell.id = value.id
    spell.ownerKey = addon.Runtime.IsSafeIdentifier(value.ownerKey, 200) and value.ownerKey or "timed-effects"
    spell.revision = 1
    return spell
end

function store.ValidateEntry(value)
    if type(value) ~= "table" or not validID(value.id)
        or (value.hidden ~= nil and type(value.hidden) ~= "boolean") then return nil end
    local spell = store.ValidateSpell(value.spell)
    local source = addon.Runtime.NormalizePlayerID(value.source)
    local now = addon.Runtime.GetTimestamp()
    local expires = value.expiresAt
    if not spell or not source or type(expires) ~= "number" or expires ~= expires
        or expires <= now or expires > now + 86400 then return nil end
    return { id = value.id, source = source, spell = spell, expiresAt = math.floor(expires), hidden = value.hidden == true }
end

local function record()
    local profile = addon.Database.GetActiveProfileData()
    if not profile then return nil end
    if type(profile.timedEffects) ~= "table" then profile.timedEffects = {} end
    local data = profile.timedEffects
    if type(data.entries) ~= "table" then data.entries = {} end
    if type(data.receipts) ~= "table" then data.receipts = {} end
    local state = normalizedRecords[data]
    if state and state.entries == data.entries and state.receipts == data.receipts then
        local now = addon.Runtime.GetTimestamp()
        if now >= state.deadline then
            local deadline = math.huge
            for index = #data.entries, 1, -1 do
                local entry = data.entries[index]
                if entry.expiresAt <= now then table.remove(data.entries, index); revision = revision + 1
                else deadline = math.min(deadline, entry.expiresAt) end
            end
            for id, expires in pairs(data.receipts) do
                if expires <= now then data.receipts[id] = nil else deadline = math.min(deadline, expires) end
            end
            state.deadline = deadline
        end
        return data
    end
    local now, entries, receipts, count = addon.Runtime.GetTimestamp(), {}, {}, 0
    for _, entry in ipairs(data.entries) do
        if #entries >= MAX_EFFECTS then break end
        local cleaned = store.ValidateEntry(entry)
        if cleaned then entries[#entries + 1] = cleaned end
    end
    for id, expires in pairs(data.receipts) do
        if count < MAX_RECEIPTS and validID(id) and type(expires) == "number"
            and expires > now and expires <= now + 86520 then
            receipts[id], count = expires, count + 1
        end
    end
    data.entries, data.receipts = entries, receipts
    normalizedRecords[data] = { entries = entries, receipts = receipts, deadline = 0 }
    touch(data)
    return data
end

function store.Revision()
    record()
    return revision
end

function store.TransferChanged()
    revision = revision + 1
end

function store.List()
    local data = record()
    return data and data.entries or {}
end

function store.Remember(id, expires)
    local data = record()
    if not data or not validID(id) or type(expires) ~= "number" or expires ~= expires
        or expires <= addon.Runtime.GetTimestamp() or expires > addon.Runtime.GetTimestamp() + 86400 then return false end
    if data.receipts[id] then return false end
    local count = 0
    for _ in pairs(data.receipts) do count = count + 1 end
    if count >= MAX_RECEIPTS then return false end
    data.receipts[id] = expires + 120
    normalizedRecords[data].deadline = 0
    return true
end

function store.Accept(value)
    local entry = store.ValidateEntry(value)
    local data = record()
    if not entry or not data or data.receipts[entry.id] then return false end
    local replacement
    for index, old in ipairs(data.entries) do
        if old.source == entry.source and old.spell.id == entry.spell.id
            and (old.spell.ownerKey == entry.spell.ownerKey or old.spell.ownerKey == "timed-effects") then replacement = index end
    end
    if not replacement and #data.entries >= MAX_EFFECTS then return false end
    if not store.Remember(entry.id, entry.expiresAt) then return false end
    if replacement then
        local previous = data.entries[replacement]
        entry.id = previous.id
        entry.hidden = entry.hidden or previous.hidden
        entry.expiresAt = math.max(entry.expiresAt, previous.expiresAt)
        data.receipts[entry.id] = entry.expiresAt + 120
        data.entries[replacement] = entry
    else data.entries[#data.entries + 1] = entry end
    touch(data)
    return true
end

function store.Remove(id)
    local data = record()
    if not data then return false end
    for index, entry in ipairs(data.entries) do
        if entry.id == id then
            table.remove(data.entries, index)
            touch(data)
            return true
        end
    end
    return false
end

function store.RestoreTransferred(transfer)
    local data = record()
    local entry = type(transfer) == "table" and transfer.entry
    if not data or type(entry) ~= "table" or type(data.transfers) ~= "table"
        or data.transfers[entry.id] ~= transfer or not transfer.acknowledged or transfer.removed then return false end
    for _, current in ipairs(data.entries) do
        if current.id == entry.id then return true end
    end
     
     
    local cleaned = store.ValidateEntry(entry)
    if not cleaned or not data.receipts[entry.id] or #data.entries >= MAX_EFFECTS then return false end
    data.entries[#data.entries + 1] = cleaned
    touch(data)
    return true
end

function store.AllowsOffers()
    local data = record()
    return data and data.blockOffers ~= true
end

function store.SetAllowsOffers(allowed)
    local data = record()
    if data then data.blockOffers = not allowed end
end

 
function store.Transfers()
    local data = record()
    if not data then return {} end
    if type(data.transfers) ~= "table" then data.transfers = {} end
    if not normalizedTransfers[data.transfers] then
        local count = 0
        for id, transfer in pairs(data.transfers) do
            local entry = type(transfer) == "table" and transfer.entry
            local spell = type(entry) == "table" and store.ValidateSpell(entry.spell)
            if count >= MAX_EFFECTS or not validID(id) or not spell
                or entry.id ~= id or type(entry.expiresAt) ~= "number" or entry.expiresAt ~= entry.expiresAt
                or entry.expiresAt == math.huge
                or (entry.hidden ~= nil and type(entry.hidden) ~= "boolean")
                or not addon.Runtime.NormalizePlayerID(entry.source)
                or not validID(transfer.activationID) or not validID(transfer.sessionID)
                or not addon.Runtime.NormalizePlayerID(transfer.gameMaster) then
                data.transfers[id] = nil
            else
                count = count + 1
                entry.spell = spell
                entry.source = addon.Runtime.NormalizePlayerID(entry.source)
                transfer.gameMaster = addon.Runtime.NormalizePlayerID(transfer.gameMaster)
                transfer.removed, transfer.acknowledged = transfer.removed == true, transfer.acknowledged == true
                transfer.terminal = transfer.terminal == true
                local attempts, nextAttempt = transfer.attempts, transfer.nextAttempt
                transfer.attempts = type(attempts) == "number" and attempts % 1 == 0 and attempts >= 0 and math.min(6, attempts) or 0
                if transfer.attempts >= 6 and not transfer.acknowledged then transfer.terminal = true end
                transfer.nextAttempt = type(nextAttempt) == "number" and nextAttempt == nextAttempt
                    and math.min(nextAttempt, addon.Runtime.GetTimestamp() + 120) or nil
            end
        end
        normalizedTransfers[data.transfers] = true
    end
    return data.transfers
end
