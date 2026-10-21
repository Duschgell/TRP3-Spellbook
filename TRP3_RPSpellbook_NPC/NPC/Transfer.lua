local _, private = ...
local addon = private.Shared or private
local archive, codec = addon.NPCArchive, addon.PortableTable
local transfer = {}
archive.Transfer = transfer
local PREFIX = "RPSBNPC1:"
local plans = setmetatable({}, { __mode = "k" })

local function count(values) local n = 0; for _ in pairs(values) do n = n + 1 end; return n end
local function keys(values)
    local result = {}; for key in pairs(values) do result[#result + 1] = key end
    table.sort(result); return result
end
local function identifier(value)
    return type(value) == "string" and #value <= 80 and value:match("^[%w_%-]+$") ~= nil
end
local function array(value, maximum)
    if type(value) ~= "table" or #value > maximum then return false end
    local total = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > #value or key ~= math.floor(key) then return false end
        total = total + 1
    end
    return total == #value
end
local function equal(a, b)
    local left, right = codec.Encode(a), codec.Encode(b)
    return left ~= nil and right ~= nil and left == right
end
local function spellData(value)
    local result = archive.ValidateTransferSpell(value)
    return result
end
local function npcData(value)
    local result = archive.ValidateTransferProfile(value)
    if result then result.spellIDs = value.spellIDs end
    return result
end
local function npcComparable(value)
    local result = npcData(value)
    result.id = nil
    local variants = {}
    for _, variantID in ipairs(keys(result.variants)) do
        local variant = result.variants[variantID]
        variants[#variants + 1] = { name = variant.name, creatureID = variant.creatureID or variantID,
            lastSeen = variant.lastSeen }
    end
    table.sort(variants, function(a, b) return codec.Encode(a) < codec.Encode(b) end)
    result.variants = variants
    return result
end

local function validate(value)
    if type(value) ~= "table" or value.format ~= "npc-transfer" or value.version ~= 1
        or (value.schema ~= 1 and value.schema ~= 2 and value.schema ~= 3)
        or (value.scope ~= "single" and value.scope ~= "all") or type(value.npcs) ~= "table"
        or count(value.npcs) > 50 or (value.scope == "single" and count(value.npcs) ~= 1) then return nil end
    for key in pairs(value) do
        if key ~= "format" and key ~= "version" and key ~= "schema" and key ~= "scope"
            and key ~= "npcs" and key ~= "book" then return nil end
    end
    local result = { npcs = {}, book = { tabs = {}, spells = {}, tabOrder = {} } }
    local identities = {}
    for npcID, source in pairs(value.npcs) do
        local npc = archive.ValidateTransferProfile(source)
        if not npc or npc.id ~= npcID or identities[npcID] then return nil end
        result.npcs[npcID], identities[npcID] = npc, true
    end
    for _, npc in pairs(result.npcs) do
        for variantID in pairs(npc.variants) do
            if identities[variantID] then return nil end
            identities[variantID] = true
        end
    end
    local book = value.book
    if value.schema < 3 then
        if book ~= nil then return nil end
        local tab = { id = "npc_general", name = archive.L("GENERAL"), spellIds = {} }
        result.book.tabs[tab.id], result.book.tabOrder[1] = tab, tab.id
        for _, npcID in ipairs(keys(result.npcs)) do
            if not archive.MigrateTransferAbilities(result.npcs[npcID], result.book) then return nil end
        end
        return result
    end
    if type(book) ~= "table" or type(book.tabs) ~= "table" or type(book.spells) ~= "table"
        or not array(book.tabOrder, 32) or #book.tabOrder == 0 or count(book.tabs) ~= #book.tabOrder
        or count(book.spells) > 1500 then return nil end
    for spellID, source in pairs(book.spells) do
        local spell = spellData(source)
        if not identifier(spellID) or not spell or (source.id ~= nil and source.id ~= spellID) then return nil end
        spell.id, spell.revision = spellID, 1
        result.book.spells[spellID] = spell
    end
    local owned, seenTabs = {}, {}
    for _, tabID in ipairs(book.tabOrder) do
        local source = book.tabs[tabID]
        local tab = archive.ValidateTransferTab(source)
        if not identifier(tabID) or seenTabs[tabID] or not tab or (source.id ~= nil and source.id ~= tabID)
            or not array(source.spellIds, 1500) then return nil end
        tab.id, tab.spellIds, tab.revision = tabID, {}, 1
        seenTabs[tabID] = true
        for _, spellID in ipairs(source.spellIds) do
            if not identifier(spellID) or not result.book.spells[spellID] or owned[spellID] then return nil end
            owned[spellID], tab.spellIds[#tab.spellIds + 1] = true, spellID
        end
        result.book.tabs[tabID], result.book.tabOrder[#result.book.tabOrder + 1] = tab, tabID
    end
    if count(owned) ~= count(result.book.spells) then return nil end
    local assigned = {}
    for npcID, npc in pairs(result.npcs) do
        local order, seen = value.npcs[npcID].spellIDs, {}
        if not array(order, 24) then return nil end
        npc.spellIDs = {}
        for _, spellID in ipairs(order) do
            if not identifier(spellID) or seen[spellID] or not result.book.spells[spellID] then return nil end
            seen[spellID], assigned[spellID], npc.spellIDs[#npc.spellIDs + 1] = true, true, spellID
        end
    end
    if value.scope == "single" and count(assigned) ~= count(result.book.spells) then return nil end
    return result
end

function transfer.Export(npcID)
    local state = archive.GetTransferState()
    if not state then return nil, "NOT_READY" end
    if npcID ~= nil then
        local npc = state.npcs[npcID]
        if not npc then return nil, "TRANSFER_INVALID" end
        state.npcs = { [npcID] = npc }
        local assigned = {}; for _, spellID in ipairs(npc.spellIDs) do assigned[spellID] = true end
        for spellID in pairs(state.book.spells) do if not assigned[spellID] then state.book.spells[spellID] = nil end end
        local tabs, order = {}, {}
        for _, tabID in ipairs(state.book.tabOrder) do
            local tab, spells = state.book.tabs[tabID], {}
            for _, spellID in ipairs(tab.spellIds) do if assigned[spellID] then spells[#spells + 1] = spellID end end
            if #spells > 0 then tab.spellIds = spells; tabs[tabID], order[#order + 1] = tab, tabID end
        end
        if #order == 0 then
            local tabID = state.book.tabOrder[1]
            tabs[tabID], order[1] = state.book.tabs[tabID], tabID
            tabs[tabID].spellIds = {}
        end
        state.book.tabs, state.book.tabOrder = tabs, order
    end
    local envelope = { format = "npc-transfer", version = 1, schema = 3,
        scope = npcID and "single" or "all", npcs = state.npcs, book = state.book }
    local clean = validate(envelope)
    if not clean then return nil, "TRANSFER_INVALID" end
    envelope.npcs, envelope.book = clean.npcs, clean.book
    local encoded, err = codec.Encode(envelope)
    return encoded and PREFIX .. encoded or nil, err
end

local function resolveStringID(original, values, matches)
    local candidate, index = original, 0
    while values[candidate] do
        if matches(values[candidate]) then return candidate, false end
        index = index + 1
        candidate = original:sub(1, 60) .. "_transfer_" .. index
    end
    return candidate, true
end

local function merge(current, incoming, mode)
    local book, spellMap, replaced = current.book, {}, {}
    for _, spellID in ipairs(keys(incoming.book.spells)) do
        local source = incoming.book.spells[spellID]
        local targetID, created = resolveStringID(spellID, book.spells, function(entry)
            return equal(spellData(entry), spellData(source))
        end)
        spellMap[spellID] = targetID
        if created then source.id = targetID; book.spells[targetID] = source end
    end
    if count(book.spells) > 1500 then return nil, "BOOK_FULL" end
    local owned = {}
    for _, tab in pairs(book.tabs) do for _, spellID in ipairs(tab.spellIds) do owned[spellID] = true end end
    for _, tabID in ipairs(incoming.book.tabOrder) do
        local source = incoming.book.tabs[tabID]
        local sourceOrder = source.spellIds
        local targetID, created = resolveStringID(tabID, book.tabs, function(entry)
            return equal(archive.ValidateTransferTab(entry), archive.ValidateTransferTab(source))
        end)
        if created then
            source.id, source.spellIds = targetID, {}
            book.tabs[targetID], book.tabOrder[#book.tabOrder + 1] = source, targetID
        end
        local target = book.tabs[targetID]
        for _, sourceID in ipairs(sourceOrder) do
            local spellID = spellMap[sourceID]
            if not owned[spellID] then target.spellIds[#target.spellIds + 1] = spellID; owned[spellID] = true end
        end
    end
    if #book.tabOrder > 32 then return nil, "BOOK_FULL" end
    local used, reserved = {}, {}
    for npcID, npc in pairs(current.npcs) do
        used[npcID] = true; for variantID in pairs(npc.variants) do used[variantID] = true end
    end
    for npcID, npc in pairs(incoming.npcs) do
        reserved[npcID] = true; for variantID in pairs(npc.variants) do reserved[variantID] = true end
    end
    local function freeID()
        local candidate = 1
        while used[candidate] or reserved[candidate] do candidate = candidate + 1 end
        used[candidate] = true
        return candidate
    end
    local added, updated, claimed = 0, 0, {}
    for _, npcID in ipairs(keys(incoming.npcs)) do
        local source = incoming.npcs[npcID]
        for index, spellID in ipairs(source.spellIDs) do source.spellIDs[index] = spellMap[spellID] end
        local targetID, same = npcID, false
        if mode == "merge" and used[npcID] then
            local comparable = npcComparable(source)
            if current.npcs[npcID] and equal(npcComparable(current.npcs[npcID]), comparable) then
                same = true
            else
                for _, candidate in ipairs(keys(current.npcs)) do
                    if not reserved[candidate] and not claimed[candidate]
                        and equal(npcComparable(current.npcs[candidate]), comparable) then
                        targetID, same = candidate, true; break
                    end
                end
            end
        end
        if not same then
            if current.npcs[targetID] and mode == "replace" then
                for variantID in pairs(current.npcs[targetID].variants) do used[variantID] = nil end
                replaced[targetID], updated = true, updated + 1
            else
                if used[targetID] then targetID = freeID() end
                added = added + 1
            end
            local variants = {}
            for _, variantID in ipairs(keys(source.variants)) do
                local variant = source.variants[variantID]
                local mapped = used[variantID] and freeID() or variantID
                used[mapped], variant.id, variants[mapped] = true, mapped, variant
            end
            source.id, source.variants, used[targetID] = targetID, variants, true
            current.npcs[targetID] = source
        end
        claimed[targetID] = true
    end
    if count(current.npcs) > 50 then return nil, "FULL" end
    return current, replaced, added, updated
end

local function editorBusy()
    if type(archive.IsTransferEditorBusy) == "function" and archive.IsTransferEditorBusy() then return true end
    local editor = addon.SpellEditorWindow
    if editor and type(editor.GetTutorialContext) == "function" then
        local frame, state = editor.GetTutorialContext()
        if frame and frame:IsShown() and state and state.storage == archive.SpellbookStorage then return true end
    end
    return false
end

local function prepare(input, mode)
    if mode ~= "merge" and mode ~= "replace" then return nil, "TRANSFER_INVALID" end
    if editorBusy() then return nil, "TRANSFER_EDITOR" end
    if type(input) ~= "string" or #input > codec.MAX_BYTES + #PREFIX or input:sub(1, #PREFIX) ~= PREFIX then
        return nil, "TRANSFER_INVALID"
    end
    local decoded = codec.Decode(input:sub(#PREFIX + 1))
    local incoming = decoded and validate(decoded)
    if not incoming then return nil, "TRANSFER_INVALID" end
    local current = archive.GetTransferState()
    if not current then return nil, "NOT_READY" end
    local fingerprint = codec.Encode(current)
    if not fingerprint then return nil, "TRANSFER_INVALID" end
    local candidate, replaced, added, updated = merge(current, incoming, mode)
    if not candidate then return nil, replaced end
     
    local checked = validate({ format = "npc-transfer", version = 1, schema = 3, scope = "all",
        npcs = candidate.npcs, book = candidate.book })
    if not checked then return nil, "TRANSFER_INVALID" end
    candidate.npcs = checked.npcs
    local handle = { added = added, updated = updated, mode = mode }
    local npcTokens, spellTokens = {}, {}
    for _, npc in ipairs(archive.List()) do npcTokens[npc.id] = archive.GetIdentityToken(npc.id) end
    for spellID in pairs(archive.SpellbookStorage.GetActiveSpellbook().spells) do
        spellTokens[spellID] = archive.SpellbookStorage.GetSpellToken(spellID)
    end
    plans[handle] = { state = candidate, replaced = replaced, fingerprint = fingerprint,
        npcTokens = npcTokens, spellTokens = spellTokens }
    return handle
end

function transfer.Prepare(input, mode)
    local ok, result, err = pcall(prepare, input, mode)
    if not ok then return nil, "TRANSFER_INVALID" end
    return result, err
end

function transfer.Commit(handle)
    local plan = plans[handle]
    if not plan then return nil, "TRANSFER_INVALID" end
    plans[handle] = nil
    if editorBusy() then return nil, "TRANSFER_EDITOR" end
    if codec.Encode(archive.GetTransferState()) ~= plan.fingerprint then return nil, "TRANSFER_STALE" end
    for npcID, token in pairs(plan.npcTokens) do
        if archive.GetIdentityToken(npcID) ~= token then return nil, "TRANSFER_STALE" end
    end
    for spellID, token in pairs(plan.spellTokens) do
        if archive.SpellbookStorage.GetSpellToken(spellID) ~= token then return nil, "TRANSFER_STALE" end
    end
    return archive.CommitTransferState(plan.state, plan.replaced)
end
