local _, addon = ...

addon.ImportedLibrary = {}

local sources = setmetatable({}, { __mode = "k" })
local cachedSource, cachedRevision, cachedBook

local function normalizeSortText(value)
    return type(value) == "string" and string.lower(value) or ""
end

local function normalizeSearchText(value)
    value = addon.Runtime.Trim(value or "") or ""
    local lower = type(strlower) == "function" and strlower or string.lower
    local success, normalized = pcall(lower, value)
    return success and type(normalized) == "string" and normalized or string.lower(value)
end

function addon.ImportedLibrary.FilterOwners(owners, query)
    local normalizedQuery = normalizeSearchText(query)
    if normalizedQuery == "" then
        return owners
    end

    local filtered = {}
    for _, owner in ipairs(type(owners) == "table" and owners or {}) do
        if normalizeSearchText(owner.displayName):find(normalizedQuery, 1, true) then
            filtered[#filtered + 1] = owner
        end
    end
    return filtered
end

local function isNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

local function isSafeSourceID(value)
    return isNonEmptyString(value)
        and #value <= addon.Constants.MAX_EXPORT_SOURCE_ID_LENGTH
        and not value:find("[%c|]")
end

local function copyOwner(owner)
    if type(owner) ~= "table" then
        return nil
    end

    local result = {}
    for _, key in ipairs({ "profileKey", "characterName", "realmName", "rpName", "ownerGuid" }) do
        if isNonEmptyString(owner[key]) then
            result[key] = owner[key]
        end
    end
    return next(result) and result or nil
end

local function getOwnerDisplayName(owner)
    local rpName = type(owner) == "table" and owner.rpName or nil
    if type(rpName) == "string" then
        rpName = rpName:match("^%s*(.-)%s*$")
        if rpName ~= "" then
            return rpName
        end
    end
    return addon.L("UNKNOWN")
end

local function getSourceBookID(book)
    local exportMeta = type(book) == "table" and book.exportMeta or nil
    if type(exportMeta) == "table" and isSafeSourceID(exportMeta.sourceBookId) then
        return exportMeta.sourceBookId
    end
    return isSafeSourceID(book and book.id) and book.id or nil
end

local function getOwnerKey(book, sourceBookID)
    local owner = type(book) == "table" and book.owner or nil
    if type(owner) == "table" then
        if isNonEmptyString(owner.profileKey) then
            return "profile:" .. owner.profileKey
        end
        if isNonEmptyString(owner.ownerGuid) then
            return "guid:" .. owner.ownerGuid
        end
        if isNonEmptyString(owner.characterName) then
            return "character:" .. normalizeSortText(owner.characterName) .. "@" .. normalizeSortText(owner.realmName)
        end
        if isNonEmptyString(owner.rpName) then
            return "rp:" .. normalizeSortText(owner.rpName)
        end
    end
    return "unknown:" .. (sourceBookID or (book and book.id) or "book")
end

local function buildSourceIDsByLocalID(sourceMap)
    local result = {}
    if type(sourceMap) == "table" then
        for sourceID, localID in pairs(sourceMap) do
            if isSafeSourceID(sourceID) and isSafeSourceID(localID) then
                result[localID] = sourceID
            end
        end
    end
    return result
end

local function getCopyPermissions(book)
    local permissions = type(book.copyPermissions) == "table"
        and book.copyPermissions
        or type(book.exportMeta) == "table" and book.exportMeta.copyPermissions
        or nil
    return {
        spells = type(permissions) == "table" and permissions.spells == true,
        tabs = type(permissions) == "table" and permissions.tabs == true,
    }
end

local function collectBook(group, book)
    local sourceSpellIDsByLocalID = buildSourceIDsByLocalID(book.sourceSpellMap)
    local sourceTabIDsByLocalID = buildSourceIDsByLocalID(book.sourceTabMap)
    group.importCount = 1
    group.latestImportedAt = tonumber(book.importedAt) or 0
    group.expiresAt = tonumber(book.expiresAt) or 0
    group.expiredImportCount = addon.Database.IsImportedBookExpired(book) and 1 or 0
    group.icon = book.icon
    group.sourceName = isNonEmptyString(book.name) and book.name or nil
    group.copyPermissions = getCopyPermissions(book)

    for tabIndex, tabID in ipairs(book.tabOrder) do
        local tab = type(book.tabs) == "table" and book.tabs[tabID] or nil
        if type(tab) == "table" and type(tab.spellIds) == "table" then
            local sourceTabID = sourceTabIDsByLocalID[tabID]
                or (isNonEmptyString(tab.id) and tab.id)
                or ("tab_" .. tabIndex)
            local tabGroup = {
                sourceID = sourceTabID,
                name = isNonEmptyString(tab.name) and tab.name or addon.L("IMPORTED_TAB_NAME"),
                icon = tab.icon,
                orderIndex = tabIndex,
                spells = {},
            }
            group.tabs[#group.tabs + 1] = tabGroup

            for _, localSpellID in ipairs(tab.spellIds) do
                local spell = type(book.spells) == "table" and book.spells[localSpellID] or nil
                local sourceSpellID = type(spell) == "table"
                    and isSafeSourceID(localSpellID)
                    and (sourceSpellIDsByLocalID[localSpellID] or localSpellID)
                    or nil
                if sourceSpellID then
                    tabGroup.spells[#tabGroup.spells + 1] = {
                        spell = spell,
                        sourceSpellID = sourceSpellID,
                    }
                end
            end
        end
    end
end

local function buildVirtualBook(group)
    local importedAt = group.latestImportedAt
    local virtualBook = {
        id = "archive_" .. group.importID,
        profileKey = group.owner and group.owner.profileKey or ("archive:" .. group.importID),
        imported = true,
        archiveView = true,
        archiveImportID = group.importID,
        owner = copyOwner(group.owner),
        name = group.displayName,
        icon = group.icon or addon.Constants.DEFAULT_BOOK_ICON,
        readOnly = true,
        expiresAt = group.expiresAt,
        copyPermissions = {
            spells = group.copyPermissions.spells,
            tabs = group.copyPermissions.tabs,
        },
        importedAt = importedAt,
        tabs = {},
        tabOrder = {},
        spells = {},
        sourceSpellMap = {},
        createdAt = importedAt,
        updatedAt = importedAt,
        revision = 1,
    }

    for tabIndex, tabGroup in ipairs(group.tabs) do
        local virtualTabID = "archive_tab_" .. tabIndex
        local virtualTab = {
            id = virtualTabID,
            name = tabGroup.name,
            icon = tabGroup.icon or addon.Constants.DEFAULT_TAB_ICON,
            spellIds = {},
            createdAt = importedAt,
            updatedAt = importedAt,
            revision = 1,
        }

        for spellIndex, candidate in ipairs(tabGroup.spells) do
            local sourceSpellID = candidate.sourceSpellID
            local virtualSpellID = sourceSpellID
            if virtualBook.spells[virtualSpellID] then
                virtualSpellID = sourceSpellID .. "_" .. spellIndex
            end

            local virtualSpell = {}
            for key, value in pairs(candidate.spell) do
                if key == "tags" and type(value) == "table" then
                    local tags = {}
                    for tagKey, tagValue in pairs(value) do
                        tags[tagKey] = tagValue
                    end
                    virtualSpell.tags = tags
                elseif key == "effects" and type(value) == "table" then
                    local effects = {}
                    for effectKey, effectValue in pairs(value) do
                        effects[effectKey] = effectValue
                    end
                    virtualSpell.effects = effects
                else
                    virtualSpell[key] = value
                end
            end
            virtualSpell.id = virtualSpellID
            virtualBook.spells[virtualSpellID] = virtualSpell
            virtualBook.sourceSpellMap[sourceSpellID] = virtualSpellID
            virtualTab.spellIds[#virtualTab.spellIds + 1] = virtualSpellID
        end

        virtualBook.tabs[virtualTabID] = virtualTab
        virtualBook.tabOrder[#virtualBook.tabOrder + 1] = virtualTabID
    end

    group.spellCount = 0
    for _ in pairs(virtualBook.spells) do
        group.spellCount = group.spellCount + 1
    end
    group.allExpired = group.expiredImportCount == 1
    return virtualBook
end

function addon.ImportedLibrary.GetVirtualBook(group)
    local source = sources[group]
    local book = source and source.book
    if not book then return nil end
    local database = addon.Database.GetDB()
    local stored = type(database) == "table" and database.importedBooks
    if addon.Database.IsImportedBookExpired(book)
        or source.persisted and (type(stored) ~= "table" or stored[book.id] ~= book) then
        if cachedSource == book then cachedSource, cachedRevision, cachedBook = nil, nil, nil end
        return nil
    end
    if cachedSource == book and cachedRevision == book.revision then return cachedBook end
     
    local materialized = {}
    for key, value in pairs(group) do materialized[key] = value end
    materialized.tabs = {}
    collectBook(materialized, book)
    cachedSource, cachedRevision = book, book.revision
    cachedBook = buildVirtualBook(materialized)
    return cachedBook
end

local groupMetatable = { __index = function(group, key)
    if key == "virtualBook" then return addon.ImportedLibrary.GetVirtualBook(group) end
end }

local function createBookGroup(book, sourceBookID, ownerGroup)
    local importID = isSafeSourceID(book.id) and book.id or nil
    if not importID then
        return nil
    end

    local group = {
        importID = importID,
        importIDs = {
            [importID] = true,
        },
        sourceBookID = sourceBookID,
        owner = copyOwner(book.owner) or ownerGroup.owner,
        ownerDisplayName = ownerGroup.displayName,
        displayName = isNonEmptyString(book.name) and book.name or addon.L("ARCHIVE_SOURCE_BOOK"),
        icon = nil,
        sourceName = nil,
        tabs = {},
        importCount = 0,
        expiredImportCount = 0,
        latestImportedAt = 0,
    }
    group.importCount = 1
    group.latestImportedAt = tonumber(book.importedAt) or 0
    group.expiresAt = tonumber(book.expiresAt) or 0
    group.allExpired = addon.Database.IsImportedBookExpired(book)
    group.expiredImportCount = group.allExpired and 1 or 0
    group.icon, group.sourceName = book.icon, book.name
    group.copyPermissions = getCopyPermissions(book)
    group.spellCount = 0
    for _, tabID in ipairs(book.tabOrder) do
        local tab = book.tabs[tabID]
        if type(tab) == "table" and type(tab.spellIds) == "table" then
            group.spellCount = group.spellCount + #tab.spellIds
        end
    end
    local database = addon.Database.GetDB()
    sources[group] = { book = book, persisted = type(database) == "table"
        and type(database.importedBooks) == "table" and database.importedBooks[book.id] == book }
    return setmetatable(group, groupMetatable)
end

function addon.ImportedLibrary.BuildIndex(importedBooks)
    local ownersByKey = {}
    local owners = {}
    local cachePresent = false

    for _, book in ipairs(type(importedBooks) == "table" and importedBooks or {}) do
        if book == cachedSource then cachePresent = true end
        local sourceBookID = getSourceBookID(book)
        if sourceBookID then
            local ownerKey = getOwnerKey(book, sourceBookID)
            local ownerGroup = ownersByKey[ownerKey]
            if not ownerGroup then
                ownerGroup = {
                    key = ownerKey,
                    owner = copyOwner(book.owner),
                    displayName = getOwnerDisplayName(book.owner),
                    books = {},
                }
                ownersByKey[ownerKey] = ownerGroup
                owners[#owners + 1] = ownerGroup
            end

            local bookGroup = createBookGroup(book, sourceBookID, ownerGroup)
            if bookGroup then
                ownerGroup.books[#ownerGroup.books + 1] = bookGroup
            end
        end
    end

    table.sort(owners, function(first, second)
        local firstName = normalizeSortText(first.displayName)
        local secondName = normalizeSortText(second.displayName)
        if firstName == secondName then
            return first.key < second.key
        end
        return firstName < secondName
    end)

    for _, ownerGroup in ipairs(owners) do
        table.sort(ownerGroup.books, function(first, second)
            if first.latestImportedAt ~= second.latestImportedAt then
                return first.latestImportedAt > second.latestImportedAt
            end
            local firstName = normalizeSortText(first.displayName)
            local secondName = normalizeSortText(second.displayName)
            if firstName ~= secondName then
                return firstName < secondName
            end
            return first.importID > second.importID
        end)
        ownerGroup.bookCount = #ownerGroup.books
    end

    if not cachePresent then cachedSource, cachedRevision, cachedBook = nil, nil, nil end
    return owners
end
