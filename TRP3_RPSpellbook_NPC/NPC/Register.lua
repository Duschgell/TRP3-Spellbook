local _, private = ...
local addon = private.Shared or private
local archive = addon.NPCArchive
local db
local MAX_TABS, MAX_SPELLS, MAX_ASSIGNED = 32, 1500, 24
local storage = {}
local spellTokens, nextSpellToken = setmetatable({}, { __mode = "k" }), 0
archive.SpellbookStorage = storage

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function plain(value, limit)
    if type(value) ~= "string" or #value > limit or value:find("|")
        or value:find("[%z\1-\8\11-\31\127]") then return nil end
    return value:match("^%s*(.-)%s*$")
end

local function identifier(value)
    return type(value) == "string" and #value <= 80 and value:match("^[%w_%-]+$") and value or nil
end

local function color(value)
    if value == nil or value == "" then return nil end
    if type(value) ~= "string" then return nil end
    value = value:gsub("^#", "")
    return value:match("^%x%x%x%x%x%x$") and value:upper() or nil
end

local function icon(value)
    if type(value) == "number" and value > 0 and value <= 2147483647 and value == math.floor(value) then return value end
    return plain(value, 255)
end

local relationships = { friendly = true, neutral = true, hostile = true }
local function relationship(value) return relationships[value] and value or nil end
local function now() return type(time) == "function" and time() or 0 end
local function count(values) local total = 0; for _ in pairs(values) do total = total + 1 end; return total end
local function errorText(key) return archive.L(key or "INVALID") end

local function cleanProfile(value)
    if type(value) ~= "table" then return nil end
    local result = { name = plain(value.name, 120), title = plain(value.title or "", 120),
        description = plain(value.description or "", 2000), area = plain(value.area or "", 120),
        nameColor = color(value.nameColor), icon = icon(value.icon), relationship = relationship(value.relationship) }
    if not result.name or result.name == "" or not result.title or not result.description or not result.area
        or (value.nameColor ~= nil and value.nameColor ~= "" and not result.nameColor)
        or (value.icon ~= nil and value.icon ~= "" and not result.icon)
        or (type(result.icon) == "string" and #result.icon > 200)
        or (value.relationship ~= nil and value.relationship ~= "" and not result.relationship) then return nil end
    return result
end

local fields = { "name", "icon", "nameColor", "description", "resource", "range", "castTime", "cooldown", "effects", "tags" }
local function cleanSpell(value)
    if type(value) ~= "table" then return nil end
    local candidate = {}
    for _, field in ipairs(fields) do
        local item = value[field]
        if field == "effects" then
            if item ~= nil then
                if type(item) ~= "table" then return nil end
                candidate.effects = {}
                for _, key in ipairs({ "buff", "debuff", "debuffType", "healing", "duration", "durationRounds", "durationSeconds", "whisperTemplate" }) do
                    local entry = item[key]
                    if entry ~= nil and type(entry) ~= "boolean" and type(entry) ~= "number" and type(entry) ~= "string" then return nil end
                    if type(entry) == "string" and not plain(entry, 300) then return nil end
                    candidate.effects[key] = entry
                end
            end
        elseif field == "tags" then
            if item ~= nil then
                if type(item) ~= "table" then return nil end
                candidate.tags = {}
                local scanned = 0
                for key, entry in pairs(item) do
                    scanned = scanned + 1
                    if scanned > 20 or not plain(key, 40) or not plain(entry, 80) then return nil end
                    candidate.tags[key] = entry
                end
            end
        elseif item ~= nil then
            if field == "icon" then
                if not icon(item) then return nil end
            elseif not plain(item, field == "description" and 2000 or 255) then return nil end
            candidate[field] = item
        end
    end
    local ok, valid, cleaned = pcall(addon.Validators.ValidateSpell, candidate)
    return ok and valid and cleaned or nil
end

local function cleanTab(value)
    if type(value) ~= "table" or not plain(value.name, 40) then return nil end
    if value.icon ~= nil and value.icon ~= "" and not icon(value.icon) then return nil end
    local valid, cleaned = addon.Validators.ValidateTab({ name = value.name, icon = value.icon })
    return valid and cleaned or nil
end

local function defaultBook()
    local tab = { id = "npc_general", name = archive.L("GENERAL"), spellIds = {}, revision = 1 }
    return { id = "npc_shared", name = archive.L("BOOK"), tabs = { [tab.id] = tab },
        tabOrder = { tab.id }, spells = {}, revision = 1, nextID = 1 }
end

local function readBook(saved)
    local book = defaultBook()
    if type(saved) ~= "table" then return book end
    local owned, seenTabs = {}, {}
    for index = 1, math.min(type(saved.tabOrder) == "table" and #saved.tabOrder or 0, MAX_TABS) do
        local tabID = identifier(saved.tabOrder[index])
        local source = tabID and type(saved.tabs) == "table" and saved.tabs[tabID]
        local tab = cleanTab(source)
        if tab and not seenTabs[tabID] then
            if next(seenTabs) == nil then book.tabs, book.tabOrder = {}, {} end
            seenTabs[tabID] = true
            tab.id, tab.revision = tabID, 1
            book.tabs[tabID], book.tabOrder[#book.tabOrder + 1] = tab, tabID
        end
    end
    local scanned = 0
    for spellID, source in pairs(type(saved.spells) == "table" and saved.spells or {}) do
        scanned = scanned + 1
        if scanned > MAX_SPELLS then break end
        local spell = identifier(spellID) and cleanSpell(source)
        if spell then
            spell.id, spell.revision, spell.npcDraft = spellID, 1, source.npcDraft == true
            book.spells[spellID] = spell
        end
    end
    for _, tabID in ipairs(book.tabOrder) do
        local source = type(saved.tabs) == "table" and saved.tabs[tabID]
        local order = type(source) == "table" and type(source.spellIds) == "table" and source.spellIds or {}
        for index = 1, math.min(#order, MAX_SPELLS) do
            local spellID = identifier(order[index])
            if spellID and book.spells[spellID] and not owned[spellID] then
                owned[spellID] = true
                local target = book.tabs[tabID].spellIds
                target[#target + 1] = spellID
            end
        end
    end
    local orphaned = {}
    for spellID in pairs(book.spells) do if not owned[spellID] then orphaned[#orphaned + 1] = spellID end end
    table.sort(orphaned)
    local first = book.tabs[book.tabOrder[1]].spellIds
    for _, spellID in ipairs(orphaned) do first[#first + 1] = spellID end
    return book
end

local function migrateAbility(npc, ability, targetBook)
    local rp = ability.rp
    local tags = {}
    if rp.kind ~= "" then tags[addon.Constants.SPELL_TAG_KIND] = rp.kind end
    if rp.kind == "magic" then tags[addon.Constants.MAGIC_TAG_ENABLED] = "true" end
    local spell = cleanSpell({ name = rp.name, icon = rp.icon, description = rp.description,
        resource = rp.resource, range = rp.range, castTime = rp.castTime, tags = tags })
    if not spell then return end
    local spellID = "legacy_" .. npc.id .. "_" .. ability.spellID
    spell.id, spell.revision, spell.npcDraft = spellID, 1, not ability.reviewed
    local book = targetBook or db.book
    book.spells[spellID] = spell
    local tab = book.tabs[book.tabOrder[1]]
    tab.spellIds[#tab.spellIds + 1] = spellID
    npc.spellIDs[#npc.spellIDs + 1] = spellID
    return true
end

function archive.InitializeRegister(clean, saved)
    db = clean
    db.version, db.book = 3, readBook(saved and saved.version == 3 and saved.book)
    db.preferences.trackingMode = "off"
    for npcID, npc in pairs(db.npcs) do
        local original = saved and type(saved.npcs) == "table" and saved.npcs[npcID] or {}
         
        npc.title = plain(original.title or "", 120) or ""
        npc.description = plain(original.description or "", 2000) or ""
        npc.area = plain(original.area or "", 120) or ""
        npc.nameColor, npc.relationship = color(original.nameColor), relationship(original.relationship)
        npc.icon = icon(original.icon)
        if type(npc.icon) == "string" and #npc.icon > 200 then npc.icon = nil end
        npc.profileEdited = original.profileEdited == true
        npc.spellIDs = {}
        if saved and saved.version == 3 then
            local assigned, seen = type(original.spellIDs) == "table" and original.spellIDs or {}, {}
            for index = 1, math.min(#assigned, MAX_ASSIGNED) do
                local spellID = identifier(assigned[index])
                if spellID and db.book.spells[spellID] and not seen[spellID] then
                    seen[spellID], npc.spellIDs[#npc.spellIDs + 1] = true, spellID
                end
            end
        else
            local ordered = {}
            for spellID in pairs(npc.abilities) do ordered[#ordered + 1] = spellID end
            table.sort(ordered)
            for _, spellID in ipairs(ordered) do migrateAbility(npc, npc.abilities[spellID]) end
        end
    end
end

function archive.ApplyCaptureMetadata(npc, metadata, created)
    metadata = type(metadata) == "table" and metadata or {}
    npc.spellIDs = npc.spellIDs or {}
    if created or not npc.profileEdited then
        npc.relationship = relationship(metadata.relationship)
        npc.area = plain(metadata.area, 120) or npc.area or ""
    end
end

function archive.SaveProfile(npcID, data, expectedToken)
    local npc = db and db.npcs[npcID]
    local profile = cleanProfile(data)
    if not npc or not profile or (expectedToken ~= nil and archive.GetIdentityToken(npcID) ~= expectedToken) then
        return nil, errorText("INVALID")
    end
    for _, key in ipairs({ "name", "title", "description", "nameColor", "icon", "relationship", "area" }) do npc[key] = profile[key] end
    npc.profileEdited = true
    archive.Notify()
    return archive.Get(npcID)
end

local function changed(value)
    if value then value.revision, value.updatedAt = (value.revision or 0) + 1, now() end
    db.book.revision = (db.book.revision or 0) + 1
    archive.Notify()
end

local function nextID(prefix, values)
    local index = db.book.nextID or 1
    while values[prefix .. index] do index = index + 1 end
    db.book.nextID = index + 1
    return prefix .. index
end

function storage.GetActiveSpellbook() return db and copy(db.book) or nil end
function storage.GetRevision() return db and db.book.revision or nil end
function storage.GetSpell(spellID) return db and copy(db.book.spells[spellID]) or nil end
function storage.GetSpellToken(spellID)
    local spell = db and db.book.spells[spellID]
    if not spell then return nil end
    if not spellTokens[spell] then
        nextSpellToken = nextSpellToken + 1
        spellTokens[spell] = nextSpellToken
    end
    return spellTokens[spell]
end
function storage.GetTab(tabID) return db and copy(db.book.tabs[tabID]) or nil end
function storage.GetSpellTabID(spellID)
    if not db then return nil end
    for _, tabID in ipairs(db.book.tabOrder) do
        for _, entry in ipairs(db.book.tabs[tabID].spellIds) do if entry == spellID then return tabID end end
    end
end

function storage.CreateTab(name, selectedIcon)
    if not db then return nil, errorText("NOT_READY") end
    if #db.book.tabOrder >= MAX_TABS then return nil, errorText("BOOK_FULL") end
    local tab = cleanTab({ name = name, icon = selectedIcon })
    if not tab then return nil, errorText("INVALID") end
    tab.id = nextID("npc_tab_", db.book.tabs)
    db.book.tabs[tab.id], db.book.tabOrder[#db.book.tabOrder + 1] = tab, tab.id
    changed(tab)
    return copy(tab)
end

function storage.UpdateTab(tabID, patch)
    local tab = db and db.book.tabs[tabID]
    if not tab or type(patch) ~= "table" then return nil, errorText("INVALID") end
    local selectedIcon = patch.icon
    if selectedIcon == nil and not patch.clearOptionalFields then selectedIcon = tab.icon end
    local clean = cleanTab({ name = patch.name or tab.name, icon = selectedIcon })
    if not clean then return nil, errorText("INVALID") end
    tab.name, tab.icon = clean.name, clean.icon
    changed(tab)
    return copy(tab)
end

local function remove(values, target)
    for index = #values, 1, -1 do if values[index] == target then table.remove(values, index) end end
end

function storage.MoveTab(tabID, index)
    if not db or not db.book.tabs[tabID] or type(index) ~= "number" or index ~= math.floor(index)
        or index < 1 or index > #db.book.tabOrder then return nil, errorText("INVALID") end
    remove(db.book.tabOrder, tabID)
    table.insert(db.book.tabOrder, index, tabID)
    changed()
    return true
end

function storage.DeleteTab(tabID, targetTabID)
    local book = db and db.book
    if not book or not book.tabs[tabID] or not book.tabs[targetTabID] or tabID == targetTabID then return nil, errorText("INVALID") end
    if #book.tabOrder <= 1 then return nil, addon.L("KEEP_ONE_TAB") end
    local target = book.tabs[targetTabID]
    for _, spellID in ipairs(book.tabs[tabID].spellIds) do target.spellIds[#target.spellIds + 1] = spellID end
    book.tabs[tabID] = nil
    remove(book.tabOrder, tabID)
    changed(target)
    return true
end

function storage.CreateSpell(tabID, data)
    local tab = db and db.book.tabs[tabID]
    if not tab then return nil, errorText("INVALID") end
    if count(db.book.spells) >= MAX_SPELLS then return nil, errorText("BOOK_FULL") end
    local spell = cleanSpell(data)
    if not spell then return nil, errorText("INVALID") end
    spell.id = nextID("npc_spell_", db.book.spells)
    db.book.spells[spell.id], tab.spellIds[#tab.spellIds + 1] = spell, spell.id
    changed(spell)
    return copy(spell)
end

function storage.UpdateSpell(spellID, patch)
    local spell = db and db.book.spells[spellID]
    if not spell or type(patch) ~= "table" then return nil, errorText("INVALID") end
    local candidate = {}
    for _, key in ipairs(fields) do
        candidate[key] = patch[key]
        if candidate[key] == nil and (key == "name" or not patch.clearOptionalFields) then candidate[key] = spell[key] end
    end
    local cleaned = cleanSpell(candidate)
    if not cleaned then return nil, errorText("INVALID") end
    for _, key in ipairs(fields) do spell[key] = cleaned[key] end
     
    spell.npcDraft = false
    changed(spell)
    return copy(spell)
end

function storage.MoveSpell(spellID, tabID, index)
    local book = db and db.book
    local target = book and book.tabs[tabID]
    if not target or not book.spells[spellID] then return nil, errorText("INVALID") end
    if index ~= nil and (type(index) ~= "number" or index < 1 or index > #target.spellIds + 1 or index ~= math.floor(index)) then return nil, errorText("INVALID") end
    for _, tab in pairs(book.tabs) do remove(tab.spellIds, spellID) end
    table.insert(target.spellIds, math.min(index or (#target.spellIds + 1), #target.spellIds + 1), spellID)
    changed(target)
    return true
end

function storage.DeleteSpell(spellID, expectedToken)
    if not db or not db.book.spells[spellID]
        or (expectedToken ~= nil and storage.GetSpellToken(spellID) ~= expectedToken) then
        return nil, errorText("INVALID")
    end
    db.book.spells[spellID] = nil
    for _, tab in pairs(db.book.tabs) do remove(tab.spellIds, spellID) end
    for _, npc in pairs(db.npcs) do remove(npc.spellIDs, spellID) end
    changed()
    return true
end

function archive.AssignSpell(npcID, spellID, assigned)
    local npc = db and db.npcs[npcID]
    if not npc or not db.book.spells[spellID] or type(assigned) ~= "boolean" then return nil, errorText("INVALID") end
    local found = false
    for _, entry in ipairs(npc.spellIDs) do if entry == spellID then found = true end end
    if assigned and not found then
        if #npc.spellIDs >= MAX_ASSIGNED then return nil, errorText("ASSIGN_FULL") end
        npc.spellIDs[#npc.spellIDs + 1] = spellID
    elseif not assigned then remove(npc.spellIDs, spellID) end
    archive.Notify()
    return true
end

function archive.CopyFromSpellbook(spellID, tabID, importedBookID, expectedBookID)
     
    local source
    if importedBookID ~= nil then
        source = addon.Database.GetImportedBook(importedBookID)
        if not source or source.imported ~= true or addon.Database.IsImportedBookExpired(source)
            or type(source.copyPermissions) ~= "table" or source.copyPermissions.spells ~= true then
            return nil, addon.L("ARCHIVE_COPY_NOT_ALLOWED")
        end
    else
        source = addon.Database.GetActiveSpellbook()
        if not source or source.imported or source.archiveView or source.readOnly then return nil, addon.L("ARCHIVE_COPY_NOT_ALLOWED") end
    end
    if expectedBookID ~= nil and source.id ~= expectedBookID then return nil, errorText("SOURCE_CHANGED") end
    local spell = type(source.spells) == "table" and source.spells[spellID]
    if not spell then return nil, errorText("INVALID") end
    return storage.CreateSpell(tabID, spell)
end

function archive.GetEncounterTemplate(npcID)
    local npc = db and db.npcs[npcID]
    if not npc then return nil end
    local profile = cleanProfile(npc)
    if not profile then return nil end
    profile.templateID, profile.spells = tostring(npcID), {}
    if npc.source == "authored" and not profile.icon then
        profile.icon = "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    for _, spellID in ipairs(npc.spellIDs) do
        local source = db.book.spells[spellID]
        local spell = source and not source.npcDraft and cleanSpell(source)
        if spell then
            spell.id = spellID
            profile.spells[#profile.spells + 1] = spell
        end
    end
    return profile
end

function archive.GetTransferState()
    return db and { npcs = copy(db.npcs), book = copy(db.book) } or nil
end

function archive.ValidateTransferProfile(value)
    local npc, profile = archive.ValidateTransferNPC(value), cleanProfile(value)
    if not npc or not profile then return nil end
    for key, item in pairs(profile) do npc[key] = item end
    return npc
end

function archive.ValidateTransferSpell(value)
    if type(value) ~= "table" or (value.npcDraft ~= nil and type(value.npcDraft) ~= "boolean") then return nil end
    if value.effects ~= nil then
        if type(value.effects) ~= "table" then return nil end
        for _, key in ipairs({ "buff", "debuff", "healing" }) do
            if value.effects[key] ~= nil and type(value.effects[key]) ~= "boolean" then return nil end
        end
        for _, key in ipairs({ "durationRounds", "durationSeconds" }) do
            if value.effects[key] ~= nil and type(value.effects[key]) ~= "number" then return nil end
        end
    end
    local result = cleanSpell(value)
    if result then result.npcDraft = value.npcDraft == true end
    return result
end

function archive.ValidateTransferTab(value) return cleanTab(value) end

function archive.MigrateTransferAbilities(npc, book)
    local ordered = {}
    for spellID in pairs(npc.abilities) do ordered[#ordered + 1] = spellID end
    table.sort(ordered)
    npc.spellIDs = {}
    for _, spellID in ipairs(ordered) do
        if not migrateAbility(npc, npc.abilities[spellID], book) then return nil end
    end
    return true
end

 
function archive.CommitTransferState(state, replaced)
    if not db then return nil, "NOT_READY" end
    for npcID, npc in pairs(state.npcs) do
        if db.npcs[npcID] and not replaced[npcID] then state.npcs[npcID] = db.npcs[npcID] end
    end
    for spellID, spell in pairs(state.book.spells) do
        if db.book.spells[spellID] then state.book.spells[spellID] = db.book.spells[spellID] end
    end
    state.book.revision = (db.book.revision or 0) + 1
    db.npcs, db.book = state.npcs, state.book
     
    pcall(archive.Notify)
    return true
end
