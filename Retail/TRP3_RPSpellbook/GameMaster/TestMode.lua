local _, addon = ...
addon = addon.Shared or addon

addon.GameMasterTestMode = {}

local participantCount = 5
local autoActions = true

local colors = {
    "DDAA44", "55B8FF", "B86BFF", "65D47A", "FF796B",
    "E8D077", "72D6D1", "E58CB7",
}

local fallbackNames = {
    "Aldren Vale", "Mira Nachtwind", "Yussif", "Elayne Thorne",
    "Arion Talathar", "Nyumi", "Lazarus Rose", "Elesia Eiswind",
    "Nore Kava Jonas", "Darian Mondhauch", "Zendrel Daemmerfalke",
}

local fallbackSpells = {
    {
        id = "test_frostbolt",
        icon = 135846,
        name = "Frostblitz",
        nameColor = "55B8FF",
        range = "40 Meter",
        resource = "30 Mana",
        revision = 1,
        tags = { magicSchool = "Hervorrufung", magicType = "Elementar" },
    },
    {
        id = "test_fireball",
        icon = 135812,
        name = "Feuerball",
        nameColor = "FF7A45",
        range = "40 Meter",
        resource = "35 Mana",
        revision = 1,
        tags = { magicSchool = "Hervorrufung", magicType = "Elementar" },
    },
    {
        castTime = "2 Runden",
        id = "test_arcane",
        icon = 136096,
        name = "Arkane Geschosse",
        nameColor = "B86BFF",
        range = "40 Meter",
        resource = "50 Mana",
        revision = 1,
        tags = { castRounds = "2", magicSchool = "Hervorrufung", magicType = "Arkan" },
    },
    {
        effects = {
            buff = true,
            duration = "2 Runden",
            durationRounds = 2,
        },
        id = "test_blessing",
        icon = 135967,
        name = "Segen des Mutes",
        nameColor = "FFE36B",
        range = "40 Meter",
        revision = 1,
        tags = { magicSchool = "Verzauberung", magicType = "Licht" },
    },
    {
        id = "test_shot",
        icon = 132223,
        name = "Gezielter Schuss",
        nameColor = "E8D077",
        range = "40 Meter",
        resource = "20 Fokus",
        revision = 1,
        tags = { damageType = "Schuss", entryType = "ability" },
    },
}

local function copyTable(source)
    if type(source) ~= "table" then
        return source
    end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = copyTable(value)
    end
    return copy
end

local function getLocalMember()
    local playerID = addon.GameMasterRoster.GetLocalPlayerID()
        or "Spieler-Testrealm"
    local known = addon.GameMasterRoster.FindMember(playerID)
    if known then
        return copyTable(known)
    end
    local rpName = addon.TRP3Bridge.GetRoleplayName(playerID)
        or addon.TRP3Bridge.GetActiveProfileName()
        or playerID:match("^[^-]+")
        or "Spieler"
    return {
        gameName = playerID,
        online = true,
        playerID = playerID,
        rpName = rpName,
    }
end

local function buildMembers(count)
    local members = { getLocalMember() }
    local used = {
        [addon.Runtime.NormalizePlayerID(members[1].playerID)] = true,
    }
    local known = addon.TRP3Bridge.GetKnownRoleplayProfiles(count * 2)
    local knownIndex = 1
    for index = 2, count do
        local candidate
        while knownIndex <= #known and not candidate do
            local current = known[knownIndex]
            knownIndex = knownIndex + 1
            local key = addon.Runtime.NormalizePlayerID(current.gameName)
            if key and not used[key] then
                used[key] = true
                candidate = copyTable(current)
                candidate.playerID = current.gameName
            end
        end
        if not candidate then
            local name = fallbackNames[((index - 2) % #fallbackNames) + 1]
            candidate = {
                gameName = "Testfigur" .. tostring(index - 1) .. "-Testrealm",
                playerID = "Testfigur" .. tostring(index - 1) .. "-Testrealm",
                rpName = name,
            }
        end
        candidate.online = index % 7 ~= 0
        candidate.isMock = true
        candidate.profileColor = candidate.profileColor
            or colors[((index - 2) % #colors) + 1]
        candidate.testCompatibility = index % 5 == 0 and "missing"
            or (index % 4 == 0 and "incompatible" or "compatible")
        members[#members + 1] = candidate
    end
    return members
end

local function collectSpells()
    local spells = {}
    local book = addon.Database.GetActiveSpellbook()
    if type(book) == "table" then
        for _, tabID in ipairs(book.tabOrder or {}) do
            local tab = book.tabs and book.tabs[tabID]
            for _, spellID in ipairs(tab and tab.spellIds or {}) do
                local spell = book.spells and book.spells[spellID]
                if type(spell) == "table" then
                    local snapshot = copyTable(spell)
                    snapshot.ownerKey = book.profileKey
                    spells[#spells + 1] = snapshot
                end
            end
        end
    end
    for _, spell in ipairs(fallbackSpells) do
        local snapshot = copyTable(spell)
        snapshot.ownerKey = "test-mode"
        spells[#spells + 1] = snapshot
    end
    return spells
end

function addon.GameMasterTestMode.CreateSession(count, options)
    count = math.max(1, math.min(
        addon.Constants.GAMEMASTER_MAX_PARTICIPANTS,
        math.floor(tonumber(count) or participantCount)
    ))
    participantCount = count
    local localID = addon.GameMasterRoster.GetLocalPlayerID()
        or "Spieler-Testrealm"
    local timestamp = addon.Runtime.GetTimestamp()
    local session = {
        access = addon.GameMasterSceneAccess.Normalize(nil, "full"),
        activeBuffs = {},
        createdAt = timestamp,
        currentRoundID = nil,
        id = "test_session",
        isTestMode = true,
        name = addon.L("GAMEMASTER_TEST_SCENE"),
        nextRoundNumber = 1,
        ownerID = localID,
        ownerKey = addon.Runtime.NormalizePlayerID(localID),
        participantOrder = {},
        participants = {},
        preparations = {},
        rounds = {},
        updatedAt = timestamp,
    }
    addon.GameMasterStore.SetEncounterOptions(session,
        addon.GameMasterStore.NormalizeEncounterOptions(options, { enemyPhases = true, enemyFirst = true }))
    local members = buildMembers(count)
    addon.GameMasterStore.UpdateRoster(session, members)
    for _, member in ipairs(members) do
        local playerKey = addon.Runtime.NormalizePlayerID(member.playerID)
        local participant = playerKey and session.participants[playerKey]
        if participant then
            participant.isMock = member.isMock == true
            participant.testCompatibility = member.testCompatibility
        end
    end
    return session
end

function addon.GameMasterTestMode.GetMembers(session)
    local members = {}
    if type(session) ~= "table" then
        return members
    end
    for _, playerKey in ipairs(session.participantOrder or {}) do
        local participant = session.participants
            and session.participants[playerKey]
        if participant then
            local member = copyTable(participant)
            member.playerKey = playerKey
            members[#members + 1] = member
        end
    end
    return members
end

function addon.GameMasterTestMode.GetWorldMarkers()
    local markers = {}
    for index = 1, 8 do
        local name = string.format(
            addon.L("GAMEMASTER_TEST_MARKER_FORMAT"),
            index
        )
        local raidIcon = ({ 6, 4, 3, 7, 1, 2, 5, 8 })[index]
        local label = string.format(
            "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14:14|t %s",
            raidIcon,
            name
        )
        markers[index] = {
            color = colors[((index - 1) % #colors) + 1],
            index = index,
            isMock = true,
            label = label,
            name = name,
            raidIcon = raidIcon,
        }
    end
    return markers
end

function addon.GameMasterTestMode.PopulateRound(session, round)
    if type(session) ~= "table" or type(round) ~= "table" or (not autoActions and not session.tutorialRole) then
        return false
    end
    if session.tutorialRole then return false end
    local spells = collectSpells()
    local localKey = addon.Runtime.NormalizePlayerID(
        addon.GameMasterRoster.GetLocalPlayerID()
    )
    local changed = false
    for index, playerKey in ipairs(session.participantOrder or {}) do
        local participant = session.participants[playerKey]
        if playerKey ~= localKey and participant and index % 6 ~= 0 then
            local spell = copyTable(spells[((index + round.number - 2) % #spells) + 1])
            local isTimedEffect = type(spell.effects) == "table"
                and (spell.effects.buff == true or spell.effects.debuff == true)
            local action = not isTimedEffect
                and (index % 4 == 0 or index % 5 == 0)
                and "prepare"
                or (index % 3 == 0 and "channel" or "cast")
            local targets = {}
            if action ~= "prepare" then
                if index % 3 == 0 and not isTimedEffect then
                    local marker = addon.GameMasterTestMode.GetWorldMarkers()[
                        ((index - 1) % 8) + 1
                    ]
                    targets[1] = {
                        color = marker.color,
                        kind = "marker",
                        label = marker.label,
                        name = marker.name,
                        raidIcon = marker.raidIcon,
                        value = ((index - 1) % 8) + 1,
                    }
                else
                    local targetKey = session.participantOrder[
                        ((index + round.number - 1) % #session.participantOrder) + 1
                    ]
                    local target = session.participants[targetKey]
                    targets[1] = {
                        kind = "player",
                        label = target and target.rpName or targetKey,
                        value = target and target.playerID or targetKey,
                    }
                    if index % 4 == 2 then
                        for offset = 1, math.min(3, #session.participantOrder - 1) do
                            local extraKey = session.participantOrder[
                                ((index + offset - 1) % #session.participantOrder) + 1
                            ]
                            local extra = session.participants[extraKey]
                            targets[#targets + 1] = {
                                kind = "player",
                                label = extra and extra.rpName or extraKey,
                                value = extra and extra.playerID or extraKey,
                            }
                        end
                    end
                end
            end
            local saved = addon.GameMasterStore.SaveSubmission(
                session,
                playerKey,
                {
                    action = action,
                    aoe = #targets > 1,
                    playerID = participant.playerID,
                    preparation = action == "prepare"
                        and { required = 2 } or nil,
                    rpName = participant.rpName,
                    spell = spell,
                    targets = targets,
                }
            )
            changed = saved and true or changed
        end
    end
    return changed
end

function addon.GameMasterTestMode.ConfigureTutorial(session)
    local others = {}
    for _, key in ipairs(session.participantOrder) do
        if key ~= session.ownerKey then others[#others + 1] = key end
    end
    if #others == 3 then
        session.participantOrder = { others[1], others[2], session.ownerKey, others[3] }
    end
    session.tutorialBuffSourceKey, session.tutorialDebuffSourceKey = others[1], others[2]
    for _, participant in pairs(session.participants) do
        participant.online, participant.active, participant.testCompatibility = true, true, "compatible"
    end
end

 
function addon.GameMasterTestMode.TickTutorial(session, round, clock)
    if not session.tutorialRole or not round or round.status ~= "open" or round.phase == "enemies" then return false end
    if session.tutorialRound ~= round.id then
        session.tutorialRound, session.tutorialCursor, session.tutorialDue = round.id, 1, clock + 2
        session.tutorialActing = nil
    end
    if clock < session.tutorialDue then return false end
    local index = session.tutorialCursor
    local key = session.participantOrder[index]
    if not key then return false end
    if key == session.ownerKey then
        if session.tutorialRole == "player" and not addon.GameMasterStore.IsTurnCompleted(round, key) then return false end
        session.tutorialCursor, session.tutorialDue = index + 1, clock + 2
        return false
    end
    if not addon.GameMasterStore.IsParticipantTurnActive(session, round, key) then
        session.tutorialDue = clock + 2
        return false
    end
    if session.tutorialActing == key then
        addon.GameMasterStore.SetTurnCompleted(session, key, true, "manual")
        session.tutorialActing = nil
        session.tutorialCursor, session.tutorialDue = index + 1, clock + 2
        return true
    end
    local spellID = round.number == 1 and key == session.tutorialBuffSourceKey and "shield" or "spark"
    if round.number == 1 and key == session.tutorialDebuffSourceKey then
        spellID = "hamper"
    end
    local spell = addon.TutorialExamples.ForPractice(spellID)
    spell.id, spell.ownerKey, spell.revision = "tutorial_" .. spellID, "tutorial", 1
    if spell.effects then spell.effects.durationRounds, spell.effects.duration = 5, "5" end
    local target = session.participants[session.ownerKey]
    local participant = session.participants[key]
    local saved = addon.GameMasterStore.SaveSubmission(session, key, {
        action = "cast", playerID = participant.playerID, rpName = participant.rpName, spell = spell,
        submissionId = "tutorial_" .. round.number .. "_" .. index,
        targets = { { kind = "player", value = target.playerID, label = target.rpName } },
    })
    session.tutorialActing, session.tutorialDue = key, clock + 3
    return saved ~= nil and saved ~= false
end

function addon.GameMasterTestMode.GetParticipantCount()
    return participantCount
end

function addon.GameMasterTestMode.SetParticipantCount(value)
    participantCount = math.max(1, math.min(
        addon.Constants.GAMEMASTER_MAX_PARTICIPANTS,
        math.floor(tonumber(value) or participantCount)
    ))
    return participantCount
end

function addon.GameMasterTestMode.ShouldGenerateActions()
    return autoActions
end

function addon.GameMasterTestMode.SetGenerateActions(enabled)
    autoActions = enabled == true
    return autoActions
end
