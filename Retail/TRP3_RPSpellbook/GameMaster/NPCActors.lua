local _, addon = ...

local actors = {}
addon.GameMasterNPCActors = actors
actors.MAX_ACTORS = 20
actors.MAX_ABILITIES = 24

function actors.IsID(value)
    if type(value) ~= "string" or #value > 14 or not value:match("^npc_[1-9]%d*$") then return false end
    local serial = tonumber(value:sub(5))
    return serial ~= nil and serial <= 2147483647
end

local function text(value, limit, multiline)
    if type(value) ~= "string" or #value > limit or value:find("|")
        or value:find(multiline and "[%z\1-\8\11-\31\127]" or "[%c]") then return nil end
    return value:match("^%s*(.-)%s*$")
end

function actors.Profile(raw)
    if type(raw) ~= "table" then return nil end
    local name = text(raw.name, 120)
    if not name or name == "" then return nil end
    local color = type(raw.nameColor) == "string" and raw.nameColor:match("^%x%x%x%x%x%x$")
    local icon = raw.icon
    if type(icon) == "number" then
        if icon ~= icon or icon < 1 or icon > 2147483647 or icon ~= math.floor(icon) then icon = nil end
    else
        icon = text(icon, 200)
    end
    return {
        name = name, title = text(raw.title or "", 120) or "",
        description = text(raw.description or "", 2000, true) or "",
        nameColor = color and string.upper(raw.nameColor) or nil,
        icon = icon, area = text(raw.area or "", 120) or "",
        relationship = (raw.relationship == "friendly" or raw.relationship == "neutral"
            or raw.relationship == "hostile") and raw.relationship or nil,
    }
end

function actors.Get(session, actorID)
    return actors.IsID(actorID) and type(session) == "table"
        and type(session.npcActors) == "table" and session.npcActors[actorID] or nil
end

function actors.Copy(raw, includeSpells)
    local result = actors.Profile(raw)
    if not result then return nil end
    result.id, result.kind, result.actorKind = raw.id, "npc", "npc"
    result.templateID = raw.templateID
    result.companionGUID = text(raw.companionGUID, 128)
    result.side = raw.side == "players" and "players" or "enemies"
    result.ownerPlayerKey = type(raw.ownerPlayerKey) == "string"
        and text(raw.ownerPlayerKey, 128) and addon.Runtime.NormalizePlayerID(raw.ownerPlayerKey) or nil
    if result.ownerPlayerKey and result.ownerPlayerKey:match("^npc_") then result.ownerPlayerKey = nil end
    local revision = tonumber(raw.revision)
    result.revision = revision and revision >= 1 and revision <= 2147483647
        and revision == math.floor(revision) and revision or 1
    result.spellCount = math.min(actors.MAX_ABILITIES, #(type(raw.spells) == "table" and raw.spells or {}))
    result.released, result.active = raw.released == true, raw.released == true
    result.markerIndex = type(raw.markerIndex) == "number" and raw.markerIndex >= 1
        and raw.markerIndex <= 8 and raw.markerIndex == math.floor(raw.markerIndex) and raw.markerIndex or nil
    if includeSpells then
        result.spells = {}
        local seen = {}
        for index, spell in ipairs(type(raw.spells) == "table" and raw.spells or {}) do
            if index > actors.MAX_ABILITIES then break end
            if type(spell) == "table" then
                local valid, clean = addon.Validators.ValidateSpell(spell)
                local spellID = text(spell.id, addon.Constants.MAX_LINK_SPELL_ID_LENGTH)
                if valid and spellID and spellID ~= "" and not seen[spellID] then
                    seen[spellID] = true
                    clean.id = spellID
                    local revision = tonumber(spell.revision)
                    clean.revision = revision and revision >= 1 and revision <= addon.Constants.MAX_LINK_REVISION
                        and revision == math.floor(revision) and revision or 1
                    clean.ownerKey = "npc-register"
                    result.spells[#result.spells + 1] = clean
                end
            end
        end
    end
    return result
end

function actors.List(session, releasedOnly, includeSpells)
    local result = {}
    for _, actorID in ipairs(type(session) == "table" and session.npcOrder or {}) do
        local actor = actors.Get(session, actorID)
        if actor and (not releasedOnly or actor.released) then result[#result + 1] = actors.Copy(actor, includeSpells ~= false) end
        if #result >= actors.MAX_ACTORS then break end
    end
    return result
end

function actors.NormalizeSession(session)
    local saved = type(session.npcActors) == "table" and session.npcActors or {}
    local order, cleaned, seen = {}, {}, {}
    local serial = tonumber(session.nextNPCSerial) or 1
    if serial ~= serial or serial < 1 or serial > 2147483647 then serial = 1 end
    serial = math.floor(serial)
    local function accept(actorID)
        if seen[actorID] or #order >= actors.MAX_ACTORS or not actors.IsID(actorID) then return end
        seen[actorID] = true
        local raw = saved[actorID]
        local actor = actors.Copy(raw, true)
        if actor then
            actor.id = actorID
            actor.templateID = text(raw.templateID, 96)
            actor.ownerPlayerKey = actor.ownerPlayerKey or session.ownerKey
            cleaned[actorID], order[#order + 1] = actor, actorID
            serial = math.max(serial, (tonumber(actorID:sub(5)) or 0) + 1)
        end
    end
    for index, actorID in ipairs(type(session.npcOrder) == "table" and session.npcOrder or {}) do
        if index > actors.MAX_ACTORS * 4 then break end
        accept(actorID)
    end
    local scanned = 0
    for actorID in pairs(saved) do
        scanned = scanned + 1
        if scanned > actors.MAX_ACTORS * 4 or #order >= actors.MAX_ACTORS then break end
        accept(actorID)
    end
    session.npcActors, session.npcOrder, session.nextNPCSerial = cleaned, order, serial
end

function actors.Add(session, template)
    if type(session) ~= "table" then return nil, addon.L("GAMEMASTER_SESSION_NOT_FOUND") end
    if #(session.npcOrder or {}) >= actors.MAX_ACTORS then return nil, addon.L("GAMEMASTER_NPC_LIMIT") end
    local actor = actors.Copy(template, true)
    if not actor then return nil, addon.L("GAMEMASTER_INVALID_SUBMISSION") end
    local serial = session.nextNPCSerial or 1
    if serial > 2147483647 then return nil, addon.L("GAMEMASTER_NPC_LIMIT") end
    local actorID = "npc_" .. tostring(serial)
    if actors.Get(session, actorID) then return nil, addon.L("GAMEMASTER_INVALID_SUBMISSION") end
    actor.id, actor.kind, actor.actorKind = actorID, "npc", "npc"
    actor.released, actor.active, actor.markerIndex = false, false, nil
    actor.revision = 1
    actor.ownerPlayerKey = actor.ownerPlayerKey or session.ownerKey
    if template.side == nil and template.relationship == "friendly" then actor.side = "players" end
    actor.templateID = text(template.templateID, 96)
    session.npcActors, session.npcOrder = session.npcActors or {}, session.npcOrder or {}
    session.npcActors[actorID] = actor
    session.npcOrder[#session.npcOrder + 1] = actorID
    session.nextNPCSerial = serial + 1
     
    if actor.side ~= "players" then session.enemyPhases = true end
    return actor
end

function actors.IsOnline(session, actor)
    if actor.side ~= "players" then return true end
    local participant = session.participants and session.participants[actor.ownerPlayerKey or session.ownerKey]
    return participant ~= nil and participant.online ~= false
end

function actors.IsTurnActive(session, round, actorID)
    local actor = actors.Get(session, actorID)
    if not actor or not actor.released or type(round) ~= "table" then return false end
    if actor.side ~= "players" then return round.phase == "enemies" end
    local owner = actor.ownerPlayerKey or session.ownerKey
    local participant = session.participants and session.participants[owner]
    return round.phase ~= "enemies" and participant ~= nil and participant.online ~= false
        and participant.active ~= false
        and not (round.inactiveParticipants and round.inactiveParticipants[owner])
end

function actors.CanAct(session, round, actorID)
    if not actors.IsTurnActive(session, round, actorID) then return false end
    local actor = actors.Get(session, actorID)
    return actor.side ~= "players" or not actors.IsCompleted(session, round, actor)
end

function actors.CanControl(session, actor, playerKey)
    return actor ~= nil and (session.ownerKey == playerKey
        or actor.side == "players" and actor.ownerPlayerKey == playerKey)
end

function actors.HasIndependentTurn(session, actor)
    return actor ~= nil and (actor.side ~= "players" or session.gmParticipates == false
        and (actor.ownerPlayerKey or session.ownerKey) == session.ownerKey)
end

function actors.IsCompleted(session, round, actor)
    if not round then return false end
    if not actors.HasIndependentTurn(session, actor) then
        return round.completedTurns and round.completedTurns[actor.ownerPlayerKey or session.ownerKey] ~= nil or false
    end
    return round.npcCompletedTurns and round.npcCompletedTurns[actor.id] == true or false
end

 
function actors.ControlUnits(session, playerKey)
    local units = {}
    local round = addon.GameMasterStore.GetCurrentRound(session)
    for _, actorID in ipairs(session.npcOrder or {}) do
        local source = actors.Get(session, actorID)
        if source and source.released and source.side == "players" and source.ownerPlayerKey == playerKey then
            local actor = actors.Copy(source, true)
            local spells = actor.spells
            actor.spells = nil
            local submission = round and round.npcSubmissions and round.npcSubmissions[actor.id]
            units[#units + 1] = { actor = actor, submission = submission and {
                actions = addon.GameMasterVisibility.CopyActions(submission, session),
            } or nil }
            for _, spell in ipairs(spells) do units[#units + 1] = { actorID = actor.id, spell = spell } end
        end
    end
    return units
end

function actors.ValidateControlUnits(units, playerKey)
    if units == nil then units = {} end
    local count = addon.Runtime.GetBoundedArrayLength(units, actors.MAX_ACTORS * (actors.MAX_ABILITIES + 1))
    if not count then return nil end
    local result, total = {}, 0
    for _, unit in ipairs(units) do
        if type(unit) ~= "table" then return nil end
        if unit.actor then
            local actor = actors.Copy(unit.actor, true)
            if not actor or not actors.IsID(actor.id) or result[actor.id] or not actor.released
                or actor.side ~= "players" or actor.ownerPlayerKey ~= playerKey then return nil end
            total = total + 1
            if total > actors.MAX_ACTORS then return nil end
            actor.spells = {}
            if unit.submission ~= nil then
                if type(unit.submission) ~= "table" then return nil end
                local actions = unit.submission.actions
                if actions == nil then actions = { unit.submission } end
                local actionCount = addon.Runtime.GetBoundedArrayLength(
                    actions, addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER)
                if not actionCount or actionCount < 1 then return nil end
                local entries = addon.GameMasterVisibility.ValidateEntries({ {
                    playerID = actor.id, rpName = actor.name, actorKind = "npc", npcProfile = actor,
                    actions = actions,
                } }, "full")
                if not entries then return nil end
                actor.lastSubmission = entries[1]
            end
            result[actor.id] = actor
        else
            local actor = result[unit.actorID]
            local copy = actor and actors.Copy({ name = actor.name, spells = { unit.spell } }, true)
            if not copy or #copy.spells ~= 1 or #actor.spells >= actors.MAX_ABILITIES then return nil end
            for _, existing in ipairs(actor.spells) do if existing.id == copy.spells[1].id then return nil end end
            actor.spells[#actor.spells + 1] = copy.spells[1]
        end
    end
    return result
end

function actors.Target(actor)
    local marker = actor.markerIndex and addon.GameMasterRoster
        and addon.GameMasterRoster.GetWorldMarker(actor.markerIndex)
    return { kind = "npc", value = actor.id, label = actor.name, name = actor.name,
        color = actor.nameColor, icon = marker and marker.raidIcon
            and ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. marker.raidIcon) or actor.icon }
end
