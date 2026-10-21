local _, addon = ...

addon.GameMasterProtocol = {
    initialized = false,
}

local handlers = {}
local visibilityTransfers = addon.Cache.NewBounded(32)
local visibilityTransferSerial = 0
local dispatch
local outgoingVisibility = addon.Cache.NewBounded(256)

local messageTypes = {
    companionRequest = "gm_companion_request",
    companionReply = "gm_companion_reply",
    npcAck = "gm_npc_ack",
    ack = addon.Constants.GAMEMASTER_MESSAGE_ACK,
    assistantCommand = addon.Constants.GAMEMASTER_MESSAGE_ASSISTANT_COMMAND,
    assistantState = addon.Constants.GAMEMASTER_MESSAGE_ASSISTANT_STATE,
    lock = addon.Constants.GAMEMASTER_MESSAGE_LOCK,
    round = addon.Constants.GAMEMASTER_MESSAGE_ROUND,
    session = addon.Constants.GAMEMASTER_MESSAGE_SESSION,
    stop = addon.Constants.GAMEMASTER_MESSAGE_STOP,
    submit = addon.Constants.GAMEMASTER_MESSAGE_SUBMIT,
    syncRequest = addon.Constants.GAMEMASTER_MESSAGE_SYNC_REQUEST,
    preparationInterrupt = addon.Constants.GAMEMASTER_MESSAGE_PREPARATION_INTERRUPT,
    preparationCancel = addon.Constants.GAMEMASTER_MESSAGE_PREPARATION_CANCEL,
    visibility = addon.Constants.GAMEMASTER_MESSAGE_VISIBILITY,
    visibilityChunk = addon.Constants.GAMEMASTER_MESSAGE_VISIBILITY_CHUNK,
    turnComplete = addon.Constants.GAMEMASTER_MESSAGE_TURN_COMPLETE,
}

local function readInteger(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= math.floor(value)
        or value < minimum or value > maximum
    then
        return nil
    end
    return value
end

local function isSafeID(value)
    return type(value) == "string"
        and value ~= ""
        and #value <= addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
        and not value:find("[%c|]")
end

local function createVisibilityTransferID()
    visibilityTransferSerial = visibilityTransferSerial + 1
    if visibilityTransferSerial >= 1000000 then
        visibilityTransferSerial = 1
    end
    return string.format(
        "v-%d-%d",
        math.floor(addon.Runtime.GetMonotonicTime() * 1000),
        visibilityTransferSerial
    )
end

local function createVisibilityChunk(payload, transferID)
    return {
        activationId = payload.activationId,
        buffStates = {},
        controlledNPCs = {},
        readerProfile = payload.readerProfile,
        chunkCount = addon.Constants.GAMEMASTER_MAX_VISIBILITY_CHUNKS,
        chunkIndex = 1,
        entries = {},
        incomingActions = payload.incomingActions ~= nil and {} or nil,
        ownSubmission = {},
        roundId = payload.roundId,
        roundNumber = payload.roundNumber,
        phase = payload.phase,
        sessionId = payload.sessionId,
        stateRevision = payload.stateRevision,
        transferId = transferID,
        visibility = payload.visibility,
    }
end

local function chunkHasContent(chunk)
    return #chunk.entries > 0
        or (chunk.controlledNPCs and #chunk.controlledNPCs > 0)
        or (chunk.incomingActions and #chunk.incomingActions > 0)
        or #chunk.ownSubmission > 0
        or next(chunk.buffStates) ~= nil
end

local function buildVisibilityChunks(payload)
    local transferID = createVisibilityTransferID()
    local chunks = {}
    local current = createVisibilityChunk(payload, transferID)
    local measure = addon.Communication.MeasurePayload
    local budget = measure and measure(current)

    local function flush()
        if #chunks >= addon.Constants.GAMEMASTER_MAX_VISIBILITY_CHUNKS then
            return false
        end
        chunks[#chunks + 1] = current
        current = createVisibilityChunk(payload, transferID)
        budget = measure and measure(current)
        return true
    end

    local function addUnit(add, remove, value, key)
        local cost = measure and measure({ [key or 1] = value }, 1)
        if measure and not cost then return false end
        local function fits()
            if not measure then return addon.Communication.CanSendPayload(current) end
            return budget and budget.bytes + cost.bytes <= addon.Constants.COMMUNICATION_MAX_PAYLOAD_BYTES
                and budget.count + cost.count <= addon.Constants.COMMUNICATION_MAX_PAYLOAD_ENTRIES
        end
        local function accept()
            if measure then budget.bytes, budget.count = budget.bytes + cost.bytes, budget.count + cost.count end
            return true
        end
        add(current)
        if fits() then
            return accept()
        end
        remove(current)
        if not chunkHasContent(current) or not flush() then
            return false
        end
        add(current)
        return fits() and accept()
    end

    for _, entry in ipairs(payload.ownSubmission or {}) do
        if not addUnit(
            function(chunk) chunk.ownSubmission[#chunk.ownSubmission + 1] = entry end,
            function(chunk) chunk.ownSubmission[#chunk.ownSubmission] = nil end, entry
        ) then
            return nil, addon.L("COMMUNICATION_INVALID_MESSAGE")
        end
    end
    for _, entry in ipairs(payload.entries or {}) do
        if not addUnit(
            function(chunk) chunk.entries[#chunk.entries + 1] = entry end,
            function(chunk) chunk.entries[#chunk.entries] = nil end, entry
        ) then
            return nil, addon.L("COMMUNICATION_INVALID_MESSAGE")
        end
    end

    for _, unit in ipairs(payload.controlledNPCs or {}) do
        if not addUnit(
            function(chunk) chunk.controlledNPCs = chunk.controlledNPCs or {}; chunk.controlledNPCs[#chunk.controlledNPCs + 1] = unit end,
            function(chunk) chunk.controlledNPCs[#chunk.controlledNPCs] = nil end, unit
        ) then return nil, addon.L("COMMUNICATION_INVALID_MESSAGE") end
    end

    for _, action in ipairs(payload.incomingActions or {}) do
        if not addUnit(
            function(chunk) chunk.incomingActions[#chunk.incomingActions + 1] = action end,
            function(chunk) chunk.incomingActions[#chunk.incomingActions] = nil end, action
        ) then
            return nil, addon.L("COMMUNICATION_INVALID_MESSAGE")
        end
    end

    local buffKeys = {}
    for playerKey in pairs(payload.buffStates or {}) do
        buffKeys[#buffKeys + 1] = playerKey
    end
    table.sort(buffKeys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    for _, playerKey in ipairs(buffKeys) do
        local entries = payload.buffStates[playerKey]
        if not addUnit(
            function(chunk) chunk.buffStates[playerKey] = entries end,
            function(chunk) chunk.buffStates[playerKey] = nil end, entries, playerKey
        ) then
            return nil, addon.L("COMMUNICATION_INVALID_MESSAGE")
        end
    end

    if chunkHasContent(current) or #chunks == 0 then
        if not flush() then
            return nil, addon.L("COMMUNICATION_INVALID_MESSAGE")
        end
    end
    local chunkCount = #chunks
    for index, chunk in ipairs(chunks) do
        chunk.chunkCount = chunkCount
        chunk.chunkIndex = index
        if not addon.Communication.CanSendPayload(chunk) then
            return nil, addon.L("COMMUNICATION_INVALID_MESSAGE")
        end
    end
    return chunks
end

local function transferMetadataMatches(transfer, payload)
    return transfer.activationId == payload.activationId
        and transfer.chunkCount == payload.chunkCount
        and transfer.roundId == payload.roundId
        and transfer.roundNumber == payload.roundNumber
        and transfer.phase == payload.phase
        and transfer.sessionId == payload.sessionId
        and transfer.stateRevision == payload.stateRevision
        and transfer.visibility == payload.visibility
        and transfer.readerProfile == payload.readerProfile
        and transfer.hasIncoming == (payload.incomingActions ~= nil)
end

local function validateIncoming(payload)
    if payload.incomingActions == nil then return true end
    local incoming = addon.GameMasterIncomingActions
    local clean = incoming and incoming.Validate(payload.incomingActions, payload.roundId, payload.roundNumber)
    return clean ~= nil, clean
end

local function discardTransfer(transfer)
     
    transfer.finished, transfer.parts, transfer.incomingIDs = true, nil, nil
end

local function receiveVisibilityChunk(payload, sender, channel)
    if type(payload) ~= "table"
        or not isSafeID(payload.activationId)
        or not isSafeID(payload.sessionId)
        or not isSafeID(payload.transferId)
        or type(payload.roundId) ~= "string"
        or #payload.roundId > addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
        or payload.roundId:find("[%c|]")
        or not addon.Constants.GAMEMASTER_VISIBILITY_MODES[payload.visibility]
        or (payload.phase ~= nil and payload.phase ~= "players" and payload.phase ~= "enemies")
    then
        return
    end
    local chunkCount = readInteger(
        payload.chunkCount,
        1,
        addon.Constants.GAMEMASTER_MAX_VISIBILITY_CHUNKS
    )
    local chunkIndex = chunkCount and readInteger(payload.chunkIndex, 1, chunkCount)
    local roundNumber = readInteger(
        payload.roundNumber,
        0,
        addon.Constants.MAX_IMPORT_SAFE_INTEGER
    )
    local stateRevision = readInteger(
        payload.stateRevision,
        0,
        addon.Constants.MAX_IMPORT_SAFE_INTEGER
    )
    local entryCount = addon.Runtime.GetBoundedArrayLength(
        payload.entries,
        addon.Constants.GAMEMASTER_MAX_VISIBLE_ACTORS or addon.Constants.GAMEMASTER_MAX_PARTICIPANTS
    )
    local ownCount = addon.Runtime.GetBoundedArrayLength(payload.ownSubmission, 1)
    if not chunkIndex or not roundNumber or not stateRevision
        or not entryCount or not ownCount or type(payload.buffStates) ~= "table"
    then
        return
    end

    local service = addon.GameMasterService
    if service and service.initialized then
        local state = service.GetRemoteSession()
         
        if not state or addon.Runtime.NormalizePlayerID(sender) ~= state.gameMasterKey
            or payload.sessionId ~= state.sessionID or payload.activationId ~= state.activationID
            or not addon.GameMasterRoster.IsMember(sender) then return end
    end

    local senderKey = addon.Runtime.NormalizePlayerID(sender)
    local key = senderKey and (senderKey .. "\031" .. payload.transferId) or nil
    if not key then
        return
    end
    local transfer = visibilityTransfers:Get(key)
    if transfer and addon.Runtime.GetMonotonicTime() - transfer.createdAt
        >= addon.Constants.GAMEMASTER_VISIBILITY_TRANSFER_TTL then
        visibilityTransfers:Remove(key)
        transfer = nil
    end
    if transfer and transfer.finished then return end
    local incomingValid, incomingActions = validateIncoming(payload)
    if not incomingValid then
        if transfer then discardTransfer(transfer) end
        return
    end
    if not transfer then
        transfer = {
            activationId = payload.activationId,
            readerProfile = payload.readerProfile,
            chunkCount = chunkCount,
            createdAt = addon.Runtime.GetMonotonicTime(),
            hasIncoming = payload.incomingActions ~= nil,
            incomingCount = 0,
            incomingIDs = {},
            parts = {},
            received = 0,
            roundId = payload.roundId,
            roundNumber = roundNumber,
            phase = payload.phase,
            sessionId = payload.sessionId,
            stateRevision = stateRevision,
            visibility = payload.visibility,
        }
        visibilityTransfers:Set(key, transfer)
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(
                addon.Constants.GAMEMASTER_VISIBILITY_TRANSFER_TTL,
                function()
                    if visibilityTransfers:Get(key) == transfer
                        and addon.Runtime.GetMonotonicTime() - transfer.createdAt
                            >= addon.Constants.GAMEMASTER_VISIBILITY_TRANSFER_TTL
                    then
                        visibilityTransfers:Remove(key)
                    end
                end
            )
        end
    elseif not transferMetadataMatches(transfer, payload) then
        discardTransfer(transfer)
        return
    end
    if transfer.parts[chunkIndex] then
        return
    end
    if incomingActions then
        if transfer.incomingCount + #incomingActions > addon.Constants.GAMEMASTER_MAX_INCOMING_ACTIONS then
            discardTransfer(transfer)
            return
        end
        for _, action in ipairs(incomingActions) do
            if transfer.incomingIDs[action.id] then
                discardTransfer(transfer)
                return
            end
            transfer.incomingIDs[action.id] = true
        end
        transfer.incomingCount = transfer.incomingCount + #incomingActions
    end
    transfer.parts[chunkIndex] = {
        controlledNPCs = payload.controlledNPCs,
        buffStates = payload.buffStates,
        entries = payload.entries,
        incomingActions = incomingActions,
        ownSubmission = payload.ownSubmission,
    }
    transfer.received = transfer.received + 1
    if transfer.received < transfer.chunkCount then
        return
    end

    local merged = {
        controlledNPCs = {},
        activationId = transfer.activationId,
        readerProfile = transfer.readerProfile,
        buffStates = {},
        entries = {},
        incomingActions = transfer.hasIncoming and {} or nil,
        ownSubmission = {},
        roundId = transfer.roundId,
        roundNumber = transfer.roundNumber,
        phase = transfer.phase,
        sessionId = transfer.sessionId,
        stateRevision = transfer.stateRevision,
        visibility = transfer.visibility,
    }
    local buffCount = 0
    for index = 1, transfer.chunkCount do
        local part = transfer.parts[index]
        if not part then
            return
        end
        for _, entry in ipairs(part.entries) do
            if #merged.entries >= (addon.Constants.GAMEMASTER_MAX_VISIBLE_ACTORS or addon.Constants.GAMEMASTER_MAX_PARTICIPANTS) then
                discardTransfer(transfer)
                return
            end
            merged.entries[#merged.entries + 1] = entry
        end
        for _, entry in ipairs(part.ownSubmission) do
            if #merged.ownSubmission >= 1 then
                discardTransfer(transfer)
                return
            end
            merged.ownSubmission[#merged.ownSubmission + 1] = entry
        end
        for _, action in ipairs(part.incomingActions or {}) do
            merged.incomingActions[#merged.incomingActions + 1] = action
        end
        local controlCount = addon.Runtime.GetBoundedArrayLength(part.controlledNPCs or {}, 500)
        if not controlCount or #merged.controlledNPCs + controlCount > 500 then discardTransfer(transfer); return end
        for _, unit in ipairs(part.controlledNPCs or {}) do merged.controlledNPCs[#merged.controlledNPCs + 1] = unit end
        for playerKey, entries in pairs(part.buffStates) do
            if merged.buffStates[playerKey] ~= nil then
                discardTransfer(transfer)
                return
            end
            buffCount = buffCount + 1
            if buffCount > (addon.Constants.GAMEMASTER_MAX_VISIBLE_ACTORS or addon.Constants.GAMEMASTER_MAX_PARTICIPANTS) then
                discardTransfer(transfer)
                return
            end
            merged.buffStates[playerKey] = entries
        end
    end
    discardTransfer(transfer)
    local valid, cleaned = validateIncoming(merged)
    if not valid then return end
    merged.incomingActions = cleaned
    dispatch("visibility", merged, sender, channel)
end

dispatch = function(eventName, payload, sender, channel)
    local callbacks = handlers[eventName]
    if not callbacks then
        return
    end
    for _, callback in ipairs(callbacks) do
        local success, errorMessage = addon.Runtime.SafeInvoke(
            callback,
            payload,
            sender,
            channel
        )
        if not success then
            addon.Logger.Error(tostring(errorMessage))
        end
    end
end

function addon.GameMasterProtocol.Initialize()
    if addon.GameMasterProtocol.initialized then
        return true
    end
    for eventName, messageType in pairs(messageTypes) do
        local registered, errorMessage = addon.Communication.RegisterHandler(
            messageType,
            function(payload, sender, channel)
                if eventName == "visibilityChunk" then
                    receiveVisibilityChunk(payload, sender, channel)
                else
                    if eventName == "visibility" and type(payload) == "table" then
                        local valid, cleaned = validateIncoming(payload)
                        if not valid then return end
                        payload.incomingActions = cleaned
                    end
                    dispatch(eventName, payload, sender, channel)
                end
            end
        )
        if not registered then
            return false, errorMessage
        end
    end
    addon.GameMasterProtocol.initialized = true
    return true
end

function addon.GameMasterProtocol.RegisterHandler(eventName, callback)
    if not messageTypes[eventName] or type(callback) ~= "function" then
        return false
    end
    if not handlers[eventName] then
        handlers[eventName] = {}
    end
    handlers[eventName][#handlers[eventName] + 1] = callback
    return true
end

local function sameVisibilityContext(left, right)
    return left.activationId == right.activationId and left.sessionId == right.sessionId
        and left.roundId == right.roundId and left.phase == right.phase
        and left.readerProfile == right.readerProfile
end

function addon.GameMasterProtocol.CancelVisibility(target)
    if target then outgoingVisibility:Remove(addon.Runtime.NormalizePlayerID(target))
    else outgoingVisibility:Clear() end
end

local function queueVisibility(target, payload, packets, chunked, priority)
    local key = addon.Runtime.NormalizePlayerID(target)
    if not key then return false, addon.L("COMMUNICATION_INVALID_TARGET") end
    local record = outgoingVisibility:Get(key)
    if record and not sameVisibilityContext(record.payload, payload) then
        outgoingVisibility:Remove(key)
        record = nil
    end
    local metadata = { activationId = payload.activationId, sessionId = payload.sessionId,
        roundId = payload.roundId, phase = payload.phase, readerProfile = payload.readerProfile,
        stateRevision = payload.stateRevision }
    local latest = { payload = metadata, packets = packets, chunked = chunked, priority = priority }
    if record then
        if (payload.stateRevision or 0) < (record.payload.stateRevision or 0) then return true end
        if record.index == 1 then
            record.payload, record.packets, record.chunked, record.priority = metadata, packets, chunked, priority
        elseif not record.next or (payload.stateRevision or 0) >= (record.next.payload.stateRevision or 0) then
            record.next = latest
        end
        return true
    end
    record = latest
    record.index = 1
    outgoingVisibility:Set(key, record)
    local function schedule()
        local synchronous = true
        C_Timer.After(0.25, function()
            if outgoingVisibility:Get(key) ~= record then return end
             
            local allowance = synchronous and #record.packets or record.chunked and 4 or 1
            for _ = 1, allowance do
                local packet = record.packets[record.index]
                if not packet then break end
                local ok, err = addon.Communication.Send(target,
                    record.chunked and messageTypes.visibilityChunk or messageTypes.visibility,
                    packet, record.priority or "MEDIUM")
                if not ok then
                    outgoingVisibility:Remove(key)
                    addon.Logger.Error(err or addon.L("COMMUNICATION_SEND_FAILED"))
                    return
                end
                record.index = record.index + 1
            end
            if record.index > #record.packets then
                local nextState = record.next
                if not nextState then outgoingVisibility:Remove(key); return end
                record.payload, record.packets, record.chunked, record.priority =
                    nextState.payload, nextState.packets, nextState.chunked, nextState.priority
                record.index, record.next = 1, nil
            end
            schedule()
        end)
        synchronous = false
    end
    schedule()
    return true
end

function addon.GameMasterProtocol.Send(target, eventName, payload, priority)
    local messageType = messageTypes[eventName]
    if not messageType then
        return false, addon.L("COMMUNICATION_INVALID_MESSAGE")
    end
    if eventName == "stop" or eventName == "round" or eventName == "session" then
        outgoingVisibility:Remove(addon.Runtime.NormalizePlayerID(target))
    end
    if eventName ~= "submit" and addon.GameMasterVisibility
        and addon.GameMasterVisibility.LegacyPermanentPayload
        and not addon.GameMasterProtocol.SupportsPermanentEffects(target) then
        payload = addon.GameMasterVisibility.LegacyPermanentPayload(payload)
    end
    if eventName == "visibility" and type(payload) == "table" then
        local valid, cleaned = validateIncoming(payload)
        if not valid then return false, addon.L("COMMUNICATION_INVALID_MESSAGE") end
        if payload.incomingActions ~= nil then
            local copy = {}
            for key, value in pairs(payload) do copy[key] = value end
            copy.incomingActions = cleaned
            payload = copy
        end
    end
    if eventName == "visibility"
        and not addon.Communication.CanSendPayload(payload)
    then
        if not addon.GameMasterProtocol.SupportsSegmentedVisibility(target) then
            return false, addon.L("COMMUNICATION_INVALID_MESSAGE")
        end
        local chunks, chunkError = buildVisibilityChunks(payload)
        if not chunks then
            return false, chunkError
        end
        if C_Timer and C_Timer.After then return queueVisibility(target, payload, chunks, true, priority) end
        for _, chunk in ipairs(chunks) do
            local sent, errorMessage = addon.Communication.Send(
                target,
                messageTypes.visibilityChunk,
                chunk,
                priority or "MEDIUM"
            )
            if not sent then
                return false, errorMessage
            end
        end
        return true
    end
    if eventName == "visibility" and C_Timer and C_Timer.After then
        return queueVisibility(target, payload, { payload }, false, priority)
    end
    return addon.Communication.Send(
        target,
        messageType,
        payload,
        priority or "MEDIUM"
    )
end

function addon.GameMasterProtocol.SupportsSegmentedVisibility(playerID)
    return addon.Communication.HasCapability(
        playerID,
        addon.Constants.GAMEMASTER_SEGMENTED_VISIBILITY_CAPABILITY
    )
end

function addon.GameMasterProtocol.SupportsTurns(playerID)
    return addon.Communication.HasCapability(
        playerID,
        addon.Constants.GAMEMASTER_TURN_CAPABILITY
    )
end

function addon.GameMasterProtocol.SupportsNPCs(playerID)
    return addon.Communication.HasKnownCapability(playerID, "gamemaster-npc-v1")
end

function addon.GameMasterProtocol.SupportsDebuffs(playerID)
    return addon.Communication.HasKnownCapability(
        playerID,
        addon.Constants.GAMEMASTER_DEBUFF_CAPABILITY
    )
end

function addon.GameMasterProtocol.SupportsPermanentEffects(playerID)
    return addon.Communication.HasKnownCapability(
        playerID, addon.Constants.GAMEMASTER_PERMANENT_CAPABILITY)
end

function addon.GameMasterProtocol.SupportsIncoming(playerID)
    return addon.Communication.HasKnownCapability(
        playerID,
        addon.Constants.GAMEMASTER_INCOMING_CAPABILITY
    )
end

function addon.GameMasterProtocol.SupportsTurnsKnown(playerID)
    return addon.Communication.HasKnownCapability(
        playerID,
        addon.Constants.GAMEMASTER_TURN_CAPABILITY
    )
end

function addon.GameMasterProtocol.SupportsOriginQueue(playerID)
    return addon.Communication.HasCapability(
        playerID,
        addon.Constants.GAMEMASTER_ORIGIN_QUEUE_CAPABILITY
    )
end

function addon.GameMasterProtocol.SupportsOriginQueueKnown(playerID)
    return addon.Communication.HasKnownCapability(
        playerID,
        addon.Constants.GAMEMASTER_ORIGIN_QUEUE_CAPABILITY
    )
end

function addon.GameMasterProtocol.Query(target)
    return addon.Communication.QueryPeer(target)
end

function addon.GameMasterProtocol.Supports(playerID)
    return addon.Communication.HasCapability(
        playerID,
        addon.Constants.GAMEMASTER_CAPABILITY
    )
end
function addon.GameMasterProtocol.SupportsDelegation(playerID)
    return addon.Communication.HasCapability(
        playerID,
        addon.Constants.GAMEMASTER_DELEGATION_CAPABILITY
    )
end


function addon.GameMasterProtocol.SupportsKnown(playerID)
    return addon.Communication.HasKnownCapability(
        playerID,
        addon.Constants.GAMEMASTER_CAPABILITY
    )
end

function addon.GameMasterProtocol.GetPeer(playerID)
    return addon.Communication.GetPeer(playerID)
end

function addon.GameMasterProtocol.RegisterPeerListener(callback)
    return addon.Communication.RegisterPeerListener(callback)
end
