local _, addon = ...
addon.TimedEncounterEffects = {}
local bridge, store = addon.TimedEncounterEffects, addon.TimedEffectsStore
local busy, lastSent, initialized = false, {}, false
local dismissals = {}
local warnedLegacyActivation
local warnedUnsupportedActivation
local nextBurst = 0
local audienceRetries = setmetatable({}, { __mode = "k" })
local function me() return addon.Runtime.NormalizePlayerID(addon.GameMasterRoster.GetLocalPlayerID()) end
local function isolated() return addon.GameMasterService.IsTutorialActive() or addon.GameMasterService.IsTestMode() end
local function context() return addon.GameMasterService.GetSubmissionContext() end
local function same(a, b)
    return a and b and a.activationID == b.activationID and a.sessionID == b.sessionID
end
local function send(target, kind, payload)
    return addon.Communication.Send(target, "effect." .. kind, payload)
end
local function terminate(transfer)
    if not transfer.terminal then transfer.terminal = true; store.TransferChanged() end
end

local function receipts(session, activationID)
    if type(session.timedEffectImports) ~= "table" or session.timedEffectImports.activationID ~= activationID then
        session.timedEffectImports = { activationID = activationID, players = {}, serial = 0 }
    end
    if type(session.timedEffectImports.players) ~= "table" then session.timedEffectImports.players = {} end
    if type(session.timedEffectImports.serial) ~= "number" then session.timedEffectImports.serial = 0 end
    return session.timedEffectImports
end

 
function bridge.Receive(sender, payload, remove)
    if isolated() or not addon.GameMasterService.IsPrimaryGameMaster() or type(payload) ~= "table" then return end
    local current, session = context(), addon.GameMasterService.GetActiveSession()
    local playerKey = addon.Runtime.NormalizePlayerID(sender)
    if not same(current, payload) or not session or not session.participants[playerKey]
        or not store.ValidID(payload.id) then return end
    local function reject(reason)
         
        if payload.result == true then
            local reply = { id = payload.id, activationID = current.activationID, sessionID = current.sessionID, rejected = reason }
            if playerKey == me() then bridge.Acknowledge(reply, sender) else send(sender, "combat_ack", reply) end
        end
    end
    local imports = receipts(session, current.activationID)
    local player = imports.players[playerKey]
    if type(player) ~= "table" then player = {}; imports.players[playerKey] = player end
    local receipt = player[payload.id]
    if type(receipt) ~= "table" then receipt = nil end
    local changed = false
    if not receipt then
        local count = 0
        for _ in pairs(player) do count = count + 1 end
        if count >= 32 then reject("capacity"); return end
        if remove then
            receipt = { removed = true }
        else
            local entry = store.ValidateEntry(payload.entry)
            if not entry or entry.id ~= payload.id or current.roundNumber ~= 1
                or (entry.hidden and not addon.Runtime.IsSafeIdentifier(payload.ownerProfile, 200)) then reject("ineligible"); return end
            local round = addon.GameMasterService.GetActiveRound()
            if not round then return end
            local entries = addon.GameMasterEffects.GetActiveBuffs(session, playerKey)
            if #entries >= addon.Constants.GAMEMASTER_MAX_ACTIVE_BUFFS_PER_PLAYER then reject("capacity"); return end
            imports.serial = imports.serial + 1
            local origin = "timed:" .. imports.serial
            local duration = entry.spell.effects.durationRounds
            if duration ~= nil then entry.spell.effects.durationSeconds = nil
            else entry.spell.effects.durationSeconds = entry.expiresAt - addon.Runtime.GetTimestamp() end
            session.activeBuffs = session.activeBuffs or {}
            session.activeBuffs[playerKey] = entries
            entries[#entries + 1] = {
                appliedAt = addon.Runtime.GetTimestamp(), appliedRound = round.number,
                expiresRound = duration and duration ~= 0 and round.number + duration or nil,
                expiresAt = duration == nil and entry.expiresAt or nil,
                identity = entry.source .. "\031" .. entry.spell.id,
                sourcePlayerKey = entry.source, sourceRoundID = origin, spell = entry.spell,
                hidden = entry.hidden, ownerProfile = entry.hidden and payload.ownerProfile or nil,
                readers = entry.hidden and addon.EffectVisibility.CleanReaders(payload.readers) or nil,
            }
            receipt = { origin = origin, readerCount = entry.hidden and addon.Runtime.CountEntries(entries[#entries].readers) or nil }
        end
        player[payload.id] = receipt
        changed = true
    end
    if remove and not receipt.removed then
        session.activeBuffs = session.activeBuffs or {}
        for index = #(session.activeBuffs[playerKey] or {}), 1, -1 do
            if session.activeBuffs[playerKey][index].sourceRoundID == receipt.origin then
                table.remove(session.activeBuffs[playerKey], index)
            end
        end
        receipt.removed = true
        changed = true
    end
    if changed then addon.GameMasterService.PublishTimedEffects() end
    local reply = { id = payload.id, activationID = current.activationID, sessionID = current.sessionID,
        origin = receipt.origin, removed = receipt.removed == true, readerCount = receipt.readerCount }
    if playerKey == me() then bridge.Acknowledge(reply, sender) else send(sender, "combat_ack", reply) end
end

function bridge.ReceiveVisibility(sender, payload)
    if isolated() or not addon.GameMasterService.IsPrimaryGameMaster() or type(payload) ~= "table"
        or not same(context(), payload) then return end
    local session, player = addon.GameMasterService.GetActiveSession(), addon.Runtime.NormalizePlayerID(sender)
    local imports = session and session.timedEffectImports
    local receipt = imports and imports.players and imports.players[player] and imports.players[player][payload.id]
    if not receipt or receipt.removed then return end
    for _, entry in ipairs((session.activeBuffs or {})[player] or {}) do
        if entry.hidden and entry.sourceRoundID == receipt.origin and entry.ownerProfile == payload.ownerProfile then
            local previous = addon.Runtime.CountEntries(entry.readers)
            local readers = addon.EffectVisibility.CleanReaders(entry.readers)
            for identity in pairs(addon.EffectVisibility.CleanReaders(payload.readers)) do readers[identity] = true end
            entry.readers = addon.EffectVisibility.CleanReaders(readers)
            receipt.readerCount = addon.Runtime.CountEntries(entry.readers)
            if previous ~= receipt.readerCount then addon.GameMasterService.PublishTimedEffects() end
            local reply = { id = payload.id, activationID = payload.activationID, sessionID = payload.sessionID,
                origin = receipt.origin, readerCount = receipt.readerCount }
            if player == me() then bridge.Acknowledge(reply, sender) else send(sender, "combat_ack", reply) end
            return
        end
    end
end

function bridge.Acknowledge(payload, sender)
    if isolated() or type(payload) ~= "table" or not same(context(), payload) then return end
    local transfer = store.Transfers()[payload.id]
    if not transfer or not same(transfer, payload)
        or addon.Runtime.NormalizePlayerID(sender) ~= transfer.gameMaster then return end
    if payload.rejected == "capacity" or payload.rejected == "ineligible" then
        if not transfer.acknowledged then terminate(transfer) end
        return
    end
    if payload.removed ~= true and not store.ValidID(payload.origin) then return end
    local acknowledged, removed, origin, readerCount = transfer.acknowledged, transfer.removed, transfer.origin, transfer.readerCount
    if payload.removed then transfer.removed, transfer.acknowledged = true, true
    elseif not transfer.removed then
        transfer.acknowledged = true
        transfer.terminal = nil
        transfer.origin = store.ValidID(payload.origin) and payload.origin or nil
        local count = payload.readerCount
        transfer.readerCount = type(count) == "number" and count % 1 == 0 and count >= 0 and count <= 256 and count or nil
    end
    if acknowledged ~= transfer.acknowledged or removed ~= transfer.removed
        or origin ~= transfer.origin or readerCount ~= transfer.readerCount then store.TransferChanged() end
    if transfer.removed then store.Remove(payload.id)
    else store.RestoreTransferred(transfer) end
end

function bridge.Remove(id)
    local transfer = store.Transfers()[id]
    if not transfer then return false end
    transfer.removed, transfer.acknowledged = true, false
    transfer.terminal, transfer.attempts, transfer.nextAttempt = nil, 0, nil
    store.TransferChanged()
    lastSent[id] = nil
    bridge.Sync()
    return true
end

function bridge.IsDismissed(source, spellID, entry)
    local current = context()
    local identity = tostring(source) .. "\031" .. tostring(spellID)
    local pending = dismissals[identity]
    if pending and same(pending, current) and pending.profile == addon.Database.GetActiveProfileKey()
        and pending.untilTime > addon.Runtime.GetTimestamp()
        and entry and pending.appliedAt == entry.appliedAt and pending.sourceRoundID == entry.sourceRoundID then return true end
    for _, transfer in pairs(store.Transfers()) do
        local entry = transfer.entry
        if transfer.removed and same(transfer, current) and entry
            and entry.source == source and entry.spell.id == spellID then return true end
    end
    return false
end

function bridge.ReceiveDismiss(sender, payload)
    if isolated() or not addon.GameMasterService.IsPrimaryGameMaster() or type(payload) ~= "table"
        or not same(context(), payload) or type(payload.source) ~= "string" or #payload.source > 200
        or not store.ValidID(payload.spellID) then return end
    local session, player = addon.GameMasterService.GetActiveSession(), addon.Runtime.NormalizePlayerID(sender)
    if not session or not session.participants[player] then return end
    local matches = false
    for _, entry in ipairs(addon.GameMasterEffects.GetActiveBuffs(session, player)) do
        if entry.sourcePlayerKey == payload.source and entry.spell.id == payload.spellID
            and entry.sourceRoundID == payload.sourceRoundID and entry.appliedAt == payload.appliedAt then matches = true; break end
    end
    if not matches then return end
     
    if addon.GameMasterEffects.RemoveActiveBuff(session, player, payload.source, payload.spellID) then
        addon.GameMasterService.PublishTimedEffects()
    end
end

function bridge.Dismiss(source, spellID, entry)
    local current = context()
    if isolated() or not current or type(source) ~= "string" or not store.ValidID(spellID) or type(entry) ~= "table" then return false end
    local payload = { source = source, spellID = spellID, activationID = current.activationID, sessionID = current.sessionID,
        appliedAt = entry.appliedAt, sourceRoundID = entry.sourceRoundID }
    if addon.GameMasterService.IsPrimaryGameMaster() then bridge.ReceiveDismiss(me(), payload); return true end
    local remote = addon.GameMasterService.GetRemoteSession()
    if not remote or not addon.Communication.HasCapability(remote.gameMasterID, "aura-display-v1") then return false end
    if not send(remote.gameMasterID, "combat_dismiss", payload) then return false end
    payload.profile, payload.untilTime, payload.lastSent = addon.Database.GetActiveProfileKey(), addon.Runtime.GetTimestamp() + 15, addon.Runtime.GetTimestamp()
    dismissals[source .. "\031" .. spellID] = payload
    return true
end

function bridge.List()
    local current, result = context(), {}
    local active = addon.GameMasterService.GetActiveBuffsForPlayer
        and addon.GameMasterService.GetActiveBuffsForPlayer(me()) or nil
    for id, transfer in pairs(store.Transfers()) do
        local present = false
        for _, effect in ipairs(active or {}) do
            if transfer.origin and effect.sourceRoundID == transfer.origin then present = true; transfer.observed = true end
        end
        if type(transfer) == "table" and same(transfer, current) and not transfer.removed
            and (transfer.acknowledged or (not transfer.terminal and transfer.entry.expiresAt > addon.Runtime.GetTimestamp()))
            and (transfer.acknowledged or transfer.gameMaster == me()
                or addon.Communication.HasCapability(transfer.gameMaster, "timed-effects-v1"))
            and transfer.entry and (not transfer.observed or present)
            and (transfer.entry.spell.effects.durationRounds == 0
                or transfer.entry.spell.effects.durationRounds
                    and current.roundNumber < 1 + transfer.entry.spell.effects.durationRounds
                or transfer.entry.spell.effects.durationRounds == nil
                    and transfer.entry.expiresAt > addon.Runtime.GetTimestamp()) then
            local duration = transfer.entry.spell.effects.durationRounds
            result[#result + 1] = { id = id, source = transfer.entry.source, spell = transfer.entry.spell,
                combat = duration ~= nil, pending = not transfer.acknowledged,
                expiresAt = duration ~= nil and math.huge or transfer.entry.expiresAt, hidden = transfer.entry.hidden == true,
                expiresRound = duration and duration ~= 0 and 1 + duration or nil }
        end
    end
    return result
end

function bridge.IsSuspended(id)
    local transfer = store.Transfers()[id]
    return transfer ~= nil and same(transfer, context()) and transfer.acknowledged == true
end

function bridge.Sync()
    if busy or isolated() then return end
    local current = context()
    local transfers = store.Transfers()
    for id, transfer in pairs(transfers) do
        if not same(transfer, current) then
            store.RestoreTransferred(transfer)
            transfers[id], lastSent[id] = nil, nil
            store.TransferChanged()
        end
    end
    if not current then return end
    local gm = addon.GameMasterService.GetRemoteSession()
    local owner = gm and gm.gameMasterID or addon.GameMasterRoster.GetLocalPlayerID()
    if not owner then return end
    local timedEntries = store.List()
    local supported = addon.Runtime.NormalizePlayerID(owner) == me() or addon.Communication.HasCapability(owner, "timed-effects-v1")
    local supportsHidden = addon.Runtime.NormalizePlayerID(owner) == me()
        or addon.Communication.HasCapability(owner, "hidden-effects-v1")
    local unknownPeer = addon.Runtime.NormalizePlayerID(owner) ~= me()
        and addon.Communication.GetPeer and not addon.Communication.GetPeer(owner)
     
    if unknownPeer and (#timedEntries > 0 or next(transfers)) and addon.Communication.QueryPeer then
        addon.Communication.QueryPeer(owner)
    end
    for id in pairs(lastSent) do if not transfers[id] then lastSent[id] = nil end end
    if current.roundNumber == 1 then
        for _, entry in ipairs(timedEntries) do
            if not supported and not unknownPeer and warnedUnsupportedActivation ~= current.activationID then
                warnedUnsupportedActivation = current.activationID
                addon.Logger.Info(addon.L("TIMED_IMPORT_GM_REQUIRED"))
            end
            if entry.hidden and addon.Runtime.NormalizePlayerID(owner) ~= me()
                and supported and not unknownPeer
                and not addon.Communication.HasCapability(owner, "hidden-effects-v1")
                and warnedLegacyActivation ~= current.activationID then
                warnedLegacyActivation = current.activationID
                addon.Logger.Info(addon.L("TIMED_HIDDEN_GM_REQUIRED"))
            end
            if supported and not transfers[entry.id]
                and (not entry.hidden or addon.Runtime.NormalizePlayerID(owner) == me()
                    or addon.Communication.HasCapability(owner, "hidden-effects-v1")) then
                transfers[entry.id] = { entry = entry, gameMaster = addon.Runtime.NormalizePlayerID(owner),
                    activationID = current.activationID, sessionID = current.sessionID }
                store.TransferChanged()
            end
        end
    end
    busy = true
    local now = addon.Runtime.GetTimestamp()
    for identity, pending in pairs(dismissals) do
        if not same(pending, current) or pending.profile ~= addon.Database.GetActiveProfileKey() or now >= pending.untilTime then
            dismissals[identity] = nil
        elseif now - pending.lastSent >= 5 then
            pending.lastSent = now
            send(owner, "combat_dismiss", { source = pending.source, spellID = pending.spellID,
                activationID = pending.activationID, sessionID = pending.sessionID,
                appliedAt = pending.appliedAt, sourceRoundID = pending.sourceRoundID })
        end
    end
    local ordered = {}
    for id, transfer in pairs(transfers) do
        ordered[#ordered + 1] = { id = id, transfer = transfer }
    end
    table.sort(ordered, function(a, b)
        local first, second = a.transfer.nextAttempt or 0, b.transfer.nextAttempt or 0
        if first ~= second then return first < second end
        return a.id < b.id
    end)
    local localOwner = addon.Runtime.NormalizePlayerID(owner) == me()
    local budget = localOwner and 32 or (now >= nextBurst and 4 or 0)
    local activeTransfers = {}
    for _, entry in ipairs(bridge.List()) do activeTransfers[entry.id] = true end
    for _, item in ipairs(ordered) do
        local id, transfer = item.id, item.transfer
        if not transfer.acknowledged and not transfer.removed
            and (((not supported or (transfer.entry.hidden and not supportsHidden)) and not unknownPeer)
                or transfer.entry.expiresAt <= now) then terminate(transfer) end
        if type(transfer) ~= "table" or not same(transfer, current) then
            transfers[id] = nil
        elseif not transfer.acknowledged and not transfer.terminal and supported
            and (transfer.removed or not transfer.entry.hidden or supportsHidden)
            and budget > 0 and now >= (transfer.nextAttempt or 0) then
            budget = budget - 1; nextBurst = now + 1
            transfer.attempts = (transfer.attempts or 0) + 1
            transfer.nextAttempt = now + math.min(120, 10 * 2 ^ (transfer.attempts - 1))
            if transfer.attempts >= 6 then terminate(transfer) end
            lastSent[id] = now
            local payload = { id = id, activationID = current.activationID, sessionID = current.sessionID,
                entry = not transfer.removed and transfer.entry or nil,
                result = true,
                ownerProfile = addon.EffectVisibility and addon.EffectVisibility.Profile() or addon.Database.GetActiveProfileKey(),
                readers = not transfer.removed and transfer.entry.hidden and addon.EffectVisibility.Audience(id) or nil }
            if addon.Runtime.NormalizePlayerID(owner) == me() then bridge.Receive(owner, payload, transfer.removed)
            elseif addon.Communication.HasCapability(owner, "timed-effects-v1") then
                send(owner, transfer.removed and "combat_remove" or "combat_import", payload)
            end
        elseif transfer.acknowledged and activeTransfers[id] and not transfer.removed and transfer.entry.hidden
            and supportsHidden
            and transfer.readerCount ~= addon.Runtime.CountEntries(addon.EffectVisibility.Audience(id))
            and budget > 0 and (not lastSent[id] or now - lastSent[id] >= 10) then
            local payload = { id = id, activationID = current.activationID, sessionID = current.sessionID,
                ownerProfile = addon.EffectVisibility.Profile(), readers = addon.EffectVisibility.Audience(id) }
            local count = addon.Runtime.CountEntries(payload.readers)
            local retry = audienceRetries[transfer]
            if not retry or retry.count ~= count then retry = { count = count, attempts = 0, nextAt = 0 }; audienceRetries[transfer] = retry end
            if now >= retry.nextAt then
                retry.attempts = math.min(5, retry.attempts + 1)
                retry.nextAt = now + math.min(120, 10 * 2 ^ (retry.attempts - 1))
                lastSent[id] = now
                budget = budget - 1; nextBurst = now + 1
                if localOwner then bridge.ReceiveVisibility(owner, payload)
                else send(owner, "combat_visibility", payload) end
            end
        end
    end
    busy = false
end

function bridge.Initialize()
    if initialized then return end
    initialized = true
    addon.Communication.RegisterHandler("effect.combat_visibility", function(payload, sender)
        if addon.GameMasterRoster.IsMember(sender) then bridge.ReceiveVisibility(sender, payload) end
    end)
    addon.Communication.RegisterHandler("effect.combat_dismiss", function(payload, sender)
        if addon.GameMasterRoster.IsMember(sender) then bridge.ReceiveDismiss(sender, payload) end
    end)
    for _, kind in ipairs({ "combat_import", "combat_remove", "combat_ack" }) do
        addon.Communication.RegisterHandler("effect." .. kind, function(payload, sender)
            if not addon.GameMasterRoster.IsMember(sender) then return end
            if kind == "combat_ack" then bridge.Acknowledge(payload, sender)
            else bridge.Receive(sender, payload, kind == "combat_remove") end
        end)
    end
    addon.GameMasterService.RegisterListener(bridge.Sync)
    addon.TimedEffects.RegisterListener(bridge.Sync)
    if addon.Communication.RegisterPeerListener then
        addon.Communication.RegisterPeerListener(function(peer)
            local remote = addon.GameMasterService.GetRemoteSession()
            if remote and peer and addon.Runtime.NormalizePlayerID(peer.playerID)
                == addon.Runtime.NormalizePlayerID(remote.gameMasterID) then bridge.Sync() end
        end)
    end
end
