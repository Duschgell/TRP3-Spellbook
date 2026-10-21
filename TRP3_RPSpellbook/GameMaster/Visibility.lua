local _, addon = ...

addon.GameMasterVisibility = {}

local modes = {
    full = true,
    targets = true,
    hidden = true,
}

local cycle = {
    full = "targets",
    targets = "hidden",
    hidden = "full",
}

local markerDefinitions = {
    [1] = { labelKey = "GAMEMASTER_MARKER_SQUARE", raidIcon = 6 },
    [2] = { labelKey = "GAMEMASTER_MARKER_TRIANGLE", raidIcon = 4 },
    [3] = { labelKey = "GAMEMASTER_MARKER_DIAMOND", raidIcon = 3 },
    [4] = { labelKey = "GAMEMASTER_MARKER_CROSS", raidIcon = 7 },
    [5] = { labelKey = "GAMEMASTER_MARKER_STAR", raidIcon = 1 },
    [6] = { labelKey = "GAMEMASTER_MARKER_CIRCLE", raidIcon = 2 },
    [7] = { labelKey = "GAMEMASTER_MARKER_MOON", raidIcon = 5 },
    [8] = { labelKey = "GAMEMASTER_MARKER_SKULL", raidIcon = 8 },
}

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

local function cleanColor(value)
    if type(value) ~= "string" or not value:match("^%x%x%x%x%x%x$") then
        return nil
    end
    return string.upper(value)
end

local function cleanProfileIcon(value)
    if type(value) == "number" then
        return readInteger(value, 0, addon.Constants.MAX_IMPORT_SAFE_INTEGER)
    end
    return type(value) == "string" and cleanText(value, 200) or nil
end

local function copyTags(tags)
    local result = {}
    for key, value in pairs(type(tags) == "table" and tags or {}) do
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
    if type(spell) ~= "table" then
        return nil
    end
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

local function copyTargets(submission, session)
    local result = {}
    for _, target in ipairs(
        addon.GameMasterActionPresentation.GetTargets(submission)
    ) do
        local npc = type(target) == "table" and target.kind == "npc" and addon.GameMasterNPCActors
            and addon.GameMasterNPCActors.Get(session, target.value)
        if type(target) == "table" and (target.kind ~= "npc" or npc and npc.released) then
            result[#result + 1] = {
                color = target.color,
                health = target.health,
                icon = target.icon,
                kind = target.kind,
                label = target.label,
                name = target.name,
                value = target.value,
            }
        end
        if #result >= addon.Constants.GAMEMASTER_MAX_TARGETS then
            break
        end
    end
    return result
end

local function copyAllTargets(submission, session)
    local result = {}
    local seen = {}
    for _, action in ipairs(
        addon.GameMasterActionCollection.Get(submission)
    ) do
        for _, target in ipairs(copyTargets(action, session)) do
            local key = target.kind .. ":" .. tostring(target.value):lower()
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = target
            end
            if #result >= addon.Constants.GAMEMASTER_MAX_TARGETS then
                return result
            end
        end
    end
    return result
end

local function copyAction(submission, session)
    local targets = copyTargets(submission, session)
    return {
        action = submission.action,
        preparation = type(submission.preparation) == "table" and {
            progress = submission.preparation.progress,
            required = submission.preparation.required,
        } or nil,
        spell = copySpell(submission.spell),
        submissionId = submission.submissionId,
        target = targets[1],
        targets = targets,
    }
end

function addon.GameMasterVisibility.Normalize(mode, fallback)
    if modes[mode] then
        return mode
    end
    return modes[fallback] and fallback or "hidden"
end

function addon.GameMasterVisibility.Next(mode)
    return cycle[addon.GameMasterVisibility.Normalize(mode)]
end

function addon.GameMasterVisibility.CanRevealNPCActions(session, round)
    return type(session) == "table" and type(round) == "table"
        and (session.deferEnemyActions == false or round.enemyActionsRevealed == true
            or session.enemyFirst == true and round.phase == "players")
end

function addon.GameMasterVisibility.CopyActions(submission, session)
    local actions = {}
    for _, action in ipairs(addon.GameMasterActionCollection.Get(submission)) do
        actions[#actions + 1] = copyAction(action, session)
    end
    return actions
end

function addon.GameMasterVisibility.GetNPCActionRound(session, round)
    if type(session) ~= "table" or type(round) ~= "table" then return nil end
    if session.enemyFirst ~= true and round.phase ~= "enemies" then
        return addon.GameMasterStore.GetPreviousRound(session, round)
    end
    return round
end

function addon.GameMasterVisibility.BuildEntries(session, round, mode, showUnrevealed)
    mode = addon.GameMasterVisibility.Normalize(mode)
    if type(session) ~= "table"
        or type(round) ~= "table"
    then
        return {}
    end

    local entries = {}
    for _, playerKey in ipairs(session.participantOrder or {}) do
        local participant = session.participants
            and session.participants[playerKey]
        local submission = round.submissions
            and round.submissions[playerKey]
        local narrator = addon.GameMasterStore.IsNarrator(session, playerKey)
        if narrator or round.phase == "enemies" then submission = nil end
        if type(participant) == "table"
            and not (session.gmParticipates == false and playerKey == session.ownerKey) then
            local hasSubmission = type(submission) == "table"
            local entry = {
                active = addon.GameMasterStore.IsParticipantTurnActive(session, round, playerKey),
                actorKind = narrator and "narrator" or "player",
                online = participant.online ~= false,
                completed = addon.GameMasterStore.IsTurnCompleted(round, playerKey),
                turnSequence = type(round.turnSequences) == "table"
                    and round.turnSequences[playerKey] or 0,
                firstName = participant.firstName,
                gameName = participant.gameName,
                lastName = participant.lastName,
                playerID = participant.playerID,
                profileColor = participant.profileColor,
                profileIcon = participant.profileIcon,
                rpName = hasSubmission and submission.rpName
                    or participant.rpName
                    or participant.gameName,
                targets = mode ~= "hidden" and hasSubmission
                    and copyAllTargets(submission, session) or {},
                title = participant.title,
            }
            if narrator then
                local name = addon.GameMasterStore.GetEncounterOptions(session).narratorName
                entry.rpName, entry.firstName, entry.gameName = name, name, name
                entry.lastName, entry.title, entry.profileIcon, entry.profileColor = nil, nil, nil, nil
            end
            entry.target = entry.targets[1]
            if mode == "full" and hasSubmission then
                local actions = {}
                for _, action in ipairs(
                    addon.GameMasterActionCollection.Get(submission)
                ) do
                    actions[#actions + 1] = copyAction(action, session)
                end
                local latest = actions[#actions]
                entry.actions = actions
                entry.action = latest and latest.action
                entry.preparation = latest and latest.preparation
                entry.spell = latest and latest.spell
            end
            entries[#entries + 1] = entry
        end
        if #entries >= addon.Constants.GAMEMASTER_MAX_PARTICIPANTS then
            break
        end
    end
    local npcRound = addon.GameMasterVisibility.GetNPCActionRound(session, round)
    local revealNPCs = showUnrevealed == true
        or addon.GameMasterVisibility.CanRevealNPCActions(session, npcRound)
    for _, actorID in ipairs(session.npcOrder or {}) do
        local actor = addon.GameMasterNPCActors and addon.GameMasterNPCActors.Get(session, actorID)
        if actor and actor.released then
            local actionRound = actor.side == "players" and round or npcRound
            local revealed = actor.side == "players" or revealNPCs
            local submission = revealed and actionRound and actionRound.npcSubmissions
                and actionRound.npcSubmissions[actorID]
            local entry = {
                actorKind = "npc", kind = "npc", playerID = actorID, playerKey = actorID,
                rpName = actor.name, firstName = actor.name, gameName = actor.name,
                profileColor = actor.nameColor, profileIcon = actor.icon, title = actor.title,
                npcProfile = addon.GameMasterNPCActors.Profile(actor), markerIndex = actor.markerIndex,
                side = actor.side, ownerPlayerKey = actor.ownerPlayerKey or session.ownerKey,
                online = addon.GameMasterNPCActors.IsOnline(session, actor),
                active = addon.GameMasterNPCActors.IsTurnActive(session, round, actorID), turnSequence = 0,
                completed = revealed and addon.GameMasterNPCActors.IsCompleted(session, actionRound, actor),
                targets = mode ~= "hidden" and submission and copyAllTargets(submission, session) or {},
            }
            entry.target = entry.targets[1]
            if mode == "full" and submission then
                entry.actions = {}
                for _, action in ipairs(addon.GameMasterActionCollection.Get(submission)) do
                    entry.actions[#entry.actions + 1] = copyAction(action, session)
                end
                local latest = entry.actions[#entry.actions]
                entry.action = latest and latest.action
                entry.spell = latest and latest.spell
                entry.preparation = latest and latest.preparation
            end
            entries[#entries + 1] = entry
        end
        if #entries >= (addon.Constants.GAMEMASTER_MAX_VISIBLE_ACTORS or 60) then break end
    end
    return entries
end

 
function addon.GameMasterVisibility.LegacyEntries(entries)
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = copy(item) end
        if result.kind == "npc" then
            result.kind, result.value = "text", result.label
        end
        return result
    end
    local result = {}
    for _, entry in ipairs(entries or {}) do
        if entry.actorKind ~= "npc" then result[#result + 1] = copy(entry) end
    end
    return result
end

local function copyWithoutDebuffs(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        result[key] = copyWithoutDebuffs(item)
    end
    local effects = type(result.spell) == "table" and result.spell.effects or nil
    if type(effects) == "table" and effects.debuff == true then
        effects.debuff, effects.debuffType = nil, nil
        effects.duration, effects.durationRounds, effects.durationSeconds = nil, nil, nil
        if effects.healing ~= true and effects.buff ~= true then
            result.spell.effects = nil
        end
    end
    return result
end

 
 
function addon.GameMasterVisibility.LegacyPermanentPayload(value)
    if type(value) ~= "table" then return value end
    local result = {}
    local function copyItem(key, item, arrayItem)
        local effects = type(item) == "table" and type(item.spell) == "table" and item.spell.effects
        local permanentEntry = effects and effects.durationRounds == 0
            and item.appliedRound ~= nil and item.appliedAt ~= nil
        if not permanentEntry then
            local copied = addon.GameMasterVisibility.LegacyPermanentPayload(item)
            if arrayItem then
                result[#result + 1] = copied
            else
                result[key] = copied
            end
        end
    end
    for index = 1, #value do copyItem(index, value[index], true) end
    for key, item in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > #value or key ~= math.floor(key) then
            copyItem(key, item, false)
        end
    end
    if result.durationRounds == 0 then result.durationRounds = nil end
    return result
end

 
function addon.GameMasterVisibility.LegacyDebuffEntries(entries)
    return copyWithoutDebuffs(entries or {})
end

function addon.GameMasterVisibility.LegacyBuffStates(states)
    local result = {}
    for _, state in ipairs(states or {}) do
        local buffs = {}
        for _, entry in ipairs(type(state.buffs) == "table" and state.buffs or {}) do
            local effects = type(entry.spell) == "table" and entry.spell.effects or nil
            if type(effects) ~= "table" or effects.debuff ~= true then
                buffs[#buffs + 1] = entry
            end
        end
        if #buffs > 0 then
            result[#result + 1] = {
                buffs = buffs,
                playerKey = state.playerKey,
            }
        end
    end
    return result
end

local function formatMarkerLabel(index, name, color, health)
    local definition = markerDefinitions[index]
    if not definition then
        return nil
    end
    local displayName = name or addon.L(definition.labelKey)
    if color then
        displayName = string.format("|cff%s%s|r", color, displayName)
    end
    if health then
        displayName = string.format(
            "%s |cffb8b8b8(%d%%)|r",
            displayName,
            health
        )
    end
    return string.format(
        "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14:14|t %s",
        definition.raidIcon,
        displayName
    )
end

local function cleanTarget(target)
    if type(target) ~= "table"
        or not addon.Constants.GAMEMASTER_TARGET_TYPES[target.kind]
    then
        return nil
    end

    local color = target.color ~= nil and cleanColor(target.color) or nil
    if target.color ~= nil and not color then
        return nil
    end
    if target.kind == "marker" then
        local index = readInteger(target.value, 1, 8)
        local name = target.name ~= nil and cleanText(
            target.name,
            addon.Constants.GAMEMASTER_MAX_TARGET_LENGTH
        ) or nil
        local health = target.health ~= nil
            and readInteger(target.health, 0, 100)
            or nil
        if not index
            or (target.name ~= nil and not name)
            or (target.health ~= nil and health == nil)
        then
            return nil
        end
        return {
            color = color,
            health = health,
            kind = "marker",
            label = formatMarkerLabel(index, name, color, health),
            name = name,
            value = index,
        }
    end

    local label = cleanText(
        target.label,
        addon.Constants.GAMEMASTER_MAX_TARGET_LENGTH
    )
    local icon = target.icon ~= nil and cleanProfileIcon(target.icon) or nil
    if not label or (target.icon ~= nil and icon == nil) then
        return nil
    end
    if target.kind == "npc" and (not addon.GameMasterNPCActors
        or not addon.GameMasterNPCActors.IsID(target.value)) then return nil end
    return {
        color = color,
        icon = icon,
        kind = target.kind,
        label = label,
        value = target.kind == "npc" and addon.GameMasterNPCActors
            and addon.GameMasterNPCActors.IsID(target.value) and target.value or label,
    }
end

local function cleanSpell(spell)
    if type(spell) ~= "table" then
        return nil
    end
    local valid, cleaned = addon.Validators.ValidateSpell(spell)
    if not valid then
        return nil
    end
    cleaned.id = cleanText(
        spell.id,
        addon.Constants.MAX_LINK_SPELL_ID_LENGTH
    )
    cleaned.ownerKey = cleanText(
        spell.ownerKey,
        addon.Constants.MAX_LINK_OWNER_LENGTH
    )
    cleaned.revision = readInteger(
        spell.revision,
        1,
        addon.Constants.MAX_LINK_REVISION
    )
    return cleaned.id
        and cleaned.ownerKey
        and cleaned.revision
        and cleaned
        or nil
end

function addon.GameMasterVisibility.ValidateEntries(rawEntries, mode)
    mode = addon.GameMasterVisibility.Normalize(mode)
    local entryCount = addon.Runtime.GetBoundedArrayLength(
        rawEntries,
        addon.Constants.GAMEMASTER_MAX_VISIBLE_ACTORS or addon.Constants.GAMEMASTER_MAX_PARTICIPANTS
    )
    if not entryCount then
        return nil
    end

    local entries = {}
    for index = 1, entryCount do
        local raw = rawEntries[index]
        local rpName = type(raw) == "table" and cleanText(
            raw.rpName,
            addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
        ) or nil
        if not rpName then
            return nil
        end

        local rawTargets = mode == "hidden" and {} or raw.targets
        if rawTargets == nil then
            if raw.target ~= nil and type(raw.target) ~= "table" then
                return nil
            end
            rawTargets = raw.target and { raw.target } or {}
        end
        local targetCount = addon.Runtime.GetBoundedArrayLength(
            rawTargets,
            addon.Constants.GAMEMASTER_MAX_TARGETS
        )
        if not targetCount then
            return nil
        end
        local targets = {}
        for targetIndex = 1, targetCount do
            local target = cleanTarget(rawTargets[targetIndex])
            if not target then
                return nil
            end
            targets[targetIndex] = target
        end

        local profileColor = raw.profileColor ~= nil
            and cleanColor(raw.profileColor)
            or nil
        local profileIcon = raw.profileIcon ~= nil
            and cleanProfileIcon(raw.profileIcon)
            or nil
        if (raw.profileColor ~= nil and not profileColor)
            or (raw.profileIcon ~= nil and profileIcon == nil)
        then
            return nil
        end

        local npcProfile
        if raw.actorKind == "npc" then
            if not addon.GameMasterNPCActors or not addon.GameMasterNPCActors.IsID(raw.playerID) then return nil end
            npcProfile = addon.GameMasterNPCActors.Profile(raw.npcProfile)
            if not npcProfile then return nil end
        elseif addon.GameMasterNPCActors and addon.GameMasterNPCActors.IsID(raw.playerID) then
            return nil
        end
        local entry = {
            active = raw.active ~= false,
            actorKind = npcProfile and "npc" or raw.actorKind == "narrator" and "narrator" or "player",
            kind = npcProfile and "npc" or nil,
            npcProfile = npcProfile,
            side = npcProfile and (raw.side == "players" and "players" or "enemies") or nil,
            ownerPlayerKey = npcProfile and cleanText(raw.ownerPlayerKey, 128) or nil,
            markerIndex = npcProfile and readInteger(raw.markerIndex, 1, 8) or nil,
            playerKey = npcProfile and raw.playerID or nil,
            online = raw.online ~= false,
            completed = raw.completed == true,
            turnSequence = readInteger(raw.turnSequence, 0,
                addon.Constants.MAX_IMPORT_SAFE_INTEGER) or 0,
            firstName = cleanText(
                raw.firstName,
                addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
            ),
            gameName = cleanText(
                raw.gameName,
                addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
            ),
            lastName = cleanText(
                raw.lastName,
                addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
            ),
            playerID = cleanText(
                raw.playerID,
                addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
            ),
            profileColor = profileColor,
            profileIcon = profileIcon,
            rpName = rpName,
            target = targets[1],
            targets = targets,
            title = cleanText(
                raw.title,
                addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
            ),
        }
        if mode == "full" then
            local hasAction = raw.action ~= nil
                or raw.spell ~= nil
                or raw.preparation ~= nil
            if hasAction then
                if not addon.Constants.GAMEMASTER_ACTIONS[raw.action] then
                    return nil
                end
                entry.action = raw.action
                if raw.preparation ~= nil then
                    if raw.action ~= "prepare"
                        or type(raw.preparation) ~= "table"
                    then
                        return nil
                    end
                    local progress = readInteger(
                        raw.preparation.progress, 0, 100
                    )
                    local required = readInteger(
                        raw.preparation.required, 1, 100
                    )
                    if progress == nil
                        or not required
                        or progress > required
                    then
                        return nil
                    end
                    entry.preparation = {
                        progress = progress,
                        required = required,
                    }
                end
                entry.spell = cleanSpell(raw.spell)
                if not entry.spell then
                    return nil
                end
                if raw.submissionId ~= nil then
                    entry.submissionId = cleanText(
                        raw.submissionId,
                        addon.Constants.GAMEMASTER_MAX_SESSION_ID_LENGTH
                    )
                    if not entry.submissionId then
                        return nil
                    end
                end
            end
            if raw.actions ~= nil then
                local actionCount = addon.Runtime.GetBoundedArrayLength(
                    raw.actions,
                    addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER
                )
                if not actionCount or actionCount < 1 then
                    return nil
                end
                local actions = {}
                for actionIndex = 1, actionCount do
                    local rawAction = raw.actions[actionIndex]
                    if type(rawAction) ~= "table"
                        or rawAction.actions ~= nil
                    then
                        return nil
                    end
                    local validated =
                        addon.GameMasterVisibility.ValidateEntries({ {
                            action = rawAction.action,
                            preparation = rawAction.preparation,
                            rpName = rpName,
                            spell = rawAction.spell,
                            submissionId = rawAction.submissionId,
                            target = rawAction.target,
                            targets = rawAction.targets,
                        } }, "full")
                    local actionEntry = validated and validated[1]
                    if not actionEntry or not actionEntry.action then
                        return nil
                    end
                    actions[actionIndex] = {
                        action = actionEntry.action,
                        preparation = actionEntry.preparation,
                        spell = actionEntry.spell,
                        submissionId = actionEntry.submissionId,
                        target = actionEntry.target,
                        targets = actionEntry.targets,
                    }
                end
                local latest = actions[#actions]
                entry.actions = actions
                entry.action = latest.action
                entry.preparation = latest.preparation
                entry.spell = latest.spell
            end
        end
        entries[index] = entry
    end
    return entries
end
