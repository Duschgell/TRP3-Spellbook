local _, addon = ...

addon.ArchiveCopy = {}

local function countEntries(values)
    local count = 0
    for _ in pairs(type(values) == "table" and values or {}) do
        count = count + 1
    end
    return count
end

local function getPermissions(book)
    return type(book) == "table" and type(book.copyPermissions) == "table"
        and book.copyPermissions
        or nil
end

local function validateArchiveBook(book, permission)
    if type(book) ~= "table" or book.archiveView ~= true or book.imported ~= true then
        return false, addon.L("ARCHIVE_COPY_INVALID_SOURCE")
    end
    if addon.Database.IsImportedBookExpired(book) then
        return false, addon.L("ARCHIVE_COPY_EXPIRED")
    end
    local permissions = getPermissions(book)
    if type(permissions) ~= "table" or permissions[permission] ~= true then
        return false, addon.L("ARCHIVE_COPY_NOT_ALLOWED")
    end
    return true
end

local function copySpellData(sourceSpell)
    if type(sourceSpell) ~= "table" then
        return nil, addon.L("ABILITY_NOT_FOUND")
    end
    local candidate = {
        name = sourceSpell.name,
        icon = sourceSpell.icon,
        nameColor = sourceSpell.nameColor,
        resource = sourceSpell.resource,
        range = sourceSpell.range,
        castTime = sourceSpell.castTime,
        cooldown = sourceSpell.cooldown,
        description = sourceSpell.description,
        effects = sourceSpell.effects,
    }
    if type(sourceSpell.tags) == "table" then
        candidate.tags = {}
        for key, value in pairs(sourceSpell.tags) do
            candidate.tags[key] = value
        end
    end

    local valid, cleaned, errors = addon.Validators.ValidateSpell(candidate)
    if not valid then
        return nil, addon.Validators.GetFirstError(errors)
    end
    return cleaned
end

function addon.ArchiveCopy.CanCopySpell(book, spellID)
    local allowed, errorMessage = validateArchiveBook(book, "spells")
    if not allowed then
        return false, errorMessage
    end
    if type(spellID) ~= "string"
        or type(book.spells) ~= "table"
        or type(book.spells[spellID]) ~= "table"
    then
        return false, addon.L("ABILITY_NOT_FOUND")
    end
    return true
end

function addon.ArchiveCopy.CanCopyTab(book, tabID)
    local allowed, errorMessage = validateArchiveBook(book, "tabs")
    if not allowed then
        return false, errorMessage
    end
    if type(tabID) ~= "string"
        or type(book.tabs) ~= "table"
        or type(book.tabs[tabID]) ~= "table"
    then
        return false, addon.L("TAB_NOT_FOUND")
    end
    return true
end

function addon.ArchiveCopy.CopySpell(book, spellID, targetTabID)
    local allowed, errorMessage = addon.ArchiveCopy.CanCopySpell(book, spellID)
    if not allowed then
        return nil, errorMessage
    end

    local targetBook = addon.Database.GetActiveSpellbook()
    if type(targetBook) ~= "table"
        or type(targetBook.tabs) ~= "table"
        or type(targetBook.tabs[targetTabID]) ~= "table"
    then
        return nil, addon.L("INVALID_SELECTED_TAB")
    end
    if countEntries(targetBook.spells) >= addon.Constants.MAX_EXPORT_SPELLS then
        return nil, addon.L("TOO_MANY_ABILITIES")
    end

    local spellData, validationError = copySpellData(book.spells[spellID])
    if not spellData then
        return nil, validationError
    end
    return addon.Database.CreateSpell(targetTabID, spellData)
end

function addon.ArchiveCopy.CopyTab(book, tabID)
    local allowed, errorMessage = addon.ArchiveCopy.CanCopyTab(book, tabID)
    if not allowed then
        return nil, errorMessage
    end

    local sourceTab = book.tabs[tabID]
    local targetBook = addon.Database.GetActiveSpellbook()
    if type(targetBook) ~= "table" then
        return nil, addon.L("ACTIVE_BOOK_UNAVAILABLE")
    end
    if #targetBook.tabOrder >= addon.Constants.MAX_EXPORT_TABS then
        return nil, addon.L("TOO_MANY_TABS")
    end

    local sourceSpellIDs = type(sourceTab.spellIds) == "table" and sourceTab.spellIds or {}
    if countEntries(targetBook.spells) + #sourceSpellIDs > addon.Constants.MAX_EXPORT_SPELLS then
        return nil, addon.L("TOO_MANY_ABILITIES")
    end

    local spellCopies = {}
    for index, sourceSpellID in ipairs(sourceSpellIDs) do
        local spellData, validationError = copySpellData(book.spells[sourceSpellID])
        if not spellData then
            return nil, validationError
        end
        spellCopies[index] = spellData
    end

    local fallbackTabID = targetBook.tabOrder[1]
    local newTab, tabError = addon.Database.CreateTab(sourceTab.name, sourceTab.icon)
    if not newTab then
        return nil, tabError
    end

    local createdSpellIDs = {}
    for index, spellData in ipairs(spellCopies) do
        local newSpell, spellError = addon.Database.CreateSpell(newTab.id, spellData)
        if not newSpell then
            for _, createdSpellID in ipairs(createdSpellIDs) do
                addon.Database.DeleteSpell(createdSpellID)
            end
            addon.Database.DeleteTab(newTab.id, fallbackTabID)
            return nil, spellError
        end
        createdSpellIDs[index] = newSpell.id
    end
    return newTab
end
