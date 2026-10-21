local _, addon = ...

addon.ReferenceIndex = {}

local indexedSource
local booksByOwner

local function rebuild(importedBooks)
    indexedSource = importedBooks
    booksByOwner = {}
    if type(importedBooks) ~= "table" then
        return
    end

    for _, book in pairs(importedBooks) do
        local owner = type(book) == "table" and book.owner or nil
        local ownerKey = type(owner) == "table" and owner.profileKey or nil
        if type(ownerKey) == "string" and ownerKey ~= "" then
            local bucket = booksByOwner[ownerKey]
            if not bucket then
                bucket = {}
                booksByOwner[ownerKey] = bucket
            end
            bucket[#bucket + 1] = book
        end
    end

    for _, bucket in pairs(booksByOwner) do
        table.sort(bucket, function(first, second)
            local firstImportedAt = tonumber(first.importedAt) or 0
            local secondImportedAt = tonumber(second.importedAt) or 0
            if firstImportedAt == secondImportedAt then
                return tostring(first.id or "") > tostring(second.id or "")
            end
            return firstImportedAt > secondImportedAt
        end)
    end
end

function addon.ReferenceIndex.Invalidate()
    indexedSource = nil
    booksByOwner = nil
end

function addon.ReferenceIndex.Resolve(importedBooks, ownerKey, spellID, revision)
    if importedBooks ~= indexedSource or not booksByOwner then
        rebuild(importedBooks)
    end

    local bucket = booksByOwner[ownerKey]
    if not bucket then
        return nil
    end

    for _, importedBook in ipairs(bucket) do
        local sourceSpellMap = type(importedBook.sourceSpellMap) == "table"
            and importedBook.sourceSpellMap
            or nil
        local localSpellID = sourceSpellMap and sourceSpellMap[spellID] or nil
        local importedSpell = localSpellID
            and type(importedBook.spells) == "table"
            and importedBook.spells[localSpellID]
            or nil
        if type(importedSpell) == "table"
            and tonumber(importedSpell.revision) == revision
        then
            return importedSpell, importedBook
        end
    end
    return nil
end
