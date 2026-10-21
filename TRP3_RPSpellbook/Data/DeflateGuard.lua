local _, addon = ...

addon.DeflateGuard = {}

local lengthBases = {
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
    35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
}
local lengthExtras = {
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
    3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
}
local distanceExtras = {
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6,
    6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
}

local function reverseBits(value, count)
    local reversed = 0
    for _ = 1, count do
        reversed = reversed * 2 + value % 2
        value = math.floor(value / 2)
    end
    return reversed
end

local function createReader(data, offset)
    local position = offset or 1
    local buffer = 0
    local buffered = 0
    local reader = {}

    function reader.read(count)
        local value = 0
        local factor = 1
        for _ = 1, count do
            if buffered == 0 then
                buffer = data:byte(position)
                if not buffer then return nil end
                position = position + 1
                buffered = 8
            end
            value = value + (buffer % 2) * factor
            buffer = math.floor(buffer / 2)
            buffered = buffered - 1
            factor = factor * 2
        end
        return value
    end

    function reader.align()
        buffer = 0
        buffered = 0
    end

    function reader.remaining()
        return #data - position + 1
    end

    return reader
end

local function buildDecoder(lengths)
    local counts = {}
    local maximum = 0
    for _, length in ipairs(lengths) do
        if length < 0 or length > 15 then return nil end
        if length > 0 then
            counts[length] = (counts[length] or 0) + 1
            maximum = math.max(maximum, length)
        end
    end
    if maximum == 0 then return nil end

    local nextCode = {}
    local code = 0
    for bits = 1, maximum do
        code = (code + (counts[bits - 1] or 0)) * 2
        if code + (counts[bits] or 0) > 2 ^ bits then return nil end
        nextCode[bits] = code
    end
    local lookup = {}
    for index, length in ipairs(lengths) do
        if length > 0 then
            lookup[length] = lookup[length] or {}
            local canonical = nextCode[length]
            nextCode[length] = canonical + 1
            lookup[length][reverseBits(canonical, length)] = index - 1
        end
    end
    return { lookup = lookup, maximum = maximum }
end

local function decodeSymbol(reader, decoder)
    local code = 0
    local factor = 1
    for length = 1, decoder.maximum do
        local bit = reader.read(1)
        if bit == nil then return nil end
        code = code + bit * factor
        local symbol = decoder.lookup[length] and decoder.lookup[length][code]
        if symbol ~= nil then return symbol end
        factor = factor * 2
    end
    return nil
end

local function fixedDecoders()
    local literals = {}
    for symbol = 0, 287 do
        literals[symbol + 1] = symbol <= 143 and 8
            or (symbol <= 255 and 9 or (symbol <= 279 and 7 or 8))
    end
    local distances = {}
    for symbol = 0, 31 do distances[symbol + 1] = 5 end
    return buildDecoder(literals), buildDecoder(distances)
end

local function dynamicDecoders(reader)
    local literalCount = reader.read(5)
    local distanceCount = reader.read(5)
    local codeCount = reader.read(4)
    if not literalCount or not distanceCount or not codeCount then return nil end
    literalCount = literalCount + 257
    distanceCount = distanceCount + 1
    codeCount = codeCount + 4
    local order = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }
    local codeLengths = {}
    for index = 1, 19 do codeLengths[index] = 0 end
    for index = 1, codeCount do
        local value = reader.read(3)
        if value == nil then return nil end
        codeLengths[order[index] + 1] = value
    end
    local codeDecoder = buildDecoder(codeLengths)
    if not codeDecoder then return nil end

    local lengths = {}
    local total = literalCount + distanceCount
    while #lengths < total do
        local symbol = decodeSymbol(reader, codeDecoder)
        if symbol == nil then return nil end
        if symbol <= 15 then
            lengths[#lengths + 1] = symbol
        else
            local repeatCount
            local value = 0
            if symbol == 16 then
                if #lengths == 0 then return nil end
                local extra = reader.read(2)
                if extra == nil then return nil end
                repeatCount = extra + 3
                value = lengths[#lengths]
            elseif symbol == 17 then
                local extra = reader.read(3)
                if extra == nil then return nil end
                repeatCount = extra + 3
            elseif symbol == 18 then
                local extra = reader.read(7)
                if extra == nil then return nil end
                repeatCount = extra + 11
            else
                return nil
            end
            if #lengths + repeatCount > total then return nil end
            for _ = 1, repeatCount do lengths[#lengths + 1] = value end
        end
    end
    local literals = {}
    local distances = {}
    for index = 1, literalCount do literals[index] = lengths[index] end
    for index = 1, distanceCount do
        distances[index] = lengths[literalCount + index]
    end
    if literals[257] == 0 then return nil end
    return buildDecoder(literals), buildDecoder(distances)
end

local function measureCompressedBlock(reader, literalDecoder, distanceDecoder, output, maximum)
    while true do
        local symbol = decodeSymbol(reader, literalDecoder)
        if symbol == nil then return nil, "invalid" end
        if symbol < 256 then
            output = output + 1
        elseif symbol == 256 then
            return output
        elseif symbol >= 257 and symbol <= 285 and distanceDecoder then
            local index = symbol - 256
            local extraBits = lengthExtras[index]
            local extra = extraBits > 0 and reader.read(extraBits) or 0
            local distanceSymbol = decodeSymbol(reader, distanceDecoder)
            if extra == nil or distanceSymbol == nil or distanceSymbol > 29 then
                return nil, "invalid"
            end
            local distanceExtraBits = distanceExtras[distanceSymbol + 1]
            local distanceExtra = distanceExtraBits > 0 and reader.read(distanceExtraBits) or 0
            if distanceExtra == nil then return nil, "invalid" end
            local distanceBase = distanceSymbol < 4 and distanceSymbol + 1
                or 2 ^ (math.floor(distanceSymbol / 2) - 1)
                    * (2 + distanceSymbol % 2) + 1
            if distanceBase + distanceExtra > output then return nil, "invalid" end
            output = output + lengthBases[index] + extra
        else
            return nil, "invalid"
        end
        if output > maximum then return nil, "too_large" end
    end
end

function addon.DeflateGuard.MeasureZlib(data, maximum)
    if type(data) ~= "string" or #data < 6 then return nil, "invalid" end
    maximum = math.max(0, math.floor(tonumber(maximum) or 0))
    local cmf, flags = data:byte(1, 2)
    if cmf % 16 ~= 8 or math.floor(cmf / 16) > 7
        or (cmf * 256 + flags) % 31 ~= 0
        or math.floor(flags / 32) % 2 ~= 0
    then
        return nil, "invalid"
    end

    local reader = createReader(data, 3)
    local output = 0
    local final = false
    while not final do
        local finalBit = reader.read(1)
        local blockType = reader.read(2)
        if finalBit == nil or blockType == nil or blockType == 3 then
            return nil, "invalid"
        end
        final = finalBit == 1
        if blockType == 0 then
            reader.align()
            local length = reader.read(16)
            local inverted = reader.read(16)
            if not length or not inverted or length + inverted ~= 65535 then
                return nil, "invalid"
            end
            for _ = 1, length do
                if reader.read(8) == nil then return nil, "invalid" end
            end
            output = output + length
        else
            local literalDecoder, distanceDecoder
            if blockType == 1 then
                literalDecoder, distanceDecoder = fixedDecoders()
            else
                literalDecoder, distanceDecoder = dynamicDecoders(reader)
            end
            if not literalDecoder then return nil, "invalid" end
            local errorMessage
            output, errorMessage = measureCompressedBlock(
                reader,
                literalDecoder,
                distanceDecoder,
                output,
                maximum
            )
            if not output then return nil, errorMessage end
        end
        if output > maximum then return nil, "too_large" end
    end
    reader.align()
    if reader.remaining() ~= 4 then return nil, "invalid" end
    return output
end
