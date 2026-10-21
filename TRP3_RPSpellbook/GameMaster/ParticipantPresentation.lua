local _, addon = ...

addon.GameMasterParticipantPresentation = {}

local validModes = {
    engine = true,
    trp_first = true,
    trp_full = true,
    trp_last = true,
    trp_title = true,
}

local function appendPart(parts, value)
    if type(value) == "string" and value:match("%S") then
        parts[#parts + 1] = value
    end
end

function addon.GameMasterParticipantPresentation.FormatName(participant, mode)
    participant = type(participant) == "table" and participant or {}
    mode = validModes[mode] and mode or "trp_full"
    if mode == "engine" then
        return participant.gameName
            or participant.playerID
            or participant.rpName
            or "?"
    end

    local parts = {}
    if mode == "trp_title" then
        appendPart(parts, participant.title)
        appendPart(parts, participant.firstName)
        appendPart(parts, participant.lastName)
    elseif mode == "trp_first" then
        appendPart(parts, participant.firstName)
    elseif mode == "trp_last" then
        appendPart(parts, participant.lastName)
    else
        appendPart(parts, participant.firstName)
        appendPart(parts, participant.lastName)
    end
    if #parts > 0 then
        return table.concat(parts, " ")
    end
    return participant.rpName
        or participant.gameName
        or participant.playerID
        or "?"
end