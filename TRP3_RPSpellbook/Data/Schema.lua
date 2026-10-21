local _, addon = ...

addon.Schema = {}

local function ensureTable(parent, key)
    if type(parent[key]) ~= "table" then
        parent[key] = {}
    end
    return parent[key]
end

local function normalizeMetadata(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number < 0 or number == math.huge then
        return fallback
    end
    return math.floor(number)
end

local function isValidIcon(icon)
    return (
        type(icon) == "number"
        and icon == icon
        and icon > 0
        and icon < math.huge
        and icon == math.floor(icon)
    )
        or (type(icon) == "string" and icon ~= "")
end

local function createDefaultTab()
    local timestamp = addon.Runtime.GetTimestamp()
    return {
        id = addon.Constants.DEFAULT_TAB_ID,
        name = addon.L("DEFAULT_TAB_NAME"),
        icon = addon.Constants.DEFAULT_TAB_ICON,
        themeID = "default",
        spellIds = {},
        createdAt = timestamp,
        updatedAt = timestamp,
        revision = 1,
    }
end

local function createDefaultSpellbook(profileKey)
    local timestamp = addon.Runtime.GetTimestamp()
    local defaultTab = createDefaultTab()
    return {
        id = "book_" .. profileKey,
        profileKey = profileKey,
        name = addon.L("DEFAULT_BOOK_NAME"),
        icon = addon.Constants.DEFAULT_BOOK_ICON,
        tabs = {
            [defaultTab.id] = defaultTab,
        },
        tabOrder = { defaultTab.id },
        spells = {},
        favorites = {},
        createdAt = timestamp,
        updatedAt = timestamp,
        revision = 1,
    }
end

local function normalizeTags(spell)
    if type(spell.tags) ~= "table" then
        spell.tags = nil
        return
    end

    for key, value in pairs(spell.tags) do
        if type(key) ~= "string"
            or key == ""
            or type(value) ~= "string"
            or value == ""
        then
            spell.tags[key] = nil
        end
    end
    if next(spell.tags) == nil then
        spell.tags = nil
    end
end

local function normalizeEffects(spell)
    if spell.effects == nil then
        return
    end
    local valid, cleaned = addon.Validators.ValidateSpell({
        effects = spell.effects,
        name = "Effect",
    })
    spell.effects = valid and cleaned.effects or nil
end

local function normalizeSpell(spell, spellID, timestamp)
    spell.id = spellID
    if type(spell.name) ~= "string" or spell.name == "" then
        spell.name = addon.L("UNKNOWN_ABILITY")
    end
    if not isValidIcon(spell.icon) then
        spell.icon = nil
    end
    for _, fieldName in ipairs({
        "nameColor",
        "resource",
        "range",
        "castTime",
        "cooldown",
        "description",
    }) do
        if spell[fieldName] ~= nil and type(spell[fieldName]) ~= "string" then
            spell[fieldName] = nil
        end
    end
    normalizeTags(spell)
    normalizeEffects(spell)

    spell.createdAt = normalizeMetadata(spell.createdAt, timestamp)
    spell.updatedAt = math.max(
        spell.createdAt,
        normalizeMetadata(spell.updatedAt, spell.createdAt)
    )
    spell.revision = math.max(1, normalizeMetadata(spell.revision, 1))
end

local function normalizeTab(tab, tabID, timestamp)
    tab.id = tabID
    if type(tab.name) ~= "string" or tab.name == "" then
        tab.name = addon.L("DEFAULT_TAB_NAME")
    end
    if not isValidIcon(tab.icon) then
        tab.icon = addon.Constants.DEFAULT_TAB_ICON
    end
    tab.themeID = addon.Validators.NormalizeTabThemeID(tab.themeID)
    if type(tab.spellIds) ~= "table" then
        tab.spellIds = {}
    end
    tab.createdAt = normalizeMetadata(tab.createdAt, timestamp)
    tab.updatedAt = math.max(
        tab.createdAt,
        normalizeMetadata(tab.updatedAt, tab.createdAt)
    )
    tab.revision = math.max(1, normalizeMetadata(tab.revision, 1))
end

local function sanitizeCollections(tabs, spells, timestamp)
    for tabID, tab in pairs(tabs) do
        if type(tabID) ~= "string" or tabID == "" or type(tab) ~= "table" then
            tabs[tabID] = nil
        else
            normalizeTab(tab, tabID, timestamp)
        end
    end
    for spellID, spell in pairs(spells) do
        if type(spellID) ~= "string" or spellID == "" or type(spell) ~= "table" then
            spells[spellID] = nil
        else
            normalizeSpell(spell, spellID, timestamp)
        end
    end
end

local function appendUnorderedTabs(tabs, tabOrder, seenTabs)
    local unordered = {}
    for tabID in pairs(tabs) do
        if not seenTabs[tabID] then
            unordered[#unordered + 1] = tabID
        end
    end
    table.sort(unordered)
    for _, tabID in ipairs(unordered) do
        seenTabs[tabID] = true
        tabOrder[#tabOrder + 1] = tabID
    end
end

function addon.Schema.NormalizeSpellbook(spellbook, profileKey)
    if type(spellbook) ~= "table" or type(profileKey) ~= "string" or profileKey == "" then
        return false
    end

    local constants = addon.Constants
    local timestamp = addon.Runtime.GetTimestamp()
    spellbook.id = type(spellbook.id) == "string" and spellbook.id ~= ""
        and spellbook.id
        or "book_" .. profileKey
    spellbook.profileKey = profileKey
    spellbook.name = type(spellbook.name) == "string" and spellbook.name ~= ""
        and spellbook.name
        or addon.L("DEFAULT_BOOK_NAME")
    if not isValidIcon(spellbook.icon) then
        spellbook.icon = constants.DEFAULT_BOOK_ICON
    end

    local tabs = ensureTable(spellbook, "tabs")
    local spells = ensureTable(spellbook, "spells")
    local favorites = ensureTable(spellbook, "favorites")
    sanitizeCollections(tabs, spells, timestamp)

    for spellID, favorite in pairs(favorites) do
        if favorite ~= true or type(spells[spellID]) ~= "table" then
            favorites[spellID] = nil
        end
    end

    local sourceOrder = ensureTable(spellbook, "tabOrder")
    local normalizedOrder = {}
    local seenTabs = {}
    for _, tabID in ipairs(sourceOrder) do
        if type(tabID) == "string"
            and not seenTabs[tabID]
            and type(tabs[tabID]) == "table"
        then
            seenTabs[tabID] = true
            normalizedOrder[#normalizedOrder + 1] = tabID
        end
    end
    appendUnorderedTabs(tabs, normalizedOrder, seenTabs)

    if #normalizedOrder == 0 then
        local defaultTab = createDefaultTab()
        tabs[defaultTab.id] = defaultTab
        normalizedOrder[1] = defaultTab.id
    end
    spellbook.tabOrder = normalizedOrder

    local seenSpells = {}
    for _, tabID in ipairs(normalizedOrder) do
        local tab = tabs[tabID]
        local normalizedSpellIDs = {}
        for _, spellID in ipairs(tab.spellIds) do
            if type(spellID) == "string"
                and not seenSpells[spellID]
                and type(spells[spellID]) == "table"
            then
                seenSpells[spellID] = true
                normalizedSpellIDs[#normalizedSpellIDs + 1] = spellID
            end
        end
        tab.spellIds = normalizedSpellIDs
    end

    local orphanSpellIDs = {}
    for spellID in pairs(spells) do
        if not seenSpells[spellID] then
            orphanSpellIDs[#orphanSpellIDs + 1] = spellID
        end
    end
    table.sort(orphanSpellIDs)
    local fallbackTab = tabs[normalizedOrder[1]]
    for _, spellID in ipairs(orphanSpellIDs) do
        fallbackTab.spellIds[#fallbackTab.spellIds + 1] = spellID
    end

    spellbook.createdAt = normalizeMetadata(spellbook.createdAt, timestamp)
    spellbook.updatedAt = math.max(
        spellbook.createdAt,
        normalizeMetadata(spellbook.updatedAt, spellbook.createdAt)
    )
    spellbook.revision = math.max(1, normalizeMetadata(spellbook.revision, 1))
    return true
end

local function normalizeProfiles(database)
    local profiles = ensureTable(database, "profiles")
    for profileKey, profileData in pairs(profiles) do
        if type(profileKey) ~= "string"
            or profileKey == ""
            or type(profileData) ~= "table"
        then
            profiles[profileKey] = nil
        else
            profileData.profileKey = profileKey
            if type(profileData.spellbook) ~= "table" then
                profileData.spellbook = createDefaultSpellbook(profileKey)
            end
            addon.Schema.NormalizeSpellbook(profileData.spellbook, profileKey)
        end
    end
end

local function clampInteger(value, fallback, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return fallback
    end
    return math.max(minimum, math.min(maximum, math.floor(number)))
end

local function cleanStoredText(value, fallback, maximumLength)
    local text = addon.Runtime.Trim(value)
    if not text or text == "" or #text > maximumLength or text:find("[%c|]") then
        return fallback
    end
    return text
end

local function normalizeParticipant(participant, playerKey)
    if type(participant) ~= "table" then
        return nil
    end

    local playerID = cleanStoredText(
        participant.playerID,
        nil,
        addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
    )
    if not playerID or addon.Runtime.NormalizePlayerID(playerID) ~= playerKey then
        return nil
    end

    participant.playerID = playerID
    participant.firstName = cleanStoredText(participant.firstName, nil, addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH)
    participant.gameName = cleanStoredText(
        participant.gameName,
        playerID,
        addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
    )
    participant.lastName = cleanStoredText(participant.lastName, nil, addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH)
    participant.rpName = cleanStoredText(
        participant.rpName,
        participant.gameName,
        addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
    )
    local profileColor = type(participant.profileColor) == "string"
        and participant.profileColor:gsub("#", "")
        or nil
    participant.profileColor = profileColor
        and profileColor:match("^%x%x%x%x%x%x$")
        and profileColor
        or nil
    participant.profileIcon = cleanStoredText(participant.profileIcon, nil, addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH)
    participant.title = cleanStoredText(participant.title, nil, addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH)
    participant.lastSeenAt = normalizeMetadata(participant.lastSeenAt, 0)
    participant.online = participant.online == true
    return participant
end

local function normalizeSubmission(submission, playerKey, participant, nested)
    local rawActions = not nested and submission and submission.actions or nil
    if type(submission) ~= "table"
        or not addon.Constants.GAMEMASTER_ACTIONS[submission.action]
        or type(submission.spell) ~= "table"
    then
        return nil
    end

    local validSpell, spell = addon.Validators.ValidateSpell(submission.spell)
    if not validSpell then
        return nil
    end

    spell.id = cleanStoredText(
        submission.spell.id,
        nil,
        addon.Constants.MAX_LINK_SPELL_ID_LENGTH
    )
    spell.name = cleanStoredText(
        spell.name,
        addon.L("UNKNOWN_ABILITY"),
        addon.Validators and addon.Validators.Limits.MAX_SPELL_NAME_LENGTH or 120
    )
    spell.revision = clampInteger(
        submission.spell.revision,
        1,
        1,
        addon.Constants.MAX_LINK_REVISION
    )
    spell.ownerKey = cleanStoredText(
        submission.spell.ownerKey,
        nil,
        addon.Constants.MAX_LINK_OWNER_LENGTH
    )
    if not spell.id or not spell.ownerKey then
        return nil
    end
    submission.spell = spell

    local function normalizeTarget(target)
        if type(target) ~= "table"
            or not addon.Constants.GAMEMASTER_TARGET_TYPES[target.kind]
        then return nil end
        if target.kind == "marker" then
            target.value = clampInteger(target.value, 0, 0, 8)
            if target.value == 0 then return nil end
        else
            target.value = cleanStoredText(
                target.value, nil,
                addon.Constants.GAMEMASTER_MAX_TARGET_LENGTH
            )
            if not target.value then return nil end
        end
        target.label = cleanStoredText(
            target.label, tostring(target.value),
            addon.Constants.GAMEMASTER_MAX_TARGET_LENGTH
        )
        target.name = cleanStoredText(
            target.name, nil,
            addon.Constants.GAMEMASTER_MAX_TARGET_LENGTH
        )
        target.health = tonumber(target.health)
        target.color = cleanStoredText(target.color, nil, 12)
        target.icon = type(target.icon) == "number" and isValidIcon(target.icon)
            and target.icon <= addon.Constants.MAX_IMPORT_SAFE_INTEGER and target.icon
            or cleanStoredText(target.icon, nil, addon.Validators.Limits.MAX_ICON_LENGTH)
        return target
    end

    local targets = {}
    local seenTargets = {}
    local sourceTargets = type(submission.targets) == "table"
        and submission.targets
        or { submission.target }
    for _, candidate in ipairs(sourceTargets) do
        local target = normalizeTarget(candidate)
        local key = target
            and target.kind .. ":" .. tostring(target.value):lower()
            or nil
        if target and not seenTargets[key] then
            seenTargets[key] = true
            targets[#targets + 1] = target
        end
        if #targets >= addon.Constants.GAMEMASTER_MAX_TARGETS then break end
    end

    submission.playerKey = playerKey
    submission.playerID = participant.playerID
    submission.rpName = cleanStoredText(
        submission.rpName,
        participant.rpName,
        addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
    )
    submission.aoe = submission.aoe == true
    submission.targets = targets
    submission.target = targets[1]
    if type(submission.emote) == "table" then
        submission.emote.channel = cleanStoredText(submission.emote.channel, nil, 40)
        submission.emote.text = cleanStoredText(
            submission.emote.text, nil,
            addon.Constants.GAMEMASTER_MAX_EMOTE_LENGTH
        )
        submission.emote.timestamp = normalizeMetadata(submission.emote.timestamp, 0)
        if not submission.emote.channel or not submission.emote.text then
            submission.emote = nil
        end
    else
        submission.emote = nil
    end
    if type(submission.preparation) == "table" then
        local required = clampInteger(submission.preparation.required, 0, 0, 100)
        local progress = clampInteger(submission.preparation.progress, 0, 0, required)
        submission.preparation = required > 0
            and { required = required, progress = progress }
            or nil
    else
        submission.preparation = nil
    end
    submission.submittedAt = normalizeMetadata(submission.submittedAt, 0)
    submission.submissionId = cleanStoredText(
        submission.submissionId,
        nil,
        addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
    )
    submission.actions = nil
    if nested then
        submission.playerID = nil
        submission.playerKey = nil
        submission.rpName = nil
        return submission
    end
    if rawActions ~= nil then
        local actionCount = addon.Runtime.GetBoundedArrayLength(
            rawActions,
            addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER
        )
        if not actionCount or actionCount < 1 then
            return nil
        end
        local actions = {}
        for index = 1, actionCount do
            local action = normalizeSubmission(
                rawActions[index],
                playerKey,
                participant,
                true
            )
            if not action then
                return nil
            end
            actions[index] = action
        end
        if not addon.GameMasterActionCollection.Set(submission, actions) then
            return nil
        end
    end
    return submission
end

local function normalizeEffectWhispers(round, session)
    local receipts, actorCount = {}, 0
    for actorID, entries in pairs(type(round.effectWhispers) == "table" and round.effectWhispers or {}) do
        local participant = session.participants[actorID]
            or addon.GameMasterNPCActors and addon.GameMasterNPCActors.Get(session, actorID)
        if participant and type(entries) == "table" then
            actorCount = actorCount + 1
            if actorCount > (addon.Constants.GAMEMASTER_MAX_VISIBLE_ACTORS or 60) then break end
            local clean = {}
            for index = 1, addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER do
                local receipt = entries[index]
                if type(receipt) == "table" and type(receipt.key) == "string" and #receipt.key <= 512
                    and not receipt.key:find("[|%z\1-\30\127]") then
                    local targets, count = {}, 0
                    for targetID, sent in pairs(type(receipt.targets) == "table" and receipt.targets or {}) do
                        local npc = addon.GameMasterNPCActors
                            and addon.GameMasterNPCActors.Get(session, targetID)
                        local player = type(targetID) == "string"
                            and #targetID <= addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
                            and addon.Runtime.NormalizePlayerID(targetID) == targetID
                            and not targetID:find("^npc_")
                         
                        if sent == true and (npc or player) then
                            targets[targetID], count = true, count + 1
                            if count >= addon.Constants.GAMEMASTER_MAX_TARGETS then break end
                        end
                    end
                    clean[index] = { key = receipt.key, targets = targets }
                end
            end
            receipts[actorID] = clean
        end
    end
    round.effectWhispers = receipts
end

local function normalizeActiveBuffs(session)
    session.permanentEffectsEndedAtRound = session.permanentEffectsEndedAtRound ~= nil
        and normalizeMetadata(session.permanentEffectsEndedAtRound, 0) or nil
    local stopped, stoppedCount = {}, 0
    for key, value in pairs(type(session.permanentEffectsStoppedSubmissions) == "table"
        and session.permanentEffectsStoppedSubmissions or {}) do
        if type(key) == "string" and #key <= 512 and value == true and stoppedCount < 600 then
            stopped[key], stoppedCount = true, stoppedCount + 1
        end
    end
    session.permanentEffectsStoppedSubmissions = stopped
    local normalized = {}
    local now = addon.Runtime.GetTimestamp()
    for playerKey, entries in pairs(
        type(session.activeBuffs) == "table" and session.activeBuffs or {}
    ) do
        if (session.participants[playerKey] or addon.GameMasterNPCActors
            and addon.GameMasterNPCActors.Get(session, playerKey)) and type(entries) == "table" then
            local kept = {}
            for _, entry in ipairs(entries) do
                local valid, spell
                if type(entry) == "table" then
                    valid, spell = addon.Validators.ValidateSpell(entry.spell)
                end
                local expiresAt = type(entry) == "table"
                    and normalizeMetadata(entry.expiresAt, 0)
                    or 0
                local expiresRound = type(entry) == "table"
                    and normalizeMetadata(entry.expiresRound, 0)
                    or 0
                if valid
                    and type(spell.effects) == "table"
                    and (spell.effects.buff == true or spell.effects.debuff == true)
                    and (expiresAt > now or expiresRound > 0
                        or spell.effects.durationRounds == addon.Constants.EFFECT_DURATION_PERMANENT
                            and entry.expiresAt == nil and entry.expiresRound == nil)
                then
                    spell.id = cleanStoredText(
                        entry.spell.id,
                        nil,
                        addon.Constants.MAX_LINK_SPELL_ID_LENGTH
                    )
                    spell.ownerKey = cleanStoredText(
                        entry.spell.ownerKey,
                        nil,
                        addon.Constants.MAX_LINK_OWNER_LENGTH
                    )
                    spell.revision = clampInteger(
                        entry.spell.revision,
                        1,
                        1,
                        addon.Constants.MAX_LINK_REVISION
                    )
                    local sourcePlayerKey = addon.Runtime.NormalizePlayerID(
                        entry.sourcePlayerKey
                    )
                    local sourceRoundID = cleanStoredText(
                        entry.sourceRoundID,
                        nil,
                        addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
                    )
                    if spell.id and spell.ownerKey
                        and sourcePlayerKey and sourceRoundID
                    then
                        kept[#kept + 1] = {
                            appliedAt = normalizeMetadata(entry.appliedAt, 0),
                            appliedRound = normalizeMetadata(entry.appliedRound, 0),
                            expiresAt = expiresAt > 0 and expiresAt or nil,
                            expiresRound = expiresRound > 0
                                and expiresRound or nil,
                            identity = cleanStoredText(
                                entry.identity,
                                sourcePlayerKey .. ":" .. spell.id,
                                300
                            ),
                            sourcePlayerKey = sourcePlayerKey,
                            sourceRoundID = sourceRoundID,
                            spell = spell,
                            hidden = entry.hidden == true,
                            ownerProfile = cleanStoredText(entry.ownerProfile, nil, 200),
                            readers = entry.hidden and addon.EffectVisibility and addon.EffectVisibility.CleanReaders(entry.readers) or nil,
                        }
                    end
                end
                if #kept
                    >= addon.Constants.GAMEMASTER_MAX_ACTIVE_BUFFS_PER_PLAYER
                then
                    break
                end
            end
            if #kept > 0 then
                normalized[playerKey] = kept
            end
        end
    end
    session.activeBuffs = normalized
end

local RECOVERY_CHARACTER_LIMIT = 50
local RECOVERY_TOMBSTONE_LIMIT = 128
local RECOVERY_REVISION_STRIDE = 1048576

local function recoveryInteger(value, fallback, minimum)
    local number = tonumber(value)
    if not number or number ~= number or number < (minimum or 0)
        or number > addon.Constants.MAX_IMPORT_SAFE_INTEGER
        or number ~= math.floor(number)
    then
        return fallback
    end
    return number
end

local function recoveryID(value)
    return addon.Runtime.IsSafeIdentifier(value,
        addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH) and value or nil
end

local function recoveryPlayer(value)
    local text = cleanStoredText(value, nil,
        addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH)
    return text and addon.Runtime.NormalizePlayerID(text) or nil
end

local function normalizeRecoveryMembers(members)
    local result, seen = {}, {}
    for index = 1, addon.Constants.GAMEMASTER_MAX_PARTICIPANTS do
        local key = type(members) == "table" and members[index]
        if key == nil then break end
        local normalized = recoveryPlayer(key)
        if normalized and not seen[normalized] then
            seen[normalized] = true
            result[#result + 1] = normalized
        end
    end
    table.sort(result)
    return result
end

local function normalizeRecoveryWindows(value)
    if type(value) ~= "table" then return nil end
    return {
        compactSpellbook = value.compactSpellbook == true,
        currentAction = value.currentAction == true,
        gameMaster = value.gameMaster == true,
        roundOverview = value.roundOverview == true,
    }
end

function addon.Schema.NormalizeRuntimeState(raw, playerKey, sessions)
    if type(raw) ~= "table" or (raw.version ~= 1 and raw.version ~= 2)
        or recoveryPlayer(playerKey) ~= playerKey
    then return nil end
    local localState = type(raw.localState) == "table" and raw.localState or nil
    local remote = type(raw.remoteState) == "table" and raw.remoteState or nil
    local source = localState or remote
    if not source or not recoveryID(source.sessionID)
        or not recoveryID(source.activationID) then return nil end
    local state = {
        sessionID = source.sessionID, activationID = source.activationID,
        visibility = addon.Constants.GAMEMASTER_VISIBILITY_MODES[source.visibility]
            and source.visibility or "hidden",
        openWindows = normalizeRecoveryWindows(source.openWindows),
    }
    if localState then
        local session = type(sessions) == "table" and sessions[state.sessionID]
        if type(session) ~= "table" or session.ownerKey ~= playerKey
            or session.runningActivationID ~= state.activationID then return nil end
        state.visibilityRevision = recoveryInteger(source.visibilityRevision, 0)
    else
        local gm = recoveryPlayer(source.gameMasterID)
        local name = cleanStoredText(source.sessionName, nil,
            addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH)
        local number = recoveryInteger(source.roundNumber, nil)
        if not gm or not name or not number
            or (number > 0 and not recoveryID(source.roundID)) then return nil end
        state.gameMasterID, state.gameMasterKey = addon.Runtime.Trim(source.gameMasterID), gm
        state.sessionName, state.roundNumber = name, number
        state.roundID = number > 0 and source.roundID or nil
        state.locked = source.locked ~= false
        state.phase = source.phase == "enemies" and "enemies" or "players"
        state.gmParticipates = source.gmParticipates ~= false
        state.enemyPhases = source.enemyPhases == true
        state.enemyFirst = source.enemyFirst == true
        state.deferEnemyActions = source.deferEnemyActions ~= false
        state.narratorName = cleanStoredText(source.narratorName,
            addon.L("GAMEMASTER_NARRATOR_DEFAULT"), addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH)
        state.turnTracking = source.turnTracking == true
        state.turnSequence = recoveryInteger(source.turnSequence, 0)
        state.lastVisibilityRevision = recoveryInteger(source.lastVisibilityRevision, 0)
        state.lastStateRevision = recoveryInteger(source.lastStateRevision, 0)
        state.originSequence = recoveryInteger(source.originSequence, 0)
        local visibility = addon.GameMasterVisibility
        state.sharedActions = visibility and visibility.ValidateEntries(
            source.sharedActions or {}, state.visibility) or {}
        state.sharedActions = state.sharedActions or {}
        if addon.GameMasterIncomingActions and source.incomingRoundID == state.roundID then
            state.incomingActions = addon.GameMasterIncomingActions.Validate(
                source.incomingActions or {}, state.roundID, state.roundNumber) or {}
            state.incomingRoundID = state.roundID
        end
        state.sharedBuffs = addon.GameMasterEffects
            and addon.GameMasterEffects.ValidateSharedBuffStates(source.sharedBuffs or {}) or {}
        state.sharedBuffs = state.sharedBuffs or {}
        state.sharedBuffProfile = addon.Runtime.IsSafeIdentifier(source.sharedBuffProfile, 200)
            and source.sharedBuffProfile or nil
        state.sharedRoundID = source.sharedRoundID == state.roundID and state.roundID or nil
        local own = visibility and type(source.lastSubmission) == "table"
            and visibility.ValidateEntries({ source.lastSubmission }, "full")
        if own and own[1] and recoveryPlayer(own[1].playerID) == playerKey then
            state.lastSubmission = own[1]
        end
        state.originOutbox = addon.GameMasterStore
            and addon.GameMasterStore.NormalizeOriginOutbox(source.originOutbox, playerKey, state)
        if state.originOutbox then
            for _, payload in ipairs(state.originOutbox.items) do
                state.originSequence = math.max(state.originSequence, payload.originSequence)
            end
        end
        local pending = source.pendingTurn
        local pendingRevision = type(pending) == "table"
            and recoveryInteger(pending.stateRevision, nil) or nil
        local currentRevision = math.max(state.lastStateRevision, state.lastVisibilityRevision)
        if type(pending) == "table" and pending.sessionId == state.sessionID
            and pending.activationId == state.activationID
            and pending.roundId == state.roundID and state.roundID
            and type(pending.completed) == "boolean"
            and recoveryInteger(pending.sequence, nil, 1)
            and tonumber(pending.sequence) >= state.turnSequence
            and pendingRevision and pendingRevision <= currentRevision
            and addon.GameMasterStore.GetRevisionEpoch(pendingRevision)
                == addon.GameMasterStore.GetRevisionEpoch(currentRevision)
        then
            state.pendingTurn = {
                sessionId = state.sessionID, activationId = state.activationID,
                roundId = state.roundID, sequence = tonumber(pending.sequence),
                stateRevision = pendingRevision,
                completed = pending.completed,
                source = pending.source == "emote" and "emote" or "manual",
            }
            state.turnSequence = math.max(state.turnSequence, state.pendingTurn.sequence)
        end
    end
    local members = normalizeRecoveryMembers(raw.groupMembers)
     
    local confirmation = raw.requiresConfirmation == true or #members == 0
    return {
        version = 2, status = raw.status == "suspended" and "suspended" or "live",
        requiresConfirmation = confirmation, groupMembers = members,
        savedAt = recoveryInteger(raw.savedAt, 0),
        suspendedAt = recoveryInteger(raw.suspendedAt, nil),
        suspendReason = raw.suspendReason == "left" and "left"
            or (raw.suspendReason == "unrelated" and "unrelated" or "missing"),
        localState = localState and state or nil,
        remoteState = not localState and state or nil,
    }
end

local function normalizeRecovery(root)
    root.originSubmissionSequence = root.originSubmissionSequence == nil and 0
        or recoveryInteger(root.originSubmissionSequence, addon.Constants.MAX_IMPORT_SAFE_INTEGER)
    local states, count = {}, 0
    for key, raw in pairs(type(root.runtimeStates) == "table" and root.runtimeStates or {}) do
        if count >= RECOVERY_CHARACTER_LIMIT then break end
        local state = addon.Schema.NormalizeRuntimeState(raw, key, root.sessions)
        if state and state.remoteState then
            root.originSubmissionSequence = math.max(root.originSubmissionSequence,
                state.remoteState.originSequence or 0)
        end
        if state then states[key], count = state, count + 1 end
    end
    root.runtimeStates = states
    local tombstones = {}
    for _, entry in ipairs(type(root.stoppedActivations) == "table" and root.stoppedActivations or {}) do
        if #tombstones >= RECOVERY_TOMBSTONE_LIMIT then break end
        if type(entry) == "table" and recoveryID(entry.sessionID)
            and recoveryID(entry.activationID) and recoveryPlayer(entry.ownerKey)
            and recoveryPlayer(entry.playerKey)
        then
            local duplicate = false
            for _, known in ipairs(tombstones) do
                if known.playerKey == recoveryPlayer(entry.playerKey)
                    and known.ownerKey == recoveryPlayer(entry.ownerKey)
                    and known.sessionID == entry.sessionID
                    and known.activationID == entry.activationID then duplicate = true; break end
            end
            if not duplicate then
                tombstones[#tombstones + 1] = {
                    playerKey = recoveryPlayer(entry.playerKey),
                    ownerKey = recoveryPlayer(entry.ownerKey),
                    sessionID = entry.sessionID, activationID = entry.activationID,
                    stoppedAt = recoveryInteger(entry.stoppedAt, 0),
                }
            end
        end
    end
     
     
    for _, session in pairs(root.sessions) do
        if #tombstones >= RECOVERY_TOMBSTONE_LIMIT then break end
        if session.lastActivationID and session.runningActivationID ~= session.lastActivationID then
            local duplicate = false
            for _, entry in ipairs(tombstones) do
                if entry.playerKey == session.ownerKey and entry.ownerKey == session.ownerKey
                    and entry.sessionID == session.id
                    and entry.activationID == session.lastActivationID then duplicate = true; break end
            end
            if not duplicate then
                tombstones[#tombstones + 1] = { playerKey = session.ownerKey, ownerKey = session.ownerKey,
                    sessionID = session.id, activationID = session.lastActivationID,
                    stoppedAt = recoveryInteger(session.updatedAt, 0) }
            end
        end
    end
    root.stoppedActivations = tombstones
    for key, saved in pairs(states) do
        local state = saved.localState or saved.remoteState
        local ownerKey = saved.localState and key or state.gameMasterKey
        for _, stopped in ipairs(tombstones) do
            if stopped.playerKey == key and stopped.ownerKey == ownerKey
                and stopped.sessionID == state.sessionID
                and stopped.activationID == state.activationID then states[key] = nil; break end
        end
    end
end

local function normalizeGameMaster(database)
    local root = ensureTable(database, "gameMaster")
    local sessions = ensureTable(root, "sessions")
    root.nextSessionSerial = clampInteger(root.nextSessionSerial, 1, 1, 2147483647)
    root.orderLocked = root.orderLocked ~= false
    root.collapsed = root.collapsed == true
    root.window = type(root.window) == "table" and root.window or {}
    root.compactCollapsed = root.compactCollapsed == true
    root.compactLocked = root.compactLocked == true
    root.compactWindow = type(root.compactWindow) == "table" and root.compactWindow or {}

    for sessionID, session in pairs(sessions) do
        local validID = addon.Runtime.IsSafeIdentifier(
            sessionID,
            addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
        )
        local ownerKey = type(session) == "table"
            and addon.Runtime.NormalizePlayerID(session.ownerID)
            or nil
        if not validID or type(session) ~= "table" or not ownerKey then
            sessions[sessionID] = nil
        else
            session.id = sessionID
            session.name = cleanStoredText(
                session.name,
                addon.L("GAMEMASTER_UNNAMED_SESSION"),
                addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH
            )
            session.ownerKey = ownerKey
            session.gmParticipates = session.gmParticipates ~= false
            session.enemyPhases = session.enemyPhases == true
             
            session.enemyFirst = session.enemyFirst == true
            session.deferEnemyActions = session.deferEnemyActions ~= false
            session.narratorName = cleanStoredText(session.narratorName,
                addon.L("GAMEMASTER_NARRATOR_DEFAULT"), addon.Constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH)
            session.runningActivationID = recoveryID(session.runningActivationID)
            session.lastActivationID = recoveryID(session.lastActivationID)
            session.recoveryRevision = recoveryInteger(session.recoveryRevision, 0)
            session.recoveryEpoch = math.floor(session.recoveryRevision / RECOVERY_REVISION_STRIDE)
            session.createdAt = normalizeMetadata(session.createdAt, 0)
            session.updatedAt = math.max(
                session.createdAt,
                normalizeMetadata(session.updatedAt, session.createdAt)
            )
            session.access = addon.GameMasterSceneAccess.Normalize(
                session.access,
                "hidden"
            )
            for index = #session.access.assistants, 1, -1 do
                if session.access.assistants[index].playerKey
                    == ownerKey
                then
                    table.remove(
                        session.access.assistants,
                        index
                    )
                end
            end

            local participants = type(session.participants) == "table"
                and session.participants
                or {}
            session.participants = participants
            if addon.GameMasterNPCActors then addon.GameMasterNPCActors.NormalizeSession(session) end
            for playerKey, participant in pairs(participants) do
                local normalizedKey = addon.Runtime.NormalizePlayerID(playerKey)
                if normalizedKey ~= playerKey
                    or not normalizeParticipant(participant, playerKey)
                then
                    participants[playerKey] = nil
                end
            end

            local order = {}
            local seen = {}
            for _, playerKey in ipairs(type(session.participantOrder) == "table"
                and session.participantOrder
                or {})
            do
                if participants[playerKey] and not seen[playerKey] then
                    seen[playerKey] = true
                    order[#order + 1] = playerKey
                end
            end
            local missing = {}
            for playerKey in pairs(participants) do
                if not seen[playerKey] then
                    missing[#missing + 1] = playerKey
                end
            end
            normalizeActiveBuffs(session)
            table.sort(missing)
            for _, playerKey in ipairs(missing) do
                order[#order + 1] = playerKey
            end
            session.participantOrder = order

            local preparations = type(session.preparations) == "table"
                and session.preparations
                or {}
            for playerKey, preparation in pairs(preparations) do
                local required = type(preparation) == "table"
                    and clampInteger(preparation.required, 0, 0, 100)
                    or 0
                local spellID = type(preparation) == "table"
                    and cleanStoredText(
                        preparation.spellID, nil,
                        addon.Constants.MAX_LINK_SPELL_ID_LENGTH
                    )
                    or nil
                local startedRound = type(preparation) == "table"
                    and clampInteger(preparation.startedRound, 0, 0, 2147483647)
                    or 0
                if not (participants[playerKey] or addon.GameMasterNPCActors
                    and addon.GameMasterNPCActors.Get(session, playerKey))
                    or required == 0 or not spellID or startedRound == 0
                then
                    preparations[playerKey] = nil
                else
                    preparation.required = required
                    preparation.spellID = spellID
                    preparation.startedRound = startedRound
                    preparation.progress = clampInteger(
                        preparation.progress, 0, 0, required
                    )
                    preparation.lastPreparedRound = clampInteger(
                        preparation.lastPreparedRound,
                        startedRound + math.max(0, preparation.progress - 1),
                        startedRound,
                        2147483647
                    )
                    preparation.automated = preparation.automated == true
                end
            end
            session.preparations = preparations

            local rounds = {}
            local highestRound = 0
            for _, round in ipairs(type(session.rounds) == "table" and session.rounds or {}) do
                if type(round) == "table" then
                    round.number = clampInteger(round.number, highestRound + 1, 1, 2147483647)
                    highestRound = math.max(highestRound, round.number)
                    round.id = cleanStoredText(
                        round.id,
                        "round_" .. tostring(round.number),
                        addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
                    )
                    round.status = round.status == "open" and "open" or "locked"
                    round.phase = round.phase == "enemies" and session.enemyPhases and "enemies" or "players"
                    round.enemyStartedAt = normalizeMetadata(round.enemyStartedAt, 0)
                    round.playerStartedAt = normalizeMetadata(round.playerStartedAt, 0)
                    round.enemyActionsRevealed = round.enemyActionsRevealed == true
                        or session.enemyFirst and round.phase == "players"
                    local enemyCompletion = type(round.enemyCompletedTurns) == "table"
                        and round.enemyCompletedTurns[ownerKey]
                    round.enemyCompletedTurns = {}
                    if type(enemyCompletion) == "table" then
                        round.enemyCompletedTurns[ownerKey] = {
                            at = normalizeMetadata(enemyCompletion.at, 0),
                            source = enemyCompletion.source == "emote" and "emote" or "manual",
                        }
                    end
                    local inactive = type(round.inactiveParticipants) == "table"
                        and round.inactiveParticipants
                        or {}
                    for playerKey, value in pairs(inactive) do
                        if not participants[playerKey] or value ~= true then
                            inactive[playerKey] = nil
                        end
                    end
                    round.inactiveParticipants = inactive
                    local completed, sequences = {}, {}
                    local count = 0
                    for playerKey, completion in pairs(type(round.completedTurns) == "table"
                        and round.completedTurns or {}) do
                        if count >= addon.Constants.GAMEMASTER_MAX_PARTICIPANTS then break end
                        if participants[playerKey] and (completion == true or type(completion) == "table") then
                            completed[playerKey] = {
                                at = type(completion) == "table" and recoveryInteger(completion.at, 0) or 0,
                                source = type(completion) == "table" and completion.source == "emote"
                                    and "emote" or "manual",
                            }
                            count = count + 1
                        end
                    end
                    count = 0
                    for playerKey, sequence in pairs(type(round.turnSequences) == "table"
                        and round.turnSequences or {}) do
                        if count >= addon.Constants.GAMEMASTER_MAX_PARTICIPANTS then break end
                        if participants[playerKey] and recoveryInteger(sequence, nil) then
                            sequences[playerKey], count = tonumber(sequence), count + 1
                        end
                    end
                    round.completedTurns, round.turnSequences = completed, sequences
                    local origins = {}
                    count = 0
                    for playerKey, sequence in pairs(type(round.originSubmissionSequences) == "table"
                        and round.originSubmissionSequences or {}) do
                        if count >= addon.Constants.GAMEMASTER_MAX_PARTICIPANTS then break end
                        if participants[playerKey] and recoveryInteger(sequence, nil, 1) then
                            origins[playerKey], count = tonumber(sequence), count + 1
                        end
                    end
                    round.originSubmissionSequences = origins
                    local fences = {}
                    count = 0
                    for playerKey, revision in pairs(type(round.participantStateRevisions) == "table"
                        and round.participantStateRevisions or {}) do
                        if count >= addon.Constants.GAMEMASTER_MAX_PARTICIPANTS then break end
                        if participants[playerKey] and recoveryInteger(revision, nil) then
                            fences[playerKey], count = tonumber(revision), count + 1
                        end
                    end
                    round.participantStateRevisions = fences
                    round.startedAt = normalizeMetadata(round.startedAt, session.createdAt)
                    round.lockedAt = normalizeMetadata(round.lockedAt, 0)
                    round.submissions = type(round.submissions) == "table"
                        and round.submissions
                        or {}
                    for playerKey, submission in pairs(round.submissions) do
                        local participant = participants[playerKey]
                        if not participant
                            or not normalizeSubmission(submission, playerKey, participant)
                        then
                            round.submissions[playerKey] = nil
                        end
                    end
                    local npcSubmissions, npcCompleted, npcSequences = {}, {}, {}
                    for _, actorID in ipairs(session.npcOrder or {}) do
                        local actor = session.npcActors[actorID]
                        local submission = type(round.npcSubmissions) == "table" and round.npcSubmissions[actorID]
                        if submission and normalizeSubmission(submission, actorID,
                            { playerID = actorID, rpName = actor.name }) then
                            npcSubmissions[actorID] = submission
                        end
                        if type(round.npcCompletedTurns) == "table" and round.npcCompletedTurns[actorID] == true then
                            npcCompleted[actorID] = true
                        end
                        local sequence = type(round.npcOriginSequences) == "table"
                            and round.npcOriginSequences[actorID] or nil
                        npcSequences[actorID] = recoveryInteger(sequence, nil, 1)
                    end
                    round.npcSubmissions, round.npcCompletedTurns = npcSubmissions, npcCompleted
                    round.npcOriginSequences = npcSequences
                    normalizeEffectWhispers(round, session)
                    rounds[#rounds + 1] = round
                end
            end
            session.rounds = rounds
            session.nextRoundNumber = math.max(
                highestRound + 1,
                clampInteger(session.nextRoundNumber, highestRound + 1, 1, 2147483647)
            )
            local current = rounds[#rounds]
            session.currentRoundID = current and current.id or nil
            for _, round in ipairs(rounds) do
                if current and round.number < current.number then round.enemyActionsRevealed = true end
            end
        end
    end

    if type(root.activeSessionID) ~= "string" or not sessions[root.activeSessionID] then
        root.activeSessionID = nil
    end
    normalizeRecovery(root)
    return root
end

addon.Schema.NormalizeGameMaster = normalizeGameMaster

function addon.Schema.NormalizeOnboarding(settings)
    local saved = ensureTable(settings, "onboarding")
    local completed, progress = {}, {}
    for _, id in ipairs({ "spellbook", "gameMasterPlayer", "gameMaster", "npc" }) do
        if type(saved.completed) == "table" and saved.completed[id] == true then
            completed[id] = true
        end
        local step = type(saved.progress) == "table" and saved.progress[id]
        if type(step) == "string" and #step <= 64 and step:match("^[%w_]+$") then
            progress[id] = step
        end
    end
    saved.completed, saved.progress = completed, progress
    return saved
end

 
 
local function repairAtEnd() return true end
local migrations = {
    [0] = repairAtEnd, [1] = repairAtEnd, [2] = repairAtEnd,
    [3] = repairAtEnd, [4] = repairAtEnd, [5] = repairAtEnd,
    [6] = repairAtEnd, [7] = repairAtEnd, [8] = repairAtEnd,
    [9] = repairAtEnd, [10] = repairAtEnd,
    [11] = function(database)
        for _, profile in pairs(database.profiles) do
            local book = type(profile) == "table" and profile.spellbook
            if type(book) == "table" and type(book.icon) == "string" then
                local icon = book.icon:lower():gsub("\\", "/")
                if icon == "inv_misc_book_09"
                    or icon == "interface/icons/inv_misc_book_09"
                then
                    book.icon = addon.Constants.DEFAULT_BOOK_ICON
                end
            end
        end
        return true
    end,
}

function addon.Schema.InitializeDatabase(database)
    if type(database) ~= "table" then
        return false, addon.L("DATABASE_INVALID")
    end

    local currentVersion = addon.Constants.DATABASE_SCHEMA_VERSION
    local rawVersion = database.schemaVersion
    local storedVersion = rawVersion == nil and 0 or tonumber(rawVersion)
    if not storedVersion
        or storedVersion ~= storedVersion
        or storedVersion == math.huge
        or storedVersion ~= math.floor(storedVersion)
        or storedVersion < 0
    then
        return false, addon.L("DATABASE_INVALID")
    end
    if storedVersion > currentVersion then
        return false, addon.L("DATABASE_SCHEMA_TOO_NEW", storedVersion, currentVersion)
    end

    local settings = ensureTable(database, "settings")
    addon.Schema.NormalizeOnboarding(settings)
    local playerSettings = ensureTable(settings, "gameMasterPlayer")
    playerSettings.incomingActionSoundEnabled = playerSettings.incomingActionSoundEnabled == true
    playerSettings.turnSoundPreset = addon.Runtime.NormalizeSoundPreset(playerSettings.turnSoundPreset) or "ready"
    playerSettings.incomingActionSoundPreset = addon.Runtime.NormalizeSoundPreset(playerSettings.incomingActionSoundPreset) or "ready"
    ensureTable(database, "profiles")
    ensureTable(database, "importedBooks")
    ensureTable(database, "linkSnapshots")
    ensureTable(database, "exportHistory")
    ensureTable(database, "debug")
    ensureTable(database, "gameMaster")

    while storedVersion < currentVersion do
        local migrate = migrations[storedVersion]
        if type(migrate) ~= "function" or migrate(database) ~= true then
            return false, addon.L("DATABASE_MIGRATION_FAILED", storedVersion, storedVersion + 1)
        end
        storedVersion = storedVersion + 1
        database.schemaVersion = storedVersion
    end

    normalizeProfiles(database)
    normalizeGameMaster(database)
    database.schemaVersion = currentVersion
    database.addonVersion = addon.Constants.ADDON_VERSION
    return true
end
