local _, addon = ...

addon.ExportCodec = {}

local codec = addon.ExportCodec
local constants = addon.Constants
local COMPACT_MARKER = constants.COMPACT_EXPORT_FORMAT_PREFIX
    .. tostring(constants.COMPACT_EXPORT_CODEC_VERSION)
local COMPRESSION_CONFIG = { level = 6 }

local function getLibDeflate()
    local libStub = type(_G) == "table" and rawget(_G, "LibStub") or nil
    if type(libStub) ~= "table" or type(libStub.GetLibrary) ~= "function" then
        return nil
    end

    local success, library = pcall(libStub.GetLibrary, libStub, "LibDeflate", true)
    if not success
        or type(library) ~= "table"
        or type(library.CompressZlib) ~= "function"
        or type(library.DecompressZlib) ~= "function"
        or type(library.EncodeForPrint) ~= "function"
        or type(library.DecodeForPrint) ~= "function"
    then
        return nil
    end
    return library
end

function codec.IsCompact(exportString)
    if type(exportString) ~= "string"
        or exportString:sub(1, #constants.COMPACT_EXPORT_FORMAT_PREFIX)
            ~= constants.COMPACT_EXPORT_FORMAT_PREFIX
    then
        return false
    end
    local versionOffset = #constants.COMPACT_EXPORT_FORMAT_PREFIX + 1
    return exportString:sub(versionOffset, versionOffset):match("^%d$") ~= nil
end

function codec.Encode(payload)
    if type(payload) ~= "string"
        or payload == ""
        or #payload > constants.MAX_EXPORT_PAYLOAD_LENGTH
    then
        return nil
    end

    local library = getLibDeflate()
    if not library then
        return nil
    end

    local compressedSuccessfully, compressed = pcall(
        library.CompressZlib,
        library,
        payload,
        COMPRESSION_CONFIG
    )
    if not compressedSuccessfully or type(compressed) ~= "string" or compressed == "" then
        return nil
    end

    local encodedSuccessfully, encoded = pcall(library.EncodeForPrint, library, compressed)
    if not encodedSuccessfully or type(encoded) ~= "string" or encoded == "" then
        return nil
    end
    return COMPACT_MARKER .. encoded
end

function codec.Decode(exportString)
    if not codec.IsCompact(exportString) then
        return nil, "not_compact"
    end

    local versionOffset = #constants.COMPACT_EXPORT_FORMAT_PREFIX + 1
    local codecVersion = tonumber(exportString:sub(versionOffset, versionOffset))
    if codecVersion ~= constants.COMPACT_EXPORT_CODEC_VERSION then
        return nil, "unsupported"
    end

    local encoded = exportString:sub(#COMPACT_MARKER + 1)
    if encoded == "" or #encoded > constants.MAX_EXPORT_STRING_LENGTH then
        return nil, "invalid"
    end

    local library = getLibDeflate()
    if not library then
        return nil, "unavailable"
    end

    local decodedSuccessfully, compressed = pcall(library.DecodeForPrint, library, encoded)
    if not decodedSuccessfully or type(compressed) ~= "string" or compressed == "" then
        return nil, "invalid"
    end

    local measuredLength, measureError = addon.DeflateGuard.MeasureZlib(
        compressed,
        constants.MAX_EXPORT_PAYLOAD_LENGTH
    )
    if not measuredLength then
        return nil, measureError == "too_large" and "too_large" or "invalid"
    end

    local decompressedSuccessfully, payload, trailingBytes = pcall(
        library.DecompressZlib,
        library,
        compressed
    )
    if not decompressedSuccessfully
        or type(payload) ~= "string"
        or payload == ""
        or trailingBytes ~= 0
    then
        return nil, "invalid"
    end
    if #payload > constants.MAX_EXPORT_PAYLOAD_LENGTH then
        return nil, "too_large"
    end
    if #payload ~= measuredLength then
        return nil, "invalid"
    end
    return payload
end
