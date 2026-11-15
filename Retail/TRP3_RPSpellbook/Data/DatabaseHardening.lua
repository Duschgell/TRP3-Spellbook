local _, addon = ...

local database = addon.Database
local original = {
    AddImportedBook = database.AddImportedBook,
    AddImportedSpell = database.AddImportedSpell,
    DeleteImportedBook = database.DeleteImportedBook,
    DeleteSpell = database.DeleteSpell,
    GetActiveProfileData = database.GetActiveProfileData,
    PurgeExpiredImportedBooks = database.PurgeExpiredImportedBooks,
    MoveSpell = database.MoveSpell,
}
local normalizedSpellbooks = setmetatable({}, { __mode = "k" })

local function markTabsChanged(tabs)
    local timestamp = addon.Runtime.GetTimestamp()
    for _, tab in ipairs(tabs) do
        tab.updatedAt = timestamp
        tab.revision = (tonumber(tab.revision) or 0) + 1
    end
end

local function collectContainingTabs(spellbook, spellID, excludedTabID)
    local tabs = {}
    if type(spellbook) ~= "table"
        or type(spellbook.tabOrder) ~= "table"
        or type(spellbook.tabs) ~= "table"
    then
        return tabs
    end

    for _, tabID in ipairs(spellbook.tabOrder) do
        local tab = spellbook.tabs[tabID]
        if tabID ~= excludedTabID
            and type(tab) == "table"
            and type(tab.spellIds) == "table"
        then
            for _, currentSpellID in ipairs(tab.spellIds) do
                if currentSpellID == spellID then
                    tabs[#tabs + 1] = tab
                    break
                end
            end
        end
    end
    return tabs
end

local function markExistingSpellbooksNormalized(root)
    local profiles = type(root) == "table" and root.profiles or nil
    if type(profiles) ~= "table" then
        return
    end

    for _, profileData in pairs(profiles) do
        local spellbook = type(profileData) == "table" and profileData.spellbook or nil
        if type(spellbook) == "table" then
            normalizedSpellbooks[spellbook] = true
        end
    end
end

function database.Initialize()
    if type(_G.TRP3_RPSpellbookDB) ~= "table" then
        _G.TRP3_RPSpellbookDB = {}
    end

    local root = _G.TRP3_RPSpellbookDB
    local success, errorMessage = addon.Schema.InitializeDatabase(root)
    if not success then
        return false, errorMessage
    end

    normalizedSpellbooks = setmetatable({}, { __mode = "k" })
    markExistingSpellbooksNormalized(root)
    original.PurgeExpiredImportedBooks()
    addon.ReferenceIndex.Invalidate()
    return true
end

function database.GetActiveProfileData()
    local profileData = original.GetActiveProfileData()
    local spellbook = type(profileData) == "table" and profileData.spellbook or nil
    if type(spellbook) == "table" and not normalizedSpellbooks[spellbook] then
        local profileKey = profileData.profileKey or database.GetActiveProfileKey()
        if addon.Schema.NormalizeSpellbook(spellbook, profileKey) then
            normalizedSpellbooks[spellbook] = true
        end
    end
    return profileData
end

function database.MoveSpell(spellID, targetTabID, targetIndex)
    local spellbook = database.GetActiveSpellbook()
    local sourceTabs = collectContainingTabs(spellbook, spellID, targetTabID)
    local moved, errorMessage = original.MoveSpell(spellID, targetTabID, targetIndex)
    if moved then
        markTabsChanged(sourceTabs)
    end
    return moved, errorMessage
end

function database.DeleteSpell(spellID)
    local spellbook = database.GetActiveSpellbook()
    local affectedTabs = collectContainingTabs(spellbook, spellID)
    local deleted, errorMessage = original.DeleteSpell(spellID)
    if deleted then
        markTabsChanged(affectedTabs)
    end
    return deleted, errorMessage
end

function database.DeleteSpells(spellIDs)
    if type(spellIDs) ~= "table" then
        return false, addon.L("ABILITY_NOT_FOUND")
    end
    local spellbook = database.GetActiveSpellbook()
    if type(spellbook) ~= "table" or type(spellbook.spells) ~= "table" then
        return false, addon.L("ACTIVE_BOOK_UNAVAILABLE")
    end

    local requested = {}
    local count = 0
    for _, spellID in ipairs(spellIDs) do
        if type(spellID) == "string"
            and type(spellbook.spells[spellID]) == "table"
            and not requested[spellID]
        then
            requested[spellID] = true
            count = count + 1
        end
    end
    if count == 0 then
        return false, addon.L("ABILITY_NOT_FOUND")
    end

    local changedTabs = {}
    for _, tabID in ipairs(spellbook.tabOrder or {}) do
        local tab = spellbook.tabs and spellbook.tabs[tabID]
        if type(tab) == "table" and type(tab.spellIds) == "table" then
            local changed = false
            for index = #tab.spellIds, 1, -1 do
                if requested[tab.spellIds[index]] then
                    table.remove(tab.spellIds, index)
                    changed = true
                end
            end
            if changed then
                changedTabs[#changedTabs + 1] = tab
            end
        end
    end
    for spellID in pairs(requested) do
        spellbook.spells[spellID] = nil
        if type(spellbook.favorites) == "table" then
            spellbook.favorites[spellID] = nil
        end
    end
    markTabsChanged(changedTabs)
    spellbook.updatedAt = addon.Runtime.GetTimestamp()
    spellbook.revision = (tonumber(spellbook.revision) or 0) + 1
    return count
end

function database.AddImportedSpell(decodedImport)
    local importedBook, errorMessage = original.AddImportedSpell(decodedImport)
    if importedBook then
        addon.ReferenceIndex.Invalidate()
    end
    return importedBook, errorMessage
end

function database.AddImportedBook(decodedImport)
    local importedBook, errorMessage = original.AddImportedBook(decodedImport)
    if importedBook then
        addon.ReferenceIndex.Invalidate()
    end
    return importedBook, errorMessage
end

function database.DeleteImportedBook(importedBookID)
    local deleted, errorMessage = original.DeleteImportedBook(importedBookID)
    if deleted then
        addon.ReferenceIndex.Invalidate()
    end
    return deleted, errorMessage
end

function database.PurgeExpiredImportedBooks()
    local removed = original.PurgeExpiredImportedBooks()
    if removed > 0 then
        addon.ReferenceIndex.Invalidate()
    end
    return removed
end

function database.ResolveSpellReference(ownerKey, spellID, revision)
    database.PurgeExpiredImportedBooks()
    if type(ownerKey) ~= "string" or ownerKey == ""
        or type(spellID) ~= "string" or spellID == ""
        or type(revision) ~= "number"
    then
        return nil
    end

    local root = database.GetDB()
    local profiles = type(root) == "table" and root.profiles or nil
    local profileData = type(profiles) == "table" and profiles[ownerKey] or nil
    local spellbook = type(profileData) == "table" and profileData.spellbook or nil
    local spell = type(spellbook) == "table"
        and type(spellbook.spells) == "table"
        and spellbook.spells[spellID]
        or nil
    if type(spell) == "table" and tonumber(spell.revision) == revision then
        return spell, spellbook
    end

    local importedBooks = type(root) == "table" and root.importedBooks or nil
    return addon.ReferenceIndex.Resolve(importedBooks, ownerKey, spellID, revision)
end
