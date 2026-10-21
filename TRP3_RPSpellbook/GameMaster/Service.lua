local _, addon = ...

addon.GameMasterService = {
    initialized = false,
}

local listeners = {}
local activeGameMaster
local remoteSession
local testSession
local tutorial
local activationSerial = 0
local compatibilityReport
local eventFrame
local lastSyncRequestAt = -math.huge
local lastRecoveryRequestAt = -math.huge
local lastVisibilitySendErrorAt = -math.huge
local sendVisibilityTo
local sendAssistantStateTo
local broadcastAssistantStates
local restoredRuntime = false
local reopenAfterRecovery = false
local turnHintUntil = 0
local ownTurnWasActive = false
local ownTurnIdentity
local lastOwnNoticeAt = -math.huge
local notifyOwnTurn
local scheduleTurnRecovery
local flushOriginOutbox
local flushPendingTurn
local requestLeaderSync
local restoreRecoveredWindows
local pendingNPCSubmissions = {}
local pendingVisibility
local pendingRosterRetry
local companionDiscovery
local companionQueryGate
local companionReplyGate
local companionQuerySerial = 0

local function currentReaderProfile()
    return addon.EffectVisibility and addon.EffectVisibility.Profile()
        or addon.Database.GetActiveProfileKey and addon.Database.GetActiveProfileKey() or nil
end

local function publicBuffsOnly(states)
    local result = {}
    for key, entries in pairs(states or {}) do
        local public = {}
        for _, entry in ipairs(entries) do
            if not entry.hidden then public[#public + 1] = entry end
        end
        if #public > 0 then result[key] = public end
    end
    return result
end

local runtimeWindowModules = {
    compactSpellbook = "GameMasterCompactSpellbook",
    currentAction = "GameMasterActionStatus",
    gameMaster = "GameMasterWindow",
    roundOverview = "GameMasterSharedActions",
}

local function normalizeOpenWindows(value)
    if type(value) ~= "table" then return nil end
    local result = {}
    for moduleID in pairs(runtimeWindowModules) do
        result[moduleID] = value[moduleID] == true
    end
    return result
end

local function captureOpenWindows()
    local result = {}
    for moduleID, addonKey in pairs(runtimeWindowModules) do
        local module = addon[addonKey]
        result[moduleID] = type(module) == "table"
            and type(module.IsShown) == "function"
            and module.IsShown() == true
            or false
    end
    return result
end

local function checkpointOpenWindows()
    local state = activeGameMaster or remoteSession
    if state and not reopenAfterRecovery then
        state.openWindows = captureOpenWindows()
    end
end

local function getVisibilityRevision()
    if not activeGameMaster then
        return 0
    end
    local revision = tonumber(activeGameMaster.visibilityRevision)
    if not revision or revision < 0 or revision > addon.Constants.MAX_IMPORT_SAFE_INTEGER
        or revision ~= math.floor(revision) then
        revision = 0
        activeGameMaster.visibilityRevision = revision
    end
    return revision
end

local function advanceVisibilityRevision()
    if not activeGameMaster then
        return 0
    end
    local revision = getVisibilityRevision() + 1
    if revision > addon.Constants.MAX_IMPORT_SAFE_INTEGER then
         
        return getVisibilityRevision()
    end
    activeGameMaster.visibilityRevision = revision
    activeGameMaster.visibilitySnapshots = nil
    return revision
end

local function hasGameMasterModule()
    return not addon.Modules or addon.Modules.IsEnabled("gameMaster")
end

local function isLocalController()
    if testSession then return true end
    if tutorial then return tutorial.role == "gm" end
    if not hasGameMasterModule() then return false end
    if activeGameMaster then
        local session = addon.GameMasterStore.GetSession(activeGameMaster.sessionID)
        local owner = session ~= nil and session.ownerKey == addon.Runtime.NormalizePlayerID(
            addon.GameMasterRoster.GetLocalPlayerID()
        ) and addon.GameMasterRoster.IsInGroup()
        if not owner then return false end
        local members = addon.GameMasterRoster.GetMembers()
        if addon.GameMasterRoster.IsAvailable and not addon.GameMasterRoster.IsAvailable() then return true end
        return addon.GameMasterStore.GetRecoveryDisposition(session.ownerKey, members, true) ~= "confirm"
    end
    return not remoteSession and addon.GameMasterRoster.IsLocalLeader()
end

local function notifyListeners(reason)
    if not testSession and not tutorial and addon.GameMasterStore.SaveRuntimeState then
        checkpointOpenWindows()
        addon.GameMasterStore.SaveRuntimeState(
            addon.Runtime.NormalizePlayerID(addon.GameMasterRoster.GetLocalPlayerID()),
            activeGameMaster, remoteSession
        )
    end
    local turn = addon.GameMasterService.GetTurnState
        and addon.GameMasterService.GetTurnState()
        or nil
    local status = addon.GameMasterActionStatus
    if turn and status and status.SetTurnState then
        addon.Runtime.SafeInvoke(status.SetTurnState, {
            visible = addon.GameMasterService.IsSessionActive()
                and (activeGameMaster ~= nil or (remoteSession and remoteSession.turnTracking))
                and turn.active,
            enabled = addon.GameMasterService.CanCompleteTurn(),
            completed = turn.completed,
        })
        if reason == "emoteHint" and status.HintTurnCompletion then
            addon.Runtime.SafeInvoke(status.HintTurnCompletion)
        end
    end
    for _, listener in ipairs(listeners) do
        local success, errorMessage = addon.Runtime.SafeInvoke(listener, reason)
        if not success then
            addon.Logger.Error(tostring(errorMessage))
        end
    end
    local ownTurnActive = turn ~= nil
        and addon.GameMasterService.IsSessionActive()
        and turn.active
        and turn.isNext
        and not turn.completed
    local sessionState = activeGameMaster or remoteSession
    local round = activeGameMaster and addon.GameMasterStore.GetCurrentRound(
        testSession or addon.GameMasterStore.GetSession(activeGameMaster.sessionID)
    )
    local turnIdentity = sessionState and table.concat({ sessionState.sessionID,
        sessionState.activationID, round and round.id or sessionState.roundID or "",
        round and round.phase or sessionState.phase or "players" }, ":")
    if ownTurnActive and (not ownTurnWasActive or turnIdentity ~= ownTurnIdentity) and notifyOwnTurn then
        addon.Runtime.SafeInvoke(notifyOwnTurn)
    end
    if addon.GameMasterTurnSound and (not ownTurnActive
        or not addon.GameMasterSettings.ShouldPlayOwnTurnSound
        or not addon.GameMasterSettings.ShouldPlayOwnTurnSound()) then
        addon.GameMasterTurnSound.Stop("turn")
    end
    ownTurnWasActive = ownTurnActive == true
    ownTurnIdentity = turnIdentity
end

local function showScreenNotice(message)
    if not _G.RaidWarningFrame then return false end
    local color = _G.ChatTypeInfo and _G.ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.82, b = 0 }
    local notices = _G.RaidWarningUtil
    if type(notices) == "table" and type(notices.AddMessage) == "function" then
        return pcall(notices.AddMessage, message, color)
    end
    if type(RaidNotice_AddMessage) == "function" then
        return pcall(RaidNotice_AddMessage, _G.RaidWarningFrame, message, color)
    end
    return false
end

local function notifyPlayer(message)
    if addon.GameMasterSettings.ShouldShowChatFeedback() then
        addon.Logger.Info(message)
    end
    if addon.GameMasterSettings.ShouldShowScreenFeedback() then
        showScreenNotice(message)
    end
    if addon.GameMasterSettings.ShouldPlayFeedbackSound()
        and addon.GameMasterTurnSound
    then
        addon.GameMasterTurnSound.Play(nil, "feedback")
    end
end

local function scheduleChatFallback(eventName, context, delay)
    if testSession then
        return false
    end
    if type(addon.ChatFallbacks) ~= "table"
        or type(
            addon.ChatFallbacks.ScheduleGameMasterAnnouncement
        ) ~= "function"
    then
        return false
    end
    return addon.ChatFallbacks.ScheduleGameMasterAnnouncement(
        eventName,
        context,
        delay
    )
end

local function isSafeID(value)
    return addon.Runtime.IsSafeIdentifier(
        value,
        addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
    )
end

local function cleanText(value, maximumLength)
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

local function createActivationID()
    activationSerial = activationSerial + 1
    if activationSerial > 1000000 then
        activationSerial = 1
    end
    return string.format(
        "activation_%d_%d",
        math.floor(addon.Runtime.GetMonotonicTime() * 1000),
        activationSerial
    )
end

local function createSubmissionID()
    if not remoteSession and not activeGameMaster then return nil end
    local sequence = addon.GameMasterStore.AllocateOriginSequence(remoteSession and remoteSession.originSequence)
    if not sequence then return nil end
    if remoteSession then remoteSession.originSequence = sequence end
    return "origin_" .. string.format("%.0f", sequence)
end

local function getLocalPlayerID()
    return addon.GameMasterRoster.GetLocalPlayerID()
end

local function getLocalPlayerKey()
    return addon.Runtime.NormalizePlayerID(getLocalPlayerID())
end

local function getStateRevision(state)
    return type(state) == "table" and math.max(state.visibilityRevision or 0,
        state.lastStateRevision or 0, state.lastVisibilityRevision or 0) or 0
end

local function pendingFromOriginPayload(payload)
    return {
        id = payload.submissionId, submissionId = payload.submissionId,
        action = payload.action, mode = payload.mode, aoe = payload.aoe,
        spell = payload.spell, targets = payload.targets, target = payload.target,
        preparation = payload.preparation, emote = payload.emote, wirePayload = payload,
        waitingForSync = true, retryCount = 0,
    }
end

local function getOriginQueue()
    return remoteSession and type(remoteSession.originQueue) == "table"
        and remoteSession.originQueue or nil
end

local function getOriginHead()
    local queue = getOriginQueue()
    return queue and queue[1] or nil
end

local function clearOriginQueue()
    if not remoteSession then return end
    remoteSession.originQueue = nil
    remoteSession.originOutbox = nil
    remoteSession.pendingSubmission = nil
end

local function syncOriginQueue()
    local queue = getOriginQueue()
    if not queue or #queue == 0 then
        clearOriginQueue()
        return true
    end
    local payloads = {}
    for index, pending in ipairs(queue) do
        if type(pending) ~= "table" or type(pending.wirePayload) ~= "table" then
            clearOriginQueue()
            return false
        end
        payloads[index] = pending.wirePayload
    end
    local outbox = addon.GameMasterStore.NormalizeOriginOutbox({
        version = 2, originKey = getLocalPlayerKey(),
        gameMasterKey = remoteSession.gameMasterKey, items = payloads,
    }, getLocalPlayerKey(), remoteSession)
    if not outbox then
        clearOriginQueue()
        return false
    end
    for index, payload in ipairs(outbox.items) do
        queue[index].wirePayload = payload
    end
    remoteSession.originOutbox = outbox
    remoteSession.pendingSubmission = queue[1]
    return true
end

local function pendingAction(pending, accepted)
    local preparation = pending.preparation
    if type(preparation) == "table" then
        preparation = {
            progress = accepted and 1 or 0,
            required = preparation.required,
        }
    end
    return {
        action = pending.action, aoe = pending.aoe, emote = pending.emote,
        preparation = preparation, spell = pending.spell,
        submissionId = pending.submissionId,
        target = pending.target, targets = pending.targets,
    }
end

local function applyPendingSubmission(base, pending, accepted)
    local actions = {}
    if pending.mode == "append" then
        for _, action in ipairs(addon.GameMasterActionCollection.Get(base)) do
            actions[#actions + 1] = action
        end
    end
    actions[#actions + 1] = pendingAction(pending, accepted)
    local member = addon.GameMasterRoster.FindMember(getLocalPlayerID())
    return addon.GameMasterActionCollection.Set({
        playerID = type(base) == "table" and base.playerID
            or member and member.playerID or getLocalPlayerID(),
        rpName = type(base) == "table" and base.rpName
            or member and member.rpName or getLocalPlayerID(),
    }, actions)
end

local function projectOriginQueue()
    local projected = remoteSession and remoteSession.lastSubmission or nil
    for _, pending in ipairs(getOriginQueue() or {}) do
        projected = applyPendingSubmission(projected, pending, false)
        if not projected then return nil end
    end
    return projected
end

local function restoreOriginOutbox(raw)
    local outbox = addon.GameMasterStore.NormalizeOriginOutbox(raw, getLocalPlayerKey(), remoteSession)
    if not outbox then
        if raw ~= nil then
            clearOriginQueue()
            notifyPlayer(addon.L("GAMEMASTER_SUBMISSION_REJECTED"))
        end
        return
    end
    local queue = {}
    for index, payload in ipairs(outbox.items) do
        remoteSession.originSequence = math.max(remoteSession.originSequence or 0,
            payload.originSequence)
        queue[index] = pendingFromOriginPayload(payload)
    end
    remoteSession.originQueue = queue
    remoteSession.originOutbox = outbox
    remoteSession.pendingSubmission = queue[1]
end

local function rebaseRecoveryIntents(previous, state)
    state.turnSequence = previous.turnSequence
    state.lastSubmission = previous.lastSubmission
    state.preparation = previous.preparation
    state.originReady = false
    state.originPeerSerial = 0
    state.originSyncSerial = 0

    local raw = previous.originOutbox
    local count = type(raw) == "table" and type(raw.items) == "table"
        and addon.Runtime.GetBoundedArrayLength(raw.items,
            addon.Constants.GAMEMASTER_ORIGIN_OUTBOX_LIMIT) or nil
    if count and count > 0 then
        local items = {}
        for index = 1, count do
            local source = raw.items[index]
            if type(source) ~= "table" then
                items = nil
                break
            end
            local payload = {}
            for key, value in pairs(source) do payload[key] = value end
            payload.stateRevision = state.lastStateRevision
            items[index] = payload
        end
        local outbox = items and addon.GameMasterStore.NormalizeOriginOutbox({
            version = 2,
            originKey = getLocalPlayerKey(),
            gameMasterKey = state.gameMasterKey,
            items = items,
        }, getLocalPlayerKey(), state) or nil
        if outbox then
            local queue = {}
            for index, payload in ipairs(outbox.items) do
                state.originSequence = math.max(state.originSequence or 0,
                    payload.originSequence)
                queue[index] = pendingFromOriginPayload(payload)
            end
            state.originQueue = queue
            state.originOutbox = outbox
            state.pendingSubmission = queue[1]
        end
    end

    local pending = previous.pendingTurn
    local sequence = type(pending) == "table" and readInteger(
        pending.sequence, 1, addon.Constants.MAX_IMPORT_SAFE_INTEGER
    ) or nil
    if sequence
        and pending.sessionId == state.sessionID
        and pending.activationId == state.activationID
        and pending.roundId == state.roundID
        and type(pending.completed) == "boolean"
    then
        state.turnSequence = math.max(state.turnSequence or 0, sequence)
        state.pendingTurn = {
            sessionId = state.sessionID,
            activationId = state.activationID,
            stateRevision = state.lastStateRevision,
            roundId = state.roundID,
            completed = pending.completed,
            sequence = sequence,
            source = pending.source == "emote" and "emote" or "manual",
            waitingForSync = true,
            retryAttempts = 0,
        }
    end
end

local function sessionMatches(payload, state, identityOnly)
    local matches = type(payload) == "table"
        and type(state) == "table"
        and payload.sessionId == state.sessionID
        and payload.activationId == state.activationID
    if not matches or identityOnly then return matches end
    local revision = payload.stateRevision == nil and 0 or readInteger(payload.stateRevision,
        0, addon.Constants.MAX_IMPORT_SAFE_INTEGER)
    return revision ~= nil and addon.GameMasterStore.GetRevisionEpoch(revision)
        == addon.GameMasterStore.GetRevisionEpoch(getStateRevision(state))
end

local function isCurrentLeader(sender)
    if tutorial then
        return addon.GameMasterRoster.IsInGroup() and addon.GameMasterRoster.IsMember(sender)
            and addon.GameMasterRoster.IsLeader(sender)
    end
    if activeGameMaster then return false end
    if remoteSession then
        return addon.GameMasterRoster.IsInGroup()
            and addon.GameMasterRoster.IsMember(sender)
            and addon.Runtime.NormalizePlayerID(sender) == remoteSession.gameMasterKey
    end
    local saved = addon.GameMasterStore.GetRuntimeState(getLocalPlayerKey())
    if saved and addon.GameMasterStore.GetRecoveryDisposition(getLocalPlayerKey(),
        addon.GameMasterRoster.GetMembers(), addon.GameMasterRoster.IsInGroup()) ~= "confirm"
    then
        return saved.remoteState ~= nil and addon.GameMasterRoster.IsInGroup()
            and addon.GameMasterRoster.IsMember(sender)
            and addon.Runtime.NormalizePlayerID(sender) == saved.remoteState.gameMasterKey
    end
    return not activeGameMaster and addon.GameMasterRoster.IsInGroup()
        and addon.GameMasterRoster.IsLeader(sender)
end

local function getSession()
    if testSession then
        return testSession
    end
    return activeGameMaster
        and addon.GameMasterStore.GetSession(activeGameMaster.sessionID)
        or nil
end

local function getCurrentRound()
    local session = getSession()
    return session and addon.GameMasterStore.GetCurrentRound(session) or nil
end

local function getEffectiveVisibility(playerID)
    local session = getSession()
    if not session or not activeGameMaster then
        return "hidden"
    end
    local access = addon.GameMasterStore.GetSceneAccess(session)
    access.defaultVisibility = addon.GameMasterVisibility.Normalize(
        activeGameMaster.visibility
    )
    return addon.GameMasterSceneAccess.GetVisibility(
        access,
        playerID
    )
end

local function createSessionPayload(playerID)
    local session = getSession()
    if not session or not activeGameMaster then
        return nil
    end
    local round = addon.GameMasterStore.GetCurrentRound(session)
    return {
        activationId = activeGameMaster.activationID,
        locked = not round or round.status ~= "open" or round.phase == "enemies",
        roundId = round and round.id or "",
        roundNumber = round and round.number or 0,
        sessionId = session.id,
        sessionName = session.name,
        stateRevision = getVisibilityRevision(),
        recovering = activeGameMaster.recovering == true,
        turnTracking = true,
        phase = addon.GameMasterStore.GetPhase(session),
        gmParticipates = session.gmParticipates ~= false,
        narratorName = addon.GameMasterStore.GetEncounterOptions(session).narratorName,
        enemyPhases = session.enemyPhases == true,
        enemyFirst = session.enemyFirst == true,
        deferEnemyActions = session.deferEnemyActions ~= false,
        visibility = getEffectiveVisibility(playerID),
    }
end

local function sendStateTo(playerID, priority)
    if testSession or tutorial then return false end
    if not activeGameMaster
        or not addon.GameMasterRoster.IsMember(playerID)
        or not addon.GameMasterProtocol.Supports(playerID)
    then
        return false
    end
    local payload = createSessionPayload(playerID)
    if not payload then return false end
    local session = getSession()
    local member = addon.GameMasterRoster.FindMember(playerID)
    local preparation = session and member
        and addon.GameMasterStore.GetPreparation(session, member.playerKey)
        or nil
    payload.preparationState = preparation and "active" or "none"
    if preparation then
        payload.preparation = {
            automated = preparation.automated == true,
            lastPreparedRound = preparation.lastPreparedRound,
            progress = preparation.progress,
            required = preparation.required,
            spellID = preparation.spellID,
            startedRound = preparation.startedRound,
        }
    end
    local sent, errorMessage = addon.GameMasterProtocol.Send(
        playerID,
        "session",
        payload,
        priority or "MEDIUM"
    )
    if sent and sendVisibilityTo then
        sendVisibilityTo(playerID, priority or "MEDIUM")
    end
    if sent and sendAssistantStateTo then
        sendAssistantStateTo(playerID, priority or "MEDIUM")
    end
    return sent, errorMessage
end

local function queryOrSend(member, priority)
    if not member or member.playerKey == getLocalPlayerKey() then
        return
    end
    if addon.GameMasterProtocol.Supports(member.playerID) then
        return sendStateTo(member.playerID, priority)
    else
        addon.GameMasterProtocol.Query(member.playerID)
    end
end

local function broadcast(eventName, payload, priority)
    if testSession then
        return false
    end
    local sent = false
    local localKey = getLocalPlayerKey()
    for _, member in ipairs(addon.GameMasterRoster.GetMembers()) do
        if member.playerKey ~= localKey then
            if addon.GameMasterProtocol.SupportsKnown(member.playerID) then
                sent = addon.GameMasterProtocol.Send(
                    member.playerID,
                    eventName,
                    payload,
                    priority
                ) or sent
            end
            if not addon.GameMasterProtocol.Supports(member.playerID) then
                addon.GameMasterProtocol.Query(member.playerID)
            end
        end
    end
    return sent
end


local function getSharedVisibilitySnapshot(session, round, mode)
    local cache = activeGameMaster.visibilitySnapshots
    if type(cache) ~= "table" then
        cache = {}
        activeGameMaster.visibilitySnapshots = cache
    end
    local key = table.concat({
        tostring(getVisibilityRevision()),
        tostring(round and round.id or ""),
        mode,
    }, "\031")
    if not cache[key] then
        cache[key] = {
            buffStates = addon.GameMasterEffects
                and addon.GameMasterEffects.BuildSharedBuffStates(session)
                or {},
            entries = addon.GameMasterVisibility.BuildEntries(session, round, mode),
        }
    end
    return cache[key]
end

local function incomingForPlayer(session, round, playerID)
    local incoming = addon.GameMasterIncomingActions
    if not incoming or not round then return {} end
    local snapshot = getSharedVisibilitySnapshot(session, round, "hidden")
    snapshot.incomingByPlayer = snapshot.incomingByPlayer
        or (incoming.BuildIndex and incoming.BuildIndex(session, round)) or {}
    local key = addon.Runtime.NormalizePlayerID(playerID)
    if not key then return {} end
    if not snapshot.incomingByPlayer[key] and not incoming.BuildIndex then
        snapshot.incomingByPlayer[key] = incoming.Build(session, round, playerID)
    end
    return snapshot.incomingByPlayer[key] or {}
end

local function createVisibilityPayload(playerID)
    local session = getSession()
    local round = session
        and addon.GameMasterStore.GetCurrentRound(session)
    if not session or not activeGameMaster then
        return nil
    end
    local mode = getEffectiveVisibility(playerID)
    local playerKey = addon.GameMasterEffects
        and type(addon.GameMasterEffects.FindParticipantKey) == "function"
        and addon.GameMasterEffects.FindParticipantKey(session, playerID)
        or nil
    local shared = getSharedVisibilitySnapshot(session, round, mode)
    local buffStates = shared.buffStates
    local readerProfile = addon.TRP3Bridge and addon.TRP3Bridge.GetPlayerProfileKey
        and addon.TRP3Bridge.GetPlayerProfileKey(playerID) or nil
    if addon.EffectVisibility then
        buffStates = addon.EffectVisibility.FilterCombat(buffStates, playerID, readerProfile,
            type(addon.Communication.HasCapability) ~= "function"
                or not addon.Communication.HasCapability(playerID, "hidden-effects-v1"))
    end
    local ownSubmission = {}
    local participant = playerKey
        and type(session.participants) == "table"
        and session.participants[playerKey]
        or nil
    if participant and round then
        ownSubmission = addon.GameMasterVisibility.BuildEntries(
            {
                participantOrder = { playerKey },
                participants = { [playerKey] = participant },
                npcActors = session.npcActors,
            },
            {
                submissions = {
                    [playerKey] = round.submissions
                        and round.submissions[playerKey]
                        or nil,
                },
            },
            "full"
        )
    end
    local entries = shared.entries
    if not addon.Communication.HasKnownCapability
        or not addon.Communication.HasKnownCapability(playerID, "gamemaster-companions-v1") then
        local legacy = {}
        for _, entry in ipairs(entries) do
            if entry.actorKind ~= "npc" or entry.side ~= "players" then legacy[#legacy + 1] = entry end
        end
        entries = legacy
    end
    if addon.GameMasterProtocol.SupportsNPCs and not addon.GameMasterProtocol.SupportsNPCs(playerID) then
        entries = addon.GameMasterVisibility.LegacyEntries(entries)
        ownSubmission = addon.GameMasterVisibility.LegacyEntries(ownSubmission)
        local playerBuffs = {}
        for _, state in ipairs(buffStates) do
            if not addon.GameMasterNPCActors.IsID(state.playerKey) then playerBuffs[#playerBuffs + 1] = state end
        end
        buffStates = playerBuffs
    end
    if addon.GameMasterProtocol.SupportsDebuffs
        and not addon.GameMasterProtocol.SupportsDebuffs(playerID)
    then
        entries = addon.GameMasterVisibility.LegacyDebuffEntries(entries)
        ownSubmission = addon.GameMasterVisibility.LegacyDebuffEntries(ownSubmission)
        buffStates = addon.GameMasterVisibility.LegacyBuffStates(buffStates)
    end
    return {
        activationId = activeGameMaster.activationID,
        buffStates = buffStates,
        readerProfile = readerProfile,
        controlledNPCs = addon.Communication.HasKnownCapability
            and addon.Communication.HasKnownCapability(playerID, "gamemaster-companions-v1")
            and addon.GameMasterNPCActors.ControlUnits(session, playerKey) or nil,
        entries = entries,
        incomingActions = addon.GameMasterProtocol.SupportsIncoming
            and addon.GameMasterProtocol.SupportsIncoming(playerID)
            and incomingForPlayer(session, round, playerID) or nil,
        phase = addon.GameMasterStore.GetPhase(session),
        ownSubmission = ownSubmission,
        roundId = round and round.id or "",
        roundNumber = round and round.number or 0,
        sessionId = session.id,
        stateRevision = getVisibilityRevision(),
        visibility = mode,
    }
end

sendVisibilityTo = function(playerID, priority)
    local payload = createVisibilityPayload(playerID)
    if not payload then
        return false
    end
    local sent, errorMessage = addon.GameMasterProtocol.Send(
        playerID,
        "visibility",
        payload,
        priority or "MEDIUM"
    )
    if not sent then
        local now = addon.Runtime.GetMonotonicTime()
        if now - lastVisibilitySendErrorAt >= 10 then
            lastVisibilitySendErrorAt = now
            addon.Logger.Error(
                errorMessage or addon.L("COMMUNICATION_SEND_FAILED")
            )
        end
    end
    return sent, errorMessage
end

local function publishVisibility(priority)
    local sent = false
    local localKey = getLocalPlayerKey()
    for _, member in ipairs(addon.GameMasterRoster.GetMembers()) do
        if member.playerKey ~= localKey then
            if addon.GameMasterProtocol.SupportsKnown(member.playerID) then
                sent = sendVisibilityTo(
                    member.playerID,
                    priority or "MEDIUM"
                ) or sent
            end
            if not addon.GameMasterProtocol.Supports(member.playerID) then
                addon.GameMasterProtocol.Query(member.playerID)
            end
        end
    end
    return sent
end

local function broadcastVisibility(priority)
    advanceVisibilityRevision()
    if testSession or not activeGameMaster then return false end
    if not C_Timer or not C_Timer.After then return publishVisibility(priority) end
    if pendingVisibility and pendingVisibility.state ~= activeGameMaster then pendingVisibility = nil end
    if pendingVisibility then
        if priority == "HIGH" then pendingVisibility.priority = priority end
        return true
    end
    local pending = { state = activeGameMaster, priority = priority }
    pendingVisibility = pending
    C_Timer.After(0.2, function()
        if pendingVisibility ~= pending then return end
        pendingVisibility = nil
        if activeGameMaster == pending.state and not testSession then
            publishVisibility(pending.priority)
        end
    end)
    return true
end

local function broadcastCurrentState(priority)
    pendingVisibility = nil
     
    advanceVisibilityRevision()
    if testSession then
        return false
    end
    local sent = false
    local localKey = getLocalPlayerKey()
    for _, member in ipairs(addon.GameMasterRoster.GetMembers()) do
        if member.playerKey ~= localKey then
            sent = queryOrSend(
                member,
                priority or "MEDIUM"
            ) or sent
        end
    end
    return sent
end

local function getAssistant(playerID)
    local _, fullKey = addon.Runtime.NormalizeFullPlayerID(playerID)
    local playerKey = fullKey or addon.Runtime.NormalizePlayerID(playerID)
    return activeGameMaster
        and type(activeGameMaster.assistants) == "table"
        and playerKey
        and activeGameMaster.assistants[playerKey]
        or nil
end

sendAssistantStateTo = function(playerID, priority, authorized)
    if not activeGameMaster
        or not addon.GameMasterRoster.IsMember(playerID)
        or not addon.GameMasterProtocol.SupportsDelegation(playerID)
    then
        return false
    end
    local session = getSession()
    if not session then
        return false
    end
    local assistant = getAssistant(playerID)
    if authorized == nil then
        authorized = type(assistant) == "table"
    end
    local payload = {
        activationId = activeGameMaster.activationID,
        stateRevision = advanceVisibilityRevision(),
        authorized = authorized == true,
        sessionId = session.id,
    }
    if payload.authorized then
        payload.control = addon.GameMasterDelegation
            .BuildControlState(session)
        payload.rights = addon.GameMasterDelegation
            .NormalizeRights(assistant)
    end
    return addon.GameMasterProtocol.Send(
        playerID,
        "assistantState",
        payload,
        priority or "MEDIUM"
    )
end

broadcastAssistantStates = function(priority)
    if testSession
        or not activeGameMaster
        or type(activeGameMaster.assistants) ~= "table"
    then
        return false
    end
    local sent = false
    for playerKey in pairs(activeGameMaster.assistants) do
        local member = addon.GameMasterRoster.FindMember(playerKey)
        if member then
            sent = sendAssistantStateTo(
                member.playerID,
                priority or "MEDIUM"
            ) or sent
        end
    end
    return sent
end

local function updateStoredRoster()
    local session = getSession()
    if not session then
        return false
    end
    if testSession then
        return true
    end
    local updated = addon.GameMasterStore.UpdateRoster(
        session,
        addon.GameMasterRoster.GetMembers()
    )
    if updated then
        notifyListeners("roster")
    end
    return updated
end

local function printCompatibilityReport(activationID)
    if not compatibilityReport
        or compatibilityReport.activationID ~= activationID
        or compatibilityReport.printed
    then
        return
    end
    compatibilityReport.printed = true

    local compatible = {}
    local incompatible = {}
    local missing = {}
    local localKey = getLocalPlayerKey()
    for _, member in ipairs(addon.GameMasterRoster.GetMembers()) do
        if member.playerKey == localKey then
            compatible[#compatible + 1] = string.format(
                "%s (v%s)",
                member.rpName,
                addon.Constants.ADDON_VERSION
            )
        else
            local peer = addon.GameMasterProtocol.GetPeer(member.playerID)
            if addon.GameMasterProtocol.Supports(member.playerID) then
                compatible[#compatible + 1] = string.format(
                    "%s (v%s)",
                    member.rpName,
                    peer and peer.addonVersion or "?"
                )
            elseif peer then
                incompatible[#incompatible + 1] = string.format(
                    "%s (v%s)",
                    member.rpName,
                    peer.addonVersion or "?"
                )
            else
                missing[#missing + 1] = member.rpName
            end
        end
    end

    addon.Logger.Info(addon.L("GAMEMASTER_COMPATIBILITY_HEADER"))
    addon.Logger.Info(addon.L(
        "GAMEMASTER_COMPATIBILITY_OK",
        #compatible > 0 and table.concat(compatible, ", ") or addon.L("NONE")
    ))
    addon.Logger.Info(addon.L(
        "GAMEMASTER_COMPATIBILITY_INCOMPATIBLE",
        #incompatible > 0 and table.concat(incompatible, ", ") or addon.L("NONE")
    ))
    addon.Logger.Info(addon.L(
        "GAMEMASTER_COMPATIBILITY_MISSING",
        #missing > 0 and table.concat(missing, ", ") or addon.L("NONE")
    ))
    notifyListeners("compatibility")
end

local function scheduleCompatibilityReport(activationID)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(
            addon.Constants.GAMEMASTER_COMPATIBILITY_DELAY,
            function()
                printCompatibilityReport(activationID)
            end
        )
    else
        printCompatibilityReport(activationID)
    end
end

local function suspendLocalSession(sendStop)
    companionDiscovery, companionQueryGate = nil, nil
    pendingRosterRetry = nil
    if not activeGameMaster then
        return
    end
    if sendStop and not testSession then
        addon.GameMasterStore.RecordStoppedActivation(getLocalPlayerKey(), getLocalPlayerKey(),
            activeGameMaster.sessionID, activeGameMaster.activationID)
    end
    if sendStop and not testSession and addon.GameMasterRoster.IsInGroup() then
        local payload = createSessionPayload()
        if payload then
            broadcast("stop", payload, "MEDIUM")
        end
    end
    pendingVisibility = nil
    if addon.GameMasterProtocol.CancelVisibility then addon.GameMasterProtocol.CancelVisibility() end
    activeGameMaster = nil
    testSession = nil
    compatibilityReport = nil
    if addon.GameMasterWindow then
        addon.GameMasterWindow.Hide()
    end
    notifyListeners("stopped")
end

local function clearRemoteSession(message)
    companionReplyGate = nil
    pendingNPCSubmissions = {}
    if not remoteSession then
        return
    end
    remoteSession = nil
    if message then
        notifyPlayer(message)
    end
    notifyListeners("remote")
end

local function validateSessionMessage(payload, sender)
    if type(payload) ~= "table"
        or not isCurrentLeader(sender)
        or not addon.GameMasterProtocol.Supports(sender)
        or not isSafeID(payload.sessionId)
        or not isSafeID(payload.activationId)
    then
        return nil
    end
    if addon.GameMasterStore.IsActivationStopped(getLocalPlayerKey(), sender,
        payload.sessionId, payload.activationId) then return nil end
    local saved = addon.GameMasterStore.GetRuntimeState(getLocalPlayerKey())
    local suspended = saved and saved.status == "suspended" and (saved.localState or saved.remoteState)
    if suspended and suspended.sessionID == payload.sessionId
        and suspended.activationID == payload.activationId
        and addon.GameMasterStore.GetRecoveryDisposition(getLocalPlayerKey(),
            addon.GameMasterRoster.GetMembers(), true) == "confirm" then return nil end
    local sessionName = cleanText(
        payload.sessionName,
        addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH
    )
    local roundNumber = readInteger(
        payload.roundNumber,
        0,
        addon.Constants.MAX_IMPORT_SAFE_INTEGER
    )
    if not sessionName or not roundNumber then
        return nil
    end
    local revision = payload.stateRevision == nil and 0 or readInteger(
        payload.stateRevision, 0, addon.Constants.MAX_IMPORT_SAFE_INTEGER
    )
    if revision == nil then return nil end
    if remoteSession and sessionMatches(payload, remoteSession, true) then
        local observed = math.max(remoteSession.lastStateRevision or 0,
            remoteSession.lastVisibilityRevision or 0)
        local newEpoch = addon.GameMasterStore.GetRevisionEpoch(revision)
            > addon.GameMasterStore.GetRevisionEpoch(observed)
        if ((payload.stateRevision ~= nil or remoteSession.turnTracking) and revision < observed)
            or (roundNumber < remoteSession.roundNumber and not newEpoch) then
            local now = addon.Runtime.GetMonotonicTime()
            if payload.recovering == true and now - lastRecoveryRequestAt >= 5 then
                lastRecoveryRequestAt = now
                addon.GameMasterProtocol.Send(sender, "syncRequest", {
                    sessionId = remoteSession.sessionID, activationId = remoteSession.activationID,
                    observedRevision = observed,
                }, "HIGH")
            end
            return nil
        end
    end
    local roundID = payload.roundId
    if payload.phase ~= nil and payload.phase ~= "players" and payload.phase ~= "enemies" then
        return nil
    end
    if roundNumber > 0 and not isSafeID(roundID) then
        return nil
    end
    return {
        activationID = payload.activationId,
        gameMasterID = sender,
        gameMasterKey = addon.Runtime.NormalizePlayerID(sender),
        locked = payload.locked ~= false,
        roundID = roundNumber > 0 and roundID or nil,
        roundNumber = roundNumber,
        sessionID = payload.sessionId,
        sessionName = sessionName,
        lastStateRevision = revision,
        turnTracking = payload.turnTracking == true,
        phase = payload.phase == "enemies" and "enemies" or "players",
        gmParticipates = payload.gmParticipates ~= false,
        narratorName = addon.GameMasterStore.NormalizeEncounterOptions(payload).narratorName,
        enemyPhases = payload.enemyPhases == true,
        enemyFirst = payload.enemyFirst == true,
        deferEnemyActions = payload.deferEnemyActions ~= false,
        visibility = addon.GameMasterVisibility.Normalize(payload.visibility),
    }
end

local function onSession(payload, sender)
    local state = validateSessionMessage(payload, sender)
    if not state then
        return
    end
    if tutorial then
        if addon.Onboarding then addon.Onboarding.Stop(false) end
        addon.GameMasterService.EndTutorial()
    end
    local previous = remoteSession
    local isNew = not previous
        or previous.activationID ~= state.activationID
        or previous.sessionID ~= state.sessionID
    if isNew and previous then
        addon.GameMasterStore.RecordStoppedActivation(getLocalPlayerKey(), previous.gameMasterKey,
            previous.sessionID, previous.activationID)
    end
    local recovered = not isNew and addon.GameMasterStore.GetRevisionEpoch(state.lastStateRevision)
        > addon.GameMasterStore.GetRevisionEpoch(math.max(previous.lastStateRevision or 0,
            previous.lastVisibilityRevision or 0))
    local sameRound = not isNew and previous.roundID == state.roundID
        and (previous.phase or "players") == state.phase
    local becameLocked = sameRound
        and previous.locked == false
        and state.locked == true
    local becameUnlocked = sameRound
        and previous.locked == true
        and state.locked == false
    if not isNew then
        state.originSequence = previous.originSequence
        state.openWindows = previous.openWindows
    end
    if not isNew and not recovered then
        state.assistantRights = previous.assistantRights
        state.assistantLegacySeen = previous.assistantLegacySeen
        state.assistantStateRevision = previous.assistantStateRevision
        state.controlSession = previous.controlSession
        state.sharedBuffs = previous.sharedBuffs
        state.sharedBuffProfile = previous.sharedBuffProfile
        state.lastVisibilityRevision = previous.lastVisibilityRevision
        if previous.roundID == state.roundID then
            state.incomingActions = previous.incomingActions
            state.incomingRoundID = previous.incomingRoundID
        end
    end
    if sameRound and recovered then
        rebaseRecoveryIntents(previous, state)
    elseif sameRound then
        state.turnSequence = previous.turnSequence
        state.pendingTurn = previous.pendingTurn
        state.lastSubmission = previous.lastSubmission
        state.pendingSubmission = previous.pendingSubmission
        state.originQueue = previous.originQueue
        state.originOutbox = previous.originOutbox
        state.originPeerSerial = previous.originPeerSerial
        state.originReady = previous.originReady
        state.originSyncSerial = previous.originSyncSerial
        state.preparation = previous.preparation
        if previous.visibility == state.visibility then
            state.sharedActions = previous.sharedActions
            state.sharedRoundID = previous.sharedRoundID
        end
    end
    if not sameRound then
        state.originReady = false
        state.originPeerSerial = 0
        state.originSyncSerial = 0
    end
    if not sameRound or recovered then pendingNPCSubmissions = {} end
    remoteSession = state
    if recovered then
        turnHintUntil = 0
        reopenAfterRecovery = true
    end
    if addon.GameMasterPreparation
        and (payload.preparationState == "active"
            or payload.preparationState == "none")
    then
        addon.GameMasterPreparation.Reconcile(
            payload.preparationState == "active" and payload.preparation or false,
            state.sessionID
        )
    end
    if isNew then
        local member = addon.GameMasterRoster.FindMember(sender)
        notifyPlayer(addon.L(
            "GAMEMASTER_SESSION_JOINED",
            state.sessionName,
            member and member.rpName or sender
        ))
    end
    if state.roundID and state.phase == "enemies" and (isNew or not sameRound) then
        notifyPlayer(addon.L("GAMEMASTER_PHASE_ENEMIES"))
    elseif state.roundID and (isNew or not sameRound) then
        notifyPlayer(
            state.locked
            and addon.L("GAMEMASTER_ROUND_LOCKED_NOTICE")
            or addon.L("GAMEMASTER_ROUND_STARTED", state.roundNumber)
        )
    elseif becameLocked then
        notifyPlayer(addon.L("GAMEMASTER_ROUND_LOCKED_NOTICE"))
    elseif becameUnlocked then
        notifyPlayer(addon.L("GAMEMASTER_ROUND_UNLOCKED_NOTICE"))
    end
    notifyListeners("remote")
end

local function validateRoundPayload(payload, sender)
    if not remoteSession
        or not isCurrentLeader(sender)
        or not sessionMatches(payload, remoteSession)
        or not isSafeID(payload.roundId)
    then
        return nil
    end
    if payload.phase ~= nil and payload.phase ~= "players" and payload.phase ~= "enemies" then
        return nil
    end
    local revision = payload.stateRevision == nil and 0 or readInteger(payload.stateRevision,
        0, addon.Constants.MAX_IMPORT_SAFE_INTEGER)
    local observed = math.max(remoteSession.lastStateRevision or 0,
        remoteSession.lastVisibilityRevision or 0)
    if not revision or addon.GameMasterStore.GetRevisionEpoch(revision)
        ~= addon.GameMasterStore.GetRevisionEpoch(observed)
        or (payload.stateRevision ~= nil and revision < observed) then return nil end
    return readInteger(
        payload.roundNumber,
        1,
        addon.Constants.MAX_IMPORT_SAFE_INTEGER
    )
end

local function onRound(payload, sender)
    local number = validateRoundPayload(payload, sender)
    if not number or number <= remoteSession.roundNumber then
        return
    end
    if remoteSession.roundID == payload.roundId then
        return
    end
    remoteSession.roundID = payload.roundId
    pendingNPCSubmissions = {}
    if payload.stateRevision ~= nil then remoteSession.lastStateRevision = tonumber(payload.stateRevision) end
    remoteSession.roundNumber = number
    remoteSession.phase = payload.phase == "enemies" and "enemies" or "players"
    remoteSession.locked = remoteSession.phase == "enemies"
    remoteSession.sharedActions = {}
    remoteSession.sharedRoundID = nil
    remoteSession.lastSubmission = nil
    remoteSession.pendingSubmission = nil
    remoteSession.originQueue = nil
    remoteSession.originOutbox = nil
    remoteSession.pendingTurn = nil
    remoteSession.originReady = false
    remoteSession.originPeerSerial = 0
    remoteSession.originSyncSerial = 0
    turnHintUntil = 0
    notifyPlayer(addon.L(remoteSession.phase == "enemies"
        and "GAMEMASTER_PHASE_ENEMIES" or "GAMEMASTER_ROUND_STARTED", number))
    notifyListeners("round")
end

local function onLock(payload, sender)
    if not remoteSession
        or not isCurrentLeader(sender)
        or not sessionMatches(payload, remoteSession)
        or payload.roundId ~= remoteSession.roundID
    then
        return
    end
    local revision = payload.stateRevision == nil and 0 or readInteger(
        payload.stateRevision, 0, addon.Constants.MAX_IMPORT_SAFE_INTEGER
    )
    if revision == nil or ((payload.stateRevision ~= nil or remoteSession.turnTracking)
        and revision < math.max(remoteSession.lastStateRevision or 0,
            remoteSession.lastVisibilityRevision or 0)) then return end
    remoteSession.lastStateRevision = revision
    if remoteSession.locked then
        return
    end
    remoteSession.locked = true
    notifyPlayer(addon.L("GAMEMASTER_ROUND_LOCKED_NOTICE"))
    notifyListeners("round")
end

local function onStop(payload, sender)
    local saved = addon.GameMasterStore.GetRuntimeState(getLocalPlayerKey())
    local state = remoteSession or (saved and saved.remoteState)
    if not state or not addon.GameMasterRoster.IsMember(sender)
        or addon.Runtime.NormalizePlayerID(sender) ~= state.gameMasterKey
        or not sessionMatches(payload, state, true) then return end
    addon.GameMasterStore.RecordStoppedActivation(getLocalPlayerKey(), sender,
        state.sessionID, state.activationID)
    clearRemoteSession(addon.L("GAMEMASTER_SESSION_STOPPED"))
end

local function sanitizeSpellText(value, flatten)
    if type(value) ~= "string" then
        return value
    end
    value = value:gsub("|", "")
    if flatten then
        value = value:gsub("[%c]", " ")
    else
        value = value:gsub("[%c]", function(character)
            if character == "\n" then
                return "\n"
            end
            return " "
        end)
    end
    return value
end

local function cleanSpellSnapshot(rawSpell)
    if type(rawSpell) ~= "table"
        or not cleanText(
            rawSpell.id,
            addon.Constants.MAX_LINK_SPELL_ID_LENGTH
        )
    then
        return nil
    end
    local revision = tonumber(rawSpell.revision)
    if not revision
        or revision < 1
        or revision > addon.Constants.MAX_LINK_REVISION
        or revision ~= math.floor(revision)
    then
        return nil
    end
    local valid, cleaned = addon.Validators.ValidateSpell(rawSpell)
    if not valid then
        return nil
    end
    cleaned.id = rawSpell.id
    cleaned.revision = revision
    cleaned.ownerKey = cleanText(
        rawSpell.ownerKey,
        addon.Constants.MAX_LINK_OWNER_LENGTH
    )
    if not cleaned.ownerKey then
        return nil
    end
    cleaned.name = sanitizeSpellText(cleaned.name, true)
    if addon.Runtime.Trim(cleaned.name) == "" then
        return nil
    end
    cleaned.resource = sanitizeSpellText(cleaned.resource, true)
    cleaned.range = sanitizeSpellText(cleaned.range, true)
    cleaned.castTime = sanitizeSpellText(cleaned.castTime, true)
    cleaned.cooldown = sanitizeSpellText(cleaned.cooldown, true)
    cleaned.description = sanitizeSpellText(cleaned.description)
    if type(cleaned.tags) == "table" then
        local tags = {}
        for key, value in pairs(cleaned.tags) do
            local cleanKey = sanitizeSpellText(key, true)
            local cleanValue = sanitizeSpellText(value, true)
            if cleanKey ~= "" and cleanValue ~= "" then
                tags[cleanKey] = cleanValue
            end
        end
        cleaned.tags = next(tags) and tags or nil
    end
    return cleaned
end

local function cleanTarget(rawTarget, action)
    if action == "prepare" or rawTarget == nil then
        return nil
    end
    if type(rawTarget) ~= "table"
        or not addon.Constants.GAMEMASTER_TARGET_TYPES[rawTarget.kind]
    then
        return false
    end
    if rawTarget.kind == "marker" then
        local index = tonumber(rawTarget.value)
        if not index
            or index < 1
            or index > 8
            or index ~= math.floor(index)
        then
            return false
        end
        local selectedMarker
        for _, marker in ipairs(
            addon.GameMasterService.GetActionWorldMarkers()
        ) do
            if marker.index == index then
                selectedMarker = marker
                break
            end
        end
        if not selectedMarker then
            return false
        end
        return {
            color = selectedMarker.color,
            health = selectedMarker.health,
            kind = "marker",
            label = selectedMarker.label,
            name = selectedMarker.name,
            raidIcon = selectedMarker.raidIcon,
            value = index,
        }
    end
    if rawTarget.kind == "npc" then
        for _, actor in ipairs(addon.GameMasterService.GetActionNPCs()) do
            if actor.id == rawTarget.value then
                return addon.GameMasterNPCActors.Target(actor)
            end
        end
        return false
    end
    if rawTarget.kind == "player" then
        local member
        local requestedKey = addon.Runtime.NormalizePlayerID(rawTarget.value)
        local members = addon.GameMasterService.GetActionMembers()
        for _, candidate in ipairs(
            members
        ) do
            local candidateKey = addon.Runtime.NormalizePlayerID(candidate.playerID)
            if requestedKey and requestedKey == candidateKey then
                member = candidate
                break
            end
        end
        if not member and requestedKey then
            local requestedName = requestedKey:match("^([^-]+)")
            for _, candidate in ipairs(members) do
                local candidateKey = addon.Runtime.NormalizePlayerID(candidate.playerID)
                local candidateName = candidateKey and candidateKey:match("^([^-]+)")
                if candidateName == requestedName
                    and (not requestedKey:find("-", 1, true)
                        or not candidateKey:find("-", 1, true))
                then
                    if member then
                        return false
                    end
                    member = candidate
                end
            end
        end
        if not member then
            return false
        end
        return {
            color = member.profileColor,
            icon = member.profileIcon,
            kind = "player",
            label = member.rpName or member.gameName or member.playerID,
            value = member.playerID,
        }
    end
    local value = cleanText(
        rawTarget.value,
        addon.Constants.GAMEMASTER_MAX_TARGET_LENGTH
    )
    if not value then
        return false
    end
    return {
        kind = "text",
        label = value,
        value = value,
    }
end

local function getTargetSource(rawTargets, rawTarget, maximum)
    if rawTarget ~= nil and type(rawTarget) ~= "table" then
        return nil
    end
    if rawTargets == nil then
        if rawTarget and maximum < 1 then
            return nil
        end
        return rawTarget and { rawTarget } or {}, rawTarget and 1 or 0
    end
    if type(rawTargets) ~= "table" then
        return nil
    end
    if rawTargets.kind ~= nil then
        if maximum < 1 then
            return nil
        end
        return { rawTargets }, 1
    end

    local count = addon.Runtime.GetBoundedArrayLength(
        rawTargets,
        addon.Constants.GAMEMASTER_MAX_TARGETS
    )
    if not count or count > maximum then
        return nil
    end
    if count == 0 and rawTarget then
        if maximum < 1 then
            return nil
        end
        return { rawTarget }, 1
    end
    return rawTargets, count
end

local function cleanTargets(rawTargets, rawTarget, action, aoe)
    local maximum = action == "prepare"
        and 0
        or (aoe == true and addon.Constants.GAMEMASTER_MAX_TARGETS or 1)
    local source, sourceCount = getTargetSource(
        rawTargets,
        rawTarget,
        maximum
    )
    if not source then
        return nil
    end

    local cleaned = {}
    local seen = {}
    for index = 1, sourceCount do
        local target = cleanTarget(source[index], action)
        if target == false then
            return nil
        end
        if target then
            local key = target.kind .. ":" .. tostring(target.value):lower()
            if not seen[key] then
                seen[key] = true
                cleaned[#cleaned + 1] = target
            end
        end
    end
    return cleaned
end

local function cleanEmote(raw)
    if type(raw) ~= "table" then return nil end
    local channel = cleanText(raw.channel, 40)
    local text = cleanText(
        raw.text,
        addon.Constants.GAMEMASTER_MAX_EMOTE_LENGTH
    )
    local timestamp = readInteger(
        raw.timestamp,
        0,
        addon.Constants.MAX_IMPORT_SAFE_INTEGER
    )
    if not channel or not text or timestamp == nil then return nil end
    return {
        channel = channel,
        text = text,
        timestamp = timestamp,
    }
end
local function cleanPreparation(raw, spell, action)
    if action ~= "prepare" or type(raw) ~= "table" then return nil end
    local required = tonumber(raw.required)
    local castRounds = addon.SpellPresentation.GetCastRounds(spell)
    if not required
        or not castRounds
        or castRounds < 1
        or required ~= castRounds
        or required ~= math.floor(required)
    then
        return nil
    end
    return {
        automated = raw.automated == true,
        required = required,
    }
end

local function rememberTextTargets(sessionID, targets)
    local values = {}
    for _, target in ipairs(targets or {}) do
        if target.kind == "text" then values[#values + 1] = target.value end
    end
    if #values > 0 then
        addon.GameMasterPlayerState.RememberTextTargets(
            sessionID,
            values,
            addon.GameMasterSettings.GetHistoryLimit()
        )
    end
end

local function sendAck(target, payload, status, reason)
    addon.GameMasterProtocol.Send(target, "ack", {
        activationId = payload.activationId,
        stateRevision = getVisibilityRevision(),
        reason = reason or "",
        roundId = payload.roundId,
        sessionId = payload.sessionId,
        submissionId = payload.submissionId,
        status = status,
    }, "HIGH")
end

local function notifyRoundEffectTargets(session, round)
    if not addon.GameMasterEffects
        or type(addon.GameMasterEffects.NotifyRoundTargets) ~= "function"
    then
        return
    end
    local success, errorMessage = addon.Runtime.SafeInvoke(
        addon.GameMasterEffects.NotifyRoundTargets,
        session,
        round
    )
    if not success then
        addon.Logger.Error(tostring(errorMessage))
    end
end

notifyOwnTurn = function()
    local settings = addon.GameMasterSettings
    local now = addon.Runtime.GetMonotonicTime()
    if now < lastOwnNoticeAt then lastOwnNoticeAt = now end
    if type(settings.ShouldNotifyOwnTurn) == "function"
        and settings.ShouldNotifyOwnTurn()
        and now - lastOwnNoticeAt >= 5
    then
        lastOwnNoticeAt = now
        showScreenNotice(addon.L("GAMEMASTER_OWN_TURN"))
    end
    if type(settings.ShouldPlayOwnTurnSound) == "function"
        and settings.ShouldPlayOwnTurnSound()
        and addon.GameMasterTurnSound
    then
        addon.GameMasterTurnSound.Play(nil, "turn")
    end
end

local function onSubmit(payload, sender)
    local session = getSession()
    local round = session and addon.GameMasterStore.GetCurrentRound(session) or nil
    if not activeGameMaster or not isLocalController() then
        return
    end

    local member = addon.GameMasterRoster.FindMember(sender)
    if not member
        or not addon.GameMasterRoster.IsMember(sender)
        or not addon.GameMasterProtocol.Supports(sender)
        or type(payload) ~= "table"
        or not isSafeID(payload.submissionId)
        or payload.sessionId ~= activeGameMaster.sessionID
        or payload.activationId ~= activeGameMaster.activationID
        or payload.roundId ~= (round and round.id)
    then
        return
    end
    if payload.stateRevision == nil
        and addon.GameMasterStore.GetRevisionEpoch(getVisibilityRevision()) > 0
    then
        sendAck(sender, payload, "rejected", "incompatible")
        return
    end
    if not sessionMatches(payload, activeGameMaster) then
        sendAck(sender, payload, "rejected", "invalid")
        return
    end
    local sequence = payload.originSequence ~= nil and readInteger(payload.originSequence,
        1, addon.Constants.MAX_IMPORT_SAFE_INTEGER) or nil
    if (payload.originSequence ~= nil or payload.submissionId:match("^origin_")) and (not sequence
        or payload.submissionId ~= "origin_" .. string.format("%.0f", sequence)) then
        sendAck(sender, payload, "rejected", "invalid")
        return
    end
    if payload.stateRevision == nil and sequence then
        sendAck(sender, payload, "rejected", "incompatible")
        return
    end
    local playerKey = member.playerKey
    if payload.npcActorID ~= nil then
        addon.GameMasterService.ReceiveNPCSubmission(payload, sender, playerKey)
        return
    end
    if not addon.GameMasterStore.CanParticipantSubmit(session, round, playerKey) then
        sendAck(sender, payload, "rejected", "locked")
        sendStateTo(sender, "HIGH")
        return
    end
    local previousSubmission = round and playerKey and round.submissions[playerKey]
    for _, previousAction in ipairs(addon.GameMasterActionCollection.Get(previousSubmission)) do
        if previousAction.submissionId == payload.submissionId then
            sendAck(sender, payload, "accepted")
            sendVisibilityTo(sender, "HIGH")
            return
        end
    end
    local previousSequence = round and type(round.originSubmissionSequences) == "table"
        and round.originSubmissionSequences[playerKey]
    if sequence and previousSequence and sequence <= previousSequence then
         
        sendAck(sender, payload, "rejected", "invalid")
        sendVisibilityTo(sender, "HIGH")
        return
    end
    local fence = round and type(round.participantStateRevisions) == "table"
        and round.participantStateRevisions[playerKey] or 0
    if (tonumber(payload.stateRevision) or 0) < fence
        or (tonumber(payload.stateRevision) or 0) > getVisibilityRevision() then
        sendAck(sender, payload, "rejected", "invalid")
        return
    end
    if not round or round.status ~= "open" then
        sendAck(sender, payload, "rejected", "locked")
        return
    end
    if not addon.Constants.GAMEMASTER_ACTIONS[payload.action] then
        sendAck(sender, payload, "rejected", "invalid")
        return
    end
    local mode = payload.mode == "append" and "append" or "replace"
    if payload.mode ~= nil
        and payload.mode ~= "append"
        and payload.mode ~= "replace"
    then
        sendAck(sender, payload, "rejected", "invalid")
        return
    end

    local spell = cleanSpellSnapshot(payload.spell)
    local targets = spell and cleanTargets(
        payload.targets,
        payload.target,
        payload.action,
        payload.aoe
    ) or nil
    local preparation = spell
        and cleanPreparation(payload.preparation, spell, payload.action)
    local emote = cleanEmote(payload.emote)
    if not spell
        or not targets
        or (payload.action == "prepare" and not preparation)
        or (payload.preparation ~= nil and not preparation)
        or (payload.emote ~= nil and not emote)
    then
        sendAck(sender, payload, "rejected", "invalid")
        return
    end

    local accepted, savedOrError, savedAction
    if playerKey then
        accepted, savedOrError, savedAction =
            addon.GameMasterStore.SaveSubmission(session, playerKey, {
            action = payload.action,
            aoe = payload.aoe == true,
            emote = emote,
            mode = mode,
            playerID = member.playerID,
            preparation = preparation,
            rpName = member.rpName,
            spell = spell,
            submissionId = payload.submissionId,
            target = targets[1],
            targets = targets,
        })
    end
    if not accepted then
        local reason = savedOrError == addon.L("GAMEMASTER_ACTION_LIMIT_REACHED")
            and "limit"
            or "invalid"
        sendAck(sender, payload, "rejected", reason)
        return
    end
    if sequence then
        round.originSubmissionSequences = round.originSubmissionSequences or {}
        round.originSubmissionSequences[playerKey] = sequence
    end
    if payload.action == "prepare" and payload.stateRevision ~= nil then
        activeGameMaster.preparationStateRevisions = activeGameMaster.preparationStateRevisions or {}
        activeGameMaster.preparationStateRevisions[playerKey] =
            math.min(addon.Constants.MAX_IMPORT_SAFE_INTEGER, getVisibilityRevision() + 1)
    end
    sendAck(sender, payload, "accepted")
    broadcastVisibility("HIGH")
    broadcastAssistantStates("HIGH")
    notifyListeners("submission")
end

local function acceptPendingRemoteSubmission(pending, authoritative)
    local queue = getOriginQueue()
    if not queue or queue[1] ~= pending then return false end
    pending.sentAt = nil
    if authoritative then
        remoteSession.lastSubmission = authoritative
    else
        remoteSession.lastSubmission = applyPendingSubmission(
            remoteSession.lastSubmission, pending, true
        )
    end
    table.remove(queue, 1)
    if not syncOriginQueue() then return false end
    rememberTextTargets(remoteSession.sessionID, pending.targets or {})
    if addon.GameMasterPreparation then
        addon.GameMasterPreparation.OnAccepted(
            pending,
            remoteSession.sessionID,
            remoteSession.roundNumber
        )
    end
    if addon.GameMasterActionStatus then addon.GameMasterActionStatus.Open() end
    notifyPlayer(addon.L("GAMEMASTER_SUBMISSION_ACCEPTED"))
    return true
end

local function onAck(payload, sender)
    if type(payload) ~= "table" or not remoteSession
        or addon.Runtime.NormalizePlayerID(sender) ~= remoteSession.gameMasterKey
        or not sessionMatches(payload, remoteSession)
        or payload.roundId ~= remoteSession.roundID
    then
        return
    end
    local pending = getOriginHead()
    if not pending or payload.submissionId ~= pending.id then
        return
    end
    if payload.status == "accepted" then
        if not acceptPendingRemoteSubmission(pending) then return end
        if getOriginHead() then
            remoteSession.originReady = false
            requestLeaderSync()
        end
    elseif payload.status == "rejected" then
        clearOriginQueue()
        local message = addon.L("GAMEMASTER_SUBMISSION_REJECTED")
        if payload.reason == "locked" then
            message = addon.L("GAMEMASTER_ROUND_LOCKED")
        elseif payload.reason == "limit" then
            message = addon.L("GAMEMASTER_ACTION_LIMIT_REACHED")
        elseif payload.reason == "incompatible" then
            local peer = addon.Communication.GetPeer
                and addon.Communication.GetPeer(remoteSession.gameMasterID)
            message = addon.L("GAMEMASTER_COMPATIBILITY_INCOMPATIBLE",
                peer and peer.version or "?")
        end
        notifyPlayer(message)
        if addon.GameMasterPreparation then
            addon.GameMasterPreparation.OnRejected(pending)
        end
    else
        return
    end
    notifyListeners("submission")
end

local function onSyncRequest(payload, sender)
    if activeGameMaster
        and isLocalController()
        and addon.GameMasterRoster.IsMember(sender)
    then
        if activeGameMaster.recovering and sessionMatches(payload, activeGameMaster, true)
            and addon.GameMasterProtocol.Supports(sender)
        then
            local observed = readInteger(payload.observedRevision, 0,
                addon.Constants.MAX_IMPORT_SAFE_INTEGER)
            local session = getSession()
            local key = addon.Runtime.NormalizePlayerID(sender)
            activeGameMaster.recoveryPeers = activeGameMaster.recoveryPeers or {}
            if observed and session and session.participants[key] then
                 
                 
                activeGameMaster.recoveryPeers[key] = true
            end
        end
        sendStateTo(sender)
    elseif not activeGameMaster and type(payload) == "table"
        and isSafeID(payload.sessionId) and isSafeID(payload.activationId)
        and addon.GameMasterRoster.IsMember(sender)
    then
        local session = addon.GameMasterStore.GetSession(payload.sessionId)
        if addon.GameMasterStore.IsActivationStopped(getLocalPlayerKey(), getLocalPlayerKey(),
            payload.sessionId, payload.activationId)
            or (session and session.ownerKey == getLocalPlayerKey()
                and session.lastActivationID == payload.activationId
                and session.runningActivationID ~= payload.activationId)
        then
            addon.GameMasterProtocol.Send(sender, "stop", {
                sessionId = payload.sessionId, activationId = payload.activationId,
            }, "HIGH")
        end
    end
end

local function onTurnComplete(payload, sender)
    local session = getSession()
    local round = session and addon.GameMasterStore.GetCurrentRound(session)
    if not activeGameMaster or not isLocalController()
        or type(payload) ~= "table"
        or not round
        or payload.sessionId ~= activeGameMaster.sessionID
        or payload.activationId ~= activeGameMaster.activationID
        or payload.roundId ~= round.id
        or type(payload.completed) ~= "boolean"
        or (payload.source ~= "manual" and payload.source ~= "emote")
    then
        return
    end
    local member = addon.GameMasterRoster.FindMember(sender)
    if not member or not addon.GameMasterRoster.IsMember(sender)
        or not addon.GameMasterProtocol.Supports(sender) then return end
    local sequence = readInteger(payload.sequence, 1,
        addon.Constants.MAX_IMPORT_SAFE_INTEGER)
    local fence = member and type(round.participantStateRevisions) == "table"
        and round.participantStateRevisions[member.playerKey] or 0
    local revision = payload.stateRevision ~= nil and readInteger(payload.stateRevision,
        0, addon.Constants.MAX_IMPORT_SAFE_INTEGER) or nil
    if not sequence then return end
    if payload.stateRevision == nil then
         
         
        if fence > 0 or addon.GameMasterStore.GetRevisionEpoch(getVisibilityRevision()) > 0 then
            sendVisibilityTo(sender, "MEDIUM")
            return
        end
    elseif not sessionMatches(payload, activeGameMaster)
        or not revision or revision < fence or revision > getVisibilityRevision()
    then
        sendVisibilityTo(sender, "MEDIUM")
        return
    end
    if not addon.GameMasterStore.CanParticipantAct(session, round, member.playerKey)
    then
        return
    end
    if type(round.turnSequences) ~= "table" then round.turnSequences = {} end
    if sequence <= (round.turnSequences[member.playerKey] or 0) then
        sendVisibilityTo(sender, "MEDIUM")
        return
    end
    round.turnSequences[member.playerKey] = sequence
    addon.GameMasterStore.SetTurnCompleted(
        session, member.playerKey, payload.completed, payload.source
    )
    broadcastVisibility("HIGH")
    broadcastAssistantStates("HIGH")
    notifyListeners("turn")
end

local function onPreparationInterrupt(payload, sender)
    if not remoteSession
        or not isCurrentLeader(sender)
        or not sessionMatches(payload, remoteSession)
    then
        return
    end
    local revision = readInteger(payload.stateRevision or 0, 0, addon.Constants.MAX_IMPORT_SAFE_INTEGER)
    if not revision or ((payload.stateRevision ~= nil or remoteSession.turnTracking)
        and revision < getStateRevision(remoteSession)) then return end
    if addon.GameMasterPreparation then
        addon.GameMasterPreparation.Interrupted()
    end
    notifyListeners("preparation")
end

local function onPreparationCancel(payload, sender)
    local session = getSession()
    if not activeGameMaster
        or not session
        or not isLocalController()
        or not sessionMatches(payload, activeGameMaster)
    then
        return
    end
    local member = addon.GameMasterRoster.FindMember(sender)
    if not member or not addon.GameMasterRoster.IsMember(sender) then return end
    local revision = readInteger(payload.stateRevision or 0, 0, getVisibilityRevision())
    local fence = activeGameMaster.preparationStateRevisions
        and activeGameMaster.preparationStateRevisions[member.playerKey] or 0
    local round = getCurrentRound()
    if not revision or revision < fence
        or (payload.roundId ~= nil and payload.roundId ~= (round and round.id)) then
        sendStateTo(sender, "HIGH")
        return
    end
    if member and addon.GameMasterStore.ClearPreparation(
        session,
        member.playerKey
    ) then
        broadcastVisibility("HIGH")
        broadcastAssistantStates("HIGH")
        notifyListeners("preparation")
    end
end

local function onVisibility(payload, sender)
    if not remoteSession
        or not isCurrentLeader(sender)
        or not sessionMatches(payload, remoteSession)
        or type(payload) ~= "table"
        or not addon.Constants.GAMEMASTER_VISIBILITY_MODES[
            payload.visibility
        ]
    then
        return
    end
    local roundNumber = readInteger(
        payload.roundNumber,
        0,
        addon.Constants.MAX_IMPORT_SAFE_INTEGER
    )
    local stateRevision = payload.stateRevision == nil and 0 or readInteger(
        payload.stateRevision,
        0,
        addon.Constants.MAX_IMPORT_SAFE_INTEGER
    )
    if roundNumber == nil
        or stateRevision == nil
        or stateRevision < math.max(remoteSession.lastVisibilityRevision or -1,
            remoteSession.lastStateRevision or -1)
        or roundNumber ~= remoteSession.roundNumber
        or (roundNumber > 0
            and payload.roundId ~= remoteSession.roundID)
    then
        return
    end
    local entries = addon.GameMasterVisibility.ValidateEntries(
        payload.entries,
        payload.visibility
    )
    local controlledNPCs = {}
    if addon.GameMasterNPCActors then
        controlledNPCs = addon.GameMasterNPCActors.ValidateControlUnits(payload.controlledNPCs, getLocalPlayerKey())
    end
    if not controlledNPCs then return end
    local ownEntries = addon.GameMasterVisibility.ValidateEntries(
        payload.ownSubmission or {},
        "full"
    )
    local sharedBuffs = {}
    if addon.GameMasterEffects then sharedBuffs = addon.GameMasterEffects.ValidateSharedBuffStates(payload.buffStates) end
    local incoming = {}
    if addon.GameMasterIncomingActions then
        incoming = addon.GameMasterIncomingActions.Validate(payload.incomingActions or {}, payload.roundId, roundNumber)
    end
    if not entries or not ownEntries or #ownEntries > 1 or not sharedBuffs or not incoming then
        return
    end
    local ownSubmission = ownEntries[1]
    if ownSubmission
        and addon.GameMasterEffects
        and type(addon.GameMasterEffects.PlayerIDsMatch) == "function"
        and not addon.GameMasterEffects.PlayerIDsMatch(
            ownSubmission.playerID,
            getLocalPlayerID()
        )
    then
        return
    end
    local profile = currentReaderProfile()
    if payload.readerProfile ~= nil and (type(payload.readerProfile) ~= "string"
        or #payload.readerProfile > 200 or payload.readerProfile:find("[%c|]")
        or payload.readerProfile ~= profile) then return end
    if payload.phase ~= nil and payload.phase ~= "players" and payload.phase ~= "enemies" then return end
    remoteSession.visibility = payload.visibility
    local phase = payload.phase or remoteSession.phase or "players"
    if phase ~= (remoteSession.phase or "players") then
        clearOriginQueue()
        remoteSession.pendingTurn = nil
        remoteSession.phase = phase
        turnHintUntil = 0
    end
    remoteSession.sharedActions = entries
    remoteSession.controlledNPCs = controlledNPCs
    for actorID, pending in pairs(pendingNPCSubmissions) do
        local actor = controlledNPCs[actorID]
        local resolved = not actor or actor.revision ~= pending.npcRevision
            or pending.sessionId ~= payload.sessionId or pending.activationId ~= payload.activationId
            or pending.roundId ~= payload.roundId or pending.phase ~= phase
        for _, action in ipairs(addon.GameMasterActionCollection.Get(actor and actor.lastSubmission)) do
            if action.submissionId == pending.submissionId then resolved = true end
        end
        if resolved then
            local acknowledged = false
            for _, action in ipairs(addon.GameMasterActionCollection.Get(actor and actor.lastSubmission)) do
                if action.submissionId == pending.submissionId then acknowledged = true end
            end
            pendingNPCSubmissions[actorID] = nil
            if not acknowledged and remoteSession.pendingTurn and remoteSession.pendingTurn.waitingForNPCs then
                remoteSession.pendingTurn = nil
            end
        end
    end
    remoteSession.incomingActions = incoming
    remoteSession.incomingRoundID = payload.roundId
    remoteSession.sharedBuffs = payload.readerProfile and sharedBuffs or publicBuffsOnly(sharedBuffs)
    remoteSession.sharedBuffProfile = payload.readerProfile or profile
    remoteSession.sharedRoundID = remoteSession.roundID
    remoteSession.lastVisibilityRevision = stateRevision
    local pendingTurn = remoteSession.pendingTurn
    local localEntry
    local hasIdentifiedEntry = false
    for _, entry in ipairs(entries) do
        if addon.Runtime.NormalizePlayerID(entry.playerID) then
            hasIdentifiedEntry = true
        end
        if addon.Runtime.NormalizePlayerID(entry.playerID) == getLocalPlayerKey() then
            localEntry = entry
            remoteSession.turnSequence = math.max(
                remoteSession.turnSequence or 0, entry.turnSequence or 0
            )
            if pendingTurn then
                if (entry.turnSequence or 0) >= pendingTurn.sequence
                    or entry.active == false or entry.online == false
                then
                    remoteSession.pendingTurn = nil
                end
            end
            break
        end
    end
    if (hasIdentifiedEntry and not localEntry)
        or (localEntry and (localEntry.active == false or localEntry.online == false))
    then
        remoteSession.pendingTurn = nil
        clearOriginQueue()
    end
    remoteSession.lastSubmission = ownSubmission
        and addon.GameMasterActionCollection.Count(ownSubmission) > 0
        and ownSubmission or nil
    local reconciled = false
    local acceptedIDs = {}
    for _, action in ipairs(addon.GameMasterActionCollection.Get(ownSubmission)) do
        if action.submissionId then acceptedIDs[action.submissionId] = true end
    end
    while getOriginHead() and acceptedIDs[getOriginHead().id] do
        if not acceptPendingRemoteSubmission(getOriginHead(), ownSubmission) then
            break
        end
        reconciled = true
    end
    if reconciled then
        notifyListeners("submission")
    end
    if (localEntry and localEntry.active ~= false and localEntry.online ~= false)
        or not hasIdentifiedEntry
    then
        if remoteSession.originReady ~= true then
            remoteSession.originSyncSerial = (remoteSession.originSyncSerial or 0) + 1
        end
        remoteSession.originReady = true
        if flushOriginOutbox then flushOriginOutbox(stateRevision) end
        if flushPendingTurn then flushPendingTurn(stateRevision) end
    else
        remoteSession.originReady = false
    end
    notifyListeners("visibility")
    if restoreRecoveredWindows then restoreRecoveredWindows() end
end

local function onAssistantState(payload, sender)
    if not hasGameMasterModule() then return end
    if not remoteSession
        or not isCurrentLeader(sender)
        or not addon.GameMasterProtocol.SupportsDelegation(sender)
        or not sessionMatches(payload, remoteSession)
        or type(payload) ~= "table"
    then
        return
    end
    local revision = payload.stateRevision ~= nil and readInteger(payload.stateRevision, 0,
        addon.Constants.MAX_IMPORT_SAFE_INTEGER) or nil
    local legacy = payload.stateRevision == nil
    if legacy then
        if payload.authorized == true and remoteSession.assistantLegacySeen then return end
    elseif not revision
        or addon.GameMasterStore.GetRevisionEpoch(revision)
            ~= addon.GameMasterStore.GetRevisionEpoch(getStateRevision(remoteSession))
        or revision <= (remoteSession.assistantStateRevision or -1)
    then
        return
    end
    local wasAssistant =
        type(remoteSession.assistantRights) == "table"
    if payload.authorized ~= true then
        remoteSession.assistantLegacySeen = true
        if revision then
            remoteSession.assistantStateRevision = revision
        end
        remoteSession.assistantRights = nil
        remoteSession.controlSession = nil
        if wasAssistant then
            notifyPlayer(addon.L("GAMEMASTER_ASSISTANT_REVOKED"))
            notifyListeners("assistant")
        end
        return
    end
    local control = addon.GameMasterDelegation.ValidateControlState(
        payload.control
    )
    if not control
        or control.id ~= remoteSession.sessionID
        or (control.ownerKey and control.ownerKey ~= remoteSession.gameMasterKey)
    then
        return
    end
    remoteSession.assistantLegacySeen = true
    if revision then
        remoteSession.assistantStateRevision = revision
    end
    remoteSession.assistantRights = addon.GameMasterDelegation
        .NormalizeRights(payload.rights)
    remoteSession.controlSession = control
    if not wasAssistant then
        notifyPlayer(addon.L("GAMEMASTER_ASSISTANT_AUTHORIZED"))
    end
    notifyListeners("assistant")
    if not wasAssistant and addon.GameMasterWindow
        and addon.GameMasterSettings.ShouldAutoOpenWindow(
            "gameMaster"
        )
    then
        addon.GameMasterWindow.Open()
    end
end

local function sendAssistantCommand(command, arguments)
    local right = addon.GameMasterDelegation.GetRightForCommand(command)
    if not remoteSession
        or not right
        or not addon.GameMasterDelegation.HasRight(
            remoteSession.assistantRights,
            right
        )
        or not addon.GameMasterProtocol.SupportsDelegation(
            remoteSession.gameMasterID
        )
        or not isCurrentLeader(remoteSession.gameMasterID)
    then
        return false, addon.L("GAMEMASTER_ASSISTANT_RIGHT_REQUIRED")
    end
    return addon.GameMasterProtocol.Send(
        remoteSession.gameMasterID,
        "assistantCommand",
        {
            roundId = remoteSession.roundID or "",
            phase = remoteSession.phase or "players",
            activationId = remoteSession.activationID,
            stateRevision = getStateRevision(remoteSession),
            arguments = type(arguments) == "table" and arguments or {},
            command = command,
            sessionId = remoteSession.sessionID,
            visibility = remoteSession.visibility,
        },
        "HIGH"
    )
end

local function onAssistantCommand(payload, sender)
    if not activeGameMaster
        or not isLocalController()
        or not addon.GameMasterRoster.IsMember(sender)
        or not addon.GameMasterProtocol.SupportsDelegation(sender)
        or not sessionMatches(payload, activeGameMaster)
        or type(payload) ~= "table"
        or type(payload.command) ~= "string"
    then
        return
    end
    local revision = readInteger(payload.stateRevision or 0, 0, getVisibilityRevision())
    local fence = activeGameMaster.assistantAuthorityRevisions
        and activeGameMaster.assistantAuthorityRevisions[addon.Runtime.NormalizePlayerID(sender)] or 0
    if not revision or revision < fence then return end
    local right = addon.GameMasterDelegation.GetRightForCommand(
        payload.command
    )
    local assistant = getAssistant(sender)
    if not right
        or not addon.GameMasterDelegation.HasRight(assistant, right)
    then
        return
    end
    local currentRound = getCurrentRound()
    if payload.command ~= "cycleVisibility"
        and (payload.phase or "players") ~= addon.GameMasterStore.GetPhase(getSession()) then
        return
    end
    if payload.command ~= "cycleVisibility"
        and payload.roundId
            ~= (currentRound and currentRound.id or "")
    then
        return
    end
    local arguments = type(payload.arguments) == "table"
        and payload.arguments
        or {}
    if payload.command == "cycleVisibility"
        and payload.visibility ~= activeGameMaster.visibility
    then
        return
    end
    if payload.command == "startRound" then
        addon.GameMasterService.StartRound()
    elseif payload.command == "lockRound" then
        addon.GameMasterService.LockRound()
    elseif payload.command == "unlockRound" then
        addon.GameMasterService.UnlockRound()
    elseif payload.command == "cycleVisibility" then
        addon.GameMasterService.CycleVisibility()
    elseif payload.command == "setParticipantActive" then
        addon.GameMasterService.SetParticipantActive(
            arguments.playerKey,
            arguments.active == true
        )
    elseif payload.command == "moveParticipant" then
        local direction = tonumber(arguments.direction)
        if direction == -1 or direction == 1 then
            local moved = addon.GameMasterStore.MoveParticipant(
                getSession(),
                arguments.playerKey,
                direction
            )
            if moved then
                broadcastVisibility("HIGH")
                broadcastAssistantStates("HIGH")
                notifyListeners("order")
            end
        end
    elseif payload.command == "interruptPreparation" then
        addon.GameMasterService.InterruptPreparation(arguments.playerKey)
    elseif payload.command == "removeBuff" then
        addon.GameMasterService.RemoveBuff(
            arguments.playerKey,
            arguments.sourcePlayerKey,
            arguments.spellID
        )
    end
end

requestLeaderSync = function()
    local leader = remoteSession
        and addon.GameMasterRoster.FindMember(remoteSession.gameMasterID)
        or (not remoteSession and addon.GameMasterRoster.GetLeader())
    if not leader or leader.playerKey == getLocalPlayerKey() then
        return
    end
    local now = addon.Runtime.GetMonotonicTime()
    if now - lastSyncRequestAt < 5 then
        local state = remoteSession
        local pending = state and (state.pendingSubmission or state.pendingTurn)
        if pending and not state.originSyncScheduled
            and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            state.originSyncScheduled = true
            local dueAt = lastSyncRequestAt + 5
            C_Timer.After(dueAt - now, function()
                state.originSyncScheduled = nil
                if remoteSession == state
                    and (state.pendingSubmission == pending or state.pendingTurn == pending)
                    and addon.Runtime.GetMonotonicTime() >= dueAt then
                    requestLeaderSync()
                end
            end)
        end
        return
    end
    if addon.GameMasterProtocol.Supports(leader.playerID) then
         
        lastSyncRequestAt = now
        addon.GameMasterProtocol.Send(
            leader.playerID,
            "syncRequest",
            remoteSession and {
                sessionId = remoteSession.sessionID,
                activationId = remoteSession.activationID,
                observedRevision = math.max(remoteSession.lastStateRevision or 0,
                    remoteSession.lastVisibilityRevision or 0),
            } or {},
            "LOW"
        )
    else
        addon.GameMasterProtocol.Query(leader.playerID)
    end
end

local function onPeerUpdated(peer)
    if tutorial then return end
    if type(peer) ~= "table" or not peer.playerID then
        return
    end
    if companionDiscovery then
        local key = addon.Runtime.NormalizePlayerID(peer.playerID)
        if key then companionDiscovery.pending[key], companionDiscovery.reports[key] = nil, nil end
    end
    companionReplyGate = nil
    if activeGameMaster
        and isLocalController()
        and addon.GameMasterRoster.IsMember(peer.playerID)
        and addon.GameMasterProtocol.Supports(peer.playerID)
    then
        sendStateTo(peer.playerID)
        notifyListeners("compatibility")
        return
    end
    if not activeGameMaster then
        local leader = remoteSession
            and addon.GameMasterRoster.FindMember(remoteSession.gameMasterID)
            or (not remoteSession and addon.GameMasterRoster.GetLeader())
        if leader
            and leader.playerKey == addon.Runtime.NormalizePlayerID(peer.playerID)
            and addon.GameMasterProtocol.Supports(peer.playerID)
        then
            if remoteSession and (remoteSession.pendingSubmission
                or remoteSession.pendingTurn) then
                remoteSession.originPeerSerial = (remoteSession.originPeerSerial or 0) + 1
                remoteSession.originReady = false
                local pending = getOriginHead()
                if pending then
                    pending.waitingForSync = true
                    pending.sentAt = nil
                end
                if remoteSession.pendingTurn then
                    remoteSession.pendingTurn.waitingForSync = true
                    remoteSession.pendingTurn.sentAt = nil
                end
            end
            requestLeaderSync()
        end
    end
end

local function restoreRuntimeState()
    if restoredRuntime then return end
    local playerKey = getLocalPlayerKey()
    if not playerKey then return end
    local saved = addon.GameMasterStore.GetRuntimeState(playerKey)
    if not saved then restoredRuntime = true; return end
    if saved.localState and not hasGameMasterModule() then
         
         
        addon.GameMasterStore.SuspendRuntimeState(playerKey, "missing")
        restoredRuntime = true
        return
    end
    local members, grouped = addon.GameMasterRoster.GetMembers(), addon.GameMasterRoster.IsInGroup()
    if addon.GameMasterRoster.IsAvailable and not addon.GameMasterRoster.IsAvailable() then return end
    local disposition = addon.GameMasterStore.GetRecoveryDisposition(playerKey, members, grouped, true)
    if disposition ~= "live" then
        addon.GameMasterStore.SuspendRuntimeState(playerKey,
            disposition == "confirm" and "unrelated" or "missing")
        restoredRuntime = disposition == "confirm"
        return
    end
    restoredRuntime = true
    local localState = saved.localState
    if type(localState) == "table" and isSafeID(localState.sessionID)
        and isSafeID(localState.activationID)
    then
        local session = addon.GameMasterStore.GetSession(localState.sessionID)
        if session and session.ownerKey == playerKey
            and not addon.GameMasterStore.IsActivationStopped(playerKey, playerKey,
                localState.sessionID, localState.activationID) then
            activeGameMaster = {
                sessionID = session.id,
                activationID = localState.activationID,
                visibility = addon.GameMasterVisibility.Normalize(localState.visibility),
                visibilityRevision = readInteger(localState.visibilityRevision, 0,
                    addon.Constants.MAX_IMPORT_SAFE_INTEGER) or 0,
                assistants = addon.GameMasterSceneAccess.ToAssistantMap(
                    addon.GameMasterStore.GetSceneAccess(session), session.ownerKey
                ),
                openWindows = normalizeOpenWindows(localState.openWindows),
            }
            activeGameMaster.visibilityRevision = math.max(activeGameMaster.visibilityRevision,
                readInteger(session.recoveryRevision, 0, addon.Constants.MAX_IMPORT_SAFE_INTEGER) or 0)
            if not addon.GameMasterStore.BeginRecovery(activeGameMaster) then
                activeGameMaster = nil
                addon.GameMasterStore.SuspendRuntimeState(playerKey, "unrelated")
                return
            end
            session.runningActivationID = activeGameMaster.activationID
            session.lastActivationID = activeGameMaster.activationID
            reopenAfterRecovery = true
        end
        return
    end
    local state = saved.remoteState
    local roundNumber = type(state) == "table" and readInteger(
        state.roundNumber, 0, addon.Constants.MAX_IMPORT_SAFE_INTEGER
    ) or nil
    if type(state) ~= "table" or not isSafeID(state.sessionID)
        or not isSafeID(state.activationID)
        or not cleanText(state.sessionName, addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH)
        or not cleanText(state.gameMasterID, addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH)
        or not roundNumber
        or (roundNumber > 0 and not isSafeID(state.roundID))
    then
        return
    end
    if addon.GameMasterStore.IsActivationStopped(playerKey, state.gameMasterID,
        state.sessionID, state.activationID) then return end
    local entries = addon.GameMasterVisibility.ValidateEntries(
        state.sharedActions or {}, state.visibility
    )
    local buffs = {}
    if addon.GameMasterEffects then buffs = addon.GameMasterEffects.ValidateSharedBuffStates(state.sharedBuffs or {}) end
    if not entries or not buffs then return end
    remoteSession = {
        sessionID = state.sessionID, activationID = state.activationID,
        sessionName = state.sessionName, gameMasterID = state.gameMasterID,
        gameMasterKey = addon.Runtime.NormalizePlayerID(state.gameMasterID),
        roundID = state.roundID, roundNumber = roundNumber,
        phase = state.phase == "enemies" and "enemies" or "players",
        gmParticipates = state.gmParticipates ~= false,
        narratorName = addon.GameMasterStore.NormalizeEncounterOptions(state).narratorName,
        enemyPhases = state.enemyPhases == true,
        enemyFirst = state.enemyFirst == true,
        deferEnemyActions = state.deferEnemyActions ~= false,
        incomingActions = state.incomingActions or {},
        incomingRoundID = state.incomingRoundID,
        locked = state.locked ~= false,
        visibility = addon.GameMasterVisibility.Normalize(state.visibility),
        sharedActions = entries,
        sharedBuffs = state.sharedBuffProfile and state.sharedBuffProfile == currentReaderProfile()
            and buffs or publicBuffsOnly(buffs),
        sharedBuffProfile = state.sharedBuffProfile,
        sharedRoundID = state.sharedRoundID == state.roundID and state.roundID or nil,
        lastVisibilityRevision = readInteger(state.lastVisibilityRevision, 0,
            addon.Constants.MAX_IMPORT_SAFE_INTEGER) or 0,
        lastStateRevision = readInteger(state.lastStateRevision, 0,
            addon.Constants.MAX_IMPORT_SAFE_INTEGER) or 0,
        turnTracking = state.turnTracking == true,
        turnSequence = readInteger(state.turnSequence, 0,
            addon.Constants.MAX_IMPORT_SAFE_INTEGER) or 0,
        openWindows = normalizeOpenWindows(state.openWindows),
        originSequence = readInteger(state.originSequence, 0,
            addon.Constants.MAX_IMPORT_SAFE_INTEGER) or 0,
        originReady = false,
        originPeerSerial = 0,
        originSyncSerial = 0,
    }
    local own = state.lastSubmission and addon.GameMasterVisibility.ValidateEntries(
        { state.lastSubmission }, "full"
    )
    if own and own[1]
        and addon.Runtime.NormalizePlayerID(own[1].playerID) == playerKey
    then
        remoteSession.lastSubmission = own[1]
    end
    restoreOriginOutbox(state.originOutbox)
     
    if type(state.pendingTurn) == "table"
        and sessionMatches(state.pendingTurn, remoteSession)
        and state.pendingTurn.roundId == remoteSession.roundID
        and type(state.pendingTurn.completed) == "boolean"
        and readInteger(state.pendingTurn.sequence, 1,
            addon.Constants.MAX_IMPORT_SAFE_INTEGER)
    then
        remoteSession.pendingTurn = {
            sessionId = remoteSession.sessionID, activationId = remoteSession.activationID,
            stateRevision = readInteger(state.pendingTurn.stateRevision, 0,
                addon.Constants.MAX_IMPORT_SAFE_INTEGER) or 0,
            roundId = remoteSession.roundID, completed = state.pendingTurn.completed,
            sequence = tonumber(state.pendingTurn.sequence),
            source = state.pendingTurn.source == "emote" and "emote" or "manual",
            waitingForSync = true,
            retryAttempts = 0,
        }
    end
    reopenAfterRecovery = true
end

function addon.GameMasterService.RestoreOpenWindows()
    if not addon.GameMasterService.IsSessionActive() then return false end
    local windows = {
        compactSpellbook = addon.GameMasterCompactSpellbook,
        roundOverview = addon.GameMasterSharedActions,
        currentAction = addon.GameMasterActionStatus,
    }
    if addon.GameMasterService.IsActiveGameMaster() then
        windows.gameMaster = addon.GameMasterWindow
    end
    local state = activeGameMaster or remoteSession
    local remembered = state and normalizeOpenWindows(state.openWindows) or nil
    for moduleID, window in pairs(windows) do
        local shouldOpen = remembered ~= nil
            and remembered[moduleID] == true
            or (remembered == nil
                and addon.GameMasterSettings.ShouldAutoOpenWindow(moduleID))
        if moduleID == "gameMaster" and addon.GameMasterService.IsActiveGameMaster() then
            shouldOpen = true
        elseif moduleID == "roundOverview"
            and not addon.GameMasterService.IsActiveGameMaster()
        then
            shouldOpen = true
        end
        if shouldOpen and type(window) == "table"
            and type(window.Open) == "function"
        then
            local restoreWindow = moduleID == "currentAction"
                or (moduleID == "roundOverview" and remembered ~= nil and remembered[moduleID] == true)
            addon.Runtime.SafeInvoke(window.Open, restoreWindow)
        elseif remembered ~= nil and type(window) == "table"
            and type(window.Hide) == "function"
        then
            addon.Runtime.SafeInvoke(window.Hide)
        end
    end
    return true
end

restoreRecoveredWindows = function()
    if not reopenAfterRecovery
        or not addon.GameMasterService.IsSessionActive()
    then
        return false
    end
    reopenAfterRecovery = false
    addon.GameMasterService.RestoreOpenWindows()
    notifyListeners("restored")
    return true
end

local function onRosterChanged()
    companionDiscovery, companionQueryGate, companionReplyGate = nil, nil, nil
    if tutorial then return end
    if not testSession and addon.GameMasterRoster.IsAvailable then
        addon.GameMasterRoster.GetMembers()
        addon.GameMasterRoster.IsInGroup()
        if not addon.GameMasterRoster.IsAvailable() then
            local recovering = not restoredRuntime and addon.GameMasterStore.GetRuntimeState(getLocalPlayerKey())
            if not pendingRosterRetry and (activeGameMaster or remoteSession or recovering)
                and C_Timer and C_Timer.After then
                local token, synchronous = {}, true
                pendingRosterRetry = token
                C_Timer.After(1, function()
                    if pendingRosterRetry ~= token then return end
                    pendingRosterRetry = nil
                    if not synchronous then onRosterChanged() end
                end)
                synchronous = false
            end
            return
        end
    end
    pendingRosterRetry = nil
    pendingVisibility = nil
    if addon.GameMasterProtocol.CancelVisibility then addon.GameMasterProtocol.CancelVisibility() end
    restoreRuntimeState()
    if testSession then
        notifyListeners("roster")
        return
    end
    if activeGameMaster or remoteSession then
        local gm = remoteSession and addon.GameMasterRoster.FindMember(remoteSession.gameMasterID)
        if remoteSession and (not gm or gm.online == false) then
            remoteSession.originPeerOffline = true
            remoteSession.originReady = false
            local pending = getOriginHead()
            if pending then
                pending.waitingForSync = true
                pending.sentAt = nil
            end
            if remoteSession.pendingTurn then
                remoteSession.pendingTurn.waitingForSync = true
                remoteSession.pendingTurn.sentAt = nil
            end
        elseif remoteSession and remoteSession.originPeerOffline then
            remoteSession.originPeerOffline = nil
            remoteSession.originPeerSerial = (remoteSession.originPeerSerial or 0) + 1
            remoteSession.originReady = false
        end
        local disposition = addon.GameMasterStore.GetRecoveryDisposition(getLocalPlayerKey(),
            addon.GameMasterRoster.GetMembers(), addon.GameMasterRoster.IsInGroup())
        if disposition == "waiting" or disposition == "confirm" then
            addon.GameMasterStore.SuspendRuntimeState(getLocalPlayerKey(),
                disposition == "confirm" and "unrelated" or "missing")
            activeGameMaster, remoteSession, compatibilityReport = nil, nil, nil
            restoredRuntime = disposition == "confirm"
            reopenAfterRecovery = false
            notifyListeners("suspended")
        end
    end
    if activeGameMaster and isLocalController() then
        updateStoredRoster()
        broadcastCurrentState("MEDIUM")
    end

    if not activeGameMaster and addon.GameMasterRoster.IsInGroup() then
        requestLeaderSync()
        if remoteSession and remoteSession.originReady and flushOriginOutbox then
            flushOriginOutbox(remoteSession.lastVisibilityRevision)
            if flushPendingTurn then
                flushPendingTurn(remoteSession.lastVisibilityRevision)
            end
        end
    end
    if not restoreRecoveredWindows() then
        notifyListeners("roster")
    end
end

local function initializeEventFrame()
    if eventFrame or type(CreateFrame) ~= "function" then
        return
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("UNIT_CONNECTION")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")
    eventFrame:RegisterEvent("GROUP_LEFT")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "GROUP_LEFT" and not testSession then
            companionDiscovery, companionQueryGate, companionReplyGate = nil, nil, nil
            pendingRosterRetry = nil
            pendingVisibility = nil
            if addon.GameMasterProtocol.CancelVisibility then addon.GameMasterProtocol.CancelVisibility() end
            addon.GameMasterStore.SuspendRuntimeState(getLocalPlayerKey(), "left")
            activeGameMaster, remoteSession, compatibilityReport = nil, nil, nil
            restoredRuntime, reopenAfterRecovery = true, false
            notifyListeners("suspended")
        elseif event == "PLAYER_LOGOUT" then
            if not testSession then
                checkpointOpenWindows()
                addon.GameMasterStore.SaveRuntimeState(
                    getLocalPlayerKey(), activeGameMaster, remoteSession
                )
            end
        else
            if (event == "UNIT_CONNECTION" or event == "PLAYER_REGEN_ENABLED") and addon.GameMasterRoster.InvalidateCache then
                addon.GameMasterRoster.InvalidateCache()
            end
            onRosterChanged()
        end
    end)
end

function addon.GameMasterService.Initialize()
    if addon.GameMasterService.initialized then
        return true
    end
    local protocolSuccess, protocolError = addon.GameMasterProtocol.Initialize()
    if not protocolSuccess then
        return false, protocolError
    end

    local function register(event, callback)
        addon.GameMasterProtocol.RegisterHandler(event, function(...)
            if not tutorial or event == "session" then return callback(...) end
        end)
    end
    register("session", onSession)
    register("round", onRound)
    register("lock", onLock)
    register("stop", onStop)
    register("submit", onSubmit)
    register("npcAck", function(payload, sender) addon.GameMasterService.ReceiveNPCAck(payload, sender) end)
    register("companionRequest", function(payload, sender) addon.GameMasterService.ReceiveCompanionRequest(payload, sender) end)
    register("companionReply", function(payload, sender) addon.GameMasterService.ReceiveCompanionReply(payload, sender) end)
    register("ack", onAck)
    register("syncRequest", onSyncRequest)
    register("preparationInterrupt", onPreparationInterrupt)
    register("preparationCancel", onPreparationCancel)
    addon.GameMasterProtocol.RegisterPeerListener(onPeerUpdated)
    initializeEventFrame()
    register("assistantState", onAssistantState)
    register("assistantCommand", onAssistantCommand)
    register("visibility", onVisibility)
    register("turnComplete", onTurnComplete)
    addon.GameMasterService.initialized = true
    if addon.GameMasterActionStatus and addon.GameMasterActionStatus.SetTurnCompletedHandler then
        addon.GameMasterActionStatus.SetTurnCompletedHandler(function(completed)
            return addon.GameMasterService.SetOwnTurnCompleted(completed)
        end)
    end
    restoreRuntimeState()
    if addon.GameMasterDelayedSubmission
        and addon.GameMasterDelayedSubmission.Initialize
    then
        addon.GameMasterDelayedSubmission.Initialize()
    end

    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(1, onRosterChanged)
    else
        onRosterChanged()
    end
    return true
end

function addon.GameMasterService.RegisterListener(listener)
    if type(listener) ~= "function" then
        return false
    end
    listeners[#listeners + 1] = listener
    return true
end

function addon.GameMasterService.CanControl()
    if tutorial then return tutorial.role == "gm" end
    return addon.GameMasterService.initialized
        and isLocalController()
end

function addon.GameMasterService.GetSuspendedRecovery()
    local saved = addon.GameMasterStore.GetRuntimeState(getLocalPlayerKey())
    if not saved or saved.status ~= "suspended" then return nil end
    local state = saved.localState or saved.remoteState
    local session = saved.localState and addon.GameMasterStore.GetSession(state.sessionID)
    return { sessionID = state.sessionID, activationID = state.activationID,
        sessionName = session and session.name or state.sessionName, localOwner = saved.localState ~= nil,
        reason = saved.suspendReason }
end

function addon.GameMasterService.ResumeRecovery()
    local saved = addon.GameMasterStore.GetRuntimeState(getLocalPlayerKey())
    if not saved or saved.status ~= "suspended" or activeGameMaster or remoteSession
        or not addon.GameMasterRoster.IsInGroup() then return false end
    if saved.localState then
        if not hasGameMasterModule() then return false end
        local session = addon.GameMasterStore.GetSession(saved.localState.sessionID)
        if not session or session.ownerKey ~= getLocalPlayerKey() then return false end
    end
    if saved.remoteState and not addon.GameMasterRoster.IsMember(saved.remoteState.gameMasterID) then return false end
    if not addon.GameMasterStore.ConfirmRuntimeRecovery(getLocalPlayerKey(),
        addon.GameMasterRoster.GetMembers()) then return false end
    restoredRuntime, lastSyncRequestAt = false, -math.huge
    onRosterChanged()
    return addon.GameMasterService.IsSessionActive()
end

function addon.GameMasterService.DiscardRecovery()
    if activeGameMaster or remoteSession then return false end
    local saved = addon.GameMasterStore.GetRuntimeState(getLocalPlayerKey())
    local state = saved and (saved.localState or saved.remoteState)
    if state then
        addon.GameMasterStore.RecordStoppedActivation(getLocalPlayerKey(),
            saved.localState and getLocalPlayerKey() or state.gameMasterKey,
            state.sessionID, state.activationID)
    end
    local cleared = addon.GameMasterStore.ClearRuntimeState(getLocalPlayerKey())
    restoredRuntime = true
    notifyListeners("recoveryDiscarded")
    return cleared
end

function addon.GameMasterService.IsPrimaryGameMaster()
    if tutorial and tutorial.role == "player" then return false end
    return activeGameMaster ~= nil
        and isLocalController()
end

function addon.GameMasterService.IsTestMode()
    return testSession ~= nil
end

function addon.GameMasterService.IsTutorialActive() return tutorial ~= nil end
function addon.GameMasterService.GetTutorialState() return tutorial end
function addon.GameMasterService.GetActionSpellbook()
    return tutorial and tutorial.book or addon.Database.GetActiveSpellbook()
end

function addon.GameMasterService.IsActionSpellFavorite(spellID)
    if tutorial then return tutorial.book.favorites and tutorial.book.favorites[spellID] == true or false end
    return addon.Database.IsSpellFavorite(spellID)
end

function addon.GameMasterService.ToggleActionSpellFavorite(spellID)
    if not tutorial then return addon.Database.ToggleSpellFavorite(spellID) end
    if not tutorial.book.spells[spellID] then return false end
    tutorial.book.favorites = tutorial.book.favorites or {}
    tutorial.book.favorites[spellID] = not tutorial.book.favorites[spellID] or nil
    return true
end

function addon.GameMasterService.BeginTutorial(role, book)
    if not addon.GameMasterService.initialized or tutorial or activeGameMaster or remoteSession or testSession
        or (role ~= "player" and role ~= "gm") or type(book) ~= "table"
        or (role == "gm" and not hasGameMasterModule()) then return false end
    tutorial = { role = role, book = book, finished = false }
    if role == "player" then
        local ok = addon.GameMasterService.StartTestMode(4, { gmParticipates = true, enemyPhases = false })
        if not ok then tutorial = nil; return false end
        testSession.name = addon.L("TUTORIAL_SCENE_NAME")
        if not addon.GameMasterService.StartRound() then addon.GameMasterService.EndTutorial(); return false end
    end
    return true
end

function addon.GameMasterService.TickTutorial(paused)
    if not tutorial or not testSession or tutorial.finished then return end
    local clock = addon.Runtime.GetMonotonicTime()
    if paused then testSession.tutorialDue = clock + 2; return end
    if addon.GameMasterTestMode.TickTutorial(testSession, addon.GameMasterStore.GetCurrentRound(testSession), clock) then
        advanceVisibilityRevision()
        notifyListeners("submission")
    end
end

function addon.GameMasterService.SetTutorialPerspective(role)
    if not tutorial or not testSession or (role ~= "gm" and role ~= "player") then return false end
    if role == "gm" and not hasGameMasterModule() then return false end
    tutorial.role, testSession.tutorialRole = role, role
    if role == "player" and addon.GameMasterWindow then addon.GameMasterWindow.Hide() end
    notifyListeners("remote")
    return true
end

function addon.GameMasterService.EndTutorial()
    if not tutorial then return end
     
     
    activeGameMaster, testSession = nil, nil
    if addon.GameMasterDelayedSubmission and addon.GameMasterDelayedSubmission.Cancel then
        addon.GameMasterDelayedSubmission.Cancel()
    end
    notifyListeners("stopped")
    tutorial = nil
end

function addon.GameMasterService.IsAssistantGameMaster()
    return hasGameMasterModule() and remoteSession ~= nil
        and type(remoteSession.assistantRights) == "table"
        and addon.GameMasterRoster.IsInGroup()
        and isCurrentLeader(remoteSession.gameMasterID)
end

function addon.GameMasterService.IsActiveGameMaster()
    return addon.GameMasterService.IsPrimaryGameMaster()
        or addon.GameMasterService.IsAssistantGameMaster()
end

function addon.GameMasterService.IsSessionActive()
    if tutorial then return testSession ~= nil end
    if addon.GameMasterService.IsPrimaryGameMaster() then
        return activeGameMaster ~= nil
    end
    return type(remoteSession) == "table"
        and addon.GameMasterRoster.IsInGroup()
end

function addon.GameMasterService.GetActiveSession()
    if addon.GameMasterService.IsAssistantGameMaster() then
        return remoteSession.controlSession
    end
    return getSession()
end

function addon.GameMasterService.GetActiveRound()
    local session = addon.GameMasterService.GetActiveSession()
    return session
        and addon.GameMasterStore.GetCurrentRound(session)
        or nil
end

function addon.GameMasterService.GetRemoteSession()
    return remoteSession
end

function addon.GameMasterService.HasControlRight(right)
    if addon.GameMasterService.IsPrimaryGameMaster() then
        return true
    end
    return addon.GameMasterService.IsAssistantGameMaster()
        and addon.GameMasterDelegation.HasRight(
            remoteSession.assistantRights,
            right
        )
end

function addon.GameMasterService.GetAssistantRights(playerKey)
    if addon.GameMasterService.IsPrimaryGameMaster() then
        local assigned = activeGameMaster.assistants
            and activeGameMaster.assistants[playerKey]
        return assigned and addon.GameMasterDelegation
            .NormalizeRights(assigned) or nil
    end
    if playerKey == getLocalPlayerKey()
        and addon.GameMasterService.IsAssistantGameMaster()
    then
        return addon.GameMasterDelegation.NormalizeRights(
            remoteSession.assistantRights
        )
    end
    return nil
end

function addon.GameMasterService.SetAssistant(playerKey, enabled, assigned)
    if not addon.GameMasterService.IsPrimaryGameMaster() then
        return false, addon.L("GAMEMASTER_PRIMARY_ONLY")
    end
    local member
    if testSession then
        local normalizedKey = addon.Runtime.NormalizePlayerID(playerKey)
        for _, candidate in ipairs(
            addon.GameMasterTestMode.GetMembers(testSession)
        ) do
            if candidate.playerKey == normalizedKey then
                member = candidate
                break
            end
        end
    else
        member = addon.GameMasterRoster.FindMember(playerKey)
    end
    if not member or member.playerKey == getLocalPlayerKey() then
        return false, addon.L("GAMEMASTER_ASSISTANT_INVALID")
    end
    if enabled == true
        and not testSession
        and not addon.GameMasterProtocol.SupportsDelegation(member.playerID)
    then
        return false, addon.L("GAMEMASTER_ASSISTANT_INCOMPATIBLE")
    end
    activeGameMaster.assistants =
        type(activeGameMaster.assistants) == "table"
            and activeGameMaster.assistants
            or {}
    local authorityChanged = activeGameMaster.assistants[member.playerKey] ~= nil
        or (activeGameMaster.assistantAuthorityRevisions
            and activeGameMaster.assistantAuthorityRevisions[member.playerKey] ~= nil)
    if enabled == true
        and activeGameMaster.assistants[member.playerKey] == nil
        and addon.Runtime.CountEntries(activeGameMaster.assistants)
            >= addon.Constants.GAMEMASTER_MAX_ASSISTANTS
    then
        return false, addon.L("GAMEMASTER_ASSISTANT_LIMIT")
    end

    if enabled == true then
        local source = type(assigned) == "table" and assigned or {
            participants = true,
            rounds = true,
            visibility = true,
        }
        activeGameMaster.assistants[member.playerKey] =
            addon.GameMasterDelegation.NormalizeRights(source)
        if not testSession then
            local sent, errorMessage = sendAssistantStateTo(
                member.playerID,
                "HIGH",
                true
            )
            if not sent then
                activeGameMaster.assistants[member.playerKey] = nil
                return false, errorMessage
                    or addon.L("COMMUNICATION_UNAVAILABLE")
            end
        end
    else
        if not testSession then
            sendAssistantStateTo(member.playerID, "HIGH", false)
        end
        activeGameMaster.assistants[member.playerKey] = nil
    end

    if authorityChanged or enabled ~= true then
         
        activeGameMaster.assistantAuthorityRevisions = activeGameMaster.assistantAuthorityRevisions or {}
        activeGameMaster.assistantAuthorityRevisions[member.playerKey] = getVisibilityRevision()
    end

    local session = getSession()
    if session then
        local access = addon.GameMasterStore.GetSceneAccess(session)
        for index = #access.assistants, 1, -1 do
            if access.assistants[index].playerKey == member.playerKey then
                table.remove(access.assistants, index)
            end
        end
        if enabled == true then
            access.assistants[#access.assistants + 1] = {
                playerID = member.playerID,
                playerKey = member.playerKey,
                rights = addon.GameMasterDelegation.NormalizeRights(
                    activeGameMaster.assistants[member.playerKey]
                ),
            }
        end
        if testSession then
            session.access = access
        else
            addon.GameMasterStore.UpdateSessionSettings(
                session.id,
                getLocalPlayerID(),
                session.name,
                access
            )
        end
    end
    notifyListeners("assistants")
    return true
end


function addon.GameMasterService.GetVisibility()
    if activeGameMaster and isLocalController() then
        return addon.GameMasterVisibility.Normalize(
            activeGameMaster.visibility
        )
    end
    return remoteSession
        and addon.GameMasterVisibility.Normalize(remoteSession.visibility)
        or "hidden"
end

function addon.GameMasterService.GetSharedActions()
    local session = getSession()
    if session then
        local round = addon.GameMasterStore.GetCurrentRound(session)
        return addon.GameMasterVisibility.BuildEntries(
            session,
            round,
            activeGameMaster and activeGameMaster.visibility or "full",
            not (tutorial and tutorial.role == "player")
        )
    end
    if not remoteSession or remoteSession.sharedRoundID ~= remoteSession.roundID
    then
        return {}
    end
    return remoteSession.sharedActions or {}
end

function addon.GameMasterService.GetIncomingActions()
    local incoming = addon.GameMasterIncomingActions
    if not incoming then return {} end
    local session = getSession()
    if session then
        local round = addon.GameMasterStore.GetCurrentRound(session)
        if not round then return {} end
        return incoming.Validate(incomingForPlayer(session, round, getLocalPlayerID()), round.id, round.number) or {}
    end
    if not remoteSession or remoteSession.incomingRoundID ~= remoteSession.roundID then return {} end
    return incoming.Validate(remoteSession.incomingActions or {}, remoteSession.roundID, remoteSession.roundNumber) or {}
end

function addon.GameMasterService.GetActiveBuffsForPlayer(playerID)
    if not addon.GameMasterEffects then
        return {}
    end
    local session = addon.GameMasterService.GetActiveSession()
    if session then
        local playerKey = addon.GameMasterNPCActors and addon.GameMasterNPCActors.IsID(playerID)
            and addon.GameMasterNPCActors.Get(session, playerID) and playerID or addon.GameMasterEffects.FindParticipantKey(
            session,
            playerID
        )
        if not playerKey then
            return {}
        end
        local round = addon.GameMasterStore.GetCurrentRound(session)
        return addon.GameMasterEffects.GetActiveBuffs(
            session,
            playerKey,
            round and round.number
        )
    end
    if not remoteSession or type(remoteSession.sharedBuffs) ~= "table" then
        return {}
    end
    local profile = currentReaderProfile()
    if remoteSession.sharedBuffProfile ~= profile then
        remoteSession.sharedBuffs = publicBuffsOnly(remoteSession.sharedBuffs)
        remoteSession.sharedBuffProfile = profile
        if remoteSession.requestedBuffProfile ~= profile then
            remoteSession.requestedBuffProfile = profile
            requestLeaderSync()
        end
    end
    local playerKey = addon.Runtime.NormalizePlayerID(playerID)
    if playerKey and playerKey:find("^npc_") and (not addon.GameMasterNPCActors
        or not addon.GameMasterNPCActors.IsID(playerID)) then return {} end
    local entries = playerKey and remoteSession.sharedBuffs[playerKey] or nil
    if not entries then
        for candidateKey, candidateEntries in pairs(remoteSession.sharedBuffs) do
            if addon.GameMasterEffects.PlayerIDsMatch(playerID, candidateKey) then
                entries = candidateEntries
                break
            end
        end
    end
    return addon.GameMasterEffects.PruneSharedBuffs(
        entries or {},
        remoteSession.roundNumber,
        addon.Runtime.GetTimestamp()
    )
end

function addon.GameMasterService.GetActionMembers()
    local members = testSession and addon.GameMasterTestMode.GetMembers(testSession)
        or addon.GameMasterRoster.GetMembers()
    local session = getSession() or remoteSession
    if not session or session.gmParticipates ~= false then return members end
    local ownerKey = session.ownerKey or addon.Runtime.NormalizePlayerID(session.gameMasterID)
    local result = {}
    for _, member in ipairs(members) do
        if addon.Runtime.NormalizePlayerID(member.playerID) ~= ownerKey then
            result[#result + 1] = member
        end
    end
    return result
end

function addon.GameMasterService.GetActionWorldMarkers()
    if testSession then
        return addon.GameMasterTestMode.GetWorldMarkers()
    end
    return addon.GameMasterRoster.GetActiveWorldMarkers()
end

function addon.GameMasterService.GetActionNPCs()
    local session = getSession()
    if session and isLocalController() then
        return addon.GameMasterNPCActors.List(session, true, false)
    end
    local result = {}
    for _, entry in ipairs(remoteSession and remoteSession.sharedActions or {}) do
        if entry.actorKind == "npc" and entry.npcProfile then
            local actor = addon.GameMasterNPCActors.Profile(entry.npcProfile)
            if actor then
                actor.id, actor.released, actor.markerIndex = entry.playerID, true, entry.markerIndex
                result[#result + 1] = actor
            end
        end
    end
    return result
end

local function editableNPCSession(sessionID)
    if not hasGameMasterModule() or remoteSession then return nil end
    if tutorial then
        return tutorial.role == "gm" and testSession
            and (not sessionID or sessionID == testSession.id) and testSession or nil
    end
    local session = sessionID and addon.GameMasterStore.GetSession(sessionID) or getSession()
    if testSession and (not sessionID or sessionID == testSession.id) then session = testSession end
    if not session or session.ownerKey ~= getLocalPlayerKey() then return nil end
    if activeGameMaster and session.id == activeGameMaster.sessionID and not isLocalController() then return nil end
    return session
end

local function npcChanged(session, sessionChanged)
    session.updatedAt = addon.Runtime.GetTimestamp()
    if activeGameMaster and session.id == activeGameMaster.sessionID then
        activeGameMaster.visibilitySnapshots = nil
        if sessionChanged then broadcastCurrentState("HIGH") else broadcastVisibility("HIGH") end
        broadcastAssistantStates("HIGH")
    end
    notifyListeners("npcs")
end

local function clearNPCIntent(session, actorID)
    local round = addon.GameMasterStore.GetCurrentRound(session)
    if round then
        if round.npcSubmissions then round.npcSubmissions[actorID] = nil end
        if round.npcCompletedTurns then round.npcCompletedTurns[actorID] = nil end
        if round.npcOriginSequences then round.npcOriginSequences[actorID] = nil end
    end
    if session.preparations then session.preparations[actorID] = nil end
end

function addon.GameMasterService.ListNPCs(sessionID)
    local session = editableNPCSession(sessionID)
    return session and addon.GameMasterNPCActors.List(session) or {}
end

function addon.GameMasterService.GetNPCActor(actorID, sessionID)
    if remoteSession and (not sessionID or sessionID == remoteSession.sessionID) then
        local actor = remoteSession.controlledNPCs and remoteSession.controlledNPCs[actorID]
        return actor and addon.GameMasterNPCActors.Copy(actor, true) or nil
    end
    local actor = addon.GameMasterNPCActors.Get(editableNPCSession(sessionID), actorID)
    return actor and addon.GameMasterNPCActors.Copy(actor, true) or nil
end

local function companionMember(playerID, session)
    if not addon.GameMasterRoster.IsInGroup() then return nil end
    local _, key = addon.Runtime.NormalizeFullPlayerID(playerID)
    local member = key and addon.GameMasterRoster.FindMember(key)
    if addon.GameMasterRoster.IsAvailable and not addon.GameMasterRoster.IsAvailable() then return nil end
    if not member or member.playerKey ~= key or member.online == false
        or session and session.currentRoundID and key ~= session.ownerKey and not session.participants[key] then return nil end
    return member
end

local function supportsCompanionDiscovery(playerID)
    return type(addon.Communication.HasCapability) == "function"
        and addon.Communication.HasCapability(playerID, addon.Constants.GAMEMASTER_COMPANION_DISCOVERY_CAPABILITY)
end

local function currentCompanionDiscovery()
    local discovery = companionDiscovery
    local session, round = getSession(), getCurrentRound()
    if not discovery or discovery.state ~= activeGameMaster or not session
        or discovery.sessionID ~= session.id or discovery.activationID ~= activeGameMaster.activationID
        or discovery.revision ~= getVisibilityRevision() or discovery.roundID ~= (round and round.id or "") then return nil end
    return discovery
end

function addon.GameMasterService.RequestNPCCompanions(sessionID)
    local session = editableNPCSession(sessionID)
    if testSession or tutorial or not activeGameMaster or not session or getSession() ~= session
        or not isLocalController() or not companionMember(getLocalPlayerID(), session) then return false end
    local now = addon.Runtime.GetMonotonicTime()
    if companionQueryGate and companionQueryGate.state == activeGameMaster and now - companionQueryGate.at < 5 then return false end
    local members = addon.GameMasterRoster.GetMembers()
    if #members > 40 or addon.GameMasterRoster.IsAvailable and not addon.GameMasterRoster.IsAvailable() then return false end
    if companionQuerySerial >= addon.Constants.MAX_IMPORT_SAFE_INTEGER then return false end
    companionQuerySerial = companionQuerySerial + 1
    companionQueryGate = { state = activeGameMaster, at = now }
    local discovery = currentCompanionDiscovery()
    if not discovery then
        local round = getCurrentRound()
        discovery = { state = activeGameMaster, sessionID = session.id, activationID = activeGameMaster.activationID,
            roundID = round and round.id or "", revision = getVisibilityRevision(), pending = {}, reports = {} }
        companionDiscovery = discovery
    end
    local sent = false
    for _, member in ipairs(members) do
        if member.playerKey ~= getLocalPlayerKey() and companionMember(member.playerID, session)
            and supportsCompanionDiscovery(member.playerID) then
            local payload = { sessionId = discovery.sessionID, activationId = discovery.activationID,
                roundId = discovery.roundID, stateRevision = discovery.revision,
                requestId = "companions_" .. string.format("%.0f", companionQuerySerial) }
            discovery.pending[member.playerKey] = { requestID = payload.requestId, at = now }
             
            if addon.GameMasterProtocol.Send(member.playerID, "companionRequest", payload, "LOW") then
                sent = true
            else discovery.pending[member.playerKey] = nil end
        end
    end
    return sent
end

function addon.GameMasterService.ReceiveCompanionRequest(payload, sender)
    if testSession or tutorial or not remoteSession or type(payload) ~= "table"
        or not companionMember(sender) or not isCurrentLeader(sender) or not supportsCompanionDiscovery(sender)
        or type(payload.stateRevision) ~= "number" or not sessionMatches(payload, remoteSession)
        or payload.stateRevision < math.max(getStateRevision(remoteSession), remoteSession.assistantStateRevision or 0)
        or payload.roundId ~= (remoteSession.roundID or "") or not isSafeID(payload.requestId) then return end
    local now = addon.Runtime.GetMonotonicTime()
     
     
    if companionReplyGate and companionReplyGate.sessionID == remoteSession.sessionID
        and companionReplyGate.activationID == remoteSession.activationID and now - companionReplyGate.at < 5 then return end
    companionReplyGate = { sessionID = remoteSession.sessionID, activationID = remoteSession.activationID, at = now }
    local entries = {}
    for _, entry in ipairs(addon.GameMasterRoster.GetLocalCompanions()) do
        if entry.ownerPlayerKey ~= getLocalPlayerKey() or #entries >= 2 then return end
        entries[#entries + 1] = { guid = entry.guid, name = entry.name, icon = entry.icon }
    end
    if not addon.GameMasterRoster.ValidateCompanionReports(entries, getLocalPlayerKey()) then return end
    addon.GameMasterProtocol.Send(sender, "companionReply", { sessionId = payload.sessionId,
        activationId = payload.activationId, roundId = payload.roundId, stateRevision = payload.stateRevision,
        requestId = payload.requestId, entries = entries }, "MEDIUM")
end

function addon.GameMasterService.ReceiveCompanionReply(payload, sender)
    local discovery = currentCompanionDiscovery()
    local session = getSession()
    if not discovery or testSession or tutorial or type(payload) ~= "table" or not isLocalController()
        or not supportsCompanionDiscovery(sender) then return end
    local member = companionMember(sender, session)
    local pending = member and discovery.pending[member.playerKey]
    if not pending or addon.Runtime.GetMonotonicTime() - pending.at >= 10
        or payload.sessionId ~= discovery.sessionID or payload.activationId ~= discovery.activationID
        or payload.roundId ~= discovery.roundID or payload.stateRevision ~= discovery.revision
        or payload.requestId ~= pending.requestID then return end
    discovery.pending[member.playerKey] = nil
    local entries = addon.GameMasterRoster.ValidateCompanionReports(payload.entries, member.playerKey)
    if not entries then return end
    discovery.reports[member.playerKey] = { entries = entries, at = addon.Runtime.GetMonotonicTime() }
     
    for _, listener in ipairs(listeners) do
        local ok, err = addon.Runtime.SafeInvoke(listener, "companions")
        if not ok then addon.Logger.Error(tostring(err)) end
    end
end

function addon.GameMasterService.GetNPCCompanions(sessionID)
    local session = editableNPCSession(sessionID)
    if not session then return {} end
    local result, seen = {}, {}
    for _, entry in ipairs(addon.GameMasterRoster.GetCompanions and addon.GameMasterRoster.GetCompanions() or {}) do
        if entry.ownerPlayerKey == getLocalPlayerKey() or companionMember(entry.ownerPlayerKey, session) then
            result[#result + 1] = entry
            seen[entry.guid] = true
        end
    end
    local discovery = currentCompanionDiscovery()
    if not discovery or getSession() ~= session or not isLocalController() then return result end
    local claims, conflicts = {}, {}
    local now = addon.Runtime.GetMonotonicTime()
    for owner, report in pairs(discovery.reports) do
        if now - report.at < 15 and companionMember(owner, session) then
            for _, entry in ipairs(report.entries) do
                if claims[entry.guid] and claims[entry.guid].ownerPlayerKey ~= owner then conflicts[entry.guid] = true end
                claims[entry.guid] = entry
            end
        end
    end
    for guid, entry in pairs(claims) do
        if not seen[guid] and not conflicts[guid] then
            result[#result + 1] = { guid = guid, name = entry.name, icon = entry.icon,
                ownerPlayerKey = entry.ownerPlayerKey, ownerReported = true }
        end
    end
    table.sort(result, function(a, b) return a.guid < b.guid end)
    return result
end

function addon.GameMasterService.GetControlledNPCs()
    if remoteSession then
        local result = {}
        for _, actor in pairs(remoteSession.controlledNPCs or {}) do
            result[#result + 1] = addon.GameMasterNPCActors.Copy(actor, true)
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end
    local result, session = {}, getSession()
    for _, actor in ipairs(addon.GameMasterNPCActors.List(session, true, true)) do
        if actor.side == "players" and addon.GameMasterNPCActors.CanControl(session, actor, getLocalPlayerKey()) then
            result[#result + 1] = actor
        end
    end
    return result
end

function addon.GameMasterService.SetNPCController(actorID, side, ownerKey, sessionID)
    local session = editableNPCSession(sessionID)
    local actor = addon.GameMasterNPCActors.Get(session, actorID)
    ownerKey = ownerKey and addon.Runtime.NormalizePlayerID(ownerKey) or session and session.ownerKey
    local knownOwner = session and ownerKey and (ownerKey == session.ownerKey or session.participants[ownerKey]
        or not session.currentRoundID and addon.GameMasterRoster.FindMember(ownerKey))
    if not actor or (side ~= "players" and side ~= "enemies") or not knownOwner
        or side == "enemies" and ownerKey ~= session.ownerKey or actor.revision >= 2147483647 then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end
    if actor.side == side and actor.ownerPlayerKey == ownerKey then return true end
    actor.companionGUID = nil
    actor.side, actor.ownerPlayerKey = side, ownerKey
    actor.revision = actor.revision + 1
    if side == "players" then actor.relationship = "friendly" else session.enemyPhases = true end
    clearNPCIntent(session, actorID)
    if actor.markerIndex and not testSession and addon.NPCMarkers then
        local ok, err = addon.NPCMarkers.Assign(actor.markerIndex, actor)
        if ok == false and err then addon.Logger.Error(err) end
    end
    npcChanged(session, true)
    return true
end

function addon.GameMasterService.AddNPCToSession(npcID, sessionID)
    local session = editableNPCSession(sessionID)
    if not session or not addon.NPCArchive or not addon.NPCArchive.GetEncounterTemplate
        or addon.Modules and not addon.Modules.IsEnabled("npc") then
        return nil, addon.L("GAMEMASTER_NPC_UNAVAILABLE")
    end
    local template, err = addon.NPCArchive.GetEncounterTemplate(npcID)
    if not template then return nil, err end
    local actor, errorMessage = addon.GameMasterNPCActors.Add(session, template)
    if not actor then return nil, errorMessage end
    npcChanged(session, true)
    return addon.GameMasterNPCActors.Copy(actor, true)
end

function addon.GameMasterService.SetNPCReleased(actorID, released, sessionID)
    local session = editableNPCSession(sessionID)
    local actor = addon.GameMasterNPCActors.Get(session, actorID)
    if not actor or type(released) ~= "boolean" then return false, addon.L("GAMEMASTER_NPC_UNAVAILABLE") end
    if actor.released == released then return true end
    if actor.revision >= 2147483647 then return false, addon.L("GAMEMASTER_NPC_UNAVAILABLE") end
    actor.released, actor.active = released, released
    actor.revision = actor.revision + 1
    if not released then
        if session.preparations then session.preparations[actorID] = nil end
        local round = addon.GameMasterStore.GetCurrentRound(session)
        if round then
            if round.npcSubmissions then round.npcSubmissions[actorID] = nil end
            if round.npcCompletedTurns then round.npcCompletedTurns[actorID] = nil end
        end
    end
    npcChanged(session)
    return true
end

function addon.GameMasterService.AssignNPCCompanion(actorID, guid, sessionID)
    local session = editableNPCSession(sessionID)
    local actor = addon.GameMasterNPCActors.Get(session, actorID)
    if not actor then return false, addon.L("GAMEMASTER_NPC_UNAVAILABLE") end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, guid)
        if not ok or secret ~= false then return false, addon.L("GAMEMASTER_NPC_NO_COMPANION") end
    end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, guid)
        if not ok or accessible ~= true then return false, addon.L("GAMEMASTER_NPC_NO_COMPANION") end
    end
    if guid == nil then
        if not actor.companionGUID then return true end
        if actor.revision >= 2147483647 then return false, addon.L("GAMEMASTER_NPC_UNAVAILABLE") end
        actor.companionGUID, actor.released, actor.active = nil, false, false
        actor.revision = actor.revision + 1
        clearNPCIntent(session, actorID)
        npcChanged(session)
        return true
    end
    if type(guid) ~= "string" then return false, addon.L("GAMEMASTER_NPC_NO_COMPANION") end
    local selected
    for _, candidate in ipairs(addon.GameMasterService.GetNPCCompanions(sessionID)) do
        if candidate.guid == guid then selected = candidate; break end
    end
    if not selected then return false, addon.L("GAMEMASTER_NPC_NO_COMPANION") end
    for _, other in pairs(session.npcActors) do
        if other.id ~= actorID and other.companionGUID == guid then
            return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
        end
    end
    if not (selected.ownerPlayerKey == session.ownerKey or session.participants[selected.ownerPlayerKey] or not session.currentRoundID
        and addon.GameMasterRoster.FindMember(selected.ownerPlayerKey)) or actor.revision >= 2147483647 then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end
    actor.side, actor.ownerPlayerKey, actor.relationship = "players", selected.ownerPlayerKey, "friendly"
    actor.name, actor.companionGUID = selected.name, guid
    if selected.icon then actor.icon = selected.icon end
    actor.revision = actor.revision + 1
    clearNPCIntent(session, actorID)
    if actor.markerIndex and not testSession and addon.NPCMarkers then addon.NPCMarkers.Assign(actor.markerIndex, actor) end
    npcChanged(session, true)
    return true
end

function addon.GameMasterService.SetNPCMarker(actorID, markerIndex, sessionID)
    local session = editableNPCSession(sessionID)
    local actor = addon.GameMasterNPCActors.Get(session, actorID)
    if not actor or markerIndex ~= nil and not readInteger(markerIndex, 1, 8) then
        return false, addon.L("GAMEMASTER_INVALID_TARGET")
    end
    markerIndex = markerIndex ~= nil and readInteger(markerIndex, 1, 8) or nil
    if actor.markerIndex == markerIndex then return true end
     
    if markerIndex then
        for _, other in pairs(session.npcActors) do
            if other.markerIndex == markerIndex then other.markerIndex = nil end
        end
    end
    actor.markerIndex = markerIndex
    if markerIndex and not testSession and addon.NPCMarkers and addon.NPCMarkers.Assign then
        local ok, err = addon.NPCMarkers.Assign(markerIndex, actor)
        if ok == false and err then addon.Logger.Error(err) end
    end
    npcChanged(session)
    return true
end

function addon.GameMasterService.RemoveNPC(actorID, sessionID)
    local session = editableNPCSession(sessionID)
    if not addon.GameMasterNPCActors.Get(session, actorID) then return false end
    if addon.GameMasterStore.GetCurrentRound(session) then return false, addon.L("GAMEMASTER_NPC_HIDE_INSTEAD") end
    session.npcActors[actorID] = nil
    for index, value in ipairs(session.npcOrder) do
        if value == actorID then table.remove(session.npcOrder, index); break end
    end
    npcChanged(session)
    return true
end

function addon.GameMasterService.GetNPCSubmissionContext(actorID)
    if remoteSession then
        local actor = remoteSession.controlledNPCs and remoteSession.controlledNPCs[actorID]
        if not actor or not addon.GameMasterService.CanSubmit() or addon.GameMasterService.GetTurnState().completed
            or not remoteSession.originReady then return nil end
        return { actorID = actorID, sessionID = remoteSession.sessionID, sessionName = remoteSession.sessionName,
            activationID = remoteSession.activationID, roundID = remoteSession.roundID,
            roundNumber = remoteSession.roundNumber, phase = remoteSession.phase or "players",
            stateRevision = remoteSession.lastVisibilityRevision or remoteSession.lastStateRevision,
            npcRevision = actor.revision, lastSubmission = actor.lastSubmission }
    end
    local session = editableNPCSession()
    local round = session and addon.GameMasterStore.GetCurrentRound(session)
    if not addon.GameMasterNPCActors.CanAct(session, round, actorID) then return nil end
    return {
        actorID = actorID, sessionID = session.id, sessionName = session.name,
        activationID = activeGameMaster and activeGameMaster.activationID,
        roundID = round.id, roundNumber = round.number, phase = round.phase,
        stateRevision = getVisibilityRevision(),
        npcRevision = session.npcActors[actorID].revision,
        lastSubmission = round.npcSubmissions and round.npcSubmissions[actorID],
    }
end

function addon.GameMasterService.CanSubmitNPC(actorID)
    local context = addon.GameMasterService.GetNPCSubmissionContext(actorID)
    if remoteSession then return context ~= nil end
    local round = getCurrentRound()
    return context ~= nil and round ~= nil and round.status == "open"
end

function addon.GameMasterService.SetNPCTurnCompleted(actorID, completed)
    local session = editableNPCSession()
    local round = session and addon.GameMasterStore.GetCurrentRound(session)
    if type(completed) ~= "boolean" or not addon.GameMasterNPCActors.IsTurnActive(session, round, actorID) then return false end
    if not addon.GameMasterNPCActors.HasIndependentTurn(session, session.npcActors[actorID]) then return false end
    round.npcCompletedTurns = round.npcCompletedTurns or {}
    if (round.npcCompletedTurns[actorID] == true) == completed then return true end
    round.npcCompletedTurns[actorID] = completed or nil
    npcChanged(session)
    return true
end

function addon.GameMasterService.SubmitNPC(actorID, spellID, action, targets, options, controllerKey)
    if not addon.GameMasterService.CanSubmitNPC(actorID) or not addon.Constants.GAMEMASTER_ACTIONS[action] then
        return false, addon.L("GAMEMASTER_NO_OPEN_ROUND")
    end
    options = type(options) == "table" and options or {}
    if options.context ~= nil and type(options.context) ~= "table" then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end
    if remoteSession then
        local context = addon.GameMasterService.GetNPCSubmissionContext(actorID)
        local pending = pendingNPCSubmissions[actorID]
        if pending and context and (pending.sessionId ~= context.sessionID
            or pending.activationId ~= context.activationID or pending.roundId ~= context.roundID
            or pending.phase ~= context.phase or pending.npcRevision ~= context.npcRevision) then
            pendingNPCSubmissions[actorID] = nil
        end
        if not context or pendingNPCSubmissions[actorID] then return false, addon.L("GAMEMASTER_SUBMISSION_PENDING") end
        if options.context and (options.context.activationID ~= context.activationID
            or options.context.roundID ~= context.roundID or options.context.npcRevision ~= context.npcRevision
            or options.context.sessionID ~= context.sessionID or options.context.phase ~= context.phase) then
            return false, addon.L("GAMEMASTER_NPC_CONTEXT_CHANGED")
        end
        local payload = { npcActorID = actorID, npcRevision = context.npcRevision,
            spellID = spellID, action = action, targets = targets, aoe = options.aoe == true,
            mode = options.mode or "replace", submissionId = createSubmissionID(),
            activationId = context.activationID, sessionId = context.sessionID,
            roundId = context.roundID, phase = context.phase, stateRevision = context.stateRevision }
        payload.originSequence = remoteSession.originSequence
        local target = remoteSession.gameMasterID
        local sent, err = addon.GameMasterProtocol.Send(target, "submit", payload, "HIGH")
        if not sent then return false, err end
        pendingNPCSubmissions[actorID] = payload
        if C_Timer and C_Timer.After then
            C_Timer.After(10, function()
                if pendingNPCSubmissions[actorID] ~= payload then return end
                pendingNPCSubmissions[actorID] = nil
                if remoteSession and remoteSession.pendingTurn and remoteSession.pendingTurn.waitingForNPCs then
                    remoteSession.pendingTurn = nil
                end
                if not remoteSession or remoteSession.sessionID ~= payload.sessionId
                    or remoteSession.activationID ~= payload.activationId
                    or remoteSession.roundID ~= payload.roundId or remoteSession.phase ~= payload.phase then return end
                requestLeaderSync()
                addon.Logger.Error(addon.L("GAMEMASTER_SUBMISSION_TIMEOUT"))
                notifyListeners("submission")
            end)
        end
        return true
    end
    local session = editableNPCSession()
    local actor = addon.GameMasterNPCActors.Get(session, actorID)
    local round = addon.GameMasterStore.GetCurrentRound(session)
    if not addon.GameMasterNPCActors.CanControl(session, actor, controllerKey or getLocalPlayerKey()) then
        return false, addon.L("GAMEMASTER_LEADER_ONLY")
    end
    if options.context then
        local context = options.context
        if context.sessionID ~= session.id or context.roundID ~= round.id
            or context.phase ~= round.phase or context.activationID ~= activeGameMaster.activationID
            or context.npcRevision ~= actor.revision then
            return false, addon.L("GAMEMASTER_NO_OPEN_ROUND")
        end
    end
    if options.mode ~= nil and options.mode ~= "append" and options.mode ~= "replace" then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end
    local spell
    for _, candidate in ipairs(actor.spells) do if candidate.id == spellID then spell = candidate; break end end
    local cleaned = spell and cleanSpellSnapshot(spell)
    if not cleaned then return false, addon.L("GAMEMASTER_OWN_SPELL_REQUIRED") end
    local castRounds = addon.SpellPresentation.GetCastRounds(cleaned) or 0
    if action == "prepare" and castRounds < 1 then return false, addon.L("GAMEMASTER_INVALID_SUBMISSION") end
    local cleanedTargets = cleanTargets(targets, nil, action, options.aoe)
    if not cleanedTargets then return false, addon.L("GAMEMASTER_INVALID_TARGET") end
    local ok, result = addon.GameMasterStore.SaveNPCSubmission(session, actorID, {
        action = action, spell = cleaned, targets = cleanedTargets, target = cleanedTargets[1],
        aoe = options.aoe == true, mode = options.mode or "replace", playerID = actorID, rpName = actor.name,
        submissionId = controllerKey and options.submissionId or createSubmissionID(),
        preparation = action == "prepare" and { required = castRounds, automated = false } or nil,
    })
    if ok then npcChanged(session) end
    return ok, result
end

function addon.GameMasterService.ReceiveNPCSubmission(payload, sender, playerKey)
    if not addon.GameMasterNPCActors.IsID(payload.npcActorID) then return end
    local session, round = getSession(), getCurrentRound()
    local actor = addon.GameMasterNPCActors.Get(session, payload.npcActorID)
    local function ack(accepted)
        addon.GameMasterProtocol.Send(sender, "npcAck", { sessionId = payload.sessionId,
            activationId = payload.activationId, roundId = payload.roundId,
            npcActorID = payload.npcActorID, submissionId = payload.submissionId, accepted = accepted }, "HIGH")
    end
    if not actor or not round or actor.side ~= "players" or actor.ownerPlayerKey ~= playerKey
        or payload.npcRevision ~= actor.revision or payload.phase ~= round.phase then ack(false); return end
    for _, previous in ipairs(addon.GameMasterActionCollection.Get(round.npcSubmissions and round.npcSubmissions[actor.id])) do
        if previous.submissionId == payload.submissionId then ack(true); sendVisibilityTo(sender, "HIGH"); return end
    end
    if not addon.GameMasterNPCActors.CanAct(session, round, actor.id)
        or not addon.GameMasterStore.CanParticipantAct(session, round, playerKey) then ack(false); return end
    local revision = readInteger(payload.stateRevision, 0, getVisibilityRevision())
    local sequence = readInteger(payload.originSequence, 1, addon.Constants.MAX_IMPORT_SAFE_INTEGER)
    if not revision or not sequence
        or revision < (round.participantStateRevisions and round.participantStateRevisions[playerKey] or 0)
        or sequence <= (round.npcOriginSequences and round.npcOriginSequences[actor.id] or 0) then ack(false); return end
    local ok = addon.GameMasterService.SubmitNPC(actor.id, payload.spellID, payload.action, payload.targets, {
        aoe = payload.aoe, mode = payload.mode, submissionId = payload.submissionId,
        context = { sessionID = session.id, roundID = round.id, phase = round.phase,
            activationID = activeGameMaster.activationID, npcRevision = actor.revision },
    }, playerKey)
    if ok then
        round.npcOriginSequences = round.npcOriginSequences or {}
        round.npcOriginSequences[actor.id] = sequence
    end
    ack(ok == true)
end

function addon.GameMasterService.ReceiveNPCAck(payload, sender)
    if not remoteSession or not sessionMatches(payload, remoteSession, true)
        or addon.Runtime.NormalizePlayerID(sender) ~= remoteSession.gameMasterKey then return end
    if not addon.GameMasterNPCActors.IsID(payload.npcActorID) or type(payload.accepted) ~= "boolean" then return end
    local pending = pendingNPCSubmissions[payload.npcActorID]
    if not pending or pending.submissionId ~= payload.submissionId or pending.roundId ~= payload.roundId then return end
    pendingNPCSubmissions[payload.npcActorID] = nil
    if payload.accepted ~= true then
        if remoteSession.pendingTurn and remoteSession.pendingTurn.waitingForNPCs then remoteSession.pendingTurn = nil end
        addon.Logger.Error(addon.L("GAMEMASTER_NPC_CONTEXT_CHANGED"))
    elseif flushPendingTurn then
        flushPendingTurn()
    end
    requestLeaderSync()
    notifyListeners("submission")
end

function addon.GameMasterService.CycleVisibility()
    if not activeGameMaster
        or not isLocalController()
    then
        if addon.GameMasterService.IsAssistantGameMaster() then
            return sendAssistantCommand("cycleVisibility")
        end
        return false, addon.L("GAMEMASTER_LEADER_ONLY")
    end
    activeGameMaster.visibility = addon.GameMasterVisibility.Next(
        activeGameMaster.visibility
    )
    local session = getSession()
    if session then
        local access = addon.GameMasterStore.GetSceneAccess(session)
        access.defaultVisibility = activeGameMaster.visibility
        if testSession then
            session.access = access
        else
            addon.GameMasterStore.UpdateSessionSettings(
                session.id,
                getLocalPlayerID(),
                session.name,
                access
            )
        end
    end
    broadcastCurrentState("HIGH")
    broadcastAssistantStates("HIGH")
    notifyListeners("visibility")
    return true, activeGameMaster.visibility
end
function addon.GameMasterService.GetCompatibility(playerID)
    if testSession then
        local playerKey = addon.Runtime.NormalizePlayerID(playerID)
        local participant = playerKey and testSession.participants[playerKey]
        if participant then
            local status = participant.testCompatibility or "compatible"
            return status, status == "compatible" and addon.Constants.ADDON_VERSION
                or (status == "incompatible" and "0.1" or nil)
        end
    end
    if addon.Runtime.NormalizePlayerID(playerID) == getLocalPlayerKey() then
        return "compatible", addon.Constants.ADDON_VERSION
    end
    local peer = addon.GameMasterProtocol.GetPeer(playerID)
    if addon.GameMasterProtocol.Supports(playerID) then
        return "compatible", peer and peer.addonVersion or nil
    end
    if peer then
        return "incompatible", peer.addonVersion
    end
    return "unknown", nil
end

function addon.GameMasterService.ListSessions()
    if tutorial then return testSession and { testSession } or {} end
    return addon.GameMasterStore.ListSessions(getLocalPlayerID())
end

function addon.GameMasterService.GetSceneAccess(sessionID)
    local session = testSession and testSession.id == sessionID and testSession
        or addon.GameMasterStore.GetSession(sessionID)
    if not session or session.ownerKey ~= getLocalPlayerKey() then
        return nil
    end
    return addon.GameMasterStore.GetSceneAccess(session)
end

function addon.GameMasterService.UpdateSessionSettings(
    sessionID,
    name,
    access,
    options
)
    if tutorial then
        if tutorial.role ~= "gm" or not testSession or testSession.id ~= sessionID then return false end
        name = cleanText(name, addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH)
        if not name then return false, addon.L("GAMEMASTER_INVALID_SESSION_NAME") end
        local normalizedOptions = addon.GameMasterStore.NormalizeEncounterOptions(options, testSession)
        if testSession.currentRoundID then
            local previous = addon.GameMasterStore.GetEncounterOptions(testSession)
            for key, value in pairs(normalizedOptions) do
                if value ~= previous[key] then return false, addon.L("GAMEMASTER_ENCOUNTER_OPTIONS_LOCKED") end
            end
        end
        testSession.name = name
        testSession.access = addon.GameMasterSceneAccess.Normalize(access, "full")
        addon.GameMasterStore.SetEncounterOptions(testSession, normalizedOptions)
        activeGameMaster.visibility = testSession.access.defaultVisibility
        notifyListeners("sessions")
        return true, testSession
    end
    if not hasGameMasterModule() then return false, addon.L("GAMEMASTER_LEADER_ONLY") end
    local updated, result =
        addon.GameMasterStore.UpdateSessionSettings(
            sessionID,
            getLocalPlayerID(),
            name,
            access,
            options
        )
    if not updated then
        return false, result
    end

    if activeGameMaster
        and activeGameMaster.sessionID == sessionID
    then
        local previousAssistants = activeGameMaster.assistants or {}
        local nextAssistants =
            addon.GameMasterSceneAccess.ToAssistantMap(
                result.access,
                result.ownerKey
            )
        for playerKey, previousRights in pairs(previousAssistants) do
            local nextRights = nextAssistants[playerKey]
            local changedRights = not nextRights
            for right, value in pairs(previousRights) do
                if nextRights and nextRights[right] ~= value then changedRights = true; break end
            end
            if changedRights then
                activeGameMaster.assistantAuthorityRevisions = activeGameMaster.assistantAuthorityRevisions or {}
                activeGameMaster.assistantAuthorityRevisions[playerKey] =
                    math.min(addon.Constants.MAX_IMPORT_SAFE_INTEGER, getVisibilityRevision() + 1)
            end
            if not nextAssistants[playerKey] then
                local member = addon.GameMasterRoster.FindMember(
                    playerKey
                )
                if member then
                    sendAssistantStateTo(
                        member.playerID,
                        "HIGH",
                        false
                    )
                end
            end
        end
        activeGameMaster.visibility =
            result.access.defaultVisibility
        activeGameMaster.assistants = nextAssistants
        updateStoredRoster()
        broadcastCurrentState("HIGH")
        broadcastAssistantStates("HIGH")
    end
    notifyListeners("sessions")
    notifyListeners("visibility")
    notifyListeners("assistants")
    return true, result
end

function addon.GameMasterService.ActivateSession(sessionID)
    if tutorial then return false, addon.L("TUTORIAL_SESSION_WAIT") end
    if not addon.GameMasterService.CanControl() then
        return false, addon.L("GAMEMASTER_LEADER_ONLY")
    end
    local session = addon.GameMasterStore.GetSession(sessionID)
    if not session or session.ownerKey ~= getLocalPlayerKey() then
        return false, addon.L("GAMEMASTER_SESSION_NOT_FOUND")
    end

    if activeGameMaster then
        suspendLocalSession(true)
    end
    local access = addon.GameMasterStore.GetSceneAccess(session)
        activeGameMaster = {
        activationID = createActivationID(),
        assistants = addon.GameMasterSceneAccess.ToAssistantMap(
            access,
            session.ownerKey
        ),
        sessionID = session.id,
            visibility = access.defaultVisibility,
            visibilityRevision = 0,
    }
    addon.GameMasterStore.SetActiveSession(session.id)
    session.lastActivationID = activeGameMaster.activationID
    session.runningActivationID = activeGameMaster.activationID
    updateStoredRoster()
    compatibilityReport = {
        activationID = activeGameMaster.activationID,
        printed = false,
    }
    addon.Communication.Announce()
    for _, member in ipairs(addon.GameMasterRoster.GetMembers()) do
        queryOrSend(member)
    end
    scheduleCompatibilityReport(activeGameMaster.activationID)
    addon.Logger.Info(addon.L("GAMEMASTER_SESSION_STARTED", session.name))
    scheduleChatFallback(
        "session_started",
        {
            activationID = activeGameMaster.activationID,
            sessionID = session.id,
            sessionName = session.name,
        },
        addon.Constants.GAMEMASTER_COMPATIBILITY_DELAY
    )
    notifyListeners("started")
    if addon.GameMasterWindow
        and addon.GameMasterSettings.ShouldAutoOpenWindow(
            "gameMaster"
        )
    then
        addon.GameMasterWindow.Open()
    end
    return true, session
end

function addon.GameMasterService.StartTestMode(participants, options)
    if not hasGameMasterModule() and not tutorial then
        return false, addon.L("OPTIONAL_MODULE_REQUIRED", "TRP3_RPSpellbook_GameMaster")
    end
    if activeGameMaster or remoteSession then
        return false, addon.L("GAMEMASTER_TEST_ALREADY_ACTIVE")
    end
    local session = addon.GameMasterTestMode.CreateSession(participants, options)
    if type(session) ~= "table" then
        return false, addon.L("GAMEMASTER_INVALID_SESSION_NAME")
    end
    testSession = session
    if tutorial then
        session.tutorialRole = tutorial.role
        addon.GameMasterTestMode.ConfigureTutorial(session)
        tutorial.actorNames = {}
        for _, key in ipairs(session.participantOrder) do
            local participant = session.participants[key]
            participant.rpName = addon.GameMasterParticipantPresentation.FormatName(participant, "trp_full")
            if key ~= session.ownerKey then tutorial.actorNames[#tutorial.actorNames + 1] = participant.rpName end
        end
    end
    activeGameMaster = {
        activationID = createActivationID(),
        assistants = {},
        sessionID = session.id,
        visibility = "full",
        visibilityRevision = 0,
    }
    compatibilityReport = nil
    addon.Logger.Info(addon.L("GAMEMASTER_TEST_STARTED"))
    notifyListeners("started")
    if addon.GameMasterWindow and not (tutorial and tutorial.role == "player") then
        addon.GameMasterWindow.Open()
    end
    return true, session
end

function addon.GameMasterService.RegenerateTestActions()
    if not testSession then
        return false, addon.L("GAMEMASTER_TEST_NOT_ACTIVE")
    end
    local round = addon.GameMasterStore.GetCurrentRound(testSession)
    if not round or round.status ~= "open" or round.phase == "enemies" then
        return false, addon.L("GAMEMASTER_NO_OPEN_ROUND")
    end
    for playerKey in pairs(round.submissions or {}) do
        if playerKey ~= getLocalPlayerKey() then
            round.submissions[playerKey] = nil
            testSession.preparations[playerKey] = nil
        end
    end
    addon.GameMasterTestMode.PopulateRound(testSession, round)
    advanceVisibilityRevision()
    notifyListeners("submission")
    return true
end

function addon.GameMasterService.CreateSession(name, access, options)
    if tutorial then
        if tutorial.role ~= "gm" or testSession or tutorial.finished then return false end
        name = cleanText(name, addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH)
        if not name then return false, addon.L("GAMEMASTER_INVALID_SESSION_NAME") end
        local ok, session = addon.GameMasterService.StartTestMode(4, options)
        if not ok then return false, session end
        session.name = name
        session.access = addon.GameMasterSceneAccess.Normalize(access, "full")
        activeGameMaster.visibility = session.access.defaultVisibility
        notifyListeners("sessions")
        return true, session
    end
    if not addon.GameMasterService.CanControl() then
        return false, addon.L("GAMEMASTER_LEADER_ONLY")
    end
    local sceneAccess = access
    if type(sceneAccess) ~= "table" then
        sceneAccess = {
            defaultVisibility =
                addon.GameMasterSettings.GetDefaultVisibility(),
        }
    end
    local session, errorMessage = addon.GameMasterStore.CreateSession(
        name,
        getLocalPlayerID(),
        sceneAccess,
        options
    )
    if not session then
        return false, errorMessage
    end
    return addon.GameMasterService.ActivateSession(session.id)
end

function addon.GameMasterService.DeleteSession(sessionID)
    if tutorial then return false, addon.L("TUTORIAL_SESSION_WAIT") end
    if not hasGameMasterModule() then return false, addon.L("GAMEMASTER_LEADER_ONLY") end
    if activeGameMaster and activeGameMaster.sessionID == sessionID then
        suspendLocalSession(true)
    end
    local deleted, errorMessage = addon.GameMasterStore.DeleteSession(
        sessionID,
        getLocalPlayerID()
    )
    if deleted then
        notifyListeners("sessions")
    end
    return deleted, errorMessage
end

function addon.GameMasterService.Stop()
    if tutorial then tutorial.finished = true end
    local session = getSession()
    local activationID = activeGameMaster
        and activeGameMaster.activationID
        or nil
    if not activeGameMaster or not session then
        return false
    end
    local wasTestMode = testSession ~= nil
    if addon.GameMasterEffects and addon.GameMasterEffects.EndPermanentEffects then
        addon.GameMasterEffects.EndPermanentEffects(session)
    end
    if not wasTestMode then session.runningActivationID = nil end
    suspendLocalSession(not wasTestMode)
    addon.Logger.Info(addon.L("GAMEMASTER_SESSION_STOPPED"))
    if not wasTestMode then
        scheduleChatFallback("session_stopped", {
            activationID = activationID,
            sessionID = session.id,
            sessionName = session.name,
        })
    end
    return true
end

local function confirmPreviousEffects(session, sourceRound, activationRound)
    if addon.GameMasterEffects and activationRound.phase ~= "enemies" then
        addon.GameMasterEffects.ApplyRoundSubmissions(session, sourceRound, activationRound)
        if sourceRound and not testSession then notifyRoundEffectTargets(session, sourceRound) end
    end
end

function addon.GameMasterService.StartRound()
    if not activeGameMaster or not isLocalController() then
        if addon.GameMasterService.IsAssistantGameMaster() then
            return sendAssistantCommand("startRound")
        end
        return false, addon.L("GAMEMASTER_LEADER_ONLY")
    end
    updateStoredRoster()
    local session = getSession()
    local previousRound = session
        and addon.GameMasterStore.GetCurrentRound(session)
        or nil
    local sameCycle = previousRound and session.enemyPhases == true
        and ((session.enemyFirst == true and previousRound.phase == "enemies")
            or (session.enemyFirst ~= true and previousRound.phase ~= "enemies"))
    if sameCycle then
        local phaseRound, failure
        if session.enemyFirst == true then
            phaseRound, failure = addon.GameMasterStore.StartPlayerPhase(session)
        else
            phaseRound, failure = addon.GameMasterStore.StartEnemyPhase(session)
        end
        if not phaseRound then return false, failure end
         
         
        phaseRound.participantStateRevisions = phaseRound.participantStateRevisions or {}
        for playerKey in pairs(session.participants) do
            phaseRound.participantStateRevisions[playerKey] = getVisibilityRevision() + 1
        end
        if phaseRound.phase == "players" then
            confirmPreviousEffects(session, addon.GameMasterStore.GetPreviousRound(session, phaseRound), phaseRound)
            if testSession then addon.GameMasterTestMode.PopulateRound(session, phaseRound) end
        end
        turnHintUntil = 0
        broadcastCurrentState("HIGH")
        broadcastAssistantStates("HIGH")
        notifyPlayer(addon.GameMasterService.GetPhaseLabel())
        scheduleChatFallback("round_started", {
            activationID = activeGameMaster.activationID,
            phase = phaseRound.phase,
            roundID = phaseRound.id,
            roundNumber = phaseRound.number,
            sessionID = session.id,
            sessionName = session.name,
        })
        notifyListeners("phase")
        return true, phaseRound
    end
    if previousRound and previousRound.phase == "enemies" then
        previousRound.enemyActionsRevealed = true
    end
    local round, errorMessage = addon.GameMasterStore.StartRound(
        session,
        addon.GameMasterSettings.GetHistoryLimit()
    )
    if not round then
        return false, errorMessage
    end
    confirmPreviousEffects(session, previousRound, round)
    if testSession and round.phase ~= "enemies" then
        addon.GameMasterTestMode.PopulateRound(session, round)
    end
    broadcast("round", {
        activationId = activeGameMaster.activationID,
        stateRevision = math.min(addon.Constants.MAX_IMPORT_SAFE_INTEGER, getVisibilityRevision() + 1),
        phase = round.phase or "players",
        roundId = round.id,
        roundNumber = round.number,
        sessionId = session.id,
    }, "HIGH")
    broadcastCurrentState("HIGH")
    broadcastAssistantStates("HIGH")
    notifyPlayer(addon.L(round.phase == "enemies"
        and "GAMEMASTER_PHASE_ENEMIES" or "GAMEMASTER_ROUND_STARTED", round.number))
    scheduleChatFallback("round_started", {
        activationID = activeGameMaster.activationID,
        phase = round.phase or "players",
        roundID = round.id,
        roundNumber = round.number,
        sessionID = session.id,
        sessionName = session.name,
    })
    notifyListeners("round")
    return true, round
end

function addon.GameMasterService.GetEncounterOptions(sessionID)
    local session = type(sessionID) == "table" and sessionID
        or (sessionID and addon.GameMasterStore.GetSession(sessionID))
        or getSession() or remoteSession
    return addon.GameMasterStore.GetEncounterOptions(session)
end

function addon.GameMasterService.GetPhase()
    local session = getSession()
    return session and addon.GameMasterStore.GetPhase(session)
        or (remoteSession and remoteSession.phase == "enemies" and "enemies" or "players")
end

function addon.GameMasterService.GetPhaseLabel()
    return addon.L(addon.GameMasterService.GetPhase() == "enemies"
        and "GAMEMASTER_PHASE_ENEMIES" or "GAMEMASTER_PHASE_PLAYERS")
end

function addon.GameMasterService.GetNextPhaseLabel()
    local round = getCurrentRound()
    if not round and not (remoteSession and remoteSession.roundID) then
        return addon.L("GAMEMASTER_START_ROUND")
    end
    if not addon.GameMasterService.GetEncounterOptions().enemyPhases then
        return addon.L("GAMEMASTER_NEXT_ROUND")
    end
    return addon.L(addon.GameMasterService.GetPhase() == "players"
        and "GAMEMASTER_START_ENEMY_PHASE" or "GAMEMASTER_START_PLAYER_PHASE")
end

function addon.GameMasterService.AdvancePhase()
    return addon.GameMasterService.StartRound()
end

function addon.GameMasterService.GetNextRoundLabel()
    return addon.GameMasterService.GetNextPhaseLabel()
end

function addon.GameMasterService.GetNarratorName()
    return addon.GameMasterService.GetEncounterOptions().narratorName
end

function addon.GameMasterService.LockRound()
    local session = getSession()
    if not session or not isLocalController() then
        if addon.GameMasterService.IsAssistantGameMaster() then
            return sendAssistantCommand("lockRound")
        end
        return false, addon.L("GAMEMASTER_LEADER_ONLY")
    end
    local locked, roundOrError = addon.GameMasterStore.LockCurrentRound(session)
    if not locked then
        return false, roundOrError
    end
    local round = roundOrError
    broadcast("lock", {
        activationId = activeGameMaster.activationID,
        roundId = round.id,
        sessionId = session.id,
        stateRevision = getVisibilityRevision() + 1,
    }, "HIGH")
    broadcastCurrentState("HIGH")
    broadcastAssistantStates("HIGH")
    scheduleChatFallback("round_locked", {
        activationID = activeGameMaster.activationID,
        roundID = round.id,
        roundNumber = round.number,
        sessionID = session.id,
    })
    notifyListeners("round")
    return true, round
end

function addon.GameMasterService.UnlockRound()
    local session = getSession()
    if not session or not isLocalController() then
        if addon.GameMasterService.IsAssistantGameMaster() then
            return sendAssistantCommand("unlockRound")
        end
        return false, addon.L("GAMEMASTER_LEADER_ONLY")
    end
    local unlocked, roundOrError =
        addon.GameMasterStore.UnlockCurrentRound(session)
    if not unlocked then
        return false, roundOrError
    end
    broadcastCurrentState("HIGH")
    broadcastAssistantStates("HIGH")
    scheduleChatFallback("round_unlocked", {
        activationID = activeGameMaster.activationID,
        roundID = roundOrError.id,
        roundNumber = roundOrError.number,
        sessionID = session.id,
    })
    notifyListeners("round")
    return true, roundOrError
end

function addon.GameMasterService.SetParticipantActive(playerKey, active)
    local session = getSession()
    if not session or not isLocalController() then
        if addon.GameMasterService.IsAssistantGameMaster() then
            return sendAssistantCommand("setParticipantActive", {
                active = active == true,
                playerKey = playerKey,
            })
        end
        return false, addon.L("GAMEMASTER_LEADER_ONLY")
    end
    local participant = session.participants[playerKey]
    local interrupted = active == false
        and addon.GameMasterStore.GetPreparation(session, playerKey) ~= nil
    local changed = addon.GameMasterStore.SetParticipantActive(
        session,
        playerKey,
        active,
        math.min(addon.Constants.MAX_IMPORT_SAFE_INTEGER, getVisibilityRevision() + 1)
    )
    if changed then
        if interrupted and participant then
            if playerKey == getLocalPlayerKey() then
                addon.GameMasterPreparation.Interrupted()
            elseif not testSession
                and addon.GameMasterProtocol.Supports(participant.playerID)
            then
                addon.GameMasterProtocol.Send(
                    participant.playerID,
                    "preparationInterrupt",
                    {
                        activationId = activeGameMaster.activationID,
                        stateRevision = math.min(addon.Constants.MAX_IMPORT_SAFE_INTEGER, getVisibilityRevision() + 1),
                        sessionId = session.id,
                    },
                    "HIGH"
                )
            end
        end
        broadcastVisibility("HIGH")
        broadcastAssistantStates("HIGH")
        notifyListeners("participant")
    end
    return changed
end

function addon.GameMasterService.RemoveBuff(
    playerKey,
    sourcePlayerKey,
    spellID
)
    local session = getSession()
    if not session or not isLocalController() then
        if addon.GameMasterService.IsAssistantGameMaster() then
            return sendAssistantCommand("removeBuff", {
                playerKey = playerKey,
                sourcePlayerKey = sourcePlayerKey,
                spellID = spellID,
            })
        end
        return false, addon.L("GAMEMASTER_LEADER_ONLY")
    end
    local removedKind
    if tutorial then
        for _, effect in ipairs(addon.GameMasterEffects.GetActiveBuffs(session, playerKey)) do
            if effect.sourcePlayerKey == sourcePlayerKey and effect.spell and effect.spell.id == spellID then
                removedKind = effect.spell.effects and effect.spell.effects.debuff and "debuff" or "buff"
            end
        end
    end
    if (type(session.participants[playerKey]) ~= "table" and not (addon.GameMasterNPCActors
        and addon.GameMasterNPCActors.Get(session, playerKey)))
        or not addon.GameMasterEffects.RemoveActiveBuff(
            session,
            playerKey,
            sourcePlayerKey,
            spellID
        )
    then
        return false, addon.L("GAMEMASTER_BUFF_NOT_FOUND")
    end
    if removedKind and addon.Onboarding and addon.Onboarding.RecordAction then
        addon.Onboarding.RecordAction("removed_" .. removedKind)
    end
    broadcastAssistantStates("HIGH")
    broadcastVisibility("HIGH")
    notifyListeners("buff")
    return true
end

local timedEffectsPublishPending = false
function addon.GameMasterService.PublishTimedEffects()
    if not addon.GameMasterService.IsPrimaryGameMaster() or testSession or tutorial then return false end
    if timedEffectsPublishPending then return true end
    timedEffectsPublishPending = true
    local function publish()
        timedEffectsPublishPending = false
        if not addon.GameMasterService.IsPrimaryGameMaster() or testSession or tutorial then return end
        broadcastAssistantStates("HIGH")
        broadcastVisibility("HIGH")
        notifyListeners("buff")
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, publish) else publish() end
    return true
end

function addon.GameMasterService.MoveParticipant(playerKey, direction)
    if addon.GameMasterStore.IsOrderLocked() then
        return false
    end
    if addon.GameMasterService.IsAssistantGameMaster() then
        return sendAssistantCommand("moveParticipant", {
            direction = direction,
            playerKey = playerKey,
        })
    end
    local moved = addon.GameMasterStore.MoveParticipant(
        getSession(),
        playerKey,
        direction
    )
    if moved then
        broadcastVisibility("HIGH")
        broadcastAssistantStates("HIGH")
        notifyListeners("order")
    end
    return moved
end

function addon.GameMasterService.SetOrderLocked(locked)
    local changed = addon.GameMasterStore.SetOrderLocked(locked)
    if changed then
        notifyListeners("order")
    end
    return changed
end

function addon.GameMasterService.CanSubmit()
    local localRound = activeGameMaster and getCurrentRound() or nil
    local canSubmitLocally = activeGameMaster ~= nil
        and isLocalController()
        and localRound ~= nil
        and localRound.status == "open"
        and addon.GameMasterStore.CanParticipantSubmit(
            getSession(), localRound, getLocalPlayerKey()
        )
    local canSubmitRemotely = remoteSession ~= nil
        and remoteSession.phase ~= "enemies"
        and remoteSession.roundID ~= nil
        and remoteSession.locked == false
        and addon.GameMasterRoster.IsInGroup()
        and (isCurrentLeader(remoteSession.gameMasterID)
            or addon.GameMasterStore.GetRecoveryDisposition(getLocalPlayerKey(),
                addon.GameMasterRoster.GetMembers(), true) == "live")
    if canSubmitRemotely then
        for _, entry in ipairs(remoteSession.sharedActions or {}) do
            if addon.Runtime.NormalizePlayerID(entry.playerID) == getLocalPlayerKey() then
                canSubmitRemotely = entry.active ~= false and entry.online ~= false
                break
            end
        end
    end
    return canSubmitLocally or canSubmitRemotely
end

function addon.GameMasterService.CanCompleteTurn()
    local localRound = activeGameMaster and getCurrentRound() or nil
    if activeGameMaster ~= nil
        and isLocalController()
        and localRound ~= nil
        and addon.GameMasterStore.CanParticipantAct(
            getSession(), localRound, getLocalPlayerKey()
        )
    then
        return true
    end
    if not remoteSession
        or remoteSession.phase == "enemies"
        or not remoteSession.turnTracking
        or not remoteSession.roundID
        or not addon.GameMasterRoster.IsInGroup()
        or not (isCurrentLeader(remoteSession.gameMasterID)
            or addon.GameMasterStore.GetRecoveryDisposition(getLocalPlayerKey(),
                addon.GameMasterRoster.GetMembers(), true) == "live")
    then
        return false
    end
    local gm = addon.GameMasterRoster.FindMember(remoteSession.gameMasterID)
    if gm and gm.online ~= false and addon.GameMasterProtocol.SupportsTurns
        and not addon.GameMasterProtocol.SupportsTurns(remoteSession.gameMasterID)
    then
        return false
    end
    if (not gm or gm.online == false) and addon.GameMasterProtocol.SupportsTurnsKnown
        and not addon.GameMasterProtocol.SupportsTurnsKnown(remoteSession.gameMasterID)
    then
        return false
    end
    for _, entry in ipairs(remoteSession.sharedActions or {}) do
        if addon.Runtime.NormalizePlayerID(entry.playerID) == getLocalPlayerKey() then
            return entry.active ~= false and entry.online ~= false
        end
    end
    return false
end

function addon.GameMasterService.GetTurnState(playerID)
    local key = addon.Runtime.NormalizePlayerID(playerID or getLocalPlayerID())
    local state = { completed = false, active = false, isNext = false, hintUntil = 0 }
    local session = getSession()
    local round = session and addon.GameMasterStore.GetCurrentRound(session)
    local entries = session and addon.GameMasterVisibility.BuildEntries(
        session, round, "hidden"
    ) or addon.GameMasterService.GetSharedActions()
    local nextKey
    for _, entry in ipairs(entries) do
        local entryKey = addon.Runtime.NormalizePlayerID(entry.playerID)
        local active = entry.active ~= false and entry.online ~= false
        if not nextKey and active and not entry.completed and entry.actorKind ~= "npc" then nextKey = entryKey end
        if entryKey == key then
            state.active = active
            state.completed = entry.completed == true
        end
    end
    state.isNext = key ~= nil and key == nextKey
    if key == getLocalPlayerKey() then
        state.hintUntil = turnHintUntil
        state.pending = remoteSession and remoteSession.pendingTurn ~= nil or false
        if remoteSession and remoteSession.pendingTurn then
            state.completed = remoteSession.pendingTurn.completed
        end
    end
    return state
end

local function turnPayload(pending)
    return {
        sessionId = pending.sessionId, activationId = pending.activationId,
        stateRevision = pending.stateRevision, roundId = pending.roundId,
        completed = pending.completed, source = pending.source,
        sequence = pending.sequence,
    }
end

local function canSendPendingTurn()
    local gm = remoteSession and addon.GameMasterRoster.FindMember(remoteSession.gameMasterID)
    return gm ~= nil and gm.online ~= false and remoteSession.originReady == true
        and isCurrentLeader(remoteSession.gameMasterID)
        and addon.GameMasterProtocol.SupportsTurns(remoteSession.gameMasterID)
        and addon.GameMasterService.CanCompleteTurn()
end

local function sendPendingTurn(pending)
    if not remoteSession or remoteSession.pendingTurn ~= pending
        or not canSendPendingTurn() then return false end
    if pending.completed and next(pendingNPCSubmissions) then
        pending.waitingForNPCs, pending.waitingForSync = true, true
        pending.lastSyncSerial = nil
        return true
    end
    pending.waitingForNPCs = nil
    pending.lastAttemptRevision = remoteSession.lastVisibilityRevision or 0
    pending.lastPeerSerial = remoteSession.originPeerSerial or 0
    local sent = addon.GameMasterProtocol.Send(
        remoteSession.gameMasterID, "turnComplete", turnPayload(pending), "HIGH"
    )
    if not sent then
        pending.sentAt = nil
        pending.waitingForSync = true
        remoteSession.originReady = false
        requestLeaderSync()
        return false
    end
    pending.sentAt = addon.Runtime.GetMonotonicTime()
    pending.waitingForSync = nil
    scheduleTurnRecovery(pending)
    return true
end

flushPendingTurn = function()
    local pending = remoteSession and remoteSession.pendingTurn
    if not pending or not pending.waitingForSync or not canSendPendingTurn() then return end
    local serial = remoteSession.originSyncSerial or 0
    if pending.lastSyncSerial == serial then return end
    pending.lastSyncSerial = serial
    sendPendingTurn(pending)
end

scheduleTurnRecovery = function(pending)
    if not C_Timer or type(C_Timer.After) ~= "function"
        or type(pending) ~= "table" or pending.retryScheduled
    then
        return
    end
    local delay = addon.Constants.GAMEMASTER_TURN_RETRY_SECONDS
    local maximum = addon.Constants.GAMEMASTER_TURN_RETRY_ATTEMPTS
    pending.retryScheduled = true
    local dueAt = addon.Runtime.GetMonotonicTime() + delay
    C_Timer.After(delay, function()
        pending.retryScheduled = nil
        if not remoteSession or remoteSession.pendingTurn ~= pending
            or remoteSession.roundID ~= pending.roundId
            or addon.Runtime.GetMonotonicTime() < dueAt
        then
            return
        end
        if not addon.GameMasterService.CanCompleteTurn() then
            remoteSession.pendingTurn = nil
            notifyListeners("turn")
            return
        end
        if not canSendPendingTurn() then
            pending.sentAt = nil
            pending.waitingForSync = true
            requestLeaderSync()
            notifyListeners("turn")
            return
        end
        local attempts = math.max(0, math.floor(tonumber(pending.retryAttempts) or 0))
        if attempts >= maximum then
            remoteSession.pendingTurn = nil
            notifyPlayer(addon.L("GAMEMASTER_TURN_UPDATE_TIMEOUT"))
            notifyListeners("turnTimeout")
            requestLeaderSync()
            return
        end
        local sent = addon.GameMasterProtocol.Send(remoteSession.gameMasterID,
            "turnComplete", turnPayload(pending), "HIGH")
        if not sent then
            pending.sentAt = nil
            pending.waitingForSync = true
            remoteSession.originReady = false
            requestLeaderSync()
            notifyListeners("turn")
            return
        end
        pending.retryAttempts = attempts + 1
        pending.sentAt = addon.Runtime.GetMonotonicTime()
        requestLeaderSync()
        scheduleTurnRecovery(pending)
    end)
end

function addon.GameMasterService.SetOwnTurnCompleted(completed, source)
    if type(completed) ~= "boolean"
        or not addon.GameMasterService.CanCompleteTurn()
    then
        return false
    end
    source = source == "emote" and "emote" or "manual"
    if activeGameMaster then
        local changed = addon.GameMasterStore.SetTurnCompleted(
            getSession(), getLocalPlayerKey(), completed, source
        )
        if changed then
            broadcastVisibility("HIGH")
            broadcastAssistantStates("HIGH")
            notifyListeners("turn")
        end
        return true
    end
    if not remoteSession or not remoteSession.turnTracking then return false end
    local sequence = (remoteSession.turnSequence or 0) + 1
    if sequence > addon.Constants.MAX_IMPORT_SAFE_INTEGER then return false end
    remoteSession.turnSequence = sequence
    local payload = {
        sessionId = remoteSession.sessionID, activationId = remoteSession.activationID,
        stateRevision = getStateRevision(remoteSession),
        roundId = remoteSession.roundID, completed = completed, source = source,
        sequence = sequence,
        retryAttempts = 0,
        waitingForSync = true,
    }
    remoteSession.pendingTurn = payload
     
    notifyListeners("turn")
    if canSendPendingTurn() then
        payload.lastSyncSerial = remoteSession.originSyncSerial or 0
        sendPendingTurn(payload)
    else
        requestLeaderSync()
    end
    return true
end

function addon.GameMasterService.OnRecognizedEmote(playerID)
    local key = addon.Runtime.NormalizePlayerID(playerID)
    if key == getLocalPlayerKey() then
        if not addon.GameMasterService.CanCompleteTurn() then return false end
        turnHintUntil = addon.Runtime.GetMonotonicTime()
            + addon.Constants.GAMEMASTER_TURN_HINT_SECONDS
        notifyListeners("emoteHint")
        if addon.GameMasterPlayerState.ShouldAutoCompleteTurn() then
            if not addon.GameMasterService.GetTurnState().completed then
                return addon.GameMasterService.SetOwnTurnCompleted(true, "emote")
            end
            return true
        end
        return true
    end
     
     
    if activeGameMaster and isLocalController()
        and addon.GameMasterPlayerState.ShouldAutoCompleteTurn()
        and not (addon.GameMasterProtocol.SupportsTurns
            and addon.GameMasterProtocol.SupportsTurns(playerID))
        and addon.GameMasterStore.SetTurnCompleted(getSession(), key, true, "emote")
    then
        broadcastVisibility("HIGH")
        broadcastAssistantStates("HIGH")
        notifyListeners("turn")
        return true
    end
    return false
end

function addon.GameMasterService.NotifyPlayer(message)
    notifyPlayer(message)
end

local schedulePendingRecovery

local function canSendOriginAction()
    local gm = remoteSession and addon.GameMasterRoster.FindMember(remoteSession.gameMasterID)
    return gm ~= nil and gm.online ~= false and remoteSession.originReady == true
        and isCurrentLeader(remoteSession.gameMasterID)
        and addon.GameMasterProtocol.Supports(remoteSession.gameMasterID)
        and addon.GameMasterService.CanSubmit()
end

local function failOriginQueue(message)
    if not getOriginHead() then return end
    clearOriginQueue()
    notifyPlayer(message or addon.L("GAMEMASTER_SUBMISSION_REJECTED"))
    notifyListeners("submission")
end

local function requireOriginProfile(pending)
    local ok, book = pcall(addon.GameMasterService.GetActionSpellbook)
    if not ok or type(book) ~= "table"
        or type(book.profileKey) ~= "string" or book.profileKey == "" then
         
        return false
    end
    local payload = pending and pending.wirePayload
    local spell = type(payload) == "table" and payload.spell
    if type(spell) ~= "table" or spell.ownerKey ~= book.profileKey then
        failOriginQueue(addon.L("GAMEMASTER_OWN_SPELL_REQUIRED"))
        return false
    end
    return true
end

local function sendOriginHead(pending)
    if not remoteSession or getOriginHead() ~= pending or not canSendOriginAction() then
        return false
    end
    if not requireOriginProfile(pending) then return false end
    if not syncOriginQueue() or getOriginHead() ~= pending then
        notifyPlayer(addon.L("GAMEMASTER_SUBMISSION_REJECTED"))
        notifyListeners("submission")
        return false
    end
    local payload = pending.wirePayload
    local spell = cleanSpellSnapshot(payload.spell)
    local targets = spell and cleanTargets(
        payload.targets, payload.target, payload.action, payload.aoe
    ) or nil
    if not spell or not targets
        or (payload.action == "prepare"
            and not cleanPreparation(payload.preparation, spell, payload.action))
    then
        failOriginQueue(addon.L("GAMEMASTER_INVALID_SUBMISSION"))
        return false
    end
    payload.spell, payload.targets, payload.target = spell, targets, targets[1]
    pending.lastSyncSerial = remoteSession.originSyncSerial or 0
    pending.lastAttemptRevision = remoteSession.lastVisibilityRevision or 0
    pending.lastPeerSerial = remoteSession.originPeerSerial or 0
    local sent = addon.GameMasterProtocol.Send(
        remoteSession.gameMasterID, "submit", payload, "HIGH"
    )
    if not sent then
        pending.sentAt = nil
        pending.waitingForSync = true
        remoteSession.originReady = false
        requestLeaderSync()
        return false
    end
    pending.sentAt = addon.Runtime.GetMonotonicTime()
    pending.waitingForSync = nil
    schedulePendingRecovery(pending)
    return true
end

flushOriginOutbox = function()
    local pending = getOriginHead()
    if not pending or not canSendOriginAction() then return end
    local sentAt = tonumber(pending.sentAt)
    local now = addon.Runtime.GetMonotonicTime()
    if sentAt and now >= sentAt
        and now - sentAt < addon.Constants.GAMEMASTER_SUBMISSION_PENDING_TIMEOUT
    then
        return
    end
    if pending.waitingForSync
        and pending.lastAttemptRevision ~= nil
        and (remoteSession.lastVisibilityRevision or 0) <= pending.lastAttemptRevision
        and pending.lastPeerSerial == (remoteSession.originPeerSerial or 0)
    then
        return
    end
    sendOriginHead(pending)
end

local function recoverPendingRemoteSubmission(pending)
    if not remoteSession or getOriginHead() ~= pending then
        return
    end
    if not requireOriginProfile(pending) then return end
    local sentAt = tonumber(pending.sentAt)
    local now = addon.Runtime.GetMonotonicTime()
    local timeout = addon.Constants.GAMEMASTER_SUBMISSION_PENDING_TIMEOUT
    if not sentAt or now < sentAt or now - sentAt < timeout then
        return
    end
    if pending.waitingForSync then return end
    if not canSendOriginAction() then
        pending.sentAt = nil
        pending.waitingForSync = true
        remoteSession.originReady = false
        requestLeaderSync()
        notifyListeners("submission")
        return
    end
    if (tonumber(pending.retryCount) or 0) < 1 then
        local sent = addon.GameMasterProtocol.Send(remoteSession.gameMasterID,
            "submit", pending.wirePayload, "HIGH")
        if not sent then
            pending.sentAt = nil
            pending.waitingForSync = true
            remoteSession.originReady = false
            requestLeaderSync()
            notifyListeners("submission")
            return
        end
        pending.retryCount = 1
        pending.sentAt = now
        requestLeaderSync()
        schedulePendingRecovery(pending)
        return
    end
    pending.sentAt = nil
    pending.waitingForSync = true
    remoteSession.originReady = false
    requestLeaderSync()
    if not pending.timeoutNotified then
        pending.timeoutNotified = true
        notifyPlayer(addon.L("GAMEMASTER_SUBMISSION_TIMEOUT"))
    end
    notifyListeners("submission")
end

schedulePendingRecovery = function(pending)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" and not pending.retryScheduled then
        pending.retryScheduled = true
        C_Timer.After(
            addon.Constants.GAMEMASTER_SUBMISSION_PENDING_TIMEOUT,
            function()
                pending.retryScheduled = nil
                recoverPendingRemoteSubmission(pending)
            end
        )
    end
end

local function getPendingRemoteSubmission()
    local pending = getOriginHead()
    if not pending or not requireOriginProfile(pending) then
        return nil
    end
    local sentAt = tonumber(pending.sentAt)
    local currentTime = addon.Runtime.GetMonotonicTime()
    if sentAt
        and sentAt == sentAt
        and sentAt ~= math.huge
        and sentAt ~= -math.huge
        and currentTime >= sentAt
        and currentTime - sentAt
            < addon.Constants.GAMEMASTER_SUBMISSION_PENDING_TIMEOUT
    then
        return pending
    end
    recoverPendingRemoteSubmission(pending)
    return getOriginHead()
end

function addon.GameMasterService.GetSubmissionContext()
    local enemyPhase = addon.GameMasterService.GetPhase() == "enemies"
    if activeGameMaster and isLocalController() then
        local session = getSession()
        local round = session and addon.GameMasterStore.GetCurrentRound(session) or nil
        local playerKey = getLocalPlayerKey()
        return session and round and {
            activationID = activeGameMaster.activationID,
            lastSubmission = not enemyPhase and round.submissions[playerKey] or nil,
            phase = round.phase or "players",
            roundID = round.id,
            roundNumber = round.number,
            sessionID = session.id,
            sessionName = session.name,
        } or nil
    end
    if remoteSession then
        local pending = getPendingRemoteSubmission()
        local projected = projectOriginQueue()
        return {
            activationID = remoteSession.activationID,
            lastSubmission = not enemyPhase and projected or nil,
            pendingSubmission = not enemyPhase and pending or nil,
            phase = remoteSession.phase or "players",
            pendingSubmissionCount = #(getOriginQueue() or {}),
            roundID = remoteSession.roundID,
            roundNumber = remoteSession.roundNumber,
            sessionID = remoteSession.sessionID,
            sessionName = remoteSession.sessionName,
        }
    end
    return nil
end

function addon.GameMasterService.GetOwnActionGroups()
    local groups = {}
    local context = addon.GameMasterService.GetSubmissionContext()
    if not context then return groups end
    local function add(actorID, name, submission)
        if #addon.GameMasterActionCollection.Get(submission) > 0 then
            groups[#groups + 1] = { actorID = actorID, name = name, submission = submission }
        end
    end
     
    add(getLocalPlayerKey(), nil, context.lastSubmission)
    if remoteSession then
        local ids = {}
        for actorID in pairs(remoteSession.controlledNPCs or {}) do ids[#ids + 1] = actorID end
        table.sort(ids)
        for _, actorID in ipairs(ids) do
            local actor = remoteSession.controlledNPCs[actorID]
            if actor.released and actor.side == "players" and actor.ownerPlayerKey == getLocalPlayerKey() then
                add(actorID, actor.name, actor.lastSubmission)
            end
        end
    else
        local session, round = getSession(), getCurrentRound()
        for _, actorID in ipairs(session and session.npcOrder or {}) do
            local actor = session.npcActors[actorID]
            if actor and actor.released and actor.side == "players"
                and (actor.ownerPlayerKey or session.ownerKey) == getLocalPlayerKey() then
                add(actorID, actor.name, round and round.npcSubmissions and round.npcSubmissions[actorID])
            end
        end
    end
    return groups
end

function addon.GameMasterService.Submit(spell, action, targets, options)
    if not addon.GameMasterService.CanSubmit() then
        return false, addon.L("GAMEMASTER_NO_OPEN_ROUND")
    end
    if not addon.Constants.GAMEMASTER_ACTIONS[action] then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end
    if not activeGameMaster and getOriginHead() then
        requireOriginProfile(getOriginHead())
    end
    local submitsLocally = activeGameMaster ~= nil
        and isLocalController()
    if not submitsLocally and getOriginHead() then
        local supportsQueue = type(addon.GameMasterProtocol.SupportsOriginQueue) ~= "function"
            or addon.GameMasterProtocol.SupportsOriginQueue(remoteSession.gameMasterID)
            or (type(addon.GameMasterProtocol.SupportsOriginQueueKnown) == "function"
                and addon.GameMasterProtocol.SupportsOriginQueueKnown(remoteSession.gameMasterID))
        if not supportsQueue then
            getPendingRemoteSubmission()
            return false, addon.L("GAMEMASTER_SUBMISSION_STILL_PENDING")
        end
    end

    local spellbook = addon.GameMasterService.GetActionSpellbook()
    local ownedSpell = type(spell) == "table"
        and type(spellbook) == "table"
        and type(spellbook.spells) == "table"
        and spellbook.spells[spell.id]
        or nil
    if type(ownedSpell) ~= "table" then
        return false, addon.L("GAMEMASTER_OWN_SPELL_REQUIRED")
    end

    local valid, cleaned, errors = addon.Validators.ValidateSpell(ownedSpell)
    if not valid then
        return false, addon.Validators.GetFirstError(errors)
    end
    if not submitsLocally and cleaned.effects
        and cleaned.effects.durationRounds == addon.Constants.EFFECT_DURATION_PERMANENT
        and addon.GameMasterProtocol.SupportsPermanentEffects
        and not addon.GameMasterProtocol.SupportsPermanentEffects(remoteSession.gameMasterID) then
        return false, addon.L("EFFECT_PERMANENT_PEER_REQUIRED")
    end
    cleaned.id = ownedSpell.id
    cleaned.revision = math.max(1, math.floor(tonumber(ownedSpell.revision) or 1))
    cleaned.ownerKey = spellbook.profileKey
    cleaned = cleanSpellSnapshot(cleaned)
    if not cleaned then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end

    local castRounds = addon.SpellPresentation.GetCastRounds(cleaned) or 0
    if action == "prepare" and castRounds < 1 then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end

    options = type(options) == "table" and options or {}
    local mode = options.mode == "append" and "append" or "replace"
    if options.mode ~= nil
        and options.mode ~= "append"
        and options.mode ~= "replace"
    then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end
    local cleanedTargets = cleanTargets(
        targets,
        type(targets) == "table" and targets.kind and targets or nil,
        action,
        options.aoe
    )
    if not cleanedTargets then
        return false, addon.L("GAMEMASTER_INVALID_TARGET")
    end
    local preparation
    if action == "prepare" then
        preparation = {
            automated = addon.GameMasterPlayerState.ShouldAutomatePreparation(),
            required = castRounds,
        }
    end
    local emote = cleanEmote(options.emote)
    if options.emote ~= nil and not emote then
        return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
    end

    if submitsLocally then
        local session = getSession()
        local member
        if testSession then
            local playerKey = getLocalPlayerKey()
            local participant = playerKey and session.participants[playerKey]
            member = participant and {
                playerID = participant.playerID,
                playerKey = playerKey,
                rpName = participant.rpName,
            } or nil
        else
            member = addon.GameMasterRoster.FindMember(getLocalPlayerID())
        end
        if not session or not member then
            return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
        end
        local round = addon.GameMasterStore.GetCurrentRound(session)
        local accepted, savedOrError, savedAction =
            addon.GameMasterStore.SaveSubmission(
            session,
            member.playerKey,
            {
                action = action,
                aoe = options.aoe == true,
                emote = emote,
                mode = mode,
                playerID = member.playerID,
                submissionId = createSubmissionID(),
                preparation = preparation,
                rpName = member.rpName,
                spell = cleaned,
                target = cleanedTargets[1],
                targets = cleanedTargets,
            }
        )
        if not accepted then
            return false, savedOrError
        end
        local saved = savedOrError
        rememberTextTargets(session.id, cleanedTargets)
        notifyPlayer(addon.L("GAMEMASTER_SUBMISSION_ACCEPTED"))
        if addon.GameMasterPreparation then
            addon.GameMasterPreparation.OnAccepted(
                savedAction
                    or addon.GameMasterActionCollection.GetLatest(saved),
                session.id,
                round and round.number
            )
        end
        broadcastAssistantStates("HIGH")
        broadcastVisibility("HIGH")
        if addon.GameMasterActionStatus then addon.GameMasterActionStatus.Open() end
        notifyListeners("submission")
        return true, saved
    end

    if not remoteSession then
        return false, addon.L("GAMEMASTER_NO_OPEN_ROUND")
    end
    local currentQueue = getOriginQueue() or {}
    if mode == "append" then
        local projected = projectOriginQueue()
        if #currentQueue >= addon.Constants.GAMEMASTER_ORIGIN_OUTBOX_LIMIT
            or addon.GameMasterActionCollection.Count(projected)
                >= addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER
        then
            return false, addon.L("GAMEMASTER_ACTION_LIMIT_REACHED")
        end
        if action == "prepare"
            or addon.GameMasterActionCollection.ContainsPreparation(projected)
        then
            return false, addon.L("GAMEMASTER_INVALID_SUBMISSION")
        end
    end
    local submissionID = createSubmissionID()
    if not submissionID then return false, addon.L("GAMEMASTER_INVALID_SUBMISSION") end
    local payload = {
        action = action, aoe = options.aoe == true,
        activationId = remoteSession.activationID, stateRevision = getStateRevision(remoteSession),
        emote = emote, mode = mode, preparation = preparation,
        roundId = remoteSession.roundID, sessionId = remoteSession.sessionID,
        spell = cleaned, submissionId = submissionID, originSequence = remoteSession.originSequence,
        target = cleanedTargets[1], targets = cleanedTargets,
    }
    local payloads = {}
    if mode == "append" then
        for index, existing in ipairs(currentQueue) do
            payloads[index] = existing.wirePayload
        end
    end
    payloads[#payloads + 1] = payload
    local outbox = addon.GameMasterStore.NormalizeOriginOutbox({
        version = 2, originKey = getLocalPlayerKey(),
        gameMasterKey = remoteSession.gameMasterKey, items = payloads,
    }, getLocalPlayerKey(), remoteSession)
    if not outbox then return false, addon.L("GAMEMASTER_INVALID_SUBMISSION") end
    local queue = {}
    if mode == "append" then
        for index, existing in ipairs(currentQueue) do
            existing.wirePayload = outbox.items[index]
            queue[index] = existing
        end
    end
    local pending = pendingFromOriginPayload(outbox.items[#outbox.items])
    queue[#queue + 1] = pending
    remoteSession.originQueue = queue
    remoteSession.pendingSubmission = queue[1]
    remoteSession.originOutbox = outbox
     
    notifyListeners("submission")
    if canSendOriginAction() then
        flushOriginOutbox()
    else
        requestLeaderSync()
    end
    if addon.GameMasterActionStatus then addon.GameMasterActionStatus.Open() end
    notifyListeners("submission")
    return true
end

function addon.GameMasterService.CancelPendingSubmissions()
    if not remoteSession or not getOriginHead() then return false end
    clearOriginQueue()
    notifyListeners("submission")
    return true
end

function addon.GameMasterService.CancelOwnPreparation()
    local context = addon.GameMasterService.GetSubmissionContext()
    if not context then return false end
    if activeGameMaster and isLocalController() then
        local changed = addon.GameMasterStore.ClearPreparation(
            getSession(),
            getLocalPlayerKey()
        )
        if changed then
            broadcastVisibility("HIGH")
            broadcastAssistantStates("HIGH")
            notifyListeners("preparation")
        end
        return changed
    end
    if not remoteSession then return false end
    return addon.GameMasterProtocol.Send(
        remoteSession.gameMasterID,
        "preparationCancel",
        {
            activationId = remoteSession.activationID,
            stateRevision = getStateRevision(remoteSession),
            roundId = remoteSession.roundID,
            sessionId = remoteSession.sessionID,
        },
        "HIGH"
    )
end

function addon.GameMasterService.InterruptPreparation(playerKey)
    local session = getSession()
    if not session or not isLocalController() then
        if addon.GameMasterService.IsAssistantGameMaster() then
            return sendAssistantCommand("interruptPreparation", {
                playerKey = playerKey,
            })
        end
        return false, addon.L("GAMEMASTER_LEADER_ONLY")
    end
    local participant = session.participants[playerKey]
    if not participant
        or not addon.GameMasterStore.ClearPreparation(session, playerKey)
    then
        return false
    end
    if playerKey == getLocalPlayerKey() then
        if addon.GameMasterPreparation then
            addon.GameMasterPreparation.Interrupted()
        end
    elseif not testSession
        and addon.GameMasterProtocol.Supports(participant.playerID)
    then
        addon.GameMasterProtocol.Send(
            participant.playerID,
            "preparationInterrupt",
            {
                activationId = activeGameMaster.activationID,
                stateRevision = math.min(addon.Constants.MAX_IMPORT_SAFE_INTEGER, getVisibilityRevision() + 1),
                sessionId = session.id,
            },
            "HIGH"
        )
    end
    broadcastVisibility("HIGH")
    broadcastAssistantStates("HIGH")
    notifyListeners("preparation")
    return true
end

function addon.GameMasterService.OpenControl()
    if addon.Modules and not addon.Modules.Require("gameMaster") then return false end
    if not addon.GameMasterService.initialized then
        addon.Logger.Error(addon.L("COMMUNICATION_UNAVAILABLE"))
        return false
    end
    if addon.GameMasterService.IsAssistantGameMaster() then
        addon.GameMasterWindow.Open()
        return true
    end
    if testSession and addon.GameMasterWindow then
        addon.GameMasterWindow.Open()
        return true
    end
    local recovery = addon.GameMasterService.GetSuspendedRecovery()
    if recovery and recovery.localOwner then
        if addon.GameMasterService.ResumeRecovery() then
            return true
        end
        addon.Logger.Error(addon.L("GAMEMASTER_RECOVERY_FAILED"))
        return false
    end
    if not isLocalController() then
        addon.Logger.Error(addon.L("GAMEMASTER_LEADER_ONLY"))
        return false
    end
    if activeGameMaster and addon.GameMasterWindow then
        addon.GameMasterWindow.Open()
        return true
    end
    if addon.GameMasterSessionDialog then
        addon.GameMasterSessionDialog.Open()
        return true
    end
    return false
end

function addon.GameMasterService.OpenAction(spell)
    if not addon.GameMasterService.CanSubmit() then
        addon.Logger.Error(addon.L("GAMEMASTER_NO_OPEN_ROUND"))
        return false
    end
    if addon.GameMasterActionDialog then
        return addon.GameMasterActionDialog.Open(spell)
    end
    return false
end
