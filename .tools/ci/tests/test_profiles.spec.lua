return {
    format = 1, area = "backup", count = 10,

    { id = "backup.settings-rejects-lossy-normalization-without-mutation", run = function(t, api, F)
        for _, settings in ipairs({
            { gameMasterPlayer = { turnSoundPreset = "not-a-preset" } },
            { gameMasterPlayer = { incomingActionSoundEnabled = "true" } },
            { gameMasterPlayer = { incomingActionSoundPreset = "kit:0" } },
            { onboarding = { progress = { npc = "invalid step" } } },
        }) do
            local original = F.copy(settings)
            t.eq(api.backup.Settings(settings), false)
            t.same(settings, original)
        end
    end },

    { id = "backup.settings-preserves-extensions-and-absent-defaults", run = function(t, api, F)
        for _, settings in ipairs({
            {},
            { extension = { magicType = "User text", [2] = false },
                gameMasterPlayer = { turnSoundPreset = "kit:2147483647", extension = true },
                onboarding = { revision = 0, completed = { npc = true }, progress = { npc = "step_1" } } },
        }) do
            local original = F.copy(settings)
            t.eq(api.backup.Settings(settings), true)
            t.same(settings, original)
        end
    end },

    { id = "backup.pooled-legacy-and-typed-values-remain-independent", run = function(t, api, F)
        for index = 1, 64 do
            local first = F.spell({ id = "first", icon = 123, description = "Literal\000\255" .. index,
                tags = { custom = "unchanged" }, resource = index % 2 == 0 and "" or false,
                extra = { [0] = false, ["0"] = "distinct", [0.5] = index } })
            if index % 3 == 0 then first.effects = { buff = true, durationRounds = 0 } end
            local second = F.copy(first)
            second.id, second.ownerKey = "second", "other"
            local original = { first, second, literal = { version = 1, data = {}, references = {}, spells = {} } }
            local packed = assert(api.packing.Encode(original))
            local restored = assert(api.packing.Decode(packed))
            t.same(restored, original)
            restored[1].tags.custom = "changed"
            t.eq(restored[2].tags.custom, "unchanged")
            t.eq(original[1].tags.custom, "unchanged")
        end
    end },

    { id = "backup.pooled-overlap-and-forged-paths-fail-closed", run = function(t, api, F)
        local first = F.spell({ id = "first", icon = 123, tags = {}, effects = {},
            description = string.rep("Synthetic description ", 20) })
        local second = F.copy(first)
        second.id = "second"
        local encoded = assert(api.packing.Encode({ first, second }))
        for _, mutate in ipairs({
            function(wire) wire.references[1].index = 0 end,
            function(wire) wire.references[1].index = 1.5 end,
            function(wire) wire.references[1].path = { "missing" } end,
            function(wire) wire.references[1].path = { false } end,
            function(wire) wire.spells[1].ownerKey = false end,
            function(wire) wire.data[1].description = "overlap" end,
        }) do
            local wire = assert(api.portable.Decode(encoded))
            mutate(wire)
            t.eq(api.packing.Decode(assert(api.portable.Encode(wire))), nil)
        end
    end },

    { id = "backup.pooled-content-is-lossless-and-independent", run = function(t, api, F)
        local first = F.spell({ id = "first", ownerKey = "source", createdAt = 1, updatedAt = 2, revision = 3,
            icon = 123, resource = "Mana", range = "40 meters", description = string.rep("Synthetic description. ", 20),
            tags = { magicType = "Arcane", extra = "custom" }, effects = { buff = true, durationRounds = 0 } })
        local second = F.copy(first)
        second.id, second.ownerKey, second.revision = "second", "other", 9
        local original = { first = first, second = second, unknown = { enabled = false, empty = "" } }
        local before = F.copy(original)
        local packed = assert(api.packing.Encode(original))
        local envelope = assert(api.portable.Decode(packed))
        t.eq(#envelope.spells, 1)
        t.eq(#envelope.references, 2)
        local restored = assert(api.packing.Decode(packed))
        t.same(restored, original)
        t.same(original, before)
        restored.first.tags.extra = "changed"
        t.eq(restored.second.tags.extra, "custom")
        t.eq(original.first.tags.extra, "custom")
    end },

    { id = "backup.pooled-references-and-expansion-are-bounded", run = function(t, api, F)
        local spell = F.spell({ icon = 123, resource = "Mana", range = "40 meters",
            description = string.rep("Synthetic. ", 100), tags = {}, effects = {} })
        local source = { F.copy(spell), F.copy(spell) }
        local encoded = assert(api.packing.Encode(source))
        local envelope = assert(api.portable.Decode(encoded))
        envelope.references[2].path = F.copy(envelope.references[1].path)
        t.eq(api.packing.Decode(assert(api.portable.Encode(envelope))), nil)
        t.eq(api.packing.Decode(encoded, { MAX_BYTES = #encoded - 1 }), nil)
        t.eq(api.packing.Decode(encoded, { MAX_ENTRIES = 5 }), nil)
        t.eq(api.packing.Decode(encoded, { MAX_DEPTH = 1 }), nil)
        t.same(source, { spell, spell })
    end },

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
