local _, addon = ...
 
local codec = { MAX_BYTES = 12000000, MAX_ENTRIES = 120000, MAX_DEPTH = 12, MAX_STRING = 8192 }
addon.PortableTable = codec

local function finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function budgets(options)
    if options == nil then return codec end
    if type(options) ~= "table" then return nil end
    local result = {}
    for _, key in ipairs({ "MAX_BYTES", "MAX_ENTRIES", "MAX_DEPTH", "MAX_STRING" }) do
        local value = options[key] or codec[key]
        if type(value) ~= "number" or not finite(value) or value < 1 or value % 1 ~= 0 then return nil end
        result[key] = value
    end
    return result
end

 
function codec.Encode(value, options)
    local limits = budgets(options)
    if not limits then return nil, "TRANSFER_INVALID" end
    local chunks, bytes, entries, active = {}, 0, 0, {}
    local function emit(part)
        bytes = bytes + #part
        if bytes > limits.MAX_BYTES then error("limit") end
        chunks[#chunks + 1] = part
    end
    local function write(item, depth)
        if depth > limits.MAX_DEPTH then error("depth") end
        local kind = type(item)
        if kind == "boolean" then emit(item and "b1" or "b0")
        elseif kind == "number" then
            if not finite(item) then error("number") end
            emit("n" .. string.format("%.17g", item) .. ":")
        elseif kind == "string" then
            if #item > limits.MAX_STRING then error("string") end
            emit("s" .. #item .. ":")
            emit((item:gsub(".", function(c) return string.format("%02X", string.byte(c)) end)))
        elseif kind == "table" then
            if getmetatable(item) or active[item] then error("table") end
            active[item] = true
            local keys = {}
            for key in pairs(item) do
                if type(key) ~= "string" and (type(key) ~= "number" or not finite(key)) then error("key") end
                entries = entries + 1
                if entries > limits.MAX_ENTRIES then error("entries") end
                keys[#keys + 1] = key
            end
            table.sort(keys, function(a, b)
                if type(a) ~= type(b) then return type(a) == "number" end
                return a < b
            end)
            emit("t" .. #keys .. ":")
            for _, key in ipairs(keys) do write(key, depth + 1); write(item[key], depth + 1) end
            active[item] = nil
        else error("type") end
    end
    local ok = pcall(write, value, 0)
    if not ok then return nil, "TRANSFER_INVALID" end
    return table.concat(chunks)
end

function codec.Decode(input, options)
    local limits = budgets(options)
    if not limits or type(input) ~= "string" or #input == 0 or #input > limits.MAX_BYTES then return nil, "TRANSFER_INVALID" end
    local cursor, entries = 1, 0
    local function numberToken(integer)
        local stop = input:find(":", cursor, true)
        if not stop or stop - cursor > 32 then error("length") end
        local token = input:sub(cursor, stop - 1)
        if token == "" or token:find("[^%d%.eE%+%-]") then error("number") end
        local value = tonumber(token)
        if not value or not finite(value) or (integer and (value < 0 or value ~= math.floor(value)
            or not token:match("^%d+$"))) then error("number") end
        cursor = stop + 1
        return value
    end
    local function read(depth)
        if depth > limits.MAX_DEPTH then error("depth") end
        local tag = input:sub(cursor, cursor); cursor = cursor + 1
        if tag == "b" then
            local flag = input:sub(cursor, cursor); cursor = cursor + 1
            if flag ~= "0" and flag ~= "1" then error("boolean") end
            return flag == "1"
        elseif tag == "n" then return numberToken(false)
        elseif tag == "s" then
            local size = numberToken(true)
            if size > limits.MAX_STRING or cursor + size * 2 - 1 > #input then error("string") end
            local hex = input:sub(cursor, cursor + size * 2 - 1); cursor = cursor + size * 2
            if hex:find("[^%x]") then error("hex") end
            return (hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
        elseif tag == "t" then
            local size, result, seen = numberToken(true), {}, {}
            entries = entries + size
            if entries > limits.MAX_ENTRIES then error("entries") end
            for _ = 1, size do
                local key = read(depth + 1)
                if (type(key) ~= "string" and type(key) ~= "number") or seen[key] then error("key") end
                seen[key] = true
                result[key] = read(depth + 1)
            end
            return result
        end
        error("tag")
    end
    local ok, value = pcall(read, 0)
    if not ok or cursor ~= #input + 1 then return nil, "TRANSFER_INVALID" end
    return value
end
