local _, addon = ...

addon.GameMasterStore = {}

local function getRoot()
    local database = addon.Database.GetDB()
    if type(database) ~= "table" then
        return nil
    end
    if type(database.gameMaster) ~= "table" then
        database.gameMaster = {}
    end
    local root = database.gameMaster
    if type(root.sessions) ~= "table" then
        root.sessions = {}
    end
    root.nextSessionSerial = math.max(
        1,
        math.floor(tonumber(root.nextSessionSerial) or 1)
    )
    if root.orderLocked == nil then
        root.orderLocked = true
    end
    if type(root.window) ~= "table" then
        root.window = {}
    end
    if type(root.compactWindow) ~= "table" then
        root.compactWindow = {}
    end
    return root
end

local function cleanName(value)
    local name = addon.Runtime.Trim(value)
    if not name
        or name == ""
        or #name > addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH
        or name:find("[%c|]")
    then
        return nil
    end
    return name
end

function addon.GameMasterStore.NormalizeEncounterOptions(raw, fallback)
    raw = type(raw) == "table" and raw or {}
    fallback = type(fallback) == "table" and fallback or {}
    local participates = raw.gmParticipates
    if type(participates) ~= "boolean" then participates = fallback.gmParticipates ~= false end
    local enemies = raw.enemyPhases
    if type(enemies) ~= "boolean" then enemies = fallback.enemyPhases == true end
    return {
        gmParticipates = participates,
        narratorName = cleanName(raw.narratorName) or cleanName(fallback.narratorName)
            or addon.L("GAMEMASTER_NARRATOR_DEFAULT"),
        enemyPhases = enemies,
        enemyFirst = type(raw.enemyFirst) == "boolean" and raw.enemyFirst
            or type(raw.enemyFirst) ~= "boolean" and fallback.enemyFirst == true,
        deferEnemyActions = type(raw.deferEnemyActions) == "boolean" and raw.deferEnemyActions
            or type(raw.deferEnemyActions) ~= "boolean" and fallback.deferEnemyActions ~= false,
    }
end

function addon.GameMasterStore.GetEncounterOptions(session)
    return addon.GameMasterStore.NormalizeEncounterOptions(session)
end

function addon.GameMasterStore.SetEncounterOptions(session, options)
    if type(session) ~= "table" then return false end
    for key, value in pairs(addon.GameMasterStore.NormalizeEncounterOptions(options, session)) do
        session[key] = value
    end
    return true
end

function addon.GameMasterStore.GetPhase(session)
    local round = addon.GameMasterStore.GetCurrentRound(session)
    return round and round.phase == "enemies" and "enemies" or "players"
end

function addon.GameMasterStore.IsNarrator(session, playerKey)
    return type(session) == "table" and playerKey == session.ownerKey
        and (session.gmParticipates == false
            or addon.GameMasterStore.GetPhase(session) == "enemies")
end

local function copyTags(tags)
    if type(tags) ~= "table" then
        return nil
    end
    local result = {}
    for key, value in pairs(tags) do
        if type(key) == "string" and type(value) == "string" then
            result[key] = value
        end
    end
    return next(result) and result or nil
end

local function copyEffects(effects)
    if type(effects) ~= "table" then
        return nil
    end
    return {
        buff = effects.buff == true,
        debuff = effects.debuff == true,
        debuffType = effects.debuffType,
        duration = effects.duration,
        durationRounds = effects.durationRounds,
        durationSeconds = effects.durationSeconds,
        healing = effects.healing == true,
        whisperTemplate = effects.whisperTemplate,
    }
end
local function copySpell(spell)
    return {
        castTime = spell.castTime,
        cooldown = spell.cooldown,
        description = spell.description,
        effects = copyEffects(spell.effects),
        icon = spell.icon,
        id = spell.id,
        name = spell.name,
        nameColor = spell.nameColor,
        ownerKey = spell.ownerKey,
        range = spell.range,
        resource = spell.resource,
        revision = spell.revision,
        tags = copyTags(spell.tags),
    }
end

local function copyTarget(target)
    if type(target) ~= "table" then
        return nil
    end
    return {
        color = target.color,
        health = target.health,
        icon = target.icon,
        kind = target.kind,
        label = target.label,
        name = target.name,
        value = target.value,
    }
end

local function copyTargets(targets)
    local result = {}
    for _, target in ipairs(type(targets) == "table" and targets or {}) do
        local copied = copyTarget(target)
        if copied then result[#result + 1] = copied end
        if #result >= addon.Constants.GAMEMASTER_MAX_TARGETS then break end
    end
    return result
end

local function copyEmote(emote)
    if type(emote) ~= "table" then return nil end
    return {
        channel = emote.channel,
        text = emote.text,
        timestamp = emote.timestamp,
    }
end

local runtimeWindowIDs = {
    "compactSpellbook",
    "currentAction",
    "gameMaster",
    "roundOverview",
}

local function copyOpenWindows(value)
    if type(value) ~= "table" then return nil end
    local result = {}
    for _, moduleID in ipairs(runtimeWindowIDs) do
        result[moduleID] = value[moduleID] == true
    end
    return result
end

local function copyPreparation(preparation)
    if type(preparation) ~= "table" then
        return nil
    end
    return {
        automated = preparation.automated == true,
        progress = preparation.progress,
        required = preparation.required,
    }
end

local function copyAction(action)
    if type(action) ~= "table"
        or not addon.Constants.GAMEMASTER_ACTIONS[action.action]
        or type(action.spell) ~= "table"
    then
        return nil
    end
    local targets = copyTargets(action.targets)
    return {
        action = action.action,
        aoe = action.aoe == true,
        emote = copyEmote(action.emote),
        preparation = copyPreparation(action.preparation),
        spell = copySpell(action.spell),
        submissionId = action.submissionId,
        submittedAt = action.submittedAt,
        target = targets[1] or copyTarget(action.target),
        targets = targets,
    }
end

function addon.GameMasterStore.GetSession(sessionID)
    local root = getRoot()
    return root and root.sessions[sessionID] or nil
end


function addon.GameMasterStore.GetSceneAccess(session)
    if type(session) ~= "table" then
        return addon.GameMasterSceneAccess.Normalize(nil, "hidden")
    end
    session.access = addon.GameMasterSceneAccess.Normalize(
        session.access,
        "hidden"
    )
    return addon.GameMasterSceneAccess.Copy(
        session.access,
        "hidden"
    )
end

function addon.GameMasterStore.UpdateSessionSettings(
    sessionID,
    ownerID,
    name,
    access,
    options
)
    local root = getRoot()
    local session = root and root.sessions[sessionID] or nil
    local ownerKey = addon.Runtime.NormalizePlayerID(ownerID)
    local cleanedName = cleanName(name)
    if not session or session.ownerKey ~= ownerKey then
        return false, addon.L("GAMEMASTER_SESSION_NOT_FOUND")
    end
    if not cleanedName then
        return false, addon.L("GAMEMASTER_INVALID_SESSION_NAME")
    end

    local normalized = addon.GameMasterSceneAccess.Normalize(
        access,
        session.access and session.access.defaultVisibility or "hidden"
    )
    for index = #normalized.assistants, 1, -1 do
        if normalized.assistants[index].playerKey == ownerKey then
            table.remove(normalized.assistants, index)
        end
    end

    local normalizedOptions = addon.GameMasterStore.NormalizeEncounterOptions(options, session)
    local previousOptions = addon.GameMasterStore.GetEncounterOptions(session)
    if session.currentRoundID then
        for key, value in pairs(normalizedOptions) do
            if value ~= previousOptions[key] then
                return false, addon.L("GAMEMASTER_ENCOUNTER_OPTIONS_LOCKED")
            end
        end
    end
    addon.GameMasterStore.SetEncounterOptions(session, normalizedOptions)
    session.name = cleanedName
    session.access = normalized
    session.updatedAt = addon.Runtime.GetTimestamp()
    return true, session
end
function addon.GameMasterStore.ListSessions(ownerID)
    local ownerKey = addon.Runtime.NormalizePlayerID(ownerID)
    local root = getRoot()
    local sessions = {}
    if not root or not ownerKey then
        return sessions
    end
    for _, session in pairs(root.sessions) do
        if type(session) == "table" and session.ownerKey == ownerKey then
            sessions[#sessions + 1] = session
        end
    end
    table.sort(sessions, function(left, right)
        if left.updatedAt ~= right.updatedAt then
            return left.updatedAt > right.updatedAt
        end
        return left.id < right.id
    end)
    return sessions
end

function addon.GameMasterStore.CreateSession(name, ownerID, access, options)
    local root = getRoot()
    local ownerKey = addon.Runtime.NormalizePlayerID(ownerID)
    local cleanedName = cleanName(name)
    if not root or not ownerKey or not cleanedName then
        return nil, addon.L("GAMEMASTER_INVALID_SESSION_NAME")
    end

    local serial = root.nextSessionSerial
    root.nextSessionSerial = serial + 1
    local timestamp = addon.Runtime.GetTimestamp()
    local sessionID = string.format("gm_%d_%d", timestamp, serial)
    while root.sessions[sessionID] do
        serial = root.nextSessionSerial
        root.nextSessionSerial = serial + 1
        sessionID = string.format("gm_%d_%d", timestamp, serial)
    end

    local session = {
        activeBuffs = {},
        createdAt = timestamp,
        currentRoundID = nil,
        id = sessionID,
        name = cleanedName,
        nextRoundNumber = 1,
        ownerID = ownerID,
        ownerKey = ownerKey,
        participantOrder = {},
        participants = {},
        preparations = {},
        rounds = {},
        updatedAt = timestamp,
        access = addon.GameMasterSceneAccess.Normalize(
            access,
            "hidden"
        ),
    }
    addon.GameMasterStore.SetEncounterOptions(session,
        addon.GameMasterStore.NormalizeEncounterOptions(options, { enemyPhases = true, enemyFirst = true }))
    root.sessions[sessionID] = session
    root.activeSessionID = sessionID
    return session
end

function addon.GameMasterStore.DeleteSession(sessionID, ownerID)
    local root = getRoot()
    local session = root and root.sessions[sessionID] or nil
    if not session
        or session.ownerKey ~= addon.Runtime.NormalizePlayerID(ownerID)
    then
        return false, addon.L("GAMEMASTER_SESSION_NOT_FOUND")
    end
    root.sessions[sessionID] = nil
    if root.activeSessionID == sessionID then
        root.activeSessionID = nil
    end
    return true
end

function addon.GameMasterStore.SetActiveSession(sessionID)
    local root = getRoot()
    if not root or (sessionID ~= nil and not root.sessions[sessionID]) then
        return false
    end
    root.activeSessionID = sessionID
    return true
end

function addon.GameMasterStore.GetActiveSessionID()
    local root = getRoot()
    return root and root.activeSessionID or nil
end

 
local RECOVERY_CHARACTER_LIMIT = 50
local RECOVERY_TOMBSTONE_LIMIT = 128
local RECOVERY_REVISION_STRIDE = 1048576.0

local function recoveryInteger(value)
    local number = tonumber(value)
    return number and number == number and number >= 0
        and number <= addon.Constants.MAX_IMPORT_SAFE_INTEGER
        and number == math.floor(number) and number or nil
end

local function recoveryPlayer(value)
    return type(value) == "string"
        and #value <= addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
        and addon.Runtime.NormalizePlayerID(value) or nil
end

local function recoveryID(value)
    return addon.Runtime.IsSafeIdentifier(value,
        addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH)
end

local function recoveryMembers(members)
    local result, seen = {}, {}
    for index = 1, addon.Constants.GAMEMASTER_MAX_PARTICIPANTS do
        local member = type(members) == "table" and members[index]
        if member == nil then break end
        local key = recoveryPlayer(type(member) == "table" and member.playerID or member)
        if key and not seen[key] then
            seen[key], result[#result + 1] = true, key
        end
    end
    table.sort(result)
    return result
end

function addon.GameMasterStore.GetRevisionEpoch(revision)
    local valid = recoveryInteger(revision)
    return valid and math.floor(valid / RECOVERY_REVISION_STRIDE) or nil
end

function addon.GameMasterStore.AllocateOriginSequence(minimum)
    local root = getRoot()
    if not root then return nil end
    local sequence = root.originSubmissionSequence == nil and 0
        or recoveryInteger(root.originSubmissionSequence)
    if not sequence then return nil end
    sequence = math.max(sequence, recoveryInteger(minimum) or 0)
    if sequence >= addon.Constants.MAX_IMPORT_SAFE_INTEGER then return nil end
     
     
    root.originSubmissionSequence = sequence + 1
    return root.originSubmissionSequence
end

local originPayloadFields = {
    action = true, activationId = true, aoe = true, emote = true, mode = true,
    originSequence = true, preparation = true, roundId = true, sessionId = true,
    spell = true, stateRevision = true, submissionId = true, target = true, targets = true,
}

local function normalizeOriginPayload(payload, playerKey, state, currentRevision)
    local communication = addon.Communication
    if type(payload) ~= "table" or type(communication) ~= "table"
        or type(communication.CanSendPayload) ~= "function"
        or not communication.CanSendPayload(payload) then return nil end
    for key in pairs(payload) do
        if type(key) ~= "string" or not originPayloadFields[key] then return nil end
    end
    if payload.sessionId ~= state.sessionID or payload.activationId ~= state.activationID
        or payload.roundId ~= state.roundID or not recoveryID(payload.sessionId)
        or not recoveryID(payload.activationId) or not recoveryID(payload.roundId)
        or not recoveryID(payload.submissionId)
        or not addon.Constants.GAMEMASTER_ACTIONS[payload.action]
        or (payload.mode ~= "replace" and payload.mode ~= "append")
        or type(payload.aoe) ~= "boolean" then return nil end
    local revision = recoveryInteger(payload.stateRevision)
    local sequence = recoveryInteger(payload.originSequence)
    if not revision or revision > currentRevision or not sequence or sequence < 1
        or payload.submissionId ~= "origin_" .. string.format("%.0f", sequence)
        or addon.GameMasterStore.GetRevisionEpoch(revision)
            ~= addon.GameMasterStore.GetRevisionEpoch(currentRevision) then return nil end
    local maximum = payload.action == "prepare" and 0
        or (payload.aoe and addon.Constants.GAMEMASTER_MAX_TARGETS or 1)
    local targetCount = addon.Runtime.GetBoundedArrayLength(payload.targets, maximum)
    if not targetCount then return nil end
    local preparation
    if payload.action == "prepare" then
        local required = type(payload.preparation) == "table"
            and recoveryInteger(payload.preparation.required)
        if not required or required < 1 or required > 100 then return nil end
        preparation = { required = required, progress = 0 }
    elseif payload.preparation ~= nil then return nil end
    local visibility = addon.GameMasterVisibility
    local validated = visibility and visibility.ValidateEntries({ {
        rpName = playerKey, playerID = playerKey, action = payload.action,
        spell = payload.spell, targets = payload.targets, preparation = preparation,
    } }, "full")
    if not validated then return nil end
    local entry = validated[1]
    for index = 1, targetCount do
        local target, source = entry.targets[index], payload.targets[index]
        if target.kind ~= "marker" then
            local value = source.value
            if type(value) ~= "string" or #value > addon.Constants.GAMEMASTER_MAX_TARGET_LENGTH
                or value:find("[%c|]") or addon.Runtime.Trim(value) == ""
                or (target.kind == "player" and not recoveryPlayer(value)) then return nil end
            target.value = addon.Runtime.Trim(value)
        end
    end
    if payload.target ~= nil then
        local first = payload.targets[1]
        if not first or type(payload.target) ~= "table"
            or payload.target.kind ~= first.kind or payload.target.value ~= first.value then return nil end
    end
    local emote
    if payload.emote ~= nil then
        local source = payload.emote
        if type(source) ~= "table" or type(source.channel) ~= "string"
            or #source.channel > 40 or source.channel:find("[%c|]")
            or addon.Runtime.Trim(source.channel) == "" or type(source.text) ~= "string"
            or #source.text > addon.Constants.GAMEMASTER_MAX_EMOTE_LENGTH
            or source.text:find("[%c|]") or addon.Runtime.Trim(source.text) == ""
            or not recoveryInteger(source.timestamp) then return nil end
        emote = { channel = addon.Runtime.Trim(source.channel),
            text = addon.Runtime.Trim(source.text), timestamp = tonumber(source.timestamp) }
    end
    local cleaned = {
        sessionId = payload.sessionId, activationId = payload.activationId,
        roundId = payload.roundId, stateRevision = revision,
        originSequence = sequence, submissionId = payload.submissionId,
        action = payload.action, mode = payload.mode, aoe = payload.aoe,
        spell = entry.spell, targets = entry.targets, target = entry.targets[1], emote = emote,
        preparation = preparation and { required = preparation.required,
            automated = payload.preparation.automated == true } or nil,
    }
    return communication.CanSendPayload(cleaned) and cleaned or nil
end

 
 
function addon.GameMasterStore.NormalizeOriginOutbox(raw, playerKey, state)
    if type(raw) ~= "table" or type(state) ~= "table"
        or not recoveryPlayer(playerKey) or recoveryPlayer(playerKey) ~= playerKey
        or raw.originKey ~= playerKey or raw.gameMasterKey ~= state.gameMasterKey
        or not recoveryPlayer(state.gameMasterID)
        or recoveryPlayer(state.gameMasterID) ~= state.gameMasterKey
        or state.gameMasterKey == playerKey then return nil end
    local allowed = { version = true, originKey = true, gameMasterKey = true,
        payload = true, items = true }
    for key in pairs(raw) do if not allowed[key] then return nil end end
    local source
    if raw.version == 1 and raw.items == nil and type(raw.payload) == "table" then
        source = { raw.payload }
    elseif raw.version == 2 and raw.payload == nil then
        local count = addon.Runtime.GetBoundedArrayLength(raw.items,
            addon.Constants.GAMEMASTER_ORIGIN_OUTBOX_LIMIT)
        if not count or count < 1 then return nil end
        source = raw.items
    else
        return nil
    end
    local communication = addon.Communication
    if type(communication) ~= "table" or type(communication.CanSendPayload) ~= "function"
        or not communication.CanSendPayload(raw) then return nil end
    local currentRevision = math.max(recoveryInteger(state.lastStateRevision) or 0,
        recoveryInteger(state.lastVisibilityRevision) or 0)
    local actions = addon.GameMasterActionCollection
    local projected = actions and actions.Count(state.lastSubmission) or 0
    local preparing = actions and actions.ContainsPreparation(state.lastSubmission) or false
    local items, previousSequence = {}, 0
    for index = 1, #source do
        local payload = normalizeOriginPayload(source[index], playerKey, state, currentRevision)
        if not payload or payload.originSequence <= previousSequence
            or (index > 1 and payload.mode ~= "append") then return nil end
        if payload.mode == "replace" then
            projected, preparing = 1, payload.action == "prepare"
        else
            if payload.action == "prepare" or preparing then return nil end
            projected = projected > 0 and projected + 1 or 1
        end
        if projected > addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER then return nil end
        items[index], previousSequence = payload, payload.originSequence
    end
    local normalized = { version = 2, originKey = playerKey,
        gameMasterKey = state.gameMasterKey, items = items }
    return communication.CanSendPayload(normalized) and normalized or nil
end

 
 
function addon.GameMasterStore.BeginRecovery(localState, observedRevision)
    if type(localState) ~= "table" then return false end
    local revision = recoveryInteger(localState.visibilityRevision)
    local observed = observedRevision == nil and 0 or recoveryInteger(observedRevision)
    if not revision or not observed then return false end
    local nextRevision = (math.floor(math.max(revision, observed)
        / RECOVERY_REVISION_STRIDE) + 1) * RECOVERY_REVISION_STRIDE
    if nextRevision >= addon.Constants.MAX_IMPORT_SAFE_INTEGER then return false end
    localState.visibilityRevision = nextRevision
    localState.visibilitySnapshots = nil
    localState.recovering = true
    local session = addon.GameMasterStore.GetSession(localState.sessionID)
    if session then
        session.recoveryRevision = nextRevision
        session.recoveryEpoch = addon.GameMasterStore.GetRevisionEpoch(nextRevision)
    end
    return true
end

function addon.GameMasterStore.IsActivationStopped(playerKey, ownerKey, sessionID, activationID)
    local root = getRoot()
    playerKey, ownerKey = recoveryPlayer(playerKey), recoveryPlayer(ownerKey)
    if not root or not playerKey or not ownerKey then return false end
    for index = 1, RECOVERY_TOMBSTONE_LIMIT do
        local entry = type(root.stoppedActivations) == "table" and root.stoppedActivations[index]
        if entry == nil then break end
        if type(entry) == "table" and entry.playerKey == playerKey and entry.ownerKey == ownerKey
            and entry.sessionID == sessionID and entry.activationID == activationID then return true end
    end
    return false
end

function addon.GameMasterStore.RecordStoppedActivation(playerKey, ownerKey, sessionID, activationID)
    local root = getRoot()
    playerKey, ownerKey = recoveryPlayer(playerKey), recoveryPlayer(ownerKey)
    if not root or not playerKey or not ownerKey
        or not recoveryID(sessionID) or not recoveryID(activationID) then return false end
    if type(root.stoppedActivations) ~= "table" then root.stoppedActivations = {} end
    local kept = {{ playerKey = playerKey, ownerKey = ownerKey,
        sessionID = sessionID, activationID = activationID,
        stoppedAt = addon.Runtime.GetTimestamp() }}
    for index = 1, RECOVERY_TOMBSTONE_LIMIT do
        local entry = root.stoppedActivations[index]
        if entry == nil or #kept >= RECOVERY_TOMBSTONE_LIMIT then break end
        if type(entry) == "table" and not (entry.playerKey == playerKey
            and entry.ownerKey == ownerKey and entry.sessionID == sessionID
            and entry.activationID == activationID) then kept[#kept + 1] = entry end
    end
    root.stoppedActivations = kept
    local saved = type(root.runtimeStates) == "table" and root.runtimeStates[playerKey]
    local state = type(saved) == "table" and (saved.localState or saved.remoteState)
    if type(state) == "table" and state.sessionID == sessionID and state.activationID == activationID
        and (saved.localState and playerKey or state.gameMasterKey) == ownerKey then
        root.runtimeStates[playerKey] = nil
    end
    local session = root.sessions[sessionID]
    if session and session.ownerKey == ownerKey and session.runningActivationID == activationID then
        session.runningActivationID = nil
    end
    return true
end

function addon.GameMasterStore.SaveRuntimeState(playerKey, localState, remoteState)
    local root = getRoot()
    playerKey = recoveryPlayer(playerKey)
    if not root or not playerKey then return false end
    if type(root.runtimeStates) ~= "table" then root.runtimeStates = {} end
    local previous = root.runtimeStates[playerKey]
    if not localState and not remoteState then
        if type(previous) ~= "table" or previous.status ~= "suspended" then
            root.runtimeStates[playerKey] = nil
        end
        return true
    end
    local source = localState or remoteState
    if type(source) ~= "table" or not recoveryID(source.sessionID)
        or not recoveryID(source.activationID) then return false end
    local ownerKey = localState and playerKey or recoveryPlayer(source.gameMasterID)
    if not ownerKey or addon.GameMasterStore.IsActivationStopped(
        playerKey, ownerKey, source.sessionID, source.activationID) then return false end
    local state = { version = 2, status = "live", savedAt = addon.Runtime.GetTimestamp() }
    local roster = addon.GameMasterRoster
    state.groupMembers = roster and roster.IsInGroup()
        and recoveryMembers(roster.GetMembers()) or {}
    local oldSource = type(previous) == "table" and (previous.localState or previous.remoteState)
    if type(oldSource) == "table" and (oldSource.sessionID ~= source.sessionID
        or oldSource.activationID ~= source.activationID) then
        addon.GameMasterStore.RecordStoppedActivation(playerKey,
            previous.localState and playerKey or oldSource.gameMasterKey,
            oldSource.sessionID, oldSource.activationID)
    end
    if #state.groupMembers == 0 and type(oldSource) == "table"
        and oldSource.sessionID == source.sessionID and oldSource.activationID == source.activationID then
        state.groupMembers = recoveryMembers(previous.groupMembers)
    end
    if localState then
        state.localState = {
            sessionID = localState.sessionID,
            activationID = localState.activationID,
            visibility = localState.visibility,
            visibilityRevision = localState.visibilityRevision,
            openWindows = copyOpenWindows(localState.openWindows),
        }
    elseif remoteState then
        state.remoteState = {}
        for _, key in ipairs({
            "sessionID", "activationID", "gameMasterID", "gameMasterKey",
            "sessionName", "roundID", "roundNumber", "locked", "visibility",
            "sharedActions", "sharedBuffs", "sharedBuffProfile", "sharedRoundID", "lastSubmission",
            "lastVisibilityRevision", "lastStateRevision", "turnTracking",
            "turnSequence", "phase", "gmParticipates", "narratorName", "enemyPhases",
            "enemyFirst", "deferEnemyActions",
            "incomingActions", "incomingRoundID",
        }) do
            state.remoteState[key] = remoteState[key]
        end
        local pendingTurn = remoteState.pendingTurn
        local pendingRevision = type(pendingTurn) == "table"
            and recoveryInteger(pendingTurn.stateRevision) or nil
        local currentRevision = math.max(
            recoveryInteger(remoteState.lastStateRevision) or 0,
            recoveryInteger(remoteState.lastVisibilityRevision) or 0
        )
        if type(pendingTurn) == "table"
            and not pendingTurn.waitingForNPCs
            and pendingTurn.sessionId == remoteState.sessionID
            and pendingTurn.activationId == remoteState.activationID
            and pendingTurn.roundId == remoteState.roundID
            and type(pendingTurn.completed) == "boolean"
            and recoveryInteger(pendingTurn.sequence)
            and pendingRevision and pendingRevision <= currentRevision
            and addon.GameMasterStore.GetRevisionEpoch(pendingRevision)
                == addon.GameMasterStore.GetRevisionEpoch(currentRevision)
        then
            state.remoteState.pendingTurn = {
                sessionId = remoteState.sessionID,
                activationId = remoteState.activationID,
                roundId = remoteState.roundID,
                stateRevision = pendingRevision,
                sequence = tonumber(pendingTurn.sequence),
                completed = pendingTurn.completed,
                source = pendingTurn.source == "emote" and "emote" or "manual",
            }
        end
        state.remoteState.openWindows = copyOpenWindows(
            remoteState.openWindows
        )
        state.remoteState.originSequence = recoveryInteger(remoteState.originSequence) or 0
        state.remoteState.originOutbox = addon.GameMasterStore.NormalizeOriginOutbox(
            remoteState.originOutbox, playerKey, remoteState
        )
    end
     
     
    local kept, count = { [playerKey] = state }, 1
    for key, value in pairs(root.runtimeStates) do
        if count >= RECOVERY_CHARACTER_LIMIT then break end
        if key ~= playerKey and recoveryPlayer(key) == key then
            kept[key], count = value, count + 1
        end
    end
    root.runtimeStates = kept
    return true
end

function addon.GameMasterStore.GetRuntimeState(playerKey)
    local root = getRoot()
    local saved = root and type(root.runtimeStates) == "table"
        and root.runtimeStates[playerKey]
    if type(saved) ~= "table" or (saved.version ~= 1 and saved.version ~= 2) then return nil end
    local source = saved.localState or saved.remoteState
    if type(source) ~= "table" or not recoveryID(source.sessionID)
        or not recoveryID(source.activationID)
        or (not saved.localState and not recoveryPlayer(source.gameMasterID)) then return nil end
    return saved
end

function addon.GameMasterStore.ClearRuntimeState(playerKey)
    local root = getRoot()
    playerKey = recoveryPlayer(playerKey)
    if not root or not playerKey then return false end
    if type(root.runtimeStates) == "table" then root.runtimeStates[playerKey] = nil end
    return true
end

function addon.GameMasterStore.SuspendRuntimeState(playerKey, reason)
    local saved = addon.GameMasterStore.GetRuntimeState(playerKey)
    if not saved then return false end
    saved.status, saved.suspendedAt = "suspended", addon.Runtime.GetTimestamp()
    saved.suspendReason = reason == "left" and "left" or (reason == "unrelated" and "unrelated" or "missing")
    saved.requiresConfirmation = saved.requiresConfirmation == true or reason == "left" or reason == "unrelated"
    return true
end

 
 
function addon.GameMasterStore.GetRecoveryDisposition(playerKey, members, inGroup, restoring)
    local saved = addon.GameMasterStore.GetRuntimeState(playerKey)
    if not saved then return "none" end
    if saved.requiresConfirmation then return "confirm" end
    if not inGroup then return "waiting" end
    local current = {}
    local keys = recoveryMembers(members)
    for _, key in ipairs(keys) do current[key] = true end
     
    if #keys < 2 or not current[playerKey] then return "waiting" end
    local previous = recoveryMembers(saved.groupMembers)
    if restoring or saved.status == "suspended" then
         
         
        if #keys ~= #previous then return "confirm" end
        for index, key in ipairs(previous) do
            if keys[index] ~= key then return "confirm" end
        end
    end
    for _, key in ipairs(previous) do
        if key ~= playerKey and current[key] then return "live" end
    end
    return "confirm"
end

function addon.GameMasterStore.ConfirmRuntimeRecovery(playerKey, members)
    local saved = addon.GameMasterStore.GetRuntimeState(playerKey)
    local keys = recoveryMembers(members)
    if not saved or #keys < 2 then return false end
    saved.groupMembers, saved.requiresConfirmation, saved.status = keys, false, "live"
    saved.suspendedAt, saved.suspendReason = nil, nil
    return true
end

function addon.GameMasterStore.UpdateRoster(session, members)
    if type(session) ~= "table" or type(members) ~= "table" then
        return false
    end
    if type(session.participants) ~= "table" then
        session.participants = {}
    end
    if type(session.participantOrder) ~= "table" then
        session.participantOrder = {}
    end
    local timestamp = addon.Runtime.GetTimestamp()
    for _, participant in pairs(session.participants) do
        if type(participant) == "table" then
            participant.online = false
        end
    end

    local currentKeys = {}
    local memberOrder = {}
    for _, member in ipairs(members) do
        local playerKey = addon.Runtime.NormalizePlayerID(member.playerID)
        if playerKey and not currentKeys[playerKey] then
            currentKeys[playerKey] = true
            memberOrder[#memberOrder + 1] = playerKey
            local participant = session.participants[playerKey]
            if not participant then
                participant = {}
                session.participants[playerKey] = participant
            end
            participant.firstName = member.firstName
            participant.gameName = member.gameName or member.playerID
            participant.lastName = member.lastName
            participant.lastSeenAt = timestamp
            participant.online = member.online ~= false
            participant.playerID = member.playerID
            participant.profileColor = member.profileColor
            participant.profileIcon = member.profileIcon
            participant.rpName = member.rpName or participant.gameName
            participant.title = member.title
            if session.gmParticipates == false and playerKey == session.ownerKey then
                local name = addon.GameMasterStore.GetEncounterOptions(session).narratorName
                participant.rpName, participant.firstName, participant.gameName = name, name, name
                participant.lastName, participant.title = nil, nil
                participant.profileIcon, participant.profileColor = nil, nil
            end
        end
    end

    local limit = math.max(
        1,
        math.floor(tonumber(
            addon.Constants.GAMEMASTER_MAX_PARTICIPANTS
        ) or 40)
    )
    local nextOrder = {}
    local ordered = {}
    for _, playerKey in ipairs(session.participantOrder) do
        if currentKeys[playerKey]
            and not ordered[playerKey]
            and #nextOrder < limit
        then
            ordered[playerKey] = true
            nextOrder[#nextOrder + 1] = playerKey
        end
    end
    for _, playerKey in ipairs(memberOrder) do
        if not ordered[playerKey] and #nextOrder < limit then
            ordered[playerKey] = true
            nextOrder[#nextOrder + 1] = playerKey
        end
    end
    session.participantOrder = nextOrder
    session.updatedAt = timestamp
    return true
end

function addon.GameMasterStore.GetCurrentRound(session)
    if type(session) ~= "table" or type(session.rounds) ~= "table" then
        return nil
    end
    local round = session.rounds[#session.rounds]
    if round and round.id == session.currentRoundID then
        return round
    end
    for _, candidate in ipairs(session.rounds) do
        if candidate.id == session.currentRoundID then
            return candidate
        end
    end
    return nil
end

function addon.GameMasterStore.StartRound(session, historyLimit)
    if type(session) ~= "table" then
        return nil, addon.L("GAMEMASTER_SESSION_NOT_FOUND")
    end
    local timestamp = addon.Runtime.GetTimestamp()
    local current = addon.GameMasterStore.GetCurrentRound(session)
    if current and current.status == "open" then
        current.status = "locked"
        current.lockedAt = timestamp
    end

    local number = math.max(1, math.floor(tonumber(session.nextRoundNumber) or 1))
    session.nextRoundNumber = number + 1
    local round = {
        id = "round_" .. tostring(number),
        inactiveParticipants = {},
        number = number,
        phase = session.enemyPhases == true and session.enemyFirst == true and "enemies" or "players",
        enemyActionsRevealed = false,
        startedAt = timestamp,
        status = "open",
        submissions = {},
    }
    session.rounds[#session.rounds + 1] = round
    session.currentRoundID = round.id
    session.updatedAt = timestamp

    local limit = math.max(
        2,
        math.min(
            addon.Constants.GAMEMASTER_MAX_HISTORY,
            math.floor(tonumber(historyLimit)
                or addon.Constants.GAMEMASTER_DEFAULT_HISTORY)
        )
    )
    while #session.rounds > limit do
        table.remove(session.rounds, 1)
    end
    if addon.GameMasterEffects then
        addon.GameMasterEffects.Prune(
            session,
            round.number,
            timestamp
        )
    end
    return round
end

function addon.GameMasterStore.GetPreviousRound(session, current)
    if type(session) ~= "table" or type(current) ~= "table"
        or type(current.number) ~= "number" then return nil end
    for index = #(session.rounds or {}), 1, -1 do
        local round = session.rounds[index]
        if round.number == current.number - 1 then return round end
    end
end

function addon.GameMasterStore.StartPlayerPhase(session)
    local round = addon.GameMasterStore.GetCurrentRound(session)
    if not round or round.phase ~= "enemies" or session.enemyFirst ~= true then
        return nil, addon.L("GAMEMASTER_NO_ACTIVE_ROUND")
    end
    round.phase, round.enemyActionsRevealed = "players", true
    round.status, round.lockedAt = "open", nil
    round.playerStartedAt = addon.Runtime.GetTimestamp()
    session.updatedAt = round.playerStartedAt
    return round
end

function addon.GameMasterStore.StartEnemyPhase(session)
    local round = addon.GameMasterStore.GetCurrentRound(session)
    if not round or session.enemyPhases ~= true or round.phase == "enemies" then
        return nil, addon.L("GAMEMASTER_NO_ACTIVE_ROUND")
    end
    round.phase = "enemies"
    round.enemyActionsRevealed = false
    round.enemyStartedAt = addon.Runtime.GetTimestamp()
    round.enemyCompletedTurns = {}
    round.status = "open"
    round.lockedAt = nil
    session.updatedAt = round.enemyStartedAt
    return round
end

function addon.GameMasterStore.LockCurrentRound(session)
    local round = addon.GameMasterStore.GetCurrentRound(session)
    if not round then
        return false, addon.L("GAMEMASTER_NO_ACTIVE_ROUND")
    end
    if round.status ~= "open" then
        return true, round
    end
    round.status = "locked"
    round.lockedAt = addon.Runtime.GetTimestamp()
    session.updatedAt = round.lockedAt
    return true, round
end

function addon.GameMasterStore.UnlockCurrentRound(session)
    local round = addon.GameMasterStore.GetCurrentRound(session)
    if not round then
        return false, addon.L("GAMEMASTER_NO_ACTIVE_ROUND")
    end
    if round.status == "open" then
        return true, round
    end
    round.status = "open"
    round.lockedAt = nil
    session.updatedAt = addon.Runtime.GetTimestamp()
    return true, round
end

function addon.GameMasterStore.SetParticipantActive(
    session,
    playerKey,
    active,
    stateRevision
)
    local round = addon.GameMasterStore.GetCurrentRound(session)
    if not round
        or type(session.participants[playerKey]) ~= "table"
    then
        return false
    end
    if type(round.inactiveParticipants) ~= "table" then
        round.inactiveParticipants = {}
    end
    if active == false then
        round.inactiveParticipants[playerKey] = true
        round.submissions[playerKey] = nil
        if type(session.preparations) == "table" then
            session.preparations[playerKey] = nil
        end
    else
        round.inactiveParticipants[playerKey] = nil
    end
    if type(round.completedTurns) == "table" then
        round.completedTurns[playerKey] = nil
    end
    if type(round.turnSequences) ~= "table" then
        round.turnSequences = {}
    end
    round.turnSequences[playerKey] = math.min(
        addon.Constants.MAX_IMPORT_SAFE_INTEGER,
        math.max(0, math.floor(tonumber(
            round.turnSequences[playerKey]
        ) or 0)) + 1
    )
    if recoveryInteger(stateRevision) then
        round.participantStateRevisions = round.participantStateRevisions or {}
        round.participantStateRevisions[playerKey] = math.max(
            round.participantStateRevisions[playerKey] or 0, stateRevision
        )
    end
    session.updatedAt = addon.Runtime.GetTimestamp()
    return true
end

function addon.GameMasterStore.IsParticipantActive(round, playerKey)
    return type(round) ~= "table"
        or type(round.inactiveParticipants) ~= "table"
        or round.inactiveParticipants[playerKey] ~= true
end

function addon.GameMasterStore.IsParticipantTurnActive(session, round, playerKey)
    if type(session) ~= "table" then return false end
    if round and round.phase == "enemies" then return false end
    if session.gmParticipates == false and playerKey == session.ownerKey then return false end
    return addon.GameMasterStore.IsParticipantActive(round, playerKey)
end

function addon.GameMasterStore.CanParticipantAct(session, round, playerKey)
    local participant = type(session) == "table"
        and type(session.participants) == "table" and session.participants[playerKey]
    return type(participant) == "table" and participant.online ~= false
        and addon.GameMasterStore.IsParticipantTurnActive(session, round, playerKey)
end

function addon.GameMasterStore.CanParticipantSubmit(session, round, playerKey)
    return addon.GameMasterStore.CanParticipantAct(session, round, playerKey)
        and (not round or round.phase ~= "enemies")
        and not (session.gmParticipates == false and playerKey == session.ownerKey)
end

function addon.GameMasterStore.SetTurnCompleted(session, playerKey, completed, source)
    local round = addon.GameMasterStore.GetCurrentRound(session)
    if type(completed) ~= "boolean" or not round
        or (round.status ~= "open" and round.status ~= "locked")
        or not addon.GameMasterStore.CanParticipantAct(session, round, playerKey)
    then
        return false
    end
    local field = round.phase == "enemies" and "enemyCompletedTurns" or "completedTurns"
    if type(round[field]) ~= "table" then round[field] = {} end
    if (round[field][playerKey] ~= nil) == completed then return false end
    round[field][playerKey] = completed and {
        at = addon.Runtime.GetTimestamp(),
        source = source == "emote" and "emote" or "manual",
    } or nil
    session.updatedAt = addon.Runtime.GetTimestamp()
    return true
end

function addon.GameMasterStore.IsTurnCompleted(round, playerKey)
    local turns = type(round) == "table" and (round.phase == "enemies"
        and round.enemyCompletedTurns or round.completedTurns)
    return type(turns) == "table" and turns[playerKey] ~= nil or false
end

local function saveActorSubmission(session, playerKey, submission, npc)
    local round = addon.GameMasterStore.GetCurrentRound(session)
    if not round or round.status ~= "open" then
        return false, addon.L("GAMEMASTER_ROUND_LOCKED")
    end
    local allowed = npc and addon.GameMasterNPCActors
        and addon.GameMasterNPCActors.CanAct(session, round, playerKey)
        or not npc and addon.GameMasterStore.CanParticipantSubmit(session, round, playerKey)
    if not allowed
        or type(submission) ~= "table"
        or not addon.Constants.GAMEMASTER_ACTIONS[submission.action]
        or type(submission.spell) ~= "table"
    then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end

    local field = npc and "npcSubmissions" or "submissions"
    round[field] = round[field] or {}
    local existingSubmission = round[field][playerKey]
    local append = submission.mode == "append"
    if append and (
        submission.action == "prepare"
        or addon.GameMasterActionCollection.ContainsPreparation(
            existingSubmission
        )
    ) then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end
    if append and addon.GameMasterActionCollection.Count(existingSubmission)
        >= addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER
    then
        return false, addon.L("GAMEMASTER_ACTION_LIMIT_REACHED")
    end

    if type(session.preparations) ~= "table" then
        session.preparations = {}
    end
    local preparation
    if submission.action == "prepare"
        and type(submission.preparation) == "table"
    then
        local required = math.max(1, math.min(
            100,
            math.floor(tonumber(submission.preparation.required) or 0)
        ))
        local existing = session.preparations[playerKey]
        local previousRound = type(existing) == "table"
            and math.floor(tonumber(existing.lastPreparedRound)
                or ((tonumber(existing.startedRound) or round.number)
                    + (tonumber(existing.progress) or 1) - 1))
            or nil
        local sameRound = previousRound == round.number
        local continues = type(existing) == "table"
            and existing.spellID == submission.spell.id
            and tonumber(existing.required) == required
            and tonumber(existing.progress) < required
            and (sameRound or previousRound == round.number - 1)
        if not continues then
            existing = {
                automated = submission.preparation.automated == true,
                progress = 1,
                required = required,
                spellID = submission.spell.id,
                startedRound = round.number,
            }
        elseif not sameRound then
            existing.progress = math.min(
                required,
                math.floor(tonumber(existing.progress) or 0) + 1
            )
        end
        existing.automated = submission.preparation.automated == true
        existing.lastPreparedRound = round.number
        existing.required = required
        session.preparations[playerKey] = existing
        preparation = existing
    elseif submission.action ~= "prepare" then
        session.preparations[playerKey] = nil
    end

    local targets = copyTargets(submission.targets)
    local actionSnapshot = {
        action = submission.action,
        aoe = submission.aoe == true,
        emote = copyEmote(submission.emote),
        preparation = copyPreparation(preparation),
        spell = copySpell(submission.spell),
        submissionId = submission.submissionId,
        submittedAt = addon.Runtime.GetTimestamp(),
        target = targets[1] or copyTarget(submission.target),
        targets = targets,
    }
    local actions = {}
    if append then
        for _, existingAction in ipairs(
            addon.GameMasterActionCollection.Get(existingSubmission)
        ) do
            local copied = copyAction(existingAction)
            if copied then
                actions[#actions + 1] = copied
            end
        end
    end
    actions[#actions + 1] = actionSnapshot
    local stored = addon.GameMasterActionCollection.Set({
        playerID = submission.playerID,
        playerKey = playerKey,
        rpName = submission.rpName,
    }, actions)
    round[field][playerKey] = stored
    if addon.GameMasterEffects and not append then
        addon.GameMasterEffects.DiscardSourceRound(
            session,
            playerKey,
            round.id
        )
    end
    session.updatedAt = addon.Runtime.GetTimestamp()
    return true, stored, actionSnapshot
end

function addon.GameMasterStore.SaveSubmission(session, playerKey, submission)
    return saveActorSubmission(session, playerKey, submission, false)
end

function addon.GameMasterStore.SaveNPCSubmission(session, actorID, submission)
    return saveActorSubmission(session, actorID, submission, true)
end

function addon.GameMasterStore.GetPreparation(session, playerKey)
    return type(session) == "table"
        and type(session.preparations) == "table"
        and session.preparations[playerKey]
        or nil
end

function addon.GameMasterStore.ClearPreparation(session, playerKey)
    if type(session) ~= "table"
        or type(session.preparations) ~= "table"
        or session.preparations[playerKey] == nil
    then
        return false
    end
    session.preparations[playerKey] = nil
    local round = addon.GameMasterStore.GetCurrentRound(session)
    local submission = round
        and round.submissions
        and round.submissions[playerKey]
    if submission and addon.GameMasterActionCollection.ContainsPreparation(
        submission
    ) then
        round.submissions[playerKey] = nil
    elseif submission then
        submission.preparation = nil
    end
    session.updatedAt = addon.Runtime.GetTimestamp()
    return true
end

function addon.GameMasterStore.MoveParticipant(session, playerKey, direction)
    if type(session) ~= "table"
        or not session.participants[playerKey]
        or (session.gmParticipates == false and playerKey == session.ownerKey)
        or (direction ~= -1 and direction ~= 1)
    then
        return false
    end
    local source
    for index, currentKey in ipairs(session.participantOrder) do
        if currentKey == playerKey then
            source = index
            break
        end
    end
    if not source then
        return false
    end
    local target = source + (direction < 0 and -1 or 1)
    if session.gmParticipates == false and session.participantOrder[target] == session.ownerKey then
        target = target + direction
    end
    if target < 1 or target > #session.participantOrder then
        return false
    end
    session.participantOrder[source], session.participantOrder[target] =
        session.participantOrder[target], session.participantOrder[source]
    session.updatedAt = addon.Runtime.GetTimestamp()
    return true
end

function addon.GameMasterStore.IsOrderLocked()
    local root = getRoot()
    return not root or root.orderLocked ~= false
end

function addon.GameMasterStore.SetOrderLocked(locked)
    local root = getRoot()
    if not root then
        return false
    end
    root.orderLocked = locked ~= false
    return true
end

function addon.GameMasterStore.IsCollapsed()
    local root = getRoot()
    return root and root.collapsed == true
end

function addon.GameMasterStore.SetCollapsed(collapsed)
    local root = getRoot()
    if not root then
        return false
    end
    root.collapsed = collapsed == true
    return true
end

function addon.GameMasterStore.GetWindowLayout()
    local root = getRoot()
    return root and root.window or {}
end

function addon.GameMasterStore.SaveWindowLayout(frame, saveSize)
    local root = getRoot()
    if not root or not frame or type(frame.GetPoint) ~= "function" then
        return false
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if type(point) ~= "string" or type(relativePoint) ~= "string" then
        return false
    end
    local previous = type(root.window) == "table"
        and root.window
        or {}
    local width = tonumber(previous.width) or 560
    local height = tonumber(previous.height) or 390
    if saveSize == true
        and type(frame.GetWidth) == "function"
        and type(frame.GetHeight) == "function"
    then
        width = tonumber(frame:GetWidth()) or width
        height = tonumber(frame:GetHeight()) or height
    end
    root.window = {
        height = math.max(300, math.min(750, height)),
        point = point,
        relativePoint = relativePoint,
        width = math.max(520, math.min(900, width)),
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
    }
    return true
end

function addon.GameMasterStore.IsCompactCollapsed()
    local root = getRoot()
    return root and root.compactCollapsed == true
end

function addon.GameMasterStore.SetCompactCollapsed(collapsed)
    local root = getRoot()
    if not root then
        return false
    end
    root.compactCollapsed = collapsed == true
    return true
end

function addon.GameMasterStore.IsCompactLocked()
    local root = getRoot()
    return root and root.compactLocked == true
end

function addon.GameMasterStore.SetCompactLocked(locked)
    local root = getRoot()
    if not root then
        return false
    end
    root.compactLocked = locked == true
    return true
end

function addon.GameMasterStore.GetCompactWindowLayout()
    local root = getRoot()
    return root and root.compactWindow or {}
end

function addon.GameMasterStore.SaveCompactWindowLayout(frame, saveSize)
    local root = getRoot()
    if not root
        or not frame
        or type(frame.GetPoint) ~= "function"
    then
        return false
    end

    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if type(point) ~= "string" or type(relativePoint) ~= "string" then
        return false
    end

    local previous = type(root.compactWindow) == "table"
        and root.compactWindow
        or {}
    local width = tonumber(previous.width) or 380
    local height = tonumber(previous.height) or 500
    if saveSize == true
        and type(frame.GetWidth) == "function"
        and type(frame.GetHeight) == "function"
    then
        width = tonumber(frame:GetWidth()) or width
        height = tonumber(frame:GetHeight()) or height
    end

    root.compactWindow = {
        point = point,
        relativePoint = relativePoint,
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        width = math.max(280, math.min(680, width)),
        height = math.max(240, math.min(800, height)),
    }
    return true
end
