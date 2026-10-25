return {
    format = 1, area = "backup", count = 4,

    { id = "backup.valid-book-and-independent-clone", run = function(t, api, F)

        local book = F.book("source")
        t.eq(api.backup.Book(book, "source"), true)
        local clone = assert(api.backup.Clone(book))
        t.same(clone, book)
        clone.spells.spark.name = "Changed"

        t.eq(book.spells.spark.name, "Spark")
        t.eq(api.backup.Clone(function() end), nil)
        t.eq(api.backup.Book(false, "source"), false)
    end },

    { id = "backup.rejects-broken-reference-graphs", run = function(t, api, F)

        local mutations = {
            function(b)
                b.tabOrder = {}
            end,
            function(b)
                b.tabOrder[2] = "general"
            end,
            function(b)
                b.tabOrder.extra = "general"
            end,
            function(b)
                b.tabs.general.spellIds = { "missing" }
            end,
            function(b)
                b.tabs.general.spellIds = { "spark", "spark" }
            end,
            function(b)
                b.tabs.general.id = "different"
            end,
            function(b)
                b.tabs.unlisted = {
                    id = "unlisted", name = "Other", spellIds = {},
                }
            end,
            function(b)
                b.spells.extra = F.spell({ id = "extra" })
            end,
            function(b)
                b.spells.spark.id = "different"
            end,
            function(b)
                b.spells.spark.name = " "
            end,
            function(b)
                b.favorites.missing = true
            end,
            function(b)
                b.favorites.spark = false
            end,
            function(b)
                b.favorites = nil
            end,
            function(b)
                b.profileKey = "different"
            end,
        }

        for index, mutate in ipairs(mutations)
        do

            local book = F.book("source")
            mutate(book)

            local before = F.copy(book)
            t.eq(api.backup.Book(book, "source"), false, "graph " .. index)
            t.same(book, before, "Validation must not mutate rejected data")
        end
    end },

    { id = "backup.rebinds-only-owned-identities", run = function(t, api, F)

        for _, bookID in ipairs({ "book_source", "custom-book" })
        do

            local root = F.binding()
            root.profiles.other = F.binding("other").profiles.other

            local other = F.copy(root.profiles.other)
            local book = root.profiles.source.spellbook
            book.id = bookID
            book.spells.foreign = F.spell({
                id = "foreign", ownerKey = "third-party",
            })
            book.tabs.general.spellIds[2] = "foreign"

            t.eq(api.backup.Rebind(root, "source", "destination"), true)
            t.eq(root.profiles.source, nil)
            local profile = root.profiles.destination
            book = profile.spellbook

            t.eq(profile.profileKey, "destination")
            t.eq(profile.owner.profileKey, "destination")
            t.eq(book.profileKey, "destination")
            t.eq(book.id, bookID == "book_source" and "book_destination" or bookID)
            t.eq(book.spells.spark.ownerKey, "destination")
            t.eq(book.spells.spark.name, "Spark")
            t.eq(book.spells.foreign.ownerKey, "third-party")
            t.same(book.favorites, { spark = true })
            t.same(root.profiles.other, other)
            t.eq(api.backup.Book(book, "destination"), true)
        end
    end },

    { id = "backup.rebind-failures-and-noops-preserve-data", run = function(t, api, F)

        for _, pair in ipairs({
            { "missing", "destination" }, { "source", "occupied" },
            { "source", "bad|key" }, { "", "destination" },
            { "source", "" }, { false, "destination" },
        })
        do

            local root = F.binding()
            root.profiles.occupied = F.binding("occupied").profiles.occupied

            local before = F.copy(root)
            t.eq(api.backup.Rebind(root, pair[1], pair[2]), false)
            t.same(root, before)
        end

        local root = F.binding()
        local before = F.copy(root)
        t.eq(api.backup.Rebind(root, "source", "source"), true)
        t.same(root, before)
        t.eq(api.backup.Rebind(root, nil, nil), true)
        t.same(root, before)
    end },
}
