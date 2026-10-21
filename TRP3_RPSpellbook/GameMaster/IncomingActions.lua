local _, addon = ...

local incoming = {}
addon.GameMasterIncomingActions = incoming

local constants = addon.Constants
local runtime = addon.Runtime

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == value
        and value >= minimum and value <= maximum
        and value == math.floor(value) and value or nil
end

local function text(value, maximum)
    if type(value) ~= "string" or #value > maximum or value:find("[%c|]") then
        return nil
    end
    value = runtime.Trim(value)
    return value ~= "" and value or nil
end

local function identifier(value, maximum)
    return runtime.IsSafeIdentifier(value, maximum)
        and runtime.Trim(value) == value and value or nil
end

local function color(value)
    return type(value) == "string" and value:match("^%x%x%x%x%x%x$")
        and string.upper(value) or nil
end

local function icon(value, maximum)
    if type(value) == "number" then
        return integer(value, 1, constants.MAX_IMPORT_SAFE_INTEGER)
    end
    return text(value, maximum)
end

local function isNPC(id)
    return addon.GameMasterNPCActors and addon.GameMasterNPCActors.IsID(id) == true
end

local function playerKey(id)
    if not identifier(id, constants.GAMEMASTER_MAX_RP_NAME_LENGTH) then return nil end
    local key = runtime.NormalizePlayerID(id)
    return key and not key:find("^npc_") and key or nil
end

local function scope(roundID, casterID)
    return "incoming:" .. #roundID .. ":" .. roundID .. ":" .. #casterID .. ":" .. casterID .. ":"
end

local function cleanSpell(raw)
    if type(raw) ~= "table" then return nil end
    local limits = addon.Validators.Limits
    local spell = {
        id = identifier(raw.id, constants.MAX_LINK_SPELL_ID_LENGTH),
        name = text(raw.name, limits.MAX_SPELL_NAME_LENGTH),
        icon = raw.icon ~= nil and icon(raw.icon, limits.MAX_ICON_LENGTH) or nil,
        nameColor = raw.nameColor ~= nil and color(raw.nameColor) or nil,
        revision = raw.revision ~= nil and integer(raw.revision, 1, constants.MAX_LINK_REVISION) or nil,
    }
    if not spell.id or not spell.name
        or (raw.icon ~= nil and not spell.icon)
        or (raw.nameColor ~= nil and not spell.nameColor)
        or (raw.revision ~= nil and not spell.revision)
    then return nil end
    return spell
end

local function cleanRecord(raw)
    if type(raw) ~= "table" then return nil end
    local roundID = identifier(raw.roundID, constants.GAMEMASTER_MAX_SESSION_ID_LENGTH)
    local roundNumber = integer(raw.roundNumber, 1, constants.MAX_IMPORT_SAFE_INTEGER)
    local casterID = isNPC(raw.casterID) and raw.casterID or playerKey(raw.casterID)
    local id = identifier(raw.id, constants.GAMEMASTER_MAX_INCOMING_ID_LENGTH)
    local spell = cleanSpell(raw.spell)
    local name = text(raw.casterName, constants.GAMEMASTER_MAX_RP_NAME_LENGTH)
    local casterIcon = raw.casterIcon ~= nil and icon(raw.casterIcon, 200) or nil
    local casterColor = raw.casterColor ~= nil and color(raw.casterColor) or nil
    if not roundID or not roundNumber or not casterID or casterID ~= raw.casterID
        or not id or not spell or not name or type(raw.previous) ~= "boolean"
        or (raw.action ~= "cast" and raw.action ~= "channel")
        or raw.phase ~= (isNPC(casterID) and "enemies" or "players")
        or (raw.casterIcon ~= nil and not casterIcon)
        or (raw.casterColor ~= nil and not casterColor)
    then return nil end
    local prefix = scope(roundID, casterID)
    if id:sub(1, #prefix) ~= prefix then return nil end
    local suffix = id:sub(#prefix + 1)
    if suffix:sub(1, 2) == "s:" then
        if not identifier(suffix:sub(3), constants.GAMEMASTER_MAX_SESSION_ID_LENGTH) then return nil end
    elseif not suffix:match("^i:[1-5]$") then
        return nil
    end
    return {
        id = id, roundID = roundID, roundNumber = roundNumber, previous = raw.previous,
        phase = raw.phase, casterID = casterID, casterName = name,
        casterIcon = casterIcon, casterColor = casterColor, action = raw.action, spell = spell,
    }
end

function incoming.Validate(raw, currentRoundID, currentRoundNumber)
    local count = runtime.GetBoundedArrayLength(raw, constants.GAMEMASTER_MAX_INCOMING_ACTIONS)
    local number = integer(currentRoundNumber, 0, constants.MAX_IMPORT_SAFE_INTEGER)
    if not count or not number or not (identifier(currentRoundID,
        constants.GAMEMASTER_MAX_SESSION_ID_LENGTH) or currentRoundID == "" and number == 0)
    then return nil end
    local result, ids, rounds, casters = {}, {}, {}, {}
    local previousStarted, previousID = false, nil
    for index = 1, count do
        local record = cleanRecord(raw[index])
        if not record or ids[record.id]
            or record.roundNumber ~= number - (record.previous and 1 or 0)
            or (not record.previous and (previousStarted or record.roundID ~= currentRoundID))
            or (record.previous and (record.roundID == currentRoundID
                or previousID and record.roundID ~= previousID))
        then return nil end
        if record.previous then previousStarted, previousID = true, record.roundID end
        local round = rounds[record.roundID]
        if not round then
            round = { players = 0, enemies = 0, counts = {} }
            rounds[record.roundID] = round
        end
        local caster = casters[record.casterID]
        if caster and caster ~= record.phase then return nil end
        casters[record.casterID] = record.phase
        local actionCount = (round.counts[record.casterID] or 0) + 1
        if actionCount > constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER then return nil end
        if actionCount == 1 then round[record.phase] = round[record.phase] + 1 end
        if round.players > constants.GAMEMASTER_MAX_PARTICIPANTS
            or round.enemies > 20 then return nil end
        round.counts[record.casterID] = actionCount
        ids[record.id], result[index] = true, record
    end
    return result
end

 
function incoming.Copy(raw)
    if raw == nil then return {} end
    local count = runtime.GetBoundedArrayLength(raw, constants.GAMEMASTER_MAX_INCOMING_ACTIONS)
    if not count then return nil end
    local result = {}
    for index = 1, count do
        result[index] = cleanRecord(raw[index])
        if not result[index] then return nil end
    end
    return result
end

local function boundedKeys(map, maximum)
    if type(map) ~= "table" then return nil end
    local keys = {}
    for key in pairs(map) do
        if type(key) ~= "string" or #keys >= maximum then return nil end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function rosterKeys(session)
    if type(session.participants) ~= "table" then return nil end
    if session.participantOrder == nil then
        return boundedKeys(session.participants, constants.GAMEMASTER_MAX_PARTICIPANTS)
    end
    local count = runtime.GetBoundedArrayLength(session.participantOrder, constants.GAMEMASTER_MAX_PARTICIPANTS)
    if not count then return nil end
    local keys, seen = {}, {}
    for index = 1, count do
        local key = session.participantOrder[index]
        if type(key) ~= "string" or seen[key] then return nil end
        keys[#keys + 1], seen[key] = key, true
    end
    return keys
end

local function realPlayer(session, key)
    local participant = session.participants[key]
    return type(participant) == "table" and playerKey(key) == key
        and playerKey(participant.playerID) == key
        and participant.kind ~= "npc" and participant.actorKind ~= "npc"
        and participant.kind ~= "narrator" and participant.actorKind ~= "narrator"
        and not (session.gmParticipates == false and key == session.ownerKey)
        and participant or nil
end

local function findPlayer(session, value, lookups)
    value = text(value, constants.GAMEMASTER_MAX_TARGET_LENGTH)
    if not value or not playerKey(value) then return nil end
    local normalized = value:lower()
    local cached = lookups.players[normalized]
    if cached ~= nil then return cached or nil end
    local key = addon.GameMasterEffects.FindParticipantKey(lookups.roster, value)
    key = key and realPlayer(session, key) and key or nil
    lookups.players[normalized] = key or false
    return key
end

local function resolveText(session, keys, value, lookups)
    value = text(value, constants.GAMEMASTER_MAX_TARGET_LENGTH)
    if not value then return nil end
    local lowered = value:lower()
    local cached = lookups.text[lowered]
    if cached ~= nil then return cached or nil end
     
    lookups.text[lowered] = false
    local match = findPlayer(session, value, lookups)
    for _, key in ipairs(keys) do
        local participant = realPlayer(session, key)
        if participant then
             
            if addon.GameMasterEffects.PlayerIDsMatch(value, participant.playerID) then
                if match and match ~= key then return nil end
                match = key
            end
            local first = text(participant.firstName, constants.GAMEMASTER_MAX_RP_NAME_LENGTH)
            local last = text(participant.lastName, constants.GAMEMASTER_MAX_RP_NAME_LENGTH)
            local fullName = first and last and first .. " " .. last or nil
            for _, field in ipairs({ "rpName", "gameName", "firstName" }) do
                local name = text(participant[field], constants.GAMEMASTER_MAX_RP_NAME_LENGTH)
                if name and name:lower() == lowered then
                    if match and match ~= key then return nil end
                    match = key
                end
            end
            if fullName and fullName:lower() == lowered then
                if match and match ~= key then return nil end
                match = key
            end
        end
    end
    lookups.text[lowered] = match or false
    return match
end

local function targetRecipients(session, keys, action, lookups)
    local targets = action.targets
    if targets == nil then targets = action.target and { action.target } or {} end
    local count = runtime.GetBoundedArrayLength(targets, constants.GAMEMASTER_MAX_TARGETS)
    if not count then return false end
    if count == 0 and action.target ~= nil then targets, count = { action.target }, 1 end
    local matched = {}
    for index = 1, count do
        local target = targets[index]
        if type(target) ~= "table" then return false end
        local key
        if target.kind == "player" then
            key = findPlayer(session, target.value, lookups)
        elseif target.kind == "text" or target.kind == "target" then
            key = resolveText(session, keys, target.value or target.label, lookups)
        end
        if key then matched[key] = true end
    end
    return matched
end

local function build(session, currentRound, recipientID, allRecipients)
    if type(session) ~= "table" or type(currentRound) ~= "table"
        or not addon.GameMasterEffects or not addon.GameMasterEffects.FindParticipantKey
    then return {} end
    local number = integer(currentRound.number, 1, constants.MAX_IMPORT_SAFE_INTEGER)
    local roundID = identifier(currentRound.id, constants.GAMEMASTER_MAX_SESSION_ID_LENGTH)
    local keys = rosterKeys(session)
    if not number or not roundID or not keys
        or (session.currentRoundID ~= nil and session.currentRoundID ~= roundID)
    then return {} end
     
    local lookups = { players = {}, text = {}, roster = { participants = {} } }
    for _, key in ipairs(keys) do lookups.roster.participants[key] = realPlayer(session, key) end
    local recipient = not allRecipients and findPlayer(session, recipientID, lookups)
    if not allRecipients and not recipient then return {} end
    local previous, ambiguous
    local rounds = session.rounds or {}
    local roundCount = runtime.GetBoundedArrayLength(rounds, constants.GAMEMASTER_MAX_HISTORY)
    if not roundCount then return {} end
    for index = 1, roundCount do
        local candidate = rounds[index]
        if type(candidate) == "table" and candidate.number == number - 1 then
            if previous then ambiguous = true end
            previous = candidate
        end
    end
    if ambiguous then previous = nil end
    local npcKeys = boundedKeys(session.npcActors or {}, 20) or {}
    local result, seen = {}, {}
    local function addActor(round, key, actor, npc, submission)
        if type(submission) ~= "table" then return end
        if (submission.playerKey ~= nil and submission.playerKey ~= key)
            or (submission.playerID ~= nil
                and (npc and submission.playerID or playerKey(submission.playerID)) ~= key)
        then return end
        local actions = submission.actions
        if actions == nil then actions = { submission } end
        local count = runtime.GetBoundedArrayLength(actions, constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER)
        if not count then return end
        for index = 1, count do
            local action = actions[index]
            if type(action) == "table" and action.actions == nil
                and integer(action.submittedAt, 0, constants.MAX_IMPORT_SAFE_INTEGER)
                and (action.action == "cast" or action.action == "channel")
            then
                local targets = targetRecipients(session, keys, action, lookups)
                if targets and (allRecipients or targets[recipient]) then
                    local token = action.submissionId ~= nil
                        and identifier(action.submissionId, constants.GAMEMASTER_MAX_SESSION_ID_LENGTH) or nil
                    if action.submissionId == nil or token then
                        local record = cleanRecord({
                            id = scope(round.id, key) .. (token and "s:" .. token or "i:" .. index),
                            roundID = round.id, roundNumber = round.number, previous = round ~= currentRound,
                            phase = npc and "enemies" or "players", casterID = key,
                            casterName = npc and actor.name or submission.rpName or actor.rpName or actor.gameName or key,
                            casterIcon = icon(npc and actor.icon or actor.profileIcon, 200),
                            casterColor = color(npc and actor.nameColor or actor.profileColor),
                            action = action.action, spell = action.spell,
                        })
                        if record then
                            if allRecipients then
                                for target in pairs(targets) do
                                    seen[target] = seen[target] or {}
                                    if not seen[target][record.id] then
                                        seen[target][record.id] = true
                                        result[target] = result[target] or {}
                                        result[target][#result[target] + 1] = record
                                    end
                                end
                            elseif not seen[record.id] then
                                seen[record.id] = true
                                result[#result + 1] = record
                            end
                        end
                    end
                end
            end
        end
    end
    local function addRound(round)
        if not round or not identifier(round.id, constants.GAMEMASTER_MAX_SESSION_ID_LENGTH)
            or (round ~= currentRound and round.id == roundID) then return end
        local sourceKeys = boundedKeys(round.submissions or {}, constants.GAMEMASTER_MAX_PARTICIPANTS) or {}
        for _, key in ipairs(sourceKeys) do
            local actor = realPlayer(session, key)
            if actor then
                addActor(round, key, actor, false, type(round.submissions) == "table" and round.submissions[key])
            end
        end
        for _, key in ipairs(npcKeys) do
            local actor = isNPC(key) and addon.GameMasterNPCActors.Get(session, key)
            local visibility = addon.GameMasterVisibility
            if type(actor) == "table" and actor.id == key and actor.kind == "npc"
                and actor.released == true and visibility
                and type(visibility.CanRevealNPCActions) == "function"
                and (actor.side == "players" or visibility.CanRevealNPCActions(session, round) == true)
            then
                addActor(round, key, actor, true, type(round.npcSubmissions) == "table" and round.npcSubmissions[key])
            end
        end
    end
    addRound(currentRound)
    addRound(previous)
    return result
end

function incoming.Build(session, currentRound, recipientID)
    return build(session, currentRound, recipientID, false)
end

function incoming.BuildIndex(session, currentRound)
    return build(session, currentRound, nil, true)
end
