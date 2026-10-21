local _, addon = ...
addon.TimedEffects = {}
local service, store = addon.TimedEffects, addon.TimedEffectsStore
local pending, listeners, rates, requests, snapshots = {}, {}, {}, {}, {}
local initialized, timer, serial = false, nil, 0
local currentProfile, currentVisibilityProfile
local publicReplyAt, viewAt = 0, 0
local replyVersions = {}
local viewQueue, viewSerial = {}, 0
local notifiedRevision
local incomingRequests, replyRates = {}, {}

local function key(value) return addon.Runtime.NormalizePlayerID(value) end
local function me() return key(addon.GameMasterRoster.GetLocalPlayerID()) end
local function profile() return addon.Database.GetActiveProfileKey() end
local function visibilityProfile() return addon.EffectVisibility and addon.EffectVisibility.Profile() or profile() end
local function isolated()
    local gm = addon.GameMasterService
    return gm and (gm.IsTutorialActive() or gm.IsTestMode())
end
local function outside()
    return not isolated() and not addon.GameMasterService.IsSessionActive()
end
local function groupMember(sender)
    return key(sender) ~= me() and addon.GameMasterRoster.IsMember(sender)
end
local function token()
    serial = serial + 1
    return tostring(addon.Runtime.GetTimestamp()) .. ":" .. tostring(math.floor(addon.Runtime.GetMonotonicTime() * 1000)) .. ":" .. serial
end
local function send(target, kind, payload)
    return addon.Communication.Send(target, "effect." .. kind, payload)
end
local function changed()
    notifiedRevision = store.Revision()
    for _, callback in ipairs(listeners) do addon.Runtime.SafeInvoke(callback) end
end

local function colored(value, color)
    local text = type(value) == "string" and value or ""
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", ""):gsub("[%c]", " ")
    color = type(color) == "string" and color:gsub("^#", "")
    return color and color:match("^%x%x%x%x%x%x$") and ("|cff" .. color .. text .. "|r") or text
end

local recipientMessages = {
    TIMED_CAST_BLOCKED = true, TIMED_CAST_UNAVAILABLE = true, TIMED_CAST_UNANSWERED = true,
    TIMED_CAST_UNCONFIRMED = true, TIMED_CAST_CANCELLED = true,
}
local function requestMessage(request, messageKey)
    local name, color = request.target, nil
    local bridge = addon.TRP3Bridge
    if bridge and bridge.GetPlayerDisplayIdentity then
        name, color = bridge.GetPlayerDisplayIdentity(request.target)
    end
    local spellName = colored(request.spell.name, request.spell.nameColor)
    local recipient = colored(name or request.target, color)
    if recipientMessages[messageKey] then return addon.L(messageKey, recipient) end
    if messageKey == "TIMED_CAST_BUSY" then return addon.L(messageKey, spellName) end
    return addon.L(messageKey, spellName, recipient)
end

local function notifyRequest(request, messageKey)
    if request.profile == profile() then addon.Logger.Info(requestMessage(request, messageKey)) end
end

local function sendResult(target, id, accepted, reason, progress)
    return send(target, "result", { id = id, accepted = accepted, reason = reason, status = progress })
end

local function rejectRequest(sender, payload, reason)
    if payload.feedback ~= true then return end
    local now, senderKey = addon.Runtime.GetTimestamp(), key(sender)
    local rate = replyRates[senderKey]
    if not rate or rate.deadline <= now then rate = { deadline = now + 5, count = 0 }; replyRates[senderKey] = rate end
    if rate.count >= 8 then return end
    rate.count = rate.count + 1
    sendResult(sender, payload.id, false, reason)
end

local function prune()
    local now = addon.Runtime.GetTimestamp()
    if currentProfile ~= profile() or currentVisibilityProfile ~= visibilityProfile() then
        pending, requests, snapshots, replyVersions, viewQueue, incomingRequests, replyRates = {}, {}, {}, {}, {}, {}, {}
        currentProfile, currentVisibilityProfile = profile(), visibilityProfile()
        notifiedRevision = nil
    end
    for id, offer in pairs(pending) do
        if offer.deadline <= now or not groupMember(offer.sender) or not outside() then
            pending[id] = nil
            if offer.entry then notifiedRevision = nil end
        end
    end
    for id, request in pairs(requests) do
        if request.deadline <= now or (request.kind == "cast"
            and (not outside() or not groupMember(request.target))) then
            requests[id] = nil
            if request.kind == "cast" then
                local message = request.deadline <= now
                    and (request.delivered and "TIMED_CAST_UNANSWERED" or "TIMED_CAST_UNCONFIRMED")
                    or "TIMED_CAST_CANCELLED"
                notifyRequest(request, message)
            end
        end
    end
    for id, deadline in pairs(incomingRequests) do if deadline <= now then incomingRequests[id] = nil end end
    for sender, state in pairs(replyRates) do if state.deadline <= now then replyRates[sender] = nil end end
    for sender, expires in pairs(rates) do if expires <= now then rates[sender] = nil end end
    for sender, snapshot in pairs(snapshots) do
        if snapshot.deadline <= now then snapshots[sender] = nil; notifiedRevision = nil end
    end
    for sender, state in pairs(replyVersions) do if state.deadline <= now then replyVersions[sender] = nil end end
    for sender, state in pairs(viewQueue) do if state.deadline <= now then viewQueue[sender] = nil end end
end

function service.CanCast(spellID)
    return outside() and store.ValidateSpell(addon.Database.GetSpell(spellID)) ~= nil
end

function service.Cast(spellID, target, minutes, hidden)
    prune()
    minutes = tonumber(minutes)
    local spell = store.ValidateSpell(addon.Database.GetSpell(spellID))
    if not outside() or not spell or not minutes or minutes ~= math.floor(minutes)
        or minutes < 1 or minutes > 1440 or not key(target) then return false, addon.L("TIMED_INVALID") end
    spell.ownerKey = profile()
    if key(target) == me() then
        local accepted = store.Accept({ id = me() .. ":" .. token(), source = me(), spell = spell,
            expiresAt = addon.Runtime.GetTimestamp() + minutes * 60, hidden = hidden == true })
        if accepted then changed() end
        return accepted, addon.L(accepted and "TIMED_APPLIED" or "TIMED_FULL")
    end
    if not groupMember(target) then return false, addon.L("TIMED_GROUP_ONLY") end
    if not addon.Communication.HasCapability(target, hidden and "hidden-effects-v1" or "timed-effects-v1") then
        addon.Communication.QueryPeer(target)
        return false, addon.L("TIMED_PEER_REQUIRED")
    end
    local rateKey = "out:" .. key(target) .. "\031" .. spell.ownerKey .. "\031" .. spell.id
    if rates[rateKey] then return false, addon.L("TIMED_RATE") end
    local count, targetCount = 0, 0
    for _, request in pairs(requests) do
        if request.kind == "cast" then
            count = count + 1
            if request.target == key(target) then targetCount = targetCount + 1 end
        end
    end
    if count >= 32 or targetCount >= 8 then return false, addon.L("TIMED_RATE") end
    local id = token()
    local request = { target = key(target), profile = profile(), spell = spell,
        minutes = minutes, hidden = hidden == true, deadline = addon.Runtime.GetTimestamp() + 60, kind = "cast" }
    requests[id] = request
    rates[rateKey] = addon.Runtime.GetTimestamp() + 15
    local success = send(target, "request", { id = id, feedback = true })
    if not success then requests[id], rates[rateKey] = nil, nil end
    return success, requestMessage(request, success and "TIMED_CAST_SENT" or "TIMED_CAST_UNAVAILABLE")
end

function service.Offers()
    prune()
    local result = {}
    for _, offer in pairs(pending) do result[#result + 1] = offer end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function service.Decide(id, accept)
    prune()
    local offer = pending[id]
    if not offer or not offer.entry or not outside() or (accept and not store.AllowsOffers()) then return false end
    pending[id] = nil
    if accept then offer.entry.expiresAt = addon.Runtime.GetTimestamp() + offer.minutes * 60 end
    local accepted = accept and store.Accept(offer.entry) or false
    if not accepted then store.Remember(offer.entry.id, offer.entry.expiresAt) end
    sendResult(offer.sender, offer.requestID, accepted, accept and not accepted and "full" or nil)
    changed()
    return accepted or not accept
end

function service.SetAllowsOffers(allowed)
    if type(allowed) ~= "boolean" then return false end
    prune()
    store.SetAllowsOffers(allowed)
    if not allowed then
        for id, offer in pairs(pending) do
            if offer.feedback then sendResult(offer.sender, offer.requestID, false, "blocked") end
            pending[id] = nil
        end
    end
    changed()
    return true
end

function service.Remove(id)
    if isolated() then return false end
    local removed = store.Remove(id)
    if addon.TimedEncounterEffects and addon.TimedEncounterEffects.Remove(id) then removed = true end
    if removed then changed() end
    return removed
end

function service.RegisterListener(callback) listeners[#listeners + 1] = callback end

function service.GetSnapshot(target)
    if key(target) == me() then
        local entries, seen = {}, {}
        if addon.TimedEncounterEffects then
            for _, entry in ipairs(addon.TimedEncounterEffects.List()) do
                entries[#entries + 1], seen[entry.id] = entry, true
            end
        end
        for _, entry in ipairs(store.List()) do
            if not seen[entry.id] and not (addon.TimedEncounterEffects and addon.TimedEncounterEffects.IsSuspended
                and addon.TimedEncounterEffects.IsSuspended(entry.id)) then entries[#entries + 1] = entry end
        end
        return entries
    end
    prune()
    local snapshot = snapshots[key(target)]
    if snapshot then
        local known = addon.TRP3Bridge and addon.TRP3Bridge.GetPlayerProfileKey and addon.TRP3Bridge.GetPlayerProfileKey(target)
        if not snapshot.profile or not known or snapshot.profile == known then return snapshot.entries end
        return {}
    end
    return addon.EffectVisibility and addon.EffectVisibility.Cached(target) or {}
end

function service.RequestSnapshot(target, revealed)
    prune()
    local targetKey = key(target)
    if isolated() or not targetKey or targetKey == me() or rates["view:" .. targetKey] then return end
    if not revealed and not groupMember(target) and not addon.Communication.HasCapability(target, "aura-display-v1") then
        addon.Communication.QueryPeer(target)
        return
    end
    local queued = viewQueue[targetKey]
    if not queued and addon.Runtime.CountEntries(viewQueue) < 64 then
        viewSerial = viewSerial + 1
        queued = { target = target, order = viewSerial, deadline = addon.Runtime.GetTimestamp() + 120 }
        viewQueue[targetKey] = queued
    end
    if queued then queued.revealed = queued.revealed or revealed end
    local now = addon.Runtime.GetMonotonicTime()
    if now < viewAt then return end
    local first
    for candidate, state in pairs(viewQueue) do
        if not state.revealed and not groupMember(state.target)
            and not addon.Communication.HasCapability(state.target, "aura-display-v1") then viewQueue[candidate] = nil
        elseif not rates["view:" .. candidate] and (not first or state.order < first.order) then first = state end
    end
    if not first then return end
    target, revealed, targetKey = first.target, first.revealed, key(first.target)
    viewQueue[targetKey] = nil
    viewAt = now + 0.5
    local id = token()
    for previousID, request in pairs(requests) do
        if request.kind == "view" and request.target == key(target) then requests[previousID] = nil end
    end
    rates["view:" .. key(target)] = addon.Runtime.GetTimestamp() + 10
    local previous = snapshots[targetKey]
    local known = addon.TRP3Bridge and addon.TRP3Bridge.GetPlayerProfileKey and addon.TRP3Bridge.GetPlayerProfileKey(target)
    if previous and (not previous.profile or (known and known ~= previous.profile)) then previous = nil end
    requests[id] = { target = key(target), profile = profile(), kind = "view", deadline = addon.Runtime.GetTimestamp() + 30,
        atomic = revealed or addon.Communication.HasCapability(target, "aura-display-v1"), entries = {}, base = previous }
    send(target, "view", { id = id, profile = visibilityProfile(), conditional = true,
        revision = previous and previous.revision, ownerProfile = previous and previous.profile })
end

 
local function signature(value)
    if type(value) ~= "table" then
        local text = tostring(value)
        return type(value) .. #text .. ":" .. text
    end
    local keys, parts = {}, {}
    for field in pairs(value) do
        if field ~= "expiresAt" or not (value.combat or value.permanent) then keys[#keys + 1] = field end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, field in ipairs(keys) do parts[#parts + 1] = signature(field) .. signature(value[field]) end
    return "{" .. table.concat(parts) .. "}"
end

local handlers = {}
function handlers.request(sender, payload)
    if not outside() then rejectRequest(sender, payload, "unavailable"); return end
    if not store.AllowsOffers() then rejectRequest(sender, payload, "blocked"); return end
    local identity = key(sender) .. "\031" .. payload.id
    if incomingRequests[identity] then return end
    local count = 0
    for _ in pairs(pending) do count = count + 1 end
    if count >= 8 or addon.Runtime.CountEntries(incomingRequests) >= 128 then rejectRequest(sender, payload, "busy"); return end
    incomingRequests[identity] = addon.Runtime.GetTimestamp() + 120
    local nonce = token()
    pending[nonce] = { id = nonce, requestID = payload.id, sender = sender, profile = profile(),
        deadline = addon.Runtime.GetTimestamp() + 60, feedback = payload.feedback == true }
    send(sender, "ready", { id = payload.id, nonce = nonce })
end
function handlers.ready(sender, payload)
    local request = requests[payload.id]
    if not request or request.kind ~= "cast" or request.target ~= key(sender)
        or not store.ValidID(payload.nonce) or not outside() then return end
    local sent = send(sender, "offer", { id = payload.nonce, requestID = payload.id, spell = request.spell,
        minutes = request.minutes, hidden = request.hidden })
    if not sent then requests[payload.id] = nil; notifyRequest(request, "TIMED_CAST_UNAVAILABLE") end
end
function handlers.offer(sender, payload)
    local offer = pending[payload.id]
    local spell = store.ValidateSpell(payload.spell)
    local minutes = payload.minutes
    if not outside() or not store.AllowsOffers() or not offer or offer.entry or key(offer.sender) ~= key(sender)
        or offer.requestID ~= payload.requestID or offer.profile ~= profile() or not spell
        or (payload.hidden ~= nil and type(payload.hidden) ~= "boolean")
        or type(minutes) ~= "number" or minutes ~= math.floor(minutes) or minutes < 1 or minutes > 1440 then return end
    offer.entry = { id = key(sender) .. ":" .. payload.id, source = key(sender), spell = spell,
        expiresAt = addon.Runtime.GetTimestamp() + minutes * 60, hidden = payload.hidden == true }
    offer.minutes = minutes
    changed()
    if offer.feedback then sendResult(sender, offer.requestID, nil, nil, "received") end
    if addon.TimedEffectsView and addon.TimedEffectsView.NotifyOffer then
        addon.TimedEffectsView.NotifyOffer(offer)
    else
        addon.Logger.Info(addon.L("TIMED_OFFER", sender,
            addon.L(spell.effects.debuff and "TIMED_DEBUFF" or "TIMED_BUFF"),
            addon.ChatLinks and addon.ChatLinks.SanitizeDisplayName(spell.name) or spell.name, minutes))
    end
end
function handlers.result(sender, payload)
    local request = requests[payload.id]
    if not request or request.kind ~= "cast" or request.target ~= key(sender) then return end
    if payload.status == "received" and payload.accepted == nil and payload.reason == nil then
        if not request.delivered then
            request.delivered = true
            request.deadline = math.max(request.deadline, addon.Runtime.GetTimestamp() + 60)
            notifyRequest(request, "TIMED_CAST_DELIVERED")
        end
        return
    end
    if type(payload.accepted) ~= "boolean" or payload.status ~= nil then return end
    local messages = { blocked = "TIMED_CAST_BLOCKED", busy = "TIMED_CAST_BUSY", unavailable = "TIMED_CAST_UNAVAILABLE",
        full = "TIMED_CAST_FULL" }
    if payload.reason ~= nil and (payload.accepted or not messages[payload.reason]) then return end
    requests[payload.id] = nil
    notifyRequest(request, messages[payload.reason] or (payload.accepted and "TIMED_CAST_ACCEPTED" or "TIMED_CAST_DECLINED"))
    local template = request.spell.effects.whisperTemplate
    if payload.accepted and type(template) == "string" and template:match("%S")
        and addon.WhisperTemplates and addon.ChatFallbacks then
        local playerID = addon.GameMasterRoster.GetLocalPlayerID()
        local message = addon.WhisperTemplates.Build(request.spell, {
            playerID = playerID, targetID = sender, durationSeconds = request.minutes * 60,
        })
        if message then
            addon.ChatFallbacks.SendEffectWhisper(sender, message, "timed:" .. payload.id)
        end
    end
end
function handlers.view(sender, payload)
    if rates["reply:" .. key(sender)] then return end
    if not groupMember(sender) then
        local now = addon.Runtime.GetMonotonicTime()
        if now < publicReplyAt then return end
        publicReplyAt = now + 1
    end
    rates["reply:" .. key(sender)] = addon.Runtime.GetTimestamp() + 10
     
    local entries = addon.EffectDisplay and (addon.Communication.HasCapability(sender, "aura-display-v1")
        or addon.Runtime.IsSafeIdentifier(payload.profile, 200))
        and addon.EffectDisplay.PublicEntries(sender, payload.profile) or store.List()
    local visible = {}
    for _, entry in ipairs(entries) do
        if not entry.hidden or (addon.Communication.HasCapability(sender, "hidden-effects-v1")
            and addon.EffectVisibility and addon.EffectVisibility.CanSee(entry, sender, payload.profile)) then
            visible[#visible + 1] = entry
        end
    end
    entries = visible
    local version
    if payload.conditional == true and addon.Runtime.IsSafeIdentifier(payload.profile, 200) then
        local content = signature({ owner = visibilityProfile(), reader = payload.profile, entries = entries })
        version = replyVersions[key(sender)]
        if not version or version.content ~= content then
            version = { content = content, revision = token() }
        end
        version.deadline = addon.Runtime.GetTimestamp() + 60
        if replyVersions[key(sender)] or addon.Runtime.CountEntries(replyVersions) < 64 then replyVersions[key(sender)] = version end
        if payload.revision == version.revision and payload.ownerProfile == visibilityProfile() then
            send(sender, "snapshot", { id = payload.id, index = 0, unchanged = true,
                revision = version.revision, profile = visibilityProfile() })
            return
        end
    end
    send(sender, "snapshot", { id = payload.id, index = 0, total = #entries, profile = visibilityProfile(),
        revision = version and version.revision })
    for index, entry in ipairs(entries) do send(sender, "snapshot", { id = payload.id, entry = entry, index = index }) end
end
function handlers.snapshot(sender, payload)
    local request = requests[payload.id]
    local index = payload.index
    if not request or request.kind ~= "view" or request.target ~= key(sender)
        or request.profile ~= profile() or type(index) ~= "number" or index ~= math.floor(index) or index < 0 or index > 32 then return end
    local known = addon.TRP3Bridge and addon.TRP3Bridge.GetPlayerProfileKey and addon.TRP3Bridge.GetPlayerProfileKey(sender)
    if index == 0 and known and payload.profile ~= nil and payload.profile ~= known then return end
    if payload.unchanged == true then
        local base = request.base
        if index ~= 0 or not request.atomic or not base or snapshots[key(sender)] ~= base
            or base.deadline <= addon.Runtime.GetTimestamp() or not base.revision
            or payload.revision ~= base.revision or payload.profile ~= base.profile then return end
        base.deadline = addon.Runtime.GetTimestamp() + 30
        requests[payload.id] = nil
        return
    end
    local entry = index > 0 and store.ValidateEntry(payload.entry)
    if index > 0 and not entry then return end
    if index > 0 then
        entry.combat = payload.entry.combat == true
        entry.permanent = payload.entry.permanent == true
    end
    if request.atomic then
        if index == 0 then
            local total = payload.total
            if type(total) ~= "number" or total % 1 ~= 0 or total < 0 or total > 32 then return end
            request.total = total
            request.ownerProfile = addon.Runtime.IsSafeIdentifier(payload.profile, 200) and payload.profile or nil
            request.revision = store.ValidID(payload.revision) and payload.revision or nil
        else request.entries[index] = entry end
        if request.total == nil then return end
        local complete = {}
        for position = 1, request.total do
            if not request.entries[position] then return end
            if request.ownerProfile or not request.entries[position].hidden then complete[#complete + 1] = request.entries[position] end
        end
        if known and request.ownerProfile and request.ownerProfile ~= known then return end
        local previous = snapshots[key(sender)]
        local different = not previous or previous.profile ~= request.ownerProfile
            or signature(previous.entries) ~= signature(complete)
        snapshots[key(sender)] = { id = payload.id, entries = complete, profile = request.ownerProfile,
            revision = request.revision, deadline = addon.Runtime.GetTimestamp() + 30 }
        if addon.EffectVisibility then
            addon.EffectVisibility.Remember(sender, request.ownerProfile, complete)
        end
        requests[payload.id] = nil
        if different then changed() end
        return
    end
    local snapshot = snapshots[key(sender)]
    if not snapshot or snapshot.id ~= payload.id then
        if addon.EffectVisibility then addon.EffectVisibility.Remember(sender, nil, {}) end
        snapshot = { id = payload.id, entries = {}, deadline = addon.Runtime.GetTimestamp() + 30 }
        snapshots[key(sender)] = snapshot
    end
    if index > 0 and not entry.hidden then
        snapshot.entries[index] = entry
    end
    changed()
end

function service.Initialize()
    if initialized then return end
    initialized, currentProfile, currentVisibilityProfile = true, profile(), visibilityProfile()
    for kind, callback in pairs(handlers) do
        addon.Communication.RegisterHandler("effect." .. kind, function(payload, sender)
            prune()
            local displayRequest = kind == "view" or kind == "snapshot"
            if isolated() or not key(sender) or (not displayRequest and not groupMember(sender))
                or type(payload) ~= "table" or not store.ValidID(payload.id) then return end
            callback(sender, payload)
        end)
    end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function() prune(); changed() end)
    local api = _G.TRP3_API
    if api and api.RegisterCallback and _G.TRP3_Addon then
        api.RegisterCallback(_G.TRP3_Addon, "REGISTER_PROFILES_LOADED", function() prune(); changed() end)
    end
    notifiedRevision = store.Revision()
     
    if C_Timer and C_Timer.NewTicker then
        timer = C_Timer.NewTicker(5, function()
            prune()
            if addon.TimedEncounterEffects then addon.TimedEncounterEffects.Sync() end
            if notifiedRevision ~= store.Revision() then changed() end
        end)
    end
end
