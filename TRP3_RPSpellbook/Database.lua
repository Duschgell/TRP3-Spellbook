local _, addon = ...

addon.Database = {}

local idCounter = 0
local normalizedSpellbooks = setmetatable({}, { __mode = "k" })

local function ensureTable(parent, key)
    if type(parent[key]) ~= "table" then
        parent[key] = {}
    end

    return parent[key]
end

local function getTimestamp()
    if type(time) == "function" then
        return time()
    end

    return 0
end

local function generateID(prefix, collection)
    local id
    repeat
        idCounter = idCounter + 1
        id = string.format("%s%d_%04x", prefix, getTimestamp(), idCounter)
    until collection[id] == nil

    return id
end

local function touchBook(spellbook)
    spellbook.updatedAt = getTimestamp()
    spellbook.revision = (tonumber(spellbook.revision) or 0) + 1
end

local function createDefaultTab()
    local constants = addon.Constants
    local timestamp = getTimestamp()
    return {
        id = constants.DEFAULT_TAB_ID,
        name = addon.L("DEFAULT_TAB_NAME"),
        icon = constants.DEFAULT_TAB_ICON,
        themeID = "default",
        spellIds = {},
        createdAt = timestamp,
        updatedAt = timestamp,
        revision = 1,
    }
end

local function createDefaultSpellbook(profileKey)
    local constants = addon.Constants
    local timestamp = getTimestamp()
    local defaultTab = createDefaultTab()

    return {
        id = "book_" .. profileKey,
        profileKey = profileKey,
        name = addon.L("DEFAULT_BOOK_NAME"),
        icon = constants.DEFAULT_BOOK_ICON,
        tabs = {
            [defaultTab.id] = defaultTab,
        },
        tabOrder = { defaultTab.id },
        spells = {},
        favorites = {},
        createdAt = timestamp,
        updatedAt = timestamp,
        revision = 1,
    }
end

local function normalizeSpellbook(spellbook, profileKey)
    local constants = addon.Constants
    if type(spellbook.id) ~= "string" or spellbook.id == "" then
        spellbook.id = "book_" .. profileKey
    end
    if type(spellbook.profileKey) ~= "string" or spellbook.profileKey == "" then
        spellbook.profileKey = profileKey
    end
    if type(spellbook.name) ~= "string" or spellbook.name == "" then
        spellbook.name = addon.L("DEFAULT_BOOK_NAME")
    end
    if spellbook.icon == nil or spellbook.icon == "" then
        spellbook.icon = constants.DEFAULT_BOOK_ICON
    end

    local tabs = ensureTable(spellbook, "tabs")
    local tabOrder = ensureTable(spellbook, "tabOrder")
    ensureTable(spellbook, "spells")
    ensureTable(spellbook, "favorites")
    if #tabOrder == 0 or type(tabs[tabOrder[1]]) ~= "table" then
        local defaultTab = tabs[constants.DEFAULT_TAB_ID]
        if type(defaultTab) ~= "table" then
            defaultTab = createDefaultTab()
            tabs[defaultTab.id] = defaultTab
        end
        tabOrder[1] = defaultTab.id
    end

    for _, tabID in ipairs(tabOrder) do
        local tab = tabs[tabID]
        if type(tab) == "table" then
            tab.themeID = addon.Validators.NormalizeTabThemeID(tab.themeID)
            ensureTable(tab, "spellIds")
        end
    end

    spellbook.createdAt = tonumber(spellbook.createdAt) or getTimestamp()
    spellbook.updatedAt = tonumber(spellbook.updatedAt) or spellbook.createdAt
    spellbook.revision = tonumber(spellbook.revision) or 1
end

local function getActiveSpellbookOrError()
    local spellbook = addon.Database.GetActiveSpellbook()
    if not spellbook then
        return nil, addon.L("ACTIVE_BOOK_UNAVAILABLE")
    end

    return spellbook
end

local function contains(list, value)
    for _, currentValue in ipairs(list) do
        if currentValue == value then
            return true
        end
    end

    return false
end

local function removeValue(list, value)
    for index = #list, 1, -1 do
        if list[index] == value then
            table.remove(list, index)
        end
    end
end

local function countEntries(entries)
    local count = 0
    for _ in pairs(entries) do
        count = count + 1
    end
    return count
end

local function getPatchedValue(existingValue, patch, fieldName, clearOptionalFields)
    if patch[fieldName] ~= nil then
        return patch[fieldName]
    end

    if clearOptionalFields then
        return nil
    end

    return existingValue
end

function addon.Database.Initialize()
    if type(_G.TRP3_RPSpellbookDB) ~= "table" then
        _G.TRP3_RPSpellbookDB = {}
    end

    local database = _G.TRP3_RPSpellbookDB
    if type(database.schemaVersion) ~= "number" then
        database.schemaVersion = addon.Constants.DATABASE_SCHEMA_VERSION
    end

    database.addonVersion = addon.Constants.ADDON_VERSION
    ensureTable(database, "settings")
    ensureTable(database, "profiles")
    ensureTable(database, "importedBooks")
    ensureTable(database, "linkSnapshots")
    ensureTable(database, "exportHistory")
    ensureTable(database, "debug")
end

function addon.Database.GetDB()
    return _G.TRP3_RPSpellbookDB
end

local storageRoles = {
    root = { profiles = "profiles", importedBooks = "imports", gameMaster = "gm" },
    profiles = { child = "profile", count = "profiles" },
    profile = { spellbook = "book" },
    book = { spells = "personalSpells" },
    personalSpells = { count = "personalSpells" },
    imports = { child = "import", count = "imports" },
    import = { spells = "importedSpells" },
    importedSpells = { count = "importedSpells" },
    gm = { sessions = "scenes" },
    scenes = { child = "scene", count = "scenes" },
    scene = { rounds = "rounds" },
    rounds = { count = "rounds" },
}

function addon.Database.GetStorageStats()
    local stats = { profiles = 0, imports = 0, personalSpells = 0, importedSpells = 0,
        scenes = 0, rounds = 0, estimatedBytes = 0, scannedEntries = 0, partial = false }
    local root = addon.Database.GetDB()
    if type(root) ~= "table" then return stats end
    local seen = { [root] = true }
    local stack = { { value = root, role = "root" } }
     
     
    while #stack > 0 and stats.scannedEntries < 100000 do
        local current = stack[#stack]
        local key, value = next(current.value, current.key)
        current.key = key
        if key == nil then
            stack[#stack] = nil
        else
            stats.scannedEntries = stats.scannedEntries + 1
            stats.estimatedBytes = stats.estimatedBytes + (type(key) == "string" and #key or 8) + 4
            if type(value) == "table" then
                local role = storageRoles[current.role]
                if role and role.count then stats[role.count] = stats[role.count] + 1 end
                if not seen[value] then
                    seen[value] = true
                    if #stack < 64 then
                        stack[#stack + 1] = { value = value, role = role and (role.child or role[key]) }
                    else
                        stats.partial = true
                    end
                end
            else
                stats.estimatedBytes = stats.estimatedBytes + (type(value) == "string" and #value or 8)
            end
        end
    end
    stats.partial = stats.partial or #stack > 0
    stats.warning = stats.partial or stats.estimatedBytes >= 10 * 1024 * 1024
        or stats.personalSpells + stats.importedSpells >= 10000
        or stats.scenes >= 50 or stats.profiles >= 25
    return stats
end

local function isUsableImportedBook(book)
    if type(book) ~= "table"
        or type(book.id) ~= "string"
        or book.id == ""
        or type(book.profileKey) ~= "string"
        or book.profileKey == ""
        or book.imported ~= true
        or type(book.name) ~= "string"
        or book.name == ""
        or type(book.readOnly) ~= "boolean"
        or type(book.expiresAt) ~= "number"
        or type(book.importedAt) ~= "number"
        or type(book.tabs) ~= "table"
        or type(book.tabOrder) ~= "table"
        or type(book.spells) ~= "table"
        or type(book.sourceSpellMap) ~= "table"
    then
        return false
    end

    if #book.tabOrder < 1 then
        return false
    end
    local seenTabs = {}
    local seenSpells = {}
    for _, tabID in ipairs(book.tabOrder) do
        local tab = type(tabID) == "string" and book.tabs[tabID] or nil
        if seenTabs[tabID] or type(tab) ~= "table" or type(tab.spellIds) ~= "table" then
            return false
        end
        seenTabs[tabID] = true
        for _, spellID in ipairs(tab.spellIds) do
            if type(spellID) ~= "string" or seenSpells[spellID] or type(book.spells[spellID]) ~= "table" then
                return false
            end
            seenSpells[spellID] = true
        end
    end
    return countEntries(book.tabs) == #book.tabOrder
        and countEntries(book.spells) == countEntries(seenSpells)
end

local function isImportedBookExpired(book, timestamp)
    local expiresAt = type(book) == "table" and tonumber(book.expiresAt) or nil
    return expiresAt ~= nil
        and expiresAt > 0
        and (timestamp or getTimestamp()) >= expiresAt
end

function addon.Database.PurgeExpiredImportedBooks()
    local database = addon.Database.GetDB()
    local importedBooks = type(database) == "table" and database.importedBooks or nil
    if type(importedBooks) ~= "table" then
        return 0
    end

    local timestamp = getTimestamp()
    local removed = 0
    for importedBookID, book in pairs(importedBooks) do
        if isImportedBookExpired(book, timestamp) then
            importedBooks[importedBookID] = nil
            removed = removed + 1
        end
    end
    return removed
end

function addon.Database.GetNextImportedBookExpiration()
    addon.Database.PurgeExpiredImportedBooks()
    local database = addon.Database.GetDB()
    local importedBooks = type(database) == "table" and database.importedBooks or nil
    local nextExpiration
    if type(importedBooks) == "table" then
        for _, book in pairs(importedBooks) do
            local expiresAt = type(book) == "table" and tonumber(book.expiresAt) or nil
            if expiresAt and expiresAt > 0 and (not nextExpiration or expiresAt < nextExpiration) then
                nextExpiration = expiresAt
            end
        end
    end
    return nextExpiration
end

function addon.Database.GetImportedBook(importedBookID)
    addon.Database.PurgeExpiredImportedBooks()
    local database = addon.Database.GetDB()
    local importedBooks = type(database) == "table" and database.importedBooks or nil
    local book = type(importedBooks) == "table" and importedBooks[importedBookID] or nil
    return isUsableImportedBook(book) and book or nil
end

function addon.Database.ListImportedBooks()
    addon.Database.PurgeExpiredImportedBooks()
    local database = addon.Database.GetDB()
    local importedBooks = type(database) == "table" and database.importedBooks or nil
    local result = {}
    if type(importedBooks) == "table" then
        for _, book in pairs(importedBooks) do
            if isUsableImportedBook(book) then
                result[#result + 1] = book
            end
        end
    end
    table.sort(result, function(first, second)
        local firstTime = tonumber(first.importedAt) or 0
        local secondTime = tonumber(second.importedAt) or 0
        if firstTime == secondTime then
            return first.id < second.id
        end
        return firstTime > secondTime
    end)
    return result
end

function addon.Database.DeleteImportedBook(importedBookID)
    if type(importedBookID) ~= "string"
        or importedBookID == ""
        or #importedBookID > addon.Constants.MAX_EXPORT_SOURCE_ID_LENGTH
        or importedBookID:find("[%c|]")
    then
        return false, addon.L("IMPORTED_BOOK_NOT_FOUND")
    end

    local database = addon.Database.GetDB()
    local importedBooks = type(database) == "table" and database.importedBooks or nil
    if type(importedBooks) ~= "table" or type(importedBooks[importedBookID]) ~= "table" then
        return false, addon.L("IMPORTED_BOOK_NOT_FOUND")
    end

    importedBooks[importedBookID] = nil
    return true
end

function addon.Database.IsImportedBookExpired(book)
    return isImportedBookExpired(book)
end

function addon.Database.GetActiveProfileKey()
    return addon.TRP3Bridge.GetActiveProfileKey()
end

function addon.Database.GetActiveProfileData()
    local database = addon.Database.GetDB()
    local profileKey = addon.Database.GetActiveProfileKey()
    if type(database) ~= "table" or not profileKey then
        return nil
    end

    local profiles = ensureTable(database, "profiles")
    local profileData = profiles[profileKey]
    if type(profileData) ~= "table" then
        local timestamp = getTimestamp()
        profileData = {
            profileKey = profileKey,
            owner = {
                profileKey = profileKey,
            },
            spellbook = createDefaultSpellbook(profileKey),
            createdAt = timestamp,
            updatedAt = timestamp,
        }
        profiles[profileKey] = profileData
    elseif type(profileData.spellbook) ~= "table" then
        profileData.spellbook = createDefaultSpellbook(profileKey)
    end

    if not normalizedSpellbooks[profileData.spellbook] then
        normalizeSpellbook(profileData.spellbook, profileKey)
        normalizedSpellbooks[profileData.spellbook] = true
    end
    return profileData
end

function addon.Database.GetActiveSpellbook()
    local profileData = addon.Database.GetActiveProfileData()
    return profileData and profileData.spellbook or nil
end

local function normalizeBookIcon(icon)
    if type(icon) == "number" and icon > 0 and icon < math.huge
        and icon == math.floor(icon) and icon <= addon.Constants.MAX_IMPORT_SAFE_INTEGER then
        return icon
    end
    icon = addon.Runtime.Trim(icon)
    if addon.Runtime.IsSafeIdentifier(icon, addon.Validators.Limits.MAX_ICON_LENGTH) then return icon end
end

function addon.Database.GetSpellbookIcon()
    local root = addon.Database.GetDB()
    local profiles = type(root) == "table" and root.profiles
    local profile = type(profiles) == "table" and profiles[addon.Database.GetActiveProfileKey()]
    local book = type(profile) == "table" and profile.spellbook
    return normalizeBookIcon(type(book) == "table" and book.icon) or addon.Constants.DEFAULT_BOOK_ICON
end

function addon.Database.SetSpellbookIcon(icon)
    icon = normalizeBookIcon(icon)
    if not icon then return false, addon.L("INVALID_ICON") end
    local book, err = getActiveSpellbookOrError()
    if not book then return false, err end
    if book.icon ~= icon then
        book.icon = icon
        touchBook(book)
    end
    return true
end

function addon.Database.GetTab(tabID)
    local spellbook = addon.Database.GetActiveSpellbook()
    return spellbook and spellbook.tabs[tabID] or nil
end

function addon.Database.GetSpell(spellID)
    local spellbook = addon.Database.GetActiveSpellbook()
    return spellbook and spellbook.spells[spellID] or nil
end

function addon.Database.IsSpellFavorite(spellID)
    local spellbook = addon.Database.GetActiveSpellbook()
    return type(spellbook) == "table"
        and type(spellbook.favorites) == "table"
        and spellbook.favorites[spellID] == true
end

function addon.Database.SetSpellFavorite(spellID, favorite)
    local spellbook, errorMessage = getActiveSpellbookOrError()
    if not spellbook or type(spellbook.spells[spellID]) ~= "table" then
        return false, errorMessage or addon.L("ABILITY_NOT_FOUND")
    end
    local favorites = ensureTable(spellbook, "favorites")
    local nextValue = favorite == true
    if (favorites[spellID] == true) == nextValue then
        return true, nextValue
    end
    favorites[spellID] = nextValue and true or nil
    touchBook(spellbook)
    return true, nextValue
end

function addon.Database.ToggleSpellFavorite(spellID)
    return addon.Database.SetSpellFavorite(
        spellID,
        not addon.Database.IsSpellFavorite(spellID)
    )
end

function addon.Database.GetSpellTabID(spellID)
    local spellbook = addon.Database.GetActiveSpellbook()
    if not spellbook then
        return nil
    end

    for _, tabID in ipairs(spellbook.tabOrder) do
        local tab = spellbook.tabs[tabID]
        if tab and contains(tab.spellIds, spellID) then
            return tabID
        end
    end

    return nil
end

function addon.Database.CreateTab(name, icon, themeID)
    local spellbook, errorMessage = getActiveSpellbookOrError()
    if not spellbook then
        return nil, errorMessage
    end
    if #spellbook.tabOrder >= 50 then
        return nil, addon.L("TOO_MANY_TABS")
    end

    local ok, cleaned, errors = addon.Validators.ValidateTab({
        name = name,
        icon = icon,
        themeID = themeID,
    })
    if not ok then
        return nil, addon.Validators.GetFirstError(errors)
    end

    local timestamp = getTimestamp()
    local tabID = generateID("tab_", spellbook.tabs)
    local tab = {
        id = tabID,
        name = cleaned.name,
        icon = cleaned.icon,
        themeID = cleaned.themeID or "default",
        spellIds = {},
        createdAt = timestamp,
        updatedAt = timestamp,
        revision = 1,
    }
    spellbook.tabs[tabID] = tab
    spellbook.tabOrder[#spellbook.tabOrder + 1] = tabID
    touchBook(spellbook)
    return tab
end

function addon.Database.UpdateTab(tabID, patch)
    local spellbook, errorMessage = getActiveSpellbookOrError()
    local tab = spellbook and spellbook.tabs[tabID]
    if not tab then
        return nil, errorMessage or addon.L("TAB_NOT_FOUND")
    end

    patch = type(patch) == "table" and patch or {}
    local clearOptionalFields = patch.clearOptionalFields == true
    local candidate = {
        name = patch.name ~= nil and patch.name or tab.name,
        icon = getPatchedValue(tab.icon, patch, "icon", clearOptionalFields),
        themeID = patch.themeID ~= nil and patch.themeID or tab.themeID,
        spellIds = tab.spellIds,
    }
    local ok, cleaned, errors = addon.Validators.ValidateTab(candidate)
    if not ok then
        return nil, addon.Validators.GetFirstError(errors)
    end

    tab.name = cleaned.name
    tab.icon = cleaned.icon
    tab.themeID = cleaned.themeID or "default"
    tab.updatedAt = getTimestamp()
    tab.revision = (tonumber(tab.revision) or 0) + 1
    touchBook(spellbook)
    return tab
end

function addon.Database.RenameTab(tabID, name)
    return addon.Database.UpdateTab(tabID, { name = name })
end

function addon.Database.MoveTab(tabID, targetIndex)
    local spellbook, errorMessage = getActiveSpellbookOrError()
    local tab = spellbook and spellbook.tabs[tabID]
    if not tab then
        return false, errorMessage or addon.L("TAB_NOT_FOUND")
    end

    local numericTarget = tonumber(targetIndex)
    if not numericTarget
        or numericTarget ~= math.floor(numericTarget)
        or numericTarget < 1
        or numericTarget > #spellbook.tabOrder
    then
        return false, addon.L("INVALID_TAB_POSITION")
    end

    local sourceIndex
    for index, orderedTabID in ipairs(spellbook.tabOrder) do
        if orderedTabID == tabID then
            sourceIndex = index
            break
        end
    end
    if not sourceIndex then
        return false, addon.L("TAB_NOT_FOUND")
    end
    if sourceIndex == numericTarget then
        return true
    end

    table.remove(spellbook.tabOrder, sourceIndex)
    table.insert(
        spellbook.tabOrder,
        math.min(numericTarget, #spellbook.tabOrder + 1),
        tabID
    )
    touchBook(spellbook)
    return true
end

function addon.Database.DeleteTab(tabID, moveSpellIdsToTabID)
    local spellbook, errorMessage = getActiveSpellbookOrError()
    local tab = spellbook and spellbook.tabs[tabID]
    if not tab then
        return false, errorMessage or addon.L("TAB_NOT_FOUND")
    end
    if #spellbook.tabOrder <= 1 then
        return false, addon.L("KEEP_ONE_TAB")
    end

    local targetTab = spellbook.tabs[moveSpellIdsToTabID]
    if not targetTab or moveSpellIdsToTabID == tabID then
        return false, addon.L("INVALID_DELETE_TARGET")
    end

    for _, spellID in ipairs(tab.spellIds) do
        if spellbook.spells[spellID] and not contains(targetTab.spellIds, spellID) then
            targetTab.spellIds[#targetTab.spellIds + 1] = spellID
        end
    end

    spellbook.tabs[tabID] = nil
    removeValue(spellbook.tabOrder, tabID)
    targetTab.updatedAt = getTimestamp()
    targetTab.revision = (tonumber(targetTab.revision) or 0) + 1
    touchBook(spellbook)
    return true
end

function addon.Database.CreateSpell(tabID, spellData)
    local spellbook, errorMessage = getActiveSpellbookOrError()
    local tab = spellbook and spellbook.tabs[tabID]
    if not tab then
        return nil, errorMessage or addon.L("INVALID_SELECTED_TAB")
    end
    if countEntries(spellbook.spells) >= 500 then
        return nil, addon.L("TOO_MANY_ABILITIES")
    end

    local ok, cleaned, errors = addon.Validators.ValidateSpell(spellData)
    if not ok then
        return nil, addon.Validators.GetFirstError(errors)
    end

    local timestamp = getTimestamp()
    local spellID = generateID("sp_", spellbook.spells)
    cleaned.id = spellID
    cleaned.createdAt = timestamp
    cleaned.updatedAt = timestamp
    cleaned.revision = 1
    spellbook.spells[spellID] = cleaned
    tab.spellIds[#tab.spellIds + 1] = spellID
    tab.updatedAt = timestamp
    tab.revision = (tonumber(tab.revision) or 0) + 1
    touchBook(spellbook)
    return cleaned
end

function addon.Database.UpdateSpell(spellID, patch)
    local spellbook, errorMessage = getActiveSpellbookOrError()
    local spell = spellbook and spellbook.spells[spellID]
    if not spell then
        return nil, errorMessage or addon.L("ABILITY_NOT_FOUND")
    end

    patch = type(patch) == "table" and patch or {}
    local clearOptionalFields = patch.clearOptionalFields == true
    local candidate = {
        name = patch.name ~= nil and patch.name or spell.name,
        icon = getPatchedValue(spell.icon, patch, "icon", clearOptionalFields),
        nameColor = getPatchedValue(spell.nameColor, patch, "nameColor", clearOptionalFields),
        resource = getPatchedValue(spell.resource, patch, "resource", clearOptionalFields),
        range = getPatchedValue(spell.range, patch, "range", clearOptionalFields),
        castTime = getPatchedValue(spell.castTime, patch, "castTime", clearOptionalFields),
        cooldown = getPatchedValue(spell.cooldown, patch, "cooldown", clearOptionalFields),
        description = getPatchedValue(spell.description, patch, "description", clearOptionalFields),
        effects = getPatchedValue(spell.effects, patch, "effects", clearOptionalFields),
        tags = getPatchedValue(spell.tags, patch, "tags", clearOptionalFields),
    }
    local ok, cleaned, errors = addon.Validators.ValidateSpell(candidate)
    if not ok then
        return nil, addon.Validators.GetFirstError(errors)
    end

    cleaned.id = spell.id
    cleaned.createdAt = spell.createdAt
    cleaned.updatedAt = getTimestamp()
    cleaned.revision = (tonumber(spell.revision) or 0) + 1
    spellbook.spells[spellID] = cleaned
    touchBook(spellbook)
    return cleaned
end

function addon.Database.MoveSpell(spellID, targetTabID, targetIndex)
    local spellbook, errorMessage = getActiveSpellbookOrError()
    local spell = spellbook and spellbook.spells[spellID]
    local targetTab = spellbook and spellbook.tabs[targetTabID]
    if not spell then
        return false, errorMessage or addon.L("ABILITY_NOT_FOUND")
    end
    if not targetTab then
        return false, addon.L("TARGET_TAB_NOT_FOUND")
    end

    for _, tabID in ipairs(spellbook.tabOrder) do
        local tab = spellbook.tabs[tabID]
        if tab then
            removeValue(tab.spellIds, spellID)
        end
    end

    local insertIndex = tonumber(targetIndex)
    if insertIndex then
        insertIndex = math.max(1, math.min(#targetTab.spellIds + 1, math.floor(insertIndex)))
        table.insert(targetTab.spellIds, insertIndex, spellID)
    else
        targetTab.spellIds[#targetTab.spellIds + 1] = spellID
    end
    targetTab.updatedAt = getTimestamp()
    targetTab.revision = (tonumber(targetTab.revision) or 0) + 1
    touchBook(spellbook)
    return true
end

function addon.Database.DeleteSpell(spellID)
    local spellbook, errorMessage = getActiveSpellbookOrError()
    if not spellbook or not spellbook.spells[spellID] then
        return false, errorMessage or addon.L("ABILITY_NOT_FOUND")
    end

    spellbook.spells[spellID] = nil
    if type(spellbook.favorites) == "table" then
        spellbook.favorites[spellID] = nil
    end
    for _, tabID in ipairs(spellbook.tabOrder) do
        local tab = spellbook.tabs[tabID]
        if tab then
            removeValue(tab.spellIds, spellID)
        end
    end
    touchBook(spellbook)
    return true
end

local function copyImportOwner(owner)
    if owner == nil then
        return nil
    end
    if type(owner) ~= "table" then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local cleaned = {}
    for _, key in ipairs({ "profileKey", "characterName", "realmName", "rpName", "ownerGuid" }) do
        local value = owner[key]
        if value ~= nil then
            if type(value) ~= "string"
                or value == ""
                or #value > addon.Constants.MAX_EXPORT_SOURCE_ID_LENGTH
                or value:find("[%c|]")
            then
                return nil, addon.L("IMPORT_INVALID_PAYLOAD")
            end
            cleaned[key] = value
        end
    end
    return next(cleaned) and cleaned or nil
end

local function isValidImportedSourceID(value)
    return type(value) == "string"
        and value ~= ""
        and #value <= addon.Constants.MAX_EXPORT_SOURCE_ID_LENGTH
        and not value:find("[%c|]")
end

local function isSupportedImportFormatVersion(value)
    return type(addon.Import) == "table"
        and type(addon.Import.IsSupportedFormatVersion) == "function"
        and addon.Import.IsSupportedFormatVersion(value)
end

local function isValidCopyPermissions(value)
    return type(value) == "table"
        and type(value.spells) == "boolean"
        and type(value.tabs) == "boolean"
end

function addon.Database.AddImportedSpell(decodedImport)
    if type(decodedImport) ~= "table"
        or not isSupportedImportFormatVersion(decodedImport.formatVersion)
        or type(decodedImport.spell) ~= "table"
        or type(decodedImport.exportMeta) ~= "table"
    then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local database = addon.Database.GetDB()
    if type(database) ~= "table" then
        return nil, addon.L("IMPORT_SAVE_FAILED")
    end
    addon.Database.PurgeExpiredImportedBooks()
    local importedBooks = ensureTable(database, "importedBooks")
    if countEntries(importedBooks) >= addon.Constants.MAX_IMPORTED_BOOKS then
        return nil, addon.L("TOO_MANY_IMPORTED_BOOKS")
    end

    local sourceBookID = decodedImport.sourceBookId
    local sourceSpellID = decodedImport.sourceSpellId
    if not isValidImportedSourceID(sourceBookID) or not isValidImportedSourceID(sourceSpellID) then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local meta = decodedImport.exportMeta
    local exportedAt = tonumber(meta.exportedAt)
    local expiresAt = tonumber(meta.expiresAt)
    if not isSupportedImportFormatVersion(meta.formatVersion)
        or meta.formatVersion ~= decodedImport.formatVersion
        or meta.exportType ~= "spell"
        or meta.sourceBookId ~= sourceBookID
        or type(meta.sourceSpellIds) ~= "table"
        or #meta.sourceSpellIds ~= 1
        or meta.sourceSpellIds[1] ~= sourceSpellID
        or type(meta.readOnly) ~= "boolean"
        or not isValidCopyPermissions(meta.copyPermissions)
        or meta.copyPermissions.tabs ~= false
        or not exportedAt
        or exportedAt < 0
        or exportedAt > addon.Constants.MAX_IMPORT_SAFE_INTEGER
        or exportedAt ~= math.floor(exportedAt)
        or not expiresAt
        or expiresAt < 0
        or expiresAt > addon.Constants.MAX_IMPORT_SAFE_INTEGER
        or expiresAt ~= math.floor(expiresAt)
        or (expiresAt ~= 0 and expiresAt < exportedAt)
    then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end
    if expiresAt ~= 0 and getTimestamp() >= expiresAt then
        return nil, addon.L("IMPORT_EXPIRED_CANNOT_IMPORT")
    end

    local valid, spell, errors = addon.Validators.ValidateSpell(decodedImport.spell)
    if not valid then
        return nil, addon.Validators.GetFirstError(errors)
    end
    local revision = tonumber(decodedImport.spell.revision)
    local createdAt = tonumber(decodedImport.spell.createdAt)
    local updatedAt = tonumber(decodedImport.spell.updatedAt)
    if not revision
        or revision < 1
        or revision > addon.Constants.MAX_LINK_REVISION
        or revision ~= math.floor(revision)
        or not createdAt
        or createdAt < 0
        or createdAt > addon.Constants.MAX_IMPORT_SAFE_INTEGER
        or createdAt ~= math.floor(createdAt)
        or not updatedAt
        or updatedAt < createdAt
        or updatedAt > addon.Constants.MAX_IMPORT_SAFE_INTEGER
        or updatedAt ~= math.floor(updatedAt)
        or decodedImport.spell.id ~= sourceSpellID
    then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local owner, ownerError = copyImportOwner(decodedImport.owner)
    if ownerError then
        return nil, ownerError
    end

    local timestamp = getTimestamp()
    local importID = generateID("import_", importedBooks)
    local spells = {}
    local localSpellID = generateID("sp_", spells)
    local tabID = "tab_imported"
    spell.id = localSpellID
    spell.createdAt = math.floor(createdAt)
    spell.updatedAt = math.floor(updatedAt)
    spell.revision = math.floor(revision)
    spells[localSpellID] = spell

    local importedBook = {
        id = importID,
        profileKey = "import:" .. importID,
        imported = true,
        source = "exportString",
        owner = owner,
        name = addon.L("IMPORTED_SPELLBOOK_NAME", spell.name),
        icon = spell.icon or addon.Constants.DEFAULT_BOOK_ICON,
        readOnly = meta.readOnly,
        expiresAt = math.floor(expiresAt),
        copyPermissions = {
            spells = meta.copyPermissions.spells,
            tabs = false,
        },
        importedAt = timestamp,
        tabs = {
            [tabID] = {
                id = tabID,
                name = addon.L("IMPORTED_TAB_NAME"),
                icon = addon.Constants.DEFAULT_TAB_ICON,
                spellIds = { localSpellID },
                createdAt = timestamp,
                updatedAt = timestamp,
                revision = 1,
            },
        },
        tabOrder = { tabID },
        spells = spells,
        sourceSpellMap = {
            [sourceSpellID] = localSpellID,
        },
        exportMeta = {
            formatVersion = meta.formatVersion,
            exportedAt = math.floor(exportedAt),
            exportedBy = owner,
            exportType = "spell",
            readOnly = meta.readOnly,
            expiresAt = math.floor(expiresAt),
            sourceBookId = sourceBookID,
            sourceSpellIds = { sourceSpellID },
            copyPermissions = {
                spells = meta.copyPermissions.spells,
                tabs = false,
            },
        },
        createdAt = timestamp,
        updatedAt = timestamp,
        revision = 1,
    }
    importedBooks[importID] = importedBook
    return importedBook
end

local function isValidImportedInteger(value, minimum, maximum)
    return type(value) == "number"
        and value >= minimum
        and value <= maximum
        and value == math.floor(value)
end

local function validateImportedMetadata(value, minimum)
    return isValidImportedInteger(value, minimum or 0, addon.Constants.MAX_IMPORT_SAFE_INTEGER)
end

local function copyList(values)
    local copy = {}
    for index, value in ipairs(values) do copy[index] = value end
    return copy
end

local function validateImportedCollectionMeta(decodedImport)
    local meta = decodedImport.exportMeta
    local sourceBookID = decodedImport.sourceBookId
    if type(meta) ~= "table"
        or not isSupportedImportFormatVersion(meta.formatVersion)
        or meta.formatVersion ~= decodedImport.formatVersion
        or (meta.exportType ~= "tab" and meta.exportType ~= "book")
        or meta.sourceBookId ~= sourceBookID
        or type(meta.readOnly) ~= "boolean"
        or not isValidCopyPermissions(meta.copyPermissions)
        or not validateImportedMetadata(meta.exportedAt, 0)
        or not validateImportedMetadata(meta.expiresAt, 0)
        or (meta.expiresAt ~= 0 and meta.expiresAt < meta.exportedAt)
        or type(meta.sourceTabIds) ~= "table"
        or type(meta.sourceSpellIds) ~= "table"
    then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end
    if meta.expiresAt ~= 0 and getTimestamp() >= meta.expiresAt then
        return nil, addon.L("IMPORT_EXPIRED_CANNOT_IMPORT")
    end
    return meta
end

function addon.Database.AddImportedBook(decodedImport)
    if type(decodedImport) ~= "table"
        or not isSupportedImportFormatVersion(decodedImport.formatVersion)
        or not isValidImportedSourceID(decodedImport.sourceBookId)
        or type(decodedImport.book) ~= "table"
    then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local meta, metaError = validateImportedCollectionMeta(decodedImport)
    if not meta then
        return nil, metaError
    end
    local book = decodedImport.book
    if book.id ~= decodedImport.sourceBookId
        or type(book.name) ~= "string"
        or book.name == ""
        or #book.name > addon.Validators.Limits.MAX_SHORT_FIELD_LENGTH
        or type(book.tabs) ~= "table"
        or type(book.tabOrder) ~= "table"
        or #book.tabOrder < 1
        or #book.tabOrder > addon.Constants.MAX_EXPORT_TABS
        or type(book.spells) ~= "table"
        or not validateImportedMetadata(book.createdAt, 0)
        or not validateImportedMetadata(book.updatedAt, book.createdAt)
        or not validateImportedMetadata(book.revision, 1)
        or book.revision > addon.Constants.MAX_LINK_REVISION
    then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local validBookIcon, cleanedBookIcon = addon.Validators.ValidateTab({ name = "Book", icon = book.icon })
    if not validBookIcon
        or (type(cleanedBookIcon.icon) == "number" and cleanedBookIcon.icon > addon.Constants.MAX_IMPORT_SAFE_INTEGER)
    then
        return nil, addon.L("INVALID_ICON")
    end

    local sourceTabs = {}
    local sourceSpells = {}
    local seenTabIDs = {}
    local seenSpellIDs = {}
    local sourceSpellIndex = 0
    for tabIndex, sourceTabID in ipairs(book.tabOrder) do
        local sourceTab = book.tabs[sourceTabID]
        if not isValidImportedSourceID(sourceTabID)
            or seenTabIDs[sourceTabID]
            or type(sourceTab) ~= "table"
            or sourceTab.id ~= sourceTabID
            or meta.sourceTabIds[tabIndex] ~= sourceTabID
            or not validateImportedMetadata(sourceTab.createdAt, 0)
            or not validateImportedMetadata(sourceTab.updatedAt, sourceTab.createdAt)
            or not validateImportedMetadata(sourceTab.revision, 1)
            or sourceTab.revision > addon.Constants.MAX_LINK_REVISION
        then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        seenTabIDs[sourceTabID] = true

        local validTab, cleanedTab, tabErrors = addon.Validators.ValidateTab(sourceTab)
        if not validTab then
            return nil, addon.Validators.GetFirstError(tabErrors)
        end
        if type(cleanedTab.icon) == "number" and cleanedTab.icon > addon.Constants.MAX_IMPORT_SAFE_INTEGER then
            return nil, addon.L("INVALID_ICON")
        end
        if type(sourceTab.spellIds) ~= "table" or #sourceTab.spellIds ~= #cleanedTab.spellIds then
            return nil, addon.L("IMPORT_INVALID_PAYLOAD")
        end
        for spellIndex, sourceSpellID in ipairs(sourceTab.spellIds) do
            if cleanedTab.spellIds[spellIndex] ~= sourceSpellID then
                return nil, addon.L("IMPORT_INVALID_PAYLOAD")
            end
        end
        cleanedTab.id = sourceTabID
        cleanedTab.createdAt = sourceTab.createdAt
        cleanedTab.updatedAt = sourceTab.updatedAt
        cleanedTab.revision = sourceTab.revision
        sourceTabs[#sourceTabs + 1] = cleanedTab

        for _, sourceSpellID in ipairs(cleanedTab.spellIds) do
            local sourceSpell = book.spells[sourceSpellID]
            sourceSpellIndex = sourceSpellIndex + 1
            if sourceSpellIndex > addon.Constants.MAX_EXPORT_SPELLS
                or not isValidImportedSourceID(sourceSpellID)
                or seenSpellIDs[sourceSpellID]
                or type(sourceSpell) ~= "table"
                or sourceSpell.id ~= sourceSpellID
                or meta.sourceSpellIds[sourceSpellIndex] ~= sourceSpellID
                or not validateImportedMetadata(sourceSpell.createdAt, 0)
                or not validateImportedMetadata(sourceSpell.updatedAt, sourceSpell.createdAt)
                or not validateImportedMetadata(sourceSpell.revision, 1)
                or sourceSpell.revision > addon.Constants.MAX_LINK_REVISION
            then
                return nil, addon.L("IMPORT_INVALID_PAYLOAD")
            end

            local validSpell, cleanedSpell, spellErrors = addon.Validators.ValidateSpell(sourceSpell)
            if not validSpell then
                return nil, addon.Validators.GetFirstError(spellErrors)
            end
            if type(cleanedSpell.icon) == "number" and cleanedSpell.icon > addon.Constants.MAX_IMPORT_SAFE_INTEGER then
                return nil, addon.L("INVALID_ICON")
            end
            cleanedSpell.id = sourceSpellID
            cleanedSpell.createdAt = sourceSpell.createdAt
            cleanedSpell.updatedAt = sourceSpell.updatedAt
            cleanedSpell.revision = sourceSpell.revision
            seenSpellIDs[sourceSpellID] = true
            sourceSpells[sourceSpellID] = cleanedSpell
        end
    end
    if #meta.sourceTabIds ~= #sourceTabs
        or #meta.sourceSpellIds ~= sourceSpellIndex
        or countEntries(book.tabs) ~= #sourceTabs
        or countEntries(book.spells) ~= sourceSpellIndex
    then
        return nil, addon.L("IMPORT_INVALID_PAYLOAD")
    end

    local owner, ownerError = copyImportOwner(decodedImport.owner)
    if ownerError then
        return nil, ownerError
    end
    local database = addon.Database.GetDB()
    if type(database) ~= "table" then
        return nil, addon.L("IMPORT_SAVE_FAILED")
    end
    addon.Database.PurgeExpiredImportedBooks()
    local importedBooks = ensureTable(database, "importedBooks")
    if countEntries(importedBooks) >= addon.Constants.MAX_IMPORTED_BOOKS then
        return nil, addon.L("TOO_MANY_IMPORTED_BOOKS")
    end

    local timestamp = getTimestamp()
    local importID = generateID("import_", importedBooks)
    local localTabs = {}
    local localTabOrder = {}
    local localSpells = {}
    local sourceTabMap = {}
    local sourceSpellMap = {}
    for _, sourceTab in ipairs(sourceTabs) do
        local localTabID = generateID("tab_", localTabs)
        local localTab = {
            id = localTabID,
            name = sourceTab.name,
            icon = sourceTab.icon,
            spellIds = {},
            createdAt = sourceTab.createdAt,
            updatedAt = sourceTab.updatedAt,
            revision = sourceTab.revision,
        }
        sourceTabMap[sourceTab.id] = localTabID
        localTabs[localTabID] = localTab
        localTabOrder[#localTabOrder + 1] = localTabID

        for _, sourceSpellID in ipairs(sourceTab.spellIds) do
            local sourceSpell = sourceSpells[sourceSpellID]
            local localSpellID = generateID("sp_", localSpells)
            sourceSpell.id = localSpellID
            localSpells[localSpellID] = sourceSpell
            localTab.spellIds[#localTab.spellIds + 1] = localSpellID
            sourceSpellMap[sourceSpellID] = localSpellID
        end
    end

    local importedBook = {
        id = importID,
        profileKey = "import:" .. importID,
        imported = true,
        source = "exportString",
        owner = owner,
        name = book.name,
        icon = cleanedBookIcon.icon or addon.Constants.DEFAULT_BOOK_ICON,
        readOnly = meta.readOnly,
        expiresAt = meta.expiresAt,
        copyPermissions = {
            spells = meta.copyPermissions.spells,
            tabs = meta.copyPermissions.tabs,
        },
        importedAt = timestamp,
        tabs = localTabs,
        tabOrder = localTabOrder,
        spells = localSpells,
        sourceTabMap = sourceTabMap,
        sourceSpellMap = sourceSpellMap,
        exportMeta = {
            formatVersion = meta.formatVersion,
            exportedAt = meta.exportedAt,
            exportedBy = owner,
            exportType = meta.exportType,
            readOnly = meta.readOnly,
            expiresAt = meta.expiresAt,
            sourceBookId = decodedImport.sourceBookId,
            sourceTabIds = copyList(meta.sourceTabIds),
            sourceSpellIds = copyList(meta.sourceSpellIds),
            copyPermissions = {
                spells = meta.copyPermissions.spells,
                tabs = meta.copyPermissions.tabs,
            },
        },
        createdAt = book.createdAt,
        updatedAt = book.updatedAt,
        revision = book.revision,
    }
    importedBooks[importID] = importedBook
    return importedBook
end
function addon.Database.ResolveSpellReference(ownerKey, spellID, revision)
    if type(ownerKey) ~= "string" or ownerKey == ""
        or type(spellID) ~= "string" or spellID == ""
        or type(revision) ~= "number"
    then
        return nil
    end

    local database = addon.Database.GetDB()
    local profiles = type(database) == "table" and database.profiles
    local profileData = type(profiles) == "table" and profiles[ownerKey]
    local spellbook = type(profileData) == "table" and profileData.spellbook
    local spell = type(spellbook) == "table"
        and type(spellbook.spells) == "table"
        and spellbook.spells[spellID]
    if type(spell) == "table" and tonumber(spell.revision) == revision then
        return spell, spellbook
    end

    local importedBooks = type(database) == "table" and database.importedBooks or nil
    if type(importedBooks) == "table" then
        for _, importedBook in pairs(importedBooks) do
            local owner = type(importedBook) == "table" and importedBook.owner or nil
            local sourceSpellMap = type(importedBook) == "table" and importedBook.sourceSpellMap or nil
            local localSpellID = type(sourceSpellMap) == "table" and sourceSpellMap[spellID] or nil
            local importedSpell = type(importedBook) == "table"
                and type(importedBook.spells) == "table"
                and importedBook.spells[localSpellID]
            if type(owner) == "table"
                and owner.profileKey == ownerKey
                and type(importedSpell) == "table"
                and tonumber(importedSpell.revision) == revision
            then
                return importedSpell, importedBook
            end
        end
    end
    return nil
end
