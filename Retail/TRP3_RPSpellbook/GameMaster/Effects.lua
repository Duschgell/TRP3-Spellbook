local _, addon = ...

addon.GameMasterEffects = {}

local listeners = {}
local expirationTimer
local timerGeneration = 0
local countdownConsumers = {}
local MAX_NPC_ACTORS = 20

local function isNPCID(value)
    local actors = addon.GameMasterNPCActors
    return type(actors) == "table"
        and type(actors.IsID) == "function"
        and actors.IsID(value) == true
end

local function normalizePlayerKey(value)
    local key = addon.Runtime.NormalizePlayerID(value)
     
    return key and not key:find("^npc_") and key or nil
end

local function normalizeActorKey(value)
    if not addon.Runtime.IsSafeIdentifier(
        value,
        addon.Constants.MAX_LINK_OWNER_LENGTH
    ) then
        return nil
    end
    return isNPCID(value) and value or normalizePlayerKey(value)
end

local function getNPC(session, id)
    if type(session) ~= "table" or not isNPCID(id) then
        return nil
    end
    local actors = addon.GameMasterNPCActors
    local actor = type(actors.Get) == "function" and actors.Get(session, id) or nil
    return type(actor) == "table" and actor.id == id
        and actor.kind == "npc" and actor or nil
end

local function getReleasedNPC(session, id)
    local actor = getNPC(session, id)
    return actor and actor.released == true and actor or nil
end

local function isPublicActor(session, id)
    if isNPCID(id) then
        return getReleasedNPC(session, id) ~= nil
    end
    return normalizeActorKey(id) ~= nil
end

local function forEachRoundSubmission(session, round, callback)
    local function visit(submissions, order, npc, maximum)
        if type(submissions) ~= "table" then return end
        local processed, count = {}, 0
        local function process(id, submission)
            local key
            if npc then
                key = getReleasedNPC(session, id) and id or nil
            else
                key = normalizePlayerKey(id)
            end
            if not key or processed[key] or count >= maximum
                or type(submission) ~= "table"
            then
                return
            end
            processed[key], count = true, count + 1
            callback(key, submission, npc)
        end
        for _, id in ipairs(type(order) == "table" and order or {}) do
            process(id, submissions[id])
            if count >= maximum then return end
        end
        for id, submission in pairs(submissions) do
            process(id, submission)
            if count >= maximum then return end
        end
    end
    visit(round.submissions, session.participantOrder, false,
        addon.Constants.GAMEMASTER_MAX_PARTICIPANTS)
    visit(round.npcSubmissions, session.npcOrder, true, MAX_NPC_ACTORS)
end

local function notifyListeners(reason)
    for _, listener in ipairs(listeners) do
        addon.Runtime.SafeInvoke(listener, reason)
    end
end

local function isActionApplied(action)
    return action == "cast" or action == "channel"
end

local function playerIDsMatch(first, second)
    local firstKey = normalizePlayerKey(first)
    local secondKey = normalizePlayerKey(second)
    if not firstKey or not secondKey then
        return false
    end
    if firstKey == secondKey then
        return true
    end
    local firstName = firstKey:match("^([^-]+)")
    local secondName = secondKey:match("^([^-]+)")
    return firstName ~= nil
        and firstName == secondName
        and (not firstKey:find("-", 1, true)
            or not secondKey:find("-", 1, true))
end

addon.GameMasterEffects.PlayerIDsMatch = playerIDsMatch

local function buildMemberIndex()
    local members = addon.GameMasterRoster
        and addon.GameMasterRoster.GetMembers()
        or {}
    local indexed = {}
    for _, member in ipairs(members) do
        local playerKey = type(member) == "table"
            and normalizePlayerKey(member.playerID)
            or nil
        if playerKey then
            indexed[playerKey] = member
        end
    end
    return members, indexed
end

local function findMember(members, indexed, playerID)
    local playerKey = normalizePlayerKey(playerID)
    if not playerKey then
        return nil
    end
    if indexed[playerKey] then
        return indexed[playerKey]
    end
    local match
    for _, member in ipairs(members) do
        if type(member) == "table"
            and playerIDsMatch(playerID, member.playerID)
        then
            if match then return nil end
            match = member
        end
    end
    return match
end

local function getFirstName(member, fallback)
    if type(member) == "table"
        and type(member.firstName) == "string"
        and member.firstName:match("%S")
    then
        return member.firstName
    end
    local rpName = type(member) == "table" and member.rpName or nil
    if type(rpName) == "string" and rpName:match("%S") then
        return rpName:match("^%s*([^%s]+)") or rpName
    end
    local name = tostring(fallback or "?"):match("^([^-]+)")
    return name or "?"
end

local function actorIdentity(profile)
    if type(profile) ~= "table" then return nil end
    return {
        firstName = profile.name, fullName = profile.name, lastName = profile.name,
        race = profile.race, class = profile.class, title = profile.title,
    }
end

function addon.GameMasterEffects.NotifyTargets(submission, casterID, session, delivery)
    local spell = type(submission) == "table" and submission.spell or nil
    local effects = type(spell) == "table" and spell.effects or nil
    if type(submission) ~= "table"
        or not isActionApplied(submission.action)
        or type(effects) ~= "table"
        or (effects.buff ~= true and effects.debuff ~= true
            and effects.healing ~= true)
        or not addon.ChatFallbacks
    then
        return false, 0
    end

    local members, memberIndex = buildMemberIndex()
    local localID = addon.GameMasterRoster.GetLocalPlayerID()
    casterID = casterID or localID
    local casterName, casterProfile
    if isNPCID(casterID) then
        local actor = getReleasedNPC(session, casterID)
        local profile = actor and addon.GameMasterNPCActors.Profile(actor)
        casterProfile = profile
        casterName = type(profile) == "table" and profile.name or nil
        if type(casterName) ~= "string" or casterName == "" then
            return false, 0
        end
    elseif not normalizePlayerKey(casterID) then
        return false, 0
    end
    local casterMember = findMember(members, memberIndex, casterID)
    local sent = 0
    local seen = {}
    for index, target in ipairs(
        addon.GameMasterActionPresentation.GetTargets(submission)
    ) do
        if index > addon.Constants.GAMEMASTER_MAX_TARGETS then break end
        local targetID = type(target) == "table"
            and target.kind == "player"
            and target.value
            or nil
        local targetMember = targetID
            and findMember(members, memberIndex, targetID)
            or nil
        local targetActor = type(target) == "table" and target.kind == "npc"
            and getReleasedNPC(session, target.value) or nil
        local targetProfile
        if targetActor then
            local ownerKey = normalizePlayerKey(targetActor.ownerPlayerKey or session.ownerKey)
             
            targetMember = ownerKey and memberIndex[ownerKey] or nil
            local profile = addon.GameMasterNPCActors.Profile(targetActor)
            if type(profile) == "table" and type(profile.name) == "string"
                and profile.name ~= "" then
                targetProfile = profile
            else
                targetMember = nil
            end
        end
        targetID = targetMember and targetMember.playerID or nil
         
        local targetKey = targetActor and targetActor.id or normalizePlayerKey(targetID)
        if targetKey
            and targetMember
            and not seen[targetKey]
            and (targetActor ~= nil or not playerIDsMatch(targetID, casterID))
            and not (delivery and delivery.targets[targetKey])
        then
            seen[targetKey] = true
            local message = addon.WhisperTemplates.Build(spell, {
                playerID = casterMember and casterMember.playerID or casterID, targetID = targetID,
                playerIdentity = actorIdentity(casterProfile),
                targetIdentity = actorIdentity(targetProfile),
            })
            if message then
                local success, accepted = addon.Runtime.SafeInvoke(
                    addon.ChatFallbacks.SendEffectWhisper,
                    targetID,
                    message,
                    table.concat({
                        tostring(normalizeActorKey(casterID)),
                        tostring(spell.id or spell.name),
                        tostring(submission.action),
                        targetKey,
                        delivery and delivery.key or tostring(submission),
                    }, "\031"),
                    casterName or getFirstName(casterMember, casterID)
                )
                if success and accepted then
                    if delivery then delivery.targets[targetKey] = true end
                    sent = sent + 1
                elseif not success and addon.Logger then
                    addon.Runtime.SafeInvoke(
                        addon.Logger.Error,
                        "Game Master effect whisper failed."
                    )
                end
            end
        end
    end
    return sent > 0, sent
end

local function getWhisperReceipt(previous, round, playerKey, action, index)
    local key = table.concat({
        tostring(round.id), playerKey, tostring(index),
        tostring(action.submissionId or ""), tostring(action.submittedAt or ""),
        tostring(action.spell.id or action.spell.name),
        tostring(action.spell.revision or ""), tostring(action.action),
    }, "\031")
    local receipt = { key = key, targets = {} }
    if type(previous) == "table" and previous.key == key
        and type(previous.targets) == "table"
    then
        local count = 0
        for targetKey, sent in pairs(previous.targets) do
            if sent == true and normalizeActorKey(targetKey) == targetKey then
                receipt.targets[targetKey] = true
                count = count + 1
                if count >= addon.Constants.GAMEMASTER_MAX_TARGETS then break end
            end
        end
    end
    return receipt
end

function addon.GameMasterEffects.NotifyRoundTargets(session, round)
    if type(session) ~= "table"
        or type(round) ~= "table"
    then
        return false, 0
    end

    local sent = 0
    local previous = type(round.effectWhispers) == "table" and round.effectWhispers or {}
     
     
    round.effectWhispers = {}
    forEachRoundSubmission(session, round, function(playerKey, submission, npc)
        local participant = type(session.participants) == "table"
            and session.participants[playerKey]
            or nil
        local casterID = npc and playerKey or (type(participant) == "table"
            and participant.playerID
            or (type(submission) == "table" and submission.playerID)
            or playerKey)
        if not npc and not normalizePlayerKey(casterID) then return end
        local receipts = {}
        round.effectWhispers[playerKey] = receipts
        local previousReceipts = type(previous[playerKey]) == "table"
            and previous[playerKey] or {}
        for index, action in ipairs(
            addon.GameMasterActionCollection.Get(submission)
        ) do
            local receipt = getWhisperReceipt(previousReceipts[index], round, playerKey, action, index)
            receipts[index] = receipt
            local _, actionSent = addon.GameMasterEffects.NotifyTargets(
                action,
                casterID,
                session,
                receipt
            )
            sent = sent + actionSent
        end
    end)
    return sent > 0, sent
end

local function findParticipantKey(session, playerID)
    if isNPCID(playerID) then
        return getNPC(session, playerID) and playerID or nil
    end
    local normalized = normalizePlayerKey(playerID)
    if not normalized or type(session.participants) ~= "table" then
        return nil
    end
    if session.participants[normalized] then
        return normalized
    end
    local match
    for playerKey, participant in pairs(session.participants) do
        if normalizePlayerKey(playerKey) and playerIDsMatch(
            playerID,
            type(participant) == "table" and participant.playerID or playerKey
        ) then
            if match then
                return nil
            end
            match = playerKey
        end
    end
    return match
end

addon.GameMasterEffects.FindParticipantKey = findParticipantKey

local function removeSourceRound(session, sourcePlayerKey, roundID)
    local changed = false
    for targetKey, entries in pairs(
        type(session.activeBuffs) == "table" and session.activeBuffs or {}
    ) do
        if type(entries) ~= "table" then
            session.activeBuffs[targetKey] = nil
            changed = true
        else
            for index = #entries, 1, -1 do
                local entry = entries[index]
                if type(entry) ~= "table"
                    or (entry.sourcePlayerKey == sourcePlayerKey
                        and entry.sourceRoundID == roundID)
                then
                    table.remove(entries, index)
                    changed = true
                end
            end
            if #entries == 0 then
                session.activeBuffs[targetKey] = nil
            end
        end
    end
    return changed
end

function addon.GameMasterEffects.DiscardSourceRound(
    session,
    sourcePlayerKey,
    roundID
)
    sourcePlayerKey = normalizeActorKey(sourcePlayerKey)
    if type(session) ~= "table"
        or not sourcePlayerKey
        or type(roundID) ~= "string"
    then
        return false
    end
    return removeSourceRound(session, sourcePlayerKey, roundID)
end

function addon.GameMasterEffects.Prune(session, roundNumber, timestamp)
    if type(session) ~= "table" or type(session.activeBuffs) ~= "table" then
        return false
    end
    local participants = type(session.participants) == "table"
        and session.participants or {}
    roundNumber = tonumber(roundNumber) or math.huge
    timestamp = tonumber(timestamp) or addon.Runtime.GetTimestamp()
    local changed = false
    for playerKey, entries in pairs(session.activeBuffs) do
        local knownTarget = isNPCID(playerKey) and getNPC(session, playerKey)
            or (normalizePlayerKey(playerKey) and participants[playerKey])
        if type(entries) ~= "table" or not knownTarget then
            session.activeBuffs[playerKey] = nil
            changed = true
        else
            for index = #entries, 1, -1 do
                local entry = entries[index]
                if type(entry) ~= "table"
                    or type(entry.spell) ~= "table"
                    or (entry.expiresRound
                        and roundNumber >= entry.expiresRound)
                    or (entry.expiresAt
                        and timestamp >= entry.expiresAt)
                then
                    table.remove(entries, index)
                    changed = true
                end
            end
            if #entries == 0 then
                session.activeBuffs[playerKey] = nil
            end
        end
    end
    return changed
end

function addon.GameMasterEffects.ApplySubmission(
    session,
    sourcePlayerKey,
    submission,
    round,
    sourceRoundID,
    preserveSourceRound
)
    sourcePlayerKey = normalizeActorKey(sourcePlayerKey)
    if type(session) ~= "table" or type(round) ~= "table"
        or not sourcePlayerKey
        or (isNPCID(sourcePlayerKey)
            and not getReleasedNPC(session, sourcePlayerKey))
    then
        return false
    end
    session.activeBuffs = type(session.activeBuffs) == "table"
        and session.activeBuffs
        or {}
    sourceRoundID = type(sourceRoundID) == "string"
        and sourceRoundID
        or round.id
    local changed = false
    if preserveSourceRound ~= true then
        changed = removeSourceRound(session, sourcePlayerKey, sourceRoundID)
    end
    local spell = type(submission) == "table" and submission.spell or nil
    local effects = type(spell) == "table" and spell.effects or nil
    local durationRounds = type(effects) == "table"
        and tonumber(effects.durationRounds)
        or nil
    local durationSeconds = type(effects) == "table"
        and tonumber(effects.durationSeconds)
        or nil
    local permanent = durationRounds == addon.Constants.EFFECT_DURATION_PERMANENT
    if type(submission) ~= "table"
        or not isActionApplied(submission.action)
        or type(effects) ~= "table"
        or (effects.buff ~= true and effects.debuff ~= true)
        or (not durationRounds and not durationSeconds)
    then
        return changed
    end
    if permanent and session.permanentEffectsEndedAtRound
        and round.number <= session.permanentEffectsEndedAtRound + 1
        and sourceRoundID ~= round.id then
        local id = submission.submissionId
        local stopped = session.permanentEffectsStoppedSubmissions or {}
        if not id or stopped[sourcePlayerKey .. "\031" .. id] then return changed end
    end

    local timestamp = addon.Runtime.GetTimestamp()
    local seen = {}
    for index, target in ipairs(
        addon.GameMasterActionPresentation.GetTargets(submission)
    ) do
        if index > addon.Constants.GAMEMASTER_MAX_TARGETS then break end
        local playerKey
        if type(target) == "table" then
            if target.kind == "npc" then
                playerKey = getReleasedNPC(session, target.value) and target.value or nil
            elseif target.kind == "player" then
                playerKey = normalizePlayerKey(target.value)
                    and findParticipantKey(session, target.value) or nil
            end
        end
        if playerKey and not seen[playerKey] then
            seen[playerKey] = true
            local entries = type(session.activeBuffs[playerKey]) == "table"
                and session.activeBuffs[playerKey] or {}
            session.activeBuffs[playerKey] = entries
            local identity = table.concat({
                tostring(sourcePlayerKey),
                tostring(spell.id or spell.name),
            }, "\031")
            for index = #entries, 1, -1 do
                if type(entries[index]) ~= "table" or entries[index].identity == identity then
                    table.remove(entries, index)
                end
            end
            entries[#entries + 1] = {
                appliedAt = timestamp,
                appliedRound = round.number,
                expiresAt = durationSeconds and timestamp + durationSeconds or nil,
                expiresRound = durationRounds and not permanent and round.number + durationRounds or nil,
                identity = identity,
                sourcePlayerKey = sourcePlayerKey,
                sourceRoundID = sourceRoundID,
                spell = spell,
            }
            while #entries
                > addon.Constants.GAMEMASTER_MAX_ACTIVE_BUFFS_PER_PLAYER
            do
                table.remove(entries, 1)
            end
            changed = true
        end
    end
    if changed then
        session.updatedAt = timestamp
    end
    return changed
end

function addon.GameMasterEffects.ApplyRoundSubmissions(
    session,
    sourceRound,
    activationRound
)
    if type(session) ~= "table"
        or type(sourceRound) ~= "table"
        or type(activationRound) ~= "table"
        or type(sourceRound.number) ~= "number"
        or sourceRound.number < 1
        or sourceRound.number ~= math.floor(sourceRound.number)
        or sourceRound.number == math.huge
        or activationRound.number ~= sourceRound.number + 1
        or activationRound.id == sourceRound.id
        or activationRound.phase == "enemies"
    then
        return false
    end

    local changed = false
    forEachRoundSubmission(session, sourceRound, function(playerKey, submission)
        changed = removeSourceRound(session, playerKey, sourceRound.id) or changed
        for _, action in ipairs(
            addon.GameMasterActionCollection.Get(submission)
        ) do
            changed = addon.GameMasterEffects.ApplySubmission(
                session,
                playerKey,
                action,
                activationRound,
                sourceRound.id,
                true
            ) or changed
        end
    end)
    return changed
end

function addon.GameMasterEffects.GetActiveBuffs(
    session,
    playerKey,
    roundNumber,
    alreadyPruned
)
    local currentRound = type(session) == "table"
        and addon.GameMasterStore.GetCurrentRound(session)
        or nil
    if not alreadyPruned then
        addon.GameMasterEffects.Prune(
            session,
            roundNumber or (currentRound and currentRound.number),
            addon.Runtime.GetTimestamp()
        )
    end
    local entries = type(session) == "table"
        and type(session.activeBuffs) == "table"
        and session.activeBuffs[playerKey]
        or nil
    return type(entries) == "table" and entries or {}
end
function addon.GameMasterEffects.RemoveActiveBuff(
    session,
    playerKey,
    sourcePlayerKey,
    spellID
)
    local entries = type(session) == "table"
        and type(session.activeBuffs) == "table"
        and session.activeBuffs[playerKey]
        or nil
    local normalizedSource = normalizeActorKey(sourcePlayerKey)
    if type(entries) ~= "table"
        or not normalizedSource
        or type(spellID) ~= "string"
        or spellID == ""
    then
        return false
    end
    for index = #entries, 1, -1 do
        local entry = entries[index]
        if type(entry) == "table"
            and entry.sourcePlayerKey == normalizedSource
            and type(entry.spell) == "table"
            and entry.spell.id == spellID
        then
            table.remove(entries, index)
            if #entries == 0 then
                session.activeBuffs[playerKey] = nil
            end
            session.updatedAt = addon.Runtime.GetTimestamp()
            return true
        end
    end
    return false
end
local function copyBuffs(session, entries)
    local copied = {}
    for index, entry in ipairs(type(entries) == "table" and entries or {}) do
        if index > addon.Constants.GAMEMASTER_MAX_ACTIVE_BUFFS_PER_PLAYER then break end
        if type(entry) == "table" and isPublicActor(session, entry.sourcePlayerKey)
            and type(entry.spell) == "table"
            and (not isNPCID(entry.spell.ownerKey)
                or getReleasedNPC(session, entry.spell.ownerKey))
        then
            copied[#copied + 1] = {
                appliedAt = entry.appliedAt,
                appliedRound = entry.appliedRound,
                expiresAt = entry.expiresAt,
                expiresRound = entry.expiresRound,
                identity = entry.identity,
                sourcePlayerKey = entry.sourcePlayerKey,
                sourceRoundID = entry.sourceRoundID,
                spell = entry.spell,
                hidden = entry.hidden == true, ownerProfile = entry.ownerProfile, readers = entry.readers,
            }
        end
    end
    return copied
end

function addon.GameMasterEffects.CopyActiveBuffs(session, playerKey)
    if not isPublicActor(session, playerKey) then return {} end
    local entries = copyBuffs(
        session,
        addon.GameMasterEffects.GetActiveBuffs(session, playerKey)
    )
     
    for _, entry in ipairs(entries) do entry.readers = nil end
    return entries
end

function addon.GameMasterEffects.BuildSharedBuffStates(session, onlyPlayerKey)
    local states = {}
    if type(session) ~= "table" then
        return states
    end
    local round = addon.GameMasterStore.GetCurrentRound(session)
    addon.GameMasterEffects.Prune(
        session,
        round and round.number,
        addon.Runtime.GetTimestamp()
    )
    local seen = {}
    local function appendStates(order, npc, maximum)
        local count = 0
        for _, playerKey in ipairs(type(order) == "table" and order or {}) do
            local eligible = npc and getReleasedNPC(session, playerKey)
                or (not npc and normalizePlayerKey(playerKey))
            if eligible and not seen[playerKey] then
                seen[playerKey], count = true, count + 1
                if not onlyPlayerKey or playerKey == onlyPlayerKey then
                    local buffs = copyBuffs(
                        session,
                        type(session.activeBuffs) == "table"
                            and session.activeBuffs[playerKey]
                            or nil
                    )
                    if #buffs > 0 then
                        states[#states + 1] = {
                            buffs = buffs,
                            playerKey = playerKey,
                        }
                    end
                end
                if count >= maximum then return end
            end
        end
    end
    appendStates(session.participantOrder, false,
        addon.Constants.GAMEMASTER_MAX_PARTICIPANTS)
    appendStates(session.npcOrder, true, MAX_NPC_ACTORS)
    return states
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


function addon.GameMasterEffects.ValidateSharedBuffs(raw)
    if raw == nil then
        return {}
    end
    if type(raw) ~= "table" then
        return nil
    end
    local maximumEntries = addon.Constants
        .GAMEMASTER_MAX_ACTIVE_BUFFS_PER_PLAYER
    local entryCount = addon.Runtime.GetBoundedArrayLength(raw, maximumEntries)
    if not entryCount then
        return nil
    end

    local cleaned = {}
    for index = 1, entryCount do
        local entry = raw[index]
        local valid, spell
        if type(entry) == "table" then
            valid, spell = addon.Validators.ValidateSpell(entry.spell)
        end
        if not valid
            or type(spell.effects) ~= "table"
            or (spell.effects.buff ~= true and spell.effects.debuff ~= true)
        then
            return nil
        end

        local maximum = addon.Constants.MAX_IMPORT_SAFE_INTEGER
        spell.id = addon.Runtime.IsSafeIdentifier(
            entry.spell.id,
            addon.Constants.MAX_LINK_SPELL_ID_LENGTH
        ) and entry.spell.id or nil
        spell.ownerKey = addon.Runtime.IsSafeIdentifier(
            entry.spell.ownerKey,
            addon.Constants.MAX_LINK_OWNER_LENGTH
        ) and entry.spell.ownerKey or nil
        spell.revision = readInteger(
            entry.spell.revision,
            1,
            addon.Constants.MAX_LINK_REVISION
        )
        local appliedAt = readInteger(entry.appliedAt, 0, maximum)
        local appliedRound = readInteger(entry.appliedRound, 1, maximum)
        local expiresAt = entry.expiresAt ~= nil
            and readInteger(entry.expiresAt, 1, maximum)
            or nil
        local expiresRound = entry.expiresRound ~= nil
            and readInteger(entry.expiresRound, 1, maximum)
            or nil
        local sourcePlayerKey = addon.Runtime.IsSafeIdentifier(
            entry.sourcePlayerKey,
            addon.Constants.MAX_LINK_OWNER_LENGTH
        ) and normalizeActorKey(entry.sourcePlayerKey) or nil
        local sourceRoundID = addon.Runtime.IsSafeIdentifier(
            entry.sourceRoundID,
            addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
        ) and entry.sourceRoundID or nil
        if not spell.id
            or not spell.ownerKey
            or not spell.revision
            or not appliedAt
            or not appliedRound
            or not sourcePlayerKey
            or not sourceRoundID
        then
            return nil
        end

        local durationRounds = spell.effects
            and spell.effects.durationRounds
        local durationSeconds = spell.effects
            and spell.effects.durationSeconds
        if durationRounds == addon.Constants.EFFECT_DURATION_PERMANENT then
            if entry.expiresAt ~= nil or entry.expiresRound ~= nil then return nil end
        elseif durationRounds then
            if expiresAt
                or not expiresRound
                or expiresRound ~= appliedRound + durationRounds
            then
                return nil
            end
        elseif durationSeconds then
            if expiresRound
                or not expiresAt
                or expiresAt ~= appliedAt + durationSeconds
            then
                return nil
            end
        else
            return nil
        end

        cleaned[#cleaned + 1] = {
            appliedAt = appliedAt,
            appliedRound = appliedRound,
            expiresAt = expiresAt,
            expiresRound = expiresRound,
            identity = sourcePlayerKey .. "\031" .. spell.id,
            sourcePlayerKey = sourcePlayerKey,
            sourceRoundID = sourceRoundID,
            spell = spell,
            hidden = entry.hidden == true,
            ownerProfile = addon.Runtime.IsSafeIdentifier(entry.ownerProfile, 200) and entry.ownerProfile or nil,
            readers = entry.hidden and addon.EffectVisibility and addon.EffectVisibility.CleanReaders(entry.readers) or nil,
        }
    end
    return cleaned
end

function addon.GameMasterEffects.EndPermanentEffects(session)
    if type(session) ~= "table" then return end
    local round = addon.GameMasterStore.GetCurrentRound(session)
    session.permanentEffectsEndedAtRound = round and round.number or 0
    session.permanentEffectsStoppedSubmissions = {}
    local function remember(sourceRound)
        if not sourceRound then return end
        forEachRoundSubmission(session, sourceRound, function(sourceKey, submission)
            for _, action in ipairs(addon.GameMasterActionCollection.Get(submission)) do
                if action.submissionId then
                    session.permanentEffectsStoppedSubmissions[sourceKey .. "\031" .. action.submissionId] = true
                end
            end
        end)
    end
    remember(round)
    if round and addon.GameMasterStore.GetPreviousRound then
        remember(addon.GameMasterStore.GetPreviousRound(session, round))
    end
    for key, entries in pairs(session.activeBuffs or {}) do
        for index = #entries, 1, -1 do
            local effects = entries[index].spell and entries[index].spell.effects
            if effects and effects.durationRounds == addon.Constants.EFFECT_DURATION_PERMANENT then
                table.remove(entries, index)
            end
        end
        if #entries == 0 then session.activeBuffs[key] = nil end
    end
end

function addon.GameMasterEffects.ValidateSharedBuffStates(raw)
    if raw == nil then
        return {}
    end
    local count = type(raw) == "table"
        and addon.Runtime.GetBoundedArrayLength(
            raw,
            addon.Constants.GAMEMASTER_MAX_PARTICIPANTS + MAX_NPC_ACTORS
        )
        or nil
    if not count then
        return nil
    end
    local states = {}
    local playerCount, npcCount = 0, 0
    for index = 1, count do
        local state = raw[index]
        local playerKey = type(state) == "table"
            and addon.Runtime.IsSafeIdentifier(
                state.playerKey,
                addon.Constants.MAX_LINK_OWNER_LENGTH
            )
            and normalizeActorKey(state.playerKey)
            or nil
        local buffs = playerKey
            and addon.GameMasterEffects.ValidateSharedBuffs(state.buffs)
            or nil
        if not playerKey or not buffs or states[playerKey] then
            return nil
        end
        if isNPCID(playerKey) then
            npcCount = npcCount + 1
        else
            playerCount = playerCount + 1
        end
        if npcCount > MAX_NPC_ACTORS
            or playerCount > addon.Constants.GAMEMASTER_MAX_PARTICIPANTS
        then
            return nil
        end
        states[playerKey] = buffs
    end
    return states
end

function addon.GameMasterEffects.PruneSharedBuffs(entries, roundNumber, timestamp)
    if type(entries) ~= "table" then
        return {}
    end
    roundNumber = tonumber(roundNumber) or math.huge
    timestamp = tonumber(timestamp) or addon.Runtime.GetTimestamp()
    for index = #entries, 1, -1 do
        local entry = entries[index]
        if type(entry) ~= "table"
            or (entry.expiresRound and roundNumber >= entry.expiresRound)
            or (entry.expiresAt and timestamp >= entry.expiresAt)
        then
            table.remove(entries, index)
        end
    end
    return entries
end

function addon.GameMasterEffects.RegisterListener(listener)
    if type(listener) ~= "function" then
        return false
    end
    listeners[#listeners + 1] = listener
    return true
end

local function hasCountdownConsumer()
    return next(countdownConsumers) ~= nil
end

local function getEffectState()
    local session = addon.GameMasterService.GetActiveSession()
    local remote = not session and addon.GameMasterService.GetRemoteSession()
        or nil
    local round = session and addon.GameMasterStore.GetCurrentRound(session)
        or nil
    return session, remote, session and session.activeBuffs
        or (remote or {}).sharedBuffs, round and round.number
        or (remote and remote.roundNumber)
end

local function pruneEffectState(session, remote, states, roundNumber, timestamp)
    if session then
        return addon.GameMasterEffects.Prune(
            session,
            roundNumber,
            timestamp
        )
    end
    local changed = false
    if remote and type(states) == "table" then
        for playerKey, entries in pairs(states) do
            if type(entries) ~= "table" then
                states[playerKey] = nil
                changed = true
            else
                local previousCount = #entries
                addon.GameMasterEffects.PruneSharedBuffs(
                    entries,
                    roundNumber,
                    timestamp
                )
                if #entries ~= previousCount then
                    changed = true
                end
                if #entries == 0 then
                    states[playerKey] = nil
                end
            end
        end
    end
    return changed
end

local function getNextExpiration(states)
    local nextExpiration
    for _, entries in pairs(type(states) == "table" and states or {}) do
        for _, entry in ipairs(type(entries) == "table" and entries or {}) do
            local expiresAt = type(entry) == "table"
                and tonumber(entry.expiresAt)
                or nil
            if expiresAt
                and expiresAt == expiresAt
                and expiresAt < math.huge
                and (not nextExpiration or expiresAt < nextExpiration)
            then
                nextExpiration = expiresAt
            end
        end
    end
    return nextExpiration
end

local updateTimer

local function cancelTimer()
    timerGeneration = timerGeneration + 1
    if expirationTimer and type(expirationTimer.Cancel) == "function" then
        expirationTimer:Cancel()
    end
    expirationTimer = nil
end

updateTimer = function()
    local wasScheduled = expirationTimer ~= nil
    cancelTimer()
    local active = addon.GameMasterService.IsSessionActive()
    if not active then
        if wasScheduled then
            notifyListeners("stopped")
        end
        return
    end
    local session, remote, states, roundNumber = getEffectState()
    local now = addon.Runtime.GetTimestamp()
    local changed = pruneEffectState(
        session,
        remote,
        states,
        roundNumber,
        now
    )
    if changed then
        notifyListeners("expired")
    end
    local nextExpiration = getNextExpiration(states)
    local timers = _G.C_Timer
    if not nextExpiration or type(timers) ~= "table" then
        return
    end
    local delay = math.max(0.1, nextExpiration - now)
    if hasCountdownConsumer() then
        delay = math.min(1, delay)
    end
    timerGeneration = timerGeneration + 1
    local generation = timerGeneration
    local dueAt = now + delay
    local function callback()
        if generation ~= timerGeneration then
            return
        end
        expirationTimer = nil
        if addon.Runtime.GetTimestamp() < dueAt then
            return
        end
        if hasCountdownConsumer()
            and addon.Runtime.GetTimestamp() < nextExpiration
        then
            notifyListeners("countdown")
        end
        updateTimer()
    end
    if type(timers.NewTimer) == "function" then
        expirationTimer = timers.NewTimer(delay, callback)
    elseif type(timers.After) == "function" then
        expirationTimer = true
        timers.After(delay, callback)
    end
end

function addon.GameMasterEffects.SetCountdownVisible(consumer, visible)
    if type(consumer) ~= "string" or consumer == "" then
        return false
    end
    if visible then
        countdownConsumers[consumer] = true
    else
        countdownConsumers[consumer] = nil
    end
    updateTimer()
    return true
end

addon.GameMasterService.RegisterListener(updateTimer)
