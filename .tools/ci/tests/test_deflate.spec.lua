local function fixedChain(count)
    local bytes, byte, bits = {}, 0, 0
    local function write(value, length)
        for _ = 1, length do
            byte = byte + value % 2 * 2 ^ bits
            value, bits = math.floor(value / 2), bits + 1
            if bits == 8 then
                bytes[#bytes + 1], byte, bits = string.char(byte), 0, 0
            end
        end
    end
    for index = 1, count do
        write(index == count and 1 or 0, 1)
        write(1, 2)
        write(0, 7)
    end
    if bits > 0 then bytes[#bytes + 1] = string.char(byte) end
    return "\120\156" .. table.concat(bytes) .. "\0\0\0\1"
end

return {
    format = 1, area = "deflate", count = 4,

    { id = "deflate.fixed-trees-are-built-once-across-blocks-and-streams", run = function(t, api)
        t.eq(api.decoderWork(), 0)
        t.eq(api.deflate.MeasureZlib(fixedChain(129), 0), 0)
        t.eq(api.decoderWork(), 321)
        t.eq(api.deflate.MeasureZlib(fixedChain(1), 0), 0)
        t.eq(api.decoderWork(), 322)
    end },

    { id = "deflate.fixed-block-work-is-bounded", run = function(t, api)
        local guard = api.deflate
        t.eq(guard.MeasureZlib(fixedChain(4096), 0), 0)
        local measured, reason = guard.MeasureZlib(fixedChain(4097), 0)
        t.eq(measured, nil)
        t.eq(reason, "too_complex")
        t.eq(guard.MeasureZlib(fixedChain(1), 0), 0)
    end },

    { id = "deflate.stored-blocks-use-the-same-work-budget", run = function(t, api)
        for _, count in ipairs({ 4096, 4097 }) do
            local stream = "\120\156" .. string.rep("\0\0\0\255\255", count - 1)
                .. "\1\0\0\255\255\0\0\0\1"
            local measured, reason = api.deflate.MeasureZlib(stream, 0)
            t.eq(measured, count == 4096 and 0 or nil)
            t.eq(reason, count == 4097 and "too_complex" or nil)
        end
    end },

    { id = "deflate.output-cap-and-trailing-data-remain-strict", run = function(t, api)
        local stream = "\120\156" .. string.rep("\2\8\32\128\0", 32)
            .. "\115\4\0\0\66\0\66"
        t.eq(api.deflate.MeasureZlib(stream, 1), 1)
        local measured, reason = api.deflate.MeasureZlib(stream, 0)
        t.eq(measured, nil)
        t.eq(reason, "too_large")
        measured, reason = api.deflate.MeasureZlib(stream .. "!", 1)
        t.eq(measured, nil)
        t.eq(reason, "invalid")
    end },
}
