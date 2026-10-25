local function rejected(t, value, failure)
    t.eq(value, nil)
    t.eq(failure, "TRANSFER_INVALID")
end

return {
    format = 1, area = "portable", count = 5,

    { id = "portable.round-trip", run = function(t, api)

        local codec = api.portable
        for _, value in ipairs({
            false, true, 0, -3.5, "", "\000\010\255", {},
            { [2] = "second", name = "Spark", nested = { active = false } },
        })
        do

            local encoded = assert(codec.Encode(value))
            t.eq(type(encoded), "string")
            t.same(codec.Decode(encoded), value)
        end
    end },

    { id = "portable.payload-compatibility-and-determinism", run = function(t, api)

        local codec = api.portable

        for _, row in ipairs({
            { "t2:n1:b0s1:78s2:4100", { [1] = false, x = "A\000" } },
            { "t1:s1:6Et0:", { n = {} } },
        })
        do

            local value, failure = codec.Decode(row[1])
            t.eq(failure, nil)
            t.same(value, row[2])
            rejected(t, codec.Decode(row[1] .. "!"))
        end

        local left, right = {}, {}
        left[1], left.x, left.n = false, "A\000", {}
        right.n, right.x, right[1] = {}, "A\000", false

        t.eq(assert(codec.Encode(left)), assert(codec.Encode(right)))
    end },

    { id = "portable.unsafe-inputs-and-options", run = function(t, api)

        local codec, cycle = api.portable, {}
        cycle.self = cycle

        for _, value in ipairs({
            function() end, math.huge, -math.huge, 0 / 0,
            { bad = function() end }, { [true] = 1 },
            setmetatable({}, {}), cycle,
        })
        do

            rejected(t, codec.Encode(value))
        end

        rejected(t, codec.Encode(nil))
        for _, options in ipairs({
            true, { MAX_DEPTH = 0 }, { MAX_ENTRIES = 1.5 },
            { MAX_STRING = math.huge }, { MAX_BYTES = "8" },
        })
        do

            rejected(t, codec.Encode(true, options))
            rejected(t, codec.Decode("b1", options))
        end
    end },

    { id = "portable.rejects-malformed-frames", run = function(t, api)

        local codec = api.portable
        local encoded = assert(codec.Encode({ x = "AB" }))
        for length = 0, #encoded - 1
        do

            rejected(t, codec.Decode(encoded:sub(1, length)))
        end

        rejected(t, codec.Decode(encoded .. "!"))
        rejected(t, codec.Decode(false))

        for _, input in ipairs({
            "?", "b2", "n1e999:", "s1:GG", "t1:b1b0",
            "t2:s1:61b0s1:61b1", "return {}",
        })
        do

            rejected(t, codec.Decode(input))
        end
    end },

    { id = "portable.enforces-budget-boundaries", run = function(t, api)

        local codec = api.portable
        local bytes = assert(codec.Encode("ab"))
        for _, row in ipairs({
            { "MAX_STRING", "ab", 2 },
            { "MAX_ENTRIES", { a = { b = true } }, 2 },
            { "MAX_DEPTH", { { true } }, 2 },
            { "MAX_BYTES", "ab", #bytes },
        })
        do

            local key, value, maximum = row[1], row[2], row[3]
            local encoded = assert(codec.Encode(value))
            t.eq(type(codec.Encode(value, { [key] = maximum })), "string", key)
            t.same(codec.Decode(encoded, { [key] = maximum }), value, key)
            rejected(t, codec.Encode(value, { [key] = maximum - 1 }))
            rejected(t, codec.Decode(encoded, { [key] = maximum - 1 }))
        end
    end },
}
