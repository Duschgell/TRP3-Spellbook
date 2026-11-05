local _, addon = ...
local validation = {}
addon.BackupValidation = validation

 
validation.Limits = { MAX_BYTES = 32 * 1024 * 1024, MAX_STRING = 4 * 1024 * 1024,
    MAX_ENTRIES = 1000000, MAX_DEPTH = 48 }

function validation.Clone(value)
    local encoded = addon.PortableTable.Encode(value, validation.Limits)
    return encoded and addon.PortableTable.Decode(encoded, validation.Limits) or nil
end

local function id(value)
    return type(value) == "string" and #value > 0 and #value <= 200 and not value:find("[%c|]")
end
validation.Identifier = id

local function array(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #value then return false end
        count = count + 1
    end
    return count == #value
end
validation.Array = array

local function retained(original, normalized, field, strict)
    if type(original) ~= "table" then
        if original == normalized then return true end
        local presets = addon.SpellCreationPresets
        if not strict and type(original) == "string" and type(normalized) == "string"
            and presets and presets.NormalizeField then
            field = field == "Magieart" and "magicType" or field == "Magieschule" and "magicSchool" or field
            return presets.NormalizeField(field, original) == normalized
        end
        return false
    end
    if type(normalized) ~= "table" then return false end
    for key, value in pairs(original) do
        if not retained(value, normalized[key], key, strict) then return false end
    end
    return true
end

function validation.Settings(value)
    if type(value) ~= "table" then return false end
    local normalized = validation.Clone({ schemaVersion = addon.Constants.DATABASE_SCHEMA_VERSION, settings = value })
    if not normalized then return false end
    local ok, success = pcall(addon.Schema.InitializeDatabase, normalized)
    return ok and success == true and retained(value, normalized.settings, nil, true)
end

function validation.Book(book, profileKey, npc)
    if type(book) ~= "table" or type(book.tabs) ~= "table" or type(book.spells) ~= "table"
        or not array(book.tabOrder) or #book.tabOrder == 0 then return false end
    if not npc and (not id(book.id) or book.profileKey ~= profileKey
        or (book.imported ~= true and type(book.favorites) ~= "table")) then return false end
    local seenTabs, seenSpells = {}, {}
    for _, tabID in ipairs(book.tabOrder) do
        local tab = book.tabs[tabID]
        if not id(tabID) or seenTabs[tabID] or type(tab) ~= "table" or tab.id ~= tabID
            or not array(tab.spellIds) or not addon.Validators.ValidateTab(tab) then return false end
        seenTabs[tabID] = true
        for _, spellID in ipairs(tab.spellIds) do
            if not id(spellID) or seenSpells[spellID] or type(book.spells[spellID]) ~= "table" then return false end
            seenSpells[spellID] = true
        end
    end
    for tabID in pairs(book.tabs) do if not seenTabs[tabID] then return false end end
    for spellID, spell in pairs(book.spells) do
        if not seenSpells[spellID] or spell.id ~= spellID or not addon.Validators.ValidateSpell(spell) then return false end
    end
    for spellID, favorite in pairs(book.favorites or {}) do
        if favorite ~= true or not book.spells[spellID] then return false end
    end
    return true
end

function validation.Core(root)
    if type(root) ~= "table" or root.schemaVersion ~= addon.Constants.DATABASE_SCHEMA_VERSION
        or root.backupControl ~= nil then return false end
    for _, key in ipairs({ "settings", "profiles", "importedBooks", "linkSnapshots", "exportHistory", "debug", "gameMaster" }) do
        if type(root[key]) ~= "table" then return false end
    end
    for profileKey, profile in pairs(root.profiles) do
        if not id(profileKey) or type(profile) ~= "table" or profile.profileKey ~= profileKey
            or not validation.Book(profile.spellbook, profileKey) then return false end
        if profile.owner ~= nil and (type(profile.owner) ~= "table" or profile.owner.profileKey ~= profileKey) then return false end
        if profile.quickSpells ~= nil then
            if type(profile.quickSpells) ~= "table" then return false end
            for slot, spellID in pairs(profile.quickSpells) do
                if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > 8
                    or not profile.spellbook.spells[spellID] then return false end
            end
        end
        if profile.timedEffects ~= nil then
            local effects = profile.timedEffects
            local store = addon.TimedEffectsStore
            if type(effects) ~= "table" or not array(effects.entries) or #effects.entries > 32
                or type(effects.receipts) ~= "table" or effects.transfers ~= nil and type(effects.transfers) ~= "table"
                or effects.blockOffers ~= nil and type(effects.blockOffers) ~= "boolean"
                or not store then return false end
            local seen = {}
            for _, entry in ipairs(effects.entries) do
                 
                 
                if type(entry) ~= "table" or not store.ValidID(entry.id) or seen[entry.id]
                    or type(entry.expiresAt) ~= "number" or entry.expiresAt <= 0
                    or not addon.Runtime.NormalizePlayerID(entry.source) or not store.ValidateSpell(entry.spell)
                    or entry.hidden ~= nil and type(entry.hidden) ~= "boolean" then return false end
                seen[entry.id] = true
            end
            local receiptCount = 0
            for receipt, expires in pairs(effects.receipts) do
                receiptCount = receiptCount + 1
                if receiptCount > 512 or not store.ValidID(receipt) or type(expires) ~= "number" or expires <= 0 then return false end
            end
        end
    end
    for bookID, book in pairs(root.importedBooks) do
        if not id(bookID) or type(book) ~= "table" or book.id ~= bookID or book.imported ~= true
            or type(book.readOnly) ~= "boolean" or type(book.sourceSpellMap) ~= "table"
            or type(book.expiresAt) ~= "number" or type(book.importedAt) ~= "number"
            or not validation.Book(book, book.profileKey) then return false end
        for sourceID, spellID in pairs(book.sourceSpellMap) do
            if not id(sourceID) or not book.spells[spellID] then return false end
        end
    end
     
     
    local normalized = validation.Clone(root)
    if not normalized then return false end
    local ok, success = pcall(addon.Schema.InitializeDatabase, normalized)
    return ok and success == true and retained(root, normalized)
end

function validation.NPC(root)
    local archive = addon.NPCArchive
    if type(root) ~= "table" or root.version ~= 3 or type(root.npcs) ~= "table"
        or type(root.preferences) ~= "table" or not archive
        or type(archive.ValidateTransferProfile) ~= "function" or not validation.Book(root.book, nil, true) then return false end
    for key in pairs(root) do
        if key ~= "version" and key ~= "npcs" and key ~= "book" and key ~= "preferences" then return false end
    end
    local bounds = { width = { 360, 1100 }, height = { 320, 1000 }, scale = { 0.6, 1.25 } }
    for _, key in ipairs({ "width", "height", "scale", "trackingMode" }) do
        if root.preferences[key] == nil then return false end
    end
    for key, value in pairs(root.preferences) do
        if key == "trackingMode" then
            if value ~= "off" and value ~= "target" and value ~= "background" then return false end
        else
            local bound = bounds[key]
            if not bound or type(value) ~= "number" or value < bound[1] or value > bound[2] then return false end
        end
    end
    local count, identities = 0, {}
    for npcID, npc in pairs(root.npcs) do
        count = count + 1
        if count > 50 or type(npc) ~= "table" or npc.id ~= npcID or identities[npcID]
            or not archive.ValidateTransferProfile(npc) or not array(npc.spellIDs) or #npc.spellIDs > 24 then return false end
        identities[npcID] = true
        local assigned = {}
        for _, spellID in ipairs(npc.spellIDs) do
            if assigned[spellID] or not root.book.spells[spellID] then return false end
            assigned[spellID] = true
        end
    end
    for _, npc in pairs(root.npcs) do
        for variantID in pairs(npc.variants or {}) do
            if identities[variantID] then return false end
            identities[variantID] = true
        end
    end
    if #root.book.tabOrder > 32 then return false end
    for _, tabID in ipairs(root.book.tabOrder) do
        if #tabID > 80 or not tabID:match("^[%w_%-]+$") or not archive.ValidateTransferTab(root.book.tabs[tabID]) then return false end
    end
    count = 0
    for spellID, spell in pairs(root.book.spells) do
        count = count + 1
        if count > 1500 or #spellID > 80 or not spellID:match("^[%w_%-]+$") or not archive.ValidateTransferSpell(spell) then return false end
    end
    return true
end

 
 
function validation.Rebind(root, source, destination)
    if source == nil then return true end
    if not id(source) or not id(destination) or not root.profiles[source] then return false end
    if source == destination then return true end
    if root.profiles[destination] then return false end
    local profile = root.profiles[source]
    root.profiles[source], root.profiles[destination] = nil, profile
    profile.profileKey, profile.spellbook.profileKey = destination, destination
    if profile.owner then profile.owner.profileKey = destination end
    if profile.spellbook.id == "book_" .. source then profile.spellbook.id = "book_" .. destination end
    for _, spell in pairs(profile.spellbook.spells) do
        if spell.ownerKey == source then spell.ownerKey = destination end
    end
     
    return true
end

do
    local packing = {}
    addon.BackupPacking = packing

    local metadata = { id = true, ownerKey = true, createdAt = true, updatedAt = true, revision = true }
    local limitKeys = { "MAX_BYTES", "MAX_ENTRIES", "MAX_DEPTH", "MAX_STRING" }

    local function finite(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    end

    local function limitsFor(options)
        if options ~= nil and (type(options) ~= "table" or getmetatable(options)) then error("limits") end
        local limits = {}
        for _, key in ipairs(limitKeys) do
            local value = options and options[key]
            if value == nil then value = addon.PortableTable[key] end
            if not finite(value) or value < 1 or value % 1 ~= 0 then error("limits") end
            limits[key] = value
        end
        return limits
    end

    local function envelopeLimits(limits)
        return {
            MAX_BYTES = limits.MAX_BYTES,
            MAX_ENTRIES = limits.MAX_ENTRIES + 4,
            MAX_DEPTH = limits.MAX_DEPTH + 4,
            MAX_STRING = math.max(limits.MAX_STRING, 10),
        }
    end

    local function spell(value)
        return type(value) == "table" and type(value.name) == "string" and value.icon ~= nil
            and (value.tags == nil or type(value.tags) == "table")
            and (value.effects == nil or type(value.effects) == "table")
            and (value.tags ~= nil or value.effects ~= nil)
    end

    local function keySize(key)
        if type(key) == "string" then return 2 + #tostring(#key) + 2 * #key end
        return 2 + #string.format("%.17g", key)
    end

    local function pathStep(cost, depth, key)
        return cost + keySize(key) + keySize(depth)
    end

    local function measure(value, limits, targets)
        local bytes, entries, active = 0, 0, {}
        local function add(size)
            bytes = bytes + size
            if bytes > limits.MAX_BYTES then error("bytes") end
        end
        local function visit(item, depth)
            if depth > limits.MAX_DEPTH then error("depth") end
            local kind = type(item)
            if kind == "string" then
                if #item > limits.MAX_STRING then error("string") end
                add(2 + #tostring(#item) + 2 * #item)
            elseif kind == "number" then
                if not finite(item) then error("number") end
                add(2 + #string.format("%.17g", item))
            elseif kind == "boolean" then
                add(2)
            elseif kind == "table" then
                if getmetatable(item) or active[item] then error("table") end
                active[item] = true
                local content = targets and targets[item]
                local count = 0
                local function fields(source, countOnly)
                    for key, child in pairs(source) do
                        if type(key) ~= "string" and not finite(key) then error("key") end
                        if countOnly then
                            count, entries = count + 1, entries + 1
                            if entries > limits.MAX_ENTRIES then error("entries") end
                        else
                            visit(key, depth + 1)
                            visit(child, depth + 1)
                        end
                    end
                end
                fields(item, true)
                if content then fields(content, true) end
                add(2 + #tostring(count))
                fields(item, false)
                if content then fields(content, false) end
                active[item] = nil
            else
                error("type")
            end
        end
        visit(value, 0)
    end

    local function clone(value, targets)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = clone(child, targets) end
        local content = targets and targets[value]
        if content then
            for key, child in pairs(content) do result[key] = clone(child, targets) end
        end
        return result
    end

    local function encode(value, options)
        local limits = limitsFor(options)
        measure(value, limits)
        local byEncoding, candidates = {}, {}
        local function collect(item, depth, pathCost)
            if type(item) ~= "table" then return end
            if spell(item) then
                local content = {}
                for key, child in pairs(item) do
                    if not metadata[key] then content[key] = child end
                end
                local encoded = assert(addon.PortableTable.Encode(content, limits))
                local candidate = byEncoding[encoded]
                if not candidate then
                    candidate = { content = content, count = 0, size = #encoded }
                    byEncoding[encoded] = candidate
                end
                if pathCost + 2 + #tostring(depth) <= candidate.size then
                    candidate.count = candidate.count + 1
                end
                candidates[item] = candidate
            else
                for key, child in pairs(item) do collect(child, depth + 1, pathStep(pathCost, depth + 1, key)) end
            end
        end
        collect(value, 0, 0)
        local pool, references, path = {}, {}, {}
        local function skeleton(item, depth, pathCost)
            if type(item) ~= "table" then return item end
            local candidate = candidates[item]
            local pooled = candidate and candidate.count > 1
                and pathCost + 2 + #tostring(depth) <= candidate.size
            if candidate and not pooled then return clone(item) end
            if pooled then
                if not candidate.index then
                    pool[#pool + 1] = candidate.content
                    candidate.index = #pool
                end
                local targetPath = {}
                for index, key in ipairs(path) do targetPath[index] = key end
                references[#references + 1] = { path = targetPath, index = candidate.index }
            end
            local result = {}
            for key, child in pairs(item) do
                if not pooled or metadata[key] then
                    path[#path + 1] = key
                    if pooled then
                        result[key] = clone(child)
                    else
                        result[key] = skeleton(child, depth + 1, pathStep(pathCost, depth + 1, key))
                    end
                    path[#path] = nil
                end
            end
            return result
        end
        local data = skeleton(value, 0, 0)
        return assert(addon.PortableTable.Encode({ version = 1, data = data, spells = pool,
            references = references }, envelopeLimits(limits)))
    end

    local function shape(value, allowed)
        if type(value) ~= "table" then error("shape") end
        for key in pairs(value) do if not allowed[key] then error("field") end end
        for key in pairs(allowed) do if value[key] == nil then error("field") end end
    end

    local function dense(value)
        if type(value) ~= "table" then error("array") end
        local count = 0
        for key in pairs(value) do
            if not finite(key) or key < 1 or key % 1 ~= 0 then error("array") end
            count = count + 1
        end
        for key in pairs(value) do if key > count then error("array") end end
        return count
    end

    local function decode(payload, options)
        local limits = limitsFor(options)
        local envelope = assert(addon.PortableTable.Decode(payload, envelopeLimits(limits)))
        shape(envelope, { version = true, data = true, spells = true, references = true })
        if envelope.version ~= 1 then error("version") end
        local pool, references = envelope.spells, envelope.references
        local poolSize, referenceCount = dense(pool), dense(references)
        for _, content in ipairs(pool) do
            if not spell(content) then error("spell") end
            for key in pairs(content) do if metadata[key] then error("metadata") end end
        end
        local targets, used = {}, {}
        local function resolve(path, size, checkAncestors)
            local item = envelope.data
            for index = 1, size do
                if type(item) ~= "table" or checkAncestors and targets[item] then error("path") end
                item = item[path[index]]
            end
            if type(item) ~= "table" then error("target") end
            return item
        end
        for index = 1, referenceCount do
            local reference = references[index]
            shape(reference, { path = true, index = true })
            local size, poolID = dense(reference.path), reference.index
            if size > limits.MAX_DEPTH or not finite(poolID) or poolID % 1 ~= 0
                or poolID < 1 or poolID > poolSize then error("reference") end
            for _, key in ipairs(reference.path) do
                if type(key) ~= "string" and not finite(key) then error("path") end
            end
            local target = resolve(reference.path, size)
            if targets[target] then error("duplicate") end
            for key in pairs(target) do if not metadata[key] then error("overlap") end end
            targets[target], used[poolID] = pool[poolID], true
        end
        for index = 1, poolSize do if not used[index] then error("unused") end end
        for _, reference in ipairs(references) do resolve(reference.path, #reference.path, true) end
        measure(envelope.data, limits, targets)
        return clone(envelope.data, targets)
    end

    local function protected(callback, value, limits)
        local ok, result = pcall(callback, value, limits)
        if not ok then return nil, "TRANSFER_INVALID" end
        return result
    end

    function packing.Encode(value, limits)
        return protected(encode, value, limits)
    end

    function packing.Decode(payload, limits)
        return protected(decode, payload, limits)
    end
end
