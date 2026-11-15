local _, addon = ...

addon.GameMasterDelegation = {}

local rights = {
    participants = true,
    rounds = true,
    visibility = true,
}

local commandRights = {
    interruptPreparation = "participants",
    removeBuff = "participants",
    moveParticipant = "participants",
    setParticipantActive = "participants",
    cycleVisibility = "visibility",
    lockRound = "rounds",
    startRound = "rounds",
    unlockRound = "rounds",
}

local function cleanText(value, maximumLength, optional)
    if value == nil and optional then
        return nil
    end
    local text = addon.Runtime.Trim(value)
    if not text
        or text == ""
        or #text > maximumLength
        or text:find("[%c|]")
    then
        return nil
    end
    return text
end

local function readInteger(value, minimum, maximum)
    local number = tonumber(value)
    if not number
        or number ~= number
        or number == math.huge
        or number == -math.huge
        or number < minimum
        or number > maximum
        or number ~= math.floor(number)
    then
        return nil
    end
    return number
end

local function cleanColor(value)
    if type(value) ~= "string" or not value:match("^%x%x%x%x%x%x$") then
        return nil
    end
    return string.upper(value)
end

local function copyProfileIcon(value)
    if type(value) == "number" then
        return readInteger(value, 0, addon.Constants.MAX_IMPORT_SAFE_INTEGER)
    end
    return type(value) == "string" and cleanText(value, 200, true) or nil
end

function addon.GameMasterDelegation.NormalizeRights(raw)
    local normalized = {}
    for right in pairs(rights) do
        normalized[right] = type(raw) == "table" and raw[right] == true
    end
    return normalized
end

function addon.GameMasterDelegation.HasRight(raw, right)
    return rights[right] == true
        and type(raw) == "table"
        and raw[right] == true
end

function addon.GameMasterDelegation.GetRightForCommand(command)
    return commandRights[command]
end

function addon.GameMasterDelegation.GetRights()
    return rights
end

function addon.GameMasterDelegation.BuildControlState(session)
    if type(session) ~= "table" then
        return nil
    end
    local round = addon.GameMasterStore.GetCurrentRound(session)
    local entries = {}
    for _, playerKey in ipairs(session.participantOrder or {}) do
        local participant = session.participants
            and session.participants[playerKey]
        if type(participant) == "table" then
            local submission = round
                and round.submissions
                and round.submissions[playerKey]
            local narrator = addon.GameMasterStore.IsNarrator(session, playerKey)
            if narrator or (round and round.phase == "enemies") then submission = nil end
            local sharedSubmission
            if type(submission) == "table" then
                sharedSubmission = addon.GameMasterVisibility.BuildEntries(
                    {
                        participantOrder = { playerKey },
                        npcActors = session.npcActors,
                        participants = {
                            [playerKey] = participant,
                        },
                    },
                    {
                        submissions = {
                            [playerKey] = submission,
                        },
                    },
                    "full"
                )[1]
            end
            entries[#entries + 1] = {
                completed = addon.GameMasterStore.IsTurnCompleted(round, playerKey),
                active = addon.GameMasterStore.IsParticipantTurnActive(session, round, playerKey),
                buffs = addon.GameMasterEffects
                    and type(addon.GameMasterEffects.CopyActiveBuffs)
                        == "function"
                    and addon.GameMasterEffects.CopyActiveBuffs(
                        session,
                        playerKey
                    )
                    or nil,
                firstName = participant.firstName,
                gameName = participant.gameName,
                lastName = participant.lastName,
                online = participant.online == true,
                playerID = participant.playerID,
                playerKey = playerKey,
                profileColor = participant.profileColor,
                profileIcon = copyProfileIcon(participant.profileIcon),
                rpName = participant.rpName,
                submission = sharedSubmission,
                title = participant.title,
            }
            if narrator then
                local entry = entries[#entries]
                local name = addon.GameMasterStore.GetEncounterOptions(session).narratorName
                entry.rpName, entry.firstName, entry.gameName = name, name, name
                entry.lastName, entry.title, entry.profileIcon, entry.profileColor = nil, nil, nil, nil
            end
        end
        if #entries >= addon.Constants.GAMEMASTER_MAX_PARTICIPANTS then
            break
        end
    end
    return {
        entries = entries,
        round = round and {
            id = round.id,
            number = round.number,
            status = round.status,
            phase = round.phase,
        } or nil,
        sessionId = session.id,
        sessionName = session.name,
        ownerID = session.ownerID,
        gmParticipates = session.gmParticipates ~= false,
        narratorName = addon.GameMasterStore.GetEncounterOptions(session).narratorName,
        enemyPhases = session.enemyPhases == true,
        enemyFirst = session.enemyFirst == true,
        deferEnemyActions = session.deferEnemyActions ~= false,
    }
end

local function validateParticipant(raw)
    if type(raw) ~= "table"
        or type(raw.active) ~= "boolean"
        or type(raw.online) ~= "boolean"
    then
        return nil
    end
    local playerID = cleanText(
        raw.playerID,
        addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
    )
    local playerKey = addon.Runtime.NormalizePlayerID(playerID)
    if not playerKey
        or raw.playerKey ~= playerKey
    then
        return nil
    end
    local gameName = cleanText(
        raw.gameName,
        addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
    )
    local rpName = cleanText(
        raw.rpName,
        addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
    )
    local profileColor = raw.profileColor ~= nil
        and cleanColor(raw.profileColor)
        or nil
    local profileIcon = raw.profileIcon ~= nil
        and copyProfileIcon(raw.profileIcon)
        or nil
    if not gameName
        or not rpName
        or (raw.profileColor ~= nil and not profileColor)
        or (raw.profileIcon ~= nil and profileIcon == nil)
    then
        return nil
    end
    local participant = {
        firstName = cleanText(
            raw.firstName,
            addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH,
            true
        ),
        gameName = gameName,
        lastName = cleanText(
            raw.lastName,
            addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH,
            true
        ),
        online = raw.online,
        playerID = playerID,
        playerKey = playerKey,
        profileColor = profileColor,
        profileIcon = profileIcon,
        rpName = rpName,
        title = cleanText(
            raw.title,
            addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH,
            true
        ),
    }
    local submission
    if raw.submission ~= nil then
        local validated = addon.GameMasterVisibility.ValidateEntries(
            { raw.submission },
            "full"
        )
        submission = validated and validated[1] or nil
        if not submission then
            return nil
        end
        submission.playerID = playerID
        submission.playerKey = playerKey
    end
    local buffs = {}
    if raw.buffs ~= nil then
        if not addon.GameMasterEffects then
            return nil
        end
        buffs = addon.GameMasterEffects.ValidateSharedBuffs(raw.buffs)
        if not buffs then
            return nil
        end
    end
    return participant, submission, raw.active, buffs
end
function addon.GameMasterDelegation.ValidateControlState(raw)
    if type(raw) ~= "table"
        or not addon.Runtime.IsSafeIdentifier(
            raw.sessionId,
            addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
        )
    then
        return nil
    end
    local sessionName = cleanText(
        raw.sessionName,
        addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH
    )
    local entryCount = addon.Runtime.GetBoundedArrayLength(
        raw.entries,
        addon.Constants.GAMEMASTER_MAX_PARTICIPANTS
    )
    if not sessionName or not entryCount then
        return nil
    end

    local session = {
        activeBuffs = {},
        currentRoundID = nil,
        id = raw.sessionId,
        name = sessionName,
        participantOrder = {},
        participants = {},
        rounds = {},
        ownerID = cleanText(raw.ownerID, addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH, true),
        ownerKey = addon.Runtime.NormalizePlayerID(raw.ownerID),
    }
    addon.GameMasterStore.SetEncounterOptions(session, raw)
    local round
    if raw.round ~= nil then
        if type(raw.round) ~= "table" then
            return nil
        end
        local number = readInteger(
            raw.round.number,
            1,
            addon.Constants.MAX_IMPORT_SAFE_INTEGER
        )
        if not number
            or not addon.Runtime.IsSafeIdentifier(
                raw.round.id,
                addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
            )
            or (raw.round.status ~= "open"
                and raw.round.status ~= "locked")
        then
            return nil
        end
        round = {
            completedTurns = {},
            id = raw.round.id,
            inactiveParticipants = {},
            number = number,
            status = raw.round.status,
            phase = raw.round.phase == "enemies" and "enemies" or "players",
            enemyCompletedTurns = {},
            submissions = {},
        }
        session.currentRoundID = round.id
        session.rounds[1] = round
    end

    local seen = {}
    for index = 1, entryCount do
        local participant, submission, active, buffs =
            validateParticipant(raw.entries[index])
        if not participant or seen[participant.playerKey] then
            return nil
        end
        seen[participant.playerKey] = true
        session.participantOrder[index] = participant.playerKey
        session.participants[participant.playerKey] = participant
        if #buffs > 0 then
            session.activeBuffs[participant.playerKey] = buffs
        end
        if round then
            if raw.entries[index].completed == true then
                local turns = round.phase == "enemies" and round.enemyCompletedTurns or round.completedTurns
                turns[participant.playerKey] = { source = "shared" }
            end
            if not active then
                round.inactiveParticipants[participant.playerKey] = true
            end
            if submission then
                round.submissions[participant.playerKey] = submission
            end
        elseif submission then
            return nil
        end
    end
    return session
end
