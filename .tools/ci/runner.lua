local function keys(value, allowed, count)

    assert(type(value) == "table", "Expected a descriptor table")

    for key in pairs(value)
    do
        local index = count and type(key) == "number"
            and key % 1 == 0 and key >= 1 and key <= count

        assert(allowed[key] or index, "Unsupported field: " .. tostring(key))
    end
end


local function validate(runner)

    assert(type(runner) == "table", "Runner returned no descriptor")

    assert(runner.format == 1 and type(runner.area) == "string",
        "Unsupported runner format/area")

    local count = runner.count

    assert(type(count) == "number" and count >= 1 and count % 1 == 0,
        "A positive declared case count is required")

    keys(runner, { format = true, area = true, count = true }, count)

    local seen = {}

    for index = 1, count
    do
        local case = runner[index]

        keys(case, { id = true, run = true })

        assert(type(case.id) == "string"
            and case.id:match("^[a-z][a-z0-9_.-]+$") and not seen[case.id],
            "Invalid or duplicate case ID")

        assert(type(case.run) == "function", "Missing case function")

        seen[case.id] = true
    end

    return runner
end


local function probeRunner(name)

    local case = { id = "probe.one", run = function(t)
        t.eq(true, true)
    end }

    local runner = { format = 1, area = "portable", count = 1, case }

    if name == "ok" then

    elseif name == "assertion" then
        case.run = function(t)
            t.eq(1, 2)
        end

    elseif name == "suppressed" then
        case.run = function(t)
            pcall(function()
                t.eq(1, 2)
            end)

            t.eq(true, true)
        end

    elseif name == "empty" then
        runner.count, runner[1] = 0, nil

    elseif name == "duplicate" then
        runner.count, runner[2] = 2, case

    elseif name == "skip" then
        case.skip = true

    elseif name == "noassert" then
        case.run = function()
        end

    elseif name == "plan" then
        runner.count = 2

    elseif name == "setup" then
        runner.area = "unknown"

    elseif name == "return" then
        return nil

    else
        error("Unknown runner probe: " .. tostring(name))
    end

    return runner
end


local function main()

    assert(_VERSION == "Lua 5.1", "Lua 5.1 semantics required")

    local root, path, report, probe = arg[1], arg[2], arg[3], arg[4]

    assert(root and path and report and probe, "Missing runner arguments")

    if probe == "early" then
        os.exit(0)
    end

    if probe == "timeout" then
        while true
        do
        end
    end

    local fixtures = assert(loadfile(
        root .. "/.tools/ci/tests/static.lua"))(root)

    local function readRunner()
        if probe ~= "" then
            return probeRunner(probe)
        end

        return fixtures.runner(path)
    end

    local runner, rows, failures = validate(readRunner()), {}, 0

    for index = 1, runner.count
    do
        local assertions, assertionFailed = 0, false

        local function check(condition, message)
            assertions = assertions + 1

            if not condition then
                assertionFailed = true
                error(message, 3)
            end
        end

        local t = {

            eq = function(actual, expected, label)
                check(actual == expected, (label or "equality")
                    .. ": expected " .. tostring(expected)
                    .. ", got " .. tostring(actual))
            end,

            same = function(actual, expected, label)
                check(fixtures.equal(actual, expected),
                    label or "Structured values differ")
            end,
        }

        local success, failure = xpcall(function()
            local fresh = validate(readRunner())

            assert(fresh.count == runner.count and fresh.area == runner.area,
                "Runner declaration changed between cases")

            for position = 1, runner.count
            do
                assert(fresh[position].id == runner[position].id,
                    "Runner IDs changed between cases")
            end

            fresh[index].run(t, fixtures.fresh(fresh.area), fixtures)

            assert(assertions > 0 and not assertionFailed,
                "No assertions executed, or an assertion failure was suppressed")
        end, debug.traceback)

        rows[#rows + 1] = { runner[index].id, assertions }

        if not success then
            failures = failures + 1
            io.stderr:write(runner[index].id, "\n", tostring(failure), "\n")
        end
    end

    assert(failures == 0, tostring(failures) .. " contract case(s) failed")

    local output = assert(io.open(report, "wb"))

    assert(output:write(string.format("SBTEST1\t%d\t%d\t0\n",
        runner.count, #rows)))

    for _, row in ipairs(rows)
    do
        assert(output:write(row[1], "\t", tostring(row[2]), "\n"))
    end

    assert(output:close())
end


local success, failure = xpcall(main, debug.traceback)

if not success then
    io.stderr:write(tostring(failure), "\n")
    os.exit(1)
end
