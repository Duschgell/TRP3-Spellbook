local _, addon = ...
addon.EffectSharing = {}
local sharing, privacy = addon.EffectSharing, addon.EffectVisibility
local initialized, replies = false, {}
local budgetAt, budgetUsed = 0, 0
local events = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
}
local function profile() return privacy.Profile() end
local function key(value) return addon.Runtime.NormalizePlayerID(value) end
local function now() return addon.Runtime.GetTimestamp() end
local function isolated() return addon.GameMasterService.IsTutorialActive() or addon.GameMasterService.IsTestMode() end

local function readable(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret ~= false then return false end
    end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible ~= true then return false end
    end
    return true
end

local function request(token, receipt)
    if not receipt or type(receipt.expiresAt) ~= "number" or receipt.expiresAt <= now()
        or (receipt.confirmed and not receipt.pendingView) then return false end
    local attempts, nextAttempt = receipt.retryCount, receipt.retryAt
    attempts = type(attempts) == "number" and attempts % 1 == 0 and attempts >= 0 and math.min(attempts, 12) or 0
    nextAttempt = type(nextAttempt) == "number" and nextAttempt == nextAttempt and math.min(nextAttempt, now() + 900) or 0
    receipt.retryCount, receipt.retryAt = attempts, nextAttempt
    if nextAttempt > now() or (not receipt.confirmed and attempts >= 12) then return false end
    if now() >= budgetAt then budgetAt, budgetUsed = now() + 5, 0 end
    if budgetUsed >= 2 then return false end
    budgetUsed = budgetUsed + 1
    receipt.retryCount = math.min(12, attempts + 1)
    receipt.retryAt = now() + math.min(receipt.confirmed and 300 or 900, 30 * 2 ^ attempts)
    if receipt.confirmed then addon.TimedEffects.RequestSnapshot(receipt.sender, true)
    else addon.Communication.Send(receipt.sender, "effect.reveal", { id = token, profile = profile() }) end
    return true
end

function sharing.Format(_, event, message, author, ...)
    if type(message) ~= "string" or not readable(message) then return false, message, author, ... end
    local function displayName(sender, token)
        local bridge = addon.TRP3Bridge
        local spell = bridge and bridge.GetOwnSpellChatTooltip and bridge.GetOwnSpellChatTooltip(sender, token)
        return spell and addon.ChatLinks.SanitizeDisplayName(spell.name) or addon.ChatLinks.DecodeNativeDisplayName(token)
    end
    local formatted = message:gsub("(|Haddon:totalrp3:([^:|]+):([^|]+)|h)(%[.-%])(|h)", function(start, sender, token, label, finish)
        local stem = token:match("^(.*):%d+$")
         
        if label ~= "[" .. tostring(stem) .. "]" and label ~= "[" .. token .. "]" then return start .. label .. finish end
        local name = displayName(sender, token)
        return name and start .. "[" .. name .. "]" .. finish or start .. label .. finish
    end)
     
     
    local sender = event == "CHAT_MSG_WHISPER_INFORM" and addon.GameMasterRoster.GetLocalPlayerID() or author
    if type(sender) == "string" and readable(sender) and #sender <= 200 and not sender:find("[%c|:]") then
        formatted = formatted:gsub("%[TRP3:([^%]%s]+)%]", function(token)
            local name = displayName(sender, token)
            if not name then return "[TRP3:" .. token .. "]" end
            return "|cffffff00|Haddon:totalrp3:" .. sender .. ":" .. token .. "|h[" .. name .. "]|h|r"
        end)
    end
    return false, formatted, author, ...
end

function sharing.Chat(event, message, author)
    if isolated() or type(message) ~= "string" or type(author) ~= "string"
        or not readable(message) or not readable(author) then return end
    local own = event == "CHAT_MSG_WHISPER_INFORM" or key(author) == key(addon.GameMasterRoster.GetLocalPlayerID())
    local scanned = 0
    local function received(token)
        scanned = scanned + 1
        if scanned > 16 then return end
        if own then privacy.MarkSent(token)
        elseif privacy.ReceiveChat(author, token) then request(token, privacy.Receipts()[token]) end
    end
    for token in message:gmatch("%[TRP3:([^%]%s]+)%]") do received(token) end
    for sender, token in message:gmatch("|Haddon:totalrp3:([^:|]+):([^|]+)|h") do
        if key(sender) == key(author) then received(token) end
    end
end

function sharing.Tick()
    if isolated() then return end
    privacy.Prune()
    for sender, deadline in pairs(replies) do if deadline <= now() then replies[sender] = nil end end
    local queue = {}
    for token, receipt in pairs(privacy.Receipts()) do
        if not receipt.confirmed or receipt.pendingView then queue[#queue + 1] = { token = token, receipt = receipt } end
    end
    table.sort(queue, function(a, b)
        local first, second = tonumber(a.receipt.retryAt) or 0, tonumber(b.receipt.retryAt) or 0
        if first ~= first then first = 0 end
        if second ~= second then second = 0 end
        if first ~= second then return first < second end
        return a.token < b.token
    end)
    for _, item in ipairs(queue) do
        request(item.token, item.receipt)
        if budgetUsed >= 2 and now() < budgetAt then break end
    end
end

function sharing.Initialize()
    if initialized then return end
    initialized = true
    addon.Communication.RegisterHandler("effect.reveal", function(payload, sender)
        if isolated() or type(payload) ~= "table" or not key(sender)
            or not addon.Runtime.IsSafeIdentifier(payload.id, 200)
            or not privacy.ReaderKey(sender, payload.profile) then return end
        local limit = key(sender) .. "\031" .. payload.id
        if (replies[limit] or 0) > now() then return end
        if addon.Runtime.CountEntries(replies) >= 256 then return end
        replies[limit] = now() + 5
         
        if privacy.Grant(payload.id, sender, payload.profile) then
            addon.Communication.Send(sender, "effect.revealed", { id = payload.id,
                profile = payload.profile, ownerProfile = profile() })
            if addon.TimedEncounterEffects then addon.TimedEncounterEffects.Sync() end
        end
    end)
    addon.Communication.RegisterHandler("effect.revealed", function(payload, sender)
        if isolated() or type(payload) ~= "table" or payload.profile ~= profile()
            or not addon.Runtime.IsSafeIdentifier(payload.ownerProfile, 200) then return end
        local receipt = privacy.Receipts()[payload.id]
        if not receipt or key(receipt.sender) ~= key(sender) then return end
        receipt.confirmed, receipt.pendingView, receipt.ownerProfile = true, true, payload.ownerProfile
        receipt.retryCount, receipt.retryAt = 0, now() + 30
        addon.TimedEffects.RequestSnapshot(sender, true)
    end)
    local frame = CreateFrame("Frame")
    for _, event in ipairs(events) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", function(_, event, message, author) sharing.Chat(event, message, author) end)
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        for _, event in ipairs(events) do ChatFrameUtil.AddMessageEventFilter(event, sharing.Format) end
    end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, sharing.Tick) end
end
